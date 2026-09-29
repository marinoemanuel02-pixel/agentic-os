# Video process v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the approved video process real: project layout, shared rules with the anti-slop list, one skill per stage, automated technical checks, contact sheets for the craft review, local-model frame screening, and a retrospective that turns rejections into rules; then run one motion-design video through every gate.

**Architecture:** A new Python tool, `video-kit` (`Desktop\1-Projects\video-kit`, CLI `vk`), holds everything testable (checks, sheets, screening, rules, scaffold), in the same pattern as nar-tools. agentic-os installs it (venv `~\.aos\venvs\video-kit`), forwards `aos video ...` to it, and ships the stage skills and the shared rules in `agents-home` so Claude, Codex and Pi all read them. v2 (a separate plan) adds the footage-edit route (silence removal, Whisper subtitles, timeline handoff) and stock footage.

**Tech Stack:** Python 3.13 + uv + pytest (video-kit); FFmpeg full build (winget `Gyan.FFmpeg`); Pillow; httpx (Ollama); PowerShell 5.1/7 + Pester 5 (agentic-os).

**Spec:** `docs/superpowers/specs/2026-09-29-video-process-design.md`

## Global Constraints

- Free only; generative engines are opt-in per video and pass the same gates.
- YouTube profile: 1920x1080 or larger, 24-60 fps, integrated loudness -14 LUFS (tolerance +/-1), true peak <= -1 dBTP, captions (SRT) present and within the video duration.
- Heavy media (renders, footage, caches, node_modules) under `~\.aos\video\<name>`, never in OneDrive; the project folder (text, code, exports) under `Desktop\1-Projects\videos\<name>`.
- The user approves three gates (definition of good, style frame, animatic) before production and the final review; skills must stop and ask at each gate.
- Installs listed with source and size for the user's approval before they run: FFmpeg (Gyan.FFmpeg, winget, ~100 MB, measure first).
- aos rules (AGENTS.md) hold: ASCII aos.psm1, PowerShell 5.1 and 7, tests first and seen failing, idempotent, no secrets in files.

## Review Focus

1. A render with no audio stream: the loudness check must report "no audio" as a failure, not crash.
2. A file path with spaces or non-ASCII characters (Italian names): every FFmpeg call gets it as one argument (list argv, no shell).
3. Ollama not running or the vision model missing during screening: a clear error, and the other checks still run.
4. `vk new` on an existing project: refuses without touching files.
5. A rule added twice by two retrospectives: stored once.

---

### Task 1: video-kit skeleton, probe and technical checks

**Files:** Create `video-kit/pyproject.toml`, `src/video_kit/__init__.py`, `src/video_kit/media.py`, `src/video_kit/checks.py`, `tests/conftest.py`, `tests/test_checks.py`, `.github/workflows/ci.yml`, `AGENTS.md`, `README.md` (create the repo with `aos new video-kit`; dev venv via `UV_PROJECT_ENVIRONMENT=$HOME\.aos\venvs\video-kit-dev`).

**Interfaces:**
- Produces: `media.probe(path) -> dict` (ffprobe JSON: `streams`, `format`); `checks.run_checks(path, srt=None, profile="youtube") -> list[Check]` where `Check = {"name": str, "ok": bool, "detail": str}`; `checks.loudness(path) -> dict | None` (`{"i": float, "tp": float}`, None when no audio).

- [ ] **Step 1: Failing tests** (fixtures make tiny media with ffmpeg: `testsrc2` video, `sine` audio, a 1 s black segment, a frozen segment):

```python
# tests/conftest.py
import subprocess, pytest
def ff(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)
@pytest.fixture
def good(tmp_path):
    p = tmp_path / "good clip.mp4"   # a space in the name on purpose
    ff("-f", "lavfi", "-i", "testsrc2=s=1920x1080:r=30:d=3", "-f", "lavfi", "-i", "sine=f=440:d=3",
       "-af", "volume=-14dB", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(p))
    return p
@pytest.fixture
def silent_small(tmp_path):
    p = tmp_path / "piccolo.mp4"
    ff("-f", "lavfi", "-i", "testsrc2=s=640x360:r=30:d=2", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(p))
    return p
@pytest.fixture
def with_black(tmp_path):
    p = tmp_path / "black.mp4"
    ff("-f", "lavfi", "-i", "color=c=black:s=1920x1080:r=30:d=1.5", "-f", "lavfi", "-i", "sine=d=1.5",
       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(p))
    return p
```

