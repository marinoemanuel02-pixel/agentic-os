// Downloads with a hard byte cap: an unknown size is allowed only under the cap, and a transfer stops at it.
import {createWriteStream, existsSync, statSync} from 'node:fs';
import {spawnSync} from 'node:child_process';

export const USER_AGENT = 'agentic-os-video-assets/1 (personal video pipeline)';

export async function fetchHttp(url, {capBytes, dest, headers = {}}) {
  const ctl = new AbortController();
  const res = await fetch(url, {headers: {'user-agent': USER_AGENT, ...headers}, signal: ctl.signal});
  if (!res.ok) throw new Error(`fetch ${url}: HTTP ${res.status}`);
  const out = createWriteStream(dest);
  let bytes = 0;
  let complete = true;
  try {
    for await (const chunk of res.body) {
      if (bytes + chunk.length > capBytes) {
        complete = false;
        ctl.abort();
        break;
      }
      bytes += chunk.length;
      if (!out.write(chunk)) await new Promise(r => out.once('drain', r));
    }
  } catch (e) {
    if (e.name !== 'AbortError') {
      out.destroy();
      throw e;
    }
    complete = false;
  }
  await new Promise(r => out.end(r));
  return {bytes, complete};
}

// An excerpt of a video page or file through yt-dlp: only the requested seconds, cut on keyframes, under the cap.
// The real start and length are measured afterwards (measure.mjs); never trust the requested times.
export function fetchExcerpt(url, {sourceIn, sourceOut, capBytes, dest}) {
  const args = ['--no-playlist', '--no-progress', '--download-sections', `*${sourceIn}-${sourceOut}`, '--force-keyframes-at-cuts',
    '--max-filesize', String(capBytes), '-f', 'bv*[height<=1080]+ba/b[height<=1080]/b', '--merge-output-format', 'mp4', '-o', dest, url];
  const r = spawnSync('yt-dlp', args, {encoding: 'utf8', env: {...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8'}});
  const bytes = existsSync(dest) ? statSync(dest).size : 0;
  return {bytes, complete: r.status === 0 && bytes > 0 && bytes <= capBytes, log: (r.stderr || '').slice(-2000)};
}
