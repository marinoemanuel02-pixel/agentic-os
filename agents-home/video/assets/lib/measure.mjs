// What a media file really is (ffprobe): the ledger records measured, never requested, times.
import {spawnSync} from 'node:child_process';

export function measureMedia(file) {
  const r = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration:stream=codec_type,width,height', '-of', 'json', file], {encoding: 'utf8'});
  if (r.status !== 0) throw new Error(`ffprobe ${file}: ${r.stderr}`);
  const j = JSON.parse(r.stdout);
  const streams = j.streams || [];
  const v = streams.find(s => s.codec_type === 'video') || {};
  const duration = j.format && j.format.duration ? Number(j.format.duration) : null;
  return {duration, width: v.width ?? null, height: v.height ?? null, hasAudio: streams.some(s => s.codec_type === 'audio')};
}
