# Cooperative coordination implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Either starting agent automatically assigns useful work across native Claude/Codex workers,
with deliberate model tiers, bounded managed concurrency, live clarification and verified integration.

**Architecture:** Keep reasoning and native agent tools in the vendor harnesses. Extend the existing
PowerShell delegate wrapper and file lock with a small internal coordination helper: actors, addressed
messages and active run state. Keep one writer per checkout and existing host verification.

**Tech Stack:** Windows PowerShell 5.1 and PowerShell 7; Pester 5; existing Node hook tests; git worktrees;
subscription-authenticated vendor CLIs. No new runtime dependencies or resident service.

**Spec:** `docs/superpowers/specs/2026-10-17-cooperative-coordination-design.md`.
**Execution:** The operator approved autonomous continuation after reviewing the design. Use inline
execution for the connected implementation, independently authored Claude safety tests, a focused
pre-code plan critique, and one final independent review. No per-task reviewer requirement.

## Global constraints

- PowerShell sources stay ASCII and compatible with both 5.1 and 7; run `aos test` after each source edit.
- Model ids live only in the local routing map, native allowlist or runtime evidence, never in this repo.
- Existing two-active-actors-per-vendor policy includes waiting coordinators and native children.
- No API spending, credential inspection, new service or changes to vendor plugin caches.
- Tests use TestDrive and redirected state, never real auth, profile, registry or network.
- A new behavioral test is observed failing before its implementation; do not change measured tests.
- Review and verification are separate. Keep independent findings and failures identifiable.
- No silent lease expiry or claim takeover to obtain a worker slot; unknown native state stays unknown.

## Files and interfaces

- `aos.psm1`: existing public dispatcher, vendor launch/receipt, process supervision, claims and cleanup.
- `config/coordination.ps1` (new, dot-sourced by the module): actor/message/run primitives and `aos coord`.
- `tools/coord.ps1` (new): narrow headless entry to `aos coord`, importing the adjacent module at runtime.
- `tests/aos.Tests.ps1`: isolated behavioral tests, including other-vendor safety tests.
- `agents-home/skills/coordination/SKILL.md` (new): routing, native worker contracts, progress and acceptance.
- Shared contract, routing guide, vendor guidance and catalog: one consistent cost-aware policy.
- Plan-owned ignored execution ledger and external fixture worktrees: red/green evidence and live results.

Internal helper contracts, returning PSCustomObjects or ordered dictionaries compatible with 5.1:

- `Resolve-AosTaskRoute(Vendor, Tier, Model, Effort)` -> `{Model; Effort; Tier; Reason}`. Read optional
  `<aos-state>/routing.json` (redirect with `AOS_ROUTING` in tests). Map vendor/tier to model/effort;
  absent light/deep mappings fall back to the standard/default route with an explicit reason. Explicit
  overrides win. Validate vendor, tier and effort; availability remains the existing vendor preflight.
- `Read-AosActorStore()` / `Write-AosCoordJson(Path, Value)`: fail closed on malformed existing state;
  JSON replacement is atomic, under the existing re-entrant coordination lock.
- `Reserve-AosActor(Id, Vendor, Task, Parent, Kind, Handle, Evidence, ProcessId, ProcessStarted)`
  -> `{Ok; Reason; Actor}`. Kinds lead/delegate/native; limit two active rows/vendor. Same identity is
  idempotent, changed identity is refused, parent must be active and authorized. Native evidence is
  marked cooperative until an observed native handle/transcript is supplied. No recursive vendor hops.
- `Set-AosActorState(Id, State, Text, Handle, Evidence)` -> actor. States reserved/running/waiting-input/
  suspect/done/failed/cancelled. Native terminal transitions require evidence; active children prevent
  reporting the parent task cleanly finished. Finishing a reserved never-launched actor is safe.
- `Get-AosActors()` and `Reconcile-AosActors()` return rows; only confirmed ended process identities
  become terminal automatically. Native children require terminal native evidence or explicit verified
  operator reconciliation; never infer death solely from elapsed time or parent death.
- `Send-AosTaskMessage(From, To, Text, ReplyTo)` -> message with unique id, task/run, sender/recipient,
  creation, reply-to and ack. Actors must share a task tree; text is data, never a shell command.
- `Get-AosTaskInbox(Actor, AckIds)` returns only that actor's unacknowledged messages; explicit ack is
  idempotent and recipient-scoped. Locked read/update prevents parent/child consumption races.
- `Set-AosRunState(Id, State, Text, ProcessId, ProcessStarted)` / `Get-AosRunState(Id)` persist
  `<coord>/delegations/<id>/run.json`, with sequence, actor, timestamps and cancellation request.
