// One fetch at a time per film: a lock file in its media root (taken over after 30 minutes, e.g. after a crash).
import {closeSync, mkdirSync, openSync, rmSync, statSync} from 'node:fs';
import {join} from 'node:path';
import {filmMediaRoot} from './paths.mjs';

const STALE_MS = 30 * 60 * 1000;

export async function withFilmLock(filmDir, fn) {
  const root = filmMediaRoot(filmDir);
  mkdirSync(root, {recursive: true});
  const lock = join(root, 'assets.lock');
  for (;;) {
    try {
      closeSync(openSync(lock, 'wx'));
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      try { if (Date.now() - statSync(lock).mtimeMs > STALE_MS) rmSync(lock, {force: true}); } catch { /* released meanwhile */ }
      await new Promise(r => setTimeout(r, 100));
    }
  }
  try {
    return await fn();
  } finally {
    rmSync(lock, {force: true});
  }
}
