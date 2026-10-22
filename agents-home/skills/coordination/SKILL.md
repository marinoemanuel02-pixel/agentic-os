---
name: coordination
description: Route work across Claude and Codex, native workers, and task status when delegation or shared run coordination can help.
---

# Cooperative coordination

The agent the user starts is the lead. It owns the goal, chooses the work split, integrates results,
and gives the user one verified answer. It may delegate automatically within the existing
subscriptions; do not ask for a separate delegation decision on every task.

Before a task that both vendors will work on, run `aos ready <repo>`: it fails on a limited vendor, a full
actor cap, a checkout another session holds or task paths that cannot resolve, and warns on stale capacity
or commits that exist only on this machine. Fix or re-split first. While a worker runs, keep watching your
inbox (`aos coord inbox <lead-id>`): a question waits at most 45 seconds twice before the worker returns
`blocked`.

## Choose the route

Keep a small, reversible task inline when one agent can finish it efficiently. For substantial work,
split only when parallel progress, a capability advantage, independent reasoning or capacity can
repay startup, context, communication and integration costs. Record short tasks, owners, dependencies,
acceptance checks, write scope and review choice. Check semantic dependencies before running work in
parallel; a file list alone does not prove independence.

Use `light`, `standard` or `deep` for task requirements. Light is narrow and has a meaningful check;
standard is ordinary work; deep is for ambiguity, difficult diagnosis or consequential reasoning.
The route is resolved from available vendor options. A fallback is recorded. Tiers, priority labels
and model choice do not prove lower cost or quota savings. Report model or effort as unknown unless
the runtime observed it. Local tier overrides live in `~/.aos/routing.json` (or `AOS_ROUTING`),
for example `{"claude":{"light":{"model":"<account-supported-id>","effort":"low"}},"codex":{}}`.
An unmapped tier uses the standard/default route with cost unknown. Native tools choose their own
supported model option; do not assume the CLI map configures a native child automatically.

Dispatch the other vendor with `aos delegate codex|claude --task <file>`, adding `--tier light|standard|deep`,
`--effort <supported-value>`, `--parent <actor-id>` and `--workers 0|1` when needed. `--workers` reserves
the coordinator's one native-child allowance; it is not a recursive CLI delegation allowance. Each
vendor has at most two active actors, including its lead/coordinator and native workers. A busy
reservation means wait for a state change, choose another eligible route, or continue inline; do not
retry immediately.

Each checkout has one writer at a time, including coordinators and native children. For native work,
choose one output path: hand the worker exclusive write ownership while the coordinator reads, or give
workers separate worktrees and collect scoped patches after they stop. Only the lead integrates
cross-vendor work. A delegated CLI worker cannot launch another CLI delegate or create another
cross-vendor tree. Keep read-only workers read-only for project files; their assigned coordination
commands may update their own status and messages.

For a native worker, reserve its actor before launch, then use the harness's spawn/Agent tool with
an explicit supported model from the local tier map or current account allowlist. A full-context
fork normally inherits the parent's settings; use a fresh bounded brief when selecting a lighter
worker. If the tool cannot override the model, report inheritance and choose another eligible route
when that cost matters. Claude's per-worker effort is version/tool dependent; use it only when the
installed schema exposes it. Do not replace native tools with a recursive CLI call.
Record the returned handle with `observe --handle <handle> --evidence <tool-call-or-transcript-ref>`;
after the harness confirms termination, `finish --evidence <completion-ref>` frees that allowance.
The coordinator must relay these observations to the host when its own metadata route is read-only.
Do not finish a coordinator while a launched child remains unconfirmed.

## Bounded free API candidates

For small supplied-context work with a cheap objective check, consider the shared API pool
before consuming a native worker slot: `python tools/stack.py swarm accounts` from the setup
repo shows admitted accounts/capabilities. Use `swarm task --packet <json> --output <new-json>`
for one task, or `submit`/`drain` for independent work. Keep trivial work inline and use native
agents for repository edits and consequential reasoning. Read `docs/swarm.md` for packet fields.

Both vendors use the same scheduler and ledger. It owns API identities, quota reservations,
account/provider concurrency, bounded failover and cancellation; do not fabricate a native
vendor or reserve an API account as a Claude/Codex actor. An account key is not a new quota
bucket unless the provider/account/project allocation establishes independence. The OmniRoute
alias shares its upstream account's allowance. Never assume a free route from authentication.

Candidates stay unaccepted until a lead-authored verifier runs. Dependent pool tasks require
host acceptance and current hashes. For existing registered task contracts, use `swarm contract
<id> --repo <checkout> --cloud-allowed --owner-session <claim-session>`: the host verifier reads
`AOS_SWARM_CANDIDATE`, validates/publishes declared artifacts, and the bridge writes the normal
host receipt. Explicit context ranges supply prior artifact content. Keep the checkout claim
with the host; API candidates never get tool or filesystem access. Do not execute worker-written
verification commands or treat model text as coordination events.

Embedding/reranking, supplied-source research preparation, PNG/JPEG questions and authorized
short WAV transcription use the same route. Pin embedding account/model space; check speech,
image facts and source support. Local/private routes remain local. Inspect status and attempt
receipts on failure; expired billing-disabled attestations need operator renewal. No paid fallback.

## Actors, messages and runs

