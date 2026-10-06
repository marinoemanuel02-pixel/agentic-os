// Downloads with a hard byte cap: an unknown size is allowed only under the cap, and a transfer stops at it. Every
// byte received is reported (also the chunk that crossed the cap, and the bytes of a transfer that failed), so the
// film's budget is charged for real traffic. URLs are sanitized before anything persists or prints them.
import {createWriteStream, existsSync, mkdtempSync, readdirSync, renameSync, rmSync, statSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {basename, dirname, join} from 'node:path';

export const USER_AGENT = 'agentic-os-video-assets/1 (personal video pipeline)';

const SECRET_PARAM = /(key|token|sig|signature|auth|password|passwd|secret|session|credential|policy|expires)/i;

// For records and messages: no user info, no credential-looking query parameters. The full URL is used only to
// make the request.
export function sanitizeUrl(url) {
  try {
    const u = new URL(url);
    u.username = '';
    u.password = '';
    for (const k of [...u.searchParams.keys()]) if (SECRET_PARAM.test(k)) u.searchParams.delete(k);
    return u.toString();
  } catch {
    return String(url).replace(/[?#].*$/, '');
  }
}

// Error text from fetch or a browser can quote the URL it was given: strip user info and credential parameters.
export function scrub(text, url = '') {
  let out = String(text);
  if (url) out = out.split(url).join(sanitizeUrl(url));
  return out.replace(/\/\/[^/@\s'"]+:[^/@\s'"]*@/g, '//').replace(/([?&])([^=&\s'"]+)=[^&\s'"#]*/g, (m, sep, k) => (SECRET_PARAM.test(k) ? `${sep}${k}=REDACTED` : m));
}

export async function fetchHttp(url, {capBytes, dest, headers = {}}) {
  const ctl = new AbortController();
  let received = 0;
  const fail = (message, cause) => Object.assign(new Error(scrub(message, url)), {bytes: received});
  let res;
  try {
    res = await fetch(url, {headers: {'user-agent': USER_AGENT, ...headers}, signal: ctl.signal});
  } catch (e) {
    throw fail(`fetch ${sanitizeUrl(url)}: ${e.message}`, e);
  }
  if (!res.ok) throw fail(`fetch ${sanitizeUrl(url)}: HTTP ${res.status}`);
  const out = createWriteStream(dest);
  let complete = true;
  try {
    for await (const chunk of res.body) {
      received += chunk.length;
      if (received > capBytes) {
        complete = false;
        ctl.abort();
        break;
      }
      if (!out.write(chunk)) await new Promise(r => out.once('drain', r));
    }
  } catch (e) {
    if (e.name !== 'AbortError') {
      out.destroy();
      throw fail(`fetch ${sanitizeUrl(url)}: transfer broke after ${received} bytes`, e);
    }
    complete = false;
  }
  await new Promise(r => out.end(r));
  return {bytes: received, complete};
}

// The bytes yt-dlp has on disk so far: the destination plus its .part and per-stream fragments.
function bytesOnDisk(dir) {
  let total = 0;
  for (const name of readdirSync(dir)) {
    try { total += statSync(join(dir, name)).size; } catch { /* renamed meanwhile */ }
  }
  return total;
}

// An excerpt of a video page or file through yt-dlp: only the requested seconds, cut on keyframes. It runs in its
// own folder, which is watched every 200 ms: past the cap the process is killed, and the most bytes seen is what it
// received. Everything but a finished destination file is removed. The real start and length are measured
// afterwards (measure.mjs); never trust the requested times. AOS_YTDLP_JS swaps in a Node stand-in for tests.
export function fetchExcerpt(url, {sourceIn, sourceOut, capBytes, dest}) {
  const work = mkdtempSync(join(dirname(dest), '.excerpt-'));
  const target = join(work, basename(dest));
  const args = ['--no-playlist', '--no-progress', '--download-sections', `*${sourceIn}-${sourceOut}`, '--force-keyframes-at-cuts',
    '--max-filesize', String(capBytes), '-f', 'bv*[height<=1080]+ba/b[height<=1080]/b', '--merge-output-format', 'mp4', '-o', target, url];
  const [exe, argv] = process.env.AOS_YTDLP_JS ? [process.execPath, [process.env.AOS_YTDLP_JS, ...args]] : ['yt-dlp', args];
  return new Promise(resolvePromise => {
    const child = spawn(exe, argv, {env: {...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8'}, windowsHide: true});
    let log = '';
    let most = 0;
    let killed = false;
    child.stderr.on('data', d => { log = (log + d).slice(-2000); });
    child.stdout.on('data', () => {});
    const watch = setInterval(() => {
      most = Math.max(most, bytesOnDisk(work));
      if (most > capBytes && !killed) {
        killed = true;
        if (process.platform === 'win32') spawn('taskkill', ['/T', '/F', '/PID', String(child.pid)], {windowsHide: true});
        else child.kill('SIGKILL');
      }
    }, 200);
    child.on('close', code => {
      clearInterval(watch);
      most = Math.max(most, bytesOnDisk(work));
      const complete = code === 0 && !killed && existsSync(target) && statSync(target).size > 0 && most <= capBytes;
      if (complete) renameSync(target, dest);
      rmSync(work, {recursive: true, force: true});
      resolvePromise({bytes: most, complete, log: log.split(url).join(sanitizeUrl(url))});
    });
  });
}
