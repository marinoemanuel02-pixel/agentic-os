# Paseo, a local agent and the aos plugin (phone app) Implementation Plan - revision 2

> Superseded 2026-10-15: Paseo was removed from this PC and repo (`2026-10-15-remove-paseo-design.md`). Kept as history.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the Android phone, away from home, start and steer sessions on this PC with Claude Code, Codex and an agent that runs on the local model, answer their permission prompts, and use a Paseo plugin to see agentic-os status and nar calibration and to give nar feedback.

**Architecture:** Paseo's daemon runs on the PC and pairs with the Paseo Android app through its end-to-end encrypted relay. Its providers are Claude Code and Codex (the official CLIs, so the subscriptions) plus Pi on the local model. Pi talks to `aos-agent`, an Ollama variant of the default model with a 16K context (Qwen3.5-4B holds 16K entirely on the 6 GB GPU); an aos extension makes Pi ask, through Paseo, before it runs a command or writes a file. Pi is adopted only if a real session through Paseo passes a context gate; OpenCode is the fallback. The plugin (TypeScript, `nar-tools/paseo-plugin`) runs only fixed commands.

**Tech Stack:** PowerShell 5.1 + 7 and Pester 5 (agentic-os); Python 3.13 (nar CLI); TypeScript, Vitest, Paseo plugin SDK (plugin); Ollama 0.34.4; Paseo 0.10.1 and Pi 0.87.1 from npm; Node 24.19.0.

**Spec:** `docs/superpowers/specs/2026-09-28-local-stack-design.md` (build steps 4 and 5). Deviation: the spec names OpenCode as the local harness; Pi is tried first (smaller prompt and download, below). Recorded in `docs/decisions.md` by Task 9.

## Status (2026-09-29 afternoon)

- Done: Tasks 1-9 (commits on agentic-os `paseo-app` and nar-tools `paseo-app`/`paseo-plugin`). Pi passed
  the Task 7 gate (numbers in `docs/decisions.md`, 2026-09-29), so the OpenCode fallback is not needed.
  The plugin was tested end to end in Paseo's local web UI: the panel renders status, calibration and
  recent calls, and a tap recorded feedback that `nar status` and `nar recent` confirm.
- Left: Task 10 (the user pairs the phone by QR, then the away-from-home checks); start-at-login is the
  user's choice; voice (about 1 GB of speech models) is off until the user decides.

## Review record (round 2, 2026-09-29)

Codex reviewed revision 2 (9 findings; one run was cut by its usage limit and resumed). Dispositions:
Paseo env through `config set` impossible and `config get` redacts secrets -> no Paseo env override; Pi
telemetry off in Pi's own settings, and aos sets only `pluginsEnabled` through the CLI. Pi sends
`max_completion_tokens` -> `compat.maxTokensField: max_tokens` (verified live: Pi sent a shrinking
`max_tokens`). The gate must use the untruncated size -> every request captured and replayed against a
32K copy; Codex's claim that Ollama reports cached tokens outside `prompt_tokens` was checked and did not
hold. Codex permission test -> Task 10 asks for a write outside the workspace. Provenance -> the whole
normalized modelfile is compared. 30 s RPC deadline -> `aos status` runs in the background (it took
~28 s). `paseo provider models` used for model lists. Gate enforcement -> node tests for Allow, Deny,
dismissal and no UI, plus live Deny/Allow through Paseo. OpenCode fallback -> would need its own plan.

## Review record (round 1, 2026-09-29)

Claude wrote its review first (scratchpad `review-claude-paseo-plan.md`), then Codex reviewed blind (`codex exec --profile review`, 12 findings). Every Codex citation was checked against the code before it was accepted.

