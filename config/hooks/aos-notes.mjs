// PostToolUse hook for both vendors: unread `aos note`s from the other vendor go into the model's context. On
// 2026-10-04 Codex posted notes for 40 minutes (its reset, review findings, unmerged guards) that Claude never read:
// the channel existed, nothing put it in front of the reader. Node, not the PowerShell module: this runs after every
// shell or edit call (0.15 s against 1.8 s). Fails open: any error prints nothing and exits 0.
//   node aos-notes.mjs <claude|codex>     hook JSON on stdin (session_id)
// Per session it keeps a byte offset into the ledger, so each call parses only lines appended since the last one,
// and a queue of notes not yet shown: at most five per call, oldest first, none dropped or marked seen unseen
// (Codex reviews 2 and 3). Claude marks subagent calls (agent_id) and they are skipped. Codex subagents share the
// parent's session with no marker, so in Codex each note is shown on two separate calls: a subagent that takes the
// first showing leaves the second for the parent. A mitigation, not a guarantee; `aos who` lists every note.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const FIRST_LOOK_HOURS = 6; // a session's first call shows notes this recent
const FIRST_LOOK_CHUNK = 512 * 1024; // the first look reads back in growing chunks until it passes that age
const PER_CALL = 5;
const MAX_PENDING = 200; // reading stops here and resumes from the same line on a later call
const MAX_CHARS = 600;
const SHOWINGS = {codex: 2};

function readRange(file, start, end) {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(end - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    return buf;
  } finally { fs.closeSync(fd); }
}

// Where a first look starts: far enough back that the oldest line read is older than the lookback, or the file start.
function firstLookStart(file, size, since) {
  let start = Math.max(0, size - FIRST_LOOK_CHUNK);
  while (start > 0) {
    const head = readRange(file, start, Math.min(size, start + 64 * 1024));
    const nl = head.indexOf(0x0a);
    const next = nl < 0 ? -1 : head.indexOf(0x0a, nl + 1);
    if (nl < 0 || next < 0) break;
    let ts = NaN;
    try { ts = Date.parse(JSON.parse(head.subarray(nl + 1, next).toString('utf8')).ts); } catch { /* keep going */ }
    if (ts <= since) return start + nl + 1;
    start = Math.max(0, start - (size - start)); // double the window
  }
  return 0;
}

function main() {
  const agent = process.argv[2];
  if (!agent || process.env.AOS_DELEGATE_ID) return; // a delegate's wrapper reads notes, not the delegate
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  if (input.agent_id) return; // a Claude subagent: leave the parent's notes alone
  const session = String(input.session_id || '').replace(/[^A-Za-z0-9._-]/g, '_');
  if (!session) return;
  const coord = process.env.AOS_COORD || path.join(os.homedir(), '.aos', 'coord');
  const ledger = path.join(coord, 'ledger.jsonl');
  if (!fs.existsSync(ledger)) return;
  const stateFile = path.join(coord, 'seen', `${agent}-${session}.json`);
  let state = null;
  try { state = JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch { state = null; }
  const size = fs.statSync(ledger).size;
  const since = Date.now() - FIRST_LOOK_HOURS * 3600 * 1000;
  const firstLook = !state || !(state.offset <= size);
  const start = firstLook ? firstLookStart(ledger, size, since) : state.offset;
  const pending = firstLook ? [] : (state.pending || []);
  const buf = readRange(ledger, start, size);
  let pos = 0;
  let offset = start;
  while (pending.length < MAX_PENDING) {
    const nl = buf.indexOf(0x0a, pos);
    if (nl < 0) break; // a half-written line waits for the next call
    const line = buf.subarray(pos, nl).toString('utf8');
    pos = nl + 1;
    offset = start + pos;
    if (!line.includes('"note"')) continue;
    let e;
    try { e = JSON.parse(line); } catch { continue; }
    if (e.type !== 'note' || !e.agent || e.agent === agent) continue;
    if (firstLook && !(Date.parse(e.ts) > since)) continue;
    pending.push({ts: e.ts, agent: e.agent, checkout: e.checkout || '', text: String(e.text || ''), shown: 0});
  }
  const shown = pending.slice(0, PER_CALL);
  for (const n of shown) n.shown = (n.shown || 0) + 1;
  const keep = pending.filter((n) => (n.shown || 0) < (SHOWINGS[agent] || 1));
  fs.mkdirSync(path.dirname(stateFile), {recursive: true});
  fs.writeFileSync(stateFile, JSON.stringify({offset, pending: keep}));
  if (!shown.length) return;
  const from = [...new Set(shown.map((n) => n.agent))].join(', ');
  const total = pending.length;
  const more = total - shown.length;
  const head = `${total} unread aos note${total > 1 ? 's' : ''} from ${from}${more ? `, showing ${shown.length}` : ''} (read before acting; answer with aos note --as ${agent}):`;
  const text = [
    head,
    ...shown.map((n) => `- ${n.ts} ${n.agent}${n.checkout ? ' @ ' + n.checkout : ''}: ${n.text.length > MAX_CHARS ? n.text.slice(0, MAX_CHARS) + ' [...]' : n.text}`),
    ...(more || offset < size ? [`(${more ? more + ' more' : 'more'} after your next tool call)`] : []),
  ].join('\n');
  process.stdout.write(JSON.stringify({hookSpecificOutput: {hookEventName: 'PostToolUse', additionalContext: text}}));
}

try { main(); } catch { /* fail open */ }
