#!/usr/bin/env python3
"""Small, offline, hash-bound workflow for editing existing local footage."""
import argparse
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path, PureWindowsPath
import re
import subprocess
import sys
import tempfile


class FootageError(Exception):
    """An input or tool failure that must stop the workflow."""


# Force known single-file demuxers; a renamed playlist must not fetch remote media.
FORMATS = {".mp4": "mov", ".mov": "mov", ".m4v": "mov", ".m4a": "mov",
           ".mkv": "matroska", ".webm": "matroska", ".wav": "wav",
           ".mp3": "mp3", ".flac": "flac", ".ogg": "ogg", ".avi": "avi",
           ".mpeg": "mpeg", ".mpg": "mpeg", ".ts": "mpegts"}


@dataclass
class Roots:
    source: Path
    cache: Path
    output: Path

    def __post_init__(self):
        self.source, self.cache, self.output = (Path(p).resolve() for p in (self.source, self.cache, self.output))
        if not self.source.is_dir():
            raise FootageError("source root must be an existing directory")
        roots = (self.source, self.cache, self.output)
        for index, first in enumerate(roots):
            for second in roots[index + 1:]:
                if first.is_relative_to(second) or second.is_relative_to(first):
                    raise FootageError("source, cache and output roots must be separate, non-overlapping directories")
        self.cache.mkdir(parents=True, exist_ok=True)
        self.output.mkdir(parents=True, exist_ok=True)


def relative_path(root, name, exists=True):
    if not isinstance(name, str) or not name or ":" in name or "\\" in name:
        raise FootageError("paths must be relative, using forward slashes")
    path = Path(name)
    if path.is_absolute() or PureWindowsPath(name).drive or ".." in path.parts:
        raise FootageError("path must stay inside its declared root")
    result = (root / path).resolve()
    if not result.is_relative_to(root) or result == root:
        raise FootageError("path escapes its declared root")
    if exists and not result.is_file():
        raise FootageError("file not found: " + name)
    return result


def run(command, timeout=120, env=None, cwd=None):
    try:
        return subprocess.run([str(x) for x in command], check=True, capture_output=True,
                              encoding="utf-8", errors="replace", timeout=timeout, env=env, cwd=cwd)
    except subprocess.CalledProcessError as error:
        raise FootageError("tool failed: " + Path(str(command[0])).name + "\n" + error.stderr[-4000:]) from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise FootageError("tool unavailable or timed out: " + Path(str(command[0])).name + ": " + str(error)) from error


def finite(value, label, minimum=0):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < minimum:
        raise FootageError(label + " must be a finite number >= " + str(minimum))
    return float(value)


def input_options(path):
    demuxer = FORMATS.get(Path(path).suffix.lower())
    if not demuxer:
        raise FootageError("unsupported media extension: " + Path(path).suffix)
    return ["-protocol_whitelist", "file,pipe", "-f", demuxer]


def probe_media(path):
    raw = run(["ffprobe", "-v", "error", *input_options(path), "-show_format", "-show_streams", "-of", "json", path])
    try:
        data = json.loads(raw.stdout)
        duration = finite(float(data["format"]["duration"]), "media duration", 0.000001)
        video = next((s for s in data["streams"] if s["codec_type"] == "video" and not s.get("disposition", {}).get("attached_pic")), None)
        audio = next((s for s in data["streams"] if s["codec_type"] == "audio"), None)
        if not video and not audio:
            raise FootageError("unsupported media: no video or audio stream")
        result = {"duration": duration, "has_video": video is not None, "has_audio": audio is not None}
        if video:
            result.update(width=int(video["width"]), height=int(video["height"]), video_index=int(video["index"]))
        if audio:
            result["audio_index"] = int(audio["index"])
        return result
    except (ValueError, KeyError, TypeError, StopIteration) as error:
        raise FootageError("unsupported or invalid media metadata") from error


def sha256(path):
    before = path.stat()
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise FootageError("source changed while reading")
    return digest.hexdigest()