- **Both flagged:** `Merge-AosTree` unions arrays, so an aos-managed command array keeps the old executable (aos.psm1:117) -> aos now replaces the subtrees it owns (Tasks 5, 6). No context limit in the harness's model config, so the harness never compacts and Ollama truncates silently -> explicit limits (Task 5). The prompt measurement (Ollama error on overflow, `server.log`) does not work -> Task 7 reads the usage Pi records per reply, in a real session through Paseo. `nar feedback` turned digit text into an index -> `--index` / `--option` (done).
- **Only Codex:** the fallback harness had no steps and "neither fits" silently dropped the third agent -> Task 7 blocks instead; the config was never applied before phone testing -> apply steps in Tasks 5-6; a failed rebuild left adoption half-done with no retry -> Task 1; a refit failure after recording reported an error, and duplicate taps inflated the refit counter -> done in nar; UTF-8 between Python and Node -> done in nar, plus `PYTHONIOENCODING` in the plugin; the RPC boundary was untested -> handler tests with a mocked runner (Task 8); the acceptance test lacked away-from-home, steering and a reliable permission prompt -> Task 10; `plugin init` installs nothing and the clamp test proved nothing -> fixed; the gateway panel was dropped silently -> deferred explicitly to step 3.
- **Only Claude:** real download sizes (OpenCode ~360 MB: both x64 binaries install; Paseo 538 MB and Pi 414 MB as installed); Pi before OpenCode; Node 24 vs Paseo's pinned 22; plugin `node_modules` must stay out of OneDrive; Paseo's default permission modes (Claude starts in `auto`); `aos local adopt` does not check that 16K still fits the GPU; Qwen3.5 thinks by default; `Sync-AosOpenCode` ran without OpenCode; a provider without an API key may not count as connected; the `aos status` timeout.
- **Found while revising:** Pi's default `compaction.reserveTokens` is 16384, which equals the whole window: without an override Pi would compact on every turn. Pi sends install telemetry by default (`enableInstallTelemetry`). Paseo gives Pi no permission prompts of its own (`providers/pi/agent.ts:1436`: no modes); only Pi extension dialogs reach the phone.

## Global Constraints

- Everything from the step 1-2 plan still holds: ASCII in `aos.psm1`/`bootstrap.ps1`, PowerShell 5.1 and 7, tests first and seen failing, idempotent, nothing created under AppData from inside the desktop apps, no absolute paths in repos, no secrets in files, model tags only in `config/local.json`.
- Measured on this laptop (2026-09-29): qwen3.5:4b holds a 16K context 100% on the GPU (3.30 GB); 32K runs 77% on the GPU. A local harness is adopted only if its largest request in the Task 7 session leaves 4K for the reply: `max(usage.input) <= 16384 - 4096`.
- aos owns named subtrees in other programs' config files (`providers.aos` in Pi's `models.json`, `aos-*` extension files, `pluginsEnabled` in Paseo) and replaces them whole; it never unions arrays inside them and never touches keys it does not own. It backs a file up before changing it and writes nothing when nothing changes.
- The plugin never runs user- or model-supplied commands: only `aos status`, `nar status`, `nar recent --limit 10` and `nar feedback <call_id> --index <n>` with validated arguments.
- Installs come only from official sources (npm registry; the Paseo app from the Play Store). The phone pairing, a daemon password, start-at-login and any consent screen are the user's.
- Heavy dependency folders stay out of OneDrive: plugin development happens in a git worktree under `~\.aos\worktrees`.

---

### Task 1: The `aos-agent` model variant (agentic-os)

**Files:** `config/local.json` (`agent_model`, `agent_num_ctx`), `aos.psm1` (`Get-AosAgentModelfile`, `Test-AosAgentModel`, `Sync-AosAgentModel`; calls from `Install-AosLocal`, `Invoke-AosLocalAdopt`, `Sync-AosBrain`; an `aos status` line), `tests/aos.Tests.ps1` (`Describe 'Agent model variant'`).

