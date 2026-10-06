// Asset gate (rule R35): every imported file has a rights row with a known basis, an allowlisted license or a bounded
// fair-use/capture use, evidence, credits and an acquisition the film's sourcing.json accepts; media reach the picture
// only through the registry. It checks policy, not law: success prints "asset policy checks passed", never "fair use".
//   node tools/checks/assets.mjs <projectDir> [--timeline qa/timeline.json] [--public <media root>/app/public] [--report qa/assets.md]
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync} from 'node:fs';
import {dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const BASES = ['license', 'public-domain', 'cc0', 'fair-use', 'capture', 'own'];
export const ACQUISITIONS = ['api', 'direct-file', 'platform-feature', 'download-tool'];
export const LICENSES = ['cc0-1.0', 'pd', 'cc-by-3.0', 'cc-by-4.0', 'pexels', 'pixabay', 'mit', 'bsd-3-clause', 'lottie-simple'];
const MAX_USE_S = 8;
const MAX_SHARE = 0.10;
const MAX_AUDIO_SUBJECT_S = 5;
const MIN_NARRATION = 0.5;
const EPS = 1e-6;
const MEDIA_EXT = 'mp4|webm|mov|m4v|png|jpe?g|webp|gif|svg|glb|gltf|json|lottie|mp3|wav|ogg|m4a|hdr|exr';

const fmt = x => String(Number(x.toFixed(3)));
const readJson = (file, fallback) => (existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : fallback);
const sha256 = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const hostOf = url => { try { return new URL(url).hostname; } catch { return ''; } };
const limited = basis => basis === 'fair-use' || basis === 'capture';

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out); else out.push(p);
  }
  return out;
}

