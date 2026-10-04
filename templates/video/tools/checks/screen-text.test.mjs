// node --test tools/checks/screen-text.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {extract, checkCoverage} from './screen-text.mjs';

const src = `
  <Headlines items={[{ text: "Alignment", start: 0, stop: 9 }]} />
  <SourceLine text="Illustration · METR, 2025" />
  const s = { verdict: "BRILLIANT", id: "S01", line: "N03" };
  type T = { text: string };
`;

test('finds headline, source line and printed labels; ignores shot and line ids and type annotations', () => {
  const r = extract(src);
  assert.deepEqual([...r.texts].sort(), ['Alignment', 'BRILLIANT', 'Illustration · METR, 2025']);
  assert.deepEqual(r.errors, []);
});

test('screen text held in a variable fails', () => {
  assert.match(extract('<SourceLine text={METR} />').errors[0], /non-literal screen text: text: METR/);
  assert.match(extract('{ text: name, start: 1 }').errors[0], /non-literal/);
  assert.match(extract('{ text: `Timed: ${t} s`, start: 1 }').errors[0], /computed screen text/);
});

test('a string on screen but missing from the ledger fails (the gap the review found)', () => {
  const errs = checkCoverage(new Set(['Calculation: never ran']), {screen: []});
  assert.match(errs[0], /on screen but not in claims.json/);
});

test('a ledger string no longer on screen fails, and entries need review and a kind', () => {
  const errs = checkCoverage(new Set(), {screen: [{texts: ['Old text'], reviewed: false}]});
  assert.equal(errs.length, 2);
});

test('full coverage passes', () => {
  assert.deepEqual(checkCoverage(new Set(['A']), {screen: [{texts: ['A'], reviewed: true, kind: 'label'}]}), []);
});

test('template JSX children and single-quoted text literals are covered', () => {
  const r = extract(`<Reveal>Everyday words</Reveal><Label>{'lower case'}</Label><Tag text='Label words' />`);
  assert.deepEqual([...r.texts].sort(), ['Everyday words', 'Label words', 'lower case']);
  assert.deepEqual(r.errors, []);
  assert.match(extract('<Reveal>{computed}</Reveal>').errors[0], /computed screen text/);
  assert.match(extract('<Tag text={"literal"} />').texts.values().next().value, /literal/);
});

test('idiomatic TSX code and numeric font weights are not screen words', () => {
  const r = extract(`export const S = () => (
    <Stage><Reveal>Real words</Reveal></Stage>
  ); const o = f > 10 ? 1 : 0; const ok = a < b && c > d;
  const style = {fontWeight: "700"};`);
  assert.deepEqual([...r.texts], ['Real words']);
  assert.deepEqual(r.errors, []);
});

test('mixed JSX children and operators in attributes remain covered', () => {
  for (const [source, expected] of [
    ['<div>Outer <span>inner</span> tail</div>', ['Outer', 'inner', 'tail']],
    ['<p>Up to <b>40%</b> faster</p>', ['Up to', '40%', 'faster']],
    ['<div style={{opacity: f > 10 ? 1 : 0}}>Hidden words</div>', ['Hidden words']],
    ['<Reveal at={() => 3}>Arrow child</Reveal>', ['Arrow child']],
  ]) {
    const r = extract(source);
    assert.deepEqual([...r.texts], expected);
    assert.deepEqual(r.errors, []);
  }
});

test('computed inline text fails while conditional geometry and literal fragments remain usable', () => {
  assert.match(extract('<p>Up to <b>{percent}</b> faster</p>').errors.join('\n'), /computed screen text/);
  const geometry = extract('<group>{items.map(x => <mesh><boxGeometry args={[1, 2, 3]} /></mesh>)}</group>');
  assert.deepEqual([...geometry.texts], []);
  assert.deepEqual(geometry.errors, []);
  const fragment = extract('<><Reveal>{"Words"}</Reveal>{/* comment */}<Label>More words</Label></>');
  assert.deepEqual([...fragment.texts], ['Words', 'More words']);
  assert.deepEqual(fragment.errors, []);
});

test('ternary and concatenated children are computed expressions rather than string literals', () => {
  for (const source of [
    "<Reveal>{done ? 'Ready' : 'Waiting'}</Reveal>",
    "<p>{n + '%'}</p>",
    '<Reveal>{"Up " + pct}</Reveal>',
  ]) assert.match(extract(source).errors.join('\n'), /computed screen text/);
});

test("a straight apostrophe in JSX text inside braces is text, not a string start (alignment-now S20)", () => {
  const r = extract(`<Scene>{show && <b>an agent's note</b>}<i>{"Next"}</i></Scene>\n<Card label={<span>it isn't</span>} />`);
  assert.deepEqual(r.errors, []);
  assert.deepEqual([...r.texts].sort(), ["Next", "an agent's note", "it isn't"]);
  assert.deepEqual([...extract(`{ text: 'It\\'s real', start: 1 }`).texts], ["It's real"]);
});
