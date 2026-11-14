// Tests for tools/checks/delivery.mjs: fixture strings only (no ffmpeg), plus one optional synthetic-clip run.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {
  evaluate,
  parseAudioCsv,
  parseBlackdetect,
  parseEbur128,
  parseFreezedetect,
  parseQaEnv,
  parseSrt,
  parseVideoCsv,
  resolveLimits,
} from './delivery.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT = path.join(here, 'delivery.mjs');

const SUMMARY = (i, peak) => `
[Parsed_ebur128_0 @ 000001] Summary:

  Integrated loudness:
    I:         ${i} LUFS
    Threshold: -24.5 LUFS

  Loudness range:
    LRA:         5.0 LU

  True peak:
    Peak:       ${peak} dBFS
`;
const SRT_OK = `1
00:00:00,000 --> 00:00:02,000
Hello there

2
00:00:02,000 --> 00:00:70,000
Second cue
`.replace('00:00:70,000', '00:01:10,000');

const good = (over = {}) => ({
  video: parseVideoCsv('h264,1080,1920,yuv420p,30/1\r\n'),
  audio: parseAudioCsv('aac,48000,2\n'),
  duration: 72,
  loudness: parseEbur128(SUMMARY('-14.0', '-1.5')),
  black: [],
  freeze: [],
  cues: parseSrt(SRT_OK),
  ...over,
});
const LIM = {width: 1080, height: 1920, min: 60, max: 90};
const fails = (m, limits = LIM) => evaluate(m, limits).filter((r) => !r.ok);

test('parsers read fixtures', () => {
  assert.deepEqual(parseVideoCsv('h264,1080,1920,yuv420p,30/1,\n'), {
    codec: 'h264', width: 1080, height: 1920, pixFmt: 'yuv420p', fps: '30/1', text: 'h264,1080,1920,yuv420p,30/1',
  });
  assert.equal(parseAudioCsv('aac,48000,2\n').text, 'aac,48000,2');
  assert.deepEqual(parseEbur128(SUMMARY('-14.2', '-1.3')), {integrated: -14.2, peak: -1.3});
  assert.deepEqual(parseBlackdetect('x black_start:1.5 black_end:3 black_duration:1.5\nnoise'), [
    {start: 1.5, end: 3, duration: 1.5},
  ]);
  assert.deepEqual(
    parseFreezedetect('lavfi.freezedetect.freeze_start: 4\nlavfi.freezedetect.freeze_duration: 2.5\nlavfi.freezedetect.freeze_end: 6.5'),
    [{start: 4, duration: 2.5}],
  );
  assert.equal(parseSrt(SRT_OK).length, 2);
  assert.equal(parseSrt(SRT_OK)[1].end, 70);
});

test('a valid portrait short passes', () => {
  const r = evaluate(good(), LIM);
  assert.ok(r.length >= 8);
  assert.deepEqual(r.filter((x) => !x.ok), []);
  assert.ok(r.every((x) => typeof x.text === 'string' && x.text.length > 0));
});

test('wrong size fails; 1920x1080 passes when the limits say so', () => {
  const landscape = good({video: parseVideoCsv('h264,1920,1080,yuv420p,30/1')});
  assert.equal(fails(landscape).length, 1);
  assert.deepEqual(fails(landscape, {...LIM, width: 1920, height: 1080}), []);
});

test('loudness outside -15..-13 fails, both sides', () => {
  assert.equal(fails(good({loudness: parseEbur128(SUMMARY('-16.0', '-1.5'))})).length, 1);
  assert.equal(fails(good({loudness: parseEbur128(SUMMARY('-12.0', '-1.5'))})).length, 1);
});

test('true peak above -1.0 fails', () => {
  assert.equal(fails(good({loudness: parseEbur128(SUMMARY('-14.0', '-0.5'))})).length, 1);
});

test('missing loudness measurement fails', () => {
  assert.ok(fails(good({loudness: parseEbur128('nothing here')})).length >= 1);
});

test('a black segment fails', () => {
  assert.equal(fails(good({black: parseBlackdetect('black_start:10 black_end:11 black_duration:1')})).length, 1);
});

