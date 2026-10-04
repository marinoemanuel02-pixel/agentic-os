"""Word start times of every narration line, from the already-cached Whisper model (no downloads).

Shots key their events to these times (src/data/words.json), so a callout lands on the word that names it
instead of on a guessed frame. Regenerate after any revoice:
  AOS_WHISPER_MODEL=<existing local model folder> <whisper python> tools/word-times.py
Times are seconds from the start of each line's own WAV. Recognized spellings may differ from the script
(numbers, acronyms); shots look words up through `cue()` in src/lib/cues.ts, which fails loudly on a miss.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import numpy as np
from faster_whisper import WhisperModel


def pcm16k(wav):
    """Decode with ffmpeg to mono float32 at 16 kHz: newer PyAV builds break faster-whisper's own decoder."""
    raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(wav), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


sys.stdout.reconfigure(encoding="utf-8", errors="replace")
root = Path(__file__).resolve().parent.parent
model_dir = os.environ.get("AOS_WHISPER_MODEL")
if not model_dir:
    raise RuntimeError("Set AOS_WHISPER_MODEL to an existing local model directory; no download attempted")
model_path = Path(model_dir)
if not (model_path / "model.bin").is_file():
    raise RuntimeError("Existing Whisper model cache incomplete; no download attempted")
media = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos/video/{{name}}"))
public = media / "app/public"
vo_dir = Path(os.environ["VO_DIR"]) if os.environ.get("VO_DIR") else None
model = WhisperModel(str(model_path), device="cpu", compute_type="int8", cpu_threads=4, local_files_only=True)
lines = json.loads((root / "src/data/lines.json").read_text(encoding="utf-8"))
voice = json.loads((root / "src/data/vo.json").read_text(encoding="utf-8"))
out = {}
meta = {}
for line in lines:
    entry = next(v for v in voice if v["id"] == line["id"])
    wav = vo_dir / Path(entry["file"]).name if vo_dir else public / entry["file"]
    meta[line["id"]] = hashlib.sha256(wav.read_bytes()).hexdigest()
    segments, _ = model.transcribe(pcm16k(wav), language="en", beam_size=5, word_timestamps=True)
    words = [[w.word.strip(), round(w.start, 2), round(w.end, 2)] for s in segments for w in s.words]
    out[line["id"]] = words
    print(line["id"], len(words), "words")
(root / "src/data/words.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
# the WAVs these times were measured from: tools/audio.mts refuses to build if a voice no longer matches
(root / "src/data/words.sha256.json").write_text(json.dumps(meta, indent=1) + "\n", encoding="utf-8")
print("wrote src/data/words.json and words.sha256.json")
