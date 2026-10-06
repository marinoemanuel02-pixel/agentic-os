// The asset gate (R35): every imported file has a rights row, a known license or a bounded fair-use/capture use,
// credits, evidence and an accepted acquisition. Each refusal mutates one field of the valid 60 s fixture
// (fixtures/assets/build.mjs). The gate checks policy, not law: it never says "fair use".
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {cpSync, mkdtempSync, readFileSync, writeFileSync, rmSync, mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const VALID = join(HERE, 'fixtures', 'assets', 'valid');
const GATE = join(HERE, 'assets.mjs');
const {checkAssets} = await import(new URL('./assets.mjs', import.meta.url));

function copy() { const d = join(mkdtempSync(join(tmpdir(), 'assets-gate-')), 'film one'); cpSync(VALID, d, {recursive: true}); return d; }
const read = (d, f) => JSON.parse(readFileSync(join(d, f), 'utf8'));
const write = (d, f, v) => { mkdirSync(dirname(join(d, f)), {recursive: true}); writeFileSync(join(d, f), typeof v === 'string' ? v : JSON.stringify(v, null, 2)); };
function mutate(fn) { const d = copy(); const led = read(d, 'assets.json'); fn(led, d); write(d, 'assets.json', led); return d; }
const row = (led, id) => led.rows.find(r => r.id === id);
function refused(d, pattern) {
  const r = checkAssets(d);
  assert.equal(r.ok, false, 'expected a refusal');
  assert.ok(r.errors.some(e => pattern.test(e)), `no error matched ${pattern}: ${r.errors.join(' | ')}`);
}

test('the valid fixture passes at exactly the 10 % fair-use cap', () => {
  const r = checkAssets(copy());
  assert.deepEqual(r.errors, []);
  assert.equal(r.ok, true);
  assert.equal(r.report.fairUseSeconds, 6);
  assert.equal(r.report.filmSeconds, 60);
  assert.deepEqual(r.report.perBasis, {license: 1, cc0: 1, 'public-domain': 1, own: 1, 'fair-use': 1, capture: 1});
});

test('an empty ledger passes', () => {
  const d = copy();
  write(d, 'assets.json', {schema: 1, rows: []});
  rmSync(join(d, 'public', 'assets'), {recursive: true});
  write(d, 'src/shots/S03 Clip.tsx', 'export const S03 = () => null;\n');
  assert.deepEqual(checkAssets(d).errors, []);
});

test('CLI prints the policy line, never "fair use"', () => {
  const out = spawnSync(process.execPath, [GATE, copy()], {encoding: 'utf8'});
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /^asset policy checks passed$/m);
  assert.doesNotMatch(out.stdout, /fair use/i);
});

test('CLI takes the media root public folder and timeline from options', () => {
  const d = copy();
  const media = mkdtempSync(join(tmpdir(), 'assets-media-'));
  cpSync(join(d, 'public'), join(media, 'app', 'public'), {recursive: true});
  cpSync(join(d, 'timeline.json'), join(media, 'qa', 'timeline.json'));
  rmSync(join(d, 'public'), {recursive: true});
  rmSync(join(d, 'timeline.json'));
  const out = spawnSync(process.execPath, [GATE, d, '--public', join(media, 'app', 'public'), '--timeline', join(media, 'qa', 'timeline.json')], {encoding: 'utf8'});
  assert.equal(out.status, 0, out.stdout + out.stderr);
});

