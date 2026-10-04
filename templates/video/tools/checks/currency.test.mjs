// Currency gate fixtures exercise each refusal through its CLI.
// The test owns a private JSON copy, so production research is never changed.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync, mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const GOOD = JSON.parse(readFileSync(new URL('./fixtures/currency/good.json', import.meta.url)));
const SCRIPT = fileURLToPath(new URL('./currency.mjs', import.meta.url));
const TODAY = '2026-10-03';

function run(data, claims) {
  const dir = mkdtempSync(join(tmpdir(), 'currency-test-'));
  try {
    const file = join(dir, 'currency.json');
    writeFileSync(file, JSON.stringify(data));
    const args = [SCRIPT, file, '--today', TODAY];
    if (claims) {
      const ledger = join(dir, 'claims.json');
      writeFileSync(ledger, JSON.stringify(claims));
      args.push('--claims', ledger);
    }
    return spawnSync(process.execPath, args, {encoding:'utf8'});
  } finally {
    rmSync(dir, {recursive:true, force:true});
  }
}

test('current complete fixture passes', () => assert.equal(run(GOOD).status, 0));

const cases = [
  ['duplicate id', d => d.items[1].id = 'C01', /duplicate id: C01/],
  ['invalid tag', d => d.items[0].tag = 'label', /invalid tag: C01/],
  ['malformed date', d => d.items[0].sourceDate = '2026-9-1', /invalid sourceDate: C01/],
  ['future date', d => d.items[0].sourceDate = '2026-10-04', /future sourceDate: C01/],
  ['stale retrieval', d => d.items[0].retrieved = '2026-09-29', /stale: re-verify C01/],
  ['old source', d => d.items[0].sourceDate = '2026-05-01', /too old for 'now': C01/],
  ['contested with no counter', d => delete d.items[1].counter, /contested needs two sources or both voices: C02/],
  ['contested with unknown counter', d => d.items[1].counter = ['missing'], /unknown counter: C02/],
];

for (const field of ['id','tag','camp','claim','url','sourceDate','retrieved','version','anchor']) {
  test(`missing required ${field}`, () => {
    const data = structuredClone(GOOD);
    delete data.items[0][field];
    const result = run(data);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, new RegExp(`missing ${field}:`));
  });
}

for (const [name, mutate, message] of cases) {
  test(name, () => {
    const data = structuredClone(GOOD);
    mutate(data);
    const result = run(data);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout + result.stderr, message);
  });
}

test('claim references and required coverage fail, optional coverage stays informational', () => {
  const data = structuredClone(GOOD);
  const result = run(data, {lines:[{currency:'missing'},{needsCurrency:true}],screen:[{currency:'C01'}]});
  assert.equal(result.status, 1);
  assert.match(result.stdout, /unknown currency id: missing/);
  assert.match(result.stdout, /needsCurrency without currency/);
  assert.equal(run(data, {lines:[{text:'no marker'}],screen:[]}).status, 0);
});
