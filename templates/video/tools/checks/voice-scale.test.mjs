// node --test tools/checks/voice-scale.test.mjs
// The voice-scale gate (R55): huggingface-it's WhatsApp takes were played at 88.2 kHz instead of 96, so 17 of 19
// lines came out 8 % slow and 1.5 semitones low, and only the operator's ear caught it. Synthetic voices here: one
// speaker's formants under different pitch contours and vowel orders, and the same voice played at the wrong rate.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readWav, checkScale, checkReceipt} from './voice-scale.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const SR = 48000;
const SLOW = 88200 / 96000; // the rate error seen on huggingface-it
const VOWELS = [[730, 1090, 2440, 3400], [270, 2290, 3010, 3600], [300, 870, 2240, 3300], [530, 1840, 2480, 3500]];
const WIDTH = [90, 110, 160, 250];

/** One speaker saying `seconds` of vowels: f0 contour and vowel order vary per take; speed != 1 is a wrong rate. */
const voice = ({seconds = 3, base = 120, seed = 1, speed = 1}) => {
  const n = Math.round((seconds / speed) * SR);
  const x = new Float64Array(n);
  let noise = seed * 7919;
  const w1 = 0.6 + 0.1 * seed;
  const w2 = 1.7 + 0.13 * seed;
  for (let i = 0; i < n; i++) {
    const t = (i / SR) * speed; // the voice's own time: a wrong rate scales every frequency by `speed`
    const f0 = base + 25 * Math.sin(2 * Math.PI * w1 * t) + 12 * Math.sin(2 * Math.PI * w2 * t + seed);
    const phase = base * t - (25 / (2 * Math.PI * w1)) * Math.cos(2 * Math.PI * w1 * t) - (12 / (2 * Math.PI * w2)) * Math.cos(2 * Math.PI * w2 * t + seed);
    const syllable = t * 4;
    const v = (Math.floor(syllable) + seed) % VOWELS.length;
    const F = VOWELS[v];
    let s = 0;
    for (let k = 1; k * f0 < 5000; k++) {
      const f = k * f0;
      let a = 0;
      for (let j = 0; j < 4; j++) a += 1 / (1 + ((f - F[j]) / WIDTH[j]) ** 2) / (j + 1);
      s += (a / Math.sqrt(k)) * Math.sin(2 * Math.PI * k * phase);
    }
    const envelope = 0.25 + 0.75 * Math.sin(Math.PI * (syllable % 1)) ** 2;
    noise = (noise * 1103515245 + 12345) % 2147483648;
    x[i] = 0.08 * envelope * s + 0.002 * (noise / 1073741824 - 1);
  }
  return {x, sr: SR};
};

const refs = [voice({seed: 1, base: 115}), voice({seed: 2, base: 128})];

test('takes played at the wrong rate measure near x0.92 against healthy takes, and the batch fails', () => {
  const r = checkScale(refs, [voice({seed: 3, base: 122, speed: SLOW}), voice({seed: 4, base: 110, speed: SLOW})]);
  for (const t of r.takes) assert.ok(Math.abs(t.factor - SLOW) < 0.012, `factor ${t.factor}`);
  assert.equal(r.ok, false);
});

test('healthy takes of the same voice measure near x1.0 under another pitch and vowel order, and pass', () => {
  // pitch moves one take's factor by a few percent (huggingface-it's healthy takes: x0.99-1.06), hence the median gate
  const r = checkScale(refs, [voice({seed: 3, base: 135}), voice({seed: 5, base: 105}), voice({seed: 6, base: 125})]);
  for (const t of r.takes) assert.ok(Math.abs(t.factor - 1) < 0.06, `factor ${t.factor}`);
  assert.ok(Math.abs(r.median - 1) < 0.03, `median ${r.median}`);
  assert.equal(r.ok, true);
});

test('the gate is the median: one odd take is reported but a systematic shift is what fails', () => {
  const r = checkScale(refs, [voice({seed: 3}), voice({seed: 5}), voice({seed: 6, speed: SLOW})]);
  assert.equal(r.ok, true);
  assert.ok(r.takes[2].factor < 0.95);
});

const wav = (x, {sr = SR, channels = 1, float = false} = {}) => {
  const bytes = float ? 4 : 2;
  const data = Buffer.alloc(x.length * channels * bytes);
  for (let i = 0; i < x.length; i++) {
    for (let c = 0; c < channels; c++) {
      const at = (i * channels + c) * bytes;
      if (float) data.writeFloatLE(x[i], at);
      else data.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(x[i] * 32767))), at);
    }
  }
  const head = Buffer.alloc(44);
  head.write('RIFF', 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write('WAVEfmt ', 8);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(float ? 3 : 1, 20);
  head.writeUInt16LE(channels, 22);
  head.writeUInt32LE(sr, 24);
  head.writeUInt32LE(sr * channels * bytes, 28);
  head.writeUInt16LE(channels * bytes, 32);
  head.writeUInt16LE(bytes * 8, 34);
  head.write('data', 36);
  head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
};