The actor registry organizes cooperative work; an actor id is routing metadata, not a security boundary
against a local process. Reservation is an assertion, not proof a native worker ran. Use the harness's
observed native tool handle or transcript as evidence of native work. Unknown activity stays unknown.

Register the lead before its first managed dispatch, then reserve each child under that lead and task.
`aos coord reserve <id> --as <codex|claude> --task <task-id> [--parent <id>] [--kind <lead|delegate|native>] [--workers 0|1]`
reserves actors. `aos coord observe <id>` records a state; `aos coord finish <id>` records completion.
`aos coord actors` lists actors and `aos coord reconcile` reports reconcilable states. These commands
return JSON. Use `aos coord status <id>` to read run state and `aos coord cancel <id>` to request
cancellation; a request does not establish that a process has stopped.

Address messages within the same task tree. `aos coord send <from-id> --to <recipient-id> --text <text>`
sends one message; add `--reply-to <message-id>` for a reply between the same actors. `aos coord inbox
<id>` reads addressed messages, `aos coord ack <id> --ack <message-id>` acknowledges one explicitly,
and `aos coord wait <id> --seconds 45` waits for at most 45 seconds. Reading does not acknowledge.
Do not guess an actor identity or read a parent's inbox as a child.

Keep messages short and link to larger artifacts. A question should identify the missing decision or
fact and the worker should enter `waiting-input`; the lead replies to that actor. The wait command is
bounded and does not wake an arbitrary idle model or interrupt a running tool. Check status at safe
tool boundaries and avoid repeated polling when nothing changes.

Supervised CLI workers use the injected actor/run identity and `tools/coord.ps1` supplied in their
prompt. With `AOS_COORD_TRANSPORT=stdout`, `question --to <parent> --text <question>` emits a narrow
metadata request; the host handles it after the tool call completes. Finish that call before using
`wait --seconds 30` in another call, then explicitly `ack --ack <id>` and
`status --state running --text <progress>`. Inbox/status reads take no write lock. Return `blocked`
after a bounded unanswered wait. This route does not inject text into arbitrary idle model sessions.
Native workers use their harness's messaging tools; the coordinator relays cross-vendor questions.
If a sandbox prevents the helper or inbox read, report that blocked route and rerun with the supplied
answer; do not weaken the project sandbox. Check actual route coverage before promising live exchange.

## Review and verification

The lead chooses review according to risk and uncertainty, then records why. Keep independent review
for user-requested checks and consequential auth, money, destructive data changes, migrations,
releases or security work. Review can also help when important assumptions cannot be checked another
way. A small reversible change with meaningful tests or other checks can stay inline without an extra
reviewer. Reuse a competent review of the same revision and scope; do not run duplicate reviews just
because two workflow skills recommend them.

Imported process skills guide the work but do not impose a reviewer, approval pause or highest-effort
model on every task. Apply their steps when they fit the request and the risk. User instructions,
repository requirements and the risk-based rule above determine when review or approval is needed.

The lead reads and verifies each result, checks scope and dependencies, integrates changes, and runs
the relevant acceptance checks on the combined result. A host receipt is evidence that its checks ran,
not a semantic guarantee or permission to publish. Report actual checks, failed or unavailable routes,
and unknowns. Do not claim savings without observed model and comparison evidence.

## Checked tasks and reusable evidence

For dependent or repeatable work, add `--contract <json>` to delegation. Use `aos coord task
register|ready|packet` to register and inspect the bounded input. A dependent task needs accepted
host receipts and matching artifacts already integrated in its checkout. A task id is stable across
failed retries; each attempt gets a new run id. Unknown/stale evidence blocks dispatch.

Use `aos coord capabilities` before choosing native controls. Managed `aos-explore`, `aos-implement`
and `aos-verify` roles come from local routing; unsupported settings are omitted. Pass supported
settings explicitly through the native harness. Codex native turn budgets are advisory. Claude
lifecycle hooks can establish identity and termination only for a matching reserved child; hooks
observe launch and do not enforce pre-launch admission. Preserve an unconfirmed child's allowance.

`--transport app-server` is an optional Codex CLI route with ChatGPT authentication and exact active
turn steering (`aos coord steer`). Keep `exec` as the ordinary route. A partial or interrupted turn
never counts as accepted work. The host still verifies scope, output and completion.

Read `aos coord report` to assess comparable task classes, failures, timing and unknown usage.
After integration, use `aos coord annotate` for corrections and measured integration/review time.
Do not tune from one successful run. The six-case `tools/coordination-eval.ps1` prepares without
model calls; explicit execution needs selected cases and an active parent, within existing capacity.

Before a long continuation, commit required source and use `aos coord checkpoint save|check` along
with `handoff`. Check tracked-file preservation and inspect live actors before resuming. Keep
necessary ignored/untracked material separately. Never archive the only recovery source on the
strength of an untested snapshot. `aos coord procedure save|list` promotes scoped reusable guidance
only with two distinct host-verified successes; stale or contradicted guidance is not retrieved.
See `docs/coordination-tuning.md` in agentic-os for contract fields and exact command examples.

After a quota interruption, follow `handoff` and use `aos coord continuation check <checkpoint-id>
--repo . --from <vendor> --to <other-vendor>` before reserving the receiver. This checks cold state
and observed capacity without dispatching, changing receipts or releasing unresolved work.
