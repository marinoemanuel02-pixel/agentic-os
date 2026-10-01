# Agent coordination (pass A) and coordinator review (pass B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code, Codex and Pi coordinate through one small, tested, aos-native layer (claims, a ledger, delegation with receipts and preflight), the two observed tool failures are repaired, and the Codex-written phone coordinator gets its independent Claude review.

**Architecture:** Plain files under `~\.aos\coord` (outside OneDrive): `claims\<key>.json` (one writer per checkout, with expiry), `ledger.jsonl` (append-only events), `delegations\<id>\` (task, events, result, receipt). New `aos claim|release|who|delegate` commands in `aos.psm1`. Delegated writes run in their own git worktree on a `delegate/<id>` branch and are accepted only from a receipt plus a host-side verify command. Agents learn the rules from `agents-home/AGENTS.md` and see who holds their checkout through a SessionStart hook in both vendors.

**Tech Stack:** PowerShell 5.1 + 7, Pester 5 (agentic-os); `codex exec --json --output-schema`, `claude -p --output-format json`; TypeScript/vitest (nar-tools, pass B1 only).

**Spec:** this pass has no separate spec. The requirements are the five observed failures (below) and the research it rests on:
`docs/superpowers/research/2026-10-01-coordination-brief.md`, `...-coordination-claude.md`, `...-coordination-codex.md`.
User decisions (2026-10-01): pass A then B1; aos-native layer, not Beads/Agent Mail; use the Codex quota needed.

Observed failures this pass must fix (session of 2026-10-01):
1. A delegated Codex run failed: the configured default model is rejected for this ChatGPT account (HTTP 400); nothing checked first.
2. The delegate could not run the test it wrote: inside `codex sandbox`, `PSModulePath` lists `C:\Users\marin\Documents\PowerShell\Modules`, but Pester 5.9.1 lives in the OneDrive-redirected `...\OneDrive\Documenti\PowerShell\Modules` (readable from the sandbox, just not on the path).
3. A paused Codex automation rewrote `HANDOFF.md` while a live Claude session worked in the same checkout; neither knew of the other.
4. Delegation was hand-typed `codex exec` lines: no record of result, tokens or failure; one prompt broke on quoting.
5. A local-model (`nar_choose`) pick was relayed as a proposal without checking; it was confidently wrong (0.94).
Plus one found while researching: every `codex exec` run logs `hook: SessionStart Failed` / `UserPromptSubmit Failed` / `Stop Failed` from the `cc` plugin (sendbird/cc 1.5.0, latest). Cause: its hooks.json uses `$PLUGIN_ROOT`; Codex runs Windows hook commands through PowerShell, where `$PLUGIN_ROOT` is an empty variable. Codex substitutes `${PLUGIN_ROOT}` textually before any shell runs (codex #19705, April 2026). The Codex -> Claude bridge's session hooks never run.

Measured facts the plan relies on:
- `codex exec --json` emits `thread.started {thread_id}`, `turn.completed {usage: input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens}`, and on failure `turn.failed` / `error`. A one-word probe costs ~19k input tokens (context preamble): cache probe results, never probe per call.
- Codex app-server has `model/list` and `account/rateLimits/read`, but `~/.codex/models_cache.json` still lists the model the account rejects, so a listed model is not proof; a cached probe is.
- `codex.exe` and `claude.exe` are native executables (Start-Process with a timeout works).
- Codex user hooks: `~/.codex/hooks.json` (or `[hooks]` in config.toml), events include `SessionStart`; plain stdout of a SessionStart hook is added as developer context; `commandWindows` overrides the command on Windows.
- Claude headless: `claude -p --output-format json` returns `is_error`, `subtype`, `session_id`, `total_cost_usd`, `usage`. Open bug anthropics/claude-code#79500: a rate-limit error can come back with exit 0 and `subtype: "success"`; trust `is_error`, never the exit code.

## Global Constraints

- `aos.psm1`, `bootstrap.ps1`, `tests/Run-Tests.ps1` stay ASCII-only and run under Windows PowerShell 5.1 and PowerShell 7: no `??`, no ternary, no `&&`/`||`. `aos test` after every edit.
- Tests use `$TestDrive`, `$env:AOS_BACKUPS` and a new `$env:AOS_COORD` (set by Run-Tests.ps1 to a temp folder); never the real profile, `~\.aos\coord`, registry, network, Codex or Claude. External commands are mocked (`Invoke-AosCapture`, and the new `Invoke-AosProcess`).
- No model names in the repo. Models come from the account at run time (probe cache) or an explicit `--model`.
- Every sync step idempotent; merge into the user's files (backup to `~/.aos-backups/` first), never replace.
- No absolute paths in the repo; resolve at run time (`{{aos}}`-style placeholders expanded by sync).
- Anything that writes to `~/.claude` or `~/.codex` gets a Codex review before it is applied (Task 9).
- Coordination state lives in `~\.aos\coord`, never in OneDrive.
- Split authorship: Codex writes the Pester tests for Tasks 3-6 from the behaviour lists below; Claude implements. Each test is seen failing before the implementation exists.
- Concurrency: at most 2 agents per vendor at a time; delegated writers each get their own worktree; one integrator (the caller) merges.

## Review Focus

1. A claim file that is empty or half-written (crash, OneDrive-free path but still a power cut): `aos claim` must not throw; it refuses with the file path and how to clear it, unless the file is older than the maximum TTL (24 h), then it is taken over with a ledger note. (Task 3 tests.)
2. Two processes claim the same checkout at the same moment: exactly one wins; the other gets the holder. (Task 3 test with a held mutex / pre-existing claim.)
3. A delegate that times out or is killed mid-write: receipt says `timed_out`, worktree and branch are left intact for inspection, the claim is released, nothing is merged, exit code 1. (Task 5 test.)
4. Codex hits its usage limit mid-run (exit 0 but an `error`/`turn.failed` event, or "usage limit" text): not accepted, reason recorded, model probing stops instead of trying other models. (Tasks 4 and 5 tests.)
5. Repo or worktree paths with spaces or non-ASCII characters (OneDrive `Documenti`, `caffe` with accent): claim keys, worktree creation and receipts still work; `aos.psm1` itself stays ASCII. (Task 3 and 5 tests use such a path in `$TestDrive`.)

---

### Task 1: Tests run inside the Codex sandbox

**Files:**
- Modify: `tests/Run-Tests.ps1` (Pester discovery; also set `$env:AOS_COORD`)

**Interfaces:**
- Produces: `tests/Run-Tests.ps1` finds Pester 5.5+ when `PSModulePath` misses the real Documents folder; sets `$env:AOS_COORD` to a fresh temp folder like `AOS_BACKUPS`.

- [ ] **Step 1: Record the failure (already observed 2026-10-01).** Run:
  `codex sandbox pwsh -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1`
  Expected now: exit 2, "Pester 5.5+ is not installed".
- [ ] **Step 2: Implement.** In Run-Tests.ps1, when `Get-Module -ListAvailable Pester` has no 5.5+, look in these extra module roots, in order, and import the newest Pester 5.5+ found by path:
  1. `$env:AOS_PESTER_DIR` if set (explicit override);
  2. the registry value `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders` `Personal` (expanded with `[Environment]::ExpandEnvironmentVariables`), plus `\PowerShell\Modules` and `\WindowsPowerShell\Modules`;
  3. `$env:OneDrive` + each of `\Documents`, `\Documenti` + the same two suffixes.
  Keep exit code 2 and the message when none has 5.5+. Add `$env:AOS_COORD = Join-Path ([IO.Path]::GetTempPath()) ('aos-test-coord-' + [guid]::NewGuid().ToString('N'))`.
- [ ] **Step 3: Verify.** `codex sandbox pwsh -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` and the same with `powershell`: exit 0 or genuine test results (if the sandbox blocks something else, record what and stop to decide). Then `aos test` on the host: all green.
- [ ] **Step 4: Commit** `tests: find Pester 5 when PSModulePath misses the redirected Documents folder (Codex sandbox)`.

### Task 2: Repair the cc bridge hooks for Windows

**Files:**
- Modify: `aos.psm1` (new `Repair-AosCcHooks`, called from `Install-AosBridges` and from `Sync-AosBrain` after `Sync-AosCodexAgents`)
- Test: `tests/aos.Tests.ps1` (`Describe 'cc bridge hooks'`, Codex-written)

**Interfaces:**
- Produces: `Repair-AosCcHooks([switch]$DryRun, [string]$PluginsRoot)`; `$PluginsRoot` defaults to `~\.codex\plugins\cache`. Finds `*\cc\*\hooks\hooks.json` under a `sendbird` (or any) marketplace folder; in each `"command"`/`"commandWindows"` string replaces `$PLUGIN_ROOT` not followed by `}` and not preceded by `{` with `${PLUGIN_ROOT}`. Backs up before writing; prints `ok   cc hooks use ${PLUGIN_ROOT}` when nothing to do.

- [ ] **Step 1: Prove the fix by hand first.** Back up `~\.codex\plugins\cache\sendbird\cc\1.5.0\hooks\hooks.json`, change `$PLUGIN_ROOT` to `${PLUGIN_ROOT}`, run `codex exec -m <working model> --profile review "Reply with exactly: PONG" </dev/null` and check the log has no `hook: ... Failed` line. If it still fails, restore the backup and stop: the cause is elsewhere (systematic-debugging). If it passes, restore the original so the test-first cycle stays honest.
- [ ] **Step 2: Codex writes the tests** (batched with Tasks 3-6, see Task 3 Step 1). Behaviours:
  - rewrites `node \"$PLUGIN_ROOT/hooks/x.mjs\"` to `node \"${PLUGIN_ROOT}/hooks/x.mjs\"` in every hook entry; JSON stays valid and otherwise byte-identical;
  - already-fixed file: no write (timestamp unchanged), `ok` line;
  - `-DryRun`: no write, `dry` line;
  - backup made before a write (file appears under `$env:AOS_BACKUPS`);
  - no cc plugin present: one `ok`/info line, no error;
  - leaves `$env:PLUGIN_ROOT` and `${PLUGIN_ROOT}` untouched.
- [ ] **Step 3: Run the tests: FAIL** (function missing).
- [ ] **Step 4: Implement** `Repair-AosCcHooks` (text replace with regex `(?<!\{)\$PLUGIN_ROOT(?![A-Za-z0-9_}])`, `Backup-AosFile`, `Write-AosText`), wire it into `Install-AosBridges` (after the cc install step) and `Sync-AosBrain` (step "Codex plugin repairs").
- [ ] **Step 5: Tests pass; `aos sync`; re-run the PONG probe: no `hook: ... Failed`.** Second `aos sync`: `ok` only.
- [ ] **Step 6: Commit** `aos: repair cc plugin hooks for Windows (${PLUGIN_ROOT}); Codex runs hooks in PowerShell`. Offer the user an upstream issue on the cc plugin (outward-facing: ask first).

### Task 3: Coordination store: ledger and claims (`aos claim|release|who`)

**Files:**
- Modify: `aos.psm1` (new region `coordination`; dispatch entries `claim`, `release`, `who`; help text)
- Test: `tests/aos.Tests.ps1` (`Describe 'Coordination ledger'`, `Describe 'Coordination claims'`, Codex-written)

**Interfaces (Produces):**
- `Get-AosCoordDir` -> `$env:AOS_COORD` if set, else `~\.aos\coord`; creates nothing.
- `Add-AosLedgerEvent([System.Collections.IDictionary]$Event)` -> appends one compact JSON line `{ "ts": "<UTC ISO 8601>", ...Event }` to `<coord>\ledger.jsonl` (UTF-8 no BOM) under named mutex `Local\aos-coord`; creates the folder if missing.
- `Get-AosLedger([int]$Last = 20)` -> array of ordered hashtables, oldest first, skipping lines that do not parse.
- `Get-AosCheckout([string]$Path)` -> full path of the git top level containing `$Path` (via `Invoke-AosCapture "git -C ""$Path"" rev-parse --show-toplevel"`, slashes turned to backslashes), or `[IO.Path]::GetFullPath($Path)` when not in git.
- `Get-AosClaimKey([string]$Checkout)` -> first 16 hex chars of SHA-256 of the lower-cased checkout path (UTF-8 bytes).
- `Invoke-AosClaim([string]$Path, [string]$Agent, [string]$Session = 'default', [string]$Note = '', [int]$TtlMinutes = 120)` -> `[pscustomobject]@{ Ok; Claim; Holder; Message }`. File `<coord>\claims\<key>.json` = `{ checkout, agent, session, note, since, expires, pid }`. Under mutex `Local\aos-coord`: none -> create; same agent+session -> renew (`expires` moves, `since` kept); other holder not expired -> `Ok=$false`, `Holder` = their claim; other holder expired -> take over + ledger `claim-takeover`; unreadable file -> refuse with `Message` naming the file, unless its LastWriteTime is older than 24 h (then take over + ledger note). Agent must match `^[a-z][a-z0-9:_-]{0,40}$`; TTL 1..1440. Ledger events `claim`, `renew`, `claim-refused`.
- `Invoke-AosRelease([string]$Path, [string]$Agent, [string]$Session = 'default')` -> `Ok=$true` and file removed when owned; otherwise `Ok=$false` with the holder; ledger `release`.
- `Get-AosClaims` -> live (unexpired, readable) claims.
- CLI: `aos claim [<path>] --as <agent> [--session <id>] [--note <text>] [--ttl <minutes>] [--json]`, `aos release [<path>] --as <agent> [--session <id>]`, `aos who [--json] [--here] [--as <agent>]`. `<path>` defaults to the current directory. Refusal sets `$global:LASTEXITCODE = 1`, success `0`. `aos who --here --as <agent>` prints exactly one line when ANOTHER agent holds the current checkout (`Note: <checkout> is held by <agent> (<session>) since <since>, until <expires>: <note>. Do not write here; coordinate first.`) and nothing otherwise (used by hooks, so it must be quiet and fast).

- [ ] **Step 1: Delegate the tests to Codex (one batched run for Tasks 2-6).** Use `codex exec -m <working model> --sandbox workspace-write` in a fresh worktree `~\.aos\worktrees\agentic-os-coord-tests` on branch `coord-tests` from `phone-orchestration-design` HEAD (this run predates `aos delegate`; it is the bootstrap). Prompt: the Interfaces and behaviour lists of Tasks 2-6 verbatim, the conventions (inside the outer `Describe 'aos isolated suite'`, `$TestDrive`, `$env:AOS_COORD`, mock `Invoke-AosCapture`/`Invoke-AosProcess`, ASCII, PS 5.1 + 7 syntax), "write only tests, commit on the branch, run them and report that they fail because the functions are missing". Claude cherry-picks the commit after reading it.
  Behaviours for Task 3:
  - ledger: two events append two lines in order; `Get-AosLedger -Last 1` returns the newest; a garbage line is skipped; non-ASCII note (`caffe` with accent) round-trips; folder created on first write.
  - claim: first claim Ok and file present with the six fields; same agent+session renews (`expires` later, `since` equal); other agent refused with `Holder.agent` set and LASTEXITCODE 1 via `aos claim`; expired claim (write a file with `expires` in the past) taken over and ledger has `claim-takeover`; empty claim file refused with a message containing its path; empty claim file with LastWriteTime 25 h ago taken over; invalid agent name and TTL 0 / 1441 rejected without a file; checkout path with a space and a non-ASCII folder works; `Get-AosCheckout` falls back to the full path when git fails (mocked).
  - release: owner releases (file gone, ledger `release`); non-owner cannot (file stays).
  - who: `aos who --here --as claude` prints nothing when nobody or claude holds it, and the one-line notice when codex holds it; `--json` returns parseable JSON with the live claims and last ledger events.
- [ ] **Step 2: Run tests: FAIL** (functions missing). Save the output.
- [ ] **Step 3: Implement** the functions above. Mutex: `New-Object System.Threading.Mutex($false, 'Local\aos-coord')`, `WaitOne(5000)`, release in `finally`; abandoned mutex (`AbandonedMutexException`) counts as acquired. Write claim files via a temp file + `[IO.File]::Replace`/`Move` so a reader never sees half a file.
- [ ] **Step 4: Tests pass; `aos test` green.**
- [ ] **Step 5: Commit** `aos: coordination ledger and checkout claims (aos claim, release, who)`.

### Task 4: Delegation preflight and model resolution

**Files:**
- Modify: `aos.psm1` (coordination region)
- Test: `tests/aos.Tests.ps1` (`Describe 'Delegation preflight'`, Codex-written)

**Interfaces (Produces):**
- `Invoke-AosProcess([string]$Exe, [string[]]$Arguments, [string]$WorkingDirectory, [string]$StdinFile, [string]$StdoutFile, [string]$StderrFile, [int]$TimeoutSeconds)` -> `{ Code; TimedOut }`. Start-Process with redirection and `-PassThru`; on timeout kills the process tree (`taskkill /T /F /PID`). The only place that starts a delegate; tests mock it.
- `Get-AosCodexModelCandidates` -> model slugs from `~\.codex\models_cache.json` with `visibility = list`, sorted by `priority` (no model names in the repo).
- `Resolve-AosDelegateModel([string]$Vendor, [string]$Model)` -> `{ Ok; Model; Reason }`. Claude: `Ok`, `Model = ''` (CLI default). Codex: cache `<coord>\models.json` `{ codex: { model, ok, checked } }` valid 24 h. Order: explicit `$Model` (probe unless cached ok) -> cached -> candidates, at most 3 probes. Probe = `Invoke-AosProcess codex.exe exec -m <m> --profile review --json --skip-git-repo-check -` with stdin `Reply with exactly: PONG`, 120 s, cwd `<coord>`. A probe passes when stdout has a `turn.completed` event and the text PONG, and no `error`/`turn.failed`. Output containing `usage limit` (any case) stops probing: `Ok=$false`, `Reason = 'codex usage limit: ...'`. `not supported` moves to the next candidate. Each probe -> ledger `model-probe` with result and tokens.
- `Test-AosDelegatePreflight([string]$Vendor, [string]$Model, [string[]]$Needs, [string]$WorkDir)` -> `{ Ok; Model; Reasons[] }`: CLI exists (`Test-AosCommand`), model resolves, and each `$Needs` command runs in the delegate's environment: Codex via `Invoke-AosCapture "codex sandbox <cmd>"` in `$WorkDir`, Claude on the host; non-zero exit -> reason `needs failed: <cmd> (exit n): <last line>`.

- [ ] **Step 1: Tests from Codex** (same batch). Behaviours:
  - cached ok model younger than 24 h: no probe (Invoke-AosProcess not called);
  - stale cache: probes; first candidate returns a 400 "not supported" -> second probed and cached; ledger has two `model-probe` events;
  - "usage limit" on the first probe: stops, `Ok` false, reason mentions usage limit, nothing cached;
  - explicit `--model` that fails probe: `Ok` false (does not silently switch);
  - claude vendor: no probe, `Ok` true when `claude` exists, false with reason when missing;
  - a `Needs` command exiting 1 under `codex sandbox`: `Ok` false with the command in the reason;
  - candidates come only from models_cache.json (fixture), sorted by priority, hidden ones skipped.
- [ ] **Step 2: FAIL.** **Step 3: Implement.** **Step 4: PASS, `aos test` green.**
- [ ] **Step 5: Commit** `aos: delegation preflight (cached model probe, sandbox needs check)`.

### Task 5: `aos delegate` with worktrees, receipts and host-side verify

**Files:**
- Create: `config/delegate/result.schema.json` (the delegate's final-answer schema)
- Modify: `aos.psm1` (coordination region; dispatch `delegate`; help)
- Test: `tests/aos.Tests.ps1` (`Describe 'aos delegate'`, Codex-written)

**Interfaces (Produces):**
- `result.schema.json`: object, required `status` (`done|blocked|failed`), `summary` (string), `files_changed` (string[]), `tests_run` (array of `{ command, exit_code (integer), passed (boolean) }`), `unverified` (string[]); `additionalProperties: false`.
- `Invoke-AosDelegate([string]$Vendor, [string]$TaskFile, [switch]$Write, [string]$Model, [string[]]$Needs, [string]$Verify, [int]$TimeoutMinutes = 30, [string]$Repo, [string]$Id)` -> receipt (ordered hashtable), also written to `<coord>\delegations\<id>\receipt.json`.
  1. `id` = `yyyyMMdd-HHmmss-<vendor>-<slug>` (slug from the task's first line, letters/digits/`-`, 30 chars). Folder gets `task.md` (copy).
  2. Workdir: read-only -> `$Repo` (default current checkout). `-Write` -> refuse when `$Repo` is not git; record `base = HEAD`; warn when `git status --porcelain` is not empty ("the delegate sees committed HEAD only"); `git worktree add -b delegate/<id> ~\.aos\worktrees\<repo-name>-<id> <base>`; `Invoke-AosClaim` the worktree as `<vendor>` session `<id>`.
  3. Preflight (Task 4) in the workdir; failure -> receipt `outcome = preflight-failed`, worktree removed (it is empty), claim released.
  4. Prompt file = task.md + footer: workdir, branch, "commit your changes on this branch with messages starting `delegate <id>:`", "your final answer must match the JSON schema; list any test you could not run under `unverified`; never report a test as passed that you did not run".
  5. Run via `Invoke-AosProcess`: Codex `codex.exe exec -m <model> --json --output-schema <schema> -o <dir>\result.json -C <workdir> --sandbox <workspace-write|read-only> --skip-git-repo-check -` (stdin = prompt file, stdout = `events.jsonl`). Claude `claude.exe -p --output-format json --json-schema <schema text> --permission-mode <acceptEdits|plan>` in the workdir (stdin = prompt, stdout = `claude.json`); for `-Write` also `--allowedTools "Bash(git:*) Bash(pwsh:*) Bash(powershell:*) Bash(npm:*) Bash(npx:*)"`.
  6. Parse: Codex -> `thread_id`, summed usage, any `error`/`turn.failed` message; Claude -> `is_error`, `session_id`, `usage`, `total_cost_usd`, structured result (field `structured_output` when present, else JSON parsed from `result`). Text `usage limit` anywhere -> `error = 'usage limit'`.
  7. Write mode: `commits` = `git -C <wt> log --format=%h %s <base>..HEAD`, `changed` = `git -C <wt> diff --name-only <base>`, `uncommitted` = `git -C <wt> status --porcelain`. Release the claim. Never merge, never delete the worktree.
  8. `-Verify <cmd>`: run on the host in the workdir via `Invoke-AosCapture`, keep exit code and last 40 lines in `verify.log`.
  9. Receipt fields: `id, vendor, model, mode, repo, workdir, branch, base, started, ended, seconds, exit_code, timed_out, thread_id, session_id, usage {input, cached, output}, cost_usd, error, delegate {status, summary, unverified}, commits, changed, uncommitted, verify {command, exit_code}, accepted, outcome`. `accepted` = no error, not timed out, delegate status `done`, verify absent or exit 0, and in write mode at least one commit. `outcome` one of `accepted|rejected|failed|timed-out|preflight-failed`. Ledger event `delegate` with `id, vendor, model, outcome, seconds, input, output`.
  10. Prints one summary line plus the receipt path; `$global:LASTEXITCODE` 0 only when accepted.
- CLI: `aos delegate <codex|claude> --task <file> [--write] [--model <m>] [--needs <cmd>]... [--verify <cmd>] [--timeout <min>] [--repo <path>]`; `aos delegate ls [--last <n>]` (table from the ledger); `aos delegate show <id>` (receipt + delegate summary).

- [ ] **Step 1: Tests from Codex** (same batch). Behaviours (all with `Invoke-AosProcess` and git mocked or a real throwaway git repo in `$TestDrive`):
  - read-only Codex run with fixture events (thread.started, item.completed, turn.completed usage) and a schema-valid result.json -> receipt accepted, usage summed, ledger `delegate` event, LASTEXITCODE 0;
  - `error` event with "You've hit your usage limit" and exit 0 -> outcome `failed`, error `usage limit`, not accepted;
  - timeout (`TimedOut = $true`) in write mode -> outcome `timed-out`, worktree folder still exists, claim released, LASTEXITCODE 1;
  - write mode on a real temp git repo whose path contains a space and an accented folder: worktree created on `delegate/<id>`, a commit made by the mocked delegate is listed in `commits`, claim present during the run and gone after;
  - write mode with zero commits -> `rejected`;
  - verify exit 1 -> `rejected` even when the delegate said `done` and listed a passing test;
  - delegate result says a test passed but `-Verify` is absent -> accepted, and the receipt keeps the delegate's `tests_run` separate from wrapper facts (no `verify` block);
  - Claude run: `is_error: true, subtype: success`, exit 0 -> `failed` (bug #79500 shape);
  - repo not git + `-Write` -> refused before any process starts;
  - dirty caller tree -> warning line, run proceeds;
  - `aos delegate ls` lists the last ledger `delegate` events; `show <id>` prints the receipt.
- [ ] **Step 2: FAIL.** **Step 3: Implement.** **Step 4: PASS, `aos test` green.**
- [ ] **Step 5: Commit** `aos: delegate to the other vendor with worktrees, receipts and host-side verify`.

### Task 6: Presence notice at session start (Claude and Codex)

**Files:**
- Modify: `config/claude/settings.json` (SessionStart hook), `aos.psm1` (`Sync-AosCodexHooks`; `{{aos}}` placeholder for the module path in `Sync-AosClaudeSettings`)
- Create: `config/codex/hooks.json` (overlay merged into `~\.codex\hooks.json`)
- Test: `tests/aos.Tests.ps1` (`Describe 'Presence hooks'`, Codex-written)

**Interfaces:**
- Hook command (both vendors): `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '{{aos}}' -DisableNameChecking; aos who --here --as <claude|codex>"`; `{{aos}}` expands to the full path of `aos.psm1` at sync time. Codex entry uses `commandWindows` with the same string and `timeout` 10.
- `Sync-AosCodexHooks([switch]$DryRun)`: merges the overlay into `~\.codex\hooks.json` like `Sync-AosClaudeSettings` (backup, never replace other hooks, idempotent).

- [ ] **Step 0: Measure** `Import-Module aos.psm1; aos who --here --as claude` wall time under Windows PowerShell 5.1. Over 3 s: stop and ask the user whether a hook is still wanted.
- [ ] **Step 1: Tests from Codex** (same batch): overlay merged into an existing `~\.codex\hooks.json` fixture keeps the user's other hooks; second sync writes nothing; DryRun writes nothing; `{{aos}}` expanded to the module path in both files; existing Claude SessionStart hooks of the user are kept (array merge appends ours once).
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS, `aos test` green.**
- [ ] **Step 5: Do not `aos sync` yet** (writes to `~/.claude`, `~/.codex`): wait for the Codex review in Task 9. **Commit** `aos: SessionStart presence notice for Claude and Codex`.

### Task 7: The contract, skills and docs

**Files:**
- Modify: `agents-home/AGENTS.md`, `agents-home/skills/second-opinion/SKILL.md`, `agents-home/skills/handoff/SKILL.md`, `docs/routing.md`, `README.md`, `docs/decisions.md`

- [ ] **Step 1: `agents-home/AGENTS.md`**: add a short "Coordination" section (it costs tokens on every request: at most 8 lines):
  - Before your first edit in a checkout: `aos claim --as <claude|codex|pi>`; refused -> do not write there, tell the user or work in a worktree. `aos release` when done.
  - Hand work to the other vendor with `aos delegate` (receipts in `~/.aos/coord`); accept delegated work only from its receipt and your own check of the diff and tests.
  - Parallel agents read and review; one writer per checkout; delegated writers get their own worktree; you integrate.
  - The local model (nar, Pi) gives hints: check them against the files or tests before acting on or relaying them.
  - Automations and scheduled agents claim before writing and stop if refused.
- [ ] **Step 2: second-opinion skill**: delegation and review rows use `aos delegate codex --task <file>` (read-only) from Claude and `aos delegate claude --task <file>` from Codex; keep the existing rules; log line.
- [ ] **Step 3: handoff skill**: claim the checkout before writing HANDOFF.md; if refused, add a ledger note instead (`aos who` shows it) and tell the user; never overwrite HANDOFF.md written by a live session.
- [ ] **Step 4: routing.md** (patterns: delegate + receipt; one writer per checkout; local model as hint), **README** (`aos claim/release/who/delegate` in daily use), **decisions.md** entry: aos-native layer over Beads/Agent Mail (Beads: 54 MB, embedded Dolt single-writer, rewrites AGENTS.md; Agent Mail: Python 3.14, advisory leases) with the research files as sources; cc hook repair; Pester discovery.
- [ ] **Step 5: Commit** `docs: coordination contract, skills and routing`.

### Task 8: Live acceptance of the coordination layer

- [ ] `codex sandbox pwsh -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1`: passes (Task 1).
- [ ] PONG probe through `aos delegate codex` read-only: receipt accepted, model from the probe cache, tokens recorded, and the Codex log has no `hook: ... Failed`.
- [ ] Two shells: `aos claim --as codex` then `aos claim --as claude` in the same checkout: second refused with the holder; `aos who` shows it; release.
- [ ] One small real `aos delegate claude --task <file>` read-only from PowerShell (the Codex -> Claude direction): receipt accepted, `is_error` false, cost recorded.
- [ ] After Task 9's review and `aos sync`: open a new Codex session in a checkout claimed `--as claude`: it reports the notice; a new Claude session in a checkout claimed `--as codex` does too.

### Task 9: Cross-vendor review of pass A, then apply

- [ ] `aos delegate codex --task <review task>` read-only on `<pass A base>..HEAD` (goal, scope, the Review Focus list). Write Claude's own findings first (second-opinion skill). Report both voices separately; verify each finding before fixing.
- [ ] Fix confirmed findings (test first), `aos test`, then `aos sync` twice (second: only `ok`), commit, push after asking.

### Task 10: Pass B1 - independent Claude review of the nar-tools phone coordinator

**Scope:** nar-tools branch `phone-coordinator` (source worktree `~\.aos\worktrees\nar-tools-coordinator`), commits written by Codex since `197e82d` (24 commits, ~2.5k lines; confirm with `git log --oneline 197e82d..phone-coordinator` and check whether earlier coordinator commits are in scope: the handoff asks for the review "against 197e82d").

- [ ] **Step 1: Claude reviews** (no Codex involvement yet): correctness, failure handling (Stop, reconcile, permission forwarding, admission limits, state locking, replay), security of permission handling, test gaps. Findings to `docs/reviews/2026-10-01-coordinator-claude.md` in nar-tools: id, file:line, defect, failure scenario, severity (high/medium/low), confidence.
- [ ] **Step 2: Local model as a measured hint.** `nar_classify` the findings into high/medium/low (task_type `review-severity`) WITHOUT seeing Claude's labels; record agreement, then `nar_feedback` with Claude's final labels. Report the agreement rate; it decides whether nar is used for severity triage later.
- [ ] **Step 3: Split authorship fixes.** For each confirmed high/medium finding: Claude writes the failing vitest (seen failing), commits on `phone-coordinator`; then `aos delegate codex --write --repo <coordinator worktree> --needs "npm --version" --verify "npm test && npm run typecheck" --task <fix task>` (the author fixes its own code against the reviewer's test). Accept only from the receipt and Claude's own read of the diff; cherry-pick the accepted commit(s).
- [ ] **Step 4:** full `npm test` + `npm run typecheck` in the worktree; push `phone-coordinator` after asking. Updating the live checkout (`phone-coordinator-live`) and `paseo plugin reload aos` is a live change: ask the user first.
- [ ] **Step 5: Report** to the user: findings by severity, what was fixed, the per-agent table (task, outcome, tokens, minutes, verified by), and what the receipts show about the orchestration.

## Codex quota budget (estimate)

Plan critique 1 run; batched test authoring 1 run (maybe 1 retry); pass-A review 1; B1 fixes 1-3 delegations; probes cached (1 per 24 h). About 6-8 Codex runs.
