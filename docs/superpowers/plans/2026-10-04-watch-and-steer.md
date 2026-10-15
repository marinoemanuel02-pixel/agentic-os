# Plan: watch and steer agents while they work (2026-10-04)

> Amended 2026-10-15: Paseo was removed (`2026-10-15-remove-paseo-design.md`). T6 and the Paseo row of the watch table are cancelled; the rest stands.

Owner: Claude (plan, review, docs). Builder: Codex, through `aos delegate codex --write`, after the
alignment-now video's batch B (the user gave the video priority on 2026-10-04). Branch: `watch-and-steer`.

## Goal

The user can tell at a glance what every agent is doing, see a preview of its work mid-run, and steer,
stop or move it to the other vendor, whether the work started in the Claude or Codex desktop app, the CLI,
`aos delegate` or Paseo on the phone. Watching costs no model tokens; only steering messages and handoffs do.

Done means: `aos test` green in both shells, and the live checks at the end pass.

## Evidence (2026-10-03/04)

- `Invoke-AosProcess` (aos.psm1, `Start-AosProcessCore`) buffers the child's stdout and writes
  `events.jsonl` at exit; Claude delegates use `--output-format json`. A running delegation shows nothing.
- Receipts: Codex runs of 10-67 min; one used 32.7M input tokens over 67 min and failed on a network
  drop; the hero v2 run failed after 51 min on the usage limit with no tokens recorded.
- User's words: "i cannot really control my agents" (Codex chat, 2026-09-30); "they didnt communicate and
  decided their usage allocation" (ledger verdict, 2026-10-03); "a whole chain of thoughts is not useful ...
  I just have to discern at a glance".
- The Paseo daemon was down most of 2026-09-30..10-03 (worker exits 0xC000013A, one 1 s after logon).
  Fixed in a09ec89: the logon task repeats every 5 min through `conhost --headless`.
- Paseo 0.10.1 already has `run -d --label --output-schema --cwd`, `ls/inspect/logs -f --filter tools`,
  `send`, `stop`, `import`; its changelog lists active-turn steering for Claude and Codex (0.9). Our
  delegations bypass it.
- Codex's independent review (delegation 20261003-220046-c48d) agreed on the stream fix and early previews,
  and added: show per row how fresh the data is and whether control is possible from here.

## Not building

A chain-of-thought viewer, a telemetry stack (OpenTelemetry/Aspire need Docker), a new agent runtime,
importing live desktop-app sessions into Paseo (two drivers of one session), model-written summaries.

## Constraints

aos.psm1 stays ASCII and runs under Windows PowerShell 5.1 and 7 (no `??`, ternary, `&&`). Tests in
`tests/aos.Tests.ps1`, fixtures under `$TestDrive`, state under `$env:AOS_COORD`, never the real profile.
New readers take their roots from env so tests can point them at fixtures (`AOS_COORD`, `CODEX_HOME`, a new
`AOS_CLAUDE_PROJECTS` defaulting to `~/.claude/projects`). Every sync step idempotent. Anything that writes
`~/.claude` gets a second opinion before it is applied. No model names in the repo.

## Tasks

### T1 - Delegations stream live (Codex)

- `Start-AosProcessCore` gains `-StdoutFile`, `-StderrFile` (append each line as it arrives, file opened
  with FileShare.ReadWrite so readers can tail it) and `-PidFile` (child PID written right after start).
  `Invoke-AosProcess` passes them through instead of writing at exit. Callers that read `.Out` keep working.
- `Invoke-AosDelegate` writes `run.json` at start: id, vendor, model, mode, pid, started, workdir, branch,
  task title (first line of task.md), preview dir. It is never rewritten; the receipt marks the end.
- Claude delegates use `--output-format stream-json --verbose`; the receipt is built from the final
  `{"type":"result"}` line (session_id, total_cost_usd, usage, is_error, structured_output or result), with
  the same receipt fields as today.
- Tests: a child script that prints line A, sleeps, prints B: A is in the file before the child exits.
  A recorded Claude stream fixture produces the same receipt as the old JSON fixture.

### T2 - Stop at once on a usage limit (Codex)

- `Start-AosProcessCore -StopPattern <regex>`: when a stdout or stderr line matches, kill the tree and
  report `Stopped = 'pattern'` with the line. The delegate passes the usage-limit patterns already handled by
  `Get-AosErrorCategory` (Codex "hit your usage limit", Claude "hit your session limit").
- Outcome `quota-exhausted`, error category `quota`, message = the matched line (it carries the reset time).
- Test: a child prints the limit line then sleeps 60 s; the delegate returns in under 10 s with that outcome.

### T3 - `aos watch` (Codex)

`aos watch [--once] [--json] [--interval <s>] [--open <id>]`, read-only, one line per item, newest first:

