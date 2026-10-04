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