```python
# tests/test_checks.py
from video_kit import checks
def by_name(res): return {c["name"]: c for c in res}
def test_good_file_passes_resolution_and_fps(good):
    r = by_name(checks.run_checks(good))
    assert r["resolution"]["ok"] and r["fps"]["ok"]
def test_small_file_fails_resolution_and_reports_no_audio(silent_small):
    r = by_name(checks.run_checks(silent_small))
    assert not r["resolution"]["ok"]
    assert not r["loudness"]["ok"] and "no audio" in r["loudness"]["detail"]
def test_black_segment_is_reported(with_black):
    assert not by_name(checks.run_checks(with_black))["black_frames"]["ok"]
def test_missing_captions_fail_and_out_of_range_captions_fail(good, tmp_path):
    assert not by_name(checks.run_checks(good))["captions"]["ok"]
    srt = tmp_path / "c.srt"
    srt.write_text("1\n00:00:01,000 --> 00:00:09,000\nciao\n", encoding="utf-8")
    assert not by_name(checks.run_checks(good, srt=srt))["captions"]["ok"]
    srt.write_text("1\n00:00:00,500 --> 00:00:02,000\nciao\n", encoding="utf-8")
    assert by_name(checks.run_checks(good, srt=srt))["captions"]["ok"]
```

- [ ] **Step 2:** `uv run pytest -q` fails (module missing).
- [ ] **Step 3: Implement** `media.py` and `checks.py`:

```python
# src/video_kit/media.py
import json, subprocess
def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
def probe(path) -> dict:
    r = run(["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)])
    if r.returncode != 0:
        raise ValueError(f"ffprobe failed: {r.stderr.strip()[:300]}")
    return json.loads(r.stdout)
```

```python
# src/video_kit/checks.py
import re
from pathlib import Path
from video_kit.media import probe, run
PROFILES = {"youtube": {"min_w": 1920, "min_h": 1080, "fps": (24, 60), "lufs": -14.0, "lufs_tol": 1.0, "tp_max": -1.0}}
def _fps(s: str) -> float:
    n, d = s.split("/")
    return float(n) / float(d) if float(d) else 0.0
def loudness(path):
    r = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"])
    i = re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr); tp = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", r.stderr)
    return {"i": float(i[-1]), "tp": float(tp[-1])} if i and tp else None
def _detect(path, filt: str, key: str) -> list[str]:
    r = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-vf", filt, "-an", "-f", "null", "-"])
    return re.findall(key + r"[^\n]*", r.stderr)
def _srt_end(srt: Path) -> float:
    ends = re.findall(r"--> (\d+):(\d+):(\d+),(\d+)", srt.read_text(encoding="utf-8", errors="replace"))
    return max((int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000 for h, m, s, ms in ends), default=-1.0)
def run_checks(path, srt=None, profile: str = "youtube") -> list[dict]:
    p = PROFILES[profile]; info = probe(path)
    v = next((s for s in info["streams"] if s["codec_type"] == "video"), None)
    a = next((s for s in info["streams"] if s["codec_type"] == "audio"), None)
    dur = float(info["format"].get("duration", 0)); out = []
    def add(name, ok, detail): out.append({"name": name, "ok": bool(ok), "detail": detail})
    add("resolution", v and v["width"] >= p["min_w"] and v["height"] >= p["min_h"], f"{v and v['width']}x{v and v['height']}")
    f = _fps(v["avg_frame_rate"]) if v else 0.0
    add("fps", p["fps"][0] <= round(f, 2) <= p["fps"][1], f"{f:.2f}")
    if a is None:
        add("loudness", False, "no audio stream")
    else:
        l = loudness(path)
        ok = l is not None and abs(l["i"] - p["lufs"]) <= p["lufs_tol"] and l["tp"] <= p["tp_max"]
        add("loudness", ok, f"{l}" if l else "not measurable")
    add("black_frames", not _detect(path, "blackdetect=d=0.5:pix_th=0.10", "black_start"), "blackdetect >= 0.5 s")
    add("frozen_frames", not _detect(path, "freezedetect=n=0.003:d=1.0", "freeze_start"), "freezedetect >= 1 s")
    if srt is None or not Path(srt).exists():
        add("captions", False, "no caption file")
    else:
        end = _srt_end(Path(srt)); add("captions", 0 <= end <= dur + 0.05, f"last cue {end:.2f}s, video {dur:.2f}s")
    return out
```

