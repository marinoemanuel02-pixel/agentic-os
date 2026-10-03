// node --no-warnings --test tools/checks/review-sheets.test.mts
import test from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { isMain, limitToFrames, resolveOutDir, sampleFrames, timestamp } from "../review-sheets.mts";

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

test("a partial cut is sampled only where it has frames, and the rest is reported", () => {
  const r = limitToFrames(sampleFrames(shots), 150);
  assert.deepEqual(r.plan.shots.map((x) => x.name), ["S01-20", "S01-50", "S01-85", "S02-20"]);
  assert.deepEqual(r.plan.dissolves.map((x) => x.name), ["S02-pre", "S02-mid", "S02-late"]);
  assert.deepEqual(r.skipped, ["S02-50", "S02-85"]);
});

test("sheets go under the media root and never into the checkout", () => {
  const media = path.join(os.tmpdir(), "aos media root"), repo = path.join(os.tmpdir(), "aos repo");
  assert.equal(resolveOutDir(media, repo, undefined, "cut"), path.join(media, "frames", "review-cut"));
  assert.equal(resolveOutDir(media, repo, path.join(media, "mine"), "cut"), path.join(media, "mine"));
  assert.throws(() => resolveOutDir(media, repo, path.join(os.tmpdir(), "elsewhere"), "cut"), /outside the media root/);
  assert.throws(() => resolveOutDir(repo, repo, path.join(repo, "frames"), "cut"), /inside the checkout/);
  assert.throws(() => resolveOutDir(media, repo, path.join(media, "..", "x"), "cut"), /outside the media root/);
});

test("the main-module guard works in a path with spaces (the percent-encoded URL case)", () => {
  const file = path.join(os.tmpdir(), "a folder with spaces", "review-sheets.mts");
  const url = pathToFileURL(file).href;
  assert.match(url, /%20/);
  assert.equal(isMain(url, file), true);
  assert.equal(isMain(url, file + ".other"), false);
  assert.equal(isMain(url, undefined), false);
});
