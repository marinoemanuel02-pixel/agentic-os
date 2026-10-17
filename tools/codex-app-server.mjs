// One bounded stdio app-server session. No daemon, listener, dependency or API-key route.
import { spawn } from 'node:child_process';
import { readFile, writeFile, rename, unlink, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { StringDecoder } from 'node:string_decoder';
import { randomUUID } from 'node:crypto';

const MAX_FRAME = 16 * 1024 * 1024;
const MAX_PROMPT = 1024 * 1024;
const MAX_CONTROL = 64 * 1024;
const textInput = text => [{ type: 'text', text }];
const error = (code, message = code) => Object.assign(new Error(message), { code });

async function atomicJson(path, value) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, JSON.stringify(value) + '\n', { encoding: 'utf8', mode: 0o600, flag: 'wx' });
    await rename(temporary, path);
  } finally {
    await unlink(temporary).catch(() => {});
  }
}

// RPC response callbacks run before the next frame is read. This is important when
// turn/start's response and the first item arrive together in one stdout chunk.
class Protocol {
  constructor(child, notify, fail, timeout) {
    this.child = child;
    this.notify = notify;
    this.fail = fail;
    this.timeout = timeout;
    this.pending = new Map();
    this.nextId = 1;
    this.buffer = '';
    this.decoder = new StringDecoder('utf8');
    this.closed = false;
    this.onData = chunk => this.feed(this.decoder.write(chunk));
    this.onEnd = () => this.abort(error('EARLY_EOF'));
    this.onError = () => this.abort(error('SERVER_IO'));
    child.stdout.on('data', this.onData);
    child.stdout.on('end', this.onEnd);
    child.stdout.on('error', this.onError);
    child.stdin.on('error', this.onError);
    child.on('error', this.onError);
    child.on('close', this.onEnd);
  }

  send(message) {
    if (this.closed) throw error('SERVER_CLOSED');
    this.child.stdin.write(JSON.stringify(message) + '\n');
  }

  request(method, params, accept = value => value) {
    if (this.closed) return Promise.reject(error('SERVER_CLOSED'));
    const id = this.nextId++;
    return new Promise((resolveRequest, reject) => {
      const timer = setTimeout(() => this.abort(error('RPC_TIMEOUT')), this.timeout);
      this.pending.set(id, { resolve: resolveRequest, reject, timer, accept });
      try { this.send({ id, method, params }); } catch { this.abort(error('SERVER_IO')); }
    });
  }

  feed(chunk) {
    if (this.closed) return;
    this.buffer += chunk;
    while (!this.closed) {
      const newline = this.buffer.indexOf('\n');
      if (newline < 0) break;
      const line = this.buffer.slice(0, newline);
      this.buffer = this.buffer.slice(newline + 1);
      if (Buffer.byteLength(line) > MAX_FRAME) return this.abort(error('PROTOCOL_LIMIT'));
      if (!line.trim()) continue;
      let frame;
      try { frame = JSON.parse(line); } catch { return this.abort(error('PROTOCOL_JSON')); }
      if (!frame || typeof frame !== 'object' || Array.isArray(frame)) return this.abort(error('PROTOCOL_JSON'));
      try {
        if ('id' in frame && !frame.method) {
          const pending = this.pending.get(frame.id);
          if (!pending) continue;
          this.pending.delete(frame.id);
          clearTimeout(pending.timer);
          // Server errors may contain account data, prompts, paths or credentials.
          if (frame.error) pending.reject(error('RPC_ERROR'));
          else if (!('result' in frame)) pending.reject(error('PROTOCOL_JSON'));
          else {
            try { pending.resolve(pending.accept(frame.result)); } catch (failure) { pending.reject(failure); }
          }
        } else if (typeof frame.method === 'string') {
          if ('id' in frame) {
            // This client cannot grant approvals, supply secrets or answer prompts.
            this.send({ id: frame.id, error: { code: -32601, message: 'Unsupported client request' } });
            this.abort(error('CLIENT_REQUEST_REFUSED'));
          } else this.notify(frame.method, frame.params ?? {});
        } else this.abort(error('PROTOCOL_JSON'));
      } catch (failure) { this.abort(failure); }
    }
    if (Buffer.byteLength(this.buffer) > MAX_FRAME) this.abort(error('PROTOCOL_LIMIT'));
  }

