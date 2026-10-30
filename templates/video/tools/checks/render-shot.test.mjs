// node --test tools/checks/render-shot.test.mjs
// tools/render-shot.py bookkeeping, without Blender: the media.json entry it writes and the files its incremental key
// hashes. huggingface-it lost both: every rendered shot played as the animatic still until the still was removed by
// hand, and a shot re-rendered only when someone added its kit files to the key.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const tool = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'render-shot.py');
const python = spawnSync('python', ['-I', '-c', 'import sys'], {encoding: 'utf8'});
const skip = python.status !== 0 && 'python is not on PATH';

/** Run `code` with the tool loaded as module m; returns its JSON print. */
const call = (code) => {
  const load = `import importlib.util, json\nspec = importlib.util.spec_from_file_location("render_shot", ${JSON.stringify(tool)})\nm = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(m)\n`;
  const p = spawnSync('python', ['-I', '-c', load + code], {encoding: 'utf8'});
  assert.equal(p.status, 0, p.stderr);
  return JSON.parse(p.stdout);
};

test('a rendered clip replaces a stale animatic still and keeps the hand-set fields', {skip}, () => {
  const old = {still: 'stills/S03.png', tag: 'Source: lab', gain: 1.2, clip: 'clips/old.mp4'};
  const entry = call(`print(json.dumps(m.clip_entry(${JSON.stringify(old)}, "S03", {"push": True})))`);
  assert.deepEqual(entry, {tag: 'Source: lab', gain: 1.2, clip: 'clips/S03.mp4', startFrom: 0, push: true});
});

test('the incremental key covers the shared kit a scene script runs, followed through the kit, and no other scene', {skip}, () => {
  const blender = fs.mkdtempSync(path.join(os.tmpdir(), 'render-kit-'));
  const put = (name, text) => fs.writeFileSync(path.join(blender, name), text);
  put('lib.py', '# shared library\n');
  put('s_lab.py', 'exec(open(os.path.join(BLENDER_DIR, "sf_incident.py"), encoding="utf-8").read())\n');
  put('sf_incident.py', 'exec(open(os.path.join(BLENDER_DIR, "toylib.py")).read())  # sets drawn like s_toy.py\n');
  put('toylib.py', 'STYLE = "sf_styleframes.py"\n');
  put('sf_styleframes.py', '# the frames s_toy.py was built from\n');
  put('s_toy.py', 'exec(open("sf_styleframes.py").read())\n');
  put('unused.py', '# never named by the lab\n');
  const files = call(`print(json.dumps(m.kit_files(m.Path(${JSON.stringify(blender)}), "s_lab.py")))`);
  assert.deepEqual(files, ['s_lab.py', 'lib.py', 'sf_incident.py', 'toylib.py', 'sf_styleframes.py']);
});
