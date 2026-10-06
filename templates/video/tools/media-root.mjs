// Where a film's heavy media lives: AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<film folder name>. The film folder is the
// project folder, or for a git worktree its main checkout (read from the worktree's .git file), so a copied project
// never writes into the film it was copied from and a delegate worktree keeps its film's media. The template itself
// is refused (no ~/.aos/video/{{name}}).
import {existsSync, readFileSync, statSync} from 'node:fs';
import {homedir} from 'node:os';
import {basename, join, resolve} from 'node:path';

export function filmName(projectDir) {
  const dir = resolve(projectDir);
  const git = join(dir, '.git');
  if (existsSync(git) && statSync(git).isFile()) {
    const m = /^gitdir:\s*(.+?)[\/]\.git[\/]worktrees[\/][^\/]+\s*$/m.exec(readFileSync(git, 'utf8'));
    if (m) return basename(m[1]);
  }
  return basename(dir);
}

export function mediaRoot(projectDir) {
  if (process.env.AOS_VIDEO_MEDIA_ROOT) return resolve(process.env.AOS_VIDEO_MEDIA_ROOT);
  const name = filmName(projectDir);
  if (name.includes('{{')) throw new Error(`media root: unsubstituted project name "${name}"`);
  if (existsSync(join(resolve(projectDir), '_gitignore'))) throw new Error('media root: refusing the video template; run tools from a project made by aos video new, or set AOS_VIDEO_MEDIA_ROOT');
  return join(homedir(), '.aos', 'video', name);
}
