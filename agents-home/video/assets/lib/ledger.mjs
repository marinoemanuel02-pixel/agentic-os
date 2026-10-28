// The film's assets.json: one row per imported asset (the schema the template's tools/checks/assets.mjs checks).
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

export function readLedger(filmDir) {
  const file = join(filmDir, 'assets.json');
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {schema: 1, rows: []};
}

export const writeLedger = (filmDir, ledger) => writeFileSync(join(filmDir, 'assets.json'), JSON.stringify(ledger, null, 2) + '\n');

export function addRow(filmDir, row) {
  const ledger = readLedger(filmDir);
  if (ledger.rows.some(r => r.id === row.id)) throw new Error(`${row.id} already in assets.json`);
  ledger.rows.push(row);
  writeLedger(filmDir, ledger);
  return row;
}