  abort(failure) {
    if (this.closed) return;
    this.closed = true;
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(failure);
    }
    this.pending.clear();
    this.fail(failure);
  }

  dispose() {
    this.abort(error('SERVER_CLOSED'));
    this.child.stdout.off('data', this.onData);
    this.child.stdout.off('end', this.onEnd);
    this.child.stdout.off('error', this.onError);
    // Keep pipe error handlers during shutdown to avoid an unhandled EPIPE.
    this.child.off('error', this.onError);
    this.child.off('close', this.onEnd);
  }
}

function normalizeLimits(result) {
  const window = value => value && Number.isFinite(value.usedPercent) ? {
    used_percent: value.usedPercent,
    window_duration_mins: Number.isFinite(value.windowDurationMins) ? value.windowDurationMins : null,
    resets_at: Number.isFinite(value.resetsAt) ? value.resetsAt : null,
  } : null;
  const bucket = value => ({ primary: window(value?.primary), secondary: window(value?.secondary) });
  const byId = result.rateLimitsByLimitId;
  return {
    type: 'account.rate_limits',
    rate_limits: bucket(result.rateLimits),
    // IDs are quota categories, never account identifiers. Drop arbitrary backend fields.
    rate_limits_by_limit_id: byId && typeof byId === 'object'
      ? Object.fromEntries(Object.entries(byId).map(([id, value]) => [id, bucket(value)])) : null,
    ordinary_usage_allowed: typeof result.ordinaryUsageAllowed === 'boolean' ? result.ordinaryUsageAllowed : null,
  };
}

async function stopChild(child, graceMs) {
  if (child.exitCode != null || child.signalCode != null) return;
  let timer;
  let onClose;
  const closed = new Promise(resolveClose => {
    onClose = () => resolveClose(true);
    child.once('close', onClose);
    timer = setTimeout(() => resolveClose(false), graceMs);
  });
  child.stdin.end();
  const exited = await closed;
  clearTimeout(timer);
  child.off('close', onClose);
  if (exited) return;
  // The outer AOS supervisor also owns a tree kill. Retain local cleanup when
  // this adapter is run directly or receives a catchable termination signal.
  if (process.platform === 'win32' && Number.isInteger(child.pid)) {
    await new Promise(done => {
      const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      const timeout = setTimeout(() => { killer.kill(); done(); }, 3000);
      killer.once('error', () => { clearTimeout(timeout); done(); });
      killer.once('close', () => { clearTimeout(timeout); done(); });
    });
  }
  child.kill();
}

