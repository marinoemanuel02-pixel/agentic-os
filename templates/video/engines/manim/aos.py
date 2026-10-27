"""Shared setup for the film's Manim shots (R56): the look from engines/look.json (written from src/lib/look.ts by
tools/export-look.mts), the template's calm in-out curve as a rate function, and finish(), which holds the last frame
until the shot has every frame tools/render-shot.py asked for. Manim owns mathematical notation; titles, labels and
captions stay in Remotion.
"""
import json
import os
from pathlib import Path

import numpy as np
from manim import ManimColor, config

LOOK = json.loads((Path(__file__).resolve().parent.parent / "look.json").read_text(encoding="utf-8"))
PALETTE = next(iter(LOOK["looks"].values()))
FPS = int(os.environ.get("AOS_FPS", LOOK["fps"]))
FRAMES = int(os.environ.get("AOS_FRAMES", "0"))  # 0 when run by hand: finish() then adds nothing
SHOT = os.environ.get("AOS_SHOT", "")
RNG = np.random.default_rng(int(os.environ.get("AOS_SEED", "1")))
MIN_MOVE = 18 / 30  # R17: nothing travels in under 0.6 s

config.background_color = ManimColor(PALETTE["bg"])
INK = ManimColor(PALETTE["ink"])
INK_SOFT = ManimColor(PALETTE["inkSoft"])
ACCENT = ManimColor(PALETTE["accent"])


def soft(x: float) -> float:
    """src/lib/ease.ts SOFT_POINTS as a Manim rate function: a CSS-style cubic bezier solved for x."""
    x1, y1, x2, y2 = LOOK["softPoints"]
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    cx, cy = 3 * x1, 3 * y1
    bx, by = 3 * (x2 - x1) - cx, 3 * (y2 - y1) - cy
    ax, ay = 1 - cx - bx, 1 - cy - by
    t = x
    for _ in range(8):
        err = ((ax * t + bx) * t + cx) * t - x
        if abs(err) < 1e-7:
            break
        d = (3 * ax * t + 2 * bx) * t + cx
        if abs(d) < 1e-7:
            break
        t -= err / d
    t = min(1.0, max(0.0, t))
    return ((ay * t + by) * t + cy) * t


def finish(scene) -> None:
    """Hold the last frame until the render has FRAMES frames (plus one spare; render-shot drops extras)."""
    remaining = FRAMES / FPS - scene.renderer.time
    if remaining > 0:
        scene.wait(remaining + 1 / FPS)
