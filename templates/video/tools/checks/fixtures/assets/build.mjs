// Writes the valid asset-gate fixture (fixtures/assets/valid): a 60 s film with one row per rights basis and fair use
// plus capture at exactly 10 %. Run `node tools/checks/fixtures/assets/build.mjs` after changing it; hashes are computed,
// never typed. The project layout matches a real film; `timeline.json` and `public/` stand in for the media root.
import {createHash} from 'node:crypto';
import {mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), 'valid');
const sha = text => createHash('sha256').update(text).digest('hex');
const put = (rel, value) => {
  const p = join(OUT, rel);
  mkdirSync(dirname(p), {recursive: true});
  writeFileSync(p, typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n');
};

rmSync(OUT, {recursive: true, force: true});

const FPS = 30;
put('timeline.json', {
  fps: FPS, frames: 1800,
  shots: ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'].map((id, i) => ({id, from: i * 300, frames: 300})),
  lines: [{id: 'L01', from: 0}, {id: 'L02', from: 600}, {id: 'L03', from: 1200}],
});
// Word times relative to each line's start, as tools/word-times.py writes them.
const run = (n, len) => Array.from({length: n}, (_, i) => [`w${i}`, i * len, (i + 1) * len]);
put('src/data/words.json', {L01: run(10, 1), L02: run(6, 1), L03: run(2, 1)});

const derivative = (id, ext, kind) => {
  const body = `${id} ${kind} derivative bytes\n`;
  put(`public/assets/${id}.${ext}`, body);
  return {path: `assets/${id}.${ext}`, sha256: sha(body), ffmpeg: ext === 'mp4' ? '-c:v libx264 -crf 18 -g 30 -an' : null};
};
const media = (id, duration) => ({sha256: sha(`${id} original`), cache: `objects/${sha(`${id} original`)}.bin`, start: 0, duration});
const use = (u, shot, shotFrom, mediaFrom, mediaTo, extra = {}) => ({use: u, shot, shotFrom, mediaFrom, mediaTo, audio: 'muted', ...extra});
const evidence = id => { put(`research/rights/${id}.json`, {url: `https://example.org/${id}`, retrieved: '2026-10-07T10:00:00+02:00', pageSha256: sha(id), excerpt: 'license text excerpt'}); return `research/rights/${id}.json`; };

const rows = [
  {id: 'a01', kind: 'clip', need: 'a robot arm sorting parts', searchStep: 3, url: 'https://www.pexels.com/video/1/', page: 'https://www.pexels.com/video/1/',
    author: 'Ana', retrieved: '2026-10-07T10:00:00+02:00', basis: 'license', license: 'pexels', licenseUrl: 'https://www.pexels.com/license/',
    acquisition: 'api', platform: 'pexels', rightsEvidence: evidence('a01'), source: {in: 0, out: 8}, media: media('a01', 8.0),
    derivatives: [derivative('a01', 'mp4', 'clip')], uses: [use('u1', 'S01', 0, 0, 8)], credit: 'Video by Ana on Pexels', clearance: null},
  {id: 'a02', kind: 'model', need: 'a recognisable industrial robot at real scale', searchStep: 3, url: 'https://polyhaven.com/a/robot_arm', page: 'https://polyhaven.com/a/robot_arm',
    author: 'Poly Haven', retrieved: '2026-10-07T10:00:00+02:00', basis: 'cc0', license: 'cc0-1.0', licenseUrl: 'https://polyhaven.com/license',
    acquisition: 'api', platform: 'polyhaven', rightsEvidence: evidence('a02'), source: null, media: media('a02', null),
    derivatives: [derivative('a02', 'glb', 'model')], uses: [use('u1', 'S02', 0, 0, 5)], credit: 'Poly Haven: Robot arm', clearance: null},
  {id: 'a03', kind: 'clip', need: 'a real launch, not an illustration', searchStep: 3, url: 'https://images-assets.nasa.gov/video/x/x~orig.mp4', page: 'https://images.nasa.gov/details/x',
    author: 'NASA/KSC', retrieved: '2026-10-07T10:00:00+02:00', basis: 'public-domain', license: 'pd', licenseUrl: 'https://www.nasa.gov/nasa-brand-center/images-and-media/',
    acquisition: 'api', platform: 'nasa', rightsEvidence: evidence('a03'), source: {in: 0, out: 4}, media: media('a03', 4.0), subjects: [],
    derivatives: [derivative('a03', 'mp4', 'clip')], uses: [use('u1', 'S04', 0, 0, 4)], credit: 'NASA/KSC', clearance: null},
  {id: 'a04', kind: 'clip', need: 'our own render of the lab', searchStep: 4, url: null, page: null,
    author: 'this channel', retrieved: '2026-10-07T10:00:00+02:00', basis: 'own', license: null, licenseUrl: null,
    acquisition: null, platform: null, rightsEvidence: null, source: null, media: media('a04', 3.0),
    derivatives: [derivative('a04', 'mp4', 'clip')], uses: [use('u1', 'S06', 0, 0, 3)], credit: '', clearance: null},
  {id: 'a05', kind: 'clip', need: 'the demo the lab showed on launch day', searchStep: 1, url: 'https://lab.example/demo.mp4', page: 'https://lab.example/launch',
    author: 'Example Lab', retrieved: '2026-10-07T10:00:00+02:00', basis: 'fair-use', license: null, licenseUrl: null,
    acquisition: 'direct-file', platform: 'lab-site', rightsEvidence: evidence('a05'), source: {in: 12, out: 18}, media: media('a05', 6.0),
    derivatives: [derivative('a05', 'mp4', 'clip')],
    uses: [use('u1', 'S03', 0, 0, 3, {rationale: 'we show the moment the agent edits its own test; the narration explains why it matters'}),
      use('u2', 'S03', 90, 3, 5, {rationale: 'the same demo a moment later: the test now passes, which the narration questions'})],
    credit: 'Source: Example Lab launch demo, 2026-09-09', clearance: null},
  {id: 'a06', kind: 'capture', need: 'the real product page, not a mock-up', searchStep: 1, url: 'https://product.example/', page: 'https://product.example/',
    author: 'Example Inc.', retrieved: '2026-10-07T10:00:00+02:00', basis: 'capture', license: null, licenseUrl: null,
    acquisition: 'platform-feature', platform: 'web', rightsEvidence: evidence('a06'), source: null, media: media('a06', 2.0),
    derivatives: [derivative('a06', 'mp4', 'capture')],
    uses: [use('u1', 'S05', 0, 0, 1, {rationale: 'the page as visitors see it on the day; the narration reads its claim and disputes it'})],
    credit: 'Source: product.example, captured 2026-10-07', clearance: null},
];
put('assets.json', {schema: 1, rows});
put('sourcing.json', {schema: 1, fairUse: true,
  acquisition: {youtube: ['api', 'platform-feature'], '*': ['api', 'direct-file', 'platform-feature', 'download-tool']},
  budget: {approvedMB: 2000, approvedAt: '2026-10-07T09:00:00+02:00', approvedBy: 'user'}});
put('claims.json', {sources: {}, lines: [], screen: rows.filter(r => r.basis === 'fair-use' || r.basis === 'capture')
  .map(r => ({texts: [r.credit], kind: 'label', asset: r.id, sources: [], reviewed: false, generated: true}))});
put('description.md', '# Fixture film\n\nWhat the film is about.\n\n## Credits\n\n- Video by Ana on Pexels\n- Poly Haven: Robot arm\n- NASA/KSC\n- Powered by Poly Haven\n');
put('src/data/assets.ts', '// generated by aos asset registry; do not edit\nexport const ASSETS = {\n' +
  rows.map(r => `  "${r.id}": { "src": "${r.derivatives[0].path}", "kind": "${r.kind}" }`).join(',\n') + '\n} as const;\n');
put('src/lib/media/Clip.tsx', 'import { OffthreadVideo, staticFile } from "remotion";\nimport { ASSETS } from "../../data/assets";\n' +
  'export const Clip = ({ asset }: { asset: keyof typeof ASSETS; use: string }) => <OffthreadVideo src={staticFile(ASSETS[asset].src)} muted />;\n');
put('src/shots/S03 Clip.tsx', 'import { Clip } from "../lib/media/Clip";\nexport const S03 = () => <Clip asset="a05" use="u1" />;\n');
console.log(`wrote ${OUT}`);