**Interfaces:**
- `Get-AosAgentModelfile -From <tag> -NumCtx <int>` -> `"FROM <tag>`nPARAMETER num_ctx <n>`n"`.
- `Test-AosAgentModel -Name <agent> -From <tag> -NumCtx <int>` -> `'ok' | 'missing' | 'stale'`. The truth comes from Ollama, not from bookkeeping: `ollama show <agent> --modelfile` must contain `PARAMETER num_ctx <n>`, and its `FROM` lines (weight blobs) must equal those of `ollama show <tag> --modelfile`. Measured: the default's modelfile has one `FROM <blob path>` line and a `# FROM qwen3.5:4b` comment (ignore comment lines).
- `Sync-AosAgentModel [-DryRun]`: when the state is not `ok`, writes `~\.aos\agent.Modelfile` and runs `ollama create <agent> -f <file>`; after a create, loads the variant once and warns if `ollama ps` does not show it 100% on the GPU (`Test-AosOllamaGpu`). Nothing in `~\.aos\local.json`, so `Sync-AosLocalState` is unchanged.
- `Invoke-AosLocalAdopt`: the "already the default" branch now also runs `Sync-AosLocalState` and `Sync-AosAgentModel`, so repeating an adopt retries a failed rebuild. `Sync-AosBrain` (`aos sync`) calls `Sync-AosAgentModel` too.

- [ ] **Step 1: Failing tests** - `Describe 'Agent model variant'` with mocks for `Get-AosLocalConfig` (`agent_model = 'aos-agent'`, `agent_num_ctx = 16384`), `Test-AosCommand ollama`, and `Invoke-AosCapture` for `ollama list`, `ollama show <x> --modelfile`, `ollama create *`, `ollama run *`, `ollama ps`:
  1. the Modelfile text has `FROM qwen3.5:4b` and `PARAMETER num_ctx 16384` lines;
  2. `Test-AosAgentModel`: `missing` when `ollama show aos-agent` fails; `stale` when its FROM blob differs from the default's or `num_ctx` differs; `ok` when both match (comment lines ignored);
  3. `Sync-AosAgentModel` creates when missing, then checks the GPU (warns on `35%/65% CPU/GPU`);
  4. does nothing when `ok`; recreates when `stale`;
  5. a failed `ollama create` warns and reports nothing as ok;
  6. DryRun and a default that is not pulled create nothing;
  7. `Invoke-AosLocalAdopt` with the tag that is already the default still calls `Sync-AosAgentModel`.
- [ ] **Step 2:** `aos test`: the new tests fail, the rest pass.
- [ ] **Step 3: Implement** as in Interfaces; `config/local.json` gets the two keys and a `_readme` line ("agent_model: an Ollama variant of the default with agent_num_ctx context for agent harnesses; OpenAI-compatible clients cannot set the context size. 16K holds 100% on the 6 GB GPU with qwen3.5:4b."). Status line: `aos-agent: ok (qwen3.5:4b, 16K)` or a warning with `aos install local` as the fix.
- [ ] **Step 4:** `aos test` green in both shells. **Step 5:** commit; then `aos install local` creates the variant for real, and `ollama show aos-agent --parameters` shows `num_ctx 16384`.

---

### Task 2: `nar feedback` on the command line (nar-tools) - DONE (0fd3505)

`nar feedback CALL_ID (--index N | --option TEXT)`; call id validated before the store is touched; one outcome per call (checked and appended under `feedback.lock`); a refit failure after recording returns `recorded: true` with `refit.error`; UTF-8 output even when piped. Tests and code by Codex; Claude saw 26 new tests fail on the old code, then 122 pass.

### Task 3: `nar recent` (nar-tools) - DONE (0fd3505)

`nar recent [--limit N]` (1..50, newest first, unlabelled scored calls; `choice_index` = argmax). Tested with 51 calls, `--limit 0`, the default, and a record with missing fields.

### Task 4: npm tools by command name; the phone layer - DONE (d8308c4)

