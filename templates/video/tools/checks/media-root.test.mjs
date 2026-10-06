// One resolver for every tool: AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<project folder>; the template itself is refused.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, cpSync} from 'node:fs';
import {tmpdir, homedir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const TOOLS = dirname(dirname(fileURLToPath(import.meta.url)));
// Git Bash by path, as the other template tests do: from PowerShell a bare `bash` can be WSL's.
const BASH = process.platform === 'win32' ? join(process.env.ProgramFiles, 'Git/bin/bash.exe') : 'bash';
const {mediaRoot} = await import(new URL('../media-root.mjs', import.meta.url));

function project(name) {
  const dir = join(mkdtempSync(join(tmpdir(), 'mr-')), name);
  mkdirSync(join(dir, 'tools'), {recursive: true});
  cpSync(join(TOOLS, 'media-root.sh'), join(dir, 'tools', 'media-root.sh'));
  return dir;
}

test('falls back to ~/.aos/video/<project folder name>', () => {
  const saved = process.env.AOS_VIDEO_MEDIA_ROOT;
  delete process.env.AOS_VIDEO_MEDIA_ROOT;
  try { assert.equal(mediaRoot(project('my film')), join(homedir(), '.aos', 'video', 'my film')); }
  finally { if (saved !== undefined) process.env.AOS_VIDEO_MEDIA_ROOT = saved; }
});

test("a git worktree resolves to its main checkout's film name", () => {
  const saved = process.env.AOS_VIDEO_MEDIA_ROOT;
  delete process.env.AOS_VIDEO_MEDIA_ROOT;
  try {
    const wt = project('film-20261007-codex-task');
    const main = join(tmpdir(), 'videos', 'real film');
    writeFileSync(join(wt, '.git'), `gitdir: ${main.replaceAll('\\', '/')}/.git/worktrees/film-20261007-codex-task\n`);
    assert.equal(mediaRoot(wt), join(homedir(), '.aos', 'video', 'real film'));
    const env = {...process.env};
    const sh = spawnSync(BASH, ['-c', 'P="$1"; . "$P/tools/media-root.sh"; printf %s "$H"', '_', wt], {encoding: 'utf8', env});
    assert.equal(sh.status, 0, sh.stderr);
    assert.match(sh.stdout.replaceAll('\\', '/'), /\/\.aos\/video\/real film$/);
  } finally { if (saved !== undefined) process.env.AOS_VIDEO_MEDIA_ROOT = saved; }
});

test('AOS_VIDEO_MEDIA_ROOT wins', () => {
  const saved = process.env.AOS_VIDEO_MEDIA_ROOT;
  process.env.AOS_VIDEO_MEDIA_ROOT = join(tmpdir(), 'private-root');
  try { assert.equal(mediaRoot(project('x')), join(tmpdir(), 'private-root')); }
  finally { if (saved === undefined) delete process.env.AOS_VIDEO_MEDIA_ROOT; else process.env.AOS_VIDEO_MEDIA_ROOT = saved; }
});

test('refuses the template folder and unsubstituted placeholders', () => {
  const saved = process.env.AOS_VIDEO_MEDIA_ROOT;
  delete process.env.AOS_VIDEO_MEDIA_ROOT;
  try {
    const tpl = project('video');
    writeFileSync(join(tpl, '_gitignore'), '');
    assert.throws(() => mediaRoot(tpl), /^Error: media root: refusing the video template/);
    assert.throws(() => mediaRoot(project('{{name}}')), /^Error: media root: unsubstituted/);
  } finally { if (saved !== undefined) process.env.AOS_VIDEO_MEDIA_ROOT = saved; }
});

test('the shell resolver agrees and refuses with exit 2', () => {
  const dir = project('shell film');
  const env = {...process.env}; delete env.AOS_VIDEO_MEDIA_ROOT;
  const ok = spawnSync(BASH, ['-c', 'P="$1"; . "$P/tools/media-root.sh"; printf %s "$H"', '_', dir], {encoding: 'utf8', env});
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout.replaceAll('\\', '/'), /\/\.aos\/video\/shell film$/);
  writeFileSync(join(dir, '_gitignore'), '');
  const bad = spawnSync(BASH, ['-c', 'P="$1"; . "$P/tools/media-root.sh"; echo unreachable', '_', dir], {encoding: 'utf8', env});
  assert.equal(bad.status, 2);
  assert.doesNotMatch(bad.stdout, /unreachable/);
});

test('no tool keeps a hard-coded film fallback', () => {
  const offenders = [];
  const walk = d => {
    for (const n of readdirSync(d)) {
      const p = join(d, n);
      if (statSync(p).isDirectory()) { if (n !== 'fixtures' && n !== 'node_modules') walk(p); continue; }
      if (!/\.(sh|mjs|mts|cjs|py|ts)$/.test(n) || /\.test\.m?[jt]s$/.test(n)) continue;
      const code = readFileSync(p, 'utf8').split('\n').filter(l => !/^\s*(#|\/\/)/.test(l)).join('\n');
      if (/\.aos[\\/"', ]+video[\\/"', ]+(\{\{name\}\}|["'][A-Za-z0-9])/.test(code)) offenders.push(p);
      if (/package\.json'\), 'utf8'\)\)\.name/.test(code) && /\.aos\/video'/.test(code)) offenders.push(`${p} (media root from package.json name)`);
    }
  };
  walk(TOOLS);
  assert.deepEqual(offenders, []);
});
