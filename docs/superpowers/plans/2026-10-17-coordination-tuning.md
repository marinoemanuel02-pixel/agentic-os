# Coordination tuning implementation plan

> **For agentic workers:** Use superpowers:executing-plans for the connected runtime work. The isolated adapter worker implements its bounded component. Checkboxes track observed completion.

**Goal:** Install all six researched additions without a new service or API spending.
**Architecture:** Extend existing delegates/receipts/coordination with optional contracts and small
helpers. Separate the stdio adapter and native signal hook from the PowerShell host.
**Tech Stack:** PowerShell 5.1/7, Node built-ins, Pester, native subscription-authenticated CLIs.
**Spec:** `docs/superpowers/specs/2026-10-17-coordination-tuning-design.md`.

## Constraints and review focus

ASCII PowerShell; no tracked cloud-model ids or machine-absolute paths; two actors per vendor;
one writer per checkout; no paid APIs/credit reset consumption. Existing measured tests stay intact.
Review stale/forged prerequisites, partial results, ambiguous native identities, unknown usage and
post-crash recovery. All five receive explicit tests below. Required settings review is cross-vendor.

## File responsibilities and interfaces

- `config/task-contracts.ps1`: `Register-AosTaskContract(Path,Repo)`, `Get-AosTaskRecord(Id)`,
  `Test-AosTaskReady(Id,Repo)` -> `{Ready,Reasons,Inputs}`, `Start-AosTaskAttempt(Id,RunId)`,
  `Complete-AosTaskAttempt(Id,RunId)` reads actual host receipt, `Get-AosTaskPacket(Id,Repo)`.
- `config/coordination-learning.ps1`: `Get-AosRouteReport()`, `Save-AosCheckpoint(Id,Repo,TaskIds,NextCheck)`,
  `Test-AosCheckpoint(Id,Repo)`, `Save-AosProcedure(Id,Repo,TaskClass,Text,EvidenceIds,Files)`,
  `Get-AosProcedures(Repo,TaskClass,IncludeStale)`.
- `config/native-coordination.ps1`: version/schema capability record, managed role sync, native
  signal correlation and active-turn steering validation.
- `tools/codex-app-server.mjs`: short-lived adapter and pure protocol reducer; Node tests beside it.
- `tools/coordination-hook.mjs`: bounded native signals; Node tests beside it.
- `tools/coordination-eval.ps1`, `config/delegate/eval-cases.json`: six-case manifest and repeat runner.
- `aos.psm1`: helper loading, contract/transport flags, phase measurements, receipt/task lifecycle,
  owner-scoped removed-checkout release and existing sync/test wiring.
- `tests/aos.Tests.ps1`: independent safety tests; `tests/tuning.Tests.ps1`: component and integration tests.

### Task 1: Contracts and compact inputs

- [ ] Have Claude author additive failing safety tests for missing/failed/stale dependencies, cycles,
  duplicate active/accepted attempts, forged receipts and removed-checkout release ownership.
- [ ] Observe RED before implementation in both shells. Implement strict path/field/limit checks,
  canonical contract identity, locked attempt ownership, receipt-backed artifact acceptance and packets.
- [ ] Wire optional `--contract` into the existing delegate; retain prose compatibility and host checks.
- [ ] Run focused `aos test` in both shells and commit.

### Task 2: Measurements, reporting and evaluations

- [ ] Write failing tests for unavailable-versus-zero usage, comparable route grouping, failures,
  correction metadata and six evaluation case classes with fixed outcome checks.
- [ ] Extend receipts with phase timing/observation, class and route/review rationale. Add reporting
  and a bounded repeated-evaluation runner over clean fixtures using the existing delegation path.
- [ ] Check deterministic reporting/manifest fixtures with no models; run focused `aos test`; commit.

### Task 3: Native controls and signals

- [ ] Test version gates, role rendering from local model maps, unsupported settings, duplicate
  start/stop/resume events, unknown native identity, partial results and unchanged second sync.
- [ ] Implement capability probes and managed roles, native allowance correlation and lifecycle hook.
  Keep native sandbox inheritance explicit. Never infer observed model from requested settings.
- [ ] Run PowerShell/Node fixtures and a bounded live native route; commit.

### Task 4: Optional App Server transport

- [ ] Isolated native worker writes failing Node tests before its adapter, using installed schemas.
- [ ] Cover auth refusal, exact main-turn result, split/duplicate streams, failed/partial completion,
  steering after turn end, cancellation acknowledgement and early EOF cleanup.
- [ ] Integrate `--transport exec|app-server`, preserving current parser, result schema, scope checks
  and receipts. Run fake-server tests and a live ChatGPT-authenticated read-only check; commit.

### Task 5: Recovery and verified procedures

- [ ] Write failing tests for cold checkpoint continuation, changed revision/artifacts, active unknown
  workers, preservation manifest checks, evidence promotion and stale procedure exclusion.
- [ ] Implement repository-scoped checkpoint/procedure commands, bounded retrieval into task packets,
  retained failure evidence and claim release after removal with exact owner checks.
- [ ] Run focused tests and a cold native continuation; commit.

### Task 6: Review, integration and rollout

- [ ] Update shared coordination/handoff/catalog guidance and append the decision; document commands,
  capability limits and actual measurements without claiming unmeasured subscription savings.
- [ ] Record author findings; obtain one blind cross-vendor final review before settings writes.
  Reproduce material findings with independently authored tests, then fix and verify.
- [ ] Full `aos test`, Node tests, ASCII/parse, `git diff --check`, bootstrap dry run and live checks.
- [ ] Fast-forward primary, preserve evidence, back up managed targets, sync twice and compare state.
  Keep source worktrees until recoverability is verified; report actual unsupported routes.
