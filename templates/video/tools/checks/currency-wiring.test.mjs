// Exercise the production entry points before any renderer or media dependency is reached.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';

for (const script of ['build.sh', 'qa.sh']) {
  for (const scenario of ['missing', 'ambient exception', 'declared exception', 'invalid despite exception']) {
    test(`${script}: ${scenario} currency ledger`, () => {
      const scratch = process.env.AOS_VIDEO_TEST_ROOT || path.join(os.homedir(), '.aos/scratch/template-currency-wiring');
      fs.mkdirSync(scratch, {recursive:true});
      const root = fs.mkdtempSync(path.join(scratch, 'case '));
      const tools = path.join(root, 'tools');
      fs.mkdirSync(path.join(tools, 'checks'), {recursive:true});
      fs.copyFileSync(new URL(`../${script}`, import.meta.url), path.join(tools, script));
      fs.copyFileSync(new URL('./currency.mjs', import.meta.url), path.join(tools, 'checks/currency.mjs'));
      fs.writeFileSync(path.join(root, 'claims.json'), '{"lines":[],"screen":[]}');
      fs.writeFileSync(path.join(root, 'qa.env'), scenario.includes('declared') || scenario.includes('despite') ? 'CURRENCY=none\n' : 'QA_MIN_S=60\n');
      if (scenario.includes('invalid')) fs.writeFileSync(path.join(root, 'currency.json'), '{"policy":{"reverifyWithinDays":3,"defaultMaxSourceAgeDays":120},"items":[]}');
      fs.writeFileSync(path.join(tools, 'checks/claims.mjs'), "import fs from 'node:fs'; fs.writeFileSync('later-stage-ran', 'yes'); process.exitCode=42;\n");
      const bash = process.platform === 'win32' ? path.join(process.env.ProgramFiles, 'Git/bin/bash.exe') : 'bash';
      const result = spawnSync(bash, [path.join(tools, script), 'missing.mp4', 'missing.srt'], {
        cwd:root, encoding:'utf8', env:{...process.env, CURRENCY:scenario.includes('ambient') ? 'none' : '', AOS_VIDEO_MEDIA_ROOT:path.join(root, 'private-media')}, timeout:10000,
      });
      assert.equal(result.signal, null, result.stderr);
      assert.notEqual(result.status, 0, result.stdout + result.stderr);
      assert.equal(fs.existsSync(path.join(root, 'later-stage-ran')), scenario === 'declared exception', result.stdout + result.stderr);
      if (scenario === 'declared exception') assert.match(result.stdout + result.stderr, /timeless topic/);
      else assert.match(result.stdout + result.stderr, scenario.includes('invalid') ? /empty currency items/ : /currency.json missing/);
    });
  }
}
