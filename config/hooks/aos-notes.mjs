// PostToolUse hook for both vendors: unread `aos note`s from the other vendor go into the model's context. On
// 2026-10-04 Codex posted notes for 40 minutes (its reset, review findings, unmerged guards) that Claude never read:
// the channel existed, nothing put it in front of the reader. Node, not the PowerShell module: this runs after every
// shell or edit call (0.15 s against 1.8 s). Fails open: any error prints nothing and exits 0.
//   node aos-notes.mjs <claude|codex>     hook JSON on stdin (session_id)
// Per session it keeps a byte offset into the ledger, so each call parses only lines appended since the last one,
// and a queue of notes not yet shown: at most five per call, oldest first, none marked seen unseen (Codex review).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const FIRST_LOOK_HOURS = 6; // a session's first call shows notes this recent
const FIRST_LOOK_BYTES = 512 * 1024; // ... found in this much of the ledger's tail
const PER_CALL = 5;
const MAX_PENDING = 200;
const MAX_CHARS = 600;

function readFrom(file, start, size) {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    return buf;
  } finally { fs.closeSync(fd); }
}

function main() {
  const agent = process.argv[2];
  if (!agent || process.env.AOS_DELEGATE_ID) return; // a delegate's wrapper reads notes, not the delegate
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  // Claude marks subagent calls with agent_id; they share the parent's session and must not consume its notes.
  // Codex subagents carry no such marker: there the first caller of the session gets the notes.
  if (input.agent_id) return;
  const session = String(input.session_id || '').replace(/[^A-Za-z0-9._-]/g, '_');
  if (!session) return;
  const coord = process.env.AOS_COORD || path.join(os.homedir(), '.aos', 'coord');
  const ledger = path.join(coord, 'ledger.jsonl');
  if (!fs.existsSync(ledger)) return;
  const stateFile = path.join(coord, 'seen', `${agent}-${session}.json`);
  let state = null;
  try { state = JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch { state = null; }
  const size = fs.statSync(ledger).size;
  const firstLook = !state || !(state.offset <= size);
  const start = firstLook ? Math.max(0, size - FIRST_LOOK_BYTES) : state.offset;
  const pending = firstLook ? [] : (state.pending || []);
  const buf = readFrom(ledger, start, size);
  const end = buf.lastIndexOf(0x0a) + 1; // complete lines only; a half-written line waits for the next call
  let lines = buf.subarray(0, end).toString('utf8').split('\n');
  if (firstLook && start > 0) lines = lines.slice(1); // started mid-line
  const since = Date.now() - FIRST_LOOK_HOURS * 3600 * 1000;
  for (const line of lines) {
    if (!line.includes('"note"')) continue;
    let e;
    try { e = JSON.parse(line); } catch { continue; }
    if (e.type !== 'note' || !e.agent || e.agent === agent) continue;
    if (firstLook && !(Date.parse(e.ts) > since)) continue;
    if (pending.length < MAX_PENDING) pending.push({ts: e.ts, agent: e.agent, checkout: e.checkout || '', text: String(e.text || '')});
  }
  const shown = pending.slice(0, PER_CALL);
  const rest = pending.slice(PER_CALL);
  fs.mkdirSync(path.dirname(stateFile), {recursive: true});
  fs.writeFileSync(stateFile, JSON.stringify({offset: start + end, pending: rest}));
  if (!shown.length) return;
  const from = [...new Set(pending.map((n) => n.agent))].join(', ');
  const total = pending.length;
  const head = `${total} unread aos note${total > 1 ? 's' : ''} from ${from}${rest.length ? `, showing ${shown.length}` : ''} (read before acting; answer with aos note --as ${agent}):`;
  const text = [
    head,
    ...shown.map((n) => `- ${n.ts} ${n.agent}${n.checkout ? ' @ ' + n.checkout : ''}: ${n.text.length > MAX_CHARS ? n.text.slice(0, MAX_CHARS) + ' [...]' : n.text}`),
    ...(rest.length ? [`(${rest.length} more after your next tool call)`] : []),
  ].join('\n');
  process.stdout.write(JSON.stringify({hookSpecificOutput: {hookEventName: 'PostToolUse', additionalContext: text}}));
}

try { main(); } catch { /* fail open */ }
