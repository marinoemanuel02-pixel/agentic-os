// Cache keys: SHA-256 over a segment's frame range, its shot ids, every src/ file its shot modules import
// transitively (relative imports, .ts/.tsx/.mts/.js/.json), the timeline files every shot depends on, and an
// environment digest (fonts, public assets, config, runtime) taken from the input manifest. When in doubt, include.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const EXTS = ['', '.ts', '.tsx', '.mts', '.js', '.mjs', '.json', '/index.ts', '/index.tsx'];
const ALWAYS = ['src/Main.tsx', 'src/Root.tsx', 'src/index.ts', 'src/data/timeline.ts', 'src/data/plan.ts', 'src/shots/registry.ts'];
const IMPORT = /(?:import|export)\s+(?:[^'"]*?\sfrom\s+)?["'](\.{1,2}\/[^"']+)["']/g;
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
export function closure(root, entries) {
  const seen = new Set();
  const stack = entries.map((e) => path.resolve(root, e));
  while (stack.length) {
    const file = stack.pop();
    if (seen.has(file)) continue;
    seen.add(file);
    if (file.endsWith('.json')) continue;
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

export function segmentKeys(root, segs, envDigest) {
  const modules = shotModules(root);
  const always = ALWAYS.filter((f) => fs.existsSync(path.join(root, f)));
  return segs.map((seg) => {
    const entries = seg.shots.map((id) => {
      if (!modules[id]) throw new Error(`no module exports shot ${id}`);
      return modules[id];
    });
    const files = closure(root, [...entries, ...always]);
    const parts = [`range ${seg.from}-${seg.to}`, `shots ${seg.shots.join(',')}`, `env ${envDigest}`];
    for (const f of files) parts.push(`${f} ${sha(fs.readFileSync(path.join(root, f)))}`);
    return sha(parts.join('\n'));
  });
}

// What the picture depends on outside src/: fonts, public assets, the lockfile and the renderer's own config files.
// Mixed audio, ledgers and docs are left out so a sound or wording change does not re-render the picture.
const PICTURE = ['fonts/', 'public/', 'dependencies/', 'tools/remotion.config.ts', 'tools/package.json', 'tools/tsconfig.json', 'tools/render.sh'];

/** Environment digest from an input manifest: picture inputs outside src/ plus the runtime metadata. */
export function envDigest(manifest, extra = '') {
  const picture = manifest.entries.filter((e) => PICTURE.some((p) => e.path === p || e.path.startsWith(p)));
  return sha(JSON.stringify({metadata: manifest.metadata, picture, extra}));
}
