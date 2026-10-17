import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough, Writable } from 'node:stream';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const adapter = await import('./codex-app-server.mjs').catch(() => ({}));

function fakeServer(onRequest = () => {}, account = { type: 'chatgpt' }) {
  const child = new EventEmitter();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.killed = false;
  child.requests = [];
  child.send = (message, split = false) => {
    const line = JSON.stringify(message) + '\n';
    if (split) {
      const bytes = Buffer.from(line);
      const at = bytes.indexOf(Buffer.from('é')) + 1;
      child.stdout.write(bytes.subarray(0, at > 0 ? at : 5));
      child.stdout.write(bytes.subarray(at > 0 ? at : 5));
    } else child.stdout.write(line);
  };
  child.notify = (method, params) => child.send({ method, params });
  child.reply = (request, result) => child.send({ id: request.id, result });
  child.stdin = new Writable({ write(chunk, encoding, next) {
    const request = JSON.parse(String(chunk));
    child.requests.push(request);
    queueMicrotask(() => {
      if (onRequest(request, child) === true) return;
      switch (request.method) {
        case 'initialize': child.reply(request, {}); break;
        case 'account/read': child.reply(request, { account }); break;
        case 'account/rateLimits/read': child.reply(request, {
          rateLimits: { primary: { usedPercent: 23, windowDurationMins: 300, resetsAt: 1234 } },
          accountId: 'private-account', ordinaryUsageAllowed: true,
          rateLimitResetCredits: { private: 'never-emit' },
        }); break;
        case 'thread/start': child.reply(request, { thread: { id: 'main-thread' } }); break;
        case 'turn/start': child.reply(request, { turn: { id: 'main-turn', status: 'inProgress', items: [] } }); break;
        case 'turn/steer': child.reply(request, { turnId: 'main-turn' }); break;
        case 'turn/interrupt': child.reply(request, {}); break;
      }
    });
    next();
  } });
  child.kill = () => { child.killed = true; child.stdout.end(); child.emit('close', null, 'SIGTERM'); return true; };
  return child;
}

const item = (text = '{"status":"ok"}', phase = 'final_answer') => ({
  id: 'answer', type: 'agentMessage', phase, text,
});
function complete(child, items = [item()], status = 'completed', threadId = 'main-thread', turnId = 'main-turn') {
  for (const entry of items) child.notify('item/completed', { threadId, turnId, item: entry });
  child.notify('turn/completed', { threadId, turn: { id: turnId, status, items } });
}
async function setup(t, handler, account) {
  assert.equal(typeof adapter.runAdapter, 'function', 'runAdapter must exist');
  const dir = await mkdtemp(join(tmpdir(), 'aos-app-server-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const events = [];
  const child = fakeServer(handler, account);
  const options = { cwd: dir, model: 'account-model', effort: 'low', sandbox: 'read-only',
    schema: { type: 'object' }, output: join(dir, 'result.json'), runDir: dir, prompt: 'Return JSON.' };
  const deps = { spawnProcess: () => child, emit: event => events.push(event), pollMs: 5,
    requestTimeoutMs: 200, maxRunMs: 1500, signalSource: new EventEmitter() };
  return { child, options, deps, events, dir, run: () => adapter.runAdapter(options, deps) };
}

test('handshake and subscription auth precede thread/model requests; sandbox and schema are explicit', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'turn/start') setImmediate(() => complete(child));
  });
  await f.run();
  assert.deepEqual(f.child.requests.map(r => r.method),
    ['initialize', 'initialized', 'account/read', 'account/rateLimits/read', 'thread/start', 'turn/start']);
  const thread = f.child.requests.find(r => r.method === 'thread/start').params;
  assert.equal(thread.sandbox, 'read-only');
  assert.equal(thread.approvalPolicy, 'never');
  assert.equal(thread.modelProvider, 'openai');
  const turn = f.child.requests.find(r => r.method === 'turn/start').params;
  assert.deepEqual(turn.outputSchema, f.options.schema);
  assert.equal(turn.effort, 'low');
  assert.equal(turn.threadId, 'main-thread');
  assert.deepEqual(JSON.parse(await readFile(f.options.output, 'utf8')), { status: 'ok' });
  assert.equal(f.child.killed, true);
  assert.equal(JSON.stringify(f.events).includes('private-account'), false);
  assert.equal(JSON.stringify(f.events).includes('never-emit'), false);
  assert.equal(f.events.find(e => e.type === 'account.rate_limits').rate_limits.primary.used_percent, 23);
});

