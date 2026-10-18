# Further coordination tuning: evidence and implementation backlog

Checked: 2026-10-17. Local baseline: `f7f42f6`.
Status at research time: proposals. All six were subsequently implemented; see the
[validation record](../validation/2026-10-18-coordination-tuning.md) for checks and rollout status.

The strongest next investment is a measured feedback loop around the existing coordinator, followed
by enforceable dependencies and smaller handoff packets. Native lifecycle integration can then reduce
manual bookkeeping. Keep the current two-active-actors-per-vendor limit while measuring these changes.

## What the current stack already provides

Read locally: `README.md`, `docs/routing.md`, the latest decision, the shared coordination skill,
`config/coordination.ps1`, delegate launch/prompt/receipt code in `aos.psm1`, the result schema and
vendor configuration templates. The prior [validation report](../superpowers/specs/2026-10-17-cooperative-coordination-validation.md)
records 435 passing tests per shell and live cooperation in both directions.

Already present: automatic routing policy, local tier maps, actor admission, native allowances,
addressed messages, live questions, checkout ownership, scoped patches, host verification and receipts.
These should be extended rather than rebuilt.

Gaps found in the inspected implementation:

- Routing uses a static local map and the lead's judgment. There is no task-class comparison dataset.
- Receipts contain total duration, usage and outcome, but do not separate startup, execution, waiting,
  verification, integration, review and rework. Some usage fields initialize to zero; an aggregator
  must distinguish unavailable usage from an observed zero.
- Task constraints and semantic dependencies are mainly prose. Actor parentage is not a dependency
  graph, and a worker's `done` status is not acceptance of a prerequisite artifact.
- Native handle/completion evidence requires coordinator or host bookkeeping. Current hooks cover
  session/edit/note events, not automatic native lifecycle correlation.
- The local smoke fixture exercises transport, admission, cancellation and launch failure. It is
  not a repeated benchmark of actual routing choices, compaction recovery or native model settings.

## Prioritized additions

| Order | Addition | Concrete change | Acceptance evidence |
|---|---|---|---|
| 1 | Routing measurements and evaluations | Extend existing receipts with route rationale, task shape, phase timings, observation flags and correction outcomes; add a local report over them | Repeated comparable solo/cooperative tasks with fixed checks; account for integration and review time |
| 2 | Dependencies and handoff packets | Validate a small task record and bind prerequisite artifacts to accepted revisions | Block dependent dispatch on missing, failed or stale prerequisites; reject cycles |
| 3 | Versioned native worker controls | Probe capabilities, then apply supported role, effort, turn and concurrency settings | Actual child settings/lifecycle observed; unsupported options visibly rejected or marked unavailable |
| 4 | Native lifecycle and active-message adapters | Correlate Claude lifecycle hooks and optionally Codex App Server events with the existing actors | No duplicate actors/messages; correct cancellation and recovery under event replay |
| 5 | Checkpoint and recovery tests | Persist a minimal continuation packet and verify preservation before archive/cleanup | Resume from files after context loss; no false success or slot release after host/process failure |
| 6 | Verified reusable procedures | Retrieve only relevant, outcome-checked project procedures | A held-out task benefits; stale procedure is detected and can be removed |

### 1. Measure the value of each route before tuning it automatically