test('reads 16-bit PCM stereo and 32-bit float WAVs as mono', () => {
  const x = Float64Array.from([0, 0.5, -0.5, 0.25]);
  const pcm = readWav(wav(x, {channels: 2, sr: 44100}));
  assert.equal(pcm.sr, 44100);
  assert.deepEqual([...pcm.x].map((v) => Math.round(v * 100) / 100), [0, 0.5, -0.5, 0.25]);
  assert.deepEqual([...readWav(wav(x, {float: true})).x], [...x]);
});

const lines = {L01: 'aa', L02: 'bb'};

test('QA: no receipt means no human voice was ingested; a passing receipt for the current voice passes', () => {
  assert.equal(checkReceipt(null, lines).ok, true);
  assert.equal(checkReceipt({ok: true, median: 1.004, refs: [{}], lines}, lines).ok, true);
});

test('QA: a human voice ingested without a reference, with shifted takes, or replaced since fails', () => {
  assert.match(checkReceipt({skipped: 'no --ref', lines}, lines).message, /not scale-checked/);
  assert.match(checkReceipt({ok: false, median: 0.932, refs: [{}], lines}, lines).message, /shifted/);
  const changed = checkReceipt({ok: true, median: 1.0, refs: [{}], lines}, {L01: 'aa', L02: 'cc'});
  assert.equal(changed.ok, false);
  assert.match(changed.message, /voice changed since/);
});

test('the command exits 1 on shifted takes, 0 on healthy ones, and writes a receipt with each file hash', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'voice-scale-'));
  const put = (name, v) => { fs.writeFileSync(path.join(dir, name), wav(v.x)); return path.join(dir, name); };
  const ref = [put('ref1.wav', refs[0]), put('ref2.wav', refs[1])];
  const slow = [put('slow1.wav', voice({seed: 3, speed: SLOW})), put('slow2.wav', voice({seed: 4, speed: SLOW}))];
  const good = [put('good1.wav', voice({seed: 3})), put('good2.wav', voice({seed: 4}))];
  const cli = path.join(here, 'voice-scale.mjs');
  const out = path.join(dir, 'receipt.json');
  const bad = spawnSync(process.execPath, [cli, '--ref', ...ref, '--takes', ...slow, '--out', out], {encoding: 'utf8'});
  assert.equal(bad.status, 1, bad.stdout + bad.stderr);
  assert.match(bad.stdout + bad.stderr, /slow1\.wav.*x0\.9[12]/);
  assert.equal(JSON.parse(fs.readFileSync(out, 'utf8')).ok, false);
  const ok = spawnSync(process.execPath, [cli, '--ref', ...ref, '--takes', ...good, '--out', out], {encoding: 'utf8'});
  assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  const receipt = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(receipt.ok, true);
  assert.equal(receipt.takes.length, 2);
  assert.match(receipt.takes[0].sha256, /^[0-9a-f]{64}$/);
  assert.match(receipt.refs[1].sha256, /^[0-9a-f]{64}$/);
  assert.equal(receipt.takes[0].file, 'good1.wav'); // a name, never an absolute path into the film repo
});

const python = spawnSync('python', ['-I', '-c', 'import numpy'], {encoding: 'utf8'});

test('ingest-voice.py --ref refuses shifted takes before it loads the recognizer, and lets healthy ones through', {skip: python.status !== 0 && 'python with numpy is not on PATH'}, () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'voice-ingest-'));
  const put = (name, v) => { fs.writeFileSync(path.join(dir, name), wav(v.x)); return path.join(dir, name); };
  const ref = `--ref=${put('ref1.wav', refs[0])},${put('ref2.wav', refs[1])}`;
  const ingest = path.join(here, '..', 'ingest-voice.py');
  // no recognizer model: a run that gets past the scale check stops at the model, before writing anything
  const env = {...process.env, AOS_VIDEO_MEDIA_ROOT: path.join(dir, 'media'), AOS_WHISPER_MODEL: ''};
  const slow = spawnSync('python', ['-I', ingest, ref, put('slow1.wav', voice({seed: 3, speed: SLOW})), put('slow2.wav', voice({seed: 4, speed: SLOW}))], {encoding: 'utf8', env});
  assert.notEqual(slow.status, 0);
  assert.match(slow.stderr, /voice-scale check failed \(R55\)/);
  const good = spawnSync('python', ['-I', ingest, ref, put('good1.wav', voice({seed: 3})), put('good2.wav', voice({seed: 4}))], {encoding: 'utf8', env});
  assert.doesNotMatch(good.stderr, /R55/);
  assert.match(good.stdout, /median spectrum factor x(0\.9[789]|1\.0[0-3])\d* .*: OK/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(dir, 'media', 'voice', 'voice-scale.json'), 'utf8')).ok, true);
});
