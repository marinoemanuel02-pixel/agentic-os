// Re-open source pages on export day and compare their saved anchors.
// Browser-only rows require explicit same-day director confirmation.
import {readFileSync, writeFileSync} from 'node:fs';
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

export async function reverify(data, today, browserOk = new Set()) {
  const problems = [];
  const passed = [];
  for (const item of data.items) {
    if (item.fetch === 'browser') {
      console.log(`BROWSER ${item.id} ${item.url} anchor: "${item.anchor}"`);
      if (browserOk.has(item.id)) passed.push(item);
      else problems.push(item.id);
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
      passed.push(item);
      console.log(`OK ${item.id}`);
    } catch {
      console.log(`CHANGED ${item.id} ${item.url}`);
      problems.push(item.id);
    }
  }
  return {problems, passed};
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
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--today') today = args[++i];
    else if (args[i] === '--browser-ok') browserOk = new Set((args[++i] ?? '').split(',').filter(Boolean));
    else if (args[i] === '--write') write = true;
    else if (args[i].startsWith('--')) throw new Error(`unknown option: ${args[i]}`);
    else file = args[i];
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(today) || new Date(`${today}T00:00:00Z`).toISOString().slice(0,10) !== today) throw new Error(`invalid --today: ${today}`);
  const data = JSON.parse(readFileSync(file, 'utf8'));
  const {problems, passed} = await reverify(data, today, browserOk);
  if (write) {
    for (const item of passed) {
      item.retrieved = today;
      item.reverified ??= [];
      item.reverified.push({date:today, result:'ok'});
    }
    writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
  }
  if (problems.length) process.exitCode = 1;
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => {console.error(error.message); process.exitCode = 1;});
}
