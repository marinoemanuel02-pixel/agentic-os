// node --test config/hooks/aos-notes.test.mjs
// The PostToolUse notes hook: unread `aos note`s from the other vendor reach the model (v7 orchestration failure:
// Codex posted notes for 40 minutes that Claude never read).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const hook = path.join(path.dirname(fileURLToPath(import.meta.url)), 'aos-notes.mjs');
const coord = () => fs.mkdtempSync(path.join(os.tmpdir(), 'aos-notes-'));
const iso = (msAgo) => new Date(Date.now() - msAgo).toISOString().replace(/\.\d+Z$/, 'Z');
const write = (dir, events) => fs.writeFileSync(path.join(dir, 'ledger.jsonl'), events.map((e) => JSON.stringify(e)).join('\n') + '\n');
const run = (dir, agent, session = 's1', env = {}) => spawnSync(process.execPath, [hook, agent], {
  input: JSON.stringify({session_id: session, hook_event_name: 'PostToolUse', tool_name: 'Bash'}),
  env: {...process.env, AOS_COORD: dir, AOS_DELEGATE_ID: '', ...env}, encoding: 'utf8', timeout: 10000,
});
const context = (r) => (r.stdout ? JSON.parse(r.stdout).hookSpecificOutput : null);

test('shows the other vendor\'s unread notes once, as PostToolUse additionalContext', () => {
  const dir = coord();
  write(dir, [
    {ts: iso(60000), type: 'note', agent: 'codex', checkout: 'C:\\film', text: 'reset: 100 % 5h, 11 % weekly'},
    {ts: iso(50000), type: 'note', agent: 'claude', checkout: 'C:\\film', text: 'my own note'},
    {ts: iso(40000), type: 'claim', agent: 'codex', checkout: 'C:\\x'},
  ]);
  const first = run(dir, 'claude');
  assert.equal(first.status, 0);
  const out = context(first);
  assert.equal(out.hookEventName, 'PostToolUse');
  assert.match(out.additionalContext, /1 unread aos note from codex/);
  assert.match(out.additionalContext, /reset: 100 % 5h, 11 % weekly/);
  assert.doesNotMatch(out.additionalContext, /my own note/);
  assert.equal(run(dir, 'claude').stdout, '', 'a note is shown once per session');
  assert.match(context(run(dir, 'claude', 's2')).additionalContext, /reset/, 'another session still sees it');
});

test('a new note after the last one shown is reported; old notes before a session are capped to recent ones', () => {
  const dir = coord();
  write(dir, [{ts: iso(30 * 3600 * 1000), type: 'note', agent: 'codex', text: 'ancient'}]);
  assert.equal(run(dir, 'claude').stdout, '', 'notes older than the first-look window stay quiet');
  fs.appendFileSync(path.join(dir, 'ledger.jsonl'), JSON.stringify({ts: iso(1000), type: 'note', agent: 'codex', text: 'fresh'}) + '\n');
  assert.match(context(run(dir, 'claude')).additionalContext, /fresh/);
});

test('long notes are truncated; at most five per call, oldest first, the rest delivered on the next calls (Codex review)', () => {
  const dir = coord();
  write(dir, Array.from({length: 7}, (_, i) => ({ts: iso(70000 - i * 1000), type: 'note', agent: 'claude', text: `n${i} ` + 'x'.repeat(2000)})));
  const text = context(run(dir, 'codex')).additionalContext;
  assert.match(text, /7 unread aos notes from claude, showing 5/);
  assert.match(text, /2 more after your next tool call/);
  assert.ok(text.length < 5000);
  assert.match(text, /n0 /);
  assert.doesNotMatch(text, /n5 /);
  const next = context(run(dir, 'codex')).additionalContext;
  assert.match(next, /n5 /);
  assert.match(next, /n6 /);
  assert.equal(run(dir, 'codex').stdout, '');
});

test('a note written in the same second as the last one shown is still delivered (Codex review)', () => {
  const dir = coord();
  const ts = iso(5000);
  write(dir, [{ts, type: 'note', agent: 'codex', text: 'first'}]);
  assert.match(context(run(dir, 'claude')).additionalContext, /first/);
  fs.appendFileSync(path.join(dir, 'ledger.jsonl'), JSON.stringify({ts, type: 'note', agent: 'codex', text: 'second'}) + '\n');
  const again = context(run(dir, 'claude'));
  assert.match(again.additionalContext, /second/);
  assert.doesNotMatch(again.additionalContext, /first/);
});

test('a Claude subagent call neither shows nor consumes the parent session notes (Codex review)', () => {
  const dir = coord();
  write(dir, [{ts: iso(2000), type: 'note', agent: 'codex', text: 'for the parent'}]);
  const sub = spawnSync(process.execPath, [hook, 'claude'], {input: JSON.stringify({session_id: 's1', agent_id: 'sub-1', agent_type: 'Explore'}), env: {...process.env, AOS_COORD: dir, AOS_DELEGATE_ID: ''}, encoding: 'utf8'});
  assert.equal(sub.stdout, '');
  assert.match(context(run(dir, 'claude')).additionalContext, /for the parent/);
});

test('only the ledger tail after the last read is parsed: a large old ledger stays fast (Codex review)', () => {
  const dir = coord();
  const filler = JSON.stringify({ts: iso(40 * 3600 * 1000), type: 'claim', agent: 'codex', checkout: 'C:\\x'.padEnd(200, 'x')});
  fs.writeFileSync(path.join(dir, 'ledger.jsonl'), (filler + '\n').repeat(60000));
  fs.appendFileSync(path.join(dir, 'ledger.jsonl'), JSON.stringify({ts: iso(1000), type: 'note', agent: 'codex', text: 'tail note'}) + '\n');
  const started = Date.now();
  assert.match(context(run(dir, 'claude')).additionalContext, /tail note/);
  fs.appendFileSync(path.join(dir, 'ledger.jsonl'), JSON.stringify({ts: iso(0), type: 'note', agent: 'codex', text: 'next'}) + '\n');
  assert.match(context(run(dir, 'claude')).additionalContext, /next/);
  assert.ok(Date.now() - started < 3000, 'two calls on a 12 MB ledger');
  const seen = fs.readdirSync(path.join(dir, 'seen'));
  assert.equal(seen.length, 1);
  assert.ok(JSON.parse(fs.readFileSync(path.join(dir, 'seen', seen[0]), 'utf8')).offset > 12e6, 'the read offset is kept');
});

test('fails open: no ledger, a malformed ledger, bad stdin or a delegate run print nothing and exit 0', () => {
  const dir = coord();
  assert.equal(run(dir, 'claude').stdout, '');
  fs.writeFileSync(path.join(dir, 'ledger.jsonl'), 'not json\n{"ts":"bad","type":"note","agent":"codex","text":"t"}\n');
  const r = run(dir, 'claude');
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
  write(dir, [{ts: iso(1000), type: 'note', agent: 'codex', text: 'hello'}]);
  assert.equal(run(dir, 'claude', 's9', {AOS_DELEGATE_ID: 'd1'}).stdout, '', 'a delegate edits under its wrapper; the wrapper reads notes');
  const bad = spawnSync(process.execPath, [hook, 'claude'], {input: 'not json', env: {...process.env, AOS_COORD: dir}, encoding: 'utf8'});
  assert.equal(bad.status, 0);
  assert.equal(bad.stdout, '');
});
