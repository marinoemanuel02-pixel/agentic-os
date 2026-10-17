// Claude lifecycle observations only; the host owns actor admission and correlation.
import { appendFile, lstat, mkdir, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';

const MAX_INPUT = 64 * 1024;
const fail = code => Object.assign(new Error(code), { code });
const controls = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/;

function validId(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$/.test(value)
      || /^(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)/i.test(value)) throw fail('INVALID_ID');
  return value;
}

function metadata(value, limit) {
  if (typeof value !== 'string' || !value.trim() || controls.test(value)) throw fail('INVALID_METADATA');
  return Array.from(value.trim()).slice(0, limit).join('');
}

export async function main(input = process.stdin, env = process.env) {
  const chunks = [];
  let bytes = 0;
  try {
    for await (const chunk of input) {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'utf8');
      bytes += buffer.length;
      if (bytes > MAX_INPUT) throw fail('INPUT_LIMIT');
      chunks.push(buffer);
    }
  } catch (failure) {
    throw fail(failure.code === 'INPUT_LIMIT' ? 'INPUT_LIMIT' : 'INPUT_IO');
  }
  let event;
  try { event = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw fail('INVALID_INPUT'); }
  if (!event || typeof event !== 'object' || Array.isArray(event)
      || typeof event.hook_event_name !== 'string' || !event.hook_event_name) throw fail('INVALID_INPUT');
  if (!['SubagentStart', 'SubagentStop'].includes(event.hook_event_name)) return;
  const phase = event.hook_event_name === 'SubagentStart' ? 'start' : 'stop';

  const sessionId = validId(event.session_id);
  const agentId = validId(event.agent_id);
  const runId = env.AOS_RUN_ID ? validId(env.AOS_RUN_ID) : null;
  const signal = {
    id: randomUUID(),
    run_id: runId,
    session_id: sessionId,
    agent_id: agentId,
    agent_type: metadata(event.agent_type, 160),
    phase,
    observed_at: new Date().toISOString(),
    source: 'claude-hook',
    // A reference is metadata, never an instruction to read a transcript.
    transcript_ref: event.agent_transcript_path == null ? null : metadata(event.agent_transcript_path, 4096),
  };
  try {
    const root = resolve(env.AOS_COORD || join(homedir(), '.aos', 'coord'), 'native-signals');
    await mkdir(root, { recursive: true, mode: 0o700 });
    const resolvedRoot = await realpath(root);
    const target = resolve(resolvedRoot, `${runId || sessionId}.jsonl`);
    if (dirname(target) !== resolvedRoot) throw fail('SIGNAL_IO');
    try {
      if ((await lstat(target)).isSymbolicLink()) throw fail('SIGNAL_IO');
    } catch (failure) {
      if (failure.code !== 'ENOENT') throw failure;
    }
    await appendFile(target, JSON.stringify(signal) + '\n', {
      encoding: 'utf8', mode: 0o600,
      flag: constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY | (constants.O_NOFOLLOW || 0),
    });
  } catch { throw fail('SIGNAL_IO'); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(failure => {
    const code = ['INVALID_INPUT', 'INPUT_LIMIT', 'INPUT_IO', 'INVALID_ID', 'INVALID_METADATA', 'SIGNAL_IO']
      .includes(failure?.code) ? failure.code : 'HOOK_FAILED';
    process.stderr.write(`Coordination hook failed: ${code}\n`);
    process.exitCode = 1;
  });
}
