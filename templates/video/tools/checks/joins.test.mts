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

// Per-shot pose files: a shot imports only src/shots/poses/<id>.ts, so one pose edit re-renders one shot
// (alignment-now v6: one global joins.ts in every 3D shot's imports re-rendered all of them for any pose change).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadPoses, poseImportErrors } from "./joins.mts";

const film = () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "joins-poses-"));
  const put = (p: string, s: string) => { fs.mkdirSync(path.dirname(path.join(root, p)), { recursive: true }); fs.writeFileSync(path.join(root, p), s); };
  const pose = (x: number) => `export const poses = {start: {pos: [${x}, 2, 8], target: [0, 1, 0], fov: 32}, end: {pos: [${x}, 2, 8], target: [0, 1, 0], fov: 32}};\n`;
  put("src/shots/poses/S01.ts", pose(0));
  put("src/shots/poses/S02.ts", pose(9));
  put("src/shots/S01One.tsx", 'import {poses} from "./poses/S01.ts";\nexport const S01One = () => poses;\n');
  put("src/shots/Chapter.tsx", 'import {poses} from "./poses/S02";\nexport const S02Two = () => poses;\n');
  put("src/lib/Stage.tsx", "export const Stage = () => null;\n");
  return { root, put };
};

test("poses load from one file per shot; a missing file is reported as missing poses", async () => {
  const { root } = film();
  const joins = await loadPoses(root, ["S01", "S02", "S03"]);
  assert.deepEqual(Object.keys(joins).sort(), ["S01", "S02"]);
  assert.equal(joins.S02.start.pos[0], 9);
  assert.match(checkJoins([["S03", 10, "c"]], joins)[0], /no start\/end poses in src\/shots\/poses\/S03\.ts/);
});

test("shots that import only their own pose files pass", () => {
  assert.deepEqual(poseImportErrors(film().root), []);
});

test("a shared stage that imports poses, a shot that imports another shot's poses, or an aggregate pose table fail", () => {
  const { root, put } = film();
  put("src/lib/Stage.tsx", 'import {poses} from "../shots/poses/S01";\nexport const Stage = () => poses;\n');
  put("src/shots/S01One.tsx", 'import {poses} from "./poses/S01.ts";\nimport {poses as b} from "./poses/S02.ts";\nexport const S01One = () => [poses, b];\n');
  put("src/shots/S03Three.tsx", 'import {JOINS} from "./joins";\nexport const S03Three = () => JOINS;\n');
  const errs = poseImportErrors(root).join("\n");
  assert.match(errs, /src\/lib\/Stage\.tsx imports poses\/S01/);
  assert.match(errs, /src\/shots\/S01One\.tsx imports poses\/S02/);
  assert.match(errs, /src\/shots\/S03Three\.tsx imports the shared pose table/);
});

test("a pose barrel (poses/index or the poses folder) and a pose file importing other poses fail (Codex review)", () => {
  const { root, put } = film();
  put("src/shots/poses/index.ts", 'export * from "./S01.ts";\nexport {poses as S02} from "./S02.ts";\n');
  put("src/shots/S01One.tsx", 'import {poses} from "./poses/index.ts";\nexport const S01One = () => poses;\n');
  put("src/shots/Chapter.tsx", 'import {S02} from "./poses";\nexport const S02Two = () => S02;\n');
  const errs = poseImportErrors(root).join("\n");
  assert.match(errs, /src\/shots\/S01One\.tsx imports a pose barrel/);
  assert.match(errs, /src\/shots\/Chapter\.tsx imports a pose barrel/);
  assert.match(errs, /src\/shots\/poses\/index\.ts imports other pose files/);
});
