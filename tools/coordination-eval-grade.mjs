// Fixed host grader. Keep this file outside each worker's writable fixture repo.
import assert from 'node:assert/strict';
import { readFile, realpath } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const [checker, directory, ...extra] = process.argv.slice(2);
let root = resolve(directory || '.');
async function file(name) {
  const path = await realpath(resolve(root, name));
  assert.ok(path.startsWith(root + sep), 'fixture path must stay inside its repo');
  return path;
}
async function text(name) { return readFile(await file(name), 'utf8'); }
async function module(name) { return import(pathToFileURL(await file(name)).href); }
const checks = {
  async mechanical() {
    assert.equal(await text('labels.txt'), 'status=ready\nowner=team\n');
  },
  async implementation() {
    const { slug } = await module('slug.mjs');
    assert.equal(typeof slug, 'function');
    for (const [input, expected] of [['Hello World', 'hello-world'], ['  Red + Blue!! ', 'red-blue'],
      ['', ''], [' !!! ', ''], ['Already---Slug', 'already-slug'], ['a_b 42', 'a-b-42']]) {
      assert.equal(slug(input), expected);
    }
  },
  async sequential() {
    const { formatAmount } = await module('amount.mjs');
    const { invoice } = await module('invoice.mjs');
    for (const [cents, amount] of [[1234, '12.34'], [0, '0.00'], [-50, '-0.50'], [7, '0.07']]) {
      assert.deepEqual(formatAmount(cents), { currency: 'EUR', amount });
      assert.equal(invoice(cents), `EUR ${amount}`);
    }
  },
  async diagnosis() {
    const { inclusiveSum } = await module('range.mjs');
    for (const [start, end, expected] of [[1, 3, 6], [4, 4, 4], [-2, 2, 0], [3, 2, 0], [0, 4, 10]]) {
      assert.equal(inclusiveSum(start, end), expected);
    }
  },
  async research() {
    assert.equal(await text('source-a.txt'), 'Source A: The Harbor library opens Monday through Friday.\n');
    assert.equal(await text('source-b.txt'), 'Source B: The Harbor library closes at 18:00 on weekdays.\n');
    assert.deepEqual(JSON.parse(await text('synthesis.json')), { claims: [
      { text: 'The Harbor library opens Monday through Friday.', sources: ['source-a.txt'] },
      { text: 'The Harbor library closes at 18:00 on weekdays.', sources: ['source-b.txt'] },
    ] });
  },
  async consequential() {
    assert.deepEqual(JSON.parse(await text('policy.json')), { default: 'deny', rules: [
      { role: 'reader', resource: 'report', actions: ['read'] },
      { role: 'editor', resource: 'report', actions: ['read', 'write'] },
    ] });
  },
};
try {
  root = await realpath(root);
  assert.equal(extra.length, 0);
  assert.ok(Object.hasOwn(checks, checker), 'known checker required');
  assert.ok(directory, 'fixture directory required');
  await checks[checker]();
  process.stdout.write(JSON.stringify({ checker, status: 'passed' }) + '\n');
} catch {
  process.stderr.write('Evaluation check failed.\n');
  process.exitCode = 1;
}
