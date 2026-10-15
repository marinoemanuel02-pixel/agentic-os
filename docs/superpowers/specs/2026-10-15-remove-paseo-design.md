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
   (`Get-AosLogonTaskState`, `Register-AosLogonTask`, `Start-AosLogonTask`, `ConvertTo-AosLogonTaskState`) are
   called only by the Paseo autostart and start functions and by each other (checked by Codex), so they go with
   them, together with their test block `Logon task state`.
5. **Old worktree copies.** `agentic-os/.claude/worktrees/objective-bun-84f1c5` (branch
   `claude/objective-bun-84f1c5`) and other checked-out branches still contain Paseo code. The tombstone test
   (below) must read tracked files (`git grep`), not the file system, or it would see that worktree.

## Approach: four stages

Each stage ends with checks; the next stage starts only on the operator's word. Stages 0 and 1 delete nothing
from the repo: stage 0 only moves the nar work to `main` and changes one `require` line in each voice tool.

### Stage 0 - cut the hidden dependencies (additive, nothing removed)

- **0a nar.** In a new worktree of `nar-tools` cut from `main` (not the live checkout), cherry-pick `90f0614`
  and `f0895d1`; run the nar-tools Python tests; fast-forward `main`. Then, between sessions, switch the live
  checkout from `phone-coordinator-live` to `main`. Check: `nar classify --backend embed` on three short items
  (local Ollama, no cost), `nar_status` from an MCP session, and `git status` clean. Rollback: switch the
  checkout back to the branch.
- **0b voice.** Copy `sherpa-onnx-node` and `sherpa-onnx-win-x64` (23 MB, no download) from the Paseo package
  to `~/.aos/deps/sherpa-onnx/node_modules/`. First render one short line through the old path and keep the
  WAV. Then change the one `require` line in `templates/video/tools/make-voice.cjs` and in the 9 film
  projects' `tools/make-voice.cjs` plus `cant-escape-ai/tools/audition.cjs` to load from
  `$AOS_SHERPA_DIR` if set, else `~/.aos/deps/sherpa-onnx/node_modules` (no fallback to the Paseo path, so
  nothing needs touching again in stage 3). One commit per film repo; skip and report any repo whose working tree
  is dirty or claimed (`aos who`). Check: the same line rendered through the new path has the same samples as the
  kept WAV, in the template and in at least `cant-escape-ai-2`; a scan finds zero `@getpaseo/cli` in
  `1-Projects\videos` and `templates`.

### Stage 1 - stop it (machine only, reversible)

- Read `aos who`; claim nothing in the repo. In this order: unregister the `agentic-os Paseo daemon` task
  first (it repeats every 5 minutes and would restart the daemon), then `paseo daemon stop`, then verify.
- Move the 18 `paseo*` skill directories (3 places x 6) into
  `~/.aos-backups/remove-paseo-<stamp>/<place>/` (a move, not a delete), with a manifest of the 18 original paths.
- Soak rules: do not run `aos install phone`, `aos install all` or `bootstrap.ps1` (the code still re-creates the
  task). Plain `aos sync` is allowed; its Places step will warn that Paseo is unreachable.
- Soak checks: no `paseo` process and no listener on port 6767, checked right after the stop and again at least
  6 minutes later (past one task repeat); the skills are still absent after one new Claude session, one new
  Codex session and the next sign-in (if they return, find the writer before stage 2); `aos test` green; the
  operator opens Claude app > Code on the phone once and sees a PC session (the premise of removal).
- Rollback, explicit: move each of the 18 directories back to its manifest path, run `aos install phone`
  (re-creates the task and starts the daemon), then check the 18 paths exist as real directories and that no
  `aos sync` replaced them with links.

### Stage 2 - remove from the repo (branch `remove-paseo`, cut from the current tip)

Order inside the stage: tests first (see Tests), then code, then docs.

