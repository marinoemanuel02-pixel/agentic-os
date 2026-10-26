"""Wikimedia Commons and Internet Archive: search, licence lookup, fetch with a rights ledger.

Every fetched file is appended to research/assets.md (file, kind, size, licence, author, source page) and counted
against BUDGET_MB in qa.env, like tools/polyhaven.py. Requests carry a descriptive User-Agent and back off on
429/5xx, which Commons enforces.

Usage:
  python tools/commons.py search "<query>" [n]           Commons files (title | size | licence | author)
  python tools/commons.py info "File:<title>"            licence, author, original URL
  python tools/commons.py fetch "File:<title>" [width]   -> <media>/assets/commons/<safe name> (thumb at width for images)
  python tools/commons.py ia-search "<query>" [n]        Internet Archive items (identifier | title | year | licence)
  python tools/commons.py ia-fetch <identifier> [pattern] -> <media>/assets/ia/<identifier>/<file> (smallest mp4/ogv)
Video sections: pass the printed URL straight to ffmpeg -ss/-t; it reads only the bytes it needs.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
MEDIA = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos" / "video" / ROOT.name))
LOG = ROOT / "research" / "assets.md"
UA = {"User-Agent": "agentic-os-video/1.0 (personal film research; https://github.com/marinoemanuel02-pixel)"}
API = "https://commons.wikimedia.org/w/api.php"


def get(url: str, raw: bool = False, tries: int = 5):
    for k in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
                data = r.read()
                return data if raw else json.loads(data)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and k + 1 < tries:
                time.sleep(2 ** k * 2)
                continue
            raise
        except urllib.error.URLError as e:
            # archive.org's chain fails Python 3.13's strict X.509 checks; curl (system store) accepts it
            if "CERTIFICATE_VERIFY_FAILED" in str(e):
                import subprocess
                data = subprocess.run(["curl", "-sL", "-A", UA["User-Agent"], url], capture_output=True, check=True).stdout
                return data if raw else json.loads(data)
            if k + 1 < tries:
                time.sleep(2 ** k * 2)
                continue
            raise
        except json.JSONDecodeError:
            if k + 1 < tries:
                time.sleep(2 ** k * 2)
                continue
            raise


def strip(html: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html or "")).strip()


def budget() -> tuple[float, int]:
    mb = 500.0
    env = ROOT / "qa.env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.startswith("BUDGET_MB="):
                mb = float(line.split("=", 1)[1])
    used = 0
    if LOG.exists():
        for line in LOG.read_text(encoding="utf-8").splitlines():
            cells = [c.strip() for c in line.split("|")]
            if len(cells) > 5 and cells[4].isdigit():
                used += int(cells[4])
    return mb, used


def log(name, kind, size, licence, author, page):
    if not LOG.exists():
        LOG.parent.mkdir(parents=True, exist_ok=True)
        LOG.write_text("# Imported assets (download budget ledger)\n\n| asset | kind | res | bytes | licence | source |\n|---|---|---|---|---|---|\n", encoding="utf-8")
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"| {name} | {kind} | - | {size} | {licence}; {author} | {page} |\n")


def info(title: str, width: int | None = None) -> dict:
    q = {"action": "query", "titles": title, "prop": "imageinfo", "iiprop": "url|size|extmetadata|mediatype", "format": "json"}
    if width:
        q["iiurlwidth"] = str(width)
    p = list(get(API + "?" + urllib.parse.urlencode(q))["query"]["pages"].values())[0]
    ii = p["imageinfo"][0]
    m = ii.get("extmetadata", {})
    return {"title": p["title"], "url": ii["url"], "thumb": ii.get("thumburl"), "w": ii.get("width"), "h": ii.get("height"),
            "bytes": ii.get("size"), "duration": ii.get("duration"), "licence": strip(m.get("LicenseShortName", {}).get("value")),
            "author": strip(m.get("Artist", {}).get("value"))[:80], "page": "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(p["title"].replace(" ", "_"))}


def fetch(title: str, width: int | None = None) -> Path:
    i = info(title, width)
    url = i["thumb"] if width and i.get("thumb") else i["url"]
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", i["title"][5:])
    target = MEDIA / "assets" / "commons" / safe
    if not target.exists():
        mb, used = budget()
        data = get(url, raw=True)
        if used + len(data) > mb * 1e6:
            sys.exit(f"refused: budget {mb} MB, used {used / 1e6:.1f} MB")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        log(safe, "commons", len(data), i["licence"], i["author"], i["page"])
    print(f"{i['licence']} | {i['author']}\n{target}")
    return target


def search(q: str, n: int = 12):
    params = {"action": "query", "generator": "search", "gsrsearch": q, "gsrnamespace": "6", "gsrlimit": str(n),
              "prop": "imageinfo", "iiprop": "size|extmetadata", "format": "json"}
    pages = get(API + "?" + urllib.parse.urlencode(params)).get("query", {}).get("pages", {})
    for p in pages.values():
        ii = p["imageinfo"][0]
        m = ii.get("extmetadata", {})
        print(f"{p['title']} | {ii.get('width')}x{ii.get('height')} | {ii.get('size')} | "
              f"{strip(m.get('LicenseShortName', {}).get('value'))} | {strip(m.get('Artist', {}).get('value'))[:40]}")


def ia_search(q: str, n: int = 10):
    url = "https://archive.org/advancedsearch.php?" + urllib.parse.urlencode(
        {"q": q, "fl[]": ["identifier", "title", "year", "licenseurl"], "rows": n, "output": "json"}, doseq=True)
    for d in get(url)["response"]["docs"]:
        print(f"{d['identifier']} | {d.get('title')} | {d.get('year')} | {d.get('licenseurl', '')}")


def ia_fetch(ident: str, pattern: str = r"\.(mp4|ogv)$"):
    meta = get(f"https://archive.org/metadata/{ident}")
    files = [f for f in meta["files"] if re.search(pattern, f["name"], re.I)]
    f = min(files, key=lambda x: int(x.get("size", 1e12)))
    url = f"https://archive.org/download/{ident}/{urllib.parse.quote(f['name'])}"
    lic = meta.get("metadata", {}).get("licenseurl", "see item page")
    target = MEDIA / "assets" / "ia" / ident / re.sub(r"[^A-Za-z0-9._-]+", "_", f["name"])
    if not target.exists():
        mb, used = budget()
        if used + int(f.get("size", 0)) > mb * 1e6:
            sys.exit(f"refused: budget {mb} MB, used {used / 1e6:.1f} MB")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(get(url, raw=True))
        log(f"{ident}/{f['name']}", "archive.org", target.stat().st_size, lic, meta.get("metadata", {}).get("creator", ""),
            f"https://archive.org/details/{ident}")
    print(f"{lic}\n{target}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    if cmd == "search":
        search(a[1], int(a[2]) if len(a) > 2 else 12)
    elif cmd == "info":
        print(json.dumps(info(a[1]), indent=1, ensure_ascii=False))
    elif cmd == "fetch":
        fetch(a[1], int(a[2]) if len(a) > 2 else None)
    elif cmd == "ia-search":
        ia_search(a[1], int(a[2]) if len(a) > 2 else 10)
    elif cmd == "ia-fetch":
        ia_fetch(a[1], a[2] if len(a) > 2 else r"\.(mp4|ogv)$")
    else:
        sys.exit(__doc__)
