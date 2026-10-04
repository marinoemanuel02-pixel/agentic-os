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
  assert.match(out.additionalContext, /1 new aos note from codex/);
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

test('long notes are truncated, at most five are listed, and the rest are counted', () => {
  const dir = coord();
  write(dir, Array.from({length: 7}, (_, i) => ({ts: iso(70000 - i * 1000), type: 'note', agent: 'claude', text: `n${i} ` + 'x'.repeat(2000)})));
  const text = context(run(dir, 'codex')).additionalContext;
  assert.match(text, /7 new aos notes from claude/);
  assert.match(text, /2 older: aos who/);
  assert.ok(text.length < 5000);
  assert.doesNotMatch(text, /n0 /, 'the newest five are shown');
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
