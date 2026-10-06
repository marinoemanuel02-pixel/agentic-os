// Transition timing and media windows (pure maths shared by the media components and every transition).
import assert from "node:assert/strict";
import { test } from "node:test";
import { transitionProgress, clipWindow, pushOffsets, wipeInset } from "../../src/lib/transitions/core.ts";
import { gradeFilter, LOOKS } from "../../src/lib/look.ts";

test("progress is 0 at the start, 1 at the end, monotonic and soft at both ends (R17)", () => {
  const d = 24;
  const xs = Array.from({ length: d + 1 }, (_, f) => transitionProgress(f, d));
  assert.equal(xs[0], 0);
  assert.equal(xs[d], 1);
  for (let i = 1; i <= d; i++) assert.ok(xs[i] >= xs[i - 1]);
  assert.ok(xs[1] < 0.02 && 1 - xs[d - 1] < 0.02, "soft in and out");
  assert.equal(transitionProgress(-5, d), 0);
  assert.equal(transitionProgress(99, d), 1);
});

test("a use maps to frames in media time without trimming twice", () => {
  assert.deepEqual(clipWindow({ mediaFrom: 3, mediaTo: 5 }, 30), { startFrom: 90, endAt: 150, frames: 60 });
});

test("push moves both layers by one frame width and wipe reveals left to right", () => {
  assert.deepEqual(pushOffsets(0, 1920), { from: 0, to: 1920 });
  assert.deepEqual(pushOffsets(1, 1920), { from: -1920, to: 0 });
  assert.equal(wipeInset(0), "inset(0 100% 0 0)");
  assert.equal(wipeInset(1), "inset(0 0% 0 0)");
});

test("the grade differs between looks and is a CSS filter", () => {
  const a = gradeFilter(LOOKS.studio);
  const b = gradeFilter({ ...LOOKS.studio, exposure: 1.3, vignette: 0.1 });
  assert.match(a, /^contrast\([\d.]+\) saturate\([\d.]+\) brightness\([\d.]+\)$/);
  assert.notEqual(a, b);
});