`Install-AosNpmTools` checks `<prefix>\<bin>.cmd`; new layer `phone` (`aos install phone`) installs `@getpaseo/cli`; the local layer installs `@earendil-works/pi-coding-agent`. Installed 2026-09-29 into `~\.npm-global`: Paseo 0.10.1 (538 MB, of which 253 MB is the Claude Agent SDK's bundled Windows binary) and Pi 0.87.1 (414 MB, of which 284 MB is esbuild for all 26 platforms, a packaging quirk).

---

### Task 5: Pi on the local model (agentic-os)

**Facts (Pi 0.87.1 docs in the installed package):** agent directory `~/.pi/agent` (`PI_CODING_AGENT_DIR`); `models.json` `providers.<name>` = `{ baseUrl, api: "openai-completions", apiKey, models: [{ id, name, contextWindow, maxTokens, input, reasoning }] }`, a dummy `apiKey` makes the model available; `settings.json` `compaction.reserveTokens` (default 16384) and `compaction.keepRecentTokens` (default 20000), per model under `compaction.modelOverrides["<provider>/<id>"]`; `enableInstallTelemetry` (default true); env `PI_OFFLINE`, `PI_SKIP_VERSION_CHECK`, `PI_TELEMETRY`; user extensions in `<agent-dir>/extensions/`, API `pi.on("tool_call", async (event, ctx) => ...)` returning `{ block: true, reason }`, dialogs `ctx.ui.select` / `ctx.ui.confirm`, `ctx.hasUI` (example `examples/extensions/permission-gate.ts`). Verify each key against the docs before relying on it.

**Files:** `config/pi/extensions/aos-permission-gate.ts` (new), `aos.psm1` (`Get-AosPiDir`, `Get-AosPiOverlay`, `Sync-AosPi`; called from `Install-AosLocal` and `Sync-AosBrain`), `tests/aos.Tests.ps1` (`Describe 'Pi on the local model'`).

**Behaviour:**
- `models.json`: aos owns `providers.aos` and replaces it whole: `baseUrl` = `ollama_url` + `/v1`, `api` `openai-completions`, `apiKey` `ollama`, one model `{ id: <agent_model>, name: "aos-agent (local)", contextWindow: <agent_num_ctx>, maxTokens: 4096, input: ["text"], reasoning: false }`. Other providers and top-level keys are kept.
- `settings.json`: aos sets `enableInstallTelemetry: false` and `compaction.modelOverrides["aos/<agent_model>"] = { reserveTokens: 4096, keepRecentTokens: 4096 }` (replaced whole); everything else kept.
- `extensions/aos-permission-gate.ts`: copied from the repo when different. Before `bash`, `write` and `edit` it asks `ctx.ui.select("<tool>: <command or path>", ["Allow", "Deny"])` and blocks unless "Allow"; with no UI it blocks. Read-only tools pass.
- Skips everything, with an info line, when `pi` is not installed. Backs up each file before its first change; DryRun writes nothing; a second run changes nothing.
- No MCP servers for the local agent in v1: every tool schema costs prompt in a 16K window (decision recorded in Task 9).

- [ ] **Step 1: Failing tests** (Pi dir mocked to `$caseRoot\pi`): adds `providers.aos` and keeps a user provider and a top-level key; replaces `providers.aos` whole when the context changes (no array union: one model entry with the new `contextWindow`); writes the settings keys and keeps other settings; copies the extension and leaves an identical copy untouched; nothing written in DryRun or on a second run; nothing when `pi` is missing.
- [ ] **Step 2:** see them fail. **Step 3:** implement. **Step 4:** `aos test` green. **Step 5:** commit; apply with `aos sync`; check `pi --list-models` (or the documented equivalent) shows `aos/aos-agent`.

---

### Task 6: Paseo on this PC (agentic-os + live)

**Files:** `aos.psm1` (`Sync-AosPaseo`, called from `Install-AosPhone`; `aos status` lines), `tests/aos.Tests.ps1` (`Describe 'Paseo config'`).

- Config through Paseo's own CLI, never by editing its JSON: `paseo daemon config get <key>` then `paseo daemon config set <key> <value>` only when different, for `pluginsEnabled` = `true` and `agents.providers.pi.env` = `{"PI_OFFLINE":"1","PI_SKIP_VERSION_CHECK":"1","PI_TELEMETRY":"0"}` (verify `config set` accepts a JSON object value; if not, set each env key). Tests mock `Invoke-AosCapture` for `paseo daemon config *`: sets only what differs, DryRun sets nothing, missing `paseo` warns.
- [ ] **Step 1-4:** tests, fail, implement, `aos test` green, commit.
- [ ] **Step 5 (live):** start the daemon outside the Claude app so it gets the full user environment (a process created through WMI, as used before for `aos status`, or Windows Terminal): `paseo daemon start`, `paseo daemon status`. If the daemon fails on Node 24 (Paseo pins 22.20; native `node-pty`), stop and record it; the fallback is the Paseo desktop app, which the user installs.
- [ ] **Step 6 (live):** `paseo provider diagnostic claude`, `codex`, `pi`: each must report the binary, its version and at least one model; `pi` must list `aos/aos-agent`.

---

### Task 7: The local-harness gate (live, through Paseo)

- [ ] **Step 1:** a scratch workspace outside OneDrive: `~\.aos\scratch\agent-gate` (git repo with a README and two small source files).
- [ ] **Step 2:** from the PC, through Paseo, one session with Pi on `aos/aos-agent`: (a) `paseo run --provider pi` with a task that needs a `read` tool call; (b) a follow-up with `paseo send`; (c) a steering message while a turn runs; (d) a `bash` request, which must wait for the permission-gate dialog, answered from the PC client; (e) turns until the context passes 8K.
- [ ] **Step 3: Measure** from Pi's session file (`~/.pi/agent/sessions/.../*.jsonl`): `usage.input` of every assistant message (it includes Paseo's appended system prompt and tools). Also `ollama ps` (100% GPU) and tokens per second. If `usage.input` is 0 or missing, fall back to a capture proxy (a local forwarder on 127.0.0.1:11435 that logs each request body and replays it with `max_tokens: 1` to read `usage.prompt_tokens`), pointed at by a temporary second provider.
- [ ] **Step 4: Decide.** Pass: `max(usage.input) <= 12288`, 100% GPU, >= 15 tok/s, the tool call and the permission dialog worked. If Qwen3.5's thinking makes turns too slow, add a Pi `before_provider_request`-style payload hook that sends `reasoning_effort: "none"` (verify the hook name in `docs/extensions.md`) and measure again. If Pi fails, the fallback is OpenCode (install `opencode-ai` after telling the user its real size, ~360 MB; `provider.aos` with `limit: { context: 16384, output: 4096 }`, `permission: { bash: "ask", edit: "ask" }`, no MCP; the same gate). If both fail, stop and report: criterion 1 is then blocked for the local model, not silently reduced. Record the numbers in the ledger and in Task 9's decision.

