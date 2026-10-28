"""Sidecar SRT from the measured words: one cue per phrase (breaks at punctuation, <= 42 characters).

Times come from src/data/edit.json (line starts) plus src/data/words.json (word times within each line), so the
subtitles match the burned-in captions. Usage: python tools/srt.py <out.srt>
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
edit = json.loads((ROOT / "src/data/edit.json").read_text(encoding="utf-8"))
words = json.loads((ROOT / "src/data/words.json").read_text(encoding="utf-8"))
captions = {l["id"]: l["caption"] for l in json.loads((ROOT / "src/data/lines.json").read_text(encoding="utf-8"))}
FPS = edit["fps"]


def stamp(s: float) -> str:
    ms = int(round(s * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


cues = []
for line in edit["lines"]:
    t0 = line["from"] / FPS
    ws = words[line["id"]]
    # caption tokens carry the on-screen spelling; spoken word times carry the timing (counts may differ: digits)
    toks = captions[line["id"]].split()
    n = len(ws)
    phrase, start = [], None
    for k, tok in enumerate(toks):
        wi = min(n - 1, round(k * (n - 1) / max(1, len(toks) - 1))) if n else 0
        if start is None:
            start = t0 + ws[wi][1]
        phrase.append(tok)
        end = t0 + ws[wi][2]
        if tok[-1] in ".,?!:" or len(" ".join(phrase)) > 34 or k == len(toks) - 1:
            cues.append((start, end, " ".join(phrase)))
            phrase, start = [], None

out = ["" for _ in range(0)]
for i, (a, b, text) in enumerate(cues, 1):
    b = max(b, a + 0.4)
    if i < len(cues):
        b = min(b, cues[i][0] - 0.01)
    out.append(f"{i}\n{stamp(a)} --> {stamp(b)}\n{text}\n")
Path(sys.argv[1]).write_text("\n".join(out), encoding="utf-8")
print(f"{sys.argv[1]}: {len(cues)} cues")
