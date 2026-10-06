// The asset tool core: cache, byte budget, capped fetch, measuring, proxies, registry and credits. A loopback HTTP
// server and ffmpeg-made media stand in for the network and for real clips; every film and cache is a temp folder.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import http from 'node:http';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {budgetFor, reserve, charge} from '../lib/budget.mjs';
import {fetchHttp} from '../lib/fetch.mjs';
import {measureMedia} from '../lib/measure.mjs';
import {makeProxy, makeAudio} from '../lib/proxy.mjs';
import {registryText} from '../lib/registry.mjs';
import {creditsBlock} from '../lib/credits.mjs';
import {storeObject, lookupUrl} from '../lib/cache.mjs';
import {addRow, readLedger} from '../lib/ledger.mjs';
import {withFilmLock} from '../lib/lock.mjs';

function film(approvedMB = 1) {
  const dir = join(mkdtempSync(join(tmpdir(), 'asset-core-')), 'film');
  mkdirSync(dir, {recursive: true});
  process.env.AOS_VIDEO_MEDIA_ROOT = join(dir, '..', 'media');
  process.env.AOS_ASSET_CACHE = join(dir, '..', 'cache');
  const budget = approvedMB === null ? null : {approvedMB, approvedAt: '2026-10-07', approvedBy: 'user'};
  writeFileSync(join(dir, 'sourcing.json'), JSON.stringify({schema: 1, fairUse: true, acquisition: {'*': ['direct-file']}, budget}));
  return dir;
}
function server(bytes) {
  return new Promise(res => {
    const s = http.createServer((q, r) => { r.writeHead(200, {'content-type': 'video/mp4'}); r.end(Buffer.alloc(bytes, 7)); });
    s.listen(0, '127.0.0.1', () => res({url: `http://127.0.0.1:${s.address().port}/x.mp4`, close: () => s.close()}));
  });
}
const clip = (dir, args) => { const f = join(dir, 'c.mp4'); const r = spawnSync('ffmpeg', ['-v', 'error', '-y', ...args, f]); assert.equal(r.status, 0, String(r.stderr)); return f; };

test('budget: 1 MB approved, reservations and charges count network bytes', () => {
  const d = film();
  assert.deepEqual(budgetFor(d), {approvedBytes: 1048576, usedBytes: 0});
  assert.equal(reserve(d, 600000).ok, true);
  charge(d, 600000, 'http://a', 'complete');
  assert.equal(reserve(d, 600000).ok, false);
  charge(d, 1000, 'http://b', 'failed');
  assert.equal(budgetFor(d).usedBytes, 601000);
});

test('budget: no approval means nothing may be fetched', () => {
  assert.equal(reserve(film(null), 1).ok, false);
});

test('budget: an approval not made by the user does not count', () => {
  const d = film();
  writeFileSync(join(d, 'sourcing.json'), JSON.stringify({schema: 1, budget: {approvedMB: 500, approvedBy: 'agent'}}));
  assert.equal(budgetFor(d).approvedBytes, null);
});

test('fetchHttp aborts at the cap and reports an incomplete transfer', async () => {
  const s = await server(300000);
  try {
    const dest = join(mkdtempSync(join(tmpdir(), 'f-')), 'x.mp4');
    const r = await fetchHttp(s.url, {capBytes: 100000, dest});
    assert.equal(r.complete, false);
    assert.ok(r.bytes <= 100000, `kept ${r.bytes}`);
    const ok = await fetchHttp(s.url, {capBytes: 400000, dest});
    assert.equal(ok.complete, true);
    assert.equal(ok.bytes, 300000);
  } finally { s.close(); }
});

test('a cache hit is found by URL and keeps one object', () => {
  film();
  const src = join(mkdtempSync(join(tmpdir(), 'o-')), 'a.bin');
  writeFileSync(src, 'same bytes');
  const one = storeObject(src, {url: 'http://x/a', retrieved: '2026-10-07T10:00:00Z'});
  const two = lookupUrl('http://x/a');
  assert.equal(two.sha256, one.sha256);
  assert.ok(existsSync(one.path));
  assert.equal(lookupUrl('http://x/other'), null);
});

