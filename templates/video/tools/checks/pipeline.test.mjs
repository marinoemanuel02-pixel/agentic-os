import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';

const template = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const scratch = process.env.AOS_VIDEO_TEST_ROOT || path.join(os.homedir(), '.aos/scratch/video-template-tests');
fs.mkdirSync(scratch, {recursive: true});
const fixture = () => {
  const root = fs.mkdtempSync(path.join(scratch, 'case space-'));
  fs.cpSync(template, root, {recursive: true});
  return root;
};
const put = (r, p, text) => {fs.mkdirSync(path.dirname(path.join(r, p)), {recursive: true}); fs.writeFileSync(path.join(r, p), text);};
const run = (r, p, env = {}, args = []) => spawnSync(process.execPath, ['--no-warnings', p, ...args], {
  cwd: r, env: {...process.env, HOME: path.join(r, 'test-home'), USERPROFILE: path.join(r, 'test-home'), ...env}, encoding: 'utf8', timeout: 30000,
});
const moduleAt = (p) => import(pathToFileURL(path.join(template, p)));

test('CLI gates run from paths with spaces rather than silently passing', () => {
  const r = fixture();
  const joins = run(r, 'tools/checks/joins.mts');
  assert.equal(joins.status, 1);
  assert.match(joins.stderr, /no start\/end poses/);
  const motion = run(r, 'tools/checks/motion.mjs');
  assert.equal(motion.status, 2);
  assert.match(motion.stderr, /usage:/);
});

test('shotCamera holds both dissolve ends and rejects non-finite or unordered keys', async () => {
  const {shotCamera} = await moduleAt('src/lib/shot-camera.ts');
  const a = {pos: [0, 2, 8], target: [0, 1, 0], fov: 32};
  const b = {...a, pos: [3, 2, 8]};
  const s = {id: 'demo', frames: 100, xin: 20, tail: 20};
  const j = {start: a, end: b};
  for (const f of [0, 10, 20]) assert.deepEqual(shotCamera(s, j, [{f: 50, pose: b}], f), a);
  for (const f of [100, 110, 120]) assert.deepEqual(shotCamera(s, j, [], f), b);
  assert.throws(() => shotCamera(s, j, [{f: 19, pose: b}], 30), /not after/);
  assert.throws(() => shotCamera(s, j, [{f: 100, pose: b}], 30), /slot end/);
  assert.throws(() => shotCamera(s, j, [{f: NaN, pose: b}], 30), /finite/);
  assert.throws(() => shotCamera(s, {start: {...a, pos: [NaN, 2, 8]}, end: b}, [], 0), /finite/);
  assert.throws(() => shotCamera(s, j, [], NaN), /finite/);
});

test('word cues share frame maths and refuse missing occurrences', async () => {
  const {makeCues} = await moduleAt('src/lib/cue-core.ts');
  const c = makeCues({L1: [['Again,', 0.2, 0.4], ['again', 1.2, 1.4]]}, [{id: 'L1', from: 60, seconds: 2}], [{id: 'S1', from: 40}], 30);
  assert.equal(c.cue('S1', 'L1', 'again', 2), 56);
  assert.equal(c.lineEnd('S1', 'L1'), 80);
  assert.throws(() => c.wordAt('L1', 'absent'), /not found/);
  assert.throws(() => c.cue('missing', 'L1', 'again'), /unknown/);
});

test('claims CLI fails stale narration and passes reviewed scaffold data', () => {
  const r = fixture();
  put(r, 'claims.json', JSON.stringify({lines: [{id: 'L1', text: 'stale', kind: 'illustration', reviewed: true, sources: []}], sources: {}, screen: []}));
  const bad = run(r, 'tools/checks/claims.mjs');
  assert.notEqual(bad.status, 0);
  assert.match(bad.stderr, /Unreviewed narration/);
  const lines = JSON.parse(fs.readFileSync(path.join(r, 'src/data/lines.json')));
  put(r, 'claims.json', JSON.stringify({lines: lines.map(l => ({id: l.id, text: l.text, kind: 'illustration', reviewed: true, sources: []})), sources: {}, screen: []}));
  assert.equal(run(r, 'tools/checks/claims.mjs').status, 0);
  put(r, 'claims.json', JSON.stringify({lines: lines.map(l => ({id: l.id, text: l.text, kind: 'illustration', reviewed: true})), sources: {}, screen: []}));
  assert.match(run(r, 'tools/checks/claims.mjs').stderr, /Missing sources array/);
  put(r, 'claims.json', JSON.stringify({lines: lines.map(l => ({id: l.id, text: l.text, kind: 'illustration', reviewed: true, sources: []})), sources: {}, screen: [{texts: ['Claim'], kind: 'fact', reviewed: true, sources: []}]}));
  assert.match(run(r, 'tools/checks/claims.mjs').stderr, /Unsourced fact/);
  put(r, 'claims.json', JSON.stringify({lines: lines.map(l => ({id: l.id, text: l.text, kind: 'fct', reviewed: true, sources: []})), sources: {}, screen: []}));
  assert.match(run(r, 'tools/checks/claims.mjs').stderr, /Unknown claim kind/);
});