(The `good` fixture's sine is too quiet for -14 LUFS on purpose; its loudness check is not asserted. `testsrc2` moves, so freezedetect stays quiet.)
- [ ] **Step 4:** `uv run pytest -q` passes. CI installs FFmpeg (`choco install ffmpeg -y` on windows-latest) before `uv run pytest -q`.
- [ ] **Step 5:** commit `video-kit: probe and technical checks for the YouTube profile`.

### Task 2: contact sheet for the craft review

**Files:** Create `src/video_kit/sheet.py`, `tests/test_sheet.py`. **Produces:** `sheet.make_sheet(path, out, cols=4, rows=3) -> list[float]` (the timestamps used; one frame per cell, evenly spaced, labelled with its time).

- [ ] **Step 1: Failing test:**

```python
from PIL import Image
from video_kit import sheet
def test_sheet_has_one_labelled_cell_per_timestamp(good, tmp_path):
    out = tmp_path / "s.jpg"
    times = sheet.make_sheet(good, out, cols=3, rows=2)
    assert len(times) == 6 and times == sorted(times) and 0 < times[0] and times[-1] < 3
    im = Image.open(out); assert im.width == 3 * 480 and im.height == 2 * 270
```

- [ ] **Step 2:** fails. **Step 3: Implement:**

```python
import subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageDraw
from video_kit.media import probe
def make_sheet(path, out, cols=4, rows=3, cell=(480, 270)) -> list[float]:
    dur = float(probe(path)["format"]["duration"]); n = cols * rows
    times = [round(dur * (i + 0.5) / n, 2) for i in range(n)]
    img = Image.new("RGB", (cols * cell[0], rows * cell[1]), "black"); d = ImageDraw.Draw(img)
    with tempfile.TemporaryDirectory() as tmp:
        for i, t in enumerate(times):
            f = Path(tmp) / f"{i}.png"
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(t), "-i", str(path), "-frames:v", "1", str(f)], check=True)
            x, y = (i % cols) * cell[0], (i // cols) * cell[1]
            img.paste(Image.open(f).convert("RGB").resize(cell), (x, y))
            d.rectangle([x, y, x + 70, y + 20], fill="black"); d.text((x + 5, y + 4), f"{t:.2f}s", fill="white")
    img.save(out, quality=88)
    return times
```

- [ ] **Step 4:** passes. **Step 5:** commit `video-kit: contact sheets`.

### Task 3: frame screening with the local vision model

**Files:** Create `src/video_kit/screen.py`, `tests/test_screen.py`. **Produces:** `screen.screen_frames(images: list[Path], model: str, client) -> list[dict]` (`{"frame", "flag": bool, "reason"}`); `screen.OllamaClient(url)` with `.ask(model, prompt, image_bytes) -> str`.

- [ ] **Step 1: Failing tests** (fake client; no Ollama in tests):

```python
from video_kit import screen
class Fake:
    def __init__(self, answers): self.answers = answers
    def ask(self, model, prompt, image): return self.answers.pop(0)
def test_flags_frames_the_model_marks(tmp_path):
    imgs = []
    for i in range(2):
        p = tmp_path / f"{i}.png"; p.write_bytes(b"x"); imgs.append(p)
    res = screen.screen_frames(imgs, "m", Fake(['{"flag": true, "reason": "melting hand"}', '{"flag": false, "reason": ""}']))
    assert [r["flag"] for r in res] == [True, False] and res[0]["reason"] == "melting hand"
def test_unparseable_answer_is_flagged_for_review(tmp_path):
    p = tmp_path / "a.png"; p.write_bytes(b"x")
    assert screen.screen_frames([p], "m", Fake(["no idea"]))[0]["flag"] is True
```

- [ ] **Step 2:** fails. **Step 3: Implement:**

```python
import base64, json, re
from pathlib import Path
import httpx
PROMPT = ("You check one frame of a video for defects. Answer only JSON: "
          '{"flag": true|false, "reason": "..."}. Flag: AI artifacts (melting, extra limbs, garbled text), '
          "unreadable text, a broken or empty frame, generic stock look.")
class OllamaClient:
    def __init__(self, url="http://127.0.0.1:11434"): self.url = url
    def ask(self, model, prompt, image):
        r = httpx.post(f"{self.url}/api/generate", timeout=120, json={"model": model, "prompt": prompt, "stream": False,
                       "think": False, "images": [base64.b64encode(image).decode()], "format": "json"})
        r.raise_for_status(); return r.json()["response"]
def screen_frames(images, model, client) -> list[dict]:
    out = []
    for p in images:
        text = client.ask(model, PROMPT, Path(p).read_bytes())
        m = re.search(r"\{.*\}", text, re.S)
        try:
            d = json.loads(m.group(0)) if m else None
            out.append({"frame": str(p), "flag": bool(d["flag"]), "reason": str(d.get("reason", ""))})
        except (ValueError, KeyError, TypeError):
            out.append({"frame": str(p), "flag": True, "reason": "unreadable answer: review by hand"})
    return out
```

- [ ] **Step 4:** passes. **Step 5:** commit `video-kit: local frame screening`.

### Task 4: rules and retrospective

**Files:** Create `src/video_kit/rules.py`, `tests/test_rules.py`. **Produces:** `rules.add_rule(path, text, source) -> bool` (False when an equal rule exists, case- and space-insensitive); `rules.load_rules(path) -> list[str]`.

- [ ] **Step 1: Failing tests:**

```python
from video_kit import rules
def test_add_is_idempotent_and_keeps_source(tmp_path):
    f = tmp_path / "video-rules.md"
    assert rules.add_rule(f, "No slideshow pacing: every shot moves.", "agi-race 2026-09-29")
    assert not rules.add_rule(f, "  no slideshow pacing:  every shot moves. ", "other")
    assert rules.load_rules(f) == ["No slideshow pacing: every shot moves."]
    assert "agi-race 2026-09-29" in f.read_text(encoding="utf-8")
```

- [ ] **Step 2:** fails. **Step 3: Implement:**

```python
import re
from pathlib import Path
_RULE = re.compile(r"^- (.+?)(?:  \(from .+\))?$")
def _norm(s): return " ".join(s.lower().split())
def load_rules(path) -> list[str]:
    p = Path(path)
    if not p.exists(): return []
    return [m.group(1) for line in p.read_text(encoding="utf-8").splitlines() if (m := _RULE.match(line))]
def add_rule(path, text, source) -> bool:
    text = " ".join(text.split())
    if any(_norm(r) == _norm(text) for r in load_rules(path)): return False
    p = Path(path); p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8") as f: f.write(f"- {text}  (from {source})\n")
    return True
```

- [ ] **Step 4:** passes. **Step 5:** commit `video-kit: rules from retrospectives`.

### Task 5: `vk` CLI and project scaffold

**Files:** Create `src/video_kit/cli.py`, `src/video_kit/scaffold.py`, `tests/test_cli.py`; `pyproject.toml` `[project.scripts] vk = "video_kit.cli:main"`. **Produces:** `vk new <name>`, `vk qa <file> [--srt F] [--json]` (exit 1 on any failed check), `vk sheet <file> --out F`, `vk screen <file> [--model M]` (frames from a 12-cell sheet grid, saved under the heavy-media dir), `vk rule add "<text>" --source S`, `vk rule list`. Paths: projects root `$env:AOS_PROJECTS` or `~/OneDrive/Desktop/1-Projects`, `videos/<name>`; media root `~/.aos/video/<name>`; rules file `~/.agents/video/video-rules.md`.

- [ ] **Step 1: Failing tests:**

```python
import json
from video_kit import cli
def test_new_creates_layout_and_refuses_existing(tmp_path, monkeypatch):
    monkeypatch.setenv("AOS_PROJECTS", str(tmp_path / "p")); monkeypatch.setenv("VK_MEDIA_ROOT", str(tmp_path / "m"))
    assert cli.main(["new", "agi-race"]) == 0
    proj = tmp_path / "p" / "videos" / "agi-race"
    for f in ["brief.md", "rubric.md", "style.md", "script.md", "shots.yaml", "retro.md", "project.json"]:
        assert (proj / f).exists()
    assert json.loads((proj / "project.json").read_text(encoding="utf-8"))["media"] == str(tmp_path / "m" / "agi-race")
    assert cli.main(["new", "agi-race"]) == 1
def test_qa_exit_code_reflects_checks(good, capsys):
    assert cli.main(["qa", str(good), "--json"]) == 1   # no captions -> fails
    assert any(c["name"] == "captions" for c in json.loads(capsys.readouterr().out))
```

- [ ] **Step 2:** fails. **Step 3: Implement** `scaffold.new_project(name) -> Path` (refuse names outside `[a-z0-9-]{1,40}` and existing folders; create the folders `refs style animatic src qa exports` and the files, each starting with a heading and the questions of its stage, e.g. `brief.md`: purpose, audience, platform, length, material, references; `rubric.md`: "5-8 checks that define good for this video"; `project.json`: name, media path, created date) and `cli.main` with argparse subcommands calling Tasks 1-4; UTF-8 stdout as in nar (`sys.stdout.reconfigure(encoding="utf-8", errors="replace")`).
- [ ] **Step 4:** passes. **Step 5:** commit `video-kit: vk command and project scaffold`.

### Task 6: aos integration (agentic-os)

**Files:** Modify `aos.psm1` (`Get-AosVideoVenv`, `Install-AosVideoKit` modelled on `Install-AosNarTools`, `Invoke-AosVideo` modelled on `Invoke-AosNar`, dispatcher `'video'`), `packages.json` (`local` list: `{ "id": "Gyan.FFmpeg", "why": "ffmpeg/ffprobe for the video process" }`), `tests/aos.Tests.ps1` (`Describe 'Video kit'`: install skipped without the repo, uv sync in DryRun previews only, `aos video qa x` forwards arguments unchanged, missing vk warns).
- [ ] Steps: failing Pester tests -> implement -> `aos test` green -> commit `aos: video kit (aos video ...)`. Ask the user to approve the FFmpeg install (size measured with `winget show Gyan.FFmpeg`) before `aos install local`.

### Task 7: stage skills and shared rules (agentic-os)

**Files:** Create `agents-home/video/video-rules.md` and seven skills `agents-home/skills/video-<stage>/SKILL.md`; test in `tests/aos.Tests.ps1` (`Describe 'Video skills'`: every video skill has `name` and a `description` under 200 characters, and its body mentions `video-rules.md`).
`video-rules.md` starts with:
```markdown
# Video rules (read at every stage; added by retrospectives with `vk rule add`)
- Never start production before the user approves the definition of good, a style frame and the animatic.  (from agi-race 2026-09-29)
- No slideshow pacing: every shot has motion inside it and a purpose; cuts land on the beat.  (from agi-race 2026-09-29)
- No generic generated imagery as the default: generative engines are opt-in and must pass the anti-slop gate.  (from agi-race 2026-09-29)
- Anti-slop gate: reject generic stock look, visuals that do not carry their line, AI artifacts, style drift, motion that goes nowhere.  (from agi-race 2026-09-29)
```
Each SKILL.md (frontmatter `name`, `description`) says, in this order: when to use it; read `~/.agents/video/video-rules.md` first; the inputs and outputs of the stage (files in the project, from the spec's layout); the gate question to put to the user and to stop until answered (brief -> approve `rubric.md`; look -> pick a style frame; structure -> approve the animatic); for produce-code: route by material per the spec's table, render with Remotion (`--gl=angle` for 3D), GPU jobs one at a time (`ollama stop` first); for qa: `vk qa`, `vk sheet`, `vk screen`, then score each rubric item and the anti-slop gate from the sheet, fix before showing the user; for retro: ask what failed and which gate should have caught it, then `vk rule add`. Commit `skills: video process stages and rules`; `aos sync` links them for Claude; Codex and Pi read `~/.agents/skills`.

### Task 8: acceptance (live, with the user)

- [ ] `aos video new <name>` for one motion-design video the user chooses; run the stages with the skills; the user answers the three gates and the final review from Paseo; `vk qa` all green; the retrospective adds at least one rule if anything was rejected. Record the result in `docs/decisions.md`.
