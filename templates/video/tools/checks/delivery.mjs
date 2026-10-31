// Delivery gate for word-cut shorts (R44): tools/qa.sh sections 1-4 for a finished MP4 + SRT of any frame size.
// qa.sh hardcodes 1920x1080 and needs build.sh outputs, so a short cannot use it; tools/finish.sh runs this instead.
// Limits mirror qa.sh: h264 / yuv420p / 30 fps / aac 48 kHz stereo, duration in [min, max], integrated loudness
// -15..-13 LUFS, true peak <= -1.0 dBTP, no black segment >= 0.5 s, no frozen segment >= 1 s, captions inside the
// duration, ordered, no overlaps, none empty.
//   node tools/checks/delivery.mjs <video.mp4> <captions.srt> [--size 1080x1920] [--min S] [--max S] [--report file]
// Size, min and max default from qa.env (QA_SIZE, QA_MIN_S, QA_MAX_S; values already in the environment win, as in
// qa.sh), then 1080x1920 and 60/90. Prints "- PASS ..." / "- FAIL ..." lines; exit 1 on any FAIL or a tool that cannot run.
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const num = (s) => Number.parseFloat(s);

/** ffprobe csv for the video stream, in ffprobe's field order: codec,width,height,pix_fmt,r_frame_rate. */
export const parseVideoCsv = (csv) => {
  const text = String(csv).replace(/\r/g, '').trim().replace(/,$/, '');
  const [codec, width, height, pixFmt, fps] = text.split(',');
  return {codec, width: Number(width), height: Number(height), pixFmt, fps, text};
};

/** ffprobe csv for the audio stream: codec,sample_rate,channels. */
export const parseAudioCsv = (csv) => {
  const text = String(csv).replace(/\r/g, '').trim().replace(/,$/, '');
  const [codec, sampleRate, channels] = text.split(',');
  return {codec, sampleRate: Number(sampleRate), channels: Number(channels), text};
};

/** The ebur128 Summary: integrated I (LUFS) and the last true Peak (dBTP); null when absent. */
export const parseEbur128 = (log) => {
  const s = String(log);
  const part = s.includes('Summary') ? s.slice(s.lastIndexOf('Summary')) : '';
  const i = part.match(/^\s*I:\s+(-?[\d.]+|-inf)\s+LUFS/m);
  const peaks = [...part.matchAll(/^\s*Peak:\s+(-?[\d.]+|-inf)\s+dBFS/gm)];
  return {
    integrated: i ? num(i[1]) : null,
    peak: peaks.length ? num(peaks[peaks.length - 1][1]) : null,
  };
};

export const parseBlackdetect = (log) =>
  [...String(log).matchAll(/black_start:([\d.]+)\s+black_end:([\d.]+)\s+black_duration:([\d.]+)/g)].map((m) => ({
    start: num(m[1]), end: num(m[2]), duration: num(m[3]),
  }));

/** freezedetect metadata lines; a segment still frozen at the end has a start and maybe no duration (null). */
export const parseFreezedetect = (log) => {
  const out = [];
  for (const m of String(log).matchAll(/freeze_(start|duration):\s*([\d.]+)/g)) {
    if (m[1] === 'start') out.push({start: num(m[2]), duration: null});
    else if (out.length) out[out.length - 1].duration = num(m[2]);
  }
  return out;
};

const stamp = (s) => {
  const m = s.trim().match(/^(\d+):(\d+):(\d+)[,.](\d+)$/);
  return m ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(`0.${m[4]}`) : NaN;
};

/** SRT text to [{index, start, end, text}] in file order. */
export const parseSrt = (text) => {
  const cues = [];
  for (const block of String(text).replace(/\r/g, '').split(/\n{2,}/)) {
    const lines = block.split('\n');
    const at = lines.findIndex((l) => l.includes('-->'));
    if (at < 0) continue;
    const [a, b] = lines[at].split('-->');
    cues.push({index: cues.length + 1, start: stamp(a), end: stamp(b), text: lines.slice(at + 1).join('\n').trim()});
  }
  return cues;
};

/** KEY=VALUE lines of a qa.env (comments and blanks skipped, quotes stripped). */
export const parseQaEnv = (text) => {
  const out = {};
  for (const line of String(text).replace(/\r/g, '').split('\n')) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)=(.*)$/);
    if (m) out[m[1]] = m[2].replace(/\s+#.*$/, '').trim().replace(/^(["'])(.*)\1$/, '$2');
  }
  return out;
};

/** Flags beat the environment, the environment beats qa.env (qa.sh's rule), then 1080x1920 and 60/90. */
export const resolveLimits = ({args = {}, env = {}, qaEnvText = ''}) => {
  const file = parseQaEnv(qaEnvText);
  const pick = (name) => (env[name] ? env[name] : file[name]);
  const size = args.size ?? pick('QA_SIZE') ?? '1080x1920';
  const m = String(size).match(/^(\d+)x(\d+)$/);
  if (!m) throw new Error(`bad size "${size}" (want WIDTHxHEIGHT)`);
  return {
    width: Number(m[1]),
    height: Number(m[2]),
    min: num(args.min ?? pick('QA_MIN_S') ?? '60'),
    max: num(args.max ?? pick('QA_MAX_S') ?? '90'),
  };
};

const fmt = (n) => (Number.isFinite(n) ? String(Math.round(n * 1000) / 1000) : 'n/a');

