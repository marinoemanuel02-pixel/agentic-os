// The film's download budget counts network bytes received (failed and partial transfers too); a cache hit is free.
// Only a budget the user approved counts (sourcing.json budget.approvedBy "user", set by aos asset budget --by-user).
import {appendFileSync, existsSync, mkdirSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {filmMediaRoot} from './paths.mjs';

const logFile = filmDir => join(filmMediaRoot(filmDir), 'assets-budget.jsonl');

export function budgetFor(filmDir) {
  const s = JSON.parse(readFileSync(join(filmDir, 'sourcing.json'), 'utf8'));
  const approvedBytes = s.budget && s.budget.approvedBy === 'user' ? Math.round(s.budget.approvedMB * 1048576) : null;
  let usedBytes = 0;
  if (existsSync(logFile(filmDir))) {
    for (const line of readFileSync(logFile(filmDir), 'utf8').split('\n')) if (line.trim()) usedBytes += JSON.parse(line).bytes;
  }
  return {approvedBytes, usedBytes};
}

export function reserve(filmDir, bytes) {
  const {approvedBytes, usedBytes} = budgetFor(filmDir);
  if (approvedBytes === null) return {ok: false, remaining: 0};
  const remaining = approvedBytes - usedBytes;
  return {ok: bytes <= remaining, remaining};
}

export function charge(filmDir, bytes, url, outcome) {
  mkdirSync(filmMediaRoot(filmDir), {recursive: true});
  appendFileSync(logFile(filmDir), JSON.stringify({ts: new Date().toISOString(), bytes, url, outcome}) + '\n');
}
