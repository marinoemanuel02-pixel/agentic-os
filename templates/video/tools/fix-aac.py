"""Turn the operator's WhatsApp .aac takes into playable 48 kHz mono WAVs.

Most of huggingface-it's takes (2026-10-29/30) carried ADTS sampling index 0 (96 kHz), but their frames are coded with
the 44.1/48 kHz band tables, so ffmpeg rejects about 98 % of them ("TNS filter order ... greater than maximum", "Number
of bands ... exceeds limit"). With the index patched to 4 every frame decodes; the decoded samples then play at the
header's own 96 kHz. After every conversion, scale-check the WAVs against a take with a sane header before ingest
(R55): `node tools/checks/voice-scale.mjs --ref <healthy.wav> --takes <out_dir>/*.wav`, or `ingest-voice.py --ref=`.
Evidence (2026-10-30, the same measurement against the film's two healthy 44.1 kHz takes):
- the long-term spectrum of the voice (formants, 150-4500 Hz) lines up with the healthy takes at x0.99-1.06 when
  played at 96 kHz (median x1.006), and 16 of 17 takes correlate better with them there than at 88.2 kHz;
- played at 88.2 kHz (the first version of this script) the voice sat at x0.90-0.96, i.e. 8 % slow and 1.5
  semitones low: the operator heard it as deeper, almost unrecognisable;
- Codex, measuring on its own: spectral correlation 0.931 at 96 kHz against 0.879 at 88.2 kHz, and the 99.9 %-energy
  band edge (7.2-7.4 kHz) matches the healthy takes (7.35-7.52 kHz) only at 96 kHz. Pitch alone is ambiguous;
- the mean frame payload (278.64 bytes; 281.36 in healthy PM.aac) is the encoder's own budget (96 kbps at
  44.1 kHz) in healthy and mislabelled takes alike, not a clue to the playback rate.
Takes with a sane header are only converted. The originals are never modified.

Usage: python tools/fix-aac.py <out_dir> <take.aac> [<take.aac> ...]   ->   <out_dir>/<stem>.wav
"""
import os
import subprocess
import sys
import tempfile

FIX_INDEX = 4          # 44.1 kHz band tables
PLAY_RATE = 96000      # true playback rate of the mislabelled takes: the header's own rate


def adts_index(data: bytes) -> int:
    if len(data) < 7 or data[0] != 0xFF or (data[1] & 0xF6) != 0xF0:
        raise SystemExit("not an ADTS stream")
    return (data[2] >> 2) & 0x0F


def patch_index(data: bytes, idx: int) -> bytes:
    b = bytearray(data)
    i = 0
    while i + 7 <= len(b):
        if b[i] != 0xFF or (b[i + 1] & 0xF6) != 0xF0:
            raise SystemExit(f"lost ADTS sync at byte {i}")
        length = ((b[i + 3] & 0x03) << 11) | (b[i + 4] << 3) | (b[i + 5] >> 5)
        if length < 7:
            raise SystemExit(f"bad frame length at byte {i}")
        b[i + 2] = (b[i + 2] & 0xC3) | (idx << 2)
        i += length
    return bytes(b)


def ffmpeg(args):
    p = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *args], capture_output=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stderr


def duration(path):
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                       capture_output=True, encoding="utf-8", errors="replace")
    return float(p.stdout.strip() or 0)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    for src in sys.argv[2:]:
        stem = os.path.splitext(os.path.basename(src))[0]
        dst = os.path.join(out_dir, stem + ".wav")
        data = open(src, "rb").read()
        idx = adts_index(data)
        code, err = ffmpeg(["-i", src, "-f", "null", "-"])
        if idx == 0 and err.strip():
            with tempfile.TemporaryDirectory() as tmp:
                fixed = os.path.join(tmp, "fixed.aac")
                open(fixed, "wb").write(patch_index(data, FIX_INDEX))
                code, err = ffmpeg(["-i", fixed, "-af", f"asetrate={PLAY_RATE},aresample=48000", "-ac", "1", "-c:a", "pcm_s16le", dst])
            how = "header fixed, played at 96 kHz"
        else:
            code, err = ffmpeg(["-i", src, "-af", "aresample=48000", "-ac", "1", "-c:a", "pcm_s16le", dst])
            how = "converted"
        if code != 0 or err.strip():
            sys.exit(f"{src}: ffmpeg failed:\n{err}")
        print(f"{stem}: {how}, {duration(dst):.2f} s -> {dst}")


if __name__ == "__main__":
    main()
