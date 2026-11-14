// Pure easing helpers (src/lib/ease.ts). mix() blends an already-eased 0..1 progress: tween(k, 0, 1, ...) would treat
// k as a frame number and stretch it over MIN_MOVE_FRAMES, so the value barely moved (pauseai-it-allineamento, 2026-10-29).
import assert from "node:assert/strict";
import { test } from "node:test";
import { mix } from "../../src/lib/ease.ts";

test("mix blends linearly between two values for a progress in 0..1", () => {
  assert.equal(mix(0, 60, 12), 60);
  assert.equal(mix(1, 60, 12), 12);
  assert.equal(mix(0.5, 60, 12), 36);
});
