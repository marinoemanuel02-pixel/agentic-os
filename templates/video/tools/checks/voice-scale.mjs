// Voice scale (R55): converted voice takes keep the speaker's real voice. Playing a recording at the wrong rate scales
// every frequency by one factor, which on a log-frequency axis is a pure shift: the long-term spectrum of each take
// (150-4500 Hz, tilt removed: the formant pattern) is correlated against the healthy reference takes' at every shift
// up to +-25 %, and the best shift gives the factor. Exit 1 when the median over the takes is outside 0.97-1.03 (a
// systematic shift, not one odd line). Seen on huggingface-it (2026-10-30): WhatsApp takes played at 88.2 kHz instead
// of 96 came out at x0.90-0.96, 8 % slow and 1.5 semitones low, and only the operator's ear caught it. Pitch alone
// was ambiguous there (intonation changes from line to line), so it is not measured.
//   node tools/checks/voice-scale.mjs --ref healthy.wav [more.wav] --takes take1.wav take2.m4a ... [--out receipt.json]
//   node tools/checks/voice-scale.mjs --receipt src/data/voice-scale.json --voice src/data/words.sha256.json   (QA)
// tools/ingest-voice.py --ref=... runs the first form before it cuts anything and keeps the receipt in
// src/data/voice-scale.json; QA refuses a human voice without a passing receipt for the current line WAVs.
// WAVs are read here; anything else is decoded with ffmpeg (on PATH).
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const LIMITS = [0.97, 1.03];
const N = 4096; // FFT frame (11.7 Hz bins at 48 kHz), hop N / 4
const LO = 150;
const HI = 4500;
const POINTS = 1200;
const STEP = Math.log(HI / LO) / (POINTS - 1);
const GRID = Float64Array.from({length: POINTS}, (_, i) => Math.exp(Math.log(LO) + i * STEP));
const LOG_GRID = GRID.map(Math.log);
const MAX_SHIFT = 0.25; // in natural-log frequency: factors from x0.78 to x1.28

/** A WAV file's samples as mono Float64 in -1..1: PCM 16/24/32-bit or IEEE float 32/64-bit, any channel count. */
export const readWav = (buf) => {
  if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') throw new Error('not a WAV file');
  let fmt = null;
  for (let at = 12; at + 8 <= buf.length;) {
    const id = buf.toString('ascii', at, at + 4);
    const size = buf.readUInt32LE(at + 4);
    const body = at + 8;
    if (id === 'fmt ') {
      let format = buf.readUInt16LE(body);
      if (format === 0xfffe) format = buf.readUInt16LE(body + 24); // WAVE_FORMAT_EXTENSIBLE: the subformat GUID
      fmt = {format, channels: buf.readUInt16LE(body + 2), sr: buf.readUInt32LE(body + 4), bits: buf.readUInt16LE(body + 14)};
    } else if (id === 'data') {
      if (!fmt) throw new Error('WAV data before its format');
      const bytes = fmt.bits / 8;
      const frames = Math.floor(Math.min(size, buf.length - body) / (bytes * fmt.channels));
      const read = fmt.format === 3
        ? (o) => (bytes === 4 ? buf.readFloatLE(o) : buf.readDoubleLE(o))
        : fmt.format === 1
          ? (o) => (bytes === 2 ? buf.readInt16LE(o) / 32768 : bytes === 3 ? buf.readIntLE(o, 3) / 8388608 : buf.readInt32LE(o) / 2147483648)
          : null;
      if (!read || ![2, 3, 4, 8].includes(bytes)) throw new Error(`unsupported WAV encoding (format ${fmt.format}, ${fmt.bits} bit)`);
      const x = new Float64Array(frames);
      for (let i = 0; i < frames; i++) {
        let s = 0;
        for (let c = 0; c < fmt.channels; c++) s += read(body + (i * fmt.channels + c) * bytes);
        x[i] = s / fmt.channels;
      }
      return {x, sr: fmt.sr};
    }
    at = body + size + (size % 2);
  }
  throw new Error('WAV without a data chunk');
};

const decode = (file) => {
  if (/\.wav$/i.test(file)) {
    try {
      return readWav(fs.readFileSync(file));
    } catch {
      // an encoding this reader does not know: let ffmpeg decode it
    }
  }
  const p = spawnSync('ffmpeg', ['-nostdin', '-v', 'error', '-i', file, '-f', 'f32le', '-ac', '1', '-ar', '48000', '-'], {maxBuffer: 1 << 30});
  if (p.error || p.status !== 0) throw new Error(`${file}: ffmpeg could not decode it (${p.error ? p.error.message : String(p.stderr).trim()})`);
  const f = new Float32Array(p.stdout.buffer, p.stdout.byteOffset, Math.floor(p.stdout.length / 4));
  return {x: Float64Array.from(f), sr: 48000};
};

