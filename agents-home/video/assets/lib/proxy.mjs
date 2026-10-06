// One silent, seek-friendly proxy per asset (1080p30 H.264, GOP 30); sound is a separate per-use derivative.
import {createHash} from 'node:crypto';
import {mkdirSync, readFileSync} from 'node:fs';
import {dirname} from 'node:path';
import {spawnSync} from 'node:child_process';

const VIDEO_ARGS = ['-vf', 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p',
  '-c:v', 'libx264', '-crf', '18', '-preset', 'medium', '-g', '30', '-an'];

export const sha256File = file => createHash('sha256').update(readFileSync(file)).digest('hex');

function ffmpeg(args) {
  const r = spawnSync('ffmpeg', ['-nostdin', '-v', 'error', '-y', ...args], {encoding: 'utf8'});
  if (r.status !== 0) throw new Error(`ffmpeg ${args.join(' ')}: ${r.stderr}`);
}

export function makeProxy(input, out) {
  mkdirSync(dirname(out), {recursive: true});
  ffmpeg(['-i', input, ...VIDEO_ARGS, out]);
  return {sha256: sha256File(out), ffmpeg: VIDEO_ARGS.join(' ')};
}

export function makeAudio(input, out, fromS, toS) {
  mkdirSync(dirname(out), {recursive: true});
  const args = ['-ss', String(fromS), '-to', String(toS), '-vn', '-ac', '2', '-ar', '48000', '-c:a', 'pcm_s16le'];
  ffmpeg(['-i', input, ...args, out]);
  return {sha256: sha256File(out), ffmpeg: args.join(' ')};
}