`aos.psm1`: delete `Install-AosPhone`, `Get-AosPaseoAutostartCommand`, `Sync-AosPaseoAutostart`,
`Test-AosPaseoDaemonRunning`, `Start-AosPaseoDaemon`, the four logon-task helpers, `Get-AosPaseoPluginDir`,
`Sync-AosPaseoPlugin`, `Repair-AosPaseoPlugin`, `Sync-AosPaseo`, `Get-AosPaseoProjectPaths`,
`Register-AosPaseoPlace`; the registration loop in `Sync-AosPlaces` and the Paseo lookup and "in Paseo" suffix in
`Show-AosPlacesStatus` (the Paseo part of `aos status`; `aos place ls` / `Show-AosPlaces` has none);
`'phone'` from `$script:Layers` and the install dispatcher (so `aos install phone` is an unknown layer, the
existing behaviour); reword the Paseo comments. About 250 lines. Places itself stays.
Other files: `packages.json` (the `@getpaseo/cli` row; reword the Pi row), `bootstrap.ps1` usage text,
`refs/repos.json` (the getpaseo/paseo row), `config/pi/extensions/aos-permission-gate.ts` (comment only),
README (layer table, the three phone rows, and the Paseo prose at about lines 98-108 and 119-121),
`docs/routing.md` (2 rows), `tool-catalog` (6 skill rows, the Pi row and the closing sentence), `media-tools`
voice note (path now `~/.aos/deps/sherpa-onnx`; its `~/.paseo/models` remark at about line 72 reworded), the
untracked `agents-home/skills/paseo*` directories, and a new dated entry on top of `docs/decisions.md`.
Historical plans and specs stay as written; four get a one-line "Superseded by 2026-10-15-remove-paseo" status
(phone-orchestration-design, paseo-and-app, phone-coordination-v1, and watch-and-steer, whose T6 and Paseo
row are cancelled). The research note `2026-09-29-paseo.md` is left as dated history.
`nar-tools` (main): remove `paseo-plugin/` in one commit; tag the old tip `archive/paseo-plugin` first. Branches
and the two worktrees under `~/.aos/worktrees` are kept; no branch is deleted.
Pi stays: its extensions are Pi's own, unrelated to Paseo's transport.

### Stage 3 - delete what is left (last; operator approves each item with its size)

Gate: the voice scan from stage 0b still reports zero `@getpaseo/cli` in `1-Projects\videos` and `templates`.
`npm uninstall -g @getpaseo/cli --prefix "<Get-AosNpmPrefix>"` (538 MB; the explicit prefix mirrors how
`aos install` installed it, so an `NPM_CONFIG_PREFIX` override cannot leave the live shims behind), then check
that `paseo`, `paseo.cmd` and `paseo.ps1` are gone from that prefix; delete
`~/.aos/refs/watch/getpaseo` (103 MB) and `~/.aos/deps/paseo-plugin-0.10.1`; move `~/.paseo` (1.1 GB) to the
Recycle Bin, after copying `agents/` and `config.json` to the backup folder (config is checked for a password
hash first and not copied if present; `daemon-keypair.json` is never copied). Removing the keypair invalidates
the phone pairing. The operator removes the Paseo app from the phone and empties the Recycle Bin. Update the four
memory notes that mention Paseo (installs-need-consent, nar-embed-backend, video-voice-kokoro-v1, MEMORY.md),
resolve the 10-12 ledger note, then run the first full `aos sync` since 10-12: dry-run first, read the preview,
apply, and run it twice (the second changes nothing).

## Tests (written first, each seen failing before stage 2 code changes)

1. Tombstone: `git grep -I -i -l paseo` (tracked files, working-tree contents, so a deleted-but-not-yet-staged file
   cannot be listed) finds nothing outside `docs/decisions.md`, `docs/superpowers/**` and the test file itself.
   It proves the tracked tree only; the machine (untracked skills, worktrees, `~/.claude`, `~/.codex`) is
   covered by the stage 1 and 3 checks.
2. `aos install phone` is rejected as an unknown layer; `$script:Layers` has no `phone`.
3. `Sync-AosPlaces` and `Show-AosPlacesStatus` (the `aos status` part) never call `paseo` even when a `paseo`
   command exists (mock `Invoke-AosCapture` and `Test-AosCommand`; assert no call matches `paseo`).
