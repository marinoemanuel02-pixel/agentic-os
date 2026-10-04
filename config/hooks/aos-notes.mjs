// PostToolUse hook for both vendors: unread `aos note`s from the other vendor go into the model's context, once per
// session. On 2026-10-04 Codex posted notes for 40 minutes (its reset, review findings, unmerged guards) that Claude
// never read: the channel existed, nothing put it in front of the reader. Node, not the PowerShell module: this runs
// after every shell or edit call (0.15 s against 1.8 s). Fails open: any error prints nothing and exits 0.
//   node aos-notes.mjs <claude|codex>     hook JSON on stdin (session_id)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const FIRST_LOOK_HOURS = 6; // a session's first call shows notes this recent
const MAX_NOTES = 5;
const MAX_CHARS = 600;

function main() {
  const agent = process.argv[2];
  if (!agent || process.env.AOS_DELEGATE_ID) return; // a delegate's wrapper reads notes, not the delegate
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  const session = String(input.session_id || '').replace(/[^A-Za-z0-9._-]/g, '_');
  if (!session) return;
  const coord = process.env.AOS_COORD || path.join(os.homedir(), '.aos', 'coord');
  const ledger = path.join(coord, 'ledger.jsonl');
  if (!fs.existsSync(ledger)) return;
  const seenFile = path.join(coord, 'seen', `${agent}-${session}.txt`);
  let since = Date.now() - FIRST_LOOK_HOURS * 3600 * 1000;
  if (fs.existsSync(seenFile)) since = Math.max(since, Date.parse(fs.readFileSync(seenFile, 'utf8').trim()) || since);
  const notes = [];
  for (const line of fs.readFileSync(ledger, 'utf8').split(/\r?\n/)) {
    if (!line.includes('"note"')) continue;
    let e;
    try { e = JSON.parse(line); } catch { continue; }
    const at = Date.parse(e.ts);
    if (e.type !== 'note' || !e.agent || e.agent === agent || !(at > since)) continue;
    notes.push({...e, at});
  }
  if (!notes.length) return;
  notes.sort((a, b) => a.at - b.at);
  fs.mkdirSync(path.dirname(seenFile), {recursive: true});
  fs.writeFileSync(seenFile, new Date(notes.at(-1).at).toISOString());
  const from = [...new Set(notes.map((n) => n.agent))].join(', ');
  const shown = notes.slice(-MAX_NOTES);
  const text = [
    `${notes.length} new aos note${notes.length > 1 ? 's' : ''} from ${from} (read before acting; answer with aos note --as ${agent}):`,
    ...shown.map((n) => {
      const body = String(n.text || '');
      return `- ${n.ts} ${n.agent}${n.checkout ? ' @ ' + n.checkout : ''}: ${body.length > MAX_CHARS ? body.slice(0, MAX_CHARS) + ' [...]' : body}`;
    }),
    ...(notes.length > shown.length ? [`(${notes.length - shown.length} older: aos who)`] : []),
  ].join('\n');
  process.stdout.write(JSON.stringify({hookSpecificOutput: {hookEventName: 'PostToolUse', additionalContext: text}}));
}

try { main(); } catch { /* fail open */ }
