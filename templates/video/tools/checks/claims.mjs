// Coverage gate, not an automated fact checker. Evidence anchors are reviewed by a person/agent.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export function validateClaims(lines, ledger) {
  if (!Array.isArray(ledger.lines) || !Array.isArray(ledger.screen) || !ledger.sources) throw new Error('Missing claims ledger lines/screen/sources');
  const evidence = (row, name) => {
    if (!['fact', 'definition', 'quote', 'inference', 'illustration', 'hypothetical', 'label', 'title'].includes(row.kind)) throw new Error(`Unknown claim kind: ${name}/${row.kind}`);
    if (!Array.isArray(row.sources)) throw new Error(`Missing sources array: ${name}`);
    if (row.kind === 'fact' && !row.sources.length) throw new Error(`Unsourced fact: ${name}`);
    for (const id of row.sources) {
      const s = ledger.sources[id];
      if (!s?.url || !s.openedBy || !s.openedDate || !s.anchor || s.provenance !== 'direct') throw new Error(`Missing direct primary evidence: ${name}/${id}`);
    }
  };
  for (const line of lines) {
    const row = ledger.lines.find(row => row.id === line.id);
    if (!row || row.text !== line.text) throw new Error(`Unreviewed narration: ${line.id}`);
    if (!row.reviewed || !row.kind) throw new Error(`Unreviewed classification: ${line.id}`);
    evidence(row, line.id);
  }
  if (ledger.lines.length !== lines.length) throw new Error('Stale ledger line count');
  for (const item of ledger.screen) {
    if (!item.reviewed || !item.kind || !Array.isArray(item.texts)) throw new Error(`Unreviewed screen text: ${item.texts?.[0]}`);
    evidence(item, item.texts[0]);
  }
  return true;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  validateClaims(JSON.parse(fs.readFileSync(path.join(root, 'src/data/lines.json'), 'utf8')),
    JSON.parse(fs.readFileSync(path.join(root, 'claims.json'), 'utf8')));
  console.log('PASS: narration ledger and reviewed screen entries match (manual truth judgement separate)');
}