for (const auth of [{ type: 'apiKey' }, { type: 'amazonBedrock' }, { type: 'unknown' }, null]) {
  test(`refuses ${auth?.type ?? 'missing'} auth before model work and suppresses personal data`, async t => {
    const f = await setup(t, undefined, auth);
    await assert.rejects(f.run(), { code: 'AUTH_REFUSED' });
    assert.equal(f.child.requests.some(r => r.method === 'thread/start'), false);
    assert.equal(f.child.killed, true);
  });
}

test('split UTF-8 lines and duplicate items preserve command stdout once and use exact main turn', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method !== 'turn/start') return;
    setImmediate(() => {
      complete(child, [item('{"wrong":"child"}')], 'completed', 'child-thread', 'child-turn');
      complete(child, [item('{"wrong":"old"}')], 'completed', 'main-thread', 'old-turn');
      const command = { id: 'cmd', type: 'commandExecution', command: 'helper', status: 'completed', exitCode: 0,
        aggregatedOutput: 'AOS_COORD_REQUEST {"text":"café"}\n' };
      child.send({ method: 'item/completed', params: { threadId: 'main-thread', turnId: 'main-turn', item: command } }, true);
      child.notify('item/completed', { threadId: 'main-thread', turnId: 'main-turn', item: command });
      child.notify('thread/tokenUsage/updated', { threadId: 'main-thread', turnId: 'main-turn',
        tokenUsage: { last: {}, total: { inputTokens: 91, cachedInputTokens: 20, outputTokens: 7 } } });
      complete(child);
    });
  });
  await f.run();
  const commands = f.events.filter(e => e.item?.type === 'command_execution');
  assert.equal(commands.length, 1);
  assert.equal(commands[0].item.aggregated_output, 'AOS_COORD_REQUEST {"text":"café"}\n');
  assert.equal(f.events.filter(e => e.item?.type === 'agent_message').length, 1);
  assert.deepEqual(f.events.find(e => e.type === 'turn.completed').usage,
    { input_tokens: 91, cached_input_tokens: 20, output_tokens: 7 });
});

test('events immediately following turn/start response in the same chunk are not lost', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method !== 'turn/start') return;
    const frames = [{ id: r.id, result: { turn: { id: 'main-turn', items: [], status: 'inProgress' } } },
      { method: 'turn/completed', params: { threadId: 'main-thread', turn: {
        id: 'main-turn', status: 'completed', items: [item()] } } }];
    child.stdout.write(frames.map(x => JSON.stringify(x)).join('\n') + '\n');
    return true;
  });
  await f.run();
  assert.equal(f.events.filter(e => e.type === 'turn.completed').length, 1);
});

test('notifications arriving before the start response are correlated only after its exact turn ID', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method !== 'turn/start') return;
    complete(child, [item('{"wrong":true}')], 'completed', 'main-thread', 'unrelated-turn');
    complete(child);
    child.reply(r, { turn: { id: 'main-turn', status: 'inProgress', items: [] } });
    return true;
  });
  await f.run();
  assert.deepEqual(JSON.parse(await readFile(f.options.output, 'utf8')), { status: 'ok' });
  assert.equal(f.events.filter(e => e.item?.type === 'agent_message').length, 1);
});

