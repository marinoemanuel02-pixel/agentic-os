// node --test tools/checks/type-size.test.mjs
// The type-size gate (rubric 4: >= 36 px at 1080p): huggingface-it v1 shipped quote-card source lines at 26-30 px,
// found only by a blind frame review.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {sizesIn, checkFilm} from './type-size.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const sizes = (src) => sizesIn(src).map((s) => [s.line, s.px]);

test('reads sizes from style objects, JSX attributes, SVG and CSS strings and the font shorthand', () => {
  const src = [
    `<div style={{ fontFamily: MONO, fontSize: 26, color: CYAN }}>{source}</div>`,
    `<text fontSize={116} fontWeight={700}>END</text>`,
    `<text font-size="30">x</text>`,
    `<div style={{ fontSize: "40px" }} />`,
    'const bar = { font: `500 20px ${SANS}` };',
    `const css = "p { font-size: 18px }";`,
  ].join('\n');
  assert.deepEqual(sizes(src), [[1, 26], [2, 116], [3, 30], [4, 40], [5, 20], [6, 18]]);
});

test('resolves a same-file numeric constant, arithmetic on it and both branches of a ternary', () => {
  const src = 'const SIZE = 84;\nexport const SMALL = 30;\n<text fontSize={SIZE} />\n<p style={{ fontSize: SIZE * 0.5 }} />\n<p style={{ fontSize: big ? 48 : SMALL }} />';
  assert.deepEqual(sizes(src), [[3, 84], [4, 42], [5, 48], [5, 30]]);
});

test('lists a size it cannot evaluate instead of passing or failing it', () => {
  const found = sizesIn('<p style={{ fontSize: props.size }} />\n<p style={{ fontSize: "2em" }} />');
  assert.deepEqual(found.map((s) => [s.line, s.px, s.expr]), [[1, null, 'props.size'], [2, null, '"2em"']]);
});

test('ignores comments, type annotations, canvas fonts and other font properties', () => {
  const src = [
    '// fontSize: 12 was too small',
    '/* font-size: 10px */',
    'type P = { font?: string; fontSize?: number };',
    `const tag = { font = '600 {px}px Bahnschrift' };`,
    'ctx.font = font.replace("{px}", String(px));',
    `<div style={{ fontFamily: SANS, fontWeight: 400, letterSpacing: "0.22em" }} />`,
    `const url = "https://example.org/a"; // fontSize: 8`,
  ].join('\n');
  assert.deepEqual(sizes(src), []);
});

const film = (files) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'type-size-'));
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), {recursive: true});
    fs.writeFileSync(path.join(root, rel), text);
  }
  return root;
};

test('a film fails on any size under the minimum in src/lib or src/shots, and nowhere else', () => {
  const root = film({
    'src/lib/QuoteCard.tsx': '<div style={{ fontSize: 66 }} />\n<div style={{ fontSize: 30 }} />',
    'src/shots/S01Open.tsx': '<text fontSize={24}>x</text>',
    'src/lib/media/Tag.tsx': 'const t = { font: `500 36px ${SANS}` };',
    'tools/notes.tsx': '<div style={{ fontSize: 10 }} />',
  });
  const r = checkFilm(root, 36);
  assert.deepEqual(r.small.map((s) => `${s.file}:${s.line} ${s.px}`).sort(), ['src/lib/QuoteCard.tsx:2 30', 'src/shots/S01Open.tsx:1 24']);
  assert.equal(r.checked, 3);
});

test('the command exits 1 on small type, 0 when every size is at least the minimum, and honours --min', () => {
  const cli = path.join(here, 'type-size.mjs');
  const bad = film({'src/lib/Counter.tsx': '<div style={{ fontSize: 26 }} />'});
  const p = spawnSync(process.execPath, [cli, '--root', bad], {encoding: 'utf8'});
  assert.equal(p.status, 1, p.stdout + p.stderr);
  assert.match(p.stdout + p.stderr, /src\/lib\/Counter\.tsx:1 26 px/);
  assert.equal(spawnSync(process.execPath, [cli, '--root', bad, '--min', '24'], {encoding: 'utf8'}).status, 0);
  const good = film({'src/lib/Counter.tsx': '<div style={{ fontSize: 36 }} />'});
  assert.equal(spawnSync(process.execPath, [cli, '--root', good], {encoding: 'utf8'}).status, 0);
});

test('the template scaffold itself passes (its own labels, source tags and capture bar are at least 36 px)', () => {
  const p = spawnSync(process.execPath, [path.join(here, 'type-size.mjs'), '--root', path.join(here, '..', '..')], {encoding: 'utf8'});
  assert.equal(p.status, 0, p.stdout + p.stderr);
});