---

### Task 8: The aos plugin (nar-tools/paseo-plugin, in a worktree)

**Where:** `git -C nar-tools worktree add ~\.aos\worktrees\nar-tools-plugin -b paseo-plugin`; `paseo plugin init <worktree>\paseo-plugin`; `npm install` there (dev dependencies only: the SDK, React and React Native types, TypeScript, Vitest; Paseo supplies the runtime ones). `.gitignore`: `node_modules/`. The OneDrive checkout gets the sources when the branch merges.

**Files:** `paseo-plugin.json` (id `aos`, `requirements.paseo` `>=0.10.0`), `shared/rpc.ts` (four `defineRpc` contracts with strict zod schemas: `callId` `/^[0-9a-f]{32}$/`, `index` integer 0..19, no other fields), `server/commands.ts` (pure argv builders and parsers), `server/handlers.ts` (handlers that take a `run(file, args, env)` function), `index.server.ts` (wires handlers to `execFile` with `{ encoding: "utf8", timeout, env: { ...process.env, PYTHONIOENCODING: "utf-8" } }`), `client/panel.tsx`, `index.client.tsx` (`addWorkspacePanel` "agentic-os"), `server/*.test.ts` (Vitest), `package.json` scripts `test` and `typecheck`.

**Interfaces (`server/commands.ts`):** `aosStatusArgv()` -> `["pwsh", ["-NoLogo", "-NonInteractive", "-Command", "aos status"]]`; `narExePath(home)` -> `<home>\.aos\venvs\nar-tools\Scripts\nar.exe`; `narArgv(exe, "status" | "recent")`; `narFeedbackArgv(exe, { callId, index })` -> `[exe, ["feedback", callId, "--index", String(index)]]`, throwing `Error("invalid feedback")` unless the call id and index are valid; `stripAnsi(text)`.

