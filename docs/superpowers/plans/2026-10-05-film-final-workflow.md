# Film shipping review and orchestration improvements

> Execution: Codex directs and implements; Claude Code provides bounded independent reviews through `aos delegate`. The user requested autonomous completion and director judgment on shipping readiness.

**Goal:** Deliver the reviewed film with traceable shipping evidence, a factual account of tools/communication/capacity, and tested improvements to the existing harness.

**Architecture:** Preserve the sealed v8 baseline until an actual defect warrants picture or narration changes. Keep film evaluation, harness changes and independent reviews separate. Improve the existing capacity command and video QA template rather than introducing another coordinator.

**Tech stack:** Existing PowerShell 5.1/7, Pester, Node, Remotion, ffmpeg, ImageMagick, local Whisper and native vendor tools; no installs, model downloads, credential extraction or reset credits.

## Constraints and shipping criteria

- Read project rules at each film stage. One writer per checkout, commits on branches, heavyweight review artifacts outside OneDrive.
- Film: all 42 shots reviewed at middle/end frames extracted from the exact final MP4, full-size checks of suspicious details, all factual narration/screen labels checked against claims/currency, sealed inputs match, QA green, no white frames, mix transcribed. Separate Claude verdict and director responses.
- If fixes are required: numbered cause-based fixes with 100% crops and before/after evidence; export-day source proofs with URL/date/SHA256/anchor; build v9 and QA on the same Rome day, then inspect every new motion hit. No edits to hashed inputs during build/QA.
- If unchanged v8 meets the rubric: retain its original export date, tag and media bytes; clearly label a director shipping review, never fabricate user approval or a new export.
- Perceptual listening and audience response cannot be established by a frame sheet or Whisper. Report their status precisely; no claim of literal perfection.
- Harness: new regression tests fail first; `aos test` green in both shells; independent Claude review before acceptance. Preserve unrelated untracked work.
- Capacity: percentage, window, reset, observation time and source travel together. A reset that has passed is a request to refresh, never evidence of a fresh 100% window. Native-provider unavailability remains unknown. Use the visible usage card when the native reader cannot report Claude.

## Tasks

### 1. Independent plan critique and immutable baseline evaluation

- [x] Commit this plan; obtain Claude's bounded read-only critique before implementation.
- [x] Baseline `aos test`; run film claims/screen-text/joins/check-plan/currency --claims --export and manifest verification.
- [x] Extract final-v8 1080p middle/end frames and comparison sheets from exact media; do not reuse earlier sheets without verifying their byte identity.
- [x] Director reviews all shots; Claude reviews the final sheets independently and reads narration blind against the factual ledgers. Save receipts, limitations and separate responses.
- [x] Decide whether actual release blockers exist and document each with source/crop evidence.

### 2. Minimal film fixes only if task 1 finds blockers

- [x] Diagnose each defect in code/source before changing it. Recheck changed narration/labels against currency and claims.
- [x] Produce before/after full-size stills, then fresh export-day source proofs. Build v9 and QA on the same local day.
- [x] Inspect new motion hits, scan all decoded frames for white frames, transcribe the exact mix using an installed local model.
- [x] Independent Claude final-frame review and director review with settled end frames; repeat only for changed or unresolved issues.

### 3. Existing capacity reporting: preserve uncertainty and both windows

Files: `aos.psm1`, `tests/aos.Tests.ps1`, `README.md`, `docs/decisions.md`.

- [x] Tests first for stale Codex log readings, all reset times passed, reported reset visibility, malformed windows and typed session/weekly observations.
- [x] Add optional paired `--weekly` / `--weekly-resets` to `aos capacity set`, retaining legacy callers; store normalized windows on the existing capacity event. Add `aos capacity --json` with source/observed/reset/windows/state for operation receipts.
- [x] Select the tightest fresh, unexpired observed window; show past windows as reset and stale data as stale. Keep an unexpired weekly limit visible after the session reset without inventing fresh session capacity.
- [x] Print reset and observation time for reported readings as well as log readings, explicitly mark unknown resets. Existing malformed advice must not break delegation.
- [x] Obtain red-first and green logs, full dual-shell aos tests and a blind Claude review. No changes to vendor credentials, login, profiles or paid usage settings.

### 4. Video QA: transfer a demonstrated gate gap

Files: `templates/video/tools/qa.sh`, matching fixtures in `tests/aos.Tests.ps1` / video checker tests as the existing suite dictates.

- [x] Inspect the current template before changing it. If a pacing report failure can still finish QA green, write a regression that executes this failure path before the fix; otherwise record already fixed.
- [x] Require pacing report failure to fail QA, and preserve existing successful behavior; run aos test and Claude review. Do not migrate unrelated film pose files merely for cleanup.

### 5. Close the evidence and delivery loop

- [x] Assemble sanitized operation records: tools/versions, exact commands and exit results, stage timings, notes, delegation receipts, capacity observations with resets, UI fallback result/failures, builds/cache outcomes, reviews/responses and source receipts. No secrets or unrelated chats/logs.
- [x] Write the closing retro and an evidence-linked workflow report. Distinguish measured outcomes, retained unknowns, already implemented fixes and deferred proposals. Include the avoidable clarification loop and failed native Claude capacity lookup.
- [x] Commit/push harness improvements on `codex/film-final-workflow`; no merge into the user's active harness branch or profile sync without review.
- [x] Package to a new Inbox delivery: README, film/captions/metadata/480p preview, exact SHA256 receipt, separate review records, workflow report, sanitized operation data and tests/review receipts. For a changed film tag/push film-v9; for unchanged v8 retain film-v8 and push review/retro metadata on a branch.
- [x] Independently verify every packaged hash/size, matching final seal, and complete the director's shipping decision.

## Review focus

1. Reset elapsed while a cached/logged observation is unchanged: do not call it a fresh full quota.
2. Weekly exhaustion with a healthy session: weekly must still bind; an expired session must not erase the weekly constraint.
3. Future/malformed observations and missing reset timestamps: keep unknown/stale distinct from available.
4. Review sheets from an earlier v8 build: all final sheets must be extracted from the delivered MP4.
5. Failed tools/reviewers: record failure and retry boundedly or retain the unknown; never convert failure to a clean verdict.


Final execution evidence is in `2026-10-05-film-final-verification.md`. Delivery/push checkboxes are closed by the film delivery receipt and independent destination verification at2026-10-05T20:40:35.490150Z:192 files, all hashes/sizes and sealed media/QA bindings passed. The shared template pacing guard was already correct; only the film copy required a repair.
