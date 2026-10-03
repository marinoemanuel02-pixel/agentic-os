// node --no-warnings --test tools/checks/review-sheets.test.mts
import test from "node:test";
import assert from "node:assert/strict";
import { sampleFrames, timestamp } from "../review-sheets.mts";

const shots = [
  { id: "S01", from: 0, frames: 100, xin: 0, tail: 20 },
  { id: "S02", from: 100, frames: 200, xin: 20, tail: 0 },
];

test("every shot is sampled inside its own slot at 20, 50 and 85 percent", () => {
  const s = sampleFrames(shots).shots;
  assert.deepEqual(s.map((x) => [x.name, x.frame]), [
    ["S01-20", 20], ["S01-50", 50], ["S01-85", 85], ["S02-20", 140], ["S02-50", 200], ["S02-85", 270],
  ]);
  for (const x of s) assert.ok(x.frame >= shots.find((h) => h.id === x.shot)!.from && x.frame < 300);
});

test("a dissolve is sampled just before it starts and 10 and 22 frames into it, only for shots that dissolve in", () => {
  const d = sampleFrames(shots).dissolves;
  assert.deepEqual(d.map((x) => [x.name, x.frame]), [["S02-pre", 98], ["S02-mid", 110], ["S02-late", 122]]);
});

test("a timestamp lands inside the frame, not on the edge between two frames", () => {
  assert.equal(timestamp(30, 30), (30.5 / 30).toFixed(4));
  assert.equal(timestamp(0, 30), (0.5 / 30).toFixed(4));
});

test("a plan with no shots fails loudly", () => {
  assert.throws(() => sampleFrames([]), /no shots/);
});