def source_identity(roots, name):
    path = relative_path(roots.source, name)
    digest = sha256(path)
    metadata = probe_media(path)
    if sha256(path) != digest:
        raise FootageError("source changed while probing")
    return {"path": Path(name).as_posix(), "sha256": digest, "bytes": path.stat().st_size, **metadata}


def check_identity(roots, identity):
    if not isinstance(identity, dict):
        raise FootageError("missing source identity")
    name = identity.get("path")
    path = relative_path(roots.source, name)
    if not isinstance(identity.get("sha256"), str) or not re.fullmatch("[0-9a-f]{64}", identity["sha256"]):
        raise FootageError("invalid source hash")
    if path.stat().st_size != identity.get("bytes") or sha256(path) != identity["sha256"]:
        raise FootageError("source changed: stale hash for " + name)
    current = probe_media(path)
    if identity.get("duration") != current["duration"]:
        raise FootageError("source duration no longer matches identity")
    return current


def inventory(roots):
    assets = []
    for path in sorted(roots.source.rglob("*")):
        if path.is_file() and path.suffix.lower() in FORMATS:
            assets.append(source_identity(roots, path.relative_to(roots.source).as_posix()))
    return {"schema": 1, "kind": "inventory", "sources": assets}


def destination(root, name):
    path = relative_path(root, name, exists=False)
    if path.exists():
        raise FootageError("destination already exists: " + name)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Resolve again after creating parents, including any existing junctions/symlinks.
    return relative_path(root, name, exists=False)


def publish(temporary, target):
    # Atomic no-clobber publication on the same volume (NTFS and normal POSIX filesystems).
    try:
        os.link(temporary, target)
    except OSError as error:
        raise FootageError("cannot publish without overwriting; destination may already exist or filesystem lacks hard links") from error


def write_json(root, name, value):
    target = destination(root, name)
    with tempfile.TemporaryDirectory(prefix=".footage-", dir=target.parent) as work:
        temporary = Path(work) / "document.json"
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        publish(temporary, target)
    return target


def read_json(root, name):
    try:
        result = json.loads(relative_path(root, name).read_text(encoding="utf-8-sig"))
        if not isinstance(result, dict) or result.get("schema") != 1:
            raise FootageError("unsupported document schema")
        return result
    except (ValueError, UnicodeError) as error:
        raise FootageError("invalid JSON document: " + name) from error


def validate_words(words, duration):
    if not isinstance(words, list):
        raise FootageError("transcript must contain a words list")
    previous = 0.0
    for word in words:
        if not isinstance(word, dict) or not isinstance(word.get("text"), str) or not word["text"].strip():
            raise FootageError("invalid transcript word")
        start = finite(word.get("start"), "word start")
        end = finite(word.get("end"), "word end")
        if not previous <= start <= end <= duration:
            raise FootageError("word times must be ordered and bounded by source duration")
        previous = start


def load_transcript(roots, name):
    data = read_json(roots.cache, name)
    if data.get("kind") != "transcript":
        raise FootageError("expected transcript")
    current = check_identity(roots, data.get("source"))
    validate_words(data.get("words"), current["duration"])
    return data


def transcribe(roots, name, model_dir, whisper_python, out, language=None):
    target = destination(roots.cache, out)
    model = Path(model_dir).resolve()
    if not model.is_dir() or any(not (model / file).is_file() for file in ("model.bin", "config.json", "tokenizer.json")):
        raise FootageError("model directory must already contain model.bin, config.json and tokenizer.json; no downloads are performed")
    interpreter = Path(whisper_python).resolve()
    if not interpreter.is_file():
        raise FootageError("whisper-python must name an existing installed interpreter")
    identity = source_identity(roots, name)
    if not identity["has_audio"]:
        raise FootageError("transcription requires an audio stream")
    env = os.environ.copy()
    env.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", HF_DATASETS_OFFLINE="1", PYTHONIOENCODING="utf-8")
    with tempfile.TemporaryDirectory(prefix=".footage-transcribe-", dir=target.parent) as work:
        raw = Path(work) / "words.json"
        command = [interpreter, Path(__file__).with_name("whisper_runner.py"), "--source", relative_path(roots.source, name), "--model-dir", model, "--out", raw]
        if language:
            command += ["--language", language]
        run(command, timeout=3600, env=env)
        try:
            data = json.loads(raw.read_text(encoding="utf-8"))
            validate_words(data.get("words"), identity["duration"])
        except (OSError, ValueError, AttributeError) as error:
            raise FootageError("transcription runner returned invalid word data") from error
        check_identity(roots, identity)
        result = {"schema": 1, "kind": "transcript", "source": identity, "language": data.get("language"), "words": data["words"]}
        write_json(roots.cache, out, result)
    return result


