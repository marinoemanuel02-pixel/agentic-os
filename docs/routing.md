# Routing work between agents

The agent the user starts is the lead. It owns the task breakdown, dispatch choice, integration and
answer. It may delegate automatically within the existing Claude and ChatGPT subscriptions. A user
does not need to approve each bounded assignment separately. Keep a small, reversible task inline;
split substantial work only when parallel progress, a capability advantage, independent reasoning or
capacity can repay startup, context and integration costs.

## Choose effort from the task

| Tier | Use when |
|---|---|
| `light` | The assignment is narrow and has a meaningful check. |
| `standard` | The assignment is ordinary implementation, research or writing. |
| `deep` | The work is ambiguous, difficult to diagnose or consequential. |

The lead considers available vendor tools, context and current capacity. A tier maps through the local
routing configuration and may fall back when unavailable. Model names stay in local routing data.
Priority and tier labels do not establish price, subscription savings or capability; report actual
model and effort only when observed. Unsupported explicit effort or model requests fail visibly.

Use `aos delegate codex|claude --task <file>` for a bounded cross-vendor assignment. Optional flags
are `--tier light|standard|deep`, `--effort <supported-value>`, `--parent <actor-id>` and `--workers 0|1`.
The worker task names its goal, dependencies, allowed files, acceptance checks and return format.
Review [the shared coordination skill](../agents-home/skills/coordination/SKILL.md) for native workers,
actor registration, addressed messages and run status.

## Keep ownership clear

Check semantic dependencies before parallel execution; disjoint file lists alone are insufficient.
Dependent work starts from its accepted prerequisite. One writer owns a checkout at a time, including
coordinators and native workers. Give a native worker exclusive write ownership while its coordinator
reads, or use separate worktrees and collect scoped patches after the writers stop. Only the lead
integrates cross-vendor work. A vendor coordinator may use one reserved native-worker allowance but
cannot start a recursive CLI delegation or another cross-vendor tree.

The configured limit is two active actors per vendor, counting the lead/coordinator and native
workers. It is an admission policy, not a vendor-enforced limit on every native tool. If the route
cannot be observed or capped, report it as cooperative. A registry row alone does not prove a native
tool ran; use the harness's observed handle or transcript. Unknown activity stays unknown.

## Choose review for risk

Use an independent reviewer when the user asks, a mistake could cause consequential harm (auth,
money, destructive data changes, migrations, releases or security), or important uncertainty cannot
be resolved by other checks. The right check may be an independent design challenge, a separately
authored test or a scoped review. Reuse a review of the same revision and scope; do not order duplicate
reviews because multiple workflow skills mention review.

Small reversible work with meaningful tests or other checks can be completed inline without another
reviewer. Imported process skills do not impose a reviewer, approval pause or highest-effort model on
every task. Follow their useful steps when they fit the user request, repository rules and risk.
For review commands and reporting, see the [`second-opinion` skill](../agents-home/skills/second-opinion/SKILL.md).

## Use the other surfaces

- For account capacity, check `/usage` in Claude Code or `/status` in Codex before a long assignment.
- When a subscription limit is near, use the `handoff` skill and continue from `HANDOFF.md`.
- The local `nar` tools can score known options or classify short texts; check samples and treat their
  output as a hint. Pi is a small local model for bounded tasks; check its claims.
- Use `/clear` between unrelated tasks and keep MCP servers few.

## Which surface

| Situation | Surface |
|---|---|
| Thinking aloud, away from the desk | ChatGPT Voice (plain conversation, no repo) |
| Repo work at the desk | Claude Code (terminal or Claude Desktop's Code tab) and the Codex app |
| From the phone, Claude on this PC | Claude app > Code: sessions from the Claude desktop app (Remote Control is on for new sessions), or new ones while `aos remote` runs on the PC |
| From the phone, Codex on this PC | ChatGPT app > Codex, after pairing once in the Codex app (Settings > Connections > Control this PC) |
| From the phone, PC off | Claude Code cloud session or Codex cloud task on a GitHub repo (sees only what was pushed) |
| From the phone, message-style | Claude Code Channels (Telegram/Discord) into a running session |
| Scheduled or recurring | Claude Code routines / Desktop scheduled tasks; Codex automations |
| Research to keep | either chat app's research mode, results saved into the KB `inbox/` |

A surface that can only see what was pushed (ChatGPT with a GitHub connector, Codex cloud)
does not warn you when its copy is stale. Push before you ask it about recent work.
