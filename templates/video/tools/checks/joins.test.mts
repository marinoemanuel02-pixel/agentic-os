// node --no-warnings --test tools/checks/joins.test.mts
import test from "node:test";
import assert from "node:assert/strict";
import { checkJoins, classify } from "./joins.mts";

const A = { pos: [0, 2, 8], target: [0, 1.5, 0], fov: 32 } as const;
const near = { pos: [0.3, 2, 8], target: [0.2, 1.5, 0], fov: 32 } as const;
const far = { pos: [9, 2.4, 7.8], target: [9, 1.75, 0], fov: 30 } as const;
type P = { pos: [number, number, number]; target: [number, number, number]; fov: number };
const p = (x: typeof A | typeof near | typeof far) => x as unknown as P;

test("classify: identical, slightly moved, reframed", () => {
  assert.equal(classify(p(A), p(A)), "same");
  assert.equal(classify(p(A), p(near)), "jump");
  assert.equal(classify(p(A), p(far)), "different");
});

test("a dissolve between two different framings fails", () => {
  const errs = checkJoins([["S08", 10, "c"], ["S09", 20, "x"]], { S08: { start: p(A), end: p(A) }, S09: { start: p(far), end: p(far) } });
  assert.equal(errs.length, 1);
  assert.match(errs[0], /dissolve between different framings/);
});

test('malformed and non-finite poses fail even at cuts; omitted fov matches the shared default', () => {
  for (const pose of [{...p(A), pos: [Infinity, 2, 8]}, {...p(A), target: [0, 1]}]) {
    assert.match(checkJoins([['a', 10, 'c'], ['b', 10, 'c']], {a: {start: p(A), end: p(A)}, b: {start: pose, end: pose}} as any).join('\n'), /invalid pose/);
  }
  assert.equal(classify({...p(A), fov: undefined}, {...p(A), fov: 30}), 'same');
});

test("a dissolve between matched poses passes; a cut may reframe or match", () => {
  assert.deepEqual(checkJoins([["S08", 10, "c"], ["S09", 20, "x"]], { S08: { start: p(far), end: p(A) }, S09: { start: p(A), end: p(far) } }), []);
  assert.deepEqual(checkJoins([["S01", 10, "c"], ["S02", 20, "c"]], { S01: { start: p(A), end: p(A) }, S02: { start: p(far), end: p(far) } }), []);
  assert.deepEqual(checkJoins([["S01", 10, "c"], ["S02", 20, "c"]], { S01: { start: p(far), end: p(A) }, S02: { start: p(A), end: p(far) } }), []);
});

test("a cut that barely moves the camera is a jump cut", () => {
  const errs = checkJoins([["S01", 10, "c"], ["S02", 20, "c"]], { S01: { start: p(A), end: p(A) }, S02: { start: p(near), end: p(near) } });
  assert.match(errs[0], /jump cut/);
});

test("a shot without join poses fails", () => {
  assert.match(checkJoins([["S01", 10, "c"]], {})[0], /no start\/end poses/);
});
