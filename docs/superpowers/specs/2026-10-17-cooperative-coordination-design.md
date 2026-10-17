# Cooperation between Claude and Codex teams

Date: 2026-10-17. Status: draft for user review; implementation has not started.
Confirmed user decision: the starting agent chooses delegation and model tiers automatically within
the existing subscriptions. That decision does not authorize additional API spending.
Independent critique and the author's dispositions are recorded separately in
[`2026-10-17-cooperative-coordination-review.md`](2026-10-17-cooperative-coordination-review.md).

## Intent and acceptance

The operator wants useful cooperation during planning and execution, including native subagents and
lighter models where they are suitable. Cross-vendor review remains available, selected for its value
and cost. The objective is better completed work per subscription window, not maximum agent count.
This change addresses coordination only; the operator will supply other architecture concerns later.

Success requires a demonstrated task with useful execution by both vendors, appropriate native worker
selection, progress and clarification exchange, verified integration, and a small task deliberately
completed by one agent. A shared instruction file alone does not establish success.

## Existing evidence

- `docs/routing.md:22` says the builder never reviews its own work alone. The shared second-opinion
  skill already makes a narrower, risk-based decision. The instructions conflict.
- `aos.psm1:2800` discards a requested Claude model; the Claude launch at line 3201 passes neither
  model nor effort. The CLI parser at line 3435 has no effort option. Both checks were reproduced
  without model calls on 2026-10-17.
- Delegate writers already get worktrees, claims, host-side commit and verification, allowed-file
  checks, timeout handling and receipts (`aos.psm1:3089-3297`). Keep those mechanisms.
- Capacity currently advises; checkout claims protect writers, not all active agents. There is no
  shared admission check for native children, read-only delegates and coordinators.
- The notes hook skips delegates (`config/hooks/aos-notes.mjs:50`); the wrapper supplies no live
  alternative. Output and the receipt are saved after the process ends. Current notes are broadcasts
  between vendors, without task addressing or acknowledgements.
- All 11 notes-hook tests passed during the audit. They establish the existing behavior, including
  delegate suppression; they do not establish cooperation. The full PowerShell suite was not run.

## Architecture and alternatives

Use the agent the operator starts as the lead. It owns decomposition, routing, integration and the
user-facing answer. Each vendor executes inside its own native harness. The lead may assign a bounded
unit to the other vendor as a worker or as a coordinator with a reserved native-worker allowance.

The lead keeps task relationships and compact results in the existing file-based coordination store.
Extend `aos delegate`, its receipts and the existing hooks. Do not add a resident scheduler, service,
external account, or replacement agent harness. Native asynchronous tools launch and wait for work;
the wrapper remains a supervised CLI process with inspectable state.

Policy-only changes would leave model selection, live exchange and admission unenforced. A new swarm
framework would duplicate native harnesses before any benefit has been demonstrated. The proposed
middle course adds only the runtime mechanisms needed to make the shared policy observable.

## Routing and task ownership

For substantial work, the lead records a short work breakdown before dispatching. The breakdown may
contain one task: a split is justified only when reduced elapsed time, a capability advantage,
independent reasoning or quota balance is worth startup, context, communication and integration cost.
Simple tasks stay inline. No invented percentage or token threshold substitutes for that judgment.

Each task has a stable id, parent task, goal, acceptance criteria, dependencies, owner, repository and
base revision, allowed write set, verification command, worker allowance, tier and review decision.
Every attempt has a separate run id. A revision to the scope is explicit; a worker cannot silently
expand its assignment or transfer ownership. Routing decisions include a concise reason, not a
long planning transcript.

Ownership is per task, not a fixed vendor specialization. The current vendor strengths are defaults,
checked against available tools, context and capacity. Assignments can include research, independent
hypothesis investigation, design, tests, implementation, documentation and review. The other vendor
does not need to be involved in every task.

Independent implementation work can run concurrently in separate worktrees. Disjoint file globs
alone do not prove independence: shared interfaces, generated files, lockfiles and dependencies must
also be checked. Dependent work waits for an accepted prerequisite and starts from its integrated
revision. Parallel branches use the same declared base, followed by verification of their combined
result. There is one writer per checkout, including native children.
Checking semantic dependencies is a lead decision recorded in the work breakdown, not a promised
static detector. Automated tests can check declared dependencies; live evidence checks this judgment.

