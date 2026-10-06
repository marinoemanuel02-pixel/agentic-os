// aos asset: import real material into a film with its rights recorded (rule R35). One copy for both vendors
// (~/.agents/video/assets); `aos asset ...` passes API keys only as AOS_KEY_* environment variables.
//   search <query> --kind clip|photo|model|hdri|texture|sfx [--source id]... [--limit n] [--json]
//   fetch --film <dir> --id <aNN> --url <url> --kind <k> --basis <b> --acquisition <a> --platform <p> --why "<need>"
//         [--license id --license-url url --credit text --author name --page url --step 1-4 --source-in s --source-out s]
//   capture --film <dir> --id <aNN> --url <url> --mode shot|scroll|record [--seconds n] --why "<need>"
//   proxy --film <dir> [--force]      registry --film <dir>      credits --film <dir>
//   budget --film <dir> [--approve <MB> --by-user]
import {mkdtempSync, existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, extname, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {createHash} from 'node:crypto';
import {budgetFor, reserve, charge} from './lib/budget.mjs';
import {fetchHttp, fetchExcerpt, USER_AGENT} from './lib/fetch.mjs';
import {measureMedia} from './lib/measure.mjs';
import {makeProxy, makeAudio, sha256File} from './lib/proxy.mjs';
import {storeObject, lookupUrl} from './lib/cache.mjs';
import {addRow, readLedger, writeLedger} from './lib/ledger.mjs';
import {withFilmLock} from './lib/lock.mjs';
import {registryText} from './lib/registry.mjs';
import {creditsBlock} from './lib/credits.mjs';
import {cacheRoot, filmMediaRoot} from './lib/paths.mjs';

const EVIDENCE_EXCERPT = 300;
const PAGE_CAP = 2 * 1048576;

async function defaultFetchPage(url) {
  const dest = join(mkdtempSync(join(tmpdir(), 'asset-page-')), 'page.html');
  const r = await fetchHttp(url, {capBytes: PAGE_CAP, dest});
  const text = readFileSync(dest, 'utf8');
  rmSync(dest, {force: true});
  return r.complete ? text : text.slice(0, PAGE_CAP);
}

const extOf = url => {
  try { return extname(new URL(url).pathname).toLowerCase() || '.bin'; } catch { return '.bin'; }
};

// Fetch one asset for a film: cache hit (free) or a capped download charged to the film's budget, then the rights
// evidence and the ledger row. Uses are added by the director afterwards (they need the shot plan).
export async function fetchAsset(filmDir, opts, io = {}) {
  const fetchPage = io.fetchPage || defaultFetchPage;
  const excerpt = opts.sourceIn !== undefined && opts.sourceIn !== null;
  const cacheKey = excerpt ? `${opts.url}#t=${opts.sourceIn},${opts.sourceOut}` : opts.url;
  return withFilmLock(filmDir, async () => {
    if (readLedger(filmDir).rows.some(r => r.id === opts.id)) throw new Error(`${opts.id} already in assets.json`);
    const retrieved = new Date().toISOString();
    let hit = lookupUrl(cacheKey);
    if (!hit) {
      const {approvedBytes} = budgetFor(filmDir);
      if (approvedBytes === null) throw new Error(`${opts.id}: no download budget approved for this film (aos asset budget --approve <MB> --by-user, after the user approves)`);
      const {remaining} = reserve(filmDir, 0);
      if (remaining <= 0) throw new Error(`${opts.id}: not fetched: over the film's download budget (0 bytes left)`);
      const dest = join(mkdtempSync(join(tmpdir(), 'asset-')), `download${excerpt ? '.mp4' : extOf(opts.url)}`);
      const got = excerpt
        ? fetchExcerpt(opts.url, {sourceIn: opts.sourceIn, sourceOut: opts.sourceOut, capBytes: remaining, dest})
        : await fetchHttp(opts.url, {capBytes: remaining, dest});
      charge(filmDir, got.bytes, opts.url, got.complete ? 'complete' : 'incomplete');
      if (!got.complete) throw new Error(`${opts.id}: not fetched: over the film's download budget (${remaining} bytes left) or the transfer failed${got.log ? `: ${got.log}` : ''}`);
      hit = storeObject(dest, {url: cacheKey, retrieved, license: opts.license || null});
      rmSync(dest, {force: true});
    }
    const measured = opts.measure === false ? {duration: null} : measureMedia(hit.path);
    let rightsEvidence = null;
    if (opts.basis !== 'own') {
      const evidenceUrl = opts.licenseUrl || opts.page || opts.url;
      const text = await fetchPage(evidenceUrl);
      rightsEvidence = `research/rights/${opts.id}.json`;
      mkdirSync(join(filmDir, 'research', 'rights'), {recursive: true});
      writeFileSync(join(filmDir, rightsEvidence), JSON.stringify({
        url: evidenceUrl, asset: opts.url, retrieved,
        pageSha256: createHash('sha256').update(text).digest('hex'),
        excerpt: text.replace(/\s+/g, ' ').slice(0, EVIDENCE_EXCERPT),
      }, null, 2) + '\n');
    }
    return addRow(filmDir, {
      id: opts.id, kind: opts.kind, need: opts.why, searchStep: opts.searchStep ?? null,
      url: opts.url, page: opts.page || null, author: opts.author || null, retrieved,
      basis: opts.basis, license: opts.license || null, licenseUrl: opts.licenseUrl || null,
      acquisition: opts.acquisition || null, platform: opts.platform || null, rightsEvidence,
      source: excerpt ? {in: opts.sourceIn, out: opts.sourceOut} : null,
      media: {sha256: hit.sha256, cache: relative(cacheRoot(), hit.path).replaceAll('\\', '/'), start: excerpt ? opts.sourceIn : 0, duration: measured.duration},
      derivatives: [], uses: [], credit: opts.credit || '', clearance: null, subjects: opts.subjects || [],
    });
  });
}

// Derivatives in the film's media root: a silent proxy for clips and captures, an audio WAV per use that keeps
// its sound as the subject, a copy for stills, models and HDRIs. Hashes and settings go into the ledger.
export function proxyFilm(filmDir, {force = false} = {}) {
  const ledger = readLedger(filmDir);
  const publicDir = join(filmMediaRoot(filmDir), 'app', 'public');
  for (const r of ledger.rows) {
    if (r.derivatives.length && !force) continue;
    const source = join(cacheRoot(), r.media.cache);
    if (!existsSync(source)) throw new Error(`${r.id}: cached media missing (${source})`);
    const derivatives = [];
    if (r.kind === 'clip' || r.kind === 'capture') {
      const path = `assets/${r.id}.mp4`;
      derivatives.push({path, ...makeProxy(source, join(publicDir, path))});
      for (const u of r.uses || []) {
        if (u.audio !== 'subject') continue;
        const wav = `assets/${r.id}.${u.use}.wav`;
        derivatives.push({path: wav, ...makeAudio(source, join(publicDir, wav), u.mediaFrom, u.mediaTo)});
      }
    } else {
      const path = `assets/${r.id}${extname(source)}`;
      mkdirSync(join(publicDir, 'assets'), {recursive: true});
      copyFileSync(source, join(publicDir, path));
      derivatives.push({path, sha256: sha256File(join(publicDir, path)), ffmpeg: null});
    }
    r.derivatives = derivatives;
  }
  writeLedger(filmDir, ledger);
  return ledger;
}

export function approveBudget(filmDir, mb) {
  const file = join(filmDir, 'sourcing.json');
  const s = JSON.parse(readFileSync(file, 'utf8'));
  s.budget = {approvedMB: mb, approvedAt: new Date().toISOString(), approvedBy: 'user'};
  writeFileSync(file, JSON.stringify(s, null, 2) + '\n');
  return s.budget;
}

async function defaultGetJson(url, headers = {}) {
  const res = await fetch(url, {headers: {'user-agent': USER_AGENT, accept: 'application/json', ...headers}});
  if (!res.ok) throw new Error(`${new URL(url).hostname}: HTTP ${res.status}`);
  return res.json();
}

async function main(argv) {
  const [command, ...rest] = argv;
  const {values: v, positionals} = parseArgs({args: rest, allowPositionals: true, options: {
    film: {type: 'string'}, id: {type: 'string'}, url: {type: 'string'}, kind: {type: 'string'}, basis: {type: 'string'},
    acquisition: {type: 'string'}, platform: {type: 'string'}, why: {type: 'string'}, license: {type: 'string'},
    'license-url': {type: 'string'}, credit: {type: 'string'}, author: {type: 'string'}, page: {type: 'string'},
    step: {type: 'string'}, 'source-in': {type: 'string'}, 'source-out': {type: 'string'}, subjects: {type: 'string'},
    mode: {type: 'string'}, seconds: {type: 'string'}, source: {type: 'string', multiple: true}, limit: {type: 'string'},
    json: {type: 'boolean'}, force: {type: 'boolean'}, approve: {type: 'string'}, 'by-user': {type: 'boolean'},
  }});
  const film = v.film ? resolve(v.film) : null;
  const needFilm = () => { if (!film || !existsSync(join(film, 'sourcing.json'))) throw new Error('--film <project folder with sourcing.json> is required'); return film; };
  switch (command) {
    case 'search': {
      const {searchAll} = await import('./adapters/index.mjs');
      const r = await searchAll(positionals.join(' '), {kind: v.kind || 'clip', limit: Number(v.limit || 8), sources: v.source}, {getJson: defaultGetJson});
      if (v.json) console.log(JSON.stringify(r, null, 2));
      else {
        for (const c of r.candidates) console.log(`${c.source}:${c.id}  ${c.license}  ${c.duration ?? '-'} s  ${c.title}\n    ${c.page}`);
        for (const s of r.skipped) console.log(`skipped ${s.id}: ${s.reason}`);
      }
      return;
    }
    case 'fetch': {
      const row = await fetchAsset(needFilm(), {
        id: v.id, url: v.url, kind: v.kind, basis: v.basis, acquisition: v.acquisition, platform: v.platform, why: v.why,
        license: v.license, licenseUrl: v['license-url'], credit: v.credit, author: v.author, page: v.page,
        searchStep: v.step ? Number(v.step) : null, subjects: v.subjects ? v.subjects.split(',') : [],
        sourceIn: v['source-in'] !== undefined ? Number(v['source-in']) : null, sourceOut: v['source-out'] !== undefined ? Number(v['source-out']) : null,
      });
      console.log(`${row.id}: ${row.media.duration ?? '-'} s measured, cached as ${basename(row.media.cache)}; add its uses to assets.json, then aos asset proxy and registry`);
      return;
    }
    case 'capture': {
      const {captureAsset} = await import('./lib/capture.mjs');
      const row = await captureAsset(needFilm(), {id: v.id, url: v.url, mode: v.mode || 'shot', seconds: Number(v.seconds || 6), why: v.why, platform: v.platform || 'web'});
      console.log(`${row.id}: captured ${row.url}`);
      return;
    }
    case 'proxy': proxyFilm(needFilm(), {force: !!v.force}); console.log('derivatives written; run aos asset registry'); return;
    case 'registry': {
      const f = needFilm();
      writeFileSync(join(f, 'src', 'data', 'assets.ts'), registryText(readLedger(f).rows));
      console.log('src/data/assets.ts written');
      return;
    }
    case 'credits': process.stdout.write(creditsBlock(readLedger(needFilm()).rows)); return;
    case 'budget': {
      const f = needFilm();
      if (v.approve !== undefined) {
        if (!v['by-user']) throw new Error('--approve records the user\'s approval: add --by-user only after the user approved the amount');
        approveBudget(f, Number(v.approve));
      }
      const b = budgetFor(f);
      console.log(`approved ${b.approvedBytes === null ? 'none' : `${(b.approvedBytes / 1048576).toFixed(0)} MB`}; used ${(b.usedBytes / 1048576).toFixed(1)} MB`);
      return;
    }
    default:
      throw new Error('usage: asset.mjs <search|fetch|capture|proxy|registry|credits|budget> ...');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(e => { console.error(e.message); process.exit(1); });
}
