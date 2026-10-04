// Join H.264 segments losslessly (ffmpeg concat demuxer, stream copy) and prove no frame was lost or added.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

export const frameCount = (file) => Number(execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-count_frames',
  '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', file], {encoding: 'utf8'}).trim());

// Git Bash hands scripts /c/Users/... paths; Node on Windows would resolve them to C:\c\Users\... (alignment-now v3).
const native = (p) => (process.platform === 'win32' ? p.replace(/^\/([a-zA-Z])\//, (_, d) => `${d.toUpperCase()}:/`) : p);

export function concat(rawParts, rawOut, expectedFrames) {
  const parts = rawParts.map(native);
  const out = native(rawOut);
  const list = `${out}.txt`;
  fs.writeFileSync(list, parts.map((p) => `file '${path.resolve(p).replaceAll('\\', '/').replaceAll("'", "'\\''")}'`).join('\n') + '\n');
  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', out]);
  fs.rmSync(list);
  const n = frameCount(out);
  if (n !== expectedFrames) throw new Error(`frame count ${n} != expected ${expectedFrames}: ${out}`);
  return n;
}

// CLI: node tools/cache/concat.mjs <out.mp4> <expected frames> <file listing one part per line>
import {fileURLToPath} from 'node:url';
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [out, frames, listFile] = process.argv.slice(2);
  const parts = fs.readFileSync(listFile, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
  console.log(`concat: ${concat(parts, out, Number(frames))} frames -> ${out}`);
}
