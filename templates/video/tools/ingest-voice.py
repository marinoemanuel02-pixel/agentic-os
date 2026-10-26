"""Ingest a human voiceover: raw takes (any order of lines, recorded in passes) -> one clean WAV per script line.

For a film narrated by a person instead of Kokoro. Takes are listed in script order. For each take: highpass,
two-pass loudness normalisation to TARGET_LUFS, gentle compression and a limiter. Whisper (with the script as a
prompt) gives word times; the script words are aligned to the heard words (difflib), so small wording slips and
recognizer errors do not break the cut. Each line is sliced at the quietest point of the gap before and after it,
keeping only a short pad of air, and written to <media>/app/public/vo/<id>.wav. It also writes src/data/vo.json,
src/data/words.json (the SCRIPT's own words with times relative to each line WAV, which is what captions and cuts
key on) and src/data/words.sha256.json, plus voice/ingest-report.md listing what was heard against what was written.

Usage: python tools/ingest-voice.py take1.m4a take2.m4a ... [--dry] [--verify]
  --dry     align and report only, write nothing
  --verify  transcribe each written line again and compare its first and last word (catches clipped words)
Needs AOS_WHISPER_MODEL (a local faster-whisper model folder; nothing is downloaded) and ffmpeg on PATH.
"""
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
MEDIA = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos" / "video" / ROOT.name))
SR = 48000
TARGET_LUFS = -19.0
PAD_BEFORE, PAD_AFTER = 0.10, 0.14  # seconds of air kept around a line
CHAIN = "highpass=f=70"


def norm(w: str) -> str:
    return re.sub(r"[^a-z0-9']", "", w.lower().replace("’", "'"))


def ff(*args) -> subprocess.CompletedProcess:
    return subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", *args], capture_output=True, text=True, encoding="utf-8", errors="replace")


def prep(take: Path, out: Path) -> None:
    """Highpass, two-pass loudnorm to TARGET_LUFS (linear), gentle compression, limiter -> mono 48 kHz 16-bit WAV."""
    first = ff("-i", str(take), "-af", f"{CHAIN},loudnorm=I={TARGET_LUFS}:TP=-2:LRA=7:print_format=json", "-f", "null", "-")
    j = json.loads(first.stderr[first.stderr.rindex("{"):first.stderr.rindex("}") + 1])
    ln = (f"loudnorm=I={TARGET_LUFS}:TP=-2:LRA=7:measured_I={j['input_i']}:measured_TP={j['input_tp']}:"
          f"measured_LRA={j['input_lra']}:measured_thresh={j['input_thresh']}:offset={j['target_offset']}:linear=true")
    out.parent.mkdir(parents=True, exist_ok=True)
    r = ff("-y", "-i", str(take), "-af", f"{CHAIN},{ln},acompressor=threshold=0.16:ratio=2.2:attack=10:release=160,alimiter=limit=0.89,aresample={SR}",
           "-ac", "1", "-c:a", "pcm_s16le", str(out))
    if r.returncode:
        sys.exit(r.stderr[-800:])


def read_wav(p: Path) -> np.ndarray:
    with wave.open(str(p), "rb") as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0


def write_wav(p: Path, x: np.ndarray) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(p), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def whisper_words(wav: Path, prompt: str, model):
    pcm = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(wav), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout
    seg, _ = model.transcribe(np.frombuffer(pcm, dtype=np.float32), language="en", beam_size=8, word_timestamps=True,
                              condition_on_previous_text=False, initial_prompt=prompt or None)
    return [(w.word.strip(), w.start, w.end) for s in seg for w in s.words]