function creditsSection(description) {
  const at = description.search(/^## Credits\s*$/m);
  if (at < 0) return '';
  const rest = description.slice(at).split('\n').slice(1).join('\n');
  const next = rest.search(/^## /m);
  return next < 0 ? rest : rest.slice(0, next);
}

// Seconds of [start, end] covered by the union of the narration's word intervals (film time).
function narrationOver(start, end, intervals) {
  const parts = intervals.map(([a, b]) => [Math.max(a, start), Math.min(b, end)]).filter(([a, b]) => b > a).sort((x, y) => x[0] - y[0]);
  let covered = 0, reach = start;
  for (const [a, b] of parts) {
    const from = Math.max(a, reach);
    if (b > from) { covered += b - from; reach = b; }
  }
  return covered;
}

function wordIntervals(timeline, words) {
  const out = [];
  for (const line of timeline.lines || []) {
    const t0 = line.from / timeline.fps;
    for (const w of words[line.id] || []) out.push([t0 + w[1], t0 + w[2]]);
  }
  return out;
}

function externalResources(file) {
  let j;
  try { j = JSON.parse(readFileSync(file, 'utf8')); } catch { return false; }
  const external = uri => typeof uri === 'string' && uri !== '' && !uri.startsWith('data:');
  if (file.endsWith('.gltf')) return [...(j.buffers || []), ...(j.images || [])].some(x => external(x.uri));
  return (j.assets || []).some(a => a.p !== undefined && a.e !== 1 && external(a.p));
}

function scanSource(dir, errors) {
  const src = join(dir, 'src');
  for (const file of walk(src)) {
    if (!/\.(ts|tsx|mts|js|jsx|mjs)$/.test(file)) continue;
    const rel = relative(dir, file).replaceAll('\\', '/');
    if (rel === 'src/data/assets.ts' || rel === 'src/data/asset-uses.ts') continue;
    const code = readFileSync(file, 'utf8');
    const inMedia = rel.startsWith('src/lib/media/');
    let bad = false;
    for (const m of code.matchAll(/staticFile\s*\(([^)]*)\)/g)) {
      const arg = m[1].trim();
      if (!(inMedia && /^ASSETS\[[A-Za-z_$][\w$]*\]\.src$/.test(arg))) bad = true;
    }
    for (const m of code.matchAll(/useGLTF\s*\(\s*(["'`])/g)) if (m) bad = true;
    if (bad) errors.push(`${rel}: dynamic or literal media path (use a media component with an asset id from src/data/assets.ts)`);
    if (new RegExp(`https?://[^\\s"'\`)]+\\.(${MEDIA_EXT})\\b`, 'i').test(code)) errors.push(`${rel}: remote media URL (fetch it with aos asset and use its id)`);
  }
}

export function checkAssets(dir, opts = {}) {
  const errors = [];
  const publicDir = resolve(opts.publicDir ?? join(dir, 'public'));
  const ledger = readJson(join(dir, 'assets.json'), {schema: 1, rows: []});
  const sourcing = readJson(join(dir, 'sourcing.json'), {schema: 1, fairUse: false, acquisition: {}});
  const rows = ledger.rows || [];
  const timelineFile = opts.timeline ?? join(dir, 'timeline.json');
  const timeline = readJson(timelineFile, null);
  const words = readJson(join(dir, 'src', 'data', 'words.json'), {});
  const claims = readJson(join(dir, 'claims.json'), {screen: []});
  const credits = creditsSection(existsSync(join(dir, 'description.md')) ? readFileSync(join(dir, 'description.md'), 'utf8') : '');
  if (rows.some(r => (r.uses || []).length) && !timeline) errors.push(`timeline: ${timelineFile} missing (node --no-warnings tools/timeline-json.mts)`);
  const intervals = timeline ? wordIntervals(timeline, words) : [];
  const filmSeconds = timeline ? timeline.frames / timeline.fps : 0;

  const seen = new Set();
  const derivativePaths = new Set();
  const perBasis = {};
  const bySearchStep = {};
  let limitedSeconds = 0;

  for (const r of rows) {
    const id = r.id;
    if (seen.has(id)) { errors.push(`${id}: duplicate id`); continue; }
    seen.add(id);
    perBasis[r.basis] = (perBasis[r.basis] || 0) + 1;
    bySearchStep[r.searchStep ?? 'unknown'] = (bySearchStep[r.searchStep ?? 'unknown'] || 0) + 1;
    if (!BASES.includes(r.basis)) errors.push(`${id}: unknown basis ${r.basis}`);

    if (['license', 'cc0', 'public-domain'].includes(r.basis) && !LICENSES.includes(r.license)) errors.push(`${id}: license ${r.license} not allowed`);
    const credit = (r.credit || '').trim();
    if (/^cc-by-/.test(r.license || '') && !credit) errors.push(`${id}: credit required by ${r.license}`);
    if (['license', 'cc0', 'public-domain'].includes(r.basis) && credit && !credits.includes(credit)) errors.push(`${id}: credit missing from description.md ("${credit}")`);
    if (/(^|\.)polyhaven\.com$/.test(hostOf(r.url)) && !credits.includes('Powered by Poly Haven')) errors.push(`${id}: description.md needs "Powered by Poly Haven"`);

    if (r.basis !== 'own') {
      if (!ACQUISITIONS.includes(r.acquisition)) errors.push(`${id}: unknown acquisition ${r.acquisition}`);
      else {
        const acq = sourcing.acquisition || {};
        const accepted = acq[r.platform] ?? acq['*'] ?? [];
        if (!accepted.includes(r.acquisition)) errors.push(`${id}: acquisition ${r.acquisition} from ${r.platform} not accepted by sourcing.json`);
      }
      if (!r.rightsEvidence || !existsSync(join(dir, r.rightsEvidence))) errors.push(`${id}: rights evidence missing (${r.rightsEvidence || 'no path'})`);
    }
    if (limited(r.basis) && sourcing.fairUse !== true) errors.push(`${id}: fair use disabled in sourcing.json`);
    if (/(^|\.)nasa\.gov$/.test(hostOf(r.url))) {
      for (const s of r.subjects || []) if ((s === 'person' || s === 'logo') && !r.clearance) errors.push(`${id}: needs clearance for ${s}`);
    }

    for (const d of r.derivatives || []) {
      const rel = String(d.path).replaceAll('\\', '/');
      derivativePaths.add(rel);
      const file = join(publicDir, rel);
      if (!existsSync(file)) { errors.push(`${id}: derivative ${rel} missing`); continue; }
      if (sha256(file) !== d.sha256) errors.push(`${id}: derivative hash mismatch (${rel})`);
      if (/\.(gltf|json|lottie)$/.test(rel) && externalResources(file)) errors.push(`${id}: ${rel} references external resources`);
    }

    let tagged = false;
    for (const u of r.uses || []) {
      const len = u.mediaTo - u.mediaFrom;
      const dur = r.media && typeof r.media.duration === 'number' ? r.media.duration : null;
      if (dur !== null && u.mediaTo > dur + EPS) errors.push(`${id}: use ${u.use} ends at ${fmt(u.mediaTo)} s past the measured ${fmt(dur)} s`);
      const shot = timeline ? (timeline.shots || []).find(s => s.id === u.shot) : null;
      if (timeline && !shot) { errors.push(`${id}: use ${u.use} on unknown shot ${u.shot}`); continue; }
      if (!limited(r.basis)) continue;
      limitedSeconds += len;
      if (len > MAX_USE_S + EPS) errors.push(`${id}: use ${u.use} is ${fmt(len)} s (max ${MAX_USE_S} s)`);
      if (u.audio === 'kept') errors.push(`${id}: use ${u.use} keeps sound (only audio "subject" may, up to ${MAX_AUDIO_SUBJECT_S} s)`);
      if (u.audio === 'subject' && len > MAX_AUDIO_SUBJECT_S + EPS) errors.push(`${id}: use ${u.use} audio subject ${fmt(len)} s over ${MAX_AUDIO_SUBJECT_S} s`);
      if (!(u.rationale || '').trim()) errors.push(`${id}: use ${u.use} needs a rationale`);
      if (shot) {
        const start = (shot.from + u.shotFrom) / timeline.fps;
        const share = len > 0 ? narrationOver(start, start + len, intervals) / len : 0;
        if (share + EPS < MIN_NARRATION) errors.push(`${id}: use ${u.use} has narration over ${Math.floor(share * 100 + EPS)} % of its ${fmt(len)} s`);
      }
      tagged = true;
    }
    if (tagged && !(claims.screen || []).some(s => s.asset === id && s.generated === true && (s.texts || []).includes(r.credit))) {
      errors.push(`${id}: no generated source tag in claims.json (aos asset registry writes it)`);
    }
  }

  if (filmSeconds > 0 && limitedSeconds > MAX_SHARE * filmSeconds + EPS) {
    errors.push(`fair-use and capture total ${fmt(limitedSeconds)} s exceeds ${MAX_SHARE * 100} % of ${fmt(filmSeconds)} s`);
  }
  for (const file of walk(join(publicDir, 'assets'))) {
    const rel = relative(publicDir, file).replaceAll('\\', '/');
    if (!derivativePaths.has(rel)) errors.push(`public/${rel}: no ledger row`);
  }
  scanSource(dir, errors);

  const fairUseSeconds = Number(limitedSeconds.toFixed(3));
  return {ok: errors.length === 0, errors,
    report: {perBasis, fairUseSeconds, filmSeconds, share: filmSeconds ? fairUseSeconds / filmSeconds : 0, bySearchStep}};
}

export function reportText(result) {
  const r = result.report;
  const basis = Object.entries(r.perBasis).map(([k, v]) => `${k} ${v}`).join(', ') || 'none';
  const steps = Object.entries(r.bySearchStep).map(([k, v]) => `step ${k}: ${v}`).join(', ') || 'none';
  return [
    '# Asset policy report', '',
    'Policy checks, not a legal determination.', '',
    `- Rows per basis: ${basis}`,
    `- fair-use and capture: ${r.fairUseSeconds.toFixed(1)} s of ${r.filmSeconds.toFixed(1)} s (${(r.share * 100).toFixed(1)} %)`,
    `- Rows per search step (1 subject's own, 2 coverage, 3 open libraries, 4 built): ${steps}`,
    `- Result: ${result.ok ? 'asset policy checks passed' : `${result.errors.length} problems`}`,
    ...result.errors.map(e => `  - ${e}`), '',
    '## Human checks', '',
    '- The narration actually comments on every fair-use or capture excerpt (the gate only measures overlap).',
    '- Every source tag is legible at full size in the review sheets.',
    '- Each excerpt takes no more than the line needs.', '',
    '## Content ID', '',
    'Stock footage and sound effects are sometimes claimed by Content ID in error. The ledger and rights evidence are',
    'supporting evidence for a dispute, not proof.', '',
  ].join('\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
  const dir = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
  if (!dir) { console.error('Usage: assets.mjs <projectDir> [--timeline <json>] [--public <dir>] [--report <md>]'); process.exit(2); }
  const result = checkAssets(dir, {timeline: opt('--timeline'), publicDir: opt('--public')});
  const report = opt('--report');
  if (report) { mkdirSync(dirname(report), {recursive: true}); writeFileSync(report, reportText(result)); }
  if (result.ok) console.log('asset policy checks passed');
  else { for (const e of result.errors) console.log(e); process.exit(1); }
}