| Source | Row | Control shown |
|---|---|---|
| delegations with no receipt | title, vendor, state (running if the run.json PID lives, else `dead`), elapsed, last action and its age (Codex: item type plus command or file; Claude: tool name plus first argument), tokens so far, files changed (`git status --porcelain` count in the workdir), newest preview file | `aos delegate stop/move <id>` |
| Paseo agents (`paseo ls --json`, only if the daemon runs) | title, provider, status | `paseo send/stop <id>` |
| Claude transcripts (`AOS_CLAUDE_PROJECTS/*/*.jsonl`) and Codex rollouts (`CODEX_HOME/sessions/**/rollout-*.jsonl`) changed in the last 15 min | cwd, last tool and its age | `open the app` |
| live claims, last 3 notes, daemon state | one line each | - |

Read at most the last 64 KB of any file. Every row shows the age of its last observation; no signal means
`unknown`, never a guess. `--json` emits the same rows for the Paseo panel and the status line. Parsers are
separate functions with fixture tests (Codex rollout, Claude transcript, Codex exec events, Claude stream).

### T4 - Previews mid-run (Codex)

- The delegate sets `AOS_PREVIEW_DIR` (write mode: `<workdir>\.aos-preview`, added to the repo's
  `.git/info/exclude` once; read mode: `<delegation dir>\preview`) and the prompt template asks for a still,
  contact sheet or proxy clip there after each finished stage. At the end it copies the folder to
  `<delegation dir>\preview`, so it outlives the worktree.
- `templates/video/tools/review-sheets.mts` also copies its sheets to `AOS_PREVIEW_DIR` when set (node test).
- `aos watch --open <id>` opens the newest preview. Paseo's file view shows `.aos-preview` in the workspace.

### T5 - Stop and move (Codex)

- `aos delegate stop <id>` writes `stop.request` in the delegation folder; the running delegate checks it
  every 2 s, kills the tree and writes outcome `stopped` itself (one writer of the receipt).
- `aos delegate move <id> --to codex|claude [--verify <cmd>]` (write mode only): stop and wait for the
  receipt; commit any changes in the worktree on the host ("WIP from <id>"); write `handoff.md` (task.md,
  receipt summary, last 30 action lines, `git diff --stat <base>`, verify command); start the other vendor on
  the same worktree and branch (new `-Workdir` reuse path); release the old claim only after its receipt
  confirms the stop, then claim for the new id. Tests with `Invoke-AosProcess` mocked.

### T6 - Delegations as Paseo agents (spike, then opt-in)

- Spike, no repo change, with the local model (free): `paseo run -d --provider pi ... --cwd <scratch>
  --label aos.delegate=spike --output-schema config/delegate/result.schema.json --json "<trivial task>"`, then
  `ls --json`, `logs --json`, `inspect --json`, `send --no-wait`, `stop`. Record whether the structured result
  comes back, whether tokens are reported, and whether Codex's sandbox mode and model can be set.
- If result, send and stop work: `aos delegate ... --via paseo` (opt-in), keeping aos's preflight, worktree,
  claim and receipt, labels `aos.delegate=<id>` and `aos.parent=<session or cli>`. Otherwise a decisions.md
  entry says why, and the Paseo panel reads `aos watch --json` instead.

### T7 - Claude Code status line (Codex builds; second opinion before applying)

- `agents-home/bin/aos-statusline.mjs`: reads the status-line JSON from stdin, runs the inner command it
  wraps with the same stdin (today `ccusage statusline`), and appends ` | aos: <n> running - <title> <state>
  <age>` from the delegations folder. Must finish in under 300 ms with no delegations.
- `aos sync` wraps the user's current `statusLine.command` once (never wraps itself twice), backs up
  settings.json first, and changes nothing on a second run. Node unit test plus Pester idempotency test.

### T8 - Docs (Claude)

README "Watching and steering" (daily use), routing.md rows, decisions.md entry, tool-catalog line for
`aos watch`. Written after T1-T5 land, from what was actually built.

## Order and delegation

0. Codex critiques this plan, read-only, before any code (`aos delegate codex --task <file>` whose task is:
   "Critique docs/superpowers/plans/2026-10-04-watch-and-steer.md on branch watch-and-steer: risky
   assumptions, missing tests, cheaper alternatives, anything that would break PS 5.1. Cite sections.").
   Claude folds the accepted points in, then:
1. Codex: T1 + T2 (one delegation, `--write --verify "pwsh -NoProfile -c 'Import-Module ./aos.psm1; aos test'"`).
2. Codex: T3. 3. Codex: T4 + T5. 4. T6 spike (either vendor; Pi is free). 5. T7 after a second opinion.
6. Claude reviews each diff before merge, then T8.

## Live checks (after merge)

1. Start a read-only delegate; within 10 s of its first event `aos watch --once` shows it running with that
   action and its age.
2. `aos delegate stop <id>` ends it with outcome `stopped` and a released claim.
3. A fake usage-limit stream ends in under 10 s with `quota-exhausted`.
4. A preview written mid-run appears in `aos watch` and in Paseo's file view.
5. After the next sign-in, killing the Paseo daemon brings it back within 5 minutes.