def quietest(rms: np.ndarray, t0: float, t1: float) -> float:
    """Time of the lowest 10 ms RMS inside the middle 70 % of [t0, t1]."""
    a, b = int((t0 + 0.15 * (t1 - t0)) * 100), int((t0 + 0.85 * (t1 - t0)) * 100)
    if b <= a:
        return (t0 + t1) / 2
    return (a + int(np.argmin(rms[a:b + 1]))) / 100


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry, verify = "--dry" in sys.argv, "--verify" in sys.argv
    if not args:
        sys.exit(__doc__)
    lines = json.loads((ROOT / "src/data/lines.json").read_text(encoding="utf-8"))
    from faster_whisper import WhisperModel
    model_dir = os.environ.get("AOS_WHISPER_MODEL")
    if not model_dir:
        sys.exit("Set AOS_WHISPER_MODEL to an existing local faster-whisper model folder; nothing is downloaded")
    model = WhisperModel(model_dir, device="cpu", compute_type="int8", cpu_threads=4, local_files_only=True)
    # no script prompt: Whisper skips sentences it recognises from the prompt (seen on the cant-escape-ai-2 takes);
    # the difflib alignment below is what ties the heard words to the script
    prompt = ""

    audio, heard = [], []  # per take: samples, then flat heard tokens (norm, take, start, end, raw)
    for ti, t in enumerate(args):
        p = MEDIA / "voice" / "prep" / (Path(t).stem + ".wav")
        prep(Path(t), p)
        audio.append(read_wav(p))
        for w, s, e in whisper_words(p, prompt, model):
            heard.append([norm(w), ti, s, e, w])
        print(f"take {ti + 1}/{len(args)} {Path(t).name}: {len(audio[-1]) / SR:.1f} s")
    heard = [h for h in heard if h[0]]
    vocab = {norm(w) for l in lines for w in l["text"].split()}
    merged, i = [], 0
    while i < len(heard):  # "super" + "intelligent" -> "superintelligent"
        if i + 1 < len(heard) and heard[i][1] == heard[i + 1][1] and heard[i][0] not in vocab and heard[i][0] + heard[i + 1][0] in vocab:
            merged.append([heard[i][0] + heard[i + 1][0], heard[i][1], heard[i][2], heard[i + 1][3], heard[i][4] + heard[i + 1][4]])
            i += 2
        else:
            merged.append(heard[i])
            i += 1
    heard = merged

    script = [(li, norm(w), w) for li, l in enumerate(lines) for w in l["text"].split() if norm(w)]
    sm = difflib.SequenceMatcher(None, [s[1] for s in script], [h[0] for h in heard], autojunk=False)
    s2h = {}
    for blk in sm.get_matching_blocks():
        for k in range(blk.size):
            s2h[blk.a + k] = blk.b + k
    claimed = set(s2h.values())

    cuts = []  # per line: (take, h_first, h_last)
    report = ["# Voice ingest report", "", f"Takes: {', '.join(Path(a).name for a in args)}", ""]
    idx_by_line = {}
    for k, (li, _, _) in enumerate(script):
        idx_by_line.setdefault(li, []).append(k)
    prev_last = -1
    for li, l in enumerate(lines):
        ks = idx_by_line[li]
        matched = [k for k in ks if k in s2h]
        if not matched:
            sys.exit(f"{l['id']}: no word of this line was heard; check the takes and the script")
        first_m, last_m = min(s2h[k] for k in matched), max(s2h[k] for k in matched)
        lead = sum(1 for k in ks if k < min(matched) and k not in s2h)
        trail = sum(1 for k in ks if k > max(matched) and k not in s2h)
        hf = first_m
        for _ in range(lead):
            if hf - 1 > prev_last and (hf - 1) not in claimed and heard[hf - 1][1] == heard[first_m][1]:
                hf -= 1
        hl = last_m
        for _ in range(trail):
            if hl + 1 < len(heard) and (hl + 1) not in claimed and heard[hl + 1][1] == heard[last_m][1]:
                hl += 1
        if heard[hf][1] != heard[hl][1]:
            sys.exit(f"{l['id']} spans two takes; record each line inside one take")
        cuts.append((heard[hf][1], hf, hl))
        prev_last = hl
        spoken = " ".join(h[4] for h in heard[hf:hl + 1])
        frac = len(matched) / len(ks)
        flag = "" if frac >= 0.85 else "  <-- CHECK"
        report.append(f"- {l['id']} ({frac:.0%} of words matched){flag}\n  written: {l['text']}\n  heard:   {spoken}")

    rms = [np.sqrt(np.convolve(a * a, np.ones(SR // 100) / (SR // 100), mode="same"))[:: SR // 100] for a in audio]
    vo, words, sha = [], {}, {}
    out_dir = MEDIA / "app" / "public" / "vo"
    for li, (l, (take, hf, hl)) in enumerate(zip(lines, cuts)):
        t0, t1 = heard[hf][2], heard[hl][3]
        dur = len(audio[take]) / SR
        prev = cuts[li - 1] if li else None
        nxt = cuts[li + 1] if li + 1 < len(cuts) else None
        cut_prev = quietest(rms[take], heard[prev[2]][3], t0) if prev and prev[0] == take and heard[prev[2]][3] < t0 else 0.0
        cut_next = quietest(rms[take], t1, heard[nxt[1]][2]) if nxt and nxt[0] == take and heard[nxt[1]][2] > t1 else dur
        s, e = max(cut_prev, t0 - PAD_BEFORE), min(cut_next, t1 + PAD_AFTER)
        x = audio[take][int(s * SR):int(e * SR)].copy()
        fi, fo = int(0.008 * SR), int(0.015 * SR)
        x[:fi] *= np.linspace(0, 1, fi)
        x[-fo:] *= np.linspace(1, 0, fo)
        ks = idx_by_line[li]
        tok = []  # the script's own words with times relative to the line WAV
        known = {k: (heard[s2h[k]][2], heard[s2h[k]][3]) for k in ks if k in s2h and hf <= s2h[k] <= hl}
        for n, k in enumerate(ks):
            if k in known:
                tok.append(known[k])
                continue
            a = max((kk for kk in known if kk < k), default=None)
            b = min((kk for kk in known if kk > k), default=None)
            lo = known[a][1] if a is not None else t0
            hi = known[b][0] if b is not None else t1
            gap = [kk for kk in ks if (a is None or kk > a) and (b is None or kk < b)]
            w = (hi - lo) / max(1, len(gap))
            pos = gap.index(k)
            tok.append((lo + pos * w, lo + (pos + 1) * w))
        words[l["id"]] = [[script[k][2], round(max(0.0, ts - s), 2), round(max(0.0, te - s), 2)] for k, (ts, te) in zip(ks, tok)]
        vo.append({"id": l["id"], "file": f"vo/{l['id']}.wav", "seconds": round(len(x) / SR, 3)})
        if not dry:
            write_wav(out_dir / f"{l['id']}.wav", x)
            sha[l["id"]] = hashlib.sha256((out_dir / f"{l['id']}.wav").read_bytes()).hexdigest()
    report.append("")
    report.append(f"Total speech: {sum(v['seconds'] for v in vo):.1f} s over {len(vo)} lines")
    text = "\n".join(report) + "\n"
    print(text)
    if dry:
        return
    (MEDIA / "voice").mkdir(parents=True, exist_ok=True)
    (MEDIA / "voice" / "ingest-report.md").write_text(text, encoding="utf-8")
    data = ROOT / "src" / "data"
    (data / "vo.json").write_text(json.dumps(vo, indent=1) + "\n", encoding="utf-8")
    (data / "words.json").write_text(json.dumps(words, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (data / "words.sha256.json").write_text(json.dumps(sha, indent=1) + "\n", encoding="utf-8")
    if verify:
        bad = 0
        for l in lines:
            ws = whisper_words(out_dir / f"{l['id']}.wav", "", model)
            got = [norm(w[0]) for w in ws]
            want = [norm(w) for w in l["text"].split() if norm(w)]
            if not got or got[0] != want[0] or got[-1] != want[-1]:
                bad += 1
                print(f"VERIFY {l['id']}: first/last heard '{got[:1]}'/'{got[-1:]}', script '{want[:1]}'/'{want[-1:]}'")
        print("verify: all line ends intact" if not bad else f"verify: {bad} line(s) to listen to")


if __name__ == "__main__":
    main()
