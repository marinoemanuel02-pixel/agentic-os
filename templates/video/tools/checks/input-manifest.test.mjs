import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {snapshot, assertSameInputs, assertExportArtifacts, assertRendererSource, projectInputs} from './input-manifest.mjs';
import crypto from 'node:crypto';

function fixture(t) {
  const scratch = process.env.AOS_MANIFEST_TEST_ROOT || path.join(os.homedir(), '.aos/scratch/input-manifest-tests');
  fs.mkdirSync(scratch, {recursive: true});
  const root = fs.mkdtempSync(path.join(scratch, 'run-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  for (const folder of ['src', 'public', 'audio']) fs.mkdirSync(path.join(root, folder));
  for (const [name, data] of [['src/scene.tsx', 'scene'], ['public/voice.wav', 'voice'], ['audio/score.wav', 'score'], ['font.ttf', 'font'], ['config.json', '{}']]) fs.writeFileSync(path.join(root, name), data);
  const options = {trees: {src: path.join(root, 'src'), public: path.join(root, 'public'), audio: path.join(root, 'audio')},
    files: {'fonts\\chosen.ttf': path.join(root, 'font.ttf'), 'config/config.json': path.join(root, 'config.json')}, metadata: {renderer: 'test', speaker: 26, speed: 1}};
  return {root, options};
}

test('rejects edits to picture, voice, music, font and config inputs', t => {
  const {root, options} = fixture(t);
  const before = snapshot(options);
  for (const name of ['src/scene.tsx', 'public/voice.wav', 'audio/score.wav', 'font.ttf', 'config.json']) {
    const file = path.join(root, name); const original = fs.readFileSync(file);
    fs.writeFileSync(file, Buffer.concat([original, Buffer.from('changed')]));
    assert.throws(() => assertSameInputs(before, snapshot(options)), /changed/i, name);
    fs.writeFileSync(file, original);
  }
});

test('rejects added or removed assets', t => {
  const {root, options} = fixture(t); const before = snapshot(options);
  fs.writeFileSync(path.join(root, 'public/new.svg'), '<svg/>');
  assert.throws(() => assertSameInputs(before, snapshot(options)), /changed/i);
  fs.unlinkSync(path.join(root, 'public/new.svg'));
  fs.unlinkSync(path.join(root, 'public/voice.wav'));
  assert.throws(() => assertSameInputs(before, snapshot(options)), /changed/i);
});

test('mtime, insertion order and Windows separators do not alter content identity', t => {
  const {root, options} = fixture(t); const before = snapshot(options);
  fs.utimesSync(path.join(root, 'src/scene.tsx'), new Date(1000), new Date(1000));
  const after = snapshot({...options, files: {'config/config.json': options.files['config/config.json'], 'fonts/chosen.ttf': options.files['fonts\\chosen.ttf']}, metadata: {speed: 1, speaker: 26, renderer: 'test'}});
  assertSameInputs(before, after);
  assert.ok(after.entries.some(entry => entry.path === 'fonts/chosen.ttf'));
  assert.ok(after.entries.every(entry => !entry.path.includes('\\') && !entry.path.includes(root)));
});

test('runtime or voice parameter drift invalidates evidence, output files do not', t => {
  const {root, options} = fixture(t); const before = snapshot(options);
  fs.mkdirSync(path.join(root, 'renders')); fs.writeFileSync(path.join(root, 'renders/output.mp4'), 'output');
  assertSameInputs(before, snapshot(options));
  assert.throws(() => assertSameInputs(before, snapshot({...options, metadata: {...options.metadata, speed: 0.9}})), /changed/i);
});

test('missing required input and duplicate normalized labels fail closed', t => {
  const {root, options} = fixture(t);
  assert.throws(() => snapshot({...options, files: {missing: path.join(root, 'missing.ttf')}}), /ENOENT|missing/i);
  assert.throws(() => snapshot({...options, files: {'fonts\\x': path.join(root, 'font.ttf'), 'fonts/x': path.join(root, 'font.ttf')}}), /duplicate/i);
});

test('QA rejects a different movie even when the input manifest matches', t => {
  const {root} = fixture(t); const file = path.join(root, 'export.mp4');
  fs.writeFileSync(file, 'movie-one');
  const manifest = {exports: [{name: 'export.mp4', sha256: crypto.createHash('sha256').update('movie-one').digest('hex')}]};
  assertExportArtifacts(manifest, [file]);
  fs.writeFileSync(file, 'movie-two');
  assert.throws(() => assertExportArtifacts(manifest, [file]), /export.*changed/i);
});

test('QA rejects unsealed manifests and missing artifact bindings', t => {
  const {root} = fixture(t); const file = path.join(root, 'export.mp4'); fs.writeFileSync(file, 'movie');
  assert.throws(() => assertExportArtifacts({}, [file]), /unsealed/i);
  assert.throws(() => assertExportArtifacts({exports: [{name: 'different.mp4', sha256: 'x'}]}, [file]), /bound/i);
});

test('a renderer junction to another checkout fails rather than certifying the wrong source', t => {
  const {root} = fixture(t);
  const expected = path.join(root, 'src'); const other = path.join(root, 'other-src');
  fs.mkdirSync(other);
  const junction = path.join(root, 'render-src');
  fs.symlinkSync(expected, junction, process.platform === 'win32' ? 'junction' : 'dir');
  assertRendererSource(expected, junction);
  fs.unlinkSync(junction);
  fs.symlinkSync(other, junction, process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => assertRendererSource(expected, junction), /renderer.*source/i);
});

test('accidentally edited manifest metadata cannot retain an old valid digest', t => {
  const {options} = fixture(t); const current = snapshot(options);
  const corrupted = {...current, metadata: {...current.metadata, renderer: 'edited'}};
  assert.throws(() => assertSameInputs(corrupted, current), /manifest.*integrity/i);
});

test('mixer scratch output does not change the declared audio inputs', t => {
  const {root, options} = fixture(t);
  const script = fs.readFileSync(new URL('../mix.sh', import.meta.url), 'utf8');
  const relative = script.match(/^tmp="\$H\/([^"\r\n]+)"/m)?.[1];
  assert.ok(relative, 'mixer must declare its temporary output path');
  const temporary = path.resolve(root, relative);
  assert.ok(temporary.startsWith(root + path.sep));
  const before = snapshot(options);
  fs.mkdirSync(path.dirname(temporary), {recursive: true});
  fs.writeFileSync(temporary, 'new mixed output');
  assertSameInputs(before, snapshot(options));
});

test('project wiring rejects a renderer loading a different dependency install', t => {
  const {root} = fixture(t);
  const app = path.join(root, 'app'); const modules = path.join(root, 'declared-modules');
  const other = path.join(root, 'other-modules');
  for (const dir of [app, modules, other, path.join(root, 'tools')]) fs.mkdirSync(dir);
  fs.writeFileSync(path.join(root, 'tools/package.json'), JSON.stringify({name: 'fixture'}));
  fs.symlinkSync(path.join(root, 'src'), path.join(app, 'src'), process.platform === 'win32' ? 'junction' : 'dir');
  fs.symlinkSync(other, path.join(app, 'node_modules'), process.platform === 'win32' ? 'junction' : 'dir');
  const previous = {media: process.env.AOS_VIDEO_MEDIA_ROOT, modules: process.env.AOS_REMOTION_MODULES};
  try {
    process.env.AOS_VIDEO_MEDIA_ROOT = root;
    process.env.AOS_REMOTION_MODULES = modules;
    assert.throws(() => projectInputs(root), /renderer dependencies/i);
  } finally {
    for (const [key, value] of [['AOS_VIDEO_MEDIA_ROOT', previous.media], ['AOS_REMOTION_MODULES', previous.modules]]) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});