test('a public/assets file without a row is refused', () => { const d = copy(); write(d, 'public/assets/stray.mp4', 'x'); refused(d, /^public\/assets\/stray\.mp4: no ledger row/); });
test('a changed derivative is refused', () => { const d = copy(); write(d, 'public/assets/a01.mp4', 'changed'); refused(d, /^a01: derivative hash mismatch/); });
test('a missing derivative is refused', () => { const d = copy(); rmSync(join(d, 'public', 'assets', 'a01.mp4')); refused(d, /^a01: derivative assets\/a01\.mp4 missing/); });
test('a license outside the allowlist is refused', () => refused(mutate(l => { row(l, 'a01').license = 'cc-by-nc-4.0'; }), /^a01: license cc-by-nc-4\.0 not allowed/));
test('CC-BY-SA is refused', () => refused(mutate(l => { row(l, 'a01').license = 'cc-by-sa-4.0'; }), /^a01: license cc-by-sa-4\.0 not allowed/));
test('a CC-BY row without credit is refused', () => refused(mutate(l => { const r = row(l, 'a01'); r.license = 'cc-by-4.0'; r.credit = ''; }), /^a01: credit required/));
test('a credit missing from description.md is refused', () => { const d = copy(); write(d, 'description.md', '# Film\n\n## Credits\n\n- Powered by Poly Haven\n'); refused(d, /^a01: credit missing from description\.md/); });
test('a Poly Haven row without the Poly Haven line is refused', () => { const d = copy(); write(d, 'description.md', '# Film\n\n## Credits\n\n- Video by Ana on Pexels\n- Poly Haven: Robot arm\n'); refused(d, /^a02: description\.md needs "Powered by Poly Haven"/); });
test('a fair-use use over 8 s is refused', () => refused(mutate(l => { row(l, 'a05').uses[0].mediaTo = 8.1; row(l, 'a05').media.duration = 9; }), /^a05: use u1 is 8\.1 s/));
test('fair-use + capture over 10 % is refused', () => refused(mutate(l => { row(l, 'a06').uses[0].mediaTo = 1.1; row(l, 'a06').media.duration = 2; }), /fair-use and capture total 6\.1 s/));
test('kept sound without audio subject is refused', () => refused(mutate(l => { row(l, 'a05').uses[0].audio = 'kept'; }), /^a05: use u1 keeps sound/));
test('audio subject over 5 s is refused', () => refused(mutate(l => { const r = row(l, 'a05'); const u = r.uses[0]; u.audio = 'subject'; u.mediaTo = 5.5; r.media.duration = 9; r.uses[1].mediaFrom = 5.5; r.uses[1].mediaTo = 6.0; }), /^a05: use u1 audio subject 5\.5 s over 5 s/));
test('no overlapping narration is refused', () => { const d = copy(); const w = read(d, 'src/data/words.json'); w.L02 = [['late', 7.0, 9.0]]; write(d, 'src/data/words.json', w); refused(d, /^a05: use u1 has narration over 0 % of its 3 s/); });
test('narration over less than half a use is refused', () => { const d = copy(); const w = read(d, 'src/data/words.json'); w.L02 = [['brief', 0.0, 1.4], ['late', 3.0, 6.0]]; write(d, 'src/data/words.json', w); refused(d, /^a05: use u1 has narration over 46 % of its 3 s/); });
test('an empty rationale is refused', () => refused(mutate(l => { row(l, 'a05').uses[0].rationale = ' '; }), /^a05: use u1 needs a rationale/));
test('missing rights evidence is refused', () => { const d = copy(); rmSync(join(d, 'research', 'rights', 'a05.json')); refused(d, /^a05: rights evidence missing/); });
test('an acquisition the brief refuses is refused', () => refused(mutate(l => { const r = row(l, 'a05'); r.acquisition = 'download-tool'; r.platform = 'youtube'; }), /^a05: acquisition download-tool from youtube not accepted by sourcing\.json/));
test('an unknown acquisition is refused', () => refused(mutate(l => { row(l, 'a05').acquisition = 'scraped'; }), /^a05: unknown acquisition scraped/));
test('a NASA person without clearance is refused', () => refused(mutate(l => { row(l, 'a03').subjects = ['person']; }), /^a03: needs clearance for person/));
test('a use past the measured media is refused', () => refused(mutate(l => { row(l, 'a01').media.duration = 7.5; }), /^a01: use u1 ends at 8 s past the measured 7\.5 s/));
test('a use on an unknown shot is refused', () => refused(mutate(l => { row(l, 'a01').uses[0].shot = 'S99'; }), /^a01: use u1 on unknown shot S99/));
test('a missing generated source tag is refused', () => { const d = copy(); const c = read(d, 'claims.json'); c.screen = c.screen.filter(s => s.asset !== 'a05'); write(d, 'claims.json', c); refused(d, /^a05: no generated source tag in claims\.json/); });
test('a dynamic staticFile path is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'const n = "a05"; export const X = () => staticFile(`assets/${n}.mp4`);\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('a literal staticFile path outside the registry is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => staticFile("assets/a05.mp4");\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('staticFile(ASSETS[...].src) outside src/lib/media is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => staticFile(ASSETS["a05"].src);\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('a literal useGLTF path is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => useGLTF("/assets/a02.glb");\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('a remote media URL in src is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => <OffthreadVideo src="https://example.com/a.mp4" />;\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: remote media URL/); });
test('a .gltf with external resources is refused', () => { const d = copy(); write(d, 'public/assets/a02.gltf', JSON.stringify({buffers: [{uri: 'scene.bin'}]})); const l = read(d, 'assets.json'); row(l, 'a02').derivatives.push({path: 'assets/a02.gltf', sha256: 'x', ffmpeg: null}); write(d, 'assets.json', l); refused(d, /^a02: assets\/a02\.gltf references external resources/); });
test('a Lottie file with external images is refused', () => { const d = copy(); write(d, 'public/assets/a04.json', JSON.stringify({v: '5.7.0', assets: [{id: 'img', u: 'images/', p: 'img.png', e: 0}]})); const l = read(d, 'assets.json'); row(l, 'a04').derivatives.push({path: 'assets/a04.json', sha256: 'x', ffmpeg: null}); write(d, 'assets.json', l); refused(d, /^a04: assets\/a04\.json references external resources/); });
test('an unknown basis is refused', () => refused(mutate(l => { row(l, 'a04').basis = 'probably-fine'; }), /^a04: unknown basis probably-fine/));
test('a duplicate id is refused', () => refused(mutate(l => { l.rows.push({...row(l, 'a04')}); }), /^a04: duplicate id/));
test('a fair-use row when the film disallows fair use is refused', () => { const d = copy(); const s = read(d, 'sourcing.json'); s.fairUse = false; write(d, 'sourcing.json', s); refused(d, /^a05: fair use disabled in sourcing\.json/); });
test('report file is written', () => {
  const d = copy(); const rep = join(d, 'qa', 'assets.md');
  const out = spawnSync(process.execPath, [GATE, d, '--report', rep], {encoding: 'utf8'});
  assert.equal(out.status, 0, out.stderr);
  const text = readFileSync(rep, 'utf8');
  assert.match(text, /fair-use and capture: 6\.0 s of 60\.0 s \(10\.0 %\)/);
  assert.match(text, /Content ID/);
  assert.match(text, /supporting evidence/);
  assert.match(text, /Human checks/);
});

