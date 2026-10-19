# Implement the selected stack additions

Approved scope: local existing-footage editing, a read-only Claude status mod, and checked
continuation after a vendor quota failure. Reuse existing tools and subscriptions. No new service,
model download, paid API, automatic permission override, or automatic replay of writes.

## Ownership and integration

- Lead: status mod, continuation checks, shared instructions, Pester integration and final checks.
- One native worker: only new `tools/footage/` files, in a separate checkout. The lead integrates
  committed scoped changes after the worker stops. Each checkout has one writer.
- Base is `5fcee0e`. Preserve the primary checkout's unrelated handoff file. Keep recovery sources.

## 1. Local footage workflow

Add a small CLI for source inventory, offline transcription with an explicitly installed local
model, timestamped transcript search, draft speech-based cuts and validated FFmpeg rendering.
Sources remain untouched; explicit output/cache roots stay outside the source tree. Bind cached
transcripts and plans to source hashes. Reject stale input, invalid times, unsafe paths and output
collisions. Use the existing Whisper environment and FFmpeg; never download implicitly.

Acceptance: tests first fail, then pass; a disposable audio/video fixture travels through an
inspectable cut plan to an export with expected streams/duration while original bytes stay equal.
Real local transcription gets a bounded smoke if a suitable cached model is available.

## 2. Read-only native Claude status mod

Package a native mod under `plugins/` using the installed version's documented API. An explicit
command opens a status pane showing existing actor/claim/capacity summaries and measurement age.
Unknown data remains unknown. Reading records must be bounded and tolerate malformed/missing data.
No prompts, tool arguments, secrets or transcripts are read or displayed. No model calls, process
launch, network, permission decisions, cross-session messages, persistent state writes or timers.
Refresh is explicit. Test hooks and rendered elements in the native mod test kit when possible.

Acceptance: pure parser and UI tests fail before implementation; native plugin validation/test
passes using an isolated configuration directory. CLI version support does not establish Desktop
rendering. Persistent installation is a separate operation subject to the repository's required
other-vendor review before writing Claude user configuration. The currently recorded Claude
weekly limit prevents that review until capacity changes; do not retry the limited model.

## 3. Checked quota continuation

Extend existing coordination commands with a read-only readiness check against an existing
checkpoint and observed source/target capacity. Require distinct supported vendors, a confirmed
source quota limit, target capacity that is confirmed usable, current tracked snapshots/task state,
and no unresolved active actors. Return the preserved next check and explicit blocking reasons.
Do not release claims, terminate actors, alter receipts, send messages or launch a model.

Acceptance: isolated dual-shell Pester tests cover success, live actors, source/input drift,
unknown/limited target capacity, expired source limit and invalid vendor selection. Update the
existing handoff skill with inspection, explicit preservation and checked next-step procedure.

## 4. Integration and deployment

Add discoverability in existing media/coordination skills and the tool catalog. Keep substantial
usage details in supporting references/docs. Update decisions with a new dated entry. Run focused
checks and the complete `aos test` suite under both shells, plus bootstrap preview, Python/Node
checks and native plugin checks. Record failures and skipped live surfaces honestly. Commit early
on the branch; integrate only verified scoped commits if primary remains unchanged.

Complete all concrete implementation and validation before resolving any remaining activation
approval. Do not describe source-only delivery or an unavailable reviewer as successful activation.
