// Where things live: a film's media root (same rule as the template's tools/media-root.mjs) and the shared cache.
import {existsSync, readFileSync, statSync} from 'node:fs';
import {homedir} from 'node:os';
import {basename, join, resolve} from 'node:path';

export function filmName(filmDir) {
  const dir = resolve(filmDir);
  const git = join(dir, '.git');
  if (existsSync(git) && statSync(git).isFile()) {
    const m = /^gitdir:\s*(.+?)[\\/]\.git[\\/]worktrees[\\/][^\\/]+\s*$/m.exec(readFileSync(git, 'utf8'));
    if (m) return basename(m[1]);
  }
  return basename(dir);
}

export const filmMediaRoot = filmDir => (process.env.AOS_VIDEO_MEDIA_ROOT ? resolve(process.env.AOS_VIDEO_MEDIA_ROOT) : join(homedir(), '.aos', 'video', filmName(filmDir)));
export const cacheRoot = () => (process.env.AOS_ASSET_CACHE ? resolve(process.env.AOS_ASSET_CACHE) : join(homedir(), '.aos', 'assets'));
