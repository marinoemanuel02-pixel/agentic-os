// Content identity for every declared input. Output paths/mtimes are deliberately absent.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
};
const normalize = label => {
  const name = label.replaceAll('\\', '/').normalize('NFC');
  if (name.startsWith('/') || name.includes(':') || name.split('/').some(part => part === '..' || part === '')) throw new Error(`Invalid input label: ${label}`);
  return name;
};

export function snapshot(options) {
  const entries = [];
  const seen = new Set();
  function add(label, file) {
    const name = normalize(label);
    if (seen.has(name.toLowerCase())) throw new Error(`Duplicate input label: ${name}`);
    seen.add(name.toLowerCase());
    entries.push({path: name, sha256: hash(fs.readFileSync(file))});
  }
  function walk(dir, prefix) {
    for (const item of fs.readdirSync(dir, {withFileTypes: true})) {
      const full = path.join(dir, item.name); const name = `${prefix}/${item.name}`;
      if (item.isSymbolicLink()) throw new Error(`Undeclared linked input: ${name}`);
      if (item.isDirectory()) walk(full, name);
      else add(name, full);
    }
  }
  for (const [label, dir] of Object.entries(options.trees ?? {})) walk(dir, normalize(label));
  for (const [label, file] of Object.entries(options.files ?? {})) add(label, file);
  entries.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const result = {schema: 1, metadata: canonical(options.metadata ?? {}), entries};
  return {...result, digest: hash(JSON.stringify(result))};
}

export function assertSameInputs(before, after) {
  for (const manifest of [before, after]) {
    if (manifest.schema !== 1 || !Array.isArray(manifest.entries) || !manifest.metadata || typeof manifest.metadata !== 'object') throw new Error('Manifest integrity failed: missing schema/content');
    const identity = {schema: manifest.schema, metadata: canonical(manifest.metadata), entries: manifest.entries};
    if (hash(JSON.stringify(identity)) !== manifest.digest) throw new Error('Manifest integrity failed: content does not match digest');
  }
  if (before.digest !== after.digest) {
    const a = new Map(before.entries.map(entry => [entry.path, entry.sha256]));
    const b = new Map(after.entries.map(entry => [entry.path, entry.sha256]));
    const changed = [...new Set([...a.keys(), ...b.keys()])].filter(key => a.get(key) !== b.get(key));
    throw new Error(`Inputs changed: ${changed.join(', ') || 'runtime metadata'}`);
  }
}

export function assertExportArtifacts(manifest, artifacts) {
  if (!manifest.exports?.length) throw new Error('Unsealed export manifest');
  for (const artifact of artifacts) {
    const entry = manifest.exports.find(entry => entry.name === path.basename(artifact));
    if (!entry) throw new Error(`Export not bound to manifest: ${path.basename(artifact)}`);
    if (entry.sha256 !== hash(fs.readFileSync(artifact))) throw new Error(`Export changed: ${entry.name}`);
  }
  return true;
}

export function assertRendererSource(expected, rendered, label = 'source') {
  const resolved = file => {
    const value = fs.realpathSync.native(file).normalize('NFC');
    return process.platform === 'win32' ? value.toLowerCase() : value;
  };
  if (resolved(expected) !== resolved(rendered)) throw new Error(`Renderer ${label} differs from declared input`);
  return true;
}

export function projectInputs(root) {
  const home = process.env.USERPROFILE;
  if (!home || !process.env.WINDIR) throw new Error('Windows USERPROFILE/WINDIR required');
  const name = JSON.parse(fs.readFileSync(path.join(root, 'tools/package.json'), 'utf8')).name;
  const media = process.env.AOS_VIDEO_MEDIA_ROOT ? path.resolve(process.env.AOS_VIDEO_MEDIA_ROOT) : path.join(home, '.aos/video', name);
  const modules = process.env.AOS_REMOTION_MODULES ? path.resolve(process.env.AOS_REMOTION_MODULES) : path.join(home, '.aos/scratch/video-agi-race/node_modules');
  const shared = path.dirname(modules);
  assertRendererSource(path.join(root, 'src'), path.join(media, 'app/src'));
  assertRendererSource(modules, path.join(media, 'app/node_modules'), 'dependencies');
  const files = {};
  for (const name of ['remotion.config.ts', 'package.json', 'tsconfig.json', 'render.sh', 'build.sh', 'mix.sh', 'audio.mts', 'make-voice.cjs', 'package-outputs.mts']) files[`tools/${name}`] = path.join(root, 'tools', name);
  for (const name of ['script.md', 'sources.md', 'qa.env']) files[name] = path.join(root, name);
  if (fs.existsSync(path.join(root, 'claims.json'))) files['claims.json'] = path.join(root, 'claims.json');
  files['dependencies/package-lock.json'] = path.join(shared, 'package-lock.json');
  const fontRoot = path.join(process.env.WINDIR, 'Fonts');
  const fonts = fs.readdirSync(fontRoot).filter(name => /^(bahnschrift|sitka|georgia|arial|segoeui).*\.(ttf|ttc|otf)$/i.test(name));
  if (!fonts.some(name => /^bahnschrift/i.test(name)) || !fonts.some(name => /^sitka/i.test(name))) throw new Error('Required fonts missing');
  for (const name of fonts) files[`fonts/${name}`] = path.join(fontRoot, name);
  for (const name of ['model.onnx', 'voices.bin', 'tokens.txt', 'lexicon-us-en.txt']) files[`voice-engine/${name}`] = path.join(home, '.aos/models/kokoro-multi-lang-v1_0', name);
  const remotionVersion = JSON.parse(fs.readFileSync(path.join(modules, '@remotion/cli/package.json'), 'utf8')).version;
  const ffmpegVersion = execFileSync('ffmpeg', ['-version'], {encoding: 'utf8', windowsHide: true}).split(/\r?\n/)[0];
  return {trees: {src: path.join(root, 'src'), public: path.join(media, 'app/public'), audio: path.join(media, 'audio')}, files,
    metadata: {node: process.version, remotion: remotionVersion, ffmpeg: ffmpegVersion, platform: process.platform, arch: process.arch, gl: 'angle',
      voice: JSON.parse(fs.readFileSync(path.join(root, 'src/data/vo.json'), 'utf8')).map(({id, sid, speed}) => ({id, sid: sid ?? null, speed: speed ?? null}))}};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  try {
    const [mode, target, ...artifacts] = process.argv.slice(2);
    if (!['write', 'verify', 'seal'].includes(mode) || !target) throw new Error('Usage: input-manifest.mjs write|verify|seal <manifest.json> [export files]');
    const current = snapshot(projectInputs(root));
    if (mode === 'write') fs.writeFileSync(target, JSON.stringify(current, null, 2) + '\n');
    else {
      const previous = JSON.parse(fs.readFileSync(target, 'utf8'));
      assertSameInputs(previous, current);
      if (mode === 'seal') {
        if (!artifacts.length) throw new Error('Seal needs export artifacts');
        previous.exports = artifacts.map(file => ({name: path.basename(file), sha256: hash(fs.readFileSync(file))}));
        fs.writeFileSync(target, JSON.stringify(previous, null, 2) + '\n');
      } else if (artifacts.length) assertExportArtifacts(previous, artifacts);
    }
    console.log(`PASS: ${mode} input manifest, ${current.entries.length} files, ${current.digest}`);
  } catch (error) {
    console.error(`Input manifest failed: ${error.message.replaceAll(root, '<project>').replaceAll(process.env.USERPROFILE ?? 'unused', '<home>')}`);
    process.exitCode = 1;
  }
}