/** measurements -> [{ok, text}] in qa.sh's order. */
export const evaluate = (m, limits) => {
  const r = [];
  const add = (ok, text) => r.push({ok: Boolean(ok), text});
  const want = `h264,${limits.width},${limits.height},yuv420p,30/1`;
  add(m.video?.text === want, m.video?.text === want ? `video ${m.video.text}` : `video ${m.video?.text || 'unreadable'} (want ${want})`);
  const aok = m.audio?.text === 'aac,48000,2';
  add(aok, aok ? `audio ${m.audio.text}` : `audio ${m.audio?.text || 'unreadable'} (want aac,48000,2)`);
  const dur = m.duration;
  const dokay = Number.isFinite(dur) && dur >= limits.min && dur <= limits.max;
  add(dokay, `duration ${fmt(dur)}s (want ${limits.min}-${limits.max})`);
  const I = m.loudness?.integrated;
  add(I != null && I >= -15 && I <= -13, `integrated loudness ${I ?? 'unmeasured'} LUFS${I != null && I >= -15 && I <= -13 ? '' : ' (want -15..-13)'}`);
  const tp = m.loudness?.peak;
  add(tp != null && tp <= -1.0, `true peak ${tp ?? 'unmeasured'} dBTP${tp != null && tp <= -1.0 ? '' : ' (want <= -1)'}`);
  const black = m.black || [];
  add(!black.length, black.length
    ? `black segments found: ${black.map((b) => `${fmt(b.start)}-${fmt(b.end)} s`).join(', ')} (judge against intended fades)`
    : 'no black segment >= 0.5 s');
  const freeze = m.freeze || [];
  add(!freeze.length, freeze.length
    ? `frozen segments found: ${freeze.map((f) => `${fmt(f.start)} s for ${f.duration == null ? 'to the end' : `${fmt(f.duration)} s`}`).join(', ')}`
    : 'no frozen segment >= 1 s');
  const cues = m.cues || [];
  if (!cues.length) {
    add(false, 'no captions found in the SRT');
  } else {
    const last = cues[cues.length - 1].end;
    add(last <= dur, last <= dur
      ? `${cues.length} captions, last ends at ${fmt(last)}s <= ${fmt(dur)}s`
      : `last caption ends at ${fmt(last)}s > ${fmt(dur)}s`);
    let bad = 0;
    let prev = 0;
    for (const c of cues) {
      if (!Number.isFinite(c.start) || !Number.isFinite(c.end) || c.start < prev || c.end <= c.start || !c.text) bad += 1;
      prev = c.end;
    }
    add(!bad, bad ? `${bad} caption(s) overlap, run backwards or are empty` : 'captions ordered, no overlaps, none empty');
  }
  return r;
};

const run = (cmd, args) => {
  const p = spawnSync(cmd, args, {encoding: 'utf8', maxBuffer: 256 * 1024 * 1024});
  if (p.error || p.status !== 0) throw new Error(`${cmd} failed: ${p.error ? p.error.message : (p.stderr || '').trim().split('\n').slice(-2).join(' ')}`);
  return {out: p.stdout || '', err: p.stderr || ''};
};

/** Runs ffprobe and ffmpeg on the files and returns the measurements evaluate() wants. */
export const measure = (video, srtPath) => {
  const probe = (entries, stream) => run('ffprobe', ['-v', 'error', '-select_streams', stream, '-show_entries', entries, '-of', 'csv=p=0', video]).out;
  const detect = (vf) => run('ffmpeg', ['-nostdin', '-hide_banner', '-nostats', '-i', video, '-vf', vf, '-an', '-f', 'null', '-']).err;
  return {
    video: parseVideoCsv(probe('stream=codec_name,width,height,r_frame_rate,pix_fmt', 'v:0')),
    audio: parseAudioCsv(probe('stream=codec_name,sample_rate,channels', 'a:0')),
    duration: num(run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', video]).out),
    loudness: parseEbur128(run('ffmpeg', ['-nostdin', '-hide_banner', '-nostats', '-i', video, '-af', 'ebur128=peak=true', '-f', 'null', '-']).err),
    black: parseBlackdetect(detect('blackdetect=d=0.5:pix_th=0.06')),
    freeze: parseFreezedetect(detect('freezedetect=n=0.0008:d=1.0')),
    cues: parseSrt(fs.readFileSync(srtPath, 'utf8')),
  };
};

const main = (argv) => {
  const args = {};
  const pos = [];
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i].startsWith('--')) args[argv[i].slice(2)] = argv[++i];
    else pos.push(argv[i]);
  }
  if (pos.length !== 2) {
    console.error('usage: node tools/checks/delivery.mjs <video.mp4> <captions.srt> [--size WxH] [--min S] [--max S] [--report file]');
    return 1;
  }
  const qaEnv = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'qa.env');
  let results;
  try {
    const limits = resolveLimits({args, env: process.env, qaEnvText: fs.existsSync(qaEnv) ? fs.readFileSync(qaEnv, 'utf8') : ''});
    results = evaluate(measure(pos[0], pos[1]), limits);
  } catch (e) {
    console.error(`delivery check could not run: ${e.message}`);
    return 1;
  }
  const lines = results.map((x) => `- ${x.ok ? 'PASS' : 'FAIL'} ${x.text}`);
  console.log(lines.join('\n'));
  if (args.report) fs.appendFileSync(args.report, `${lines.join('\n')}\n`);
  return results.every((x) => x.ok) ? 0 : 1;
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2));