const COS = Float64Array.from({length: N / 2}, (_, k) => Math.cos((2 * Math.PI * k) / N));
const SIN = Float64Array.from({length: N / 2}, (_, k) => -Math.sin((2 * Math.PI * k) / N));
const HANN = Float64Array.from({length: N}, (_, i) => 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (N - 1)));

/** |FFT|^2 of one N-sample frame (iterative radix-2), bins 0 .. N/2. */
const power = (frame) => {
  const re = Float64Array.from(frame);
  const im = new Float64Array(N);
  for (let i = 1, j = 0; i < N; i++) {
    let bit = N >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      const t = re[i];
      re[i] = re[j];
      re[j] = t;
    }
  }
  for (let len = 2; len <= N; len <<= 1) {
    const half = len >> 1;
    const step = N / len;
    for (let i = 0; i < N; i += len) {
      for (let k = 0; k < half; k++) {
        const a = i + k;
        const b = a + half;
        const wr = COS[k * step];
        const wi = SIN[k * step];
        const tr = re[b] * wr - im[b] * wi;
        const ti = re[b] * wi + im[b] * wr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
      }
    }
  }
  const p = new Float64Array(N / 2 + 1);
  for (let k = 0; k <= N / 2; k++) p[k] = re[k] * re[k] + im[k] * im[k];
  return p;
};

const rms = (x, from = 0, to = x.length) => {
  let s = 0;
  for (let i = from; i < to; i++) s += x[i] * x[i];
  return Math.sqrt(s / Math.max(1, to - from));
};

/** Long-term spectrum of the loud frames on the log grid, in dB with its linear tilt removed (the formant pattern). */
const formants = ({x, sr}) => {
  const loud = 0.5 * rms(x);
  const sum = new Float64Array(N / 2 + 1);
  let frames = 0;
  const frame = new Float64Array(N);
  for (let at = 0; at < x.length - N; at += N / 4) {
    if (rms(x, at, at + N) <= loud) continue;
    for (let i = 0; i < N; i++) frame[i] = x[at + i] * HANN[i];
    const p = power(frame);
    for (let k = 0; k < p.length; k++) sum[k] += p[k];
    frames++;
  }
  if (!frames) throw new Error('no loud frame: the take is silent or shorter than one 4096-sample frame');
  const db = GRID.map((f) => {
    const pos = (f * N) / sr;
    const lo = Math.floor(pos);
    const p = (sum[lo] + (sum[lo + 1] - sum[lo]) * (pos - lo)) / frames;
    return 10 * Math.log10(p + 1e-20);
  });
  const mx = LOG_GRID.reduce((a, b) => a + b, 0) / POINTS;
  const my = db.reduce((a, b) => a + b, 0) / POINTS;
  let sxy = 0;
  let sxx = 0;
  for (let i = 0; i < POINTS; i++) {
    sxy += (LOG_GRID[i] - mx) * (db[i] - my);
    sxx += (LOG_GRID[i] - mx) ** 2;
  }
  const slope = sxy / sxx;
  return db.map((v, i) => v - (my + slope * (LOG_GRID[i] - mx)));
};

const correlation = (a, b) => {
  const n = a.length;
  const ma = a.reduce((s, v) => s + v, 0) / n;
  const mb = b.reduce((s, v) => s + v, 0) / n;
  let ab = 0;
  let aa = 0;
  let bb = 0;
  for (let i = 0; i < n; i++) {
    ab += (a[i] - ma) * (b[i] - mb);
    aa += (a[i] - ma) ** 2;
    bb += (b[i] - mb) ** 2;
  }
  return ab / Math.sqrt(aa * bb);
};

/** The frequency factor of `take` against the reference pattern: the shift with the best correlation. */
const scaleVs = (ref, take) => {
  const m = Math.floor(MAX_SHIFT / STEP);
  let best = {r: -2, k: 0};
  for (let k = -m; k <= m; k++) {
    const a = ref.subarray(Math.max(0, k), POINTS + Math.min(0, k));
    const b = take.subarray(Math.max(0, -k), POINTS + Math.min(0, -k));
    const r = correlation(a, b);
    if (r > best.r) best = {r, k};
  }
  return {factor: Math.exp(-best.k * STEP), r: best.r};
};

const median = (v) => {
  const s = [...v].sort((a, b) => a - b);
  const h = s.length >> 1;
  return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2;
};

