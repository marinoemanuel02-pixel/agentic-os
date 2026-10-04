import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as manifest from './input-manifest.mjs';

test('changing or removing the dated currency evidence invalidates the sealed input identity', () => {
  assert.equal(typeof manifest.projectEvidenceFiles, 'function');
  const scratch = process.env.AOS_VIDEO_TEST_ROOT || path.join(os.homedir(), '.aos/scratch/input-evidence-tests');
  fs.mkdirSync(scratch, {recursive:true});
  const root = fs.mkdtempSync(path.join(scratch, 'case '));
  for (const name of ['script.md', 'sources.md', 'qa.env', 'claims.json', 'currency.json']) fs.writeFileSync(path.join(root, name), name);
  const options = () => ({files:manifest.projectEvidenceFiles(root)});
  const before = manifest.snapshot(options());
  assert.ok(before.entries.some(x => x.path === 'currency.json'));
  fs.writeFileSync(path.join(root, 'currency.json'), 'changed retrieval or claim');
  assert.throws(() => manifest.assertSameInputs(before, manifest.snapshot(options())), /Inputs changed: currency.json/);
  fs.unlinkSync(path.join(root, 'currency.json'));
  assert.throws(() => manifest.assertSameInputs(before, manifest.snapshot(options())), /Inputs changed: currency.json/);
});