4. Test disposition, rule: a case is deleted only if its assertion is about Paseo itself (a daemon, task, plugin,
   project listing or registration); a case about local persistence, preview-without-writes or brain-sync
   pass-through is kept and loses only its Paseo mocks.
   - Delete whole Describe blocks: `Phone layer`, `Paseo config`, `Paseo aos plugin`, `Paseo daemon at logon`,
     `Paseo daemon startup`, `Paseo daemon logon command`, `Logon task state`.
   - `Places registration`: delete 'registers existing places and skips normalized known paths', 'refuses
     malformed listings and reports failed registration', 'skips external calls without Paseo and skips absent
     configuration', 'previews an existing unregistered folder without registering or writing it'; keep and adjust
     'persists local discovery when the daemon cannot list projects' (rename: no daemon) and 'runs Places sync
     from brain sync and passes preview through'; 'never registers missing folders or preview changes' is
     adjusted or folded into 'Places persistence' (its remaining assertion is about local writes).
   - `Places commands`: 'shows each place and whether Paseo knows it in aos status' is rewritten, not deleted: it
     keeps the missing-folder warning assertion and drops the Paseo mock and the "in Paseo" expectation.
   - Every other test stays as is. Codex checks this list against the test file (done once; see the review).
5. Voice resolver (stage 0b): a node test with a temp tree proves the order: `AOS_SHERPA_DIR`, then
   `~/.aos/deps/sherpa-onnx/node_modules`, then a clear error naming both paths.
Split authorship per the global contract: Codex writes tests 1-3 if its capacity allows (see Decisions), else
Claude writes them and Codex reviews them.

## Acceptance (checkable)

- Stage 0: `main` of nar-tools has the embed commits; live nar passes the checks above from `main`; the new voice
  path renders a line identical to the old path in the template and in each repointed film repo; zero
  `@getpaseo/cli` under `1-Projects\videos` and `templates`.
- Stage 1: no `paseo` process or task; no port 6767 listener, now and 6+ minutes later; the skills stay absent
  across the three events; the rollback procedure is written down with the 18-path manifest before the move.
- Stage 2: `aos test` green under Windows PowerShell 5.1 and PowerShell 7; `aos place ls` fine; `aos delegate`
  preflight, `aos remote` and `pi --version` still work; second `aos sync` changes nothing.
- Stage 3: `paseo` command absent; `~/.paseo`, the clone and the deps cache gone; about 1.8 GB freed.

## Risks and unknowns

- The writer of the skill copies is unknown; stage 1 verifies instead of assuming.
- The first full `aos sync` since 10-12 may surface other drift; hence preview-first.
- Concurrent sessions and other branches: `aos who` showed no live claim at 2026-10-15; the guard hook claims the
  checkout on the first edit. Branches that still carry the Paseo code will conflict with the deletion only where
  they edit the same blocks.
- The film projects' own `make-voice.cjs` copies would break after stage 3; stage 0b repoints all of them and
  stage 3 is gated on a clean scan.
- Codex weekly capacity was 98% used in its last log (resets 2026-10-18). The spec review ran anyway and
  completed (see the end); the code-diff review of stage 2 and any test writing depend on the window left then.

## Decisions for the operator