test('captions fall back to narration while retaining explicit caption text', () => {
  const r = fixture();
  const look = path.join(r, 'src/lib/look.ts');
  fs.writeFileSync(look, fs.readFileSync(look, 'utf8').replace('BPM = 100', 'BPM = 75'));
  put(r, 'src/data/vo.json', JSON.stringify([{id: 'L1', file: 'vo/L1.wav', seconds: 2}]));
  for (const [row, expected] of [[{id: 'L1', text: 'Fallback words.'}, 'Fallback words.'], [{id: 'L1', text: 'Narration.', caption: 'Caption words.'}, 'Caption words.']]) {
    put(r, 'src/data/lines.json', JSON.stringify([row]));
    const p = run(r, 'tools/package-outputs.mts');
    assert.equal(p.status, 0, p.stderr);
    assert.match(fs.readFileSync(path.join(r, 'exports/{{name}}.srt'), 'utf8'), new RegExp(expected.replaceAll('.', '\\.')));
  }
  put(r, 'src/data/lines.json', JSON.stringify([{id: 'L1', text: 'Narration.', caption: ''}]));
  assert.equal(run(r, 'tools/package-outputs.mts').status, 0);
  assert.equal(fs.readFileSync(path.join(r, 'exports/{{name}}.srt'), 'utf8'), '');
  put(r, 'src/data/lines.json', JSON.stringify([{id: 'L1'}]));
  assert.match(run(r, 'tools/package-outputs.mts').stderr, /Missing caption\/text for L1/);
});

