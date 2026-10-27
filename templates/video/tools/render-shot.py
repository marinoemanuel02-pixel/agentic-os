"""Render Blender and engine shots headless: the same scene scripts the MCPs run during look-dev.

Usage: python tools/render-shot.py S02 S11 ...  [--scale 50] [--frames N] [--repeat K] [--force]  (or "all")
Reads blender/shots.json ({shot: {script, shot, offset?}}) and src/data/edit.json (frames per shot), runs
`blender -b --python-expr` with SHOT set, renders frames offset+1 .. offset+frames+HANDLE to an H.264 MP4 in
<media>/app/public/clips/<shot>.mp4, and records it in src/data/media.json. Logs seconds per frame to
<media>/renders/render-log.jsonl so render budgets are measured, not guessed (R32).
Engine shots (engines/shots.json: Godot, Manim, Unreal, Unity, cmd, import; see tools/engines.py and R55-R57) go
through the same clip, log, state and exposure gate. Without edit.json a shot takes "frames" from its table entry.
--repeat K renders an engine shot's first K frames twice and records whether the rerun is pixel-identical (R57).
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import engines

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
MEDIA = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos" / "video" / ROOT.name))
BLENDER = os.environ.get("BLENDER_PATH", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
HANDLE = 6  # extra frames so a cut can slip by a few frames without a re-render
LUMA_MIN, LUMA_MAX = 40, 225  # 90th-percentile Y of the mid frame (TV range: black is 16); v1 shipped near-black shots


def exposure(clip: Path, n: int, png: Path) -> tuple[float, Path]:
    """Mean luma of the clip's middle frame (ffmpeg signalstats); the PNG is kept for the contact sheet."""
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(clip), "-vf", rf"select=eq(n\,{n // 2})",
                    "-vframes", "1", str(png)], check=True)
    r = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-i", str(png), "-vf", "signalstats,metadata=print:key=lavfi.signalstats.YHIGH",
                        "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    vals = [float(l.split("=")[-1]) for l in r.stderr.splitlines() if "YHIGH" in l]
    return (vals[-1] if vals else -1.0), png

EXPR = r"""
import bpy, json, sys, time
SHOT = {shot!r}
BLENDER_LIB = {lib!r}
exec(open({script!r}, encoding="utf-8").read())
sc = bpy.context.scene
sc.render.resolution_percentage = {scale}
for _f in range({start} - {preroll}, {start}):
    sc.frame_set(_f)  # particle pre-roll: rain, embers and paper are in the air on the first frame
sc.frame_start = {start}
sc.frame_end = {end}
r = sc.render
r.image_settings.media_type = "VIDEO"
r.image_settings.file_format = "FFMPEG"
r.ffmpeg.format = "MPEG4"
r.ffmpeg.codec = "H264"
r.ffmpeg.constant_rate_factor = "HIGH"
r.ffmpeg.ffmpeg_preset = "GOOD"
r.ffmpeg.audio_codec = "NONE"
r.filepath = {out!r}
t = time.time()
bpy.ops.render.render(animation=True)
print("RENDER_SECONDS", time.time() - t)
"""


