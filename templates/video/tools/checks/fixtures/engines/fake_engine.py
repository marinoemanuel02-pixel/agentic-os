"""A stand-in engine for engines_test.py: writes numbered grey PNGs like a real engine's frame output.
Usage: python fake_engine.py <out dir> <frames> <w> <h> <mode>; mode "steady" (grey 100 + frame index), "random"
(noise: never repeatable), "short" (one frame fewer than asked, like a crashed renderer) or "scripterror" (all
frames and exit 0, but a script error on stdout: Godot renders an empty scene when a shot script fails to parse)."""
import os
import struct
import sys
import zlib


def png(path, w, h, pixels):
    rows = b"".join(b"\x00" + pixels[y * w:(y + 1) * w] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


out, n, w, h, mode = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
os.makedirs(out, exist_ok=True)
if mode == "scripterror":
    print('SCRIPT ERROR: Parse Error: Could not resolve class "res://lib/aos_shot.gd".')
for i in range(n - 1 if mode == "short" else n):
    grey = 24 if mode == "dark" else min(220, 100 + i)  # "dark": a thin-line diagram on a near-black look
    pixels = os.urandom(w * h) if mode == "random" else bytes([grey]) * (w * h)
    png(os.path.join(out, f"frame{i}.png"), w, h, pixels)
