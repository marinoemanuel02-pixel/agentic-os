// Render cache tests: segments tile the edit, keys follow transitive imports, concat keeps every frame.
// Run: node --test tools/cache/cache.test.mjs (needs ffmpeg/ffprobe on PATH for the concat case).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {segments} from './segments.mjs';
import {closure, segmentKeys} from './keys.mjs';
import {concat} from './concat.mjs';

test('segments split at cuts, merge dissolve runs and tile the edit without gaps', () => {
  const s = segments([['S01', 2, 'c'], ['S02', 3, 'x'], ['S03', 1, 'c'], ['S04', 2, 'c']], 10);
  assert.deepEqual(s.map((x) => [x.from, x.to, x.shots.join('+')]), [[0, 50, 'S01+S02'], [50, 60, 'S03'], [60, 80, 'S04']]);
});

const tree = () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cache-keys-'));
  const put = (p, s) => {fs.mkdirSync(path.dirname(path.join(root, p)), {recursive: true}); fs.writeFileSync(path.join(root, p), s);};
  put('src/lib/deep.ts', 'export const DEEP = 1;\n');
  put('src/lib/mid.tsx', 'import {DEEP} from "./deep";\nexport const MID = DEEP;\n');
  put('src/lib/a.ts', 'import {B} from "./b";\nexport const A = 1;\n');
  put('src/lib/b.ts', 'import {A} from "./a";\nexport const B = A;\n');
  put('src/data/words.json', '{"L1": []}\n');
  put('src/shots/S01One.tsx', 'import {MID} from "../lib/mid";\nexport const S01One = () => MID;\n');
  put('src/shots/S02Two.tsx', 'import words from "../data/words.json";\nexport const S02Two = () => words;\n');
  put('src/shots/Chapter.tsx', 'import {A} from "../lib/a";\nexport const S03Three = () => A;\nexport const S04Four = () => 4;\n');
  return {root, put};
};
const keysOf = (root, env = 'env') => segmentKeys(root, [{from: 0, to: 10, shots: ['S01']}, {from: 10, to: 20, shots: ['S02']}, {from: 20, to: 30, shots: ['S03']}, {from: 30, to: 40, shots: ['S04']}], env);

test('changing a shot file changes only its own segment key', () => {
  const {root, put} = tree();
  const before = keysOf(root);
  put('src/shots/S01One.tsx', 'import {MID} from "../lib/mid";\nexport const S01One = () => MID + 1;\n');
  const after = keysOf(root);
  assert.notEqual(after[0], before[0]);
  assert.deepEqual(after.slice(1), before.slice(1));
});

test('changing a library two imports down invalidates every dependent segment (regression)', () => {
  const {root, put} = tree();
  const before = keysOf(root);
  put('src/lib/deep.ts', 'export const DEEP = 2;\n');
  const after = keysOf(root);
  assert.notEqual(after[0], before[0], 'S01 imports mid -> deep');
  assert.equal(after[1], before[1], 'S02 does not import deep');
});

test('data files, the environment digest and the frame range are part of the key', () => {
  const {root, put} = tree();
  const before = keysOf(root);
  put('src/data/words.json', '{"L1": [["x", 0, 1]]}\n');
  assert.notEqual(keysOf(root)[1], before[1]);
  assert.notEqual(keysOf(root, 'other env')[2], keysOf(root)[2]);
  const shifted = segmentKeys(root, [{from: 1, to: 11, shots: ['S01']}], 'env');
  assert.notEqual(shifted[0], keysOf(root)[0]);
});

test('import cycles terminate and shots exported from a chapter file are found', () => {
  const {root} = tree();
  const files = closure(root, ['src/shots/Chapter.tsx']);
  assert.ok(files.includes('src/lib/a.ts') && files.includes('src/lib/b.ts'));
  assert.equal(keysOf(root).length, 4);
});

test('an unknown shot id is an error, never a silent cache hit', () => {
  const {root} = tree();
  assert.throws(() => segmentKeys(root, [{from: 0, to: 10, shots: ['S99']}], 'env'), /S99/);
});

test('concat keeps every frame of H.264 segments and rejects a wrong total', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cache-concat-'));
  const parts = [12, 7, 20].map((n, i) => {
    const out = path.join(dir, `p${i}.mp4`);
    execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', `testsrc=size=160x90:rate=30:duration=${n / 30}`, '-frames:v', String(n),
      '-c:v', 'libx264', '-crf', '16', '-pix_fmt', 'yuv420p', out]);
    return out;
  });
  const out = path.join(dir, 'all.mp4');
  assert.equal(concat(parts, out, 39), 39);
  assert.throws(() => concat(parts, path.join(dir, 'bad.mp4'), 40), /frame count/);
});
