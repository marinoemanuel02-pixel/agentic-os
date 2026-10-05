// A loopback HTTP server gives deterministic page and error responses.
// Tests exercise the CLI and inspect each successfully verified row.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createServer} from 'node:http';
import {mkdtempSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const SCRIPT = fileURLToPath(new URL('./reverify.mjs', import.meta.url));
const TODAY = '2026-10-03';

function run(args) {
  return new Promise(resolve => {
    const child = spawn(process.execPath, [SCRIPT, ...args]);
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => stdout += chunk);
    child.stderr.on('data', chunk => stderr += chunk);
    child.on('close', status => resolve({status, stdout, stderr}));
  });
}

test('finds normalized anchor, reports changed pages, and requires browser confirmation', async () => {
  const server = createServer((req, res) => {
    res.statusCode = req.url === '/error' ? 503 : 200;
    res.end(req.url === '/good' ? '<script>noise</script><p>Evidence &amp; &ldquo;context&rdquo;</p>' : '<p>Different text</p>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const dir = mkdtempSync(join(tmpdir(), 'reverify-test-'));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const file = join(dir, 'currency.json');
    const items = [
      {id:'C01', url:`${base}/good`, fetch:'curl', anchor:'Evidence & "context"', retrieved:'2026-09-01'},
      {id:'C02', url:`${base}/bad`, fetch:'curl', anchor:'missing', retrieved:'2026-09-01'},
      {id:'C03', url:`${base}/browser`, fetch:'browser', anchor:'manual anchor', retrieved:'2026-09-01'},
      {id:'C04', url:`${base}/error`, fetch:'curl', anchor:'unavailable', retrieved:'2026-09-01'},
    ];
    writeFileSync(file, JSON.stringify({items}));
    const bad = await run([file, '--today', TODAY, '--write']);
    assert.equal(bad.status, 1, bad.stderr);
    assert.match(bad.stdout, /CHANGED C02/);
    assert.match(bad.stdout, /CHANGED C04/);
    assert.match(bad.stdout, /BROWSER C03/);
    assert.equal(JSON.parse(readFileSync(file)).items[0].retrieved, TODAY);
    assert.equal(JSON.parse(readFileSync(file)).items[1].retrieved, '2026-09-01');
    items.splice(1, 1);
    items.splice(2, 1);
    writeFileSync(file, JSON.stringify({items}));
    const good = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--write']);
    assert.equal(good.status, 0, good.stderr);
    const saved = JSON.parse(readFileSync(file)).items;
    assert.equal(saved[0].retrieved, TODAY);
    assert.deepEqual(saved[0].reverified, [{date:TODAY, result:'ok'}]);
    assert.equal(saved[1].retrieved, TODAY);
  } finally {
    server.close();
    rmSync(dir, {recursive:true, force:true});
  }
});

// Retro 32: a recheck must leave proof. With --evidence, each page gets <id>.txt: URL, time, length, the SHA-256 of
// its full normalized text and a short excerpt around the anchor (no full copy of the article); the hash is recorded
// in the ledger. A browser row passes only with such a file, saved from the browser, that contains its anchor.
test('--evidence keeps each page text with its hash and checks browser rows against their saved text', async () => {
  const {createHash} = await import('node:crypto');
  const {existsSync, mkdirSync} = await import('node:fs');
  const server = createServer((req, res) => { res.statusCode = 200; res.end('<p>Evidence &amp; more</p>'); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const dir = mkdtempSync(join(tmpdir(), 'reverify-evidence-'));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const file = join(dir, 'currency.json');
    const ev = join(dir, 'evidence');
    const items = [
      {id:'C01', url:`${base}/good`, fetch:'curl', anchor:'Evidence & more', retrieved:'2026-09-01'},
      {id:'C03', url:`${base}/browser`, fetch:'browser', anchor:'manual anchor', retrieved:'2026-09-01'},
    ];
    writeFileSync(file, JSON.stringify({items}));
    const noText = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--evidence', ev, '--write']);
    assert.equal(noText.status, 1, 'a confirmed browser row without saved page text fails');
    assert.match(noText.stdout, /BROWSER C03 .*no saved page text/);
    mkdirSync(ev, {recursive: true});
    writeFileSync(join(ev, 'C03.txt'), ['url: ' + base + '/browser', 'captured: ' + TODAY + 'T09:00:00Z', 'via: browser', 'sha256: ' + 'a'.repeat(64), 'excerpt: page text with the manual anchor in it'].join('\n') + '\n');
    writeFileSync(file, JSON.stringify({items}));
    const ok = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--evidence', ev, '--write']);
    assert.equal(ok.status, 0, ok.stdout + ok.stderr);
    assert.ok(existsSync(join(ev, 'C01.txt')));
    const kept = readFileSync(join(ev, 'C01.txt'), 'utf8');
    assert.match(kept, /^excerpt: .*Evidence & more/m);
    const saved = JSON.parse(readFileSync(file)).items;
    const sha = (t) => createHash('sha256').update(t).digest('hex');
    assert.deepEqual(saved[0].reverified.at(-1), {date: TODAY, result: 'ok', evidence: 'C01.txt', sha256: sha('Evidence & more')});
    assert.match(kept, new RegExp('^sha256: ' + sha('Evidence & more') + '$', 'm'));
    assert.equal(saved[1].reverified.at(-1).sha256, 'a'.repeat(64));
  } finally {
    server.close();
    rmSync(dir, {recursive: true, force: true});
  }
});

test('browser proof must name the row URL and today; without --evidence a browser row is recorded as unproven (Codex review)', async () => {
  const {mkdirSync} = await import('node:fs');
  const dir = mkdtempSync(join(tmpdir(), 'reverify-proof-'));
  try {
    const file = join(dir, 'currency.json');
    const ev = join(dir, 'evidence');
    mkdirSync(ev, {recursive: true});
    const items = [{id: 'C03', url: 'https://example.invalid/page', fetch: 'browser', anchor: 'manual anchor', retrieved: '2026-09-01'}];
    const proof = (url, captured) => writeFileSync(join(ev, 'C03.txt'), ['url: ' + url, 'captured: ' + captured, 'via: browser', 'sha256: ' + 'b'.repeat(64), 'excerpt: the manual anchor'].join('\n') + '\n');
    writeFileSync(file, JSON.stringify({items}));
    proof('https://example.invalid/other', TODAY + 'T10:00:00Z');
    let r = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--evidence', ev, '--write']);
    assert.equal(r.status, 1, 'a proof for another URL fails');
    proof('https://example.invalid/page', '2026-09-30T10:00:00Z');
    r = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--evidence', ev, '--write']);
    assert.equal(r.status, 1, 'an old proof fails');
    proof('https://example.invalid/page', TODAY + 'T10:00:00Z');
    r = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--evidence', ev, '--write']);
    assert.equal(r.status, 0, r.stdout);
    writeFileSync(file, JSON.stringify({items}));
    r = await run([file, '--today', TODAY, '--browser-ok', 'C03', '--write']);
    assert.equal(r.status, 0);
    assert.equal(JSON.parse(readFileSync(file)).items[0].reverified.at(-1).proof, 'none');
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
});