Only the lead integrates cross-vendor results. A vendor coordinator can use native children within
its assigned unit, but cannot delegate back across vendors or create a second cross-vendor tree.
Native workers cannot acquire extra slots or change their own budget. This bounds delegation loops
without preventing the two vendor teams from doing useful execution.
Before native implementation starts, choose one output path. With one native writer, the coordinator
can hand it exclusive writing of the assigned worktree while remaining read-only itself; the task's
claim remains held and the child identity is recorded. The coordinator resumes writing only after the
native handle is terminal. Otherwise children use separate worktrees and return scoped patches; the
coordinator checks and applies those patches into its assigned worktree after the child writers stop.
The existing host then commits and verifies that assigned worktree. Native child output is never
accepted merely because it exists in an uncollected worktree, and CLI delegates still do not commit.

## Model and effort selection

Use three task tiers: `light`, `standard`, and `deep`. They describe task requirements, not permanent
model names. A light assignment is narrow and has a meaningful check; standard covers normal
implementation; deep covers ambiguity, difficult diagnosis or consequential reasoning. Review does
not automatically select the most expensive model.

Resolve tiers from the current harness allowlist and a local, untracked routing map under the aos
home directory. Explicit account-supported model ids may be stored there, never in this repository.
Catalog priority is not evidence of price, capability or subscription quota efficiency. Preserve the
existing model availability probe and cache, extended where needed; do not probe many candidates on
every assignment. Availability is a property of a vendor, account, client and model combination.

Explicit model and effort requests must reach both vendor launch commands. An unsupported explicit
request fails visibly; it is not silently ignored. For automatic routing, an unavailable light tier
may use an available standard tier, recording the reason and actual selection. Do not claim a
cheaper worker ran unless the actual model is observed and the cost comparison is established.
Record requested tier, model and effort separately from observed model and effort; unknown is null.
Correct routing is independently valuable; it does not by itself prove a saving. Tier substitution
tests demonstrate honest fallback only. Speed or quota benefit requires an observed comparison.

Use native per-spawn model and effort controls where supported. CLI version checks and tool schemas
determine support. Do not write global settings to force every child onto one model or override an
unrelated user's session. If an effort field is unavailable on a native spawn, use a supported worker
definition or CLI route, or record the limitation and choose another eligible route.

Keep calls on the existing subscription authentication paths. Do not add API keys, enable extra
usage credits, change billing mode or assume a dollar token estimate is a subscription bill. Verify
the auth mode through supported status metadata; never inspect credential contents. An unverified
route is not advertised as verified subscription-only execution.
The implementation plan must first establish which safe status metadata each installed client exposes.
Until that evidence exists, the route is ineligible for unattended subscription-only CLI execution;
use the already verified native session route instead of guessing the billing mode.

## Team budget and enforcement boundary

Retain the existing budget of two active actors per vendor, including the coordinator. This is the
operator's policy, not a claimed vendor hard limit. A waiting coordinator still occupies its slot
until the task completes. Thus a lead and one native worker fill one vendor's allowance; a foreign
coordinator and one native worker fill the other vendor's allowance.
This supports one child per coordinator at the current cap. Useful gains can come from different
model tiers, tools and isolated contexts without more fan-out. Larger teams require a later explicit
budget change based on measurements; they are not silently enabled by this design.

Add actor registrations and slot reservations under the existing coordination lock. Register the
lead before its first managed dispatch. Reserve all slots needed for an assignment atomically before
launching it. Pending assignments stay in the lead's work breakdown and hold no slots. A reservation
carries vendor, task, parent,
actor id, owning session/process identity, native handle when known, state and timestamps. Record
launch, failure and terminal transitions. Return `busy` when required slots are unavailable; the lead
can wait for a terminal event, pick another eligible route, or work inline. There is no durable queue
or scheduler. Do not retry a busy request before state changes or beyond its assignment deadline.
Presence registration is distinct from admission: an idle session with no active assignment does not
hold a slot. A session-start hook for an admitted delegate attaches to its existing reservation using
the run/actor identity; it must not count the same coordinator twice.

Claims cannot substitute for this registry: read-only actors do not claim checkouts. Session hooks
register observable top-level sessions; managed native spawns reserve before calling the native tool
and register its returned handle. A failed spawn releases its reservation. Budget changes belong to
the lead, and a worker receives only the allowance already reserved for it.

Enforce admission for aos-managed launches. Native tool spawns must follow the shared skill and use
supported native caps where available. Some harnesses do not expose enforceable cross-session spawn
hooks; report those paths as cooperative rather than claiming a universal hard cap. A top-level
session discovered outside the managed flow reduces the available budget only while known to have
an active assignment; idle session presence alone does not reserve capacity.
Unknown native activity is reported as unknown; a strict task cannot fan out through an unobservable
route. Capability checks must establish which routes are eligible before the live demonstration.