def main() -> None:
    args = sys.argv[1:]
    scale = 75  # 810x1440, upscaled in Remotion under the grain; ~3 s per frame
    engine_scale = 100  # real-time engines are cheap per frame: full size unless --scale says otherwise
    force_frames = None
    repeat_k = 0
    args = [a for a in args if a != "--force"]
    if "--scale" in args:
        i = args.index("--scale"); scale = engine_scale = int(args[i + 1]); del args[i:i + 2]
    if "--frames" in args:
        i = args.index("--frames"); force_frames = int(args[i + 1]); del args[i:i + 2]
    if "--repeat" in args:
        i = args.index("--repeat"); repeat_k = int(args[i + 1]); del args[i:i + 2]
        if repeat_k < 1:
            sys.exit(f"--repeat needs a positive frame count, got {repeat_k}")
    table = engines.load_table(ROOT)
    edit_path = ROOT / "src/data/edit.json"
    edit = {s["id"]: s for s in json.loads(edit_path.read_text(encoding="utf-8"))["shots"]} if edit_path.exists() else None
    ids = list(table) if args == ["all"] else args
    clips = MEDIA / "app" / "public" / "clips"
    clips.mkdir(parents=True, exist_ok=True)
    (MEDIA / "renders").mkdir(parents=True, exist_ok=True)
    media_path = ROOT / "src/data/media.json"
    state_path = MEDIA / "renders" / "render-state.json"
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
    bad = []
    for sid in ids:
        if sid not in table:
            sys.exit(f"{sid}: not in blender/shots.json or engines/shots.json")
        engine, spec = table[sid]
        if edit is not None and sid not in edit:
            print(f"{sid}: not in the current edit, skipped")
            continue
        if edit is None and not force_frames and "frames" not in spec:
            sys.exit(f"{sid}: no src/data/edit.json and no \"frames\" in its table entry")
        n = force_frames or (edit[sid]["frames"] if edit is not None else spec["frames"]) + HANDLE
        start = 1 + spec.get("offset", 0)
        out = clips / f"{sid}.mp4"
        partial = clips / f"{sid}.partial.mp4"  # an interrupted render never overwrites a good clip
        if engine != "blender":
            render_engine(sid, engine, spec, n, engine_scale, repeat_k, out, partial, media_path, state, state_path, bad)
            continue
        # incremental: a shot re-renders only when its scene script, lib.py, table entry or scale changed, or when the
        # edit now needs more frames than the clip has (a longer clip is fine: the composition plays only what it needs)
        key = hashlib.sha256(json.dumps([spec, scale, (ROOT / "blender" / spec["script"]).read_text(encoding="utf-8"),
                                         (ROOT / "blender" / "lib.py").read_text(encoding="utf-8")]).encode()).hexdigest()
        have = state.get(sid) if isinstance(state.get(sid), dict) else {}
        if "--force" not in sys.argv and have.get("key") == key and have.get("frames", 0) >= n and out.exists():
            print(f"{sid}: unchanged ({have['frames']} frames, need {n}), skipped")
            continue
        expr = EXPR.format(lib=str(ROOT / "blender" / "lib.py"), shot=spec["shot"], script=str(ROOT / "blender" / spec["script"]), scale=scale, preroll=spec.get("preroll", 0),
                           start=start, end=start + n - 1, out=str(partial))
        t = time.time()
        p = subprocess.run([BLENDER, "-b", "--factory-startup", "--python-expr", expr], capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
        secs = time.time() - t
        if p.returncode != 0 or not partial.exists():
            print(p.stdout[-3000:], p.stderr[-3000:])
            sys.exit(f"{sid}: render failed")
        os.replace(partial, out)
        with open(MEDIA / "renders" / "render-log.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"shot": sid, "frames": n, "scale": scale, "seconds": round(secs, 1),
                                "s_per_frame": round(secs / n, 2), "at": time.strftime("%Y-%m-%dT%H:%M:%S")}) + "\n")
        media = json.loads(media_path.read_text(encoding="utf-8")) if media_path.exists() else {}
        # keep hand-set fields (tag, gain) and replace only what the render owns
        media[sid] = {**media.get(sid, {}), "clip": f"clips/{sid}.mp4", "startFrom": 0, "push": spec.get("push", False)}
        media_path.write_text(json.dumps(media, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        state[sid] = {"key": key, "frames": n}
        state_path.write_text(json.dumps(state, indent=1) + "\n", encoding="utf-8")
        luma = gate(sid, out, n, bad)
        print(f"{sid}: {n} frames in {secs:.0f} s ({secs / n:.2f} s/frame), mid luma {luma:.0f} -> {out}")
    if bad:
        sys.exit(f"exposure gate failed: {' '.join(bad)} (mid frames in renders/mid/)")


def render_engine(sid, engine, spec, n, scale, repeat_k, out, partial, media_path, state, state_path, bad) -> None:
    """One engine shot: frames from the engine (preroll dropped), one clip, the same log, media row, state and gate."""
    conf = engines.settings(ROOT)
    size, fps = engines.scaled(conf["size"], scale), conf["fps"]
    lo, hi = spec.get("luma", [LUMA_MIN, LUMA_MAX])
    if "luma" in spec and not str(spec.get("luma_why", "")).strip():
        # a dark graphic shot (thin notation on a near-black look) may move the R50 gate, never silently
        sys.exit(f"{sid}: \"luma\" moves the exposure gate and needs \"luma_why\" saying why this shot is darker or brighter")
    if engine != "import" and (ROOT / "tools/export-look.mts").exists() and (ROOT / "src/lib/look.ts").exists():
        # engines read engines/look.json; a look changed in look.ts must reach them before they render (R56)
        p = subprocess.run(["node", "--no-warnings", str(ROOT / "tools/export-look.mts"), "--check"], capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
        if p.returncode != 0:
            sys.exit(f"{sid}: {p.stderr.strip() or p.stdout.strip()}")
    preroll = spec.get("preroll", 0)
    work = MEDIA / "renders" / "frames" / sid
    key = engines.render_key(ROOT, engine, spec, size, fps)
    have = state.get(sid) if isinstance(state.get(sid), dict) else {}
    media = json.loads(media_path.read_text(encoding="utf-8")) if media_path.exists() else {}
    if "--force" not in sys.argv and have.get("key") == key and have.get("frames", 0) >= n and out.exists():
        print(f"{sid}: unchanged ({have['frames']} frames, need {n}), skipped")
        if media.get(sid, {}).get("clip") != f"clips/{sid}.mp4":  # a lost or edited row is restored on a hit
            media[sid] = {**media.get(sid, {}), "clip": f"clips/{sid}.mp4", "startFrom": 0, "push": spec.get("push", False),
                          "engine": engine}
    else:
        t = time.time()
        try:
            if engine == "import":
                engines.import_clip(ROOT, spec, partial, preroll, n, fps, size)
            else:
                frames = engines.run_frames(ROOT, engine, spec, work / "final", preroll + n, size, fps, work / "final.log")
                engines.encode(frames[preroll:], partial, fps, spec.get("color", "linear") == "linear")
                shutil.rmtree(work / "final", ignore_errors=True)  # 1080p frames run to hundreds of MB; the clip and log stay
        except (engines.RenderError, subprocess.CalledProcessError) as e:
            partial.unlink(missing_ok=True)
            sys.exit(f"{sid}: render failed: {e}")
        secs = time.time() - t
        os.replace(partial, out)
        with open(MEDIA / "renders" / "render-log.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"shot": sid, "engine": engine, "frames": n, "scale": scale, "seconds": round(secs, 1),
                                "s_per_frame": round(secs / n, 2), "at": time.strftime("%Y-%m-%dT%H:%M:%S")}) + "\n")
        media[sid] = {**media.get(sid, {}), "clip": f"clips/{sid}.mp4", "startFrom": 0, "push": spec.get("push", False),
                      "engine": engine}
        state[sid] = {"key": key, "frames": n}
        print(f"{sid}: {engine}, {n} frames in {secs:.0f} s ({secs / n:.2f} s/frame) -> {out}")
    if repeat_k and engine != "import":
        try:
            result = engines.repeat(ROOT, engine, spec, work, repeat_k, preroll, size, fps)
        except engines.RenderError as e:
            sys.exit(f"{sid}: repeat render failed: {e}")
        media[sid] = {**media.get(sid, {}), "determinism": {**result, "key": key}}
        print(f"{sid}: rerun of {repeat_k} frames is {result['level']} ({result['differ']} differ)")
    if "luma" in spec and sid in media:
        media[sid]["luma"] = {"range": [lo, hi], "why": spec["luma_why"]}
    if sid in media:
        media_path.write_text(json.dumps(media, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    state_path.write_text(json.dumps(state, indent=1) + "\n", encoding="utf-8")
    if out.exists():
        luma = gate(sid, out, n, bad, lo, hi)
        print(f"{sid}: mid luma {luma:.0f}")


def gate(sid: str, clip: Path, n: int, bad: list, lo: float = LUMA_MIN, hi: float = LUMA_MAX) -> float:
    """Exposure gate (R50): mean luma of the clip's middle frame must lie within LUMA_MIN..LUMA_MAX (or the range an
    engine shot sets with a written "luma_why")."""
    luma, _ = exposure(clip, n, MEDIA / "renders" / "mid" / f"{sid}.png")
    if not lo <= luma <= hi:
        bad.append(sid)
        print(f"{sid}: EXPOSURE FAIL, mid-frame 90th-percentile luma {luma:.0f} (want {lo}-{hi})")
    return luma


def check_only(ids: list) -> None:
    """--check: gate clips that already exist (any source: Blender, footage, detection) without rendering."""
    clips = MEDIA / "app" / "public" / "clips"
    bad = []
    for sid in ids:
        clip = clips / f"{sid}.mp4"
        if not clip.exists():
            continue
        r = subprocess.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries",
                            "stream=nb_read_packets", "-of", "csv=p=0", str(clip)], capture_output=True, text=True)
        n = int(r.stdout.strip() or 2)
        print(f"{sid}: mid luma {gate(sid, clip, n, bad):.0f}")
    if bad:
        sys.exit(f"exposure gate failed: {' '.join(bad)}")


if __name__ == "__main__":
    if "--check" in sys.argv:
        rest = [a for a in sys.argv[1:] if a != "--check"]
        check_only(rest or sorted(p.stem for p in (MEDIA / "app" / "public" / "clips").glob("S*.mp4")))
    else:
        main()
