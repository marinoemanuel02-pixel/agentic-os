// Caption timing (src/lib/caption-timing.ts), ported from huggingface-it v6: chunks, shared boxes, swaps on the same frame,
// cards that carry their own type, and the readable-time share the frontier asks the next fast short to beat.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildChunks, captionsAt, chunksOf, readableShare, runsOf, TALL_TIMING, type WordTuple } from "../../src/lib/caption-timing.ts";

const FPS = 30;
const T = TALL_TIMING;
const ws = (text: string, start = 0, step = 0.25) =>
  text.split(" ").map((w, i): WordTuple => [w, start + i * step, start + i * step + step * 0.9]);

test("a chunk keeps rows under the character limit and ends after two rows or at a full stop", () => {
  const words = ws("one two three four five six seven eight nine ten eleven. twelve").map(([w, a, b]) => ({ w, a, b }));
  const chunks = chunksOf(words, T);
  for (const c of chunks) {
    assert.ok(c.rows.length <= T.rows);
    for (const r of c.rows) assert.ok(r.map((x) => x.w).join(" ").length <= T.maxChars, r.map((x) => x.w).join(" "));
  }
  const ends = chunks.map((c) => c.rows.flat().at(-1)!.w);
  assert.ok(ends.includes("eleven."), "a full stop closes its chunk");
  assert.equal(chunks.at(-1)!.rows.flat()[0].w, "twelve");
});

test("words are placed on the film clock from their line's start frame", () => {
  const chunks = buildChunks([{ id: "L2", from: 60 }], { L2: [["hello", 0.5, 0.9]] }, FPS, T);
  assert.equal(chunks[0].from, 60 / FPS + 0.5);
  assert.equal(chunks[0].to, 60 / FPS + 0.9 + T.tail, "nothing follows: the chunk stays `tail` after its last word");
});

test("chunks closer than the gap share one box, a longer pause starts a new one", () => {
  const words = { L1: ws("first chunk here. second chunk here."), L2: ws("after a pause.") };
  const chunks = buildChunks([{ id: "L1", from: 0 }, { id: "L2", from: 6 * FPS }], words, FPS, T);
  const runs = runsOf(chunks);
  assert.equal(chunks[0].to, chunks[1].from, "close chunks hand over");
  assert.deepEqual(runs, [[0, 1], [2, 2]]);
});

test("inside a run the next chunk replaces the last on the same frame: no empty or half-faded frame", () => {
  const chunks = buildChunks([{ id: "L1", from: 0 }], { L1: ws("one two three four five. six seven eight nine ten. eleven twelve.") }, FPS, T);
  const runs = runsOf(chunks);
  assert.equal(runs.length, 1);
  const start = chunks[0].from;
  const end = chunks.at(-1)!.to;
  for (let f = Math.ceil(start * FPS); f < end * FPS; f++) {
    const { box, shown } = captionsAt(chunks, runs, f / FPS, T);
    assert.ok(box >= 0.99, `box full at frame ${f}`);
    assert.ok(shown.some((s) => s.o >= 0.99), `a whole chunk shows at frame ${f}`);
  }
});

test("the box fades in before the first word and out after the run, never in one frame", () => {
  const chunks = buildChunks([{ id: "L1", from: 30 }], { L1: ws("just one line.") }, FPS, T);
  const runs = runsOf(chunks);
  const halfIn = captionsAt(chunks, runs, chunks[0].from - T.boxFade / 2, T).box;
  assert.ok(halfIn > 0.2 && halfIn < 0.8, `mid fade ${halfIn}`);
  assert.equal(captionsAt(chunks, runs, chunks[0].from - T.boxFade - 0.01, T).box, 0);
  assert.equal(captionsAt(chunks, runs, chunks[0].to + T.boxFade + 0.01, T).box, 0);
});

test("a chunk that starts on a card with its own type is left to the card", () => {
  const shots = [{ id: "S01", from: 0, frames: 60 }, { id: "S02", from: 60, frames: 60 }];
  const words = { L1: ws("spoken over the scene."), L2: ws("spoken over the card.") };
  const lines = [{ id: "L1", from: 0 }, { id: "L2", from: 70 }];
  const all = buildChunks(lines, words, FPS, T, shots);
  const kept = buildChunks(lines, words, FPS, T, shots, ["S02"]);
  assert.equal(all.length, 2);
  assert.equal(kept.length, 1);
  assert.equal(kept[0].rows.flat()[0].w, "spoken");
});

test("readable time: continuous narration in one run is fully readable, a line with no words counts as nothing", () => {
  const chunks = buildChunks([{ id: "L1", from: 0 }], { L1: ws("one two three four five. six seven eight nine ten.") }, FPS, T);
  assert.equal(readableShare(chunks, T, FPS), 1);
  assert.equal(readableShare([], T, FPS), 1);
  const slowSwap = { ...T, swap: 0.25 };
  assert.ok(readableShare(chunks, slowSwap, FPS) < 1, "a 0.25 s swap leaves narrated frames half faded (allineamento's timing at hf's pace)");
});
