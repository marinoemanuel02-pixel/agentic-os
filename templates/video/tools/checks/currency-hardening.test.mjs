import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {checkCurrency} from './currency.mjs';

const good = JSON.parse(fs.readFileSync(new URL('./fixtures/currency/good.json', import.meta.url)));
test('empty research cannot certify a current film', () => {
  assert.ok(checkCurrency({...good, items: []}, '2026-10-03').some(x => /empty/.test(x)));
});
test('a self-only counter is not a distinct source or voice', () => {
  const data = structuredClone(good);
  data.items[1].counter = [data.items[1].id];
  assert.ok(checkCurrency(data, '2026-10-03').some(x => /distinct/.test(x)));
});
test('factual and quoted claims require a known currency mapping without opt-in markers', () => {
  for (const kind of ['fact', 'quote']) {
    const errors = checkCurrency(good, '2026-10-03', {lines: [{id:'L1', kind}], screen:[]});
    assert.ok(errors.some(x => /without currency/.test(x)), JSON.stringify(errors));
  }
});
for (const script of ['build.sh', 'qa.sh']) {
  test(`${script} refuses an unknown claim mapping before later production checks`, () => {
    const scratch = process.env.AOS_VIDEO_TEST_ROOT || path.join(os.homedir(), '.aos/scratch/currency-wiring-tests');
    fs.mkdirSync(scratch, {recursive:true});
    const root = fs.mkdtempSync(path.join(scratch, 'case '));
    const tools = path.join(root, 'tools');
    fs.mkdirSync(path.join(tools, 'checks'), {recursive:true});
    fs.copyFileSync(new URL(`../${script}`, import.meta.url), path.join(tools, script)); fs.copyFileSync(new URL('../media-root.sh', import.meta.url), path.join(tools, 'media-root.sh'));
    fs.copyFileSync(new URL('./currency.mjs', import.meta.url), path.join(tools, 'checks/currency.mjs'));
    const data = structuredClone(good);
    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
    for (const item of data.items) item.retrieved = item.sourceDate = today;
    fs.writeFileSync(path.join(root, 'currency.json'), JSON.stringify(data));
    fs.writeFileSync(path.join(root, 'claims.json'), JSON.stringify({lines:[{id:'L1', kind:'fact', currency:'absent'}], screen:[]}));
    fs.writeFileSync(path.join(tools, 'checks/claims.mjs'), "import fs from 'node:fs'; fs.writeFileSync('later-stage-ran', 'yes'); process.exitCode=42;\n");
    const bash = process.platform === 'win32' ? path.join(process.env.ProgramFiles, 'Git/bin/bash.exe') : 'bash';
    const result = spawnSync(bash, [path.join(tools, script), 'missing.mp4', 'missing.srt'], {
      cwd:root, encoding:'utf8', env:{...process.env, AOS_VIDEO_MEDIA_ROOT:path.join(root, 'private-media')}, timeout:10000,
    });
    assert.notEqual(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(path.join(root, 'later-stage-ran')), false, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, /unknown currency id/);
  });
}
