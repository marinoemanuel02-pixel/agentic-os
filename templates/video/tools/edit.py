"""Frame-exact edit for a short: places every narration line, then cuts each shot on the word its picture names.

Shorts cut on words, not on a 0.6 s music grid, so this replaces plan.ts's beat slots for this film. Input:
src/data/vo.json (measured line lengths), src/data/words.json (Whisper word times per line), src/data/cuts.json.
Output: src/data/edit.json  {fps, total, lines: [{id, file, from, frames}], shots: [{id, from, frames, line, word}]}.
A cut lands LEAD frames before its word starts, so the picture shows the idea just before the word names it (R19).
Run: python tools/edit.py   (fails loudly when an anchor word is missing from a line)
"""
import json
import math
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
FPS = 30
HEAD = 6  # frames before the first word: the hook starts at once
LEAD = 4  # a cut leads its word by this many frames
GAP = 5  # default air between lines
OUTRO = 75  # frames held after the last line (title)
# Per-film tables live in src/data/cuts.json:
#   {"pause": {"L02": 6}, "cuts": [["S01", "L01", null], ["S02", "L02", "They"], ..., ["S40", null, "outro"]]}
# shot, line, anchor word (case-insensitive prefix; "word#n" picks the n-th match), null = the line's start.
TABLES = json.loads((ROOT / "src/data/cuts.json").read_text(encoding="utf-8"))
PAUSE = TABLES.get("pause", {})
CUTS = [tuple(c) for c in TABLES["cuts"]]


def norm(w: str) -> str:
    return "".join(ch for ch in w.lower() if ch.isalnum() or ch == "'")


def main() -> None:
    vo = {v["id"]: v for v in json.loads((ROOT / "src/data/vo.json").read_text(encoding="utf-8"))}
    words = json.loads((ROOT / "src/data/words.json").read_text(encoding="utf-8"))
    order = [l["id"] for l in json.loads((ROOT / "src/data/lines.json").read_text(encoding="utf-8"))]
    lines, t = [], HEAD
    for lid in order:
        n = math.ceil(vo[lid]["seconds"] * FPS)
        lines.append({"id": lid, "file": vo[lid]["file"], "from": t, "frames": n})
        t += n + GAP + PAUSE.get(lid, 0)
    end_of_speech = lines[-1]["from"] + lines[-1]["frames"]
    total = end_of_speech + OUTRO
    start_of = {l["id"]: l["from"] for l in lines}

    cuts = []
    for sid, lid, anchor in CUTS:
        if lid is None:
            cuts.append((sid, None, "outro", end_of_speech + 8))
            continue
        if anchor is None:
            f = start_of[lid] - LEAD if cuts else 0
            cuts.append((sid, lid, None, max(0, f)))
            continue
        name, _, nth = anchor.partition("#")
        hits = [w for w in words[lid] if norm(w[0]).startswith(norm(name))]
        k = int(nth) - 1 if nth else (len(hits) - 1 if name.lower() == "ai" else 0)
        if not hits or k >= len(hits):
            sys.exit(f"{sid}: anchor '{anchor}' not found in {lid}: {[w[0] for w in words[lid]]}")
        cuts.append((sid, lid, anchor, start_of[lid] + round(hits[k][1] * FPS) - LEAD))

    shots = []
    for i, (sid, lid, anchor, f) in enumerate(cuts):
        nxt = cuts[i + 1][3] if i + 1 < len(cuts) else total
        if nxt <= f:
            sys.exit(f"{sid} has no frames ({f} -> {nxt})")
        shots.append({"id": sid, "from": f, "frames": nxt - f, "line": lid, "word": anchor})
    out = {"fps": FPS, "total": total, "lines": lines, "shots": shots}
    (ROOT / "src/data/edit.json").write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    lens = [s["frames"] / FPS for s in shots]
    print(f"total {total / FPS:.1f} s, {len(shots)} shots, mean {sum(lens) / len(lens):.2f} s, "
          f"min {min(lens):.2f} s ({shots[lens.index(min(lens))]['id']}), max {max(lens):.2f} s ({shots[lens.index(max(lens))]['id']})")


if __name__ == "__main__":
    main()