- `Invoke-AosCoordControl(Arguments)` dispatches JSON-returning `aos coord reserve|observe|finish|actors|
  reconcile|send|inbox|ack|status|wait|cancel`. Validate ids before forming paths; waits are at most 45 s.

Exact CLI options and root registration rules are documented with the implementation. Commands do not
take an executable, arbitrary code string, force-release flag or unauthenticated third-party endpoint.
The actor ids identify cooperative native work, not a security boundary against a hostile local process.

## Review focus

1. Concurrent read-only/native work must count; malformed state must not create free capacity (Task 2).
2. Claim/setup/launch/verify exceptions and failed termination must not leak success or free live slots (3).
3. Parent/child identity ambiguity must not consume another actor's inbox or trust self-reported handles (4,7).
4. Read-only vendor sandboxes may forbid metadata writes: expose tested coverage and retain blocked/rerun
   fallback; do not weaken the project sandbox or advertise a live route not demonstrated (4,7).
5. Shared native output must reach the host-verified tree; combined acceptance must fail without either
   vendor's real contribution, and baseline comparisons must include coordination overhead (7).

### Task 1: Model/effort forwarding and honest receipts

**Files:** aos.psm1, config/coordination.ps1, tests/aos.Tests.ps1.
**Interfaces:** add optional `Tier`, `Effort`, `Parent`, `Workers` arguments to `Invoke-AosDelegate`;
existing arguments/default callers keep working. Dispatcher accepts `--tier`, `--effort`, `--parent`,
`--workers`. Only 0 or 1 native worker allowance is accepted at the current cap.

- [ ] Write failing tests: requested Claude model survives resolver and launch; Codex receives effort
  via `-c model_reasoning_effort=...`; Claude receives `--effort`; invalid explicit tier/effort is refused;
  local mapping selects and records tier fallback; actual unobserved settings remain null. Example:
  `Resolve-AosDelegateModel -Vendor claude -Model fixture-model` must return Model `fixture-model`.
- [ ] Run `AOS_TEST_FILTER='*cooperative routing*'` through tests/Run-Tests.ps1; observe the named failures.
- [ ] Implement route helper and forward settings in both launchers. Parse Claude modelUsage as a list
  of observed models; do not confuse a usage list with proof of the root's configured model/effort.
- [ ] Run the focused tests, then `aos test`; commit the routing fix.

### Task 2: Minimal actor admission and native reservations

**Files:** config/coordination.ps1, aos.psm1 dispatcher, tools/coord.ps1, tests/aos.Tests.ps1.
**Interfaces:** actor/store functions above; JSON public control. Root/child identity is explicit.

- [ ] Have Claude author isolated failing safety tests for atomic two-slot admission, read-only actor
  counting, idempotent reservation, malformed registry, invalid ids, parent/depth constraints, native
  evidence and stale/orphan reconciliation. Keep production files outside its allowed write set.
- [ ] Read the returned diff/receipt and run its tests locally before writing the implementation.
- [ ] Implement lock-protected actor rows and atomic writes. Root sessions reserve explicitly when
  active; mere session-hook presence does not consume a slot. Reserve a foreign coordinator/child
  allowance as one locked operation. Busy returns to the lead; no queue or scheduler.
- [ ] Add the narrow script entry and public dispatcher; check actors/finish/reconcile with fixtures.
- [ ] Run focused tests and `aos test`; commit admission and commands.

### Task 3: Integrate delegate lifecycle and capacity

**Files:** aos.psm1, config/coordination.ps1, tests/aos.Tests.ps1.
**Interfaces:** delegate id is its actor/run identity; optional parent references an admitted lead.
Standalone delegates still reserve their own actor; the shared skill registers the calling lead.

- [ ] Claude authors failing tests for failed claim and setup preventing model launch, exceptions
  creating a failed receipt/releasing confirmed stopped resources, active children rejecting clean
  completion, kill failure retaining claim/slot, limited capacity refusing dispatch and nested
  cross-vendor delegation refusing before launch. Existing tests continue unmodified.
- [ ] Run them red. Wrap resource ownership in try/catch/finally without changing host verification;
  reserve before any model probe/launch, preserve partial work on failure, and write every final receipt.
- [ ] Persist initial active run before launch; separate requested settings, observed settings,
  assigned checks and worker claims. A blocked worker is not accepted and can be re-dispatched.
- [ ] Run focused tests and `aos test`; commit lifecycle integration.

### Task 4: Addressed live clarification and run supervision

**Files:** config/coordination.ps1, tools/coord.ps1, aos.psm1 process runner/prompt, tests/aos.Tests.ps1.
**Interfaces:** message/run functions above. Existing broadcasts/hooks remain compatible; addressed
delivery uses explicit actor ids unless the harness positively identifies the actor.

