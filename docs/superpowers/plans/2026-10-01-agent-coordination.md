# Agent coordination (pass A) and coordinator review (pass B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code, Codex and Pi coordinate through one small, tested, aos-native layer (checkout claims enforced at write time, an append-only ledger, delegation with preflight, host-made commits, receipts and host-side verification); the two observed tool failures are repaired; then the Codex-written phone coordinator gets its independent Claude review.

**Architecture:** Plain files under `~\.aos\coord` (outside OneDrive): `claims\<key>.json` (one writer per checkout, renewed on every write), `ledger.jsonl` (append-only events), `delegations\<id>\` (task, events, result, receipt). A PreToolUse guard hook in both vendors claims the checkout on the first edit, renews it on each edit, and blocks edits in a checkout another live session holds; SessionEnd releases. `aos delegate` runs the other vendor in its own worktree; the delegate only edits files (Codex's sandbox keeps `.git` read-only), the wrapper commits on the host, verifies on the host and writes a receipt. New commands: `aos claim|release|who|note|delegate`.

**Tech Stack:** PowerShell 5.1 + 7, Pester 5 (agentic-os); `codex exec --json --output-schema`, `claude -p --output-format json`; TypeScript/vitest (nar-tools, pass B1 only).

**Spec:** no separate spec. Requirements = the observed failures below + research:
`docs/superpowers/research/2026-10-01-coordination-brief.md`, `...-coordination-claude.md`, `...-coordination-codex.md`.
User decisions (2026-10-01): pass A then B1; aos-native layer (not Beads/Agent Mail); use the Codex quota needed.
Revision 2 after Codex's adversarial critique (`docs/superpowers/research/2026-10-01-plan-critique-codex.md`, 16 findings): see "Critique disposition" at the end.

Observed failures this pass must fix:
1. A delegated Codex run failed: the configured default model is rejected for this ChatGPT account (HTTP 400); nothing checked first.
2. The delegate could not run the test it wrote: in Codex's sandbox `PSModulePath` lists `C:\Users\marin\Documents\PowerShell\Modules`; Pester 5.9.1 is in `%OneDrive%\Documenti\PowerShell\Modules`.
3. A paused Codex automation rewrote `HANDOFF.md` while a live Claude session worked in the same checkout.
4. Delegation was hand-typed `codex exec` lines: no record of result, tokens or failure; one prompt broke on quoting.
5. A local-model (`nar_choose`) pick was relayed without checking; it was confidently wrong (0.94).
6. Every `codex exec` logs `hook: SessionStart Failed` / `UserPromptSubmit Failed` / `Stop Failed` from the `cc` plugin (sendbird/cc 1.5.0, the latest): its hooks.json uses `$PLUGIN_ROOT`; Codex runs Windows hook commands through PowerShell, where that is an empty variable; Codex substitutes `${PLUGIN_ROOT}` textually (codex #19705).

Measured facts (2026-10-01, this PC):
- `codex exec --json` events: `thread.started {thread_id}`, `item.completed {item: {type: agent_message, text}}`, `turn.completed {usage: input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens}`; failures as `error` / `turn.failed`. A one-word probe costs ~19k input tokens.
- `~/.codex/models_cache.json` lists the model the account rejects: listing is not proof; a probe is.
- A Codex delegate in `--sandbox workspace-write` can create files but `git add`/`commit` fail: `.git/index.lock: Permission denied` (Codex keeps `.git` read-only). Plain `git status` works in the sandbox.
- In the sandbox, typed `-Command` text runs in ConstrainedLanguage, script files (`-File`) in FullLanguage; `aos.psm1` imports; Pester 5.9.1 imports by explicit path; `$env:OneDrive` is set; the registry `Personal` folder reads the unredirected `C:\Users\marin\Documents`.
- Codex hooks run on the host (not in the sandbox), from `~/.codex/hooks.json`; PreToolUse tool names for edits: `apply_patch`, `Edit`, `Write`; block = exit 2 with reason on stderr, or `hookSpecificOutput.permissionDecision = "deny"`; input has `session_id`, `cwd`, `tool_name`, `tool_input`; timeout in seconds; new or changed hooks run only after the user trusts them (`/hooks`), recorded as `trusted_hash` in `~/.codex/config.toml`. A patched plugin hook is therefore skipped until re-trusted: "no `hook: ... Failed`" alone does not prove a hook ran.
- Claude Code hooks: PreToolUse matcher `Edit|Write|MultiEdit|NotebookEdit`, block with exit 2 or `permissionDecision: deny`; SessionStart/SessionEnd exist; input has `session_id`, `cwd`, `tool_input.file_path`.
- `Import-Module aos.psm1` in a fresh shell: ~500 ms (Windows PowerShell), ~460 ms (pwsh).
- `claude -p --output-format json`: `is_error`, `subtype`, `session_id`, `total_cost_usd`, `usage`; anthropics/claude-code#79500: a rate-limit error can come back with exit 0 and `subtype: success`.
- nar-tools tests live in `paseo-plugin/` (`npm test` = `vitest run`, `npm run typecheck` = `tsc --noEmit`); dependencies come from a `node_modules` junction; a matching cache exists at `~\.aos\deps\paseo-plugin-0.10.1\node_modules`.

## Global Constraints

- `aos.psm1`, `bootstrap.ps1`, `tests/Run-Tests.ps1` ASCII-only, Windows PowerShell 5.1 and PowerShell 7: no `??`, no ternary, no `&&`/`||`. `aos test` after every edit.
- Tests use `$TestDrive`, `$env:AOS_BACKUPS` and `$env:AOS_COORD` (set by Run-Tests.ps1 to a temp folder); never the real profile, `~\.aos\coord`, registry, network, Codex or Claude. External processes go through `Invoke-AosCapture` or the new `Invoke-AosProcess`, both mockable.
- No model names in the repo. Models come from the account (probe cache) or an explicit `--model`.
- Sync steps idempotent; merge into user files with a backup first; never replace.
- No absolute paths in the repo; placeholders expanded at sync (`{{aos}}` = full path of `aos.psm1`).
- Nothing is written to `~/.claude` or `~/.codex` (sync of hooks, cc repair) before Codex has reviewed that diff (Task 7).
- Coordination state only in `~\.aos\coord`.
- Split authorship: Codex writes the Pester tests for Tasks 2-6 from the behaviour lists; Claude implements; each test seen failing first.
- At most 2 agents per vendor; delegated writers in their own worktree; the caller integrates.
- Usage-limit detection reads only error events (`error`/`turn.failed`, or Claude `is_error: true`), never raw output.

## Review Focus

1. Lock file left behind by a killed process, or a claim file empty/half-written: no throw; lock acquisition times out with a clear message; an unreadable claim older than 24 h is taken over with a ledger note, younger is refused with its path. (Task 3)
2. The guard hook itself fails (coord folder unwritable, module missing, timeout): edits are allowed with a one-line warning (fail open), and the failure is in the ledger when it can be written. A guard that blocks every edit is worse than none. (Task 5)
3. A delegate times out and `taskkill` cannot end it: outcome `needs-inspection`, claim kept, nothing committed, exit 1. (Task 6)
4. Codex usage limit or auth failure during a probe or a run: not accepted, category recorded, no further model probes. The words "usage limit" in normal output do not trigger this. (Tasks 4 and 6)
5. Paths with spaces and non-ASCII characters (OneDrive `Documenti`, an accented folder) in repo, worktree, task file and verify command: argument quoting, claim keys and receipts still work. (Tasks 3, 4, 6)

---

### Task 1: Tests run inside Codex's sandbox

**Files:** Modify `tests/Run-Tests.ps1`.

- [ ] **Step 1 (failure already observed):** `codex sandbox pwsh -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` exits 2 "Pester 5.5+ is not installed".
- [ ] **Step 2: Implement.** When `Get-Module -ListAvailable Pester` has no 5.5+, search in order: `$env:AOS_PESTER_DIR`; every `$env:OneDrive\*\PowerShell\Modules\Pester\*\Pester.psd1` and `$env:OneDrive\*\WindowsPowerShell\Modules\Pester\*\Pester.psd1`; import the newest 5.5+ by path. Keep exit code 2 and the message when none is found. Also set `$env:AOS_COORD` to a fresh temp folder like `AOS_BACKUPS`.
- [ ] **Step 3: Verify.** In the sandbox, both `pwsh` and `powershell` with `-File tests/Run-Tests.ps1`: the suite runs; record pass/fail counts and any sandbox-specific failures (e.g. tests that need writes outside the workspace; list them, decide with the user whether to skip them under the sandbox). Host `aos test`: green.
- [ ] **Step 4: Commit** `tests: find Pester 5 in the OneDrive Documents folder (Codex sandbox)`.

### Task 2: Repair the cc bridge hooks

**Files:** Modify `aos.psm1` (`Repair-AosCcHooks`, called from `Install-AosBridges` and as a `Sync-AosBrain` step "Codex plugin repairs"). Test: `Describe 'cc bridge hooks'` (Codex-written).

**Interfaces:** `Repair-AosCcHooks([switch]$DryRun, [string]$PluginsRoot)`; default root `~\.codex\plugins\cache`; every `*\cc\*\hooks\hooks.json`; in `command`/`commandWindows` strings replace `(?<!\{)\$PLUGIN_ROOT(?![A-Za-z0-9_}])` with `${PLUGIN_ROOT}`; backup before writing; after a write print `!!   cc hooks changed: trust them once in Codex (/hooks)`.

- [ ] **Step 1: Tests from Codex** (batched with Tasks 3-6, see Task 3 Step 1): rewrite of every hook entry, valid JSON, otherwise unchanged text; already fixed -> no write (timestamp unchanged) and `ok`; DryRun -> no write; backup under `$env:AOS_BACKUPS`; no cc plugin -> no error; `$env:PLUGIN_ROOT` and `${PLUGIN_ROOT}` untouched; the trust warning appears only when a file was written.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS, `aos test` green. Step 5: Commit** `aos: repair cc plugin hooks for Windows (${PLUGIN_ROOT})`.
- Live application and proof are in Task 8 (after review): run the repair, the user trusts the changed hooks in Codex (`/hooks`), then a `codex exec` probe must show the hooks RUNNING: the cc SessionStart hook leaves its session marker / env file (find the exact file in `hooks/session-lifecycle-hook.mjs` and `scripts/lib/state.mjs` before the run; compare timestamps before/after) and no `hook: ... Failed` line. A plugin update replaces the file: the next `aos sync` repairs it and the trust step repeats (documented in README).

### Task 3: Coordination store: lock, ledger, claims (`aos claim|release|who|note`)

**Files:** Modify `aos.psm1` (region `coordination`; dispatch `claim`, `release`, `who`, `note`; help). Test: `Describe 'Coordination ledger'`, `Describe 'Coordination claims'` (Codex-written).

**Interfaces (Produces):**
- `Get-AosCoordDir` -> `$env:AOS_COORD` if set, else `~\.aos\coord`.
- `Invoke-AosCoordLocked([scriptblock]$Body, [int]$TimeoutMs = 5000)` -> runs `$Body` while holding `<coord>\coord.lock` opened with `FileMode.OpenOrCreate`, `FileAccess.ReadWrite`, `FileShare.None` (retry every 50 ms until timeout, then throw `coordination lock busy: <path>`). Works across logon sessions, scheduled tasks and the Paseo daemon (a file, not a session-scoped mutex). The OS releases it when a process dies.
- `Add-AosLedgerEvent([System.Collections.IDictionary]$Event)` -> one compact JSON line `{"ts": "<UTC ISO 8601>", ...}` appended to `<coord>\ledger.jsonl` (UTF-8 no BOM) inside the lock.
- `Get-AosLedger([int]$Last = 20)` -> ordered hashtables, oldest first, skipping unparsable lines.
- `Get-AosCheckout([string]$Path)` -> git top level of `$Path` (file or folder) via `Invoke-AosProcess git rev-parse --show-toplevel` with WorkingDirectory = the folder, backslashes; when git fails, the full path of the folder. Never different for host and hooks: both run on the host.
- `Get-AosClaimKey([string]$Checkout)` -> first 16 hex of SHA-256 of the lower-cased checkout path (UTF-8).
- `Invoke-AosClaim([string]$Path, [string]$Agent, [string]$Session, [string]$Note = '', [int]$TtlMinutes = 60)` -> `{ Ok; Action (created|renewed|taken-over|refused); Claim; Holder; Message }`. `$Session` is required (hooks pass the vendor session id; CLI users pass `--session`, default `<agent>-<PID of the calling shell>`). Claim file `{ checkout, agent, session, note, since, renewed, expires, host_pid }`, written via temp file + rename inside the lock. Rules: none -> create; same agent AND same session -> renew; any other holder unexpired -> refuse; expired -> take over (ledger `claim-takeover` with the old holder); unreadable file -> refuse naming the file, unless LastWriteTime older than 24 h -> take over + ledger. Agent `^[a-z][a-z0-9:_-]{0,40}$`; TTL 1..1440.
- `Invoke-AosRelease([string]$Path, [string]$Agent, [string]$Session)` -> only the same agent+session releases.
- `Get-AosClaims` -> live claims.
- `aos claim [<path>] --as <agent> [--session <id>] [--note <text>] [--ttl <min>] [--json]`; `aos release [<path>] --as <agent> [--session <id>]`; `aos who [--json]`; `aos note <text> --as <agent>` (ledger `note` with the current checkout). Refusal -> `$global:LASTEXITCODE = 1`.

- [ ] **Step 1: Delegate the tests to Codex (one batched run for Tasks 2-6).** This predates `aos delegate` (bootstrap): host creates worktree `~\.aos\worktrees\agentic-os-coord-tests` on branch `coord-tests` from HEAD; `codex exec -m <working model> --sandbox workspace-write -C <worktree> -` with the prompt on stdin: the Interfaces and behaviour lists of Tasks 2-6 verbatim, the conventions (inside the outer `Describe 'aos isolated suite'`; `$TestDrive`; `$env:AOS_COORD`; mock `Invoke-AosCapture`/`Invoke-AosProcess`; ASCII; PS 5.1 + 7 syntax), "write only tests; do not try to commit (the sandbox cannot); run `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` after Task 1 is merged and report that the new tests fail because the functions are missing". Claude reads the diff, commits it on the host, cherry-picks.
  Behaviours for Task 3:
  - ledger: two events -> two lines in order; `-Last 1` newest; garbage line skipped; accented note round-trips; folder created on first write.
  - lock: a second `Invoke-AosCoordLocked` while the first holds the file (open the lock file with FileShare.None in the test) times out with `coordination lock busy`; lock freed after the body throws.
  - claim: create (file with all fields, Action created); same agent+session renews (`expires` later, `since` same); same agent, other session -> refused; other agent refused with `Holder.agent`, `aos claim` sets LASTEXITCODE 1; expired -> taken-over + ledger `claim-takeover`; empty file -> refused with its path; empty file 25 h old -> taken over; invalid agent / TTL 0 / 1441 rejected without a file; path with a space and an accented folder works; `Get-AosCheckout` falls back to the folder when git fails (mocked) and resolves a file path to its folder's checkout.
  - release: owner releases (file gone, ledger `release`); other session cannot.
  - who/note: `aos who --json` parses and lists live claims and the last ledger events; `aos note` writes a `note` event with the checkout.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS, `aos test` green.**
- [ ] **Step 5: Commit** `aos: coordination lock, ledger and checkout claims`.

### Task 4: Process runner and delegation preflight

**Files:** Modify `aos.psm1`. Test: `Describe 'Process runner'`, `Describe 'Delegation preflight'` (Codex-written).

**Interfaces (Produces):**
- `ConvertTo-AosArgString([string[]]$Arguments)` -> one Windows command-line string following the MSVCRT/CommandLineToArgvW rules (quote when empty or containing space/tab/quote; double backslashes before a quote; escape quotes).
- `Invoke-AosProcess([string]$Exe, [string[]]$Arguments, [string]$WorkingDirectory, [string]$StdinFile, [string]$StdoutFile, [string]$StderrFile, [int]$TimeoutSeconds)` -> `{ Code; TimedOut; KillFailed }`. Uses `System.Diagnostics.Process` with `ProcessStartInfo.Arguments = ConvertTo-AosArgString`, `UseShellExecute = $false`, redirected streams copied to the files (stdin from file). On timeout: `taskkill /T /F /PID`, then wait up to 10 s; still alive -> `KillFailed = $true`. `.cmd`/`.bat` targets are refused (only native exes).
- `Get-AosCodexModelCandidates` -> slugs from `~\.codex\models_cache.json` with `visibility = list`, by `priority`.
- `Resolve-AosDelegateModel([string]$Vendor, [string]$Model)` -> `{ Ok; Model; Category; Reason }`. Claude: `Ok`, `Model = ''`. Codex: cache `<coord>\models.json` `{ codex: { model, checked } }` valid 24 h (only successes are cached). Explicit `$Model`: use it if cached, else probe once; failure -> `Ok=$false` (never switches). No explicit model: cached, else at most 2 candidates. Probe: `Invoke-AosProcess codex.exe @('exec','-m',<m>,'--profile','review','--json','--skip-git-repo-check','-')`, stdin `Reply with exactly: PONG`, 120 s, WorkingDirectory `<coord>`. Classify from `error`/`turn.failed` messages only: `not-supported` (contains "not supported") -> next candidate; `quota` ("usage limit", "rate limit", "429") and `auth` ("401", "unauthorized", "login") and `other` -> stop. Pass = `turn.completed` + an agent_message containing PONG. Ledger `model-probe` with model, category, input tokens.
- `Clear-AosDelegateModelCache([string]$Vendor)` (called when a real run fails `not-supported`).
- `Test-AosDelegatePreflight([string]$Vendor, [string]$Model, [string[]]$Needs, [string]$Verify, [string]$WorkDir)` -> `{ Ok; Model; Reasons[] }`: CLI exists; model resolves; the verify command's executable is found where the delegate runs (Codex: `Invoke-AosProcess codex.exe @('sandbox','where.exe',<exe>)` in `$WorkDir`; Claude: `Get-Command`); every `$Needs` command exits 0 there (Codex: `codex.exe sandbox` + the command split by `ConvertTo-AosArgString` rules; Claude: host). Reasons carry the command, exit code and last output line.

- [ ] **Step 1: Tests from Codex** (same batch):
  - `ConvertTo-AosArgString`: `a b` -> `"a b"`; `C:\p q\` -> `"C:\p q\\"`; `say "hi"` -> `"say \"hi\""`; empty -> `""`; accented path kept; round-trip check by passing the string to `cmd /c echo` is NOT used (mock-free pure function).
  - `Invoke-AosProcess` (real, harmless): `where.exe` with a missing name -> non-zero Code; a `powershell -NoProfile -Command Start-Sleep 30` with timeout 1 -> TimedOut, KillFailed false; WorkingDirectory with a space is honoured (`cmd.exe /c cd` output); `.cmd` target refused.
  - model: cached fresh model -> no probe; stale cache -> probes; first candidate "not supported" -> second probed and cached, two ledger `model-probe` events; first probe `error` event "You've hit your usage limit" -> stops, category quota, nothing cached; an agent_message mentioning "usage limit" with turn.completed and PONG -> passes; explicit model failing -> Ok false, no other probe; hidden models skipped; claude -> no probe.
  - preflight: verify executable not found in sandbox -> reason names it; a `--needs` exit 1 -> reason has the command; all fine -> Ok.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS, `aos test` green. Step 5: Commit** `aos: process runner with Windows quoting; delegation preflight`.

### Task 5: Write guard and presence hooks (Claude and Codex)

**Files:** Modify `aos.psm1` (`Invoke-AosGuard`; `Sync-AosCodexHooks`; owned-hook merge for Claude settings), `config/claude/settings.json`; Create `config/codex/hooks.json`. Test: `Describe 'Write guard'`, `Describe 'Presence hooks sync'` (Codex-written).

**Interfaces (Produces):**
- `Invoke-AosGuard([string]$Agent, [string]$Event, [string]$InputJson)` -> `{ Exit; Stdout; Stderr }` (the hook wrapper prints them and exits):
  - `pre-edit`: paths = Claude `tool_input.file_path` (or `notebook_path`); Codex `apply_patch` -> lines `*** Add File: `, `*** Update File: `, `*** Delete File: `, `*** Move to: ` in `tool_input` (relative to `cwd`); `Edit`/`Write` -> `tool_input.file_path`; no path found -> `cwd`. For each distinct checkout: `Invoke-AosClaim -Agent $Agent -Session $session_id -TtlMinutes 60 -Note 'auto (first edit)'`. Refused -> Exit 2, Stderr `aos: <checkout> is held by <agent> (<session>) since <since>, until <expires>: <note>. Do not edit here; coordinate (aos who) or use a worktree.`. Created/renewed -> Exit 0, no output.
  - `session-start`: Stdout one line when a live claim on the `cwd` checkout belongs to another session (same text as above, prefixed `Note:`), else nothing. Exit 0.
  - `session-end`: releases every claim of this agent+session. Exit 0.
  - Any exception (lock busy, unwritable coord, bad JSON): Exit 0 with Stderr `aos guard: <message> (edit allowed)` and a best-effort ledger `guard-error`. Fail open.
- Hook command (both vendors), `{{aos}}` expanded at sync: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '{{aos}}' -DisableNameChecking; aos guard <claude|codex> <event>"` with stdin passed through (`aos guard` reads `[Console]::In.ReadToEnd()`). Typed `-Command` runs in FullLanguage on the host (hooks are not sandboxed). Timeouts: PreToolUse 10 s, SessionStart 10 s, SessionEnd 5 s.
- Claude (`config/claude/settings.json`): `hooks.PreToolUse` matcher `Edit|Write|MultiEdit|NotebookEdit`; `hooks.SessionStart`; `hooks.SessionEnd`. Codex (`config/codex/hooks.json`): `PreToolUse` matcher `apply_patch|Edit|Write` (event -> [{ matcher, hooks: [{ type: "command", command, commandWindows, timeout }] }]); `SessionStart`; `SessionEnd`.
- Owned-hook merge (`Merge-AosOwnedHooks`): our hook entries are recognised by the text `aos guard` in `command`; on sync, remove every existing owned entry in the target (also from older repo paths), then add the current ones; other hooks untouched. Used by `Sync-AosClaudeSettings` (for `hooks` only) and `Sync-AosCodexHooks` (`~\.codex\hooks.json`, backup, idempotent). After a Codex hooks write print `!!   Codex hooks changed: trust them once (/hooks)`.

