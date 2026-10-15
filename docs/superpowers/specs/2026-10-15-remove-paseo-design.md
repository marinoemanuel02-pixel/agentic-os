# Remove Paseo: same orchestration, no phone intermediary

Date: 2026-10-15. Status: draft for user review. Codex review: see the end of this file.
Supersedes the Paseo parts of `2026-09-30-phone-orchestration-design.md` and the Paseo decision of
2026-09-29 in `docs/decisions.md`.

## User intent

The operator has never used Paseo from the phone and defaults to the Claude desktop app every time. They
want Paseo out of the architecture, with the cross-model orchestration (Claude, Codex, local model) kept
working without that intermediary, provided no major capability is lost. Decisions in chat on 2026-10-15:
the local model does not need to be reachable from the phone; option A (full removal); staged; Codex
reviews the plan before anything is changed.

Success: nothing on this PC runs, installs, schedules, links or tests Paseo; every capability the operator
uses still works; each stage can be checked and the first two can be undone in minutes.

## Evidence (measured 2026-10-15)

- Paseo's own state: `~/.paseo` is 1.1 GB, 993 MB of it `models/local-speech` (kokoro-en-v0_19 353 MB, which
  the operator rejected as "terrible", and a parakeet dictation model 641 MB; no consumer of the parakeet
  model found in the repo or skills). 14 agent records, all from 2026-09-29/30 setup and smoke tests; the
  newest activity is a Coordinator conversation in agentic-os on 2026-10-08. The files cannot say whether that
  was the operator or a test. The daemon was down most of 09-30..10-03 (recorded in the watch-and-steer plan).
- The orchestration the operator relies on is Paseo-free: claims and guard hook, ledger, `aos delegate`,
  `aos capacity`, the notes hook, the `handoff` and `second-opinion` skills use plain files, `claude -p` and
  `codex exec`. `aos watch` is not built; Paseo appears in its plan only as one table row and task T6.
- First-party phone routes already documented in the README: Claude app > Code (Remote Control),
  `aos remote`, Codex app "Control this PC", cloud sessions. Not tested by this work; the soak checks one.

### Capability ledger

| Capability | After removal | Lost? |
|---|---|---|
| Claude / Codex from the phone | first-party apps (README "From your phone") | no |
| One thread that fails over between providers on a quota error | `aos capacity`, `handoff` skill, `aos delegate`; on the phone, open the other app | the single-thread convenience only (accepted) |
| Local model (Pi + Ollama) from the phone | none | yes (accepted: the operator does not need it) |
| aos phone panel: status, nar feedback, Inbox box | `aos status`; the Inbox is a folder | minor (accepted) |
| Pi, Ollama, nar, `aos remote`, delegate, claims, Places | unchanged | no |

## Hidden dependencies found (these shape the stage order)

1. **The live `nar` is an editable install of the working tree on a Paseo branch.**
   `~/.aos/venvs/nar-tools` is an editable install of `1-Projects\nar-tools` (direct_url.json), currently on
   branch `phone-coordinator-live`, 27 commits ahead of `main` (0 behind). Claude and Codex both launch
   `~/.aos/venvs/nar-tools/Scripts/nar-mcp.exe`. Only 2 of the 27 commits touch code outside `paseo-plugin/`
   (`90f0614`, `f0895d1`: the embedding backend and `nar classify`), and no commit mixes the two. Switching or
   deleting that branch changes live nar at once.
2. **Video voice requires sherpa-onnx from inside the Paseo CLI package.**
   `templates/video/tools/make-voice.cjs` and the `make-voice.cjs` of 9 film projects (agi-asi-alignment,
   agi-race-2, alignment, alignment-3, alignment-now, alignment-now-it, cant-escape-ai, cant-escape-ai-2,
   where-you-end; plus `cant-escape-ai/tools/audition.cjs`) require
   `~/.npm-global/node_modules/@getpaseo/cli/node_modules/sherpa-onnx-node`. Uninstalling `@getpaseo/cli`
   breaks voice generation. The two packages are 85 KB + 23 MB (`sherpa-onnx-node`, `sherpa-onnx-win-x64`).
   The Kokoro v1.0 model the pipeline uses is already outside Paseo (`~/.aos/models`).
3. **The six `paseo*` skills exist in three places**, all copies with the same names: real directories in
   `~/.claude/skills` and `~/.codex/skills` (2026-10-05 16:40) and untracked directories in
   `agents-home/skills` (= `~/.agents/skills`, 16:47). Their writer is not established (the daemon log does
   not mention it). A full `aos sync` has been held back since 2026-10-12 because it would replace the first
   two with links to the untracked repo copies. They add six entries to every session's skill list.
