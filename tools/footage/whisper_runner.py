#!/usr/bin/env python3
"""Run only in the already-installed local faster-whisper environment."""
import argparse
import json
import os
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--language")
    args = parser.parse_args()
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", HF_DATASETS_OFFLINE="1")
    model_dir = args.model_dir.resolve()
    if not model_dir.is_dir() or any(not (model_dir / name).is_file() for name in ("model.bin", "config.json", "tokenizer.json")):
        parser.error("complete existing model directory required; downloads are disabled")
    from faster_whisper import WhisperModel
    model = WhisperModel(str(model_dir), device="cpu", compute_type="int8", local_files_only=True)
    segments, info = model.transcribe(args.source, language=args.language, word_timestamps=True)
    words = []
    for segment in segments:
        if segment.words is None:
            raise ValueError("transcription returned no word timestamps")
        words.extend({"start": word.start, "end": word.end, "text": word.word} for word in segment.words)
    with args.out.open("x", encoding="utf-8") as output:
        json.dump({"language": info.language, "words": words}, output, ensure_ascii=False, allow_nan=False)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    main()