/** Each take's frequency factor against the mean pattern of the reference takes; ok when the median is in LIMITS. */
export const checkScale = (refs, takes, limits = LIMITS) => {
  const patterns = refs.map(formants);
  const ref = Float64Array.from({length: POINTS}, (_, i) => patterns.reduce((s, p) => s + p[i], 0) / patterns.length);
  const out = takes.map((t) => scaleVs(ref, formants(t)));
  const m = median(out.map((t) => t.factor));
  return {takes: out, median: m, ok: m >= limits[0] && m <= limits[1]};
};

const canonical = (o) => JSON.stringify(Object.keys(o || {}).sort().map((k) => [k, o[k]]));

/** QA: the ingest receipt (or none, for a synthetic voice) against the current line WAV hashes. */
export const checkReceipt = (receipt, voice) => {
  if (!receipt) return {ok: true, message: 'voice-scale: no human voice ingested (no receipt), nothing to check'};
  if (receipt.skipped) {
    return {ok: false, message: `voice-scale: human voice not scale-checked (${receipt.skipped}); re-run tools/ingest-voice.py with --ref=<a healthy take> (R55)`};
  }
  if (!receipt.ok) {
    return {ok: false, message: `voice-scale: takes shifted x${Number(receipt.median).toFixed(3)} against the reference; fix the conversion (tools/fix-aac.py) and re-ingest (R55)`};
  }
  if (canonical(receipt.lines) !== canonical(voice)) {
    return {ok: false, message: 'voice-scale: voice changed since its scale check; re-ingest with --ref=<a healthy take>, or delete src/data/voice-scale.json if the voice is no longer the human takes'};
  }
  return {ok: true, message: `voice-scale: takes checked against ${receipt.refs.length} reference take(s), median x${Number(receipt.median).toFixed(3)}`};
};

const sha256 = (file) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');

const main = (args) => {
  const list = (flag) => {
    const at = args.indexOf(flag);
    if (at < 0) return [];
    const rest = args.slice(at + 1);
    const end = rest.findIndex((a) => a.startsWith('--'));
    return end < 0 ? rest : rest.slice(0, end);
  };
  if (args.includes('--receipt')) {
    const [receiptFile] = list('--receipt');
    const [voiceFile] = list('--voice');
    const read = (f) => (f && fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null);
    const r = checkReceipt(read(receiptFile), read(voiceFile) || {});
    (r.ok ? console.log : console.error)(r.message);
    return r.ok ? 0 : 1;
  }
  const refs = list('--ref');
  const takes = list('--takes');
  if (!refs.length || !takes.length) {
    console.error('usage: voice-scale.mjs --ref healthy.wav [...] --takes take.wav [...] [--out receipt.json] | --receipt file --voice words.sha256.json');
    return 2;
  }
  const r = checkScale(refs.map(decode), takes.map(decode));
  takes.forEach((file, i) => {
    const t = r.takes[i];
    const flag = t.factor >= LIMITS[0] && t.factor <= LIMITS[1] ? '' : '  <-- CHECK';
    console.log(`${path.basename(file).slice(0, 46).padEnd(46)} spectrum x${t.factor.toFixed(3)} (r=${t.r.toFixed(2)})${flag}`);
  });
  const verdict = r.ok ? 'OK' : 'SHIFTED: wrong playback rate? (huggingface-it: 88.2 kHz instead of 96)';
  (r.ok ? console.log : console.error)(`median spectrum factor x${r.median.toFixed(3)} against ${refs.length} reference take(s): ${verdict}`);
  const [out] = list('--out');
  if (out) {
    // file names, not paths: the receipt lives in the film repo, and the hash is the identity
    const receipt = {
      checked: new Date().toISOString(),
      refs: refs.map((file) => ({file: path.basename(file), sha256: sha256(file)})),
      takes: takes.map((file, i) => ({file: path.basename(file), sha256: sha256(file), factor: Number(r.takes[i].factor.toFixed(4)), r: Number(r.takes[i].r.toFixed(3))})),
      median: Number(r.median.toFixed(4)),
      limits: LIMITS,
      ok: r.ok,
    };
    fs.mkdirSync(path.dirname(path.resolve(out)), {recursive: true});
    fs.writeFileSync(out, JSON.stringify(receipt, null, 1) + '\n');
  }
  return r.ok ? 0 : 1;
};

// exit 1 means shifted takes or a refused receipt; 2 means the check could not run (usage, unreadable file)
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    console.error(`voice-scale: ${e.message}`);
    process.exit(2);
  }
}