- [ ] **Step 1: Failing tests:** argv builders (fixed arguments; `--index`, never digit text); invalid feedback (`../../x`, uppercase hex, 31 and 33 characters, index -1, 20, 1.5, a string) throws; the zod schemas reject the same inputs and extra fields; handlers with a mocked `run`: malformed input -> `run` never called; valid feedback -> `run` called once with the exact argv and `PYTHONIOENCODING=utf-8`; a failed or timed-out feedback returns `{ ok: false, reconcile: true }` so the panel re-reads `nar recent` instead of retrying; `stripAnsi`.
- [ ] **Step 2:** `npx vitest run` fails (modules missing). **Step 3:** implement; the panel: status text, calibration per model/task type from `nar status`, recent calls with one button per option; after any feedback reply, refresh the list. Measure `aos status` first and set its timeout to twice that (at least 20 s).
- [ ] **Step 4:** `npx vitest run` and `npm run typecheck` pass. Add a CI job to nar-tools (`windows-latest`: `npm ci`, `vitest run`, `tsc --noEmit` in `paseo-plugin`).
- [ ] **Step 5:** `paseo plugin install <worktree>\paseo-plugin`; `paseo plugin logs aos` clean; commit.
- The spec's gateway server-list panel is deferred to the step 3 (tool gateway) plan: it needs the gateway first.

---

### Task 9: Docs and decisions (agentic-os)

- [ ] README: the phone section gets Paseo (pair once, what runs where, the permission prompts, how to stop the daemon); the layer table already lists `phone`.
- [ ] `docs/decisions.md` (new entry on top): Paseo adopted for the phone; Pi (or the fallback) with the gate's numbers; no MCP for the local agent in v1; real install sizes; Qwen3.5 16K vs 32K measurement (supersedes the 2026-09-28 line about 32K, which was measured on MiniCPM5-2B).
- [ ] `docs/routing.md`: when to use the local agent from the phone.

### Task 10: Phone acceptance (live, the user present)

- [ ] The user installs Paseo from the Play Store; on the PC `paseo daemon pair --relay`; the user scans the QR (keep it private). Offer `paseo daemon set-password` (the user types it).
- [ ] With the phone's Wi-Fi off (mobile data, so the relay path is tested): start one session each with Claude Code (mode "Always Ask"), Codex (on-request) and Pi, in the scratch workspace; send a follow-up to each while it works (steering); ask each for a harmless file write and approve it on the phone, checking that the write waited for the approval.
- [ ] Plugin: note one call id from `nar recent`, tap its right option on the phone, then check `aos nar status` shows one more labelled call and `nar recent` no longer lists it.
- [ ] Offer, do not do: start the daemon at login (Startup-folder shortcut or scheduled task): the user decides.

---

## Review Focus (round 2)

1. Task 1: provenance from `ollama show --modelfile` instead of bookkeeping; the retry path through `aos local adopt` and `aos sync`.
2. Task 5: the Pi facts, the subtrees aos owns in Pi's files, and whether the permission gate really reaches the phone through Paseo (`providers/pi/agent.ts` maps `select`/`confirm` to permissions).
3. Task 6: starting the daemon outside the Claude app; Node 24; `paseo daemon config set` for nested keys.
4. Task 7: whether Pi's recorded `usage.input` is a faithful prompt size for Ollama's OpenAI-compatible endpoint, and the gate's pass rule.
5. Task 8: the RPC boundary (Paseo parses the contract's input schema before the handler, `plugin-process.ts:482-486`) and the worktree approach.
