# Evaluate the two GPT reports and the Perplexity follow-up

## Goal and constraints

Evaluate recommendations against the checked-out stack before adding behavior. Keep existing
coordination, subscription authentication, vendor settings and video approval policy. No downloads,
upgrades, telemetry collector, destructive cleanup or automatic routing change is part of this work.
Use an isolated branch and retain raw experiment evidence outside OneDrive. Imported process skills
do not add an approval pause or reviewer beyond the project's risk rules and the user's request.

## Task 1: Establish the actual baseline

- Read all three reports and map overlapping proposals to existing code and tests.
- Run the unchanged dual-shell suite and retain its log.
- Record CLI authentication/version observations without credentials, local model availability,
  receipt completeness and selected primary-source corrections.
- Write a dated evaluation with retain, duplicate, conditional and unsupported decisions.

Acceptance: every research recommendation has a disposition; unknowns remain explicit. Existing
receipt annotations, creative gates and the optional automation transport are not rebuilt.

## Task 2: Make fixed evaluation runs comparable, if the gap reproduces

Interfaces: `tools/coordination-eval.ps1` produces prepared/executed trial reports;
`tools/coordination-compare.mjs` consumes those reports and their host receipts read-only.

- Add regressions in `tests/aos.Tests.ps1` for immutable fixture/task/grader fingerprints,
  mismatched inputs, incomplete evidence, and execution time versus known repair/review overhead.
- Observe the new assertions fail before implementation. Do not weaken existing graders/tests.
- Add deterministic input fingerprints and requested route metadata to existing trial rows.
- Add a dependency-free offline comparison tool. Keep failed attempts and unknown measurements
  visible; require matching fingerprints before comparing. Never infer zero corrections or unknown
  overhead, and never add waiting twice. Do not declare an automatic winning route.
- Re-run the regressions under both shells, then `aos test` for the combined change.

Acceptance: frozen equivalent fixtures can be compared without conflating quick execution with
accepted work requiring repair. Old/unmatched reports are visibly non-comparable. Existing receipts
remain authoritative; there is no duplicate telemetry store or billing estimate.

## Task 3: Run bounded local experiments

- If capacity/authentication allow, run two existing fixtures once per vendor in alternating order,
  preserving fixed graders, receipts, fingerprints and actual observations. Annotate only observed
  correction/integration/review effort. Treat this as feasibility evidence, not a model ranking.
- Use a synthetic required ignored/untracked file to demonstrate the tracked-only recovery limit,
  then restore a declared preservation set into a new destination. Retain the source. This proves
  only the fixture's preservation, not clean-machine or app-managed archive recovery. Do not ship a
  general archive/restore utility from a single synthetic trial.
- Freeze representative queries and sources before comparing current rg search, disposable FTS5,
  and the installed Ollama embedding route. Use explicit non-secret documentation roots only,
  report language coverage and cold/warm latency, and do not download a model or create a service.
  Do not promote a persistent retrieval tool on synthetic examples alone.
- Preflight Perplexity-only additions from primary sources. Keep installer/auth and TUI changes
  deferred where they duplicate current behavior or require unrelated upgrades.

Acceptance: each experiment has a baseline, actual outcome, evidence references and a limited claim.
No real worktree is deleted, no secret is exported, no new vendor configuration is applied.

## Task 4: Verify and deliver

- Verify the final runtime with `aos test`, focused controls and `git diff --check`.
- Document exact checks, failures, skipped probes and limits; update usage documentation only for
  implemented commands. Append a decision only if persistent behavior is adopted.
- Commit by explicit file names on the isolated branch. Preserve the primary checkout's unrelated
  handoff file. Integrate only the verified scoped changes if the primary has not advanced.

## Review focus

Input identity versus timestamps; stale report snapshots versus annotated host receipts; missing
metrics versus measured zero; failed versus accepted host checks; repeated attempt aggregation;
waiting already included in execution; lexical versus semantic retrieval; source copies versus
actual disaster recovery. Recovery/authentication changes, if later proposed for production, require
the project's separate risk review and independently authored failing tests first.
