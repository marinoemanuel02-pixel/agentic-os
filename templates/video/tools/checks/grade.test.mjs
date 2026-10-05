// node --test tools/checks/grade.test.mjs
// The grade must not split colour channels: lateral chromatic aberration put orange/blue fringes on every
// high-contrast edge, which viewers read as outlines around objects (alignment-now v7 verdict, retro 34).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const stage = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '../../src/lib/Stage.tsx'), 'utf8');

test('the grade samples every channel at the same UV (no chromatic aberration fringes)', () => {
  assert.doesNotMatch(stage, /texture2D\(tDiffuse,\s*vUv\s*[+-]\s*off\)/);
});

test('no half-resolution SAO pass (its depth-edge halos drew a white shape around objects)', () => {
  assert.doesNotMatch(stage, /SAOPass/);
});
