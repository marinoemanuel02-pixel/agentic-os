"""Render Blender shots headless: the same scene scripts the Blender MCP runs during look-dev.

Usage: python tools/render-shot.py S02 S11 ...  [--scale 50] [--frames N]  (or "all")
Reads blender/shots.json ({shot: {script, shot, offset?}}) and src/data/edit.json (frames per shot), runs
`blender -b --python-expr` with SHOT set, renders frames offset+1 .. offset+frames+HANDLE to an H.264 MP4 in
<media>/app/public/clips/<shot>.mp4, and records it in src/data/media.json. Logs seconds per frame to
<media>/renders/render-log.jsonl so render budgets are measured, not guessed (R32).
"""
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
    for sid in ids:
        spec = table[sid]
        n = force_frames or edit[sid]["frames"] + HANDLE
        start = 1 + spec.get("offset", 0)
        out = clips / f"{sid}.mp4"
        expr = EXPR.format(lib=str(ROOT / "blender" / "lib.py"), shot=spec["shot"], script=str(ROOT / "blender" / spec["script"]), scale=scale, preroll=spec.get("preroll", 0),
                           start=start, end=start + n - 1, out=str(out))
        t = time.time()
        p = subprocess.run([BLENDER, "-b", "--factory-startup", "--python-expr", expr], capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
        secs = time.time() - t
        if p.returncode != 0 or not out.exists():
            print(p.stdout[-3000:], p.stderr[-3000:])
            sys.exit(f"{sid}: render failed")
        with open(MEDIA / "renders" / "render-log.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"shot": sid, "frames": n, "scale": scale, "seconds": round(secs, 1),
                                "s_per_frame": round(secs / n, 2), "at": time.strftime("%Y-%m-%dT%H:%M:%S")}) + "\n")
        media = json.loads(media_path.read_text(encoding="utf-8")) if media_path.exists() else {}
        media[sid] = {"clip": f"clips/{sid}.mp4", "startFrom": 0, "push": spec.get("push", False)}
        media_path.write_text(json.dumps(media, indent=1) + "\n", encoding="utf-8")
        print(f"{sid}: {n} frames in {secs:.0f} s ({secs / n:.2f} s/frame) -> {out}")


if __name__ == "__main__":
    main()