4. **One scheduled task** `agentic-os Paseo daemon` (logon, repeats every 5 minutes). Nothing else in
   `~/.codex/automations`, `~/.claude/scheduled-tasks` or other tasks mentions Paseo. The task helpers
   (`Get-AosLogonTaskState`, `Register-AosLogonTask`, `Start-AosLogonTask`, `ConvertTo-AosLogonTaskState`) have no
   other caller in `aos.psm1`.
5. **Old worktree copies.** `agentic-os/.claude/worktrees/objective-bun-84f1c5` (branch
   `claude/objective-bun-84f1c5`) and other checked-out branches still contain Paseo code. The tombstone test
   (below) must read tracked files (`git ls-files`), not the file system, or it would see that worktree.

## Approach: four stages

Each stage ends with checks; the next stage starts only on the operator's word. Stages 0 and 1 write no
repo code.

### Stage 0 - cut the hidden dependencies (additive, nothing removed)

- **0a nar.** In a new worktree of `nar-tools` cut from `main` (not the live checkout), cherry-pick `90f0614`
  and `f0895d1`; run the nar-tools Python tests; fast-forward `main`. Then, between sessions, switch the live
  checkout from `phone-coordinator-live` to `main`. Check: `nar classify --backend embed` on three short items
  (local Ollama, no cost), `nar_status` from an MCP session, and `git status` clean. Rollback: switch the
  checkout back to the branch.
- **0b voice.** Copy `sherpa-onnx-node` and `sherpa-onnx-win-x64` (23 MB, no download) from the Paseo package
  to `~/.aos/deps/sherpa-onnx/node_modules/`. Change `templates/video/tools/make-voice.cjs` to resolve, in order,
  `$env:AOS_SHERPA_DIR`, `~/.aos/deps/sherpa-onnx/node_modules`, then the old Paseo path (fallback removed in
  stage 3). Test it by generating one short line with the new path and comparing the WAV to one made through the
  old path (same samples). Existing films: see Decisions.

### Stage 1 - stop it (machine only, reversible)

- Read `aos who`; claim nothing in the repo. `paseo daemon stop`; unregister the `agentic-os Paseo daemon` task.
- Move the 18 `paseo*` skill directories (3 places x 6) into
  `~/.aos-backups/remove-paseo-<stamp>/` (a move, not a delete).
- Soak rules: do not run `aos install phone`, `aos install all` or `bootstrap.ps1` (the code still re-creates the
  task). Plain `aos sync` is allowed; its Places step will warn that Paseo is unreachable.
- Soak checks: no process on port 6767; the skills are still absent after one new Claude session, one new
  Codex session and the next sign-in (if they return, find the writer before stage 2); `aos test` green; the
  operator opens Claude app > Code on the phone once and sees a PC session (the premise of removal).
- Rollback: `aos install phone` re-creates the task and daemon; skills come back from the backup.

### Stage 2 - remove from the repo (branch `remove-paseo`, cut from the current tip)

Order inside the stage: tests first (see Tests), then code, then docs.

`aos.psm1`: delete `Install-AosPhone`, `Get-AosPaseoAutostartCommand`, `Sync-AosPaseoAutostart`,
`Test-AosPaseoDaemonRunning`, `Start-AosPaseoDaemon`, the four logon-task helpers, `Get-AosPaseoPluginDir`,
`Sync-AosPaseoPlugin`, `Repair-AosPaseoPlugin`, `Sync-AosPaseo`, `Get-AosPaseoProjectPaths`,
`Register-AosPaseoPlace`; the registration loop in `Sync-AosPlaces` and the "in Paseo" suffix in `aos place ls`;
`'phone'` from `$script:Layers` and the install dispatcher (so `aos install phone` is an unknown layer, the
existing behaviour); reword the Paseo comments. About 250 lines. Places itself stays.
Other files: `packages.json` (the `@getpaseo/cli` row; reword the Pi row), `bootstrap.ps1` usage text,
`refs/repos.json` (the getpaseo/paseo row), `config/pi/extensions/aos-permission-gate.ts` (comment only),
README (layer table and the three phone rows), `docs/routing.md` (2 rows), `tool-catalog` (6 skill rows,
the Pi row and the closing sentence), `media-tools` voice note (path now `~/.aos/deps/sherpa-onnx`), the
untracked `agents-home/skills/paseo*` directories, and a new dated entry on top of `docs/decisions.md`.
Historical plans and specs stay as written; four get a one-line "Superseded by 2026-10-15-remove-paseo" status
(phone-orchestration-design, paseo-and-app, phone-coordination-v1, and watch-and-steer, whose T6 and Paseo
row are cancelled). The research note `2026-09-29-paseo.md` is left as dated history.
`nar-tools` (main): remove `paseo-plugin/` in one commit; tag the old tip `archive/paseo-plugin` first. Branches
and the two worktrees under `~/.aos/worktrees` are kept; no branch is deleted.
Pi stays: its extensions are Pi's own, unrelated to Paseo's transport.

