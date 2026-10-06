// Page captures with Playwright against a loopback page (no network); skipped when the browser is not installed.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import http from 'node:http';
import {existsSync, mkdtempSync, statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {capture, playwrightAvailable} from '../lib/capture.mjs';
import {measureMedia} from '../lib/measure.mjs';

const PAGE = '<!doctype html><html><body style="margin:0;background:#123"><h1 style="color:#fff;font:64px sans-serif">Product</h1><div style="height:3000px;background:linear-gradient(#123,#c84)"></div></body></html>';
const serve = () => new Promise(res => { const s = http.createServer((q, r) => { r.writeHead(200, {'content-type': 'text/html'}); r.end(PAGE); });
  s.listen(0, '127.0.0.1', () => res({url: `http://127.0.0.1:${s.address().port}/`, close: () => s.close()})); });

test('shot writes a 1920x1080 PNG of the page', {skip: !playwrightAvailable() && 'Playwright not installed'}, async () => {
  const s = await serve();
  try {
    const dest = join(mkdtempSync(join(tmpdir(), 'cap-')), 'page.png');
    const r = await capture(s.url, {mode: 'shot', dest});
    assert.ok(existsSync(r.file) && statSync(r.file).size > 1000);
    const m = measureMedia(r.file);
    assert.equal(m.width, 1920);
    assert.equal(m.height, 1080);
  } finally { s.close(); }
});

test('scroll records a video of about the requested length', {skip: !playwrightAvailable() && 'Playwright not installed'}, async () => {
  const s = await serve();
  try {
    const dest = join(mkdtempSync(join(tmpdir(), 'cap-')), 'scroll.webm');
    const r = await capture(s.url, {mode: 'scroll', seconds: 2, dest});
    const m = measureMedia(r.file);
    assert.ok(m.duration > 1.5 && m.duration < 4, `duration ${m.duration}`);
  } finally { s.close(); }
});
