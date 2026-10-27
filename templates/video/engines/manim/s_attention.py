"""Example shot: the attention equation becomes its weight matrix. The QK^T term lifts out of the formula into a 6x6
grid of raw scores, then each row is normalised by softmax and the scores settle into attention weights. Seeded
scores (AOS_SEED), calm curves, held to the shot length by finish().
Render by hand: manim render engines/manim/s_attention.py Attention -ql
"""
import numpy as np
from manim import DOWN, UP, FadeIn, MathTex, Scene, Square, TransformFromCopy, VGroup, Write

from aos import ACCENT, INK, INK_SOFT, MIN_MOVE, RNG, finish, soft

N = 6


class Attention(Scene):
    def construct(self):
        eq = MathTex(r"\mathrm{Attention}(Q,K,V)=", r"\mathrm{softmax}", r"\left(", r"\frac{QK^{\top}}{\sqrt{d_k}}",
                     r"\right)", r"V", color=INK).scale(1.1)
        self.play(Write(eq), run_time=2.4, rate_func=soft)
        self.wait(0.8)
        self.play(eq.animate.scale(0.7).to_edge(UP, buff=0.7), run_time=1.6, rate_func=soft)

        scores = RNG.normal(0.0, 1.4, (N, N))
        weights = np.exp(scores) / np.exp(scores).sum(axis=1, keepdims=True)
        raw = (scores - scores.min()) / (scores.max() - scores.min())
        cells = VGroup(*[Square(0.62, stroke_color=INK_SOFT, stroke_width=1.2, fill_color=ACCENT, fill_opacity=0.08 + 0.5 * raw[i, j])
                         for i in range(N) for j in range(N)])
        cells.arrange_in_grid(N, N, buff=0.08).next_to(eq, DOWN, buff=0.7)
        self.play(TransformFromCopy(eq[3], cells), run_time=2.2, rate_func=soft)
        self.wait(0.6)

        self.play(eq[1].animate.set_color(ACCENT), run_time=max(MIN_MOVE, 1.0), rate_func=soft)
        settle = [cells[i * N + j].animate.set_fill(ACCENT, opacity=min(0.95, 0.05 + 1.6 * weights[i, j]))
                  for i in range(N) for j in range(N)]
        self.play(*settle, run_time=2.6, rate_func=soft)
        self.play(FadeIn(MathTex(r"\textstyle\sum_j a_{ij}=1", color=INK_SOFT).scale(0.8).next_to(cells, DOWN, buff=0.4)),
                  run_time=1.2, rate_func=soft)
        finish(self)
