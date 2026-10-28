// Search adapters behind one interface: fixtures shaped like each API's response, injected getJson (no network).
// Task 12 replaces each fixture with a trimmed real response from one real call (rule R08).
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {ADAPTERS, searchAll} from '../adapters/index.mjs';

const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8'));
const calls = [];
const io = (name, key = 'k') => ({key, getJson: async (url, headers) => { calls.push({url, headers}); return fixture(name); }});
const ALLOWED = new Set(['cc0-1.0', 'pd', 'cc-by-3.0', 'cc-by-4.0', 'pexels', 'pixabay']);

test('nine search sources behind one interface (generic URLs are fetched, not searched)', () => {
  assert.deepEqual(ADAPTERS.map(a => a.id).sort(), ['ambientcg', 'archive', 'freesound', 'nasa', 'openverse', 'pexels', 'pixabay', 'polyhaven', 'wikimedia'].sort());
  for (const a of ADAPTERS) {
    assert.equal(typeof a.search, 'function');
    assert.ok(a.kinds.length > 0);
  }
});

test('every adapter returns only allowlisted licenses and full Candidates', async () => {
  for (const a of ADAPTERS) for (const kind of a.kinds) {
    const got = await a.search('robot arm', {kind, limit: 5}, io(`${a.id}-${kind}`));
    assert.ok(got.length > 0, `${a.id} ${kind} returned nothing from its fixture`);
    for (const c of got) {
      assert.ok(ALLOWED.has(c.license), `${a.id}: ${c.license}`);
      assert.equal(c.source, a.id);
      assert.equal(c.kind, kind);
      for (const k of ['id', 'page', 'download', 'author', 'credit']) assert.ok(c[k], `${a.id} ${kind}: missing ${k}`);
      assert.match(c.download, /^https:\/\//, `${a.id}: download must be https`);
    }
  }
});

test('openverse drops share-alike and non-commercial results present in its fixture', async () => {
  const a = ADAPTERS.find(x => x.id === 'openverse');
  const got = await a.search('x', {kind: 'photo', limit: 20}, io('openverse-photo'));
  assert.deepEqual(got.map(c => c.license).sort(), ['cc-by-4.0', 'cc0-1.0']);
  assert.match(calls.at(-1).url, /license_type=commercial%2Cmodification|license_type=commercial,modification/);
});

test('wikimedia keeps CC BY, CC0 and public domain only, with plain-text authors', async () => {
  const a = ADAPTERS.find(x => x.id === 'wikimedia');
  const photos = await a.search('x', {kind: 'photo', limit: 20}, io('wikimedia-photo'));
  assert.deepEqual(photos.map(c => c.license).sort(), ['cc-by-4.0', 'pd']);
  assert.ok(photos.every(c => !/[<>]/.test(c.author)));
  const clips = await a.search('x', {kind: 'clip', limit: 20}, io('wikimedia-clip'));
  assert.deepEqual(clips.map(c => c.license), ['cc0-1.0']);
});

test('archive drops items without a license URL (Prelinger is not blanket public domain)', async () => {
  const a = ADAPTERS.find(x => x.id === 'archive');
  const got = await a.search('x', {kind: 'clip', limit: 20}, io('archive-clip'));
  assert.deepEqual(got.map(c => c.id), ['robots_1957', 'factory_film']);
  assert.ok(got.every(c => c.licenseUrl));
});

test('freesound keeps CC0 and CC BY, drops NC, and asks for previews only', async () => {
  const a = ADAPTERS.find(x => x.id === 'freesound');
  const got = await a.search('x', {kind: 'sfx', limit: 20}, io('freesound-sfx'));
  assert.deepEqual(got.map(c => c.license), ['cc0-1.0', 'cc-by-4.0']);
  assert.ok(got.every(c => /preview/.test(c.download)));
});

test('pexels picks the best file at or under 1080p', async () => {
  const a = ADAPTERS.find(x => x.id === 'pexels');
  const [first] = await a.search('x', {kind: 'clip', limit: 5}, io('pexels-clip'));
  assert.equal(first.download, 'https://videos.pexels.com/101-hd.mp4');
  assert.equal(first.height, 1080);
  assert.equal(first.credit, 'Video by Ana on Pexels');
});

test('polyhaven filters its catalogue by the query words and credits Poly Haven', async () => {
  const a = ADAPTERS.find(x => x.id === 'polyhaven');
  const got = await a.search('robot', {kind: 'model', limit: 5}, io('polyhaven-model'));
  assert.deepEqual(got.map(c => c.id), ['robot_arm']);
  assert.match(got[0].credit, /Poly Haven/);
  assert.match(calls.at(-1).headers['user-agent'], /agentic-os-video-assets/);
});

test('nasa leaves people and logos for the director to clear', async () => {
  const a = ADAPTERS.find(x => x.id === 'nasa');
  const [c] = await a.search('x', {kind: 'clip', limit: 5}, io('nasa-clip'));
  assert.equal(c.license, 'pd');
  assert.match(c.credit, /^NASA\/KSC/);
  assert.match(c.note, /clearance/);
});

test('searchAll skips keyed adapters without a key and says why', async () => {
  const saved = process.env.AOS_KEY_PEXELS;
  delete process.env.AOS_KEY_PEXELS;
  try {
    const r = await searchAll('x', {kind: 'clip', limit: 1, sources: ['pexels']}, {getJson: async () => { throw new Error('must not call'); }});
    assert.deepEqual(r.skipped, [{id: 'pexels', reason: 'no key (aos secret set pexels)'}]);
    assert.deepEqual(r.candidates, []);
  } finally { if (saved !== undefined) process.env.AOS_KEY_PEXELS = saved; }
});

test('searchAll reports a failing source and keeps the others', async () => {
  const r = await searchAll('robot', {kind: 'clip', limit: 2, sources: ['nasa', 'archive']}, {getJson: async url => {
    if (url.includes('nasa')) throw new Error('HTTP 503');
    return fixture('archive-clip');
  }});
  assert.equal(r.candidates.length, 2);
  assert.deepEqual(r.skipped, [{id: 'nasa', reason: 'HTTP 503'}]);
});

test('header-auth keys never appear in a URL', async () => {
  for (const id of ['pexels']) {
    const a = ADAPTERS.find(x => x.id === id);
    await a.search('x', {kind: 'clip', limit: 1}, io(`${id}-clip`, 'SECRET-KEY'));
    assert.doesNotMatch(calls.at(-1).url, /SECRET-KEY/);
    assert.equal(calls.at(-1).headers.authorization, 'SECRET-KEY');
  }
});