test('a frozen segment fails', () => {
  const freeze = parseFreezedetect('lavfi.freezedetect.freeze_start: 5\nlavfi.freezedetect.freeze_duration: 1.4');
  assert.equal(fails(good({freeze})).length, 1);
});

test('a caption past the end fails', () => {
  const cues = parseSrt('1\n00:00:00,000 --> 00:01:20,000\nlate\n');
  assert.equal(fails(good({cues})).length, 1);
});

test('overlapping, backwards and empty captions fail', () => {
  const overlap = parseSrt('1\n00:00:00,000 --> 00:00:03,000\na\n\n2\n00:00:02,000 --> 00:00:04,000\nb\n');
  assert.equal(fails(good({cues: overlap})).length, 1);
  const empty = parseSrt('1\n00:00:00,000 --> 00:00:03,000\n\n\n2\n00:00:03,000 --> 00:00:04,000\nb\n');
  assert.equal(fails(good({cues: empty})).length, 1);
  assert.equal(fails(good({cues: []})).length, 1);
});

test('duration outside min/max fails', () => {
  assert.equal(fails(good({duration: 45, cues: parseSrt('1\n00:00:00,000 --> 00:00:02,000\na\n')})).length, 1);
  assert.equal(fails(good({duration: 95, cues: parseSrt('1\n00:00:00,000 --> 00:00:02,000\na\n')})).length, 1);
});

test('wrong codec or audio format fails', () => {
  assert.equal(fails(good({audio: parseAudioCsv('aac,44100,2')})).length, 1);
  assert.equal(fails(good({video: parseVideoCsv('hevc,1080,1920,yuv420p,30/1')})).length, 1);
});

test('limits: defaults, qa.env, and the environment beating qa.env', () => {
  assert.deepEqual(resolveLimits({args: {}, env: {}, qaEnvText: ''}), {width: 1080, height: 1920, min: 60, max: 90});
  const qa = 'QA_MIN_S=20\nQA_MAX_S=40\n# QA_SIZE=1920x1080\nQA_SIZE=1280x720\n';
  assert.deepEqual(parseQaEnv(qa), {QA_MIN_S: '20', QA_MAX_S: '40', QA_SIZE: '1280x720'});
  assert.deepEqual(resolveLimits({args: {}, env: {}, qaEnvText: qa}), {width: 1280, height: 720, min: 20, max: 40});
  assert.deepEqual(resolveLimits({args: {}, env: {QA_MIN_S: '30', QA_SIZE: '1080x1080'}, qaEnvText: qa}),
    {width: 1080, height: 1080, min: 30, max: 40});
  assert.deepEqual(resolveLimits({args: {size: '1920x1080', min: '5', max: '9'}, env: {QA_MIN_S: '30'}, qaEnvText: qa}),
    {width: 1920, height: 1080, min: 5, max: 9});
});

const hasFfmpeg = spawnSync('ffmpeg', ['-version'], {encoding: 'utf8'}).status === 0;
test('CLI on a synthetic 2 s clip (needs ffmpeg)', {skip: !hasFfmpeg && 'ffmpeg not on PATH'}, () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'delivery-'));
  try {
    const mp4 = path.join(dir, 'c.mp4');
    const srt = path.join(dir, 'c.srt');
    const report = path.join(dir, 'r.md');
    const mk = spawnSync('ffmpeg', ['-nostdin', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=s=1080x1920:r=30:d=2',
      '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:d=2', '-ac', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-shortest', mp4], {encoding: 'utf8'});
    assert.equal(mk.status, 0, mk.stderr);
    fs.writeFileSync(srt, '1\n00:00:00,000 --> 00:00:01,500\nhi\n');
    const run = spawnSync(process.execPath, [SCRIPT, mp4, srt, '--min', '1', '--max', '3', '--report', report], {encoding: 'utf8'});
    const out = run.stdout + run.stderr;
    assert.match(out, /- PASS video h264,1080,1920,yuv420p,30\/1/);
    assert.match(out, /- PASS audio aac,48000,2/);
    assert.match(out, /- FAIL integrated loudness/); // a plain sine is not at -14 LUFS: the gate must say so
    assert.equal(run.status, 1);
    assert.match(fs.readFileSync(report, 'utf8'), /- PASS video/);
  } finally {
    fs.rmSync(dir, {recursive: true, force: true});
  }
});
