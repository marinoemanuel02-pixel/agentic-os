// node --test tools/checks/grade.test.mjs
// The grade must not split colour channels: lateral chromatic aberration put orange/blue fringes on every
// high-contrast edge, which viewers read as outlines around objects (alignment-now v7 verdict, retro 34).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const lib = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../src/lib');
const stage = fs.readFileSync(path.join(lib, 'Stage.tsx'), 'utf8');
const sources = (dir) => fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) =>
  e.isDirectory() ? sources(path.join(dir, e.name)) : /\.(tsx?|mts)$/.test(e.name) ? [path.join(dir, e.name)] : []);

test('the grade samples tDiffuse once, at the plain UV (no per-channel offsets, whatever they are called)', () => {
  const samples = [...stage.matchAll(/texture2D\(\s*tDiffuse\s*,\s*([^)]*)\)/g)].map((m) => m[1].trim());
  assert.ok(samples.length >= 1, 'the grade reads tDiffuse');
  assert.deepEqual([...new Set(samples)], ['vUv'], `tDiffuse sampled at ${samples.join(', ')}`);
});

test('no SAO pass anywhere in src/lib (its depth-edge halos drew a white shape around objects)', () => {
  for (const file of sources(lib)) assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /SAOPass/, file);
});