Research across 260 configurations reports that collaboration can help decomposable work and hurt
sequential work. This supports task-specific measurement, not a universal best team size or model
split. These are benchmark findings, not results for this machine.
Source: [Towards a Science of Scaling Agent Systems](https://arxiv.org/abs/2512.08296), submitted
2025-12-09, revised 2026-04-08; abstract opened.

Proposed implementation in the delegate/receipt code:

- Record task shape, chosen vendor/tier, reason for delegation, review choice and relevant risk.
- Separate launch, model execution, user/peer wait, host checks, integration and optional review times.
  Record corrections and human intervention separately from final success.
- Preserve observed usage separately from unavailable usage. Subscription-window changes are shared
  account observations, not reliable per-task billing. API dollar estimates are not subscription cost.
- Tag failures by stage: specification, routing/admission, tool/permission, communication, execution,
  integration or verification. Preserve the raw outcome and an unknown cause when attribution is uncertain.

A published failure taxonomy provides a basis for separating coordination failures from execution
failures, but its categories should not be presented as a diagnosis without trace evidence.
Source: [Why Do Multi-Agent LLM Systems Fail?](https://arxiv.org/abs/2503.13657), submitted 2025-03-17,
revised 2025-10-26; abstract opened.

Start with six small task classes: mechanical edit, independent implementation, sequential refactor,
diagnosis with competing hypotheses, research synthesis, and consequential change. Include cases where
delegation/review should occur and cases where they should not. Use clean fixtures, fixed outcome checks
and repeated trials within the existing subscriptions. Compare success and corrections first, then
end-to-end time and observed usage. Keep the consequential-review rule independently of efficiency.

This follows the evaluation guidance to use isolated trials, check outcomes and test both triggering
and non-triggering behavior. Source: [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents),
2026-01-09; article and evaluation-design sections opened.

The existing tiny fixture was slower with cooperation than solo. That supports keeping tiny tasks
inline; it does not settle the result for larger tasks. Do not run every real user task twice. Use a
bounded benchmark and selected comparisons, with no learned routing thresholds until there is data.

### 2. Turn task dependencies into checked inputs

Claude's native team task list has dependency blocking. It also documents overhead and cases where
dependent work is better kept in one session. These are useful semantics to adopt in the existing
cross-vendor wrapper, without requiring the experimental team mode.
Source: [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams), documentation date
not found; opened 2026-10-17.

Add a small optional task record beside the existing task text: task id, prerequisite task ids,
base revision, allowed writes, acceptance check, expected artifacts and task budget. Keep task
identity separate from the already-unique attempt id. No scheduler service is needed: the lead still
chooses the route, while admission checks whether required inputs are accepted and current.

Pass each worker a compact packet: objective, constraints, relevant file/symbol references,
prerequisite artifact/commit references, unresolved questions and required evidence. Prefer references
and short excerpts to a copy of the lead's entire conversation. Check artifact content/revision before
launch and again during integration. A file list alone cannot establish independence.

Context engineering guidance supports selective retrieval, compaction and external structured notes.
The proposed packet format is a local design inference, not a vendor interoperability standard.
Source: [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents),
2025-09-29; article and compaction/note sections opened.

Tests should cover unresolved/failed prerequisites, cycles, changed prerequisite revisions, duplicate
attempts, dependent tasks falsely marked done, and cold continuation that can locate the actual evidence.

### 3. Add native controls only after checking the installed version

Local CLI checks: Codex `0.157.1`; Claude Code `2.1.286`. No model request was made for this check.

The current Claude docs describe `maxTurns`, tool restrictions, worktree isolation and per-worker
effort. However, per-invocation effort requires `2.1.292+`; automatic compact-window configuration and
unknown-field diagnostics require `2.1.296+`. Those newer capabilities are not established for the
installed version. Frontmatter support and actual invocation support must be tested separately.
Source: [Claude Code subagents](https://code.claude.com/docs/en/sub-agents), documentation date not
found; frontmatter and effort sections opened 2026-10-17.

Codex's current docs expose native model/effort defaults and a concurrent child-thread limit that
excludes the primary agent. Thus one child per coordinator is the corresponding per-session ceiling
for this stack, where supported. This does not enforce the global two-per-vendor policy across sessions.
Custom-agent instructions also do not create a separate read-only sandbox.
Source: [OpenAI subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents),
documentation date not found; configuration and permission sections opened 2026-10-17.

Maintain a local capability record with CLI version, supported schema, last successful fixture and
observed limitations. Use a few reusable task roles such as exploration, implementation and verification,
with narrow briefs and meaningful checks. Keep cloud model ids only in local routing data. Apply a
bounded escalation rule: an appropriate lighter worker can escalate with its evidence when a concrete
check or capability fails; permission/quota failures do not justify blindly retrying a stronger model.

Before rollout, verify actual child model/effort where exposed, turn-limit partial results, read/write
scope, parent accounting and settings precedence. A requested model is not an observed model. Retain
the current supported route when a feature is missing. This review did not upgrade either CLI.

### 4. Use native lifecycle events to reduce manual coordination

Claude documents `SubagentStart`/`SubagentStop` identities and a child transcript path on stop. Start
events can also occur on resume, so they cannot be treated as unique new launches. Use these signals
for observed lifecycle correlation, not as proof that a pre-launch budget was enforced.
Source: [Claude hooks reference](https://code.claude.com/docs/en/hooks), documentation date not found;
lifecycle and subagent sections opened 2026-10-17.

The Codex App Server documents structured turn/item events, active-turn steering, interruption and
ChatGPT rate-limit reads/updates. The installed CLI's generated schema contains `turn/steer`,
`turn/interrupt`, `account/rateLimits/read` and `thread/tokenUsage/updated`. Schema presence is a local
prerequisite check; it is not a completed live integration.
Source: [Codex App Server](https://learn.chatgpt.com/docs/app-server), documentation date not found;
lifecycle, steering and account sections opened 2026-10-17.

Prototype an optional adapter behind the existing delegate interface. Normalize events into existing
actor/run/message records, deduplicate by stable event identity and correlate the exact active turn.
Keep `codex exec` as the fallback. Account reads must stay read-only; no credit/reset consumption or
credential extraction is needed. Prove existing-subscription authentication on the actual adapter route.

Validate split/duplicate/out-of-order events, reconnect, process death during host verification,
an already-ended turn receiving a reply, and kill failure. Preserve suspect state when completion is
unknown. Active steering must not be advertised as an arbitrary idle-session wake mechanism.

### 5. Make recovery evidence a first-class acceptance check

Long-running harness guidance uses incremental work, commits, progress files and explicit verification
to help a fresh session continue correctly. Source: [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents),
2025-11-26; progress, environment and testing sections opened.

Extend the current handoff with a short machine-readable checkpoint: current accepted revision,
pending task/attempt ids, active actors, unanswered questions, artifact locations and next check.
Keep a human-readable explanation alongside it. Test recovery after compaction or a stopped host,
rather than merely testing that a checkpoint file exists.

The previous rollout also exposed an app archive-restore failure and an archived-path claim that the
normal path-resolving release command could not clear. All source and validation evidence were preserved.
Before future archive cleanup, verify a preservation manifest and a recoverable source reference.
A future owner-scoped release path should work from recorded checkout identity after the directory
is gone; it must still reject another session's claim. Do not bypass an edit guard or force-release
unknown activity. App-owned snapshot recovery remains an external limitation until a real restore passes.

### 6. Reuse verified procedures selectively

Workflow-memory research reports benefits from reusing task procedures on web-navigation benchmarks.
Applying that result to coding-team coordination remains an inference.
Source: [Agent Workflow Memory](https://arxiv.org/abs/2409.07429), 2024-09-11; abstract opened.

Use existing project notes and shared skills first. A reusable procedure should identify its applicable
task, evidence, last verified revision and invalidation conditions. Retrieve only the relevant procedure;
do not append every lesson to always-loaded instructions. Promote a repeated successful procedure
after checking its outcome. Keep conflicting and failed results visible. The existing local classifier
can screen short texts after sample calibration; no new memory server is justified by this review.

## Implementation sequence and boundaries

1. Extend receipts and add the small evaluation/reporting layer. Run it in observation mode before
   changing automatic routing decisions.
2. Add dependency checks and artifact packets to the existing delegate path. Keep prose-only tasks
   compatible and preserve current receipts.
3. Validate native settings against installed versions, then add lifecycle correlation. Prototype
   the App Server adapter separately and retain the working CLI path.
4. Add checkpoint/recovery fixtures and promote useful procedures only after outcome evidence exists.

New runtime behavior needs failing tests first, both PowerShell versions, and the existing `aos test`
checks. Changes that write vendor profiles/settings need the required independent vendor review before
sync, then backups and a second idempotence check. This research document does not authorize a paid
API migration or claim that the proposed settings are already active.

Do not increase swarm size or add a general orchestration framework yet. This is an engineering
recommendation based on the existing wrapper and observed overhead, not a claim that such frameworks
cannot help. Likewise, the hosted Agents API is a separate API-billed runtime, so it does not meet the
current subscription-only constraint merely because it uses the same harness.
Source: [OpenAI Agents API pricing section](https://developers.openai.com/api/docs/guides/agents-api/overview),
documentation date not found; opened 2026-10-17.

Research used this session and one bounded native worker within the existing subscription. No new
service, MCP server, dependency, paid API call, vendor update or profile setting was added by this
review. Local protocol schemas were generated under `~/.aos/research/coordination-tuning-20261017/`;
they contain protocol definitions, not credentials. Verification for this documentation-only change:
source-link/local-reference inspection and `git diff --check`; the runtime test suite was not rerun.