test('steering accepts the current active turn once and acknowledges the actual server response', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'turn/steer') setImmediate(() => complete(child));
  });
  await writeFile(join(f.dir, 'steering.json'), JSON.stringify({ id: 'steer-1', text: 'Narrow the task', expected_turn_id: 'main-turn' }));
  await f.run();
  const steering = f.child.requests.filter(r => r.method === 'turn/steer');
  assert.equal(steering.length, 1);
  assert.equal(steering[0].params.expectedTurnId, 'main-turn');
  assert.deepEqual(JSON.parse(await readFile(join(f.dir, 'steering-ack.json'), 'utf8')),
    { id: 'steer-1', status: 'accepted', turn_id: 'main-turn' });
});

test('stale steering is refused without sending turn/steer or waking another turn', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'turn/start') setTimeout(() => complete(child), 35);
  });
  await writeFile(join(f.dir, 'steering.json'), JSON.stringify({ id: 'stale', text: 'No', expected_turn_id: 'old-turn' }));
  await f.run();
  assert.equal(f.child.requests.some(r => r.method === 'turn/steer'), false);
  assert.deepEqual(JSON.parse(await readFile(join(f.dir, 'steering-ack.json'), 'utf8')),
    { id: 'stale', status: 'rejected', turn_id: 'main-turn' });
});

test('cancel sends interrupt but waits for terminal event and never emits success', async t => {
  let interrupted = false;
  const f = await setup(t, (r, child) => {
    if (r.method === 'turn/interrupt') {
      interrupted = true;
      setTimeout(() => complete(child, [], 'interrupted'), 25);
    }
  });
  await writeFile(join(f.dir, 'cancel.json'), '{"requested":true}');
  await assert.rejects(f.run(), { code: 'TURN_INTERRUPTED' });
  assert.equal(interrupted, true);
  assert.equal(f.events.some(e => e.type === 'turn.completed'), false);
  await assert.rejects(readFile(f.options.output), { code: 'ENOENT' });
});

test('signal cancellation interrupts an active turn and removes handlers on cleanup', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'turn/start') setImmediate(() => f.deps.signalSource.emit('SIGTERM'));
    if (r.method === 'turn/interrupt') setImmediate(() => complete(child, [], 'interrupted'));
  });
  await assert.rejects(f.run(), { code: 'TURN_INTERRUPTED' });
  assert.equal(f.child.killed, true);
  assert.equal(f.deps.signalSource.listenerCount('SIGTERM'), 0);
});

for (const status of ['failed', 'interrupted']) {
  test(`${status} turn with a partial JSON answer cannot produce success`, async t => {
    const f = await setup(t, (r, child) => {
      if (r.method === 'turn/start') setImmediate(() => complete(child, [item()], status));
    });
    await assert.rejects(f.run(), { code: `TURN_${status.toUpperCase()}` });
    assert.equal(f.events.some(e => e.type === 'turn.completed'), false);
    await assert.rejects(readFile(f.options.output), { code: 'ENOENT' });
  });
}

test('invalid final JSON, commentary-only and partial-only JSON are failures', async t => {
  for (const answer of [item('partial'), item('{"status":"ok"}', 'commentary'), item('{"status":"ok"}', 'partial_answer')]) {
    const f = await setup(t, (r, child) => {
      if (r.method === 'turn/start') setImmediate(() => complete(child, [answer]));
    });
    await assert.rejects(f.run(), { code: 'INVALID_RESULT' });
    assert.equal(f.events.some(e => e.type === 'turn.completed'), false);
  }
});

test('included usage unavailable refuses model work and never consumes or resets credits', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'account/rateLimits/read') {
      child.reply(r, { rateLimits: {}, ordinaryUsageAllowed: false });
      return true;
    }
  });
  await assert.rejects(f.run(), { code: 'INCLUDED_USAGE_UNAVAILABLE' });
  assert.equal(f.child.requests.some(r => r.method === 'thread/start'), false);
  assert.equal(f.child.requests.some(r => /consume|reset|login/.test(r.method)), false);
});

