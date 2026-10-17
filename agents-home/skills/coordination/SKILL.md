---
name: coordination
description: Route work across Claude and Codex, native workers, and task status when delegation or shared run coordination can help.
---

# Cooperative coordination

The agent the user starts is the lead. It owns the goal, chooses the work split, integrates results,
and gives the user one verified answer. It may delegate automatically within the existing
subscriptions; do not ask for a separate delegation decision on every task.

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
the runtime observed it. Local tier overrides live in `~/.aos/routing.json` (or `AOS_ROUTING`), as
`{"claude":{"light":{"model":"<account-supported-id>","effort":"low"}},"codex":{...}}`.
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