const audioFixture = () => {
  const r = fixture(), media = path.join(r, 'private-media');
  const look = path.join(r, 'src/lib/look.ts');
  fs.writeFileSync(look, fs.readFileSync(look, 'utf8').replace('BPM = 100', 'BPM = 75'));
  const wav = Buffer.alloc(44 + 4800 * 2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22); wav.writeUInt32LE(48000, 24); wav.writeUInt32LE(96000, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(9600, 40);
  put(media, 'app/public/vo/L1.wav', wav);
  put(r, 'src/data/vo.json', JSON.stringify([{id: 'L1', file: 'vo/L1.wav', seconds: 0.1}]));
  put(r, 'src/data/words.json', JSON.stringify({L1: [['First', 0, 0.1]]}));
  put(r, 'src/data/words.sha256.json', JSON.stringify({L1: crypto.createHash('sha256').update(wav).digest('hex')}));
  return {r, media};
};

test('audio builds only in the private media root on BEAT/FPS timing', () => {
  const {r, media} = audioFixture();
  const p = run(r, 'tools/audio.mts', {AOS_VIDEO_MEDIA_ROOT: media});
  assert.equal(p.status, 0, p.stderr);
  const plan = JSON.parse(fs.readFileSync(path.join(media, 'audio/plan.json')));
  assert.ok(Math.abs(plan.seconds - 14 * 24 / 30) < 1 / 48000);
  const wav = fs.readFileSync(path.join(media, 'audio/vo.wav'));
  assert.ok(Math.abs(wav.readUInt32LE(40) / (48000 * 4) - (plan.seconds + 2.5)) <= 1 / 48000);
});

test('changed voice refuses before overwriting any soundtrack stem', () => {
  const {r, media} = audioFixture();
  put(r, 'src/data/words.sha256.json', JSON.stringify({L1: 'outdated'}));
  for (const f of ['music.wav', 'sfx.wav', 'vo.wav']) put(media, 'audio/' + f, 'sentinel');
  const p = run(r, 'tools/audio.mts', {AOS_VIDEO_MEDIA_ROOT: media});
  assert.notEqual(p.status, 0);
  assert.match(p.stderr, /voice changed since its word times/);
  for (const f of ['music.wav', 'sfx.wav', 'vo.wav']) assert.equal(fs.readFileSync(path.join(media, 'audio', f), 'utf8'), 'sentinel');
});

test('every media writer honours AOS_VIDEO_MEDIA_ROOT and build gates precede audio/render', () => {
  for (const f of ['audio.mts', 'build.sh', 'frames.sh', 'make-voice.cjs', 'mix.sh', 'qa.sh', 'render.sh', 'screen.mjs', 'still.sh', 'sync-app.sh', 'verify.mjs', 'verify-hero.mjs', 'word-times.py']) {
    assert.match(fs.readFileSync(path.join(template, 'tools', f), 'utf8'), /AOS_VIDEO_MEDIA_ROOT/, f);
  }
  const build = fs.readFileSync(path.join(template, 'tools/build.sh'), 'utf8');
  for (const gate of ['checks/claims.mjs', 'checks/screen-text.mjs', 'check-plan.mts', 'checks/joins.mts']) {
    assert.ok(build.indexOf(gate) >= 0 && build.indexOf(gate) < build.indexOf('tools/audio.mts'), gate);
  }
});

test('hero verifier requires explicit compositions before writing anything', () => {
  const r = fixture(), media = path.join(r, 'private-media');
  const p = run(r, 'tools/verify-hero.mjs', {AOS_VIDEO_MEDIA_ROOT: media});
  assert.notEqual(p.status, 0);
  assert.match(p.stderr, /usage:/);
  assert.equal(fs.existsSync(media), false);
});

test('standard verifier rejects AppData before creating a runner', () => {
  const r = fixture(), media = path.join(r, 'AppData', 'private-media');
  const p = run(r, 'tools/verify.mjs', {AOS_VIDEO_MEDIA_ROOT: media}, ['S01']);
  assert.notEqual(p.status, 0);
  assert.match(p.stderr, /refusing to write under AppData/);
  assert.equal(fs.existsSync(media), false);
});

test('screen image scratch stays under the private media override', () => {
  const r = fixture(), media = path.join(r, 'private-media');
  put(media, 'qa/shots/S01.png', 'fixture');
  fs.mkdirSync(path.join(r, 'qa'), {recursive: true});
  put(r, 'mock-screen.mjs', `
    import cp from 'node:child_process'; import fs from 'node:fs'; import path from 'node:path';
    import assert from 'node:assert/strict'; import {syncBuiltinESMExports} from 'node:module';
    cp.execFileSync = (cmd, args) => {
      assert.equal(cmd, 'magick');
      assert.ok(args.at(-1).startsWith(process.env.AOS_VIDEO_MEDIA_ROOT + path.sep), 'scratch outside private media root');
      fs.writeFileSync(args.at(-1), 'fixture image'); return '';
    };
    globalThis.fetch = async () => ({json: async () => ({message: {content: '{"text_on_screen":"Example"}'}})});
    syncBuiltinESMExports();
  `);
  const p = run(r, '--import', {AOS_VIDEO_MEDIA_ROOT: media}, ['./mock-screen.mjs', 'tools/screen.mjs']);
  assert.equal(p.status, 0, p.stderr);
  assert.match(fs.readFileSync(path.join(r, 'qa/screen.md'), 'utf8'), /Example/);
});

test('screen CLI scans a general scaffold and authored JSX rather than film-specific library paths', () => {
  const r = fixture();
  put(r, 'claims.json', JSON.stringify({screen: []}));
  assert.equal(run(r, 'tools/checks/screen-text.mjs').status, 0);
  put(r, 'src/shots/Example.tsx', '<Reveal>Simple words</Reveal>');
  assert.match(run(r, 'tools/checks/screen-text.mjs').stderr, /on screen but not in claims.json/);
  put(r, 'claims.json', JSON.stringify({screen: [{texts: ['Simple words'], reviewed: true, kind: 'label'}]}));
  assert.equal(run(r, 'tools/checks/screen-text.mjs').status, 0);
});

test('both verifiers write only beneath the media override using a controlled renderer fixture', () => {
  const r = fixture(), media = fs.mkdtempSync(path.join(scratch, 'media-')), shared = path.join(r, 'modules');
  fs.mkdirSync(path.join(shared, '@remotion/cli'), {recursive: true});
  put(r, 'mock-renderer.mjs', `
    import cp from 'node:child_process'; import fs from 'node:fs'; import {syncBuiltinESMExports} from 'node:module';
    cp.execFileSync = (cmd, args) => {
      if (cmd === 'git') return args.includes('--show-toplevel') ? process.env.TEST_CHECKOUT : 'test-branch';
      if (cmd === 'magick') return '';
      if (args.some(a => String(a).endsWith('check-plan.mts'))) return 'plan ok';
      if (args.includes('compositions')) return 'S01 30 1920x1080 108';
      if (args.includes('still')) fs.writeFileSync(args[args.indexOf('still') + 3], 'fixture image');
      return '';
    };
    syncBuiltinESMExports();
  `);
  for (const [file, args] of [['verify.mjs', ['S01']], ['verify-hero.mjs', ['--stills', 'S01:0']]]) {
    const p = spawnSync(process.execPath, ['--no-warnings', '--import', './mock-renderer.mjs', 'tools/' + file, ...args], {
      cwd: r, env: {...process.env, HOME: path.join(r, 'test-home'), USERPROFILE: path.join(r, 'test-home'), AOS_VIDEO_MEDIA_ROOT: media, AOS_REMOTION_MODULES: shared, TEST_CHECKOUT: r},
      encoding: 'utf8', timeout: 30000,
    });
    if (/[\\/]AppData[\\/]/i.test(media)) {
      assert.notEqual(p.status, 0);
      assert.match(p.stderr, /refusing to write under AppData/);
      assert.equal(fs.existsSync(path.join(media, 'verify-app')), false);
      assert.equal(fs.existsSync(path.join(media, 'hero-verify')), false);
    } else assert.equal(p.status, 0, p.stderr);
  }
  if (!/[\\/]AppData[\\/]/i.test(media)) {
    assert.ok(fs.existsSync(path.join(media, 'verify', path.basename(r), 'S01-0.png')));
    assert.ok(fs.existsSync(path.join(media, 'hero-verify/test-branch/media/stills/S01-0.png')));
  }
  assert.equal(fs.existsSync(path.join(r, 'test-home/.aos/video/{{name}}')), false);
});

test('hero key-frame filenames follow stream order for unsorted and repeated requests', () => {
  const r = fixture(), media = fs.mkdtempSync(path.join(scratch, 'key-media-')), shared = path.join(r, 'modules');
  fs.mkdirSync(path.join(shared, '@remotion/cli'), {recursive: true});
  put(r, 'mock-stream.mjs', `
    import cp from 'node:child_process'; import fs from 'node:fs'; import {syncBuiltinESMExports} from 'node:module';
    cp.execFileSync = (cmd, args) => {
      if (cmd === 'git') return args.includes('--show-toplevel') ? process.env.TEST_CHECKOUT : 'test-branch';
      if (cmd === 'ffprobe') return JSON.stringify({streams: [{codec_type: 'video', codec_name: 'h264', width: 1920, height: 1080, r_frame_rate: '30/1'}], format: {duration: 3.6}});
      if (cmd === 'ffmpeg') {
        const select = args[args.indexOf('-vf') + 1];
        const frames = [...new Set([...select.matchAll(/eq\\(n,(\\d+)\\)/g)].map(m => Number(m[1])))].sort((a,b) => a-b);
        frames.forEach((frame, i) => fs.writeFileSync(args.at(-1).replace('%02d', String(i+1).padStart(2,'0')), 'frame ' + frame)); return '';
      }
      if (cmd === 'magick') {
        if (args[0] === 'identify') return '1920x1080';
        if (args[0] === 'compare') {const e = new Error('different'); e.stderr = '100 (0.1)'; throw e;} return '';
      }
      if (args.includes('compositions')) return 'S01 30 1920x1080 108';
      if (args.includes('render')) fs.writeFileSync(args[args.indexOf('render') + 3], 'fixture movie');
      return '';
    }; syncBuiltinESMExports();
  `);
  const p = run(r, '--import', {AOS_VIDEO_MEDIA_ROOT: media, AOS_REMOTION_MODULES: shared, TEST_CHECKOUT: r}, ['./mock-stream.mjs', 'tools/verify-hero.mjs', 'S01:90,30,30']);
  if (/[\\/]AppData[\\/]/i.test(media)) {
    assert.match(p.stderr, /refusing to write under AppData/);
    assert.equal(fs.existsSync(path.join(media, 'hero-verify')), false);
    return;
  }
  assert.equal(p.status, 0, p.stderr + p.stdout);
  const out = path.join(media, 'hero-verify/test-branch/media/S01');
  assert.equal(fs.readFileSync(path.join(out, 'key-030.png'), 'utf8'), 'frame 30');
  assert.equal(fs.readFileSync(path.join(out, 'key-090.png'), 'utf8'), 'frame 90');
});