- [ ] **Step 1: Tests from Codex** (same batch):
  - guard pre-edit: free checkout -> Exit 0 and a claim for (agent, session); same session again -> renewed; checkout held by another agent -> Exit 2 and Stderr names the holder; apply_patch input with two files in two different checkouts (temp git repos) -> both claimed; a path with a space and an accented folder; unparsable input -> Exit 0 + `guard: ... (edit allowed)`; lock held by the test -> Exit 0 + warning (fail open).
  - session-start prints the note only for another session's live claim; session-end releases only its own claims.
  - sync: Claude settings with a user's own SessionStart hook keep it and get ours once; a stale owned entry pointing at another path is replaced, not duplicated; second sync writes nothing; Codex hooks.json created when missing, merged when present (user hook kept), DryRun writes nothing, warning printed only on write; `{{aos}}` expanded to the module path.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS, `aos test` green.**
- [ ] **Step 5: Do not `aos sync` yet (Task 7 reviews it first). Commit** `aos: write guard and presence hooks for Claude and Codex`.

### Task 6: `aos delegate`

**Files:** Create `config/delegate/result.schema.json`. Modify `aos.psm1` (dispatch `delegate`; help). Test: `Describe 'aos delegate'` (Codex-written).

**Interfaces (Produces):**
- `result.schema.json`: object; required `status` (`done|blocked|failed`), `summary` (string), `files_changed` (string[]), `tests_run` ({ command, exit_code: integer, passed: boolean }[]), `unverified` (string[]); `additionalProperties: false`.
- `Invoke-AosDelegate([string]$Vendor, [string]$TaskFile, [switch]$Write, [string]$Model, [string[]]$Needs, [string]$Verify, [string[]]$Allow, [string[]]$Setup, [int]$TimeoutMinutes = 30, [string]$Repo)` -> receipt (also `<coord>\delegations\<id>\receipt.json`):
  1. `id` = `yyyyMMdd-HHmmss-<vendor>-<slug>` (first task line, letters/digits/`-`, 30 chars); folder with `task.md`.
  2. Workdir: read-only -> `$Repo` (default: current checkout). `-Write` -> requires git and `-Verify` (refuse otherwise); `base` = HEAD; dirty tree -> warning "the delegate sees committed HEAD only"; `git worktree add -b delegate/<id> ~\.aos\worktrees\<repo-name>-<id> <base>` (host); claim it as `<vendor>` session `<id>`; run each `-Setup` command on the host in the worktree (e.g. a `node_modules` junction).
  3. Preflight (Task 4) in the workdir; failure -> outcome `preflight-failed`, worktree and branch removed (nothing in them), claim released.
  4. Prompt = task.md + footer: workdir and branch; "edit files only; do not run git add/commit (the host commits your changes)"; "your final answer must match the JSON schema; list any test you could not run under `unverified`; never report a test as passed that you did not run".
  5. Run (`Invoke-AosProcess`): Codex `codex.exe exec -m <model> --json --output-schema <schema> -o <dir>\result.json -C <workdir> --sandbox <workspace-write|read-only> --skip-git-repo-check -` (stdin prompt, stdout `events.jsonl`). Claude `claude.exe -p --output-format json --json-schema <schema JSON> --permission-mode <acceptEdits|plan>` (stdin prompt, stdout `claude.json`); write mode adds `--allowedTools` with the executables of `-Verify`/`-Needs` (e.g. `Bash(npm:*)`).
  6. Parse: Codex `thread_id`, summed usage, error messages from `error`/`turn.failed` (classified like Task 4; `not-supported` clears the model cache). Claude `is_error` (true -> failed even with exit 0), `session_id`, `usage`, `total_cost_usd`, structured output (`structured_output`, else JSON in `result`).
  7. Timeout: `KillFailed` -> outcome `needs-inspection`, claim kept, nothing committed, stop. Otherwise continue.
  8. Write mode, on the host: `changed` = `git -C <wt> status --porcelain` paths; `outside_allow` = changed paths matching none of `-Allow` globs (when given); if anything changed: `git add -A` + commit `delegate <id>: <delegate summary first line>` on `delegate/<id>`; `commit` hash recorded. Release the claim.
  9. Verify (write mode required, read-only optional): `Invoke-AosProcess` with WorkingDirectory = workdir; the command line runs via `cmd.exe /d /c <verify>`; exit code and last 40 lines in `verify.log`.
  10. Receipt: `id, vendor, model, mode, repo, workdir, branch, base, commit, started, ended, seconds, exit_code, timed_out, kill_failed, thread_id, session_id, usage {input, cached, output}, cost_usd, error {category, message}, delegate {status, summary, tests_run, unverified}` (the delegate's claims, labelled as such), `changed, outside_allow, verify {command, exit_code}` (wrapper facts), `accepted, outcome`. `accepted` = no error, no timeout, delegate `done`, verify exit 0 (when given), write mode: a commit exists and `outside_allow` empty. `outcome` = `accepted|rejected|failed|timed-out|needs-inspection|preflight-failed`. Ledger `delegate` event: id, vendor, model, outcome, seconds, input, output tokens.
  11. Print one summary line + receipt path; `$global:LASTEXITCODE` 0 only when accepted.
- CLI: `aos delegate <codex|claude> --task <file> [--write] [--model <m>] [--needs <cmd>]... [--verify <cmd>] [--allow <glob>]... [--setup <cmd>]... [--timeout <min>] [--repo <path>]`; `aos delegate ls [--last <n>]`; `aos delegate show <id>`; `aos delegate clean <id>` (removes the worktree and deletes `delegate/<id>` after asking `git branch --merged`-style confirmation: refuses when the branch is not merged into the repo's current branch unless `--force`).

- [ ] **Step 1: Tests from Codex** (same batch; `Invoke-AosProcess` mocked to write fixture files; git real on throwaway repos in `$TestDrive`):
  - read-only Codex run, fixture events + valid result.json -> accepted, usage summed, ledger event, LASTEXITCODE 0;
  - `error` event "You've hit your usage limit" with exit 0 -> failed, category quota;
  - agent_message containing "usage limit" + done result -> not a failure;
  - write mode without `--verify` -> refused before any process;
  - write mode on a repo whose path has a space and an accented folder: worktree on `delegate/<id>`; mocked delegate creates a file; host commit exists on the branch; claim present during the run, gone after; verify exit 0 -> accepted;
  - write mode, nothing changed -> rejected;
  - change outside `--allow` -> rejected with the path in `outside_allow`;
  - verify exit 1 -> rejected although the delegate reported done and a passing test (its claim stays in `delegate.tests_run`);
  - timeout + KillFailed -> needs-inspection, claim kept, no commit; timeout with clean kill -> timed-out, claim released;
  - Claude `is_error: true, subtype: success`, exit 0 -> failed;
  - preflight failure -> preflight-failed, worktree and branch removed;
  - `ls` shows the last delegate events; `show <id>` prints the receipt; `clean` refuses an unmerged branch without `--force`.
- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS, `aos test` green. Step 5: Commit** `aos: delegate with preflight, host commits, receipts and host-side verify`.

### Task 7: Cross-vendor review before anything touches ~/.claude or ~/.codex

- [ ] Claude writes its own findings first (second-opinion skill), then `aos delegate codex --task <review task>` read-only on `<pass A base>..HEAD` (goal, scope, Review Focus, "the guard must fail open; the hooks must not slow sessions"). Report both voices separately. Verify each finding before fixing; fixes test-first.

### Task 8: Apply and accept live

- [ ] `aos sync` twice (second: only `ok`, plus the trust warnings only on the first).
- [ ] The user trusts the changed cc hooks and the new aos hooks in Codex (`/hooks`): a security setting, theirs to approve.
- [ ] cc hooks proof: the session marker/env file written by `session-lifecycle-hook.mjs` changes on a `codex exec` PONG probe, and no `hook: ... Failed`.
- [ ] Sandbox tests: `codex sandbox pwsh -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` runs the suite.
- [ ] Guard, Claude side: with `aos claim <scratch repo> --as codex --session test`, a new Claude session asked to edit a file there is blocked with the holder's message; after `aos release`, the edit works and `aos who` shows the auto claim.
- [ ] Guard, Codex side (failure 3 reproduced): Claude session holds the agentic-os checkout through the guard; `codex exec --sandbox workspace-write -C <agentic-os>` asked to append a line to HANDOFF.md is blocked (apply_patch denied) and reports it; HANDOFF.md unchanged. Measure added latency per edit.
- [ ] `aos delegate codex` read-only PONG-sized task: accepted receipt, model from the cache, tokens recorded.
- [ ] `aos delegate claude` read-only small task from PowerShell (Codex -> Claude direction): accepted, `is_error` false, cost recorded.
- [ ] Commit; push after asking.

### Task 9: Contract, skills, docs

**Files:** `agents-home/AGENTS.md`, `agents-home/skills/second-opinion/SKILL.md`, `agents-home/skills/handoff/SKILL.md`, `docs/routing.md`, `README.md`, `docs/decisions.md`.

- [ ] `agents-home/AGENTS.md` "Coordination" (at most 8 lines): edits claim the checkout automatically (guard hook); a blocked edit means another live session holds it: tell the user or work in a worktree, never work around the guard; hand work to the other vendor with `aos delegate` and accept it only from its receipt plus your own read of the diff; parallel agents read and review, one writer per checkout; `aos note` for messages other agents see in `aos who`; local-model output (nar, Pi) is a hint: verify against files or tests before acting on or relaying it.
- [ ] second-opinion skill: rows use `aos delegate codex --task <file>` / `aos delegate claude --task <file>`; log line.
- [ ] handoff skill: write HANDOFF.md only when your session holds the checkout (the guard enforces edits; for shell writes run `aos claim` first); refused -> `aos note` with the handoff summary and tell the user.
- [ ] routing.md, README (daily use of `aos who/note/delegate`, the trust step after cc updates), decisions.md entry (aos-native layer over Beads/Agent Mail with numbers; guard fails open; host commits because Codex's sandbox keeps `.git` read-only; file lock not session mutex).
- [ ] Commit `docs: coordination contract, skills and routing`.

### Task 10: Pass B1 - independent Claude review of the nar-tools phone coordinator

**Scope:** `phone-coordinator` in `~\.aos\worktrees\nar-tools-coordinator`, `197e82d..HEAD` (24 commits, the range the handoff asks for).

- [ ] **Step 1: Claude reviews** (Codex not involved yet): correctness and failure handling (Stop, reconcile, permission forwarding, admission, store locking, no replay), permission security, test gaps. Findings to `docs/reviews/2026-10-01-coordinator-claude.md` in nar-tools: id, file:line, defect, failure scenario, severity, confidence.
- [ ] **Step 2: local-model measurement (free, informational only, not a decision input):** `nar_classify` the finding summaries into high/medium/low (`review-severity`) without Claude's labels; report agreement; `nar_feedback` with Claude's labels.
- [ ] **Step 3: split authorship fixes.** For each confirmed high/medium: Claude writes the failing vitest on `phone-coordinator` (seen failing, committed); then `aos delegate codex --write --repo <coordinator worktree> --setup "cmd /c mklink /J paseo-plugin\node_modules %USERPROFILE%\.aos\deps\paseo-plugin-0.10.1\node_modules" --needs "npm --prefix paseo-plugin --version" --verify "npm --prefix paseo-plugin test && npm --prefix paseo-plugin run typecheck" --allow "paseo-plugin/server/**" --task <fix task>`. Accept from the receipt plus Claude's read of the diff; merge `delegate/<id>` into `phone-coordinator`; `aos delegate clean <id>`.
- [ ] **Step 4:** full test + typecheck in the coordinator worktree; push `phone-coordinator` after asking; updating `phone-coordinator-live` and `paseo plugin reload aos` only after the user agrees.
- [ ] **Step 5: Report**: findings by severity, fixed vs open, the per-agent table from the ledger (task, outcome, tokens, minutes, verified by), what the receipts show.

## Codex quota budget

Critique done (120k tokens). Batched test authoring 1 run (+1 retry), pass-A review 1, B1 fixes 1-3 delegations, model probes cached (at most 1-2 per 24 h at ~19k each), acceptance 2 small runs. About 6-8 runs.

## Critique disposition (Codex, 2026-10-01; numbering from its report)

Accepted as written: 1 (file lock replaces the session-scoped mutex), 3 (session id required; renew on every edit; TTL 60), 6 (own quoting + process runner with working directory), 7 (KillFailed keeps the claim), 9 (write mode needs host verify; `--allow`; delegate claims labelled), 10 (verify in `paseo-plugin` via `npm --prefix`; `--setup` junction to the dependency cache), 11 (verify executable checked in the delegate's sandbox), 12 (explicit model probed once; max 2 candidates; categories; stop on quota/auth), 13 (owned-hook merge; timeouts; trust step; live check), 14 (`aos note`), 15 (review before any write to ~/.claude, ~/.codex; the Task 2 hand patch was restored), 5 (live proof uses the hook's own side effect, after trust).
Accepted, solved differently: 2 (not only a notice: a PreToolUse guard blocks edits in a held checkout, reproduced in Task 8), 4 (hooks run on the host, so claims work for sandboxed Codex sessions; delegate claims are made by the host wrapper), 8 (measured: a sandboxed delegate cannot write `.git` at all, so the host commits; `aos delegate clean` added).
Partly accepted: 16 (the B1 nar measurement stays because it is free and local, labelled informational; enforcement for nar hints is the guard-free contract line plus the inbox skill's check, there is no hard check for it).
