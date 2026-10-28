"""Fetch CC0 assets from Poly Haven (models, HDRIs, textures) into the film's media root and log them.

Every download is appended to research/assets.md (id, type, resolution, bytes, licence, URL) and counted against
the film's download budget (BUDGET_MB in qa.env, default 500). Already-downloaded files are skipped.

Usage:
  python tools/polyhaven.py model security_camera_01 [2k]   -> <media>/assets/polyhaven/security_camera_01/*.blend + textures
  python tools/polyhaven.py hdri  dikhololo_night [2k]      -> <media>/assets/polyhaven/hdri/dikhololo_night_2k.exr
  python tools/polyhaven.py tex   concrete_wall_008 [2k]    -> <media>/assets/polyhaven/concrete_wall_008/*.blend + maps
  python tools/polyhaven.py budget                           -> bytes used so far
Prints the local path of the .blend / .exr on the last line.
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
MEDIA = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos" / "video" / ROOT.name))
DEST = MEDIA / "assets" / "polyhaven"
LOG = ROOT / "research" / "assets.md"
UA = {"User-Agent": "agentic-os-video/1.0"}


def budget_mb() -> float:
    env = ROOT / "qa.env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.startswith("BUDGET_MB="):
                return float(line.split("=", 1)[1])
    return 500.0


def used_bytes() -> int:
    if not LOG.exists():
        return 0
    total = 0
    for line in LOG.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 5 and cells[4].isdigit():
            total += int(cells[4])
    return total


def get_json(url: str):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url: str, target: Path) -> int:
    if target.exists() and target.stat().st_size > 0:
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".part")
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    tmp.replace(target)
    return target.stat().st_size


def log(asset_id: str, kind: str, res: str, size: int, url: str) -> None:
    if not LOG.exists():
        LOG.parent.mkdir(parents=True, exist_ok=True)
        LOG.write_text(
            "# Imported assets (download budget ledger)\n\n"
            "| asset | kind | res | bytes | licence | source |\n|---|---|---|---|---|---|\n",
            encoding="utf-8",
        )
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"| {asset_id} | {kind} | {res} | {size} | CC0 (Poly Haven) | {url} |\n")


def fetch(kind: str, asset_id: str, res: str) -> Path:
    files = get_json(f"https://api.polyhaven.com/files/{asset_id}")
    if kind == "hdri":
        entry = files["hdri"][res]["exr"]
        planned = entry["size"]
        target = DEST / "hdri" / f"{asset_id}_{res}.exr"
        includes = {}
    else:
        entry = files["blend"][res]["blend"]
        includes = entry.get("include", {})
        planned = entry["size"] + sum(v["size"] for v in includes.values())
        target = DEST / asset_id / Path(entry["url"]).name
    left = budget_mb() * 1e6 - used_bytes()
    if not target.exists() and planned > left:
        sys.exit(f"refused: {asset_id} needs {planned / 1e6:.1f} MB, budget left {left / 1e6:.1f} MB")
    size = download(entry["url"], target)
    for rel, inc in includes.items():
        size += download(inc["url"], target.parent / rel)
    if size:
        log(asset_id, kind, res, size, f"https://polyhaven.com/a/{asset_id}")
    print(f"{asset_id}: {size / 1e6:.1f} MB new, budget used {used_bytes() / 1e6:.1f} of {budget_mb():.0f} MB")
    return target


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "budget":
        print(f"{used_bytes() / 1e6:.1f} MB of {budget_mb():.0f} MB")
        sys.exit(0)
    if len(sys.argv) < 3 or sys.argv[1] not in ("model", "hdri", "tex"):
        sys.exit(__doc__)
    print(fetch(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "2k"))
