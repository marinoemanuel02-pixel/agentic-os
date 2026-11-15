"""Narration with Qwen3-TTS VoiceDesign (local GPU, Apache-2.0): the whole script in one take, so the narrator stays one
voice and the delivery flows from line to line, then cut per line at the Whisper word times.

  <qwen venv python> tools/make-voice-qwen3.py                 # the film's voice -> media root app/public/vo + vo.json
  <qwen venv python> tools/make-voice-qwen3.py --audition DIR  # every voice in voice.json "audition" -> DIR/<name>.wav

The voice lives in voice.json (film root): {"instruct": "...", "seed": 7, "language": "English", "audition": {...}}.
Describe the voice and the delivery in words (age, warmth, pace, where to pause, which words are quieter).
Setup (once, with the operator's OK for about 7 GB: torch cu126 ~2.5 GB, model ~4.5 GB), never under AppData:
  UV_PYTHON_INSTALL_DIR=~/.aos/uv-python uv venv ~/.aos/tts/qwen3 --python 3.12
  uv pip install --python ~/.aos/tts/qwen3/Scripts/python.exe qwen-tts soundfile
  uv pip install --python ~/.aos/tts/qwen3/Scripts/python.exe --reinstall-package torch torch torchaudio \
      --index-url https://download.pytorch.org/whl/cu126      # qwen-tts pulls the CPU torch: put the CUDA one back
  HF_HOME=~/.aos/hf (model cache outside OneDrive). Word times come from the installed `whisper-ctranslate2` tool.
bfloat16 only: float16 overflows to a flat full-scale signal on Turing cards (seen on a GTX 1660 Ti, 2026-11-15).
After it: re-run tools/word-times.py (cues) and tools/check-plan.mts; a slower, more natural voice usually needs the
line slots and shots re-timed around it, never the voice sped up. Check the words by transcript, the voice by ear.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

sys.path.insert(0, str(Path(__file__).parent))
from media_root import media_root  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
lines = json.loads((ROOT / "src/data/lines.json").read_text(encoding="utf-8"))
voice = json.loads((ROOT / "voice.json").read_text(encoding="utf-8"))
audition = sys.argv[sys.argv.index("--audition") + 1] if "--audition" in sys.argv else None
norm = lambda s: re.sub(r"[^a-z0-9']", "", s.lower().replace("-", ""))

model = Qwen3TTSModel.from_pretrained(voice.get("model", "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"), device_map="cuda:0",
                                      dtype=torch.bfloat16, attn_implementation="sdpa")
text = "\n\n".join(l["text"] for l in lines)


def take(instruct: str, seed: int):
    torch.manual_seed(seed)
    wavs, sr = model.generate_voice_design(text=text, language=voice.get("language", "English"), instruct=instruct)
    return np.asarray(wavs[0], dtype=np.float32), sr


def word_times(wav: Path):
    out = Path(tempfile.mkdtemp())
    subprocess.run(["whisper-ctranslate2", str(wav), "--model", "large-v3-turbo", "--language", voice.get("whisper_lang", "en"),
                    "--device", "cpu", "--compute_type", "int8", "--word_timestamps", "True", "--output_format", "json",
                    "-o", str(out)], check=True, capture_output=True)
    tx = json.loads((out / f"{wav.stem}.json").read_text(encoding="utf-8"))
    return [(x["word"].strip(), x["start"], x["end"]) for s in tx["segments"] for x in s.get("words", []) if norm(x["word"])]


if audition:
    os.makedirs(audition, exist_ok=True)
    for name, instruct in voice.get("audition", {"voice": voice["instruct"]}).items():
        w, sr = take(instruct, voice.get("seed", 7))
        sf.write(f"{audition}/{name}.wav", w, sr)
        print(name, f"{len(w) / sr:.1f} s")
    sys.exit(0)

w, sr = take(voice["instruct"], voice.get("seed", 7))
media = media_root(ROOT)
vo = media / "app/public/vo"
vo.mkdir(parents=True, exist_ok=True)
whole = media / "vo-take.wav"
sf.write(whole, w, sr)
words = word_times(whole)
counts = [len([t for t in l["text"].replace("-", "").split() if norm(t)]) for l in lines]
if len(words) != sum(counts):
    sys.exit(f"heard {len(words)} words, the script has {sum(counts)}: listen to {whole} and re-take (another seed)")
res, k = [], 0
for i, (l, n) in enumerate(zip(lines, counts)):
    seg = words[k:k + n]; k += n
    heard = [norm(x[0]) for x in seg]
    want = [norm(t) for t in l["text"].replace("-", "").split() if norm(t)]
    a = max(0.0, seg[0][1] - 0.06)                       # 60 ms before the first word
    b = seg[-1][2] + 0.22                                # 220 ms after the last
    if i + 1 < len(lines):
        b = min(b, words[k][1] - 0.03)                   # never into the next line's first word
    x = w[int(a * sr):int(b * sr)].copy()
    fade = int(0.01 * sr)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    sf.write(vo / f"{l['id']}.wav", x, sr)
    res.append({"id": l["id"], "file": f"vo/{l['id']}.wav", "seconds": round(len(x) / sr, 3), "voice": "qwen3-tts voicedesign"})
    print(f"{l['id']}: {res[-1]['seconds']:.2f} s  {'ok' if heard == want else 'CHECK: ' + ' '.join(x[0] for x in seg)}")
(ROOT / "src/data/vo.json").write_text(json.dumps(res, indent=2), encoding="utf-8")
