// Re-open source pages on export day and compare their saved anchors.
// Browser-only rows require explicit same-day director confirmation.
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/129.0 Safari/537.36';
const ENTITIES = {amp:'&', quot:'"', apos:"'", lt:'<', gt:'>', nbsp:' ', ldquo:'"', rdquo:'"', lsquo:"'", rsquo:"'", ndash:'-', mdash:'-', hellip:'…'};

export function normalizeText(html) {
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, num) => String.fromCodePoint(Number(num)))
    .replace(/&([a-z]+);/gi, (match, name) => ENTITIES[name.toLowerCase()] ?? match)
    .replace(/[“”]/g, '"').replace(/[‘’]/g, "'")
    .replace(/\s+/g, ' ').trim();
}

// With an evidence directory each page gets <id>.txt: URL, time, length, the SHA-256 of its full normalized text and a
// short excerpt around the anchor; no full copy of the article is kept (retro 32). A browser row needs such a file,
// saved from the browser, containing its anchor and a sha256 line.
const sha256 = (text) => createHash('sha256').update(text).digest('hex');
const excerpt = (page, anchor) => {
  const at = page.indexOf(anchor);
  return page.slice(Math.max(0, at - 80), at + anchor.length + 80);
};

export async function reverify(data, today, browserOk = new Set(), evidence = null) {
  const problems = [];
  const passed = [];
  const proof = new Map();
  if (evidence) mkdirSync(evidence, {recursive: true});
  for (const item of data.items) {
    if (item.fetch === 'browser') {
      if (!browserOk.has(item.id)) { console.log(`BROWSER ${item.id} ${item.url} anchor: "${item.anchor}"`); problems.push(item.id); continue; }
      if (evidence) {
        const saved = join(evidence, `${item.id}.txt`);
        const text = existsSync(saved) ? readFileSync(saved, 'utf8') : null;
        const hash = text && /^sha256: ([0-9a-f]{64})$/m.exec(text);
        if (text === null || !hash || !normalizeText(text).includes(normalizeText(item.anchor))) {
          console.log(`BROWSER ${item.id} ${item.url}: ${text === null ? 'no saved page text' : 'saved page text lacks the anchor or a sha256 line'}`);
          problems.push(item.id);
          continue;
        }
        proof.set(item.id, {evidence: `${item.id}.txt`, sha256: hash[1]});
      }
      console.log(`OK ${item.id} (browser)`);
      passed.push(item);
      continue;
    }
    if (item.fetch !== 'curl') {
      console.log(`CHANGED ${item.id} ${item.url}`);
      problems.push(item.id);
      continue;
    }
    try {
      const response = await fetch(item.url, {headers:{'user-agent':USER_AGENT}, redirect:'follow', signal:AbortSignal.timeout(20000)});
      const page = response.ok ? normalizeText(await response.text()) : '';
      if (!response.ok || !page.includes(normalizeText(item.anchor))) throw new Error(`HTTP ${response.status} or anchor absent`);
      if (evidence) {
        const hash = sha256(page);
        writeFileSync(join(evidence, `${item.id}.txt`), `url: ${item.url}
captured: ${new Date().toISOString()}
via: curl
chars: ${page.length}
sha256: ${hash}
excerpt: ${excerpt(page, normalizeText(item.anchor))}
`);
        proof.set(item.id, {evidence: `${item.id}.txt`, sha256: hash});
      }
      passed.push(item);
      console.log(`OK ${item.id}`);
    } catch {
      console.log(`CHANGED ${item.id} ${item.url}`);
      problems.push(item.id);
    }
  }
  return {problems, passed, proof};
}

function localDate() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

async function main(args) {
  let file = 'currency.json';
  let today = localDate();
  let browserOk = new Set();
  let write = false;
  let evidence = null;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--today') today = args[++i];
    else if (args[i] === '--browser-ok') browserOk = new Set((args[++i] ?? '').split(',').filter(Boolean));
    else if (args[i] === '--write') write = true;
    else if (args[i] === '--evidence') evidence = args[++i];
    else if (args[i].startsWith('--')) throw new Error(`unknown option: ${args[i]}`);
    else file = args[i];
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(today) || new Date(`${today}T00:00:00Z`).toISOString().slice(0,10) !== today) throw new Error(`invalid --today: ${today}`);
  const data = JSON.parse(readFileSync(file, 'utf8'));
  const {problems, passed, proof} = await reverify(data, today, browserOk, evidence);
  if (write) {
    for (const item of passed) {
      item.retrieved = today;
      item.reverified ??= [];
      item.reverified.push({date:today, result:'ok', ...(proof.get(item.id) ?? {})});
    }
    writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
  }
  if (problems.length) process.exitCode = 1;
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => {console.error(error.message); process.exitCode = 1;});
}
