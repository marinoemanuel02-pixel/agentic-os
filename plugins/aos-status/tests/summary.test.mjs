import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summarize } from '../hooks/summary.mjs';

const now = Date.parse('2026-10-19T19:00:00Z');
test('shows active identities, not task text or private annotations', () => {
  const result = summarize({ now, actors: { actors: {
    a: { id: 'a', vendor: 'codex', state: 'running', text: 'private task details' },
    b: { id: 'b', vendor: 'claude', state: 'done' },
  } }, claims: [{ agent: 'codex', expires: '2026-10-19T20:00:00Z', note: 'private note' }] });
  assert.deepEqual(result.actors, [{ id: 'a', vendor: 'codex', state: 'running' }]);
  assert.equal(result.claims, 1);
  assert.doesNotMatch(JSON.stringify(result), /private/);
});
test('a future quota reset remains limited while old positive observations become stale', () => {
  const ledger = [
    { type: 'capacity', vendor: 'claude', remaining: 0, ts: '2026-10-18T01:00:00Z', resets: '2026-10-22T04:00:00Z' },
    { type: 'capacity', vendor: 'codex', remaining: 80, ts: '2026-10-18T01:00:00Z' },
  ];
  const result = summarize({ now, ledger });
  assert.equal(result.capacity[0].state, 'limited');
  assert.equal(result.capacity[1].state, 'stale');
  assert.equal(result.capacity[1].remaining, null);
});
test('unknown invalid future-dated observations never become measured zero or available capacity', () => {
  const result = summarize({ now, ledger: [
    { type: 'capacity', vendor: 'codex', remaining: 120, ts: '2026-10-19T18:59:00Z' },
    { type: 'capacity', vendor: 'claude', remaining: 80, ts: '2026-10-20T19:00:00Z' },
  ], usage: { context: { percent: NaN } } });
  assert.deepEqual(result.capacity.map(row => row.state), ['unknown', 'unknown']);
  assert.equal(result.context, null);
  assert.equal(result.claims, null);
});
test('reports only valid measured context and expired claim exclusion', () => {
  const result = summarize({ now, actors: { actors: {} }, claims: [{ expires: '2026-10-19T18:00:00Z' }],
    usage: { context: { percent: 23.4 }, cost: { dollars: 100 }, messages: ['private'] } });
  assert.equal(result.context, 23.4);
  assert.equal(result.claims, 0);
  assert.doesNotMatch(JSON.stringify(result), /dollars|private/);
});
