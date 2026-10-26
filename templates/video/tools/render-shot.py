"""Render Blender shots headless: the same scene scripts the Blender MCP runs during look-dev.

Usage: python tools/render-shot.py S02 S11 ...  [--scale 50] [--frames N]  (or "all")
Reads blender/shots.json ({shot: {script, shot, offset?}}) and src/data/edit.json (frames per shot), runs
`blender -b --python-expr` with SHOT set, renders frames offset+1 .. offset+frames+HANDLE to an H.264 MP4 in
<media>/app/public/clips/<shot>.mp4, and records it in src/data/media.json. Logs seconds per frame to
<media>/renders/render-log.jsonl so render budgets are measured, not guessed (R32).
"""
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

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
    force_frames = None
    if "--scale" in args:
        i = args.index("--scale"); scale = int(args[i + 1]); del args[i:i + 2]
    if "--frames" in args:
        i = args.index("--frames"); force_frames = int(args[i + 1]); del args[i:i + 2]
    table = json.loads((ROOT / "blender/shots.json").read_text(encoding="utf-8"))
    edit = {s["id"]: s for s in json.loads((ROOT / "src/data/edit.json").read_text(encoding="utf-8"))["shots"]}
    ids = list(table) if args == ["all"] else args
    clips = MEDIA / "app" / "public" / "clips"
    clips.mkdir(parents=True, exist_ok=True)
    (MEDIA / "renders").mkdir(parents=True, exist_ok=True)
    media_path = ROOT / "src/data/media.json"
    state_path = MEDIA / "renders" / "render-state.json"
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
    bad = []
    for sid in ids:
        spec = table[sid]
        if sid not in edit:
            print(f"{sid}: not in the current edit, skipped")
            continue
        n = force_frames or edit[sid]["frames"] + HANDLE
        start = 1 + spec.get("offset", 0)
        out = clips / f"{sid}.mp4"
        partial = clips / f"{sid}.partial.mp4"  # an interrupted render never overwrites a good clip
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


def gate(sid: str, clip: Path, n: int, bad: list) -> float:
    """Exposure gate (R50): mean luma of the clip's middle frame must lie within LUMA_MIN..LUMA_MAX."""
    luma, _ = exposure(clip, n, MEDIA / "renders" / "mid" / f"{sid}.png")
    if not LUMA_MIN <= luma <= LUMA_MAX:
        bad.append(sid)
        print(f"{sid}: EXPOSURE FAIL, mid-frame 90th-percentile luma {luma:.0f} (want {LUMA_MIN}-{LUMA_MAX})")
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