def tokens(text):
    return re.findall(r"\w+", text.casefold(), flags=re.UNICODE)


def search(roots, transcripts, query):
    needle = tokens(query)
    if not needle:
        raise FootageError("search query must contain words")
    hits = []
    for name in transcripts:
        data = load_transcript(roots, name)
        # Each token keeps its original word so punctuation/multi-token ASR words retain times.
        indexed = [(token, index) for index, word in enumerate(data["words"]) for token in tokens(word["text"])]
        for start in range(len(indexed) - len(needle) + 1):
            if [item[0] for item in indexed[start:start + len(needle)]] == needle:
                first, last = indexed[start][1], indexed[start + len(needle) - 1][1]
                words = data["words"][first:last + 1]
                hits.append({"source": data["source"]["path"], "start": words[0]["start"], "end": words[-1]["end"], "text": " ".join(word["text"].strip() for word in words)})
    return hits


def draft_plan(roots, transcripts, pad=0.2, min_gap=0.5):
    pad, min_gap = finite(pad, "pad"), finite(min_gap, "min-gap")
    sources, cuts = [], []
    seen = set()
    for name in transcripts:
        data = load_transcript(roots, name)
        source = data["source"]
        if source["path"] in seen:
            raise FootageError("duplicate transcript source")
        seen.add(source["path"])
        sources.append(source)
        intervals = []
        for word in data["words"]:
            start, end = max(0, word["start"] - pad), min(source["duration"], word["end"] + pad)
            if end <= start:
                continue
            if intervals and start - intervals[-1][1] <= min_gap:
                intervals[-1][1] = max(intervals[-1][1], end)
            else:
                intervals.append([start, end])
        cuts.extend({"source": source["path"], "start": round(start, 6), "end": round(end, 6)} for start, end in intervals)
    return {"schema": 1, "kind": "cut-plan", "reviewed": False, "method": "speech word intervals; silence gaps removed", "pad": pad, "min_gap": min_gap, "sources": sources, "cuts": cuts}


def validate_plan(roots, plan):
    if not isinstance(plan, dict) or plan.get("schema") != 1 or plan.get("kind") != "cut-plan":
        raise FootageError("expected cut-plan schema 1")
    if plan.get("reviewed") is not True:
        raise FootageError("review the explicit cut plan, then set reviewed to true before rendering")
    if not isinstance(plan.get("sources"), list) or not isinstance(plan.get("cuts"), list) or not plan["cuts"]:
        raise FootageError("plan must contain sources and at least one cut")
    sources = {}
    for identity in plan["sources"]:
        metadata = check_identity(roots, identity)
        name = identity["path"]
        if name in sources:
            raise FootageError("duplicate plan source")
        sources[name] = metadata
    for cut in plan["cuts"]:
        if not isinstance(cut, dict) or not isinstance(cut.get("source"), str) or cut["source"] not in sources:
            raise FootageError("cut source is not bound to this plan")
        start, end = finite(cut.get("start"), "cut start"), finite(cut.get("end"), "cut end")
        if not start < end <= sources[cut["source"]]["duration"]:
            raise FootageError("cut times must be positive intervals within source duration")
    return sources


