"""Review sheets for a word-cut short (src/data/edit.json): every shot at 20, 50 and 85 % of its slot, three frames
per row with the shot and line id, eight shots per sheet. tools/review-sheets.mts samples the beat plan (plan.ts),
which a word-cut film does not use. Frames cannot show playback, pacing or sound (R14).
Usage: python tools/edit-sheets.py <video.mp4> <out_dir>   -> <out_dir>/sheet-01.jpg ...
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
video, out = sys.argv[1], Path(sys.argv[2])
(out / "f").mkdir(parents=True, exist_ok=True)
edit = json.loads((ROOT / "src/data/edit.json").read_text(encoding="utf-8"))
fps = edit["fps"]
line_at = lambda f: next((l["id"] for l in edit["lines"] if l["from"] <= f < l["from"] + l["frames"]), "-")
rows = []
for s in edit["shots"]:
    files = []
    for k in (0.2, 0.5, 0.85):
        f = s["from"] + int(s["frames"] * k)
        png = out / "f" / f"{s['id']}-{int(k * 100)}.png"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", f"{f / fps:.3f}", "-i", video, "-frames:v", "1",
                        "-vf", "scale=300:-1", str(png)], check=True)
        files.append(str(png))
    rows.append((f"{s['id']} {line_at(s['from'] + s['frames'] // 2)}", files))
for i in range(0, len(rows), 8):
    args = []
    for label, files in rows[i:i + 8]:
        for j, f in enumerate(files):
            args += ["-label", label if j == 0 else "", f]
    sheet = out / f"sheet-{i // 8 + 1:02d}.jpg"
    subprocess.run(["magick", "montage", *args, "-tile", "3x", "-geometry", "+3+3", "-background", "#1a1a1a",
                    "-fill", "white", "-pointsize", "18", str(sheet)], check=True)
    print(sheet)
