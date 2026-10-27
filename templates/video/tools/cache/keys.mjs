// Cache keys: SHA-256 over a segment's frame range, its shot ids, every src/ file its shot modules import
// transitively (relative imports, .ts/.tsx/.mts/.js/.json), the timeline files every shot depends on, and an
// environment digest (fonts, public assets, config, runtime) taken from the input manifest. When in doubt, include.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const EXTS = ['', '.ts', '.tsx', '.mts', '.js', '.mjs', '.json', '/index.ts', '/index.tsx'];
// The edit's wiring is followed (Main's fades and libraries shape every frame), but the registry is a stop: it is
// hashed and never traversed, because it imports every shot and would tie every key to every shot (Codex reviews).
const WIRING = ['src/Main.tsx', 'src/Root.tsx', 'src/index.ts'];
const STOPS = ['src/shots/registry.ts'];
// The timeline is followed: slot lengths, the beat and the measured voice shape every segment.
const TIMELINE = ['src/data/timeline.ts', 'src/data/plan.ts'];
const IMPORT = /(?:(?:import|export)\s+(?:[^'"]*?\sfrom\s+)?|import\s*\(\s*)["'](\.{1,2}\/[^"']+)["']/g;
const sha = (data) => crypto.createHash('sha256').update(data).digest('hex');
const rel = (root, file) => path.relative(root, file).split(path.sep).join('/');

function resolve(fromFile, spec) {
  const base = path.resolve(path.dirname(fromFile), spec);
  for (const ext of EXTS) {
    const file = base + ext;
    if (fs.existsSync(file) && fs.statSync(file).isFile()) return file;
  }
  throw new Error(`cannot resolve import ${spec} from ${fromFile}`);
}

/** Every file reachable from `entries` (paths relative to root) through relative imports; cycles terminate. */
export function closure(root, entries, stops = []) {
  const stop = new Set(stops.map((s) => path.resolve(root, s)));
  const seen = new Set();
  const stack = entries.map((e) => path.resolve(root, e));
  while (stack.length) {
    const file = stack.pop();
    if (seen.has(file)) continue;
    seen.add(file);
    if (file.endsWith('.json') || stop.has(file)) continue;
    const text = fs.readFileSync(file, 'utf8');
    for (const m of text.matchAll(IMPORT)) stack.push(resolve(file, m[1]));
  }
  return [...seen].map((f) => rel(root, f)).sort();
}

/** The module under src/shots that declares `export const <id>...` (one file per shot or one per chapter). */
export function shotModules(root) {
  const dir = path.join(root, 'src/shots');
  const map = {};
  for (const name of fs.readdirSync(dir)) {
    if (!/\.(tsx?|mts)$/.test(name)) continue;
    const text = fs.readFileSync(path.join(dir, name), 'utf8');
    for (const m of text.matchAll(/export const (S\d\d)[A-Za-z0-9_]*\s*[:=]/g)) map[m[1]] = `src/shots/${name}`;
  }
  return map;
}

// `clips` ({shot: sha256}, from clipShas) keys a segment on the rendered clips its own shots play, so a re-rendered
// Blender or engine clip re-renders one segment, not the film. Without clips the key is what it always was.
export function segmentKeys(root, segs, envDigest, clips = {}) {
  const modules = shotModules(root);
  const present = (files) => files.filter((f) => fs.existsSync(path.join(root, f)));
  const wiring = present(WIRING);
  const timeline = present(TIMELINE);
  const stops = present(STOPS);
  return segs.map((seg) => {
    const entries = seg.shots.map((id) => {
      if (!modules[id]) throw new Error(`no module exports shot ${id}`);
      return modules[id];
    });
    const files = [...new Set([...closure(root, [...entries, ...timeline, ...wiring], stops), ...stops])].sort();
    const parts = [`range ${seg.from}-${seg.to}`, `shots ${seg.shots.join(',')}`, `env ${envDigest}`];
    for (const f of files) parts.push(`${f} ${sha(fs.readFileSync(path.join(root, f)))}`);
    for (const id of seg.shots) if (clips[id]) parts.push(`clip ${id} ${clips[id]}`);
    return sha(parts.join('\n'));
  });
}

/** The clip each shot plays, as a public/ path: rows of src/data/media.json ({S07: {clip: "clips/S07.mp4"}}) that
 *  tools/render-shot.py writes. A clip no row owns stays in the environment digest (when in doubt, include). */
export function shotClips(root) {
  const file = path.join(root, 'src/data/media.json');
  if (!fs.existsSync(file)) return {};
  const rows = JSON.parse(fs.readFileSync(file, 'utf8'));
  const out = {};
  for (const [id, row] of Object.entries(rows)) if (row && typeof row.clip === 'string') out[id] = `public/${row.clip}`;
  return out;
}

/** {shot: sha256} of each owned clip in the input manifest; a clip the manifest lacks is keyed as "missing". */
export function clipShas(manifest, clips) {
  const byPath = new Map(manifest.entries.map((e) => [e.path, e.sha256]));
  return Object.fromEntries(Object.entries(clips).map(([id, p]) => [id, byPath.get(p) ?? 'missing']));
}

// What the picture depends on outside src/: fonts, public assets, the lockfile and the renderer's own config files.
// Mixed audio, ledgers and docs are left out so a sound or wording change does not re-render the picture.
const PICTURE = ['fonts/', 'public/', 'dependencies/', 'tools/remotion.config.ts', 'tools/package.json', 'tools/tsconfig.json', 'tools/render.sh'];

/** Environment digest from an input manifest: picture inputs outside src/ plus the runtime metadata. `owned` clip
 *  paths (shotClips) are left out here because they key their own segments. */
export function envDigest(manifest, extra = '', owned = []) {
  const skip = new Set(owned);
  const picture = manifest.entries.filter((e) => !skip.has(e.path) && PICTURE.some((p) => e.path === p || e.path.startsWith(p)));
  return sha(JSON.stringify({metadata: manifest.metadata, picture, extra}));
}
