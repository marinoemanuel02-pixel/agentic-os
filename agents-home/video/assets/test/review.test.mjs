// Codex review 2026-10-06, findings 3, 4, 5 and 7: no credentials persisted, every received byte charged (failed
// transfers, rights pages, excerpts while they run), cached objects trusted only when their bytes still match.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import http from 'node:http';
import {existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {budgetFor} from '../lib/budget.mjs';
import {fetchHttp, fetchExcerpt, sanitizeUrl} from '../lib/fetch.mjs';
import {storeObject, lookupUrl} from '../lib/cache.mjs';
import {addRow, readLedger} from '../lib/ledger.mjs';
import {sha256File} from '../lib/proxy.mjs';

const FAKE_YTDLP = fileURLToPath(new URL('./fakes/yt-dlp.mjs', import.meta.url));

function film(approvedMB = 1) {
  const dir = join(mkdtempSync(join(tmpdir(), 'asset-review-')), 'film');
  mkdirSync(dir, {recursive: true});
  process.env.AOS_VIDEO_MEDIA_ROOT = join(dir, '..', 'media');
  process.env.AOS_ASSET_CACHE = join(dir, '..', 'cache');
  writeFileSync(join(dir, 'sourcing.json'), JSON.stringify({schema: 1, fairUse: true, acquisition: {'*': ['direct-file']}, budget: {approvedMB, approvedAt: 'x', approvedBy: 'user'}}));
  return dir;
}
// handler(req, res) decides what the loopback server sends.
const serve = handler => new Promise(res => {
  const s = http.createServer(handler);
  s.listen(0, '127.0.0.1', () => res({base: `http://127.0.0.1:${s.address().port}`, close: () => s.close()}));
});
const opts = (url, extra = {}) => ({url, id: 'a01', basis: 'cc0', license: 'cc0-1.0', licenseUrl: url, acquisition: 'direct-file', platform: 't', why: 'x', kind: 'clip', credit: '', measure: false, ...extra});

test('sanitizeUrl drops credential-looking parameters and user info, keeps the rest', () => {
  assert.equal(sanitizeUrl('https://u:p@cdn.example/v.mp4?token=S&w=1&Signature=Z&api_key=K'), 'https://cdn.example/v.mp4?w=1');
  assert.equal(sanitizeUrl('https://x.example/a?q=robot'), 'https://x.example/a?q=robot');
});

test('credential-looking URL parameters never reach the ledger, budget log, cache index or evidence', async () => {
  const {fetchAsset} = await import('../asset.mjs');
  const s = await serve((q, r) => r.end(Buffer.alloc(500, 1)));
  try {
    const d = film();
    const url = `${s.base}/v.mp4?token=SECRET-123&w=1`;
    await fetchAsset(d, opts(url), {fetchPage: async () => 'license page'});
    const files = [join(d, 'assets.json'), join(d, 'research', 'rights', 'a01.json'), join(process.env.AOS_VIDEO_MEDIA_ROOT, 'assets-budget.jsonl'), join(process.env.AOS_ASSET_CACHE, 'index.json')];
    for (const f of files) assert.doesNotMatch(readFileSync(f, 'utf8'), /SECRET-123/, f);
    assert.match(readLedger(d).rows[0].url, /\?w=1$/);
  } finally { s.close(); }
});

test('an HTTP error never shows a credential parameter', async () => {
  const s = await serve((q, r) => { r.statusCode = 404; r.end(); });
  try {
    const dest = join(mkdtempSync(join(tmpdir(), 'e-')), 'x');
    await assert.rejects(fetchHttp(`${s.base}/x?token=SECRET-9`, {capBytes: 10, dest}), e => !/SECRET-9/.test(e.message) && /HTTP 404/.test(e.message));
  } finally { s.close(); }
});

test('fetchHttp counts every byte received, also the chunk that crossed the cap', async () => {
  const s = await serve((q, r) => { r.write(Buffer.alloc(60, 1)); setTimeout(() => r.end(Buffer.alloc(60, 2)), 50); });
  try {
    const dest = join(mkdtempSync(join(tmpdir(), 'c-')), 'x');
    const got = await fetchHttp(`${s.base}/x`, {capBytes: 100, dest});
    assert.equal(got.complete, false);
    assert.equal(got.bytes, 120);
  } finally { s.close(); }
});

test('a transfer cut off midway is charged to the film', async () => {
  const {fetchAsset} = await import('../asset.mjs');
  const s = await serve((q, r) => { r.writeHead(200, {'content-length': '1000'}); r.write(Buffer.alloc(60, 1)); setTimeout(() => r.socket.destroy(), 50); });
  try {
    const d = film();
    await assert.rejects(fetchAsset(d, opts(`${s.base}/x.mp4`), {fetchPage: async () => 'p'}));
    assert.ok(budgetFor(d).usedBytes >= 60, `charged ${budgetFor(d).usedBytes}`);
    assert.equal(readLedger(d).rows.length, 0);
  } finally { s.close(); }
});

test('the rights page fetch is charged to the film', async () => {
  const {fetchAsset} = await import('../asset.mjs');
  const s = await serve((q, r) => r.end(q.url.startsWith('/license') ? 'L'.repeat(300) : Buffer.alloc(500, 1)));
  try {
    const d = film();
    await fetchAsset(d, opts(`${s.base}/v.mp4`, {licenseUrl: `${s.base}/license`}));
    assert.equal(budgetFor(d).usedBytes, 800);
  } finally { s.close(); }
});

test('an excerpt that fails midway is charged and leaves no files behind', async () => {
  process.env.AOS_YTDLP_JS = FAKE_YTDLP;
  process.env.FAKE_YTDLP_MODE = 'fail';
  process.env.FAKE_YTDLP_BYTES = '200000';
  try {
    const dir = mkdtempSync(join(tmpdir(), 'x-'));
    const got = await fetchExcerpt('https://video.example/watch', {sourceIn: 1, sourceOut: 3, capBytes: 10_000_000, dest: join(dir, 'excerpt.mp4')});
    assert.equal(got.complete, false);
    assert.ok(got.bytes >= 200000, `bytes ${got.bytes}`);
    assert.deepEqual(readdirSync(dir), []);
  } finally { delete process.env.AOS_YTDLP_JS; delete process.env.FAKE_YTDLP_MODE; delete process.env.FAKE_YTDLP_BYTES; }
});

test('an excerpt that grows past the cap is stopped while it runs', async () => {
  process.env.AOS_YTDLP_JS = FAKE_YTDLP;
  process.env.FAKE_YTDLP_MODE = 'grow';
  try {
    const dir = mkdtempSync(join(tmpdir(), 'x-'));
    const started = Date.now();
    const got = await fetchExcerpt('https://video.example/watch', {sourceIn: 1, sourceOut: 3, capBytes: 300000, dest: join(dir, 'excerpt.mp4')});
    assert.equal(got.complete, false);
    assert.ok(got.bytes >= 300000, `bytes ${got.bytes}`);
    assert.ok(Date.now() - started < 10000, 'killed promptly');
    assert.deepEqual(readdirSync(dir), []);
  } finally { delete process.env.AOS_YTDLP_JS; delete process.env.FAKE_YTDLP_MODE; }
});

test('a finished excerpt keeps its file and reports its size', async () => {
  process.env.AOS_YTDLP_JS = FAKE_YTDLP;
  process.env.FAKE_YTDLP_MODE = 'ok';
  process.env.FAKE_YTDLP_BYTES = '150000';
  try {
    const dir = mkdtempSync(join(tmpdir(), 'x-'));
    const dest = join(dir, 'excerpt.mp4');
    const got = await fetchExcerpt('https://video.example/watch', {sourceIn: 1, sourceOut: 3, capBytes: 10_000_000, dest});
    assert.equal(got.complete, true);
    assert.ok(existsSync(dest));
    assert.ok(got.bytes >= 150000);
  } finally { delete process.env.AOS_YTDLP_JS; delete process.env.FAKE_YTDLP_MODE; delete process.env.FAKE_YTDLP_BYTES; }
});

test('a cached object whose bytes changed is not trusted', () => {
  film();
  const src = join(mkdtempSync(join(tmpdir(), 'o-')), 'a.bin');
  writeFileSync(src, 'original bytes');
  const obj = storeObject(src, {url: 'http://x/a', retrieved: 'now'});
  writeFileSync(obj.path, 'tampered bytes');
  assert.equal(lookupUrl('http://x/a'), null);
});

test('a partial object left at the final path is replaced, not trusted', () => {
  film();
  const src = join(mkdtempSync(join(tmpdir(), 'o-')), 'a.bin');
  writeFileSync(src, 'complete bytes');
  const sha = sha256File(src);
  mkdirSync(join(process.env.AOS_ASSET_CACHE, 'objects'), {recursive: true});
  writeFileSync(join(process.env.AOS_ASSET_CACHE, 'objects', `${sha}.bin`), 'comp');
  const obj = storeObject(src, {url: 'http://x/b', retrieved: 'now'});
  assert.equal(readFileSync(obj.path, 'utf8'), 'complete bytes');
});

test('proxyFilm refuses cached media whose hash differs from the ledger', async () => {
  const {proxyFilm} = await import('../asset.mjs');
  const d = film();
  const src = join(mkdtempSync(join(tmpdir(), 'o-')), 'a.png');
  writeFileSync(src, 'png bytes');
  const obj = storeObject(src, {url: 'http://x/c', retrieved: 'now'});
  addRow(d, {id: 'p01', kind: 'photo', media: {sha256: '0'.repeat(64), cache: `objects/${obj.sha256}.png`}, derivatives: [], uses: []});
  assert.throws(() => proxyFilm(d), /p01: cached media changed/);
});