test('fetchAsset: a cache hit charges nothing but still writes this film\'s row and evidence', async () => {
  const {fetchAsset} = await import('../asset.mjs');
  const s = await server(1000);
  try {
    const a = film(), b = film();
    const shared = mkdtempSync(join(tmpdir(), 'shared-cache-'));
    const use = d => { process.env.AOS_VIDEO_MEDIA_ROOT = join(d, '..', 'media'); process.env.AOS_ASSET_CACHE = shared; };
    const opts = {url: s.url, id: 'a01', basis: 'cc0', license: 'cc0-1.0', licenseUrl: 'https://example.org/license', acquisition: 'direct-file', platform: 'test', why: 'test need', kind: 'clip', credit: '', measure: false};
    use(a); await fetchAsset(a, opts, {fetchPage: async () => 'license page'});
    assert.equal(budgetFor(a).usedBytes, 1000);
    use(b); await fetchAsset(b, opts, {fetchPage: async () => 'license page'});
    assert.equal(budgetFor(b).usedBytes, 0);
    assert.ok(existsSync(join(b, 'research', 'rights', 'a01.json')));
    assert.equal(readLedger(b).rows[0].id, 'a01');
  } finally { s.close(); }
});

test('fetchAsset: over budget stops before writing a row', async () => {
  const {fetchAsset} = await import('../asset.mjs');
  const s = await server(300000);
  try {
    const d = film(0.1);
    const opts = {url: s.url, id: 'a02', basis: 'cc0', license: 'cc0-1.0', licenseUrl: 'https://example.org/license', acquisition: 'direct-file', platform: 'test', why: 'x', kind: 'clip', credit: '', measure: false};
    await assert.rejects(fetchAsset(d, opts, {fetchPage: async () => 'p'}), /over the film's download budget/);
    assert.equal(readLedger(d).rows.length, 0);
    assert.ok(budgetFor(d).usedBytes > 0, 'the partial transfer is still charged');
  } finally { s.close(); }
});

test('ledger refuses a duplicate id', () => {
  const d = film();
  addRow(d, {id: 'a01', kind: 'clip'});
  assert.throws(() => addRow(d, {id: 'a01', kind: 'clip'}), /a01 already in assets\.json/);
});

test('withFilmLock serializes and releases', async () => {
  const d = film();
  const order = [];
  await Promise.all([withFilmLock(d, async () => { order.push(1); await new Promise(r => setTimeout(r, 200)); order.push(2); }),
    new Promise(r => setTimeout(r, 50)).then(() => withFilmLock(d, async () => { order.push(3); }))]);
  assert.deepEqual(order, [1, 2, 3]);
});

test('measureMedia reads the real duration of a cut excerpt', () => {
  const f = clip(mkdtempSync(join(tmpdir(), 'm-')), ['-f', 'lavfi', '-i', 'testsrc=d=2.4:s=160x90:r=30', '-c:v', 'libx264']);
  const m = measureMedia(f);
  assert.ok(Math.abs(m.duration - 2.4) < 0.05, `duration ${m.duration}`);
  assert.equal(m.hasAudio, false);
  assert.equal(m.width, 160);
});

test('makeProxy writes a silent 1080p30 H.264 file and returns its hash and settings', () => {
  const dir = mkdtempSync(join(tmpdir(), 'p-'));
  const f = clip(dir, ['-f', 'lavfi', '-i', 'testsrc=d=1:s=320x180:r=25', '-f', 'lavfi', '-i', 'sine=d=1', '-shortest']);
  const out = join(dir, 'assets', 'a01.mp4');
  const p = makeProxy(f, out);
  const m = measureMedia(out);
  assert.equal(m.hasAudio, false);
  assert.equal(m.width, 1920);
  assert.equal(m.height, 1080);
  assert.match(p.sha256, /^[0-9a-f]{64}$/);
  assert.match(p.ffmpeg, /-crf 18/);
});

test('makeAudio cuts one use\'s sound into its own WAV', () => {
  const dir = mkdtempSync(join(tmpdir(), 'a-'));
  const f = clip(dir, ['-f', 'lavfi', '-i', 'testsrc=d=3:s=160x90:r=30', '-f', 'lavfi', '-i', 'sine=d=3', '-shortest']);
  const out = join(dir, 'a01.u1.wav');
  makeAudio(f, out, 1, 2.5);
  const m = measureMedia(out);
  assert.ok(Math.abs(m.duration - 1.5) < 0.05, `duration ${m.duration}`);
  assert.equal(m.hasAudio, true);
});

test('registryText uses forward slashes and sorted ids', () => {
  const t = registryText([{id: 'b2', kind: 'clip', derivatives: [{path: 'assets/b2.mp4'}]}, {id: 'a1', kind: 'model', derivatives: [{path: 'assets\\a1.glb'}]}]);
  assert.match(t, /"a1": \{ "src": "assets\/a1\.glb", "kind": "model" \},\n {2}"b2"/);
});

test('creditsBlock lists required credits once and the Poly Haven line', () => {
  const t = creditsBlock([
    {basis: 'license', license: 'cc-by-4.0', credit: 'Photo by X (CC BY 4.0)', url: 'https://commons.wikimedia.org/f'},
    {basis: 'cc0', license: 'cc0-1.0', credit: 'Model: Y', url: 'https://polyhaven.com/a/y'},
    {basis: 'cc0', license: 'cc0-1.0', credit: 'Model: Y', url: 'https://polyhaven.com/a/y2'},
    {basis: 'own', credit: '', url: null},
    {basis: 'fair-use', credit: 'Source: Lab, 2026-09-09', url: 'https://lab.example/demo'}]);
  assert.match(t, /^## Credits\n/);
  assert.equal(t.match(/Model: Y/g).length, 1);
  assert.match(t, /Photo by X \(CC BY 4\.0\)/);
  assert.match(t, /Powered by Poly Haven/);
  assert.match(t, /Source: Lab, 2026-09-09/);
});

test('proxyFilm writes a silent proxy and one WAV per audio-subject use, with hashes in the ledger', async () => {
  const {proxyFilm} = await import('../asset.mjs');
  const d = film();
  const src = clip(mkdtempSync(join(tmpdir(), 'pf-')), ['-f', 'lavfi', '-i', 'testsrc=d=3:s=320x180:r=30', '-f', 'lavfi', '-i', 'sine=d=3', '-shortest']);
  const obj = storeObject(src, {url: 'http://x/clip', retrieved: 'now'});
  addRow(d, {id: 'a01', kind: 'clip', media: {cache: `objects/${obj.sha256}.mp4`}, derivatives: [],
    uses: [{use: 'u1', audio: 'muted', mediaFrom: 0, mediaTo: 1}, {use: 'u2', audio: 'subject', mediaFrom: 1, mediaTo: 2}]});
  const row = proxyFilm(d).rows[0];
  assert.deepEqual(row.derivatives.map(x => x.path), ['assets/a01.mp4', 'assets/a01.u2.wav']);
  const pub = join(process.env.AOS_VIDEO_MEDIA_ROOT, 'app', 'public');
  assert.equal(measureMedia(join(pub, 'assets', 'a01.mp4')).hasAudio, false);
  assert.match(readLedger(d).rows[0].derivatives[1].sha256, /^[0-9a-f]{64}$/);
});

test('approveBudget records the user as the approver', async () => {
  const {approveBudget} = await import('../asset.mjs');
  const d = film(null);
  approveBudget(d, 300);
  assert.equal(budgetFor(d).approvedBytes, 300 * 1048576);
  assert.equal(JSON.parse(readFileSync(join(d, 'sourcing.json'), 'utf8')).budget.approvedBy, 'user');
});

test('the CLI refuses --approve without --by-user', () => {
  const d = film(null);
  const r = spawnSync(process.execPath, ['--no-warnings', join(import.meta.dirname, '..', 'asset.mjs'), 'budget', '--film', d, '--approve', '50'], {encoding: 'utf8'});
  assert.equal(r.status, 1);
  assert.match(r.stderr, /--by-user/);
  assert.equal(budgetFor(d).approvedBytes, null);
});