Heartbeat expiry alone is not proof that an actor stopped. Mark stale actors suspect, retaining their
slots until terminal harness evidence or confirmed process-tree termination permits release. Check
process identity, including creation time, to avoid PID reuse. Cancellation is acknowledged only after
termination is confirmed; a failed kill retains the slot and claim and reports inspection needed.
Normal completion and exceptions release resources in a finally path, without overwriting a newer
owner's claim. Failed claim acquisition or required setup stops execution before model work begins.
Keep the first registry minimal: actor identity, reservation and observed terminal evidence, reusing
the existing lock and process runner. No heartbeat service or automatic lease-based release is needed.
If the lead dies, reconciliation inspects each child's own native handle or process tree. Confirmed
terminal children release slots; unresolved children remain suspect and visible. A reconciliation
command reports the blocking evidence and allows an operator to record a verified end explicitly.
The lead cannot silently free unknown live work to obtain a slot.

Capacity observations remain separate from slots. Fresh limited capacity blocks new work on that
vendor until reset or a fresh observation permits it. Low capacity favors small bounded assignments
or the other vendor. Unknown or stale capacity is not reported as available or exhausted; allow at
most one bounded attempt and learn from its result. Quota/auth errors stop retries and update the
known state. Do not automatically retry across accounts or add paid routes.

## Work status, communication and supervision

Persist an active run record before launch. `aos delegate ls/show` must distinguish running, waiting
for input, completed, failed, timed out and inspection needed, rather than showing only historical
receipts. State updates are atomic and append events with run id and sequence. Stream or checkpoint
progress while the process is alive; do not buffer every observable fact until process return.
Do not treat a quiet model as failed solely because a heartbeat did not arrive.

Extend notes with optional task/run id, recipient actor, message id, reply-to id and acknowledgement.
Preserve existing broadcast notes. Addressed messages are visible only to the intended managed task;
delivery and acknowledgement use the coordination lock and independent per-actor state, so one child
cannot consume its parent's messages. Keep messages compact and preserve references to larger files.
Read-only assignments forbid project artifact changes, but permit the coordination commands to update
that actor's own status, inbox acknowledgements and replies. Prompts must state that limited exception;
it does not grant a worker arbitrary writes to the coordination store or another task's records.

Use native messaging for native children. Across vendors, the lead and worker inspect their addressed
inbox before consequential decisions and receive targeted messages at supported tool boundaries.
If a hook cannot positively identify the actor, it leaves addressed messages unread. Use explicit
inbox commands with the assigned actor identity instead of guessing or replaying a parent's message
to children. A native tool's observed handle or transcript must establish identity outside the lead's
own registry assertion.
Remove blanket delegate suppression only for registered addressed delivery. A PostToolUse hook cannot
wake an idle model or interrupt a running tool, so do not promise immediate arbitrary steering.

A worker needing clarification records a question and enters `waiting-input`. The lead sees it in
the active status/inbox and replies through the same addressed channel. A worker can wait through a
bounded wait command and read the answer at its next safe boundary. No response by the assignment's
deadline returns a blocked result with the unresolved question. Progress and input waits have their
own statuses and must not be misclassified as ordinary output-idle stalls.

The lead launches long delegates through its harness's asynchronous shell facility, keeps working on
independent tasks, and uses bounded status waits when idle. It surfaces meaningful changes, failures
and questions, not repeated unchanged polling. Process cancellation targets the recorded run and
process identity. Resuming a native session is optional until tested on the installed client; a new
attempt with explicit prior context remains a valid fallback. Neither route inherits false success.
Blocked receipt plus re-dispatch is the interim baseline before live exchange is validated. It does
not complete the requested live-cooperation capability, which remains a later required increment.

## Acceptance and review decisions

An accepted execution receipt means the assigned checks and wrapper conditions passed. It is not a
semantic guarantee, a review verdict, or permission to publish. Preserve host verification and the
distinction between observed checks and worker claims. The lead reads the diff, checks scope and
interfaces, integrates and verifies the combined result. Read-only results require source/evidence
assessment appropriate to the task rather than unconditional acceptance of model prose.

Record the separate-review decision and its reason before dispatch, revisiting it when scope or risk
changes. Explicit user requests and consequential auth, money, destructive data changes, migrations,
releases and security work retain independent review. Uncertain assumptions that deterministic checks
cannot discriminate can justify review. Cheap reversible changes with meaningful verification can
skip an additional reviewer. Duration alone and use of a worker are not sufficient reasons to force
cross-review of every output.

Match review to the uncertainty: a focused design challenge, independently authored failing test,
scoped code review or source check can be more useful than a full second implementation. Reuse a
competent independent review already covering the current revision and scope; do not buy the same
review twice merely because two workflow skills fire. Broader integrated changes may need a final
review even if their pieces were checked. Reviewers do not recursively order reviewers.

