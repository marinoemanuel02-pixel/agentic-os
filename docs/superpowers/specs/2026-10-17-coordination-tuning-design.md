# Coordination tuning implementation

Date: 2026-10-17. The user approved all six additions in the researched backlog. Execution is
automatic within existing subscriptions, using the shared policy instead of imported approval gates.

## Outcome and constraints

Extend the working coordinator with measurements, checked dependencies, compact context, native
budgets/events, durable recovery and verified reusable procedures. Preserve prose-only delegation,
existing receipts, one writer per checkout and two active actors per vendor. No paid API, new server,
dependency, automatic credit consumption or forced update. PowerShell stays ASCII and 5.1 compatible.

Use optional task contracts; do not replace the existing dispatcher with a scheduler. The root owns
integration, native workers use separate worktrees, and the other vendor authors safety tests before
the root writes the corresponding changes. Review the final settings changes before syncing.

## Task contracts and acceptance

`--contract <json>` adds a version-1 record containing `id`, `objective`, `task_class`, `depends_on`,
`allow`, `verify`, `artifacts`, `context`, `route_reason`, `review` and `budget`. Task classes are
mechanical, implementation, sequential, diagnosis, research and consequential. Optional fields get
conservative defaults. Unknown fields, unsafe relative paths and invalid limits fail visibly.
Artifacts are relative file paths. Context is an array of `{path,start_line,end_line}` references.
Budget contains `timeout_minutes` (1..120) and `max_turns` (1..100); native allowance remains 0 or 1.

Task ids remain separate from immutable attempt ids. Registration is idempotent only for the same
contract/repository. Cycles are rejected. Missing dependencies may be registered but block dispatch.
Only an accepted host receipt with successful verification and immutable artifact hashes can satisfy
a prerequisite. Its artifacts must already be integrated into the dispatch checkout and still match.
Check again before accepting work. An active/suspect attempt or an accepted task prevents accidental
duplicate dispatch. Failed terminal attempts can be retried with a new attempt id.

Packets include the objective, constraints, accepted input references and bounded context excerpts
(at most 12,000 characters). Preserve exact file references and unresolved inputs. Select at most
three relevant verified procedures; never include the entire lead history or all memory by default.

## Measurements and evaluations

Extend receipts with task identity/class, route/review rationale, phase timings and explicit usage
observation. Missing values remain null. Record host verification separately from worker claims.
Route reports group comparable task class/vendor/tier/transport, include failed attempts, corrections
and missing measurements, and never convert API dollar estimates to subscription savings.

Provide a six-case evaluation manifest and a local runner that uses the existing delegate path when
explicitly requested. Repeated trials get unique task ids and clean fixture worktrees. The no-model
test path checks manifest, reporting and outcome grading, not model quality. Quality and corrections
precede timing. Consequential review remains required independently of the comparison.

## Native controls and lifecycle

Probe installed CLI versions and local schema support without model requests. Generate managed native
role definitions from local routing data, with supported effort/turn controls and conservative fallback.
Keep model ids out of this repository. The role/launch contract records requested versus observed
settings. A CLI cap applies per session; the shared registry still accounts across managed sessions.
Partial output at a turn budget is never accepted as completion.

Claude hooks relay bounded native start/stop metadata to the host. Correlate reserved allowance,
parent/run and actual native identity. Deduplicate repeat delivery; resume does not create free capacity.
Hooks provide lifecycle observations, not a security boundary or pre-launch budget enforcement.

The optional Codex App Server adapter is a short-lived stdio child behind `--transport app-server`.
It confirms ChatGPT authentication before starting a model turn, consumes no credits/resets, normalizes
events for existing parsing and accepts steering only for the exact active turn. The current `exec`
transport remains the default. No schema-only check is advertised as a successful live integration.

## Recovery and procedures

Checkpoints bind the repository revision, task/attempt states, artifact hashes, active actors,
unanswered message references and next check. A cold read detects changed artifacts or unknown actors;
it never releases a suspect actor. Preservation manifests are verified before archival. Owner-scoped
claim release works for a removed checkout by its recorded canonical identity and still refuses any
other session's claim. App-owned missing snapshots are not repaired by bypassing the app.

Procedures are scoped to repository and task class, with text, relevant file hashes, evidence receipt
ids and invalidation conditions. Promotion requires two distinct successful host-verified attempts
in that repository. Failed/contradictory evidence is retained and prevents promotion. File drift marks
the procedure stale; selection excludes stale or unverified entries. Retrieval is bounded and explicit.

## Done

All six paths have callable interfaces and meaningful RED/GREEN tests. Both shells, Node protocol/hook
tests, a live subscription adapter check, cold checkpoint continuation and an actual bounded native
route are checked. Independent review precedes backed-up sync; second sync preserves bytes/timestamps.
Report unsupported native settings and external archive recovery separately from implemented features.
