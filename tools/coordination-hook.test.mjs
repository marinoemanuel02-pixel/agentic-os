import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const hook = resolve(import.meta.dirname, 'coordination-hook.mjs');
const event = (overrides = {}) => ({ hook_event_name: 'SubagentStart', session_id: 'session-1',
  agent_id: 'worker-1', agent_type: 'Explore', ...overrides });
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'aos-native-signals-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const env = { ...process.env, AOS_COORD: root, AOS_RUN_ID: 'managed-run' };
  return {
    root, env,
    run(input, extraEnv = {}) {
      return spawnSync(process.execPath, [hook], { input: typeof input === 'string' ? input : JSON.stringify(input),
        env: { ...env, ...extraEnv }, encoding: 'utf8', timeout: 5000, windowsHide: true });
    },
    async signals(id = 'managed-run') {
      return (await readFile(join(root, 'native-signals', `${id}.jsonl`), 'utf8'))
        .trim().split('\n').map(line => JSON.parse(line));
    },
  };
}

test('actual start and stop hook roundtrip appends minimal distinct signals without stdout', async t => {
  const f = await fixture(t);
  const before = Date.now();
  for (const phase of ['SubagentStart', 'SubagentStop']) {
    const result = f.run(event({ hook_event_name: phase, agent_transcript_path: join(f.root, 'never-opened.jsonl'),
      last_assistant_message: 'secret-last-answer', account: { token: 'secret-account' }, arbitrary: 'secret-extra' }));
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, '');
  }
  const signals = await f.signals();
  assert.equal(signals.length, 2);
  assert.deepEqual(signals.map(s => s.phase), ['start', 'stop']);
  for (const signal of signals) {
    assert.deepEqual(Object.keys(signal).sort(), ['id', 'run_id', 'session_id', 'agent_id', 'agent_type',
      'phase', 'observed_at', 'source', 'transcript_ref'].sort());
    assert.match(signal.id, /^[0-9a-f-]{36}$/);
    assert.equal(signal.run_id, 'managed-run');
    assert.equal(signal.session_id, 'session-1');
    assert.equal(signal.agent_id, 'worker-1');
    assert.equal(signal.agent_type, 'Explore');
    assert.equal(signal.source, 'claude-hook');
    assert.equal(signal.transcript_ref, join(f.root, 'never-opened.jsonl'));
    assert.ok(Date.parse(signal.observed_at) >= before);
  }
  assert.notEqual(signals[0].id, signals[1].id);
  assert.equal(JSON.stringify(signals).includes('secret-'), false);
});

test('identical hook inputs append distinct UUIDs for resumed handles', async t => {
  const f = await fixture(t);
  assert.equal(f.run(event()).status, 0);
  assert.equal(f.run(event()).status, 0);
  const signals = await f.signals();
  assert.equal(signals.length, 2);
  assert.notEqual(signals[0].id, signals[1].id);
});

test('missing run ID uses validated session filename and preserves unknown owner as null', async t => {
  const f = await fixture(t);
  assert.equal(f.run(event(), { AOS_RUN_ID: '' }).status, 0);
  const [signal] = await f.signals('session-1');
  assert.equal(signal.run_id, null);
  assert.equal(signal.transcript_ref, null);
});

test('unknown event is ignored without creating native-signals or requiring child fields', async t => {
  const f = await fixture(t);
  for (const name of ['PostToolUse', 'constructor', 'toString', '__proto__']) {
    const result = f.run({ hook_event_name: name });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, '');
  }
  assert.deepEqual(await readdir(f.root), []);
});

test('invalid JSON, oversized input and missing required metadata fail with bounded safe stderr', async t => {
  const f = await fixture(t);
  for (const input of ['{ secret-value', ' '.repeat(65537), event({ agent_id: null }),
    event({ session_id: '' }), event({ agent_type: null }), [], null]) {
    const result = f.run(input);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.ok(result.stderr.length < 200);
    assert.equal(result.stderr.includes('secret-value'), false);
  }
  assert.deepEqual(await readdir(f.root), []);
});

test('IDs reject traversal, separators, overlength values and Windows reserved device names', async t => {
  const f = await fixture(t);
  for (const bad of ['../outside', '..', 'a/b', 'a\\b', 'C:escape', 'CON', 'nul', 'COM1.txt', 'LPT9',
    'A'.repeat(161), 'name\nsecret-value', 'name name']) {
    for (const field of ['session_id', 'agent_id', 'run']) {
      const result = field === 'run' ? f.run(event(), { AOS_RUN_ID: bad }) : f.run(event({ [field]: bad }));
      assert.notEqual(result.status, 0, `${field} ${JSON.stringify(bad)}`);
      assert.equal(result.stdout, '');
      assert.ok(result.stderr.length < 200);
    }
  }
  assert.deepEqual(await readdir(f.root), []);
});

test('agent type is safely bounded and transcript references are strings without control characters', async t => {
  const f = await fixture(t);
  assert.equal(f.run(event({ agent_type: 'A'.repeat(1000) })).status, 0);
  assert.equal((await f.signals())[0].agent_type.length, 160);
  for (const metadata of [{ agent_type: 'type\nsecret' }, { agent_transcript_path: { token: 'secret' } },
    { agent_transcript_path: 'ref\u0000secret' }, { agent_transcript_path: 'ref\nsecret' }]) {
    const result = f.run(event(metadata));
    assert.notEqual(result.status, 0);
    assert.equal(result.stderr.includes('secret'), false);
  }
  assert.equal((await f.signals()).length, 1);
});

test('filesystem failure returns nonzero without revealing the path or raw input', async t => {
  const f = await fixture(t);
  const file = join(f.root, 'private-path');
  await writeFile(file, 'not a directory');
  const result = f.run(event({ last_assistant_message: 'secret-value' }), { AOS_COORD: file });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
  assert.ok(result.stderr.length < 200);
  assert.equal(result.stderr.includes(file), false);
  assert.equal(result.stderr.includes('secret-value'), false);
});
