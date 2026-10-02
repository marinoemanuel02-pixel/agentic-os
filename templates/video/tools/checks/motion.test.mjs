// Labelled examples for the motion check: node --test tools/checks/motion.test.mjs
// A move's per-frame change is proportional to its speed, so a series of frame differences is |p(t) - p(t-1)|
// times the moved area. Soft moves must pass; expo-out moves must be flagged; blinks, cuts and camera drift must
// not be mistaken for snaps.
import assert from "node:assert/strict";
import test from "node:test";
import { excluded, findSnaps, OPTS, scanSource, snapsInSeries } from "./motion.mjs";

// cubic-bezier easing like CSS / Remotion's Easing.bezier
const bezier = (x1, y1, x2, y2) => (x) => {
  const cx = (t, a, b) => 3 * a * t * (1 - t) ** 2 + 3 * b * t * t * (1 - t) + t ** 3;
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (cx(mid, x1, x2) < x) lo = mid;
    else hi = mid;
  }
  return cx((lo + hi) / 2, y1, y2);
};
const SOFT = bezier(0.45, 0, 0.55, 1);
const EXPO_OUT = bezier(0.16, 1, 0.3, 1);

/** Difference series: rest, then a move of `frames` frames with easing `ease` and size `amp`, then rest. */
const move = (ease, frames, amp, { pre = 20, post = 30, base = 0.2 } = {}) => {
  const d = [];
  for (let i = 0; i < pre; i++) d.push(base);
  for (let i = 1; i <= frames; i++) d.push(base + amp * Math.abs(ease(i / frames) - ease((i - 1) / frames)) * frames);
  for (let i = 0; i < post; i++) d.push(base);
  return d;
};
const never = () => false;

test("a soft move of 24 frames is not a snap", () => {
  assert.deepEqual(snapsInSeries(move(SOFT, 24, 6), 0.2, never), []);
});

test("a large soft move of 18 frames is not a snap", () => {
  assert.deepEqual(snapsInSeries(move(SOFT, 18, 14), 0.2, never), []);
});

test("a very large soft move is not a snap even when its first frame already changes a lot", () => {
  const d = move(SOFT, 18, 60);
  assert.ok(d[20] - 0.2 > OPTS.peak, "the first moving frame clears the change threshold");
  assert.deepEqual(snapsInSeries(d, 0.2, never), []);
});

test("an expo-out move of 14 frames is a snap at its first frame", () => {
  const d = move(EXPO_OUT, 14, 6);
  assert.deepEqual(snapsInSeries(d, 0.2, never), [20]);
});

test("an expo-out move of 24 frames is still a snap", () => {
  assert.equal(snapsInSeries(move(EXPO_OUT, 24, 6), 0.2, never).length, 1);
});

test("a linear move that starts at full speed is a snap", () => {
  assert.equal(snapsInSeries(move((x) => x, 30, 4), 0.2, never).length, 1);
});

test("a blink (three frames of change) is an accent, not a snap", () => {
  const d = Array(40).fill(0.2);
  d[20] = 8;
  d[21] = 9;
  d[22] = 6;
  assert.deepEqual(snapsInSeries(d, 0.2, never), []);
});

test("a cut is excluded even when the next shot starts with a moving camera", () => {
  const d = [...Array(20).fill(0.2), ...Array(30).fill(12)];
  assert.deepEqual(snapsInSeries(d, 0.2, excluded([[20, 21]])), []);
  assert.equal(snapsInSeries(d, 0.2, never).length, 1);
});

test("a soft move over a slow camera drift is not a snap; an expo move over the same drift is", () => {
  const drift = 1.4;
  const soft = move(SOFT, 24, 6, { base: drift });
  const expo = move(EXPO_OUT, 14, 6, { base: drift });
  assert.deepEqual(snapsInSeries(soft, drift, never), []);
  assert.equal(snapsInSeries(expo, drift, never).length, 1);
});

test("findSnaps merges one move seen by several tiles into one hit", () => {
  const a = move(EXPO_OUT, 14, 6);
  const b = move(EXPO_OUT, 14, 6);
  const quiet = Array(a.length).fill(0.2);
  const hits = findSnaps([a, b, quiet], [], OPTS);
  assert.equal(hits.length, 1);
  assert.deepEqual(hits[0].tiles, [0, 1]);
});

test("scanSource flags expo-out and overshoot curves, and passes soft ones", () => {
  const src = [
    "const a = Easing.bezier(0.16, 1, 0.3, 1);",
    "const b = Easing.bezier(0.34, 1.56, 0.64, 1);",
    "const c = Easing.bezier(0.45, 0, 0.55, 1);",
    "const d = Easing.out(Easing.exp);",
    "const e = Easing.inOut(Easing.cubic);",
  ].join("\n");
  assert.deepEqual(
    scanSource(src).map(([line]) => line),
    [1, 2, 4],
  );
});