- [ ] Write failing tests: task-tree addressing, explicit recipient ack, retry without message loss,
  foreign task refusal, parent/child inbox isolation, wait deadline, live run visible before process
  completion, cancellation of the recorded process, and waiting-input suspending only the idle timer.
- [ ] Run red. Add optional live run/actor identity to process supervision. Reuse the existing .NET
  Process handle and process-tree kill, checkpoint stdout while running, and retain the hard deadline.
- [ ] Add JSON control commands and a prompt contract for status/questions/inbox/replies. Permit only
  actor-scoped coordination metadata for read-only assignments. Use native tools for native children.
  Test each sandbox route before enabling live metadata for it; keep blocked/rerun on unsupported ones.
- [ ] Run real local child-process tests (no models/network) plus focused tests and `aos test`; commit.

### Task 5: Shared routing and coordination instructions

**Files:** agents-home/AGENTS.md, coordination/SKILL.md, tool-catalog/SKILL.md, second-opinion/SKILL.md,
docs/routing.md, config/claude/CLAUDE.md, README.md, append-only docs/decisions.md.
**Interfaces:** exact implemented CLI commands and supported coverage from Tasks 1-4.

- [ ] Read skill-creator/writing-skills guidance before adding the shared skill. Keep always-loaded
  rules short and put execution details and examples in the callable skill.
- [ ] Replace contradictory universal review/default-highest-tier instructions with task-aware routing,
  automatic delegation inside subscriptions, required consequential checks and no redundant reviews.
  Explicitly resolve imported process-skill defaults using the user's approved local policy.
- [ ] Document task ownership, dependency checks, native handles/allowances, exclusive native writer
  handoff or scoped patches, integration acceptance, truthful capability limits and quota failover.
- [ ] Run catalog/skill checks, notes-hook tests and `aos test`; commit. Do not sync before final review.

### Task 6: Local end-to-end fixtures and capability gates

**Files:** tools/coordination-smoke.ps1 (new), tests/aos.Tests.ps1; evidence under plan workspace.
**Interfaces:** fixed disposable fixture and JSON evidence, using the implemented control commands.

- [ ] Test a disposable process pair exchanging a question/reply while the worker is still alive, busy
  admission, cancellation, exception cleanup and terminal reconciliation. Verify no artifact outside
  redirected fixture roots is changed. Record acceptance and live-state evidence.
- [ ] Check safe auth metadata for both CLIs (never output/store account details or credentials),
  installed flags/tool schemas, native handle/status support and writable coordination metadata.
- [ ] Persist per-route capability evidence and mark unsupported/unknown coverage accurately; do not
  infer subscription cost from model priority or API dollar estimates.
- [ ] Run focused tests and `aos test`; commit fixture/support changes.

### Task 7: Cooperative live demonstrations and baseline

**Files:** plan-owned evidence, concise tracked validation report.
**Interfaces:** same fixture/base/acceptance checks for both lead directions and single-agent baseline.

- [ ] Use disposable fixture worktrees with two independent required implementation artifacts and
  fixed tests. One task uses an appropriate native worker with observed tool handle/status/transcript;
  the other vendor produces the other artifact. Explicitly collect native output into its assigned tree.
- [ ] Exercise a genuine bounded clarification before completion; inspect the question, reply and
  final receipt. If a sandbox route blocks live metadata, use the supported route and report the limit.
- [ ] Integrate and run fixed checks; remove each contribution in disposable copies to prove the checks
  depend on both artifacts. Run the single-agent baseline and reverse-lead fixture with the same checks.
- [ ] Record actual available settings, actor evidence, wall times and quota observations. Run a small
  inline task showing that no imported skill forces another reviewer. Report unmeasured savings as unknown.

### Task 8: Independent review, integration and idempotent rollout

**Files:** final review/validation report, execution ledger and existing sync targets only as managed.
**Interfaces:** final code revision, spec requirements and evidence, then the existing sync command.

- [ ] Record the author's findings, then request one blind Claude review of the whole change. Check its
  findings against code/tests, obtain independently authored failing tests for risky fixes, fix, and
  run `aos test`, notes tests, whitespace/ASCII checks and bootstrap dry run.
- [ ] Fast-forward the approved design branch in the primary checkout after verifying claims and the
  unchanged unrelated untracked file. Preserve both worktree commits and recorded evidence.
- [ ] After the cross-vendor settings review, sync from the primary source with backups; run a second
  sync and compare managed files/links for idempotence. Run the live small-task policy check in a fresh
  agent session loading the synced rules. No cloud publish or push is required.
- [ ] Mark the spec/ledger with observed completion and remaining capability limits. Report exactly
  which checks passed, skipped or failed, and link implementation/evidence. Do not claim the goal
  complete while required cooperative execution, clarification or rollout checks remain unverified.
