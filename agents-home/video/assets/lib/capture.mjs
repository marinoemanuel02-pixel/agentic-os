// Live captures of a public page or product UI with the installed Playwright (global npm, browsers in
// PLAYWRIGHT_BROWSERS_PATH or ~/.aos/ms-playwright): a still, a scroll recording or a plain recording at 1920x1080.
// A capture is not permission: its ledger row has basis "capture" and follows the fair-use limits (R35).
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readdirSync, renameSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {homedir, tmpdir} from 'node:os';
import {join, relative} from 'node:path';
import {storeObject} from './cache.mjs';
import {measureMedia} from './measure.mjs';
import {addRow, readLedger} from './ledger.mjs';
import {cacheRoot} from './paths.mjs';
import {withFilmLock} from './lock.mjs';

const VIEWPORT = {width: 1920, height: 1080};
const PLAYWRIGHT = join(process.env.AOS_NPM_GLOBAL || join(homedir(), '.npm-global', 'node_modules'), 'playwright');

if (!process.env.PLAYWRIGHT_BROWSERS_PATH) process.env.PLAYWRIGHT_BROWSERS_PATH = join(homedir(), '.aos', 'ms-playwright');

export const playwrightAvailable = () => existsSync(join(PLAYWRIGHT, 'package.json')) && existsSync(process.env.PLAYWRIGHT_BROWSERS_PATH);

function chromium() {
  return createRequire(join(PLAYWRIGHT, 'package.json'))('playwright').chromium;
}

export async function capture(url, {mode = 'shot', seconds = 6, dest}) {
  mkdirSync(join(dest, '..'), {recursive: true});
  const browser = await chromium().launch();
  try {
    if (mode === 'shot') {
      const page = await browser.newPage({viewport: VIEWPORT});
      await page.goto(url, {waitUntil: 'networkidle'});
      await page.screenshot({path: dest});
      return {file: dest, bytes: statSync(dest).size, html: await page.content()};
    }
    const videoDir = mkdtempSync(join(tmpdir(), 'asset-capture-'));
    const context = await browser.newContext({viewport: VIEWPORT, recordVideo: {dir: videoDir, size: VIEWPORT}});
    const page = await context.newPage();
    await page.goto(url, {waitUntil: 'networkidle'});
    const html = await page.content();
    const steps = Math.max(1, Math.round(seconds * 2));
    for (let i = 0; i < steps; i++) {
      if (mode === 'scroll') await page.mouse.wheel(0, 400);
      await page.waitForTimeout(500);
    }
    await context.close();
    const recorded = readdirSync(videoDir).find(n => n.endsWith('.webm'));
    if (!recorded) throw new Error(`capture ${url}: no video was recorded`);
    renameSync(join(videoDir, recorded), dest);
    rmSync(videoDir, {recursive: true, force: true});
    return {file: dest, bytes: statSync(dest).size, html};
  } finally {
    await browser.close();
  }
}

export async function captureAsset(filmDir, {id, url, mode, seconds, why, platform = 'web'}) {
  return withFilmLock(filmDir, async () => {
    if (readLedger(filmDir).rows.some(r => r.id === id)) throw new Error(`${id} already in assets.json`);
    const retrieved = new Date().toISOString();
    const dest = join(mkdtempSync(join(tmpdir(), 'asset-')), mode === 'shot' ? 'capture.png' : 'capture.webm');
    const shot = await capture(url, {mode, seconds, dest});
    const hit = storeObject(shot.file, {url: `${url}#capture=${mode}@${retrieved}`, retrieved});
    rmSync(dest, {force: true});
    const rightsEvidence = `research/rights/${id}.json`;
    mkdirSync(join(filmDir, 'research', 'rights'), {recursive: true});
    writeFileSync(join(filmDir, rightsEvidence), JSON.stringify({url, retrieved, mode,
      pageSha256: createHash('sha256').update(shot.html).digest('hex'),
      excerpt: shot.html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 300)}, null, 2) + '\n');
    const host = new URL(url).hostname;
    return addRow(filmDir, {
      id, kind: mode === 'shot' ? 'photo' : 'capture', need: why, searchStep: 1, url, page: url, author: host, retrieved,
      basis: 'capture', license: null, licenseUrl: null, acquisition: 'platform-feature', platform, rightsEvidence,
      source: null, media: {sha256: hit.sha256, cache: relative(cacheRoot(), hit.path).replaceAll('\\', '/'), start: 0, duration: mode === 'shot' ? null : measureMedia(hit.path).duration},
      derivatives: [], uses: [], credit: `Source: ${host}, captured ${retrieved.slice(0, 10)}`, clearance: null, subjects: [],
    });
  });
}
