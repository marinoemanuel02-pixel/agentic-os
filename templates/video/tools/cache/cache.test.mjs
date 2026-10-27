// Render cache tests: segments tile the edit, keys follow transitive imports, concat keeps every frame.
// Run: node --test tools/cache/cache.test.mjs (needs ffmpeg/ffprobe on PATH for the concat case).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {segments} from './segments.mjs';
import {closure, segmentKeys, envDigest, shotClips, clipShas} from './keys.mjs';
import {concat, parseCount} from './concat.mjs';

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

test('concat accepts Git Bash style paths (/c/Users/...) from render-cached.sh', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cache-msys-'));
  const part = path.join(dir, 'p.mp4');
  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=160x90:rate=30:duration=0.4', '-frames:v', '12',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', part]);
  const msys = (p) => p.replace(/^([A-Za-z]):[\\/]/, (_, d) => `/${d.toLowerCase()}/`).replaceAll(path.sep, '/');
  if (process.platform !== 'win32') return;
  assert.equal(concat([msys(part)], msys(path.join(dir, 'out.mp4')), 12), 12);
});

test('the environment digest follows picture inputs only (fonts, public, renderer config), not audio or docs', () => {
  const base = {metadata: {remotion: '4'}, entries: [
    {path: 'fonts/a.ttf', sha256: '1'}, {path: 'public/vo/L1.wav', sha256: '2'}, {path: 'tools/remotion.config.ts', sha256: '3'},
    {path: 'audio/sfx.wav', sha256: '4'}, {path: 'claims.json', sha256: '5'}, {path: 'script.md', sha256: '6'}, {path: 'src/x.ts', sha256: '7'}]};
  const change = (p, v) => ({...base, entries: base.entries.map((e) => (e.path === p ? {...e, sha256: v} : e))});
  assert.equal(envDigest(change('audio/sfx.wav', 'x')), envDigest(base));
  assert.equal(envDigest(change('claims.json', 'x')), envDigest(base));
  assert.notEqual(envDigest(change('fonts/a.ttf', 'x')), envDigest(base));
  assert.notEqual(envDigest(change('tools/remotion.config.ts', 'x')), envDigest(base));
  assert.notEqual(envDigest({...base, metadata: {remotion: '5'}}), envDigest(base));
});

test('frame counts parse ffprobe csv with a trailing empty field ("7092,") from real exports', () => {
  assert.equal(parseCount('7092,\r\n'), 7092);
  assert.equal(parseCount('39\n'), 39);
  assert.throws(() => parseCount('N/A'), /frame count/);
});

test('a registry that imports every shot does not tie the keys together (one changed shot -> one changed key)', () => {
  const {root, put} = tree();
  put('src/shots/registry.ts', 'import {S01One} from "./S01One";\nimport {S02Two} from "./S02Two";\nimport {S03Three, S04Four} from "./Chapter";\nexport const R = {S01One, S02Two, S03Three, S04Four};\n');
  put('src/Main.tsx', 'import {R} from "./shots/registry";\nexport const Main = () => R;\n');
  const before = keysOf(root);
  put('src/shots/S01One.tsx', 'import {MID} from "../lib/mid";\nexport const S01One = () => MID + 2;\n');
  const after = keysOf(root);
  assert.notEqual(after[0], before[0]);
  assert.deepEqual(after.slice(1), before.slice(1), 'S02-S04 keys must not change when only S01 changed');
});

test('dynamic import() is followed like a static import', () => {
  const {root, put} = tree();
  put('src/lib/lazy.ts', 'export const L = 1;\n');
  put('src/shots/S02Two.tsx', 'export const S02Two = async () => (await import("../lib/lazy")).L;\n');
  const before = keysOf(root);
  put('src/lib/lazy.ts', 'export const L = 2;\n');
  assert.notEqual(keysOf(root)[1], before[1]);
});

test('a library imported by the wiring (Main.tsx -> lib/fade) changes every key; the registry still does not couple shots', () => {
  const {root, put} = tree();
  put('src/lib/fade.ts', 'export const FADE = 1;\n');
  put('src/shots/registry.ts', 'import {S01One} from "./S01One";\nimport {S02Two} from "./S02Two";\nexport const R = {S01One, S02Two};\n');
  put('src/Main.tsx', 'import {FADE} from "./lib/fade";\nimport {R} from "./shots/registry";\nexport const Main = () => [FADE, R];\n');
  const before = keysOf(root);
  put('src/lib/fade.ts', 'export const FADE = 2;\n');
  const after = keysOf(root);
  after.forEach((k, i) => assert.notEqual(k, before[i], `segment ${i} must change with Main's fade`));
  put('src/shots/S02Two.tsx', 'import words from "../data/words.json";\nexport const S02Two = () => [words, 2];\n');
  const third = keysOf(root);
  assert.equal(third[0], after[0], 'S01 must not change when only S02 changed');
  assert.notEqual(third[1], after[1]);
});

test('long segments are split into chunks of at most maxFrames (fresh render processes; S36 v6 went white after ~290 frames)', () => {
  const s = segments([['S01', 40, 'c'], ['S02', 3, 'c']], 10, 150);
  assert.ok(s.every((x) => x.to - x.from <= 150), JSON.stringify(s));
  assert.deepEqual(s.map((x) => [x.from, x.to]), [[0, 150], [150, 300], [300, 400], [400, 430]]);
  assert.ok(s.slice(0, 3).every((x) => x.shots.join() === 'S01'));
});

test('a re-rendered engine clip changes only the segment of the shot that plays it (media.json owns the clip)', () => {
  const {root, put} = tree();
  put('src/data/media.json', JSON.stringify({S02: {clip: 'clips/S02.mp4'}, S03: {clip: 'clips/S03.mp4'}}));
  const manifest = (s02) => ({metadata: {remotion: '4'}, entries: [
    {path: 'fonts/a.ttf', sha256: '1'}, {path: 'public/clips/S02.mp4', sha256: s02}, {path: 'public/clips/S03.mp4', sha256: 'c3'},
    {path: 'public/clips/loose.mp4', sha256: 'l1'}]});
  const clips = shotClips(root);
  assert.deepEqual(clips, {S02: 'public/clips/S02.mp4', S03: 'public/clips/S03.mp4'});
  const keys = (m) => segmentKeys(root, [{from: 0, to: 10, shots: ['S01']}, {from: 10, to: 20, shots: ['S02']}, {from: 20, to: 30, shots: ['S03']}],
    envDigest(m, '', Object.values(clips)), clipShas(m, clips));
  const a = keys(manifest('c2'));
  const b = keys(manifest('c2-new'));
  assert.equal(a[0], b[0]);
  assert.notEqual(a[1], b[1]);
  assert.equal(a[2], b[2]);
});

test('a public clip no media.json row owns still changes every key; a missing owned clip is keyed as missing', () => {
  const base = {metadata: {}, entries: [{path: 'public/clips/S02.mp4', sha256: 'a'}, {path: 'public/clips/loose.mp4', sha256: 'l'}]};
  const owned = ['public/clips/S02.mp4'];
  const loose = {...base, entries: base.entries.map((e) => (e.path.endsWith('loose.mp4') ? {...e, sha256: 'l2'} : e))};
  assert.notEqual(envDigest(loose, '', owned), envDigest(base, '', owned));
  assert.deepEqual(clipShas({metadata: {}, entries: []}, {S02: 'public/clips/S02.mp4'}), {S02: 'missing'});
});