### Stage 3 - delete what is left (last; operator approves each item with its size)

`npm uninstall -g @getpaseo/cli` (538 MB); remove the voice fallback to the Paseo path; delete
`~/.aos/refs/watch/getpaseo` (103 MB) and `~/.aos/deps/paseo-plugin-0.10.1`; move `~/.paseo` (1.1 GB) to the
Recycle Bin, after copying `agents/` and `config.json` to the backup folder (config is checked for a password
hash first and not copied if present; `daemon-keypair.json` is never copied). Removing the keypair invalidates
the phone pairing. The operator removes the Paseo app from the phone and empties the Recycle Bin. Update the four
memory notes that mention Paseo (installs-need-consent, nar-embed-backend, video-voice-kokoro-v1, MEMORY.md),
resolve the 10-12 ledger note, then run the first full `aos sync` since 10-12: dry-run first, read the preview,
apply, and run it twice (the second changes nothing).

## Tests (written first, each seen failing before stage 2 code changes)

1. Tombstone: no file returned by `git ls-files`, other than `docs/decisions.md`, `docs/superpowers/**` and the
   test file itself, contains "paseo" (case-insensitive).
2. `aos install phone` is rejected as an unknown layer; `$script:Layers` has no `phone`.
3. `Sync-AosPlaces` and `aos place ls` never call `paseo` even when a `paseo` command exists (mock
   `Invoke-AosCapture`, assert no call matches).
4. Deleted with the behaviour they covered, listed so the review can check the list: Describe blocks `Phone layer`,
   `Paseo config`, `Paseo aos plugin`, `Paseo daemon at logon`, `Paseo daemon startup`,
   `Paseo daemon logon command`, and the Paseo cases inside `Places registration`. Every other test stays as is.
5. Voice resolver (stage 0b): a node test with a temp tree proves the order env, `~/.aos/deps`, fallback.
Split authorship per the global contract: Codex writes tests 1-3 if its capacity allows (see Decisions), else
Claude writes them and Codex reviews them.

## Acceptance (checkable)

- Stage 0: `main` of nar-tools has the embed commits; live nar passes the checks above from `main`; the new voice
  path renders a line identical to the old path.
- Stage 1: no `paseo` process or task; no port 6767 listener; the skills stay absent across the three events.
- Stage 2: `aos test` green under Windows PowerShell 5.1 and PowerShell 7; `aos place ls` fine; `aos delegate`
  preflight, `aos remote` and `pi --version` still work; second `aos sync` changes nothing.
- Stage 3: `paseo` command absent; `~/.paseo`, the clone and the deps cache gone; about 1.8 GB freed.

## Risks and unknowns

- The writer of the skill copies is unknown; stage 1 verifies instead of assuming.
- The first full `aos sync` since 10-12 may surface other drift; hence preview-first.
- Concurrent sessions and other branches: `aos who` showed no live claim at 2026-10-15; the guard hook claims the
  checkout on the first edit. Branches that still carry the Paseo code will conflict with the deletion only where
  they edit the same blocks.
- The film projects' own `make-voice.cjs` copies break after stage 3 unless repointed (Decisions).
- Codex weekly capacity was 98% used in its last log (resets 2026-10-18); the review below may fail on a limit.

## Decisions for the operator

1. **Film voice tools.** Recommended: repoint the template and `cant-escape-ai-2` (paused, likely to resume);
   leave the other 8 delivered projects untouched and record the one-line fix in `decisions.md`. Alternative: a
   junction at the old path (keeps a dead folder named after Paseo).
2. **Soak length.** Recommended: at least one sign-in cycle and one use of the phone check, then stage 2 on your
   word.
3. **Who writes tests 1-3.** Recommended: Codex when it has window left (a small write); otherwise Claude.
4. **nar-tools branches.** Recommended: keep all, tag the old tip, delete none.

## Review focus for Codex

1. Anything Paseo-dependent the inventory missed (other repos, hooks, MCP entries, Pi config, scheduled jobs).
2. Stage order: can any stage leave live nar, video voice or `aos sync` broken between steps?
3. The deletion list for tests: is any deleted test covering behaviour that stays?
4. Stage 1 and 3 commands that write to `~/.claude`, `~/.codex`, the npm global prefix or the PATH.
5. Whether the tombstone test and the stage-0 checks can actually fail.