async function readControl(path) {
  try {
    if ((await stat(path)).size > MAX_CONTROL) throw error('CONTROL_LIMIT');
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (failure) {
    // A producer replacing/writing the file may briefly leave incomplete JSON.
    if (failure.code === 'ENOENT' || failure instanceof SyntaxError) return null;
    throw error('CONTROL_IO');
  }
}

export async function runAdapter(options, dependencies = {}) {
  const { cwd, model, effort, sandbox, schema, output, runDir, prompt } = options;
  if (!cwd || !model || !output || !runDir || !schema || typeof schema !== 'object' || Array.isArray(schema)
      || typeof prompt !== 'string' || !prompt.trim() || Buffer.byteLength(prompt) > MAX_PROMPT
      || !['read-only', 'workspace-write'].includes(sandbox)) throw error('INVALID_OPTIONS');
  const emit = dependencies.emit ?? (event => process.stdout.write(JSON.stringify(event) + '\n'));
  const signals = dependencies.signalSource ?? process;
  const child = (dependencies.spawnProcess ?? spawn)('codex', ['app-server', '--stdio',
    '-c', 'forced_login_method="chatgpt"', '-c', 'model_provider="openai"'], {
    cwd, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true,
  });
  let threadId = null;
  let turnId = null;
  let active = false;
  let settled = false;
  let cancellation = false;
  let interruptSent = false;
  let polling = false;
  let controlTask = Promise.resolve();
  let controlFailure = null;
  let usage = { input_tokens: null, cached_input_tokens: null, output_tokens: null };
  let answer = null;
  let stderrBytes = 0;
  const seenItems = new Set();
  const seenSteering = new Set();
  const earlyNotifications = [];
  let earlyBytes = 0;
  let resolveTerminal;
  let rejectTerminal;
  const terminal = new Promise((yes, no) => { resolveTerminal = yes; rejectTerminal = no; });
  terminal.catch(() => {});
  const fail = failure => {
    if (settled) return;
    settled = true;
    active = false;
    rejectTerminal(failure);
  };
  const acceptItem = entry => {
    if (!entry || typeof entry.id !== 'string' || seenItems.has(entry.id)) return;
    seenItems.add(entry.id);
    if (entry.type === 'agentMessage' && typeof entry.text === 'string') {
      if (entry.phase == null || entry.phase === 'final_answer') answer = entry.text;
      emit({ type: 'item.completed', item: { id: entry.id, type: 'agent_message', text: entry.text } });
    } else if (entry.type === 'commandExecution' && typeof entry.aggregatedOutput === 'string'
        && ['completed', 'failed', 'declined'].includes(entry.status)) {
      emit({ type: 'item.completed', item: { id: entry.id, type: 'command_execution',
        command: entry.command, aggregated_output: entry.aggregatedOutput,
        exit_code: entry.exitCode ?? null, status: entry.status } });
    }
  };
  const notify = (method, params) => {
    if (settled || !threadId || params.threadId !== threadId) return;
    if (!turnId) {
      if (!['item/completed', 'thread/tokenUsage/updated', 'turn/completed'].includes(method)) return;
      earlyBytes += Buffer.byteLength(JSON.stringify(params));
      if (earlyBytes > MAX_FRAME || earlyNotifications.length >= 10000) throw error('PROTOCOL_LIMIT');
      earlyNotifications.push([method, params]);
      return;
    }
    if (method === 'item/completed' && params.turnId === turnId) acceptItem(params.item);
    if (method === 'thread/tokenUsage/updated' && params.turnId === turnId) {
      // This is a new thread with exactly one model turn, so total includes all its steps.
      const total = params.tokenUsage?.total;
      if (total) usage = {
        input_tokens: Number.isFinite(total.inputTokens) ? total.inputTokens : null,
        cached_input_tokens: Number.isFinite(total.cachedInputTokens) ? total.cachedInputTokens : null,
        output_tokens: Number.isFinite(total.outputTokens) ? total.outputTokens : null,
      };
    }
    if (method === 'turn/completed' && turnId && params.turn?.id === turnId) {
      active = false;
      if (params.turn.status !== 'completed') {
        fail(error(params.turn.status === 'interrupted' ? 'TURN_INTERRUPTED' : 'TURN_FAILED'));
        return;
      }
      if (cancellation) { fail(error('TURN_INTERRUPTED')); return; }
      for (const entry of params.turn.items ?? []) acceptItem(entry);
      let result;
      try {
        result = JSON.parse(answer);
        if (!result || typeof result !== 'object' || Array.isArray(result)) throw error('INVALID_RESULT');
      } catch { fail(error('INVALID_RESULT')); return; }
      settled = true;
      resolveTerminal(result);
    }
  };
  const protocol = new Protocol(child, notify, fail, dependencies.requestTimeoutMs ?? 30000);
  const onStderr = chunk => { stderrBytes = Math.min(MAX_FRAME, stderrBytes + chunk.length); };
  child.stderr.on('data', onStderr); // Drain but never retain or print personal payloads.
  const interrupt = async () => {
    cancellation = true;
    if (!active || !turnId || interruptSent || settled) return;
    interruptSent = true;
    await protocol.request('turn/interrupt', { threadId, turnId });
    // The interrupt response is only a receipt. turn/completed establishes termination.
  };
  const onSignal = () => {
    if (!active) { cancellation = true; protocol.abort(error('CANCELLED')); }
    else interrupt().catch(fail);
  };
  signals.on('SIGINT', onSignal);
  signals.on('SIGTERM', onSignal);
  const poll = async () => {
    if (polling || settled) return;
    polling = true;
    try {
      const cancel = await readControl(join(runDir, 'cancel.json'));
      if (cancel?.requested === true) await interrupt();
      if (!active || settled || cancellation) return;
      const steering = await readControl(join(runDir, 'steering.json'));
      if (!steering || typeof steering.id !== 'string' || seenSteering.has(steering.id)) return;
      seenSteering.add(steering.id);
      let status = 'rejected';
      const expected = steering.expected_turn_id;
      if (active && !settled && !cancellation && expected === turnId
          && typeof steering.text === 'string' && steering.text.trim()) {
        try {
          const response = await protocol.request('turn/steer', {
            threadId, expectedTurnId: turnId, input: textInput(steering.text),
          });
          if (response?.turnId === turnId) status = 'accepted';
        } catch (failure) {
          if (failure.code !== 'RPC_ERROR') throw failure;
        }
      }
      await atomicJson(join(runDir, 'steering-ack.json'), { id: steering.id, status, turn_id: turnId });
    } catch (failure) { controlFailure = failure; fail(failure); }
    finally { polling = false; }
  };
  const triggerPoll = () => {
    if (!polling) controlTask = poll();
    return controlTask;
  };
  let pollTimer;
  const deadline = setTimeout(() => protocol.abort(error('RUN_TIMEOUT')), dependencies.maxRunMs ?? 60 * 60 * 1000);
  try {
    await protocol.request('initialize', { clientInfo: { name: 'aos_bounded_adapter', version: '1' } });
    protocol.send({ method: 'initialized' });
    const account = await protocol.request('account/read', { refreshToken: false });
    if (account?.account?.type !== 'chatgpt') throw error('AUTH_REFUSED');
    // Rate-limit reads do not reset limits or consume credits. Older servers may not support them.
    try {
      const limits = await protocol.request('account/rateLimits/read', {});
      emit(normalizeLimits(limits));
      if (limits.ordinaryUsageAllowed === false) throw error('INCLUDED_USAGE_UNAVAILABLE');
    } catch (failure) {
      if (failure.code !== 'RPC_ERROR') throw failure;
      emit({ type: 'account.rate_limits', rate_limits: null, rate_limits_by_limit_id: null, ordinary_usage_allowed: null });
    }
    await protocol.request('thread/start', { cwd, model, modelProvider: 'openai', sandbox, approvalPolicy: 'never' }, value => {
      if (typeof value?.thread?.id !== 'string' || !value.thread.id) throw error('PROTOCOL_THREAD');
      threadId = value.thread.id;
      emit({ type: 'thread.started', thread_id: threadId });
      return value;
    });
    await protocol.request('turn/start', { threadId, input: textInput(prompt), outputSchema: schema,
      ...(effort ? { effort } : {}) }, value => {
      if (typeof value?.turn?.id !== 'string' || !value.turn.id) throw error('PROTOCOL_TURN');
      turnId = value.turn.id;
      active = true;
      emit({ type: 'turn.started', thread_id: threadId, turn_id: turnId });
      // A fast server may notify before replying to turn/start. Only the reply
      // establishes the expected ID; replay through the same exact-ID filter.
      for (const [method, params] of earlyNotifications) notify(method, params);
      earlyNotifications.length = 0;
      return value;
    });
    pollTimer = setInterval(() => { void triggerPoll(); }, dependencies.pollMs ?? 100);
    await triggerPoll();
    const result = await terminal;
    await controlTask;
    if (controlFailure) throw controlFailure;
    await atomicJson(output, result);
    emit({ type: 'turn.completed', usage });
    return { result, threadId, turnId, usage };
  } catch (failure) {
    const code = /^[A-Z_]+$/.test(failure?.code ?? '') ? failure.code : 'ADAPTER_FAILED';
    emit({ type: 'turn.failed', error: { message: code } });
    throw error(code);
  } finally {
    settled = true;
    clearTimeout(deadline);
    clearInterval(pollTimer);
    signals.off('SIGINT', onSignal);
    signals.off('SIGTERM', onSignal);
    protocol.dispose();
    await controlTask;
    await stopChild(child, dependencies.cleanupGraceMs ?? (dependencies.spawnProcess ? 1 : 1000));
    child.stderr.off('data', onStderr);
    if (stderrBytes) emit({ type: 'adapter.diagnostic', message: 'App-server stderr suppressed', bytes: stderrBytes });
  }
}

export async function main(args = process.argv.slice(2), input = process.stdin) {
  const values = {};
  const allowed = new Set(['cwd', 'model', 'effort', 'sandbox', 'schema', 'output', 'run-dir']);
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index].replace(/^--/, '');
    if (!args[index].startsWith('--') || !allowed.has(key) || values[key] !== undefined
        || !args[index + 1] || args[index + 1].startsWith('--')) throw error('INVALID_ARGUMENTS');
    values[key] = args[index + 1];
  }
  for (const key of ['cwd', 'model', 'sandbox', 'schema', 'output', 'run-dir']) {
    if (!values[key]) throw error('INVALID_ARGUMENTS');
  }
  const schema = JSON.parse(await readFile(resolve(values.schema), 'utf8'));
  let prompt = '';
  input.setEncoding('utf8');
  for await (const chunk of input) {
    prompt += chunk;
    if (Buffer.byteLength(prompt) > MAX_PROMPT) throw error('PROMPT_LIMIT');
  }
  return runAdapter({ cwd: resolve(values.cwd), model: values.model, effort: values.effort,
    sandbox: values.sandbox, schema, output: resolve(values.output), runDir: resolve(values['run-dir']), prompt });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(failure => {
    const code = /^[A-Z_]+$/.test(failure?.code ?? '') ? failure.code : 'ADAPTER_FAILED';
    process.stderr.write(`Codex adapter failed: ${code}\n`);
    process.exitCode = 1;
  });
}