test('quota read unavailable stays unknown and cannot manufacture usage token counts', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'account/rateLimits/read') {
      child.send({ id: r.id, error: { code: -32601, message: 'unsupported' } });
      return true;
    }
    if (r.method === 'turn/start') setImmediate(() => complete(child));
  });
  await f.run();
  assert.equal(f.events.find(e => e.type === 'account.rate_limits').rate_limits, null);
  assert.deepEqual(f.events.find(e => e.type === 'turn.completed').usage,
    { input_tokens: null, cached_input_tokens: null, output_tokens: null });
});

test('an unanswered RPC and a silent active turn have bounded deadlines and cleanup', async t => {
  for (const method of ['account/read', 'none']) {
    const f = await setup(t, r => r.method === method);
    f.deps.requestTimeoutMs = 25;
    f.deps.maxRunMs = 70;
    await assert.rejects(f.run(), { code: method === 'none' ? 'RUN_TIMEOUT' : 'RPC_TIMEOUT' });
    assert.equal(f.child.killed, true);
    assert.equal(f.events.some(e => e.type === 'turn.completed'), false);
  }
});

test('CLI rejects malformed arguments before reading stdin or spawning any server', async () => {
  await assert.rejects(adapter.main(['--sandbox', 'danger-full-access']), { code: 'INVALID_ARGUMENTS' });
  await assert.rejects(adapter.main(['--unknown', 'value']), { code: 'INVALID_ARGUMENTS' });
});

test('premature EOF rejects pending work and cleans up child without exposing stderr', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'account/read') {
      child.stderr.write('personal@example.test token=do-not-print');
      child.stdout.end();
      return true;
    }
  });
  await assert.rejects(f.run(), { code: 'EARLY_EOF' });
  assert.equal(f.child.killed, true);
  assert.equal(JSON.stringify(f.events).includes('do-not-print'), false);
});

test('EOF after a complete JSON item is still a failure without the exact terminal turn', async t => {
  const f = await setup(t, (r, child) => {
    if (r.method === 'turn/start') setImmediate(() => {
      child.notify('item/completed', { threadId: 'main-thread', turnId: 'main-turn', item: item() });
      child.stdout.end();
    });
  });
  await assert.rejects(f.run(), { code: 'EARLY_EOF' });
  assert.equal(f.child.killed, true);
  await assert.rejects(readFile(f.options.output), { code: 'ENOENT' });
});

test('malformed protocol JSON and RPC errors fail closed with safe error codes', async t => {
  for (const malformed of [true, false]) {
    const f = await setup(t, (r, child) => {
      if (r.method === 'account/read') {
        if (malformed) child.stdout.write('{broken}\n');
        else child.send({ id: r.id, error: { code: -1, message: 'private@example.test' } });
        return true;
      }
    });
    await assert.rejects(f.run(), { code: malformed ? 'PROTOCOL_JSON' : 'RPC_ERROR' });
    assert.equal(f.child.killed, true);
  }
});

test('options.timeoutMs governs the run deadline when dependencies.maxRunMs is omitted', async t => {
  const f = await setup(t, () => {});
  delete f.deps.maxRunMs;
  f.options.timeoutMs = 70;
  // Safety valve so an adapter that ignores timeoutMs fails fast instead of waiting on its default hour.
  const valve = setTimeout(() => f.child.stdout.end(), 1500);
  t.after(() => clearTimeout(valve));
  const started = Date.now();
  await assert.rejects(f.run(), { code: 'RUN_TIMEOUT' });
  clearTimeout(valve);
  assert.ok(Date.now() - started < 1200, 'deadline must come from options.timeoutMs');
  assert.equal(f.child.killed, true);
  assert.equal(f.events.some(e => e.type === 'turn.completed'), false);
});
