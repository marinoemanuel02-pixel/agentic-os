// Export-day currency gate for dated source claims.
// Reports every invalid row so the director can repair the ledger in one pass.
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const REQUIRED = ['id', 'tag', 'camp', 'claim', 'url', 'sourceDate', 'retrieved', 'version', 'anchor'];
const TAGS = new Set(['fact', 'measurement', 'opinion', 'forecast', 'contested', 'quote']);
const DAY_MS = 86400000;

function parseDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const ms = Date.parse(`${value}T00:00:00Z`);
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 10) === value ? ms : null;
}

export function checkCurrency(data, today, claims, exportMode = false) {
  const errors = [];
  const todayMs = parseDate(today);
  if (todayMs === null) return [`invalid --today: ${today}`];
  const policy = data?.policy ?? {};
  if (!Number.isFinite(policy.reverifyWithinDays) || policy.reverifyWithinDays < 0) errors.push('invalid policy.reverifyWithinDays');
  if (!Number.isFinite(policy.defaultMaxSourceAgeDays) || policy.defaultMaxSourceAgeDays < 0) errors.push('invalid policy.defaultMaxSourceAgeDays');
  if (!Array.isArray(data?.items)) return [...errors, 'missing items array'];
  if (!data.items.length) errors.push('empty currency items');
  const ids = new Set();
  for (const item of data.items) {
    const id = item?.id || '(unknown)';
    for (const field of REQUIRED) {
      if (typeof item?.[field] !== 'string' || !item[field].trim()) errors.push(`missing ${field}: ${id}`);
    }
    if (ids.has(id)) errors.push(`duplicate id: ${id}`);
    ids.add(id);
    if (item?.tag && !TAGS.has(item.tag)) errors.push(`invalid tag: ${id}`);
    for (const field of ['sourceDate', 'retrieved']) {
      if (!item?.[field]) continue;
      const ms = parseDate(item[field]);
      if (ms === null) errors.push(`invalid ${field}: ${id}`);
      else if (ms > todayMs) errors.push(`future ${field}: ${id}`);
      else if (field === 'retrieved' && Number.isFinite(policy.reverifyWithinDays) && ms < todayMs - policy.reverifyWithinDays * DAY_MS) errors.push(`stale: re-verify ${id}`);
      else if (field === 'sourceDate') {
        const maxAge = item.maxSourceAgeDays ?? policy.defaultMaxSourceAgeDays;
        if (!Number.isFinite(maxAge) || maxAge < 0) errors.push(`invalid maxSourceAgeDays: ${id}`);
        else if (ms < todayMs - maxAge * DAY_MS) errors.push(`too old for 'now': ${id}`);
      }
    }
  }
  for (const item of data.items) {
    if (item?.tag !== 'contested') continue;
    const counters = Array.isArray(item.counter) ? item.counter : [];
    // Both voices: a counter item from another camp. A second URL alone can repeat the same side (Codex review).
    if (counters.length === 0) errors.push(item.url2 ? `contested needs a counter-voice from another camp: ${item.id}` : `contested needs two sources or both voices: ${item.id}`);
    for (const counter of counters) {
      const other = data.items.find((x) => x?.id === counter);
      if (!other) errors.push(`unknown counter: ${item.id} -> ${counter}`);
      else if (other.camp === item.camp) errors.push(`counter from the same camp: ${item.id} -> ${counter} (not a distinct voice)`);
    }
  }
  // Export mode: every item carries a re-verification (tools/reverify.mjs --write) dated on the actual export day,
  // so a recent first retrieval cannot stand in for the export-day check.
  if (exportMode) {
    for (const item of data.items) {
      const dates = (Array.isArray(item?.reverified) ? item.reverified : []).filter((r) => r?.result === 'ok').map((r) => parseDate(r.date)).filter((ms) => ms !== null);
      const last = dates.length ? Math.max(...dates) : null;
      if (last !== todayMs) errors.push(`not re-verified for export: ${item?.id}`);
    }
  }
  if (claims) {
    let covered = 0;
    for (const section of ['lines', 'screen']) {
      for (const entry of claims[section] ?? []) {
        if (entry.currency) {
          covered++;
          if (!ids.has(entry.currency)) errors.push(`unknown currency id: ${entry.currency} (${section} ${entry.id ?? entry.shots ?? '?'})`);
        } else if (entry.needsCurrency === true || ['fact', 'quote'].includes(entry.kind)) errors.push(`needsCurrency without currency: ${section} ${entry.id ?? entry.shots ?? '?'}`);
      }
    }
    console.log(`currency coverage: ${covered} claims entry(s)`);
  }
  return errors;
}

function localDate() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function main(args) {
  let file = 'currency.json';
  let today = localDate();
  let claimsFile;
  let exportMode = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--today') today = args[++i];
    else if (args[i] === '--claims') claimsFile = args[++i];
    else if (args[i] === '--export') exportMode = true;
    else if (args[i].startsWith('--')) throw new Error(`unknown option: ${args[i]}`);
    else file = args[i];
  }
  const data = JSON.parse(readFileSync(file, 'utf8'));
  const claims = claimsFile ? JSON.parse(readFileSync(claimsFile, 'utf8')) : undefined;
  const errors = checkCurrency(data, today, claims, exportMode);
  for (const error of errors) console.log(error);
  if (errors.length) process.exitCode = 1;
  else console.log(`currency ok: ${data.items.length} item(s)`);
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