test('timeline-json.mts exports the plan in frames for the gate', () => {
  const out = spawnSync(process.execPath, ['--no-warnings', join(HERE, '..', 'timeline-json.mts')], {encoding: 'utf8'});
  assert.equal(out.status, 0, out.stderr);
  const t = JSON.parse(out.stdout);
  assert.equal(t.fps, 30);
  assert.deepEqual(t.shots.map(s => s.id), ['S01', 'S02']);
  assert.equal(t.shots[1].from, t.shots[0].frames);
  assert.deepEqual(t.lines.map(l => [l.id, l.from]), [['L1', 2 * 18]]);
  assert.ok(t.frames >= t.shots[1].from + t.shots[1].frames);
});

test('build and QA run the gate before rendering or decoding, and the manifest seals the ledger', () => {
  const build = readFileSync(join(HERE, '..', 'build.sh'), 'utf8');
  const qa = readFileSync(join(HERE, '..', 'qa.sh'), 'utf8');
  assert.ok(build.indexOf('checks/assets.mjs') > 0 && build.indexOf('checks/assets.mjs') < build.indexOf('tools/audio.mts'));
  assert.ok(qa.indexOf('checks/assets.mjs') > 0 && qa.indexOf('checks/assets.mjs') < qa.indexOf('input-manifest.mjs" verify'));
  const manifest = readFileSync(join(HERE, 'input-manifest.mjs'), 'utf8');
  for (const name of ['assets.json', 'sourcing.json', 'research/rights']) assert.match(manifest, new RegExp(name.replace('/', '\/')));
});