def render(roots, plan, out):
    target = destination(roots.output, out)
    if target.suffix.lower() != ".mp4":
        raise FootageError("render destination must use .mp4")
    sources = validate_plan(roots, plan)
    for media in sources.values():
        if not media["has_video"] or not media["has_audio"]:
            raise FootageError("unsupported export: each source needs video and audio streams")
    first = sources[plan["cuts"][0]["source"]]
    width, height = max(2, first["width"] // 2 * 2), max(2, first["height"] // 2 * 2)
    duration = sum(cut["end"] - cut["start"] for cut in plan["cuts"])
    with tempfile.TemporaryDirectory(prefix=".footage-render-", dir=target.parent) as work:
        work = Path(work)
        parts = []
        for index, cut in enumerate(plan["cuts"]):
            metadata = sources[cut["source"]]
            length = cut["end"] - cut["start"]
            if length < 1 / 30:
                raise FootageError("unsupported cut shorter than one export frame (1/30 second)")
            part = work / ("part%05d.mkv" % index)
            video_filter = "scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,setpts=PTS-STARTPTS" % (width, height, width, height)
            source = relative_path(roots.source, cut["source"])
            run(["ffmpeg", "-v", "error", "-nostdin", "-n", "-ss", format(cut["start"], ".9f"), *input_options(source), "-i", source,
                 "-map", "0:" + str(metadata["video_index"]), "-map", "0:" + str(metadata["audio_index"]),
                 "-vf", video_filter, "-af", "aresample=48000,asetpts=PTS-STARTPTS,apad", "-t", format(length, ".9f"),
                 "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", "-map_metadata", "-1", part], timeout=3600)
            parts.append("file '" + part.name + "'")
        (work / "concat.txt").write_text("\n".join(parts) + "\n", encoding="utf-8")
        temporary = work / "export.mp4"
        run(["ffmpeg", "-v", "error", "-nostdin", "-n", "-protocol_whitelist", "file,pipe", "-f", "concat", "-safe", "1", "-i", "concat.txt", "-map", "0:v:0", "-map", "0:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-map_metadata", "-1", temporary], timeout=3600, cwd=work)
        result = probe_media(temporary)
        if not result["has_video"] or not result["has_audio"] or abs(result["duration"] - duration) > max(0.15, len(parts) / 30 + 0.05):
            raise FootageError("render validation failed: output streams or duration mismatch")
        validate_plan(roots, plan)  # Refuse source drift during rendering before publication.
        publish(temporary, target)
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for root in ("source", "cache", "output"):
        parser.add_argument("--" + root + "-root", type=Path, required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    item = commands.add_parser("inventory", help="inventory recognized local media")
    item.add_argument("--out", required=True, help="new JSON path relative to cache root")
    item = commands.add_parser("transcribe", help="transcribe using an existing local model/interpreter")
    item.add_argument("source", help="media path relative to source root")
    item.add_argument("--model-dir", type=Path, required=True)
    item.add_argument("--whisper-python", type=Path, required=True)
    item.add_argument("--language")
    item.add_argument("--out", required=True)
    item = commands.add_parser("search", help="search timestamped word sequences")
    item.add_argument("query")
    item.add_argument("transcripts", nargs="+")
    item = commands.add_parser("draft", help="draft speech cuts; review before rendering")
    item.add_argument("transcripts", nargs="+")
    item.add_argument("--pad", type=float, default=0.2)
    item.add_argument("--min-gap", type=float, default=0.5)
    item.add_argument("--out", required=True)
    item = commands.add_parser("render", help="render an explicit reviewed plan")
    item.add_argument("plan", help="reviewed JSON path relative to cache root")
    item.add_argument("--out", required=True, help="new .mp4 path relative to output root")
    args = parser.parse_args(argv)
    try:
        roots = Roots(args.source_root, args.cache_root, args.output_root)
        if args.command == "inventory":
            value = inventory(roots)
            write_json(roots.cache, args.out, value)
        elif args.command == "transcribe":
            value = transcribe(roots, args.source, args.model_dir, args.whisper_python, args.out, args.language)
        elif args.command == "search":
            value = search(roots, args.transcripts, args.query)
        elif args.command == "draft":
            value = draft_plan(roots, args.transcripts, args.pad, args.min_gap)
            write_json(roots.cache, args.out, value)
        else:
            value = {"export": str(render(roots, read_json(roots.cache, args.plan), args.out))}
        print(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False))
        return 0
    except (FootageError, OSError) as error:
        print("footage: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