1. **Film voice tools.** Recommended (changed after Codex's blocker): repoint all 10 files in stage 0b, one
   commit per film repo; all nine are git repos and none has a seal marker, and the edit is a tools script, not
   a render output. Alternative: leave the delivered films alone and keep a junction at the old Paseo path, which
   leaves a dead folder named after Paseo and makes stage 3 incomplete.
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

## Codex review (2026-10-15)

Run: `codex exec --profile review` (model passed per call), read-only, 74,894 tokens, exit 0, no usage-limit error. Full text:
`2026-10-15-remove-paseo-codex-critique.md`. Result: 1 blocker, 5 important, 1 minor, and claim (b) wrong as worded.
Claims (a) 2 of 27 nar commits outside the plugin, none mixed, and (c) 9 films + template + `audition.cjs` hard-code
the Paseo path were confirmed. Hooks, MCP entries and Pi config: nothing found beyond the Pi comment.

| # | Codex finding | Disposition |
|---|---|---|
| 1 | Blocker: eight films keep a dead voice path after stage 3 | Accepted. Stage 0b repoints all 10 files; stage 3 gated on a clean scan; Decision 1 changed |
| 2 | Important: `Logon task state` block and a status test missing from the deletion list; keep persistence and brain-sync cases | Accepted. Test disposition rewritten (Tests 4) |
| 3 | Important: stopping before unregistering leaves a 5-minute restart window | Accepted. Stage 1 order reversed; recheck after 6+ minutes |
| 4 | Important: `aos install phone` does not restore the skills | Accepted. Explicit rollback with an 18-path manifest |
| 5 | Important: uninstall without the install prefix can leave the shims | Accepted. `--prefix` mirrored from install; shim check |
| 6 | Important: the "in Paseo" lookup is in `aos status`, not `aos place ls` | Accepted. Stage 2 and Tests 3 corrected |
| 7 | Minor: README prose, media-tools line, tombstone limits, `git ls-files` staleness | Accepted. Edits listed; tombstone uses `git grep`; scope stated |
| b | Claim (b) wrong as worded | Accepted. Wording fixed; the helpers still go with the Paseo functions |

Not yet reviewed by Codex: the revised text above, and the stage 2 code diff (reviewed when it exists).

## Amendments at planning time (2026-10-15, pending the operator's confirmation)

Found while writing `docs/superpowers/plans/2026-10-15-remove-paseo.md`; each changes the approved text above only
as stated.

1. **Decision 1 is refined by a seal.** `tools/checks/input-manifest.mjs` hashes `tools/make-voice.cjs` into a film's
   `exports/input-manifest.json`, and `qa.sh` verifies the sealed manifest against the current file. Three films are
   sealed (agi-asi-alignment, alignment-now, alignment-now-it): repointing their voice tool would break their seal.
   Three more have no seal but uncommitted changes (alignment, alignment-3, cant-escape-ai). Stage 0b therefore
   repoints the template and every film that is unsealed and clean (today: agi-race-2, cant-escape-ai-2,
   where-you-end), and skips and lists the others. For the skipped films the operator chooses at the stage 0
   checkpoint: leave them (the old path dies; re-voicing a sealed film needs a new seal anyway) or keep a junction
   at the old Paseo path pointing at `~/.aos/deps/sherpa-onnx/node_modules`. Stage 3's gate becomes that choice
   instead of "zero occurrences".
2. The voice loader's error names the path in use (the override or the default), not both paths: it is a two-line
   edit that fits nine films' files without a helper module.
3. The `archive/paseo-plugin` tag is created in stage 0a, before the live nar checkout moves off its branch.
4. Stage 3 moves `~/.paseo`, the reference clone and the deps cache into a holding folder under the backup
   directory instead of the Recycle Bin (a 1.1 GB item can exceed the bin's capacity and be deleted outright); the
   operator deletes the holding folder. An agent never permanently deletes.
5. Added to stage 2: the `'phone'` entry in `bootstrap.ps1`'s `ValidateSet`, the `Install-AosPhone` entry in the
   'Media layer' test's mock list, a tombstone check that no tracked file documents `install phone`, and an opt-in
   `AOS_TEST_FILTER` variable in `tests/Run-Tests.ps1` so one test block can be seen failing and passing.
6. Stage 3 removes the Paseo package by moving it and its three shims into the holding folder instead of running
   `npm uninstall -g`: the agent deletes nothing permanently, and the undo is a move back rather than a 538 MB
   download.
7. Of the four memory notes the spec lists, two (an install-size measurement; where the rejected v0.19 voice came
   from) name Paseo only as dated history that stays true; they are left unchanged, and a new `paseo-removed` note
   records the removal.