Update the shared contract, routing guide, vendor-specific guidance, catalog and relevant shared
skills together. The shared user policy must explicitly resolve imported process-skill rules that
otherwise mandate a reviewer per task or the most expensive tier. Leave vendor plugin caches alone.
If review is skipped, report the chosen verification without adding a ceremony to every small task.
When independent reviews run, keep verdicts and reviewer failures separate as the current skill requires.
The small-task live check must also show that the running agent follows this policy precedence and
does not request a redundant reviewer solely because an imported process skill normally requires one.

## Delivery boundaries and validation

Deliver in four verifiable increments, with the later implementation plan defining exact edits:

1. Correct model/effort forwarding and receipts; define selective review and the shared coordination
   skill. This foundation can ship independently, without claiming complete team cooperation.
2. Add minimal actor admission and failure cleanup; verify native identities and the path from native
   output into the assigned worktree. Keep existing task commands compatible.
3. Add live run state and addressed progress/clarification, using blocked/re-dispatch as an interim
   fallback while the native and cross-vendor live paths are validated.
4. Run the cooperation demonstrations, refine defaults from observed results, then sync approved
   shared rules/settings with backups and verify that a second sync changes nothing.

No stage is described as complete merely because instructions were written. Runtime behavior changes
get Pester tests in `tests/aos.Tests.ps1`; meaningful new tests must be seen failing before the fix.
Tests use TestDrive and redirected coordination/config paths, with no real auth, profile or network.
Use the other vendor for failing tests where the resource-safety fix is risky. Run `aos test` under
PowerShell 5.1 and 7, the notes-hook tests, and a bootstrap dry run before applying configuration.
Changes writing into vendor settings get a cross-vendor second opinion before sync.

Required scenarios:

- Both vendor launchers receive explicit model/effort; unsupported explicit settings fail visibly.
- An automatic light-tier substitution is recorded; actual unobserved settings remain null.
- Two concurrent slot requests cannot overbook a vendor; root and nested actors all count.
- Read-only actors count, failed launches release slots, stale heartbeats do not free live workers,
  failed cancellation retains resources, and required setup/claim failures prevent execution.
- Parent and worker receive only their addressed messages; delivery survives retries/restarts without
  losing questions or letting a child consume parent messages. Existing broadcasts still work.
- A worker asks a question, the lead answers, and useful execution continues with recorded evidence.
- Quota, auth failure and an unmet dependency do not produce success or repeated blind retries.
- Concurrent work with a shared interface is rejected as independent or explicitly coordinated;
  verification runs again on the integrated revision.
- A low-risk small task runs inline without delegation or an extra reviewer. A consequential task
  receives the relevant independent check. A change in scope reopens the review decision.
- Before the live fixture, establish eligible native routes from an observed harness handle/status
  or transcript. Self-authored registry rows and worker prose alone do not establish a native child.
- A bounded fixture has fixed acceptance checks requiring distinct artifacts from both vendors and
  at least one suitable native worker. Removing either vendor's contribution must fail a required
  check or leave a required deliverable absent. All fixed acceptance checks must pass after integration.
  Record harness evidence for the native child, actual tiers/models, elapsed time, checks, messages
  and available quota observations. Run the same fixture from the same base with one agent and the
  same acceptance checks; report both results and elapsed times, including coordination overhead.
  Do not claim improved quality, speed or quota efficiency unless the measured comparison supports it.
- Repeat with the other vendor leading. A route without observable native actors is reported as a
  limitation, not counted as a successful enforcement demonstration.

Live checks consume the existing subscriptions and use disposable fixture worktrees. Keep the
existing routes available while rollout evidence is collected. Reverting the new shared policy and
opt-in coordination registration must not require deleting user projects or historical receipts.

## Current capability references and limits

Checked on 2026-10-17: installed CLIs were Codex 0.157.1 and Claude Code 2.1.286. Claude's help
advertises session model and effort flags. Actual native spawn controls must be checked against the
tools in the running session; current documentation includes features newer than the installed CLI.

- [OpenAI subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents): model and effort
  selection and native defaults/caps. Per-session caps are not a cross-vendor global budget.
- [Claude subagents](https://code.claude.com/docs/en/sub-agents): model selection and version-dependent
  effort controls. Per-invocation effort is documented from a version newer than this installed CLI.
- [Claude teams](https://code.claude.com/docs/en/agent-teams): experimental behavior, coordination cost
  and team nesting restrictions. Do not make experimental teams a requirement for basic cooperation.
- [Claude costs](https://code.claude.com/docs/en/costs): subscription usage and token-price estimates
  are different measurements. More workers do not establish a quota saving.

The audit's read-only Claude contribution independently favored existing transport, explicit work
orders and tier routing. Its suggestions to infer live actors from claims, treat model-list position
as a cost tier, or defer clarification until a rerun were not adopted here. They do not satisfy the
observability or live cooperation requirements.
