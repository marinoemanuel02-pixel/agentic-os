# Coordinating coding agents across vendors: research as of 2026-10-01

Undated official doc pages are marked "accessed 2026-10-01". I read only what is cited here. Star counts come from the GitHub pages on that day.

## 1. Coordination on one machine (boards, mail, leases, presence)

**Widely adopted**
- **Worktree-per-session is the baseline isolation.** Claude Code's docs say worktrees give "each session a separate git checkout". Agent view moves dispatched sessions into their own worktree before they edit. Agent teams do NOT isolate teammates, so you must split the files between them (https://code.claude.com/docs/en/agents, accessed 2026-10-01). Third-party GUIs build on the same idea:
  - Conductor: Mac-only; paid cloud tier (https://continuumcode.ai/guides/what-is-conductor/, 2026).
  - Claude Squad: 8.6k stars; needs tmux, no stated Windows support (https://github.com/smtg-ai/claude-squad).
  - Crystal: deprecated Feb 2026 and replaced by Nimbalyst (https://github.com/stravu/crystal).
  - vibe-kanban: 28.2k stars, now "sunsetting". Bloop shut down; the app went local-only and community-maintained (https://github.com/BloopAI/vibe-kanban; https://www.vibekanban.com/blog/shutdown).
  - uzi: 583 stars, tmux-based; I could not confirm recent activity (https://github.com/devflowinc/uzi).
  - container-use: "Experimental", **needs Dagger/Docker** (https://github.com/dagger/container-use).
- **Beads (`bd`)**: a git-backed issue graph for agents. It has 27.6k stars and v1.3.1 shipped 2026-09-30, with Windows amd64/arm64 binaries (https://github.com/steveyegge/beads/releases).
  - Commands: `bd ready` (unblocked work), `bd update <id> --claim` (atomic claim), `bd close`, `bd prime`.
  - Hash IDs avoid merge collisions. `bd setup claude` and `bd setup codex` install hooks. It also has a Dolt backend (https://github.com/steveyegge/beads).

**New / experimental**
- **MCP Agent Mail** (Python, 2.2k stars; last commit 2026-09-29) (https://github.com/Dicklesworthstone/mcp_agent_mail/commits/main).
  - Agents get identities and inboxes, and can take advisory **file leases** on globs with a TTL. An optional pre-commit guard blocks commits that conflict with an exclusive lease.
  - Storage is a Git archive plus SQLite. It works with Claude Code and Codex.
  - Commit of 2026-09-22: "deliver Codex reminders through PostToolUse hooks".
  - **Flags:** needs Python 3.14 via uv. The installer is `curl | bash`, and it also installs Beads Rust and other tools.
  - A Rust rewrite has a Windows zip and PowerShell installer. It claims fixes for git-lock and SQLite contention. It has 180 stars and an "MIT+Rider" license (https://github.com/Dicklesworthstone/mcp_agent_mail_rust).
- **Claude Code cross-session messaging** (https://code.claude.com/docs/en/cross-session-messaging, accessed 2026-10-01).
  - Requires v2.1.234+ on native Windows. Transport is a per-session named pipe, discovered with `ListAgents` / `/peers`.
  - `notify_when_idle` asks for one notice when another session goes idle (12 h expiry).
  - The receiver treats peer messages as non-consent. `claude -p` workers bind an inbox too.
  - **Claude-only**, but a script can post to `CLAUDE_CODE_MESSAGING_SOCKET` with the session token.
- **Agent teams**: a shared task list where claims use file locks, JSON mailboxes in `~/.claude/teams/{name}/inboxes/`, and `TaskCompleted` / `TeammateIdle` hooks that can block (exit 2).
  - Still experimental, with no resume.
  - Spawning needs an interactive session: it does not work from `-p` or the SDK.
  - Docs suggest 3-5 teammates (https://code.claude.com/docs/en/agent-teams, accessed 2026-10-01).
- **Codex** added an "in-memory agent message board for ephemeral sessions" and multi-agent spawn-failure metrics on 2026-09-29 (https://learn.chatgpt.com/docs/changelog).

**Gap:** I found no cross-vendor "presence" standard. The candidates are Agent Mail (identities plus leases) and Beads claims (assignee plus status). Neither stops a scheduled job unless that job checks them first.

## 2. Delegation protocols and receipts

- **`codex exec --json`** emits JSONL events: `thread.started`, `turn.completed` (with `usage`: input, cached and output tokens), `turn.failed` and `error`. Related flags (https://learn.chatgpt.com/docs/non-interactive-mode, accessed 2026-10-01):
  - `--output-schema schema.json -o result.json` forces a final answer in a schema you define.
  - `--ephemeral`, `--ignore-user-config`, `--skip-git-repo-check`.
  - `codex exec resume <id>`.
- **`claude -p --output-format json`** returns `is_error`, `subtype`, `session_id`, `total_cost_usd` and `usage`. **Caveat:** open bug #79500 (2026-07-20). A rate-limit API error comes back as `subtype:"success"` with `is_error:true` and **exit 0** (https://github.com/anthropics/claude-code/issues/79500). Wrappers must check `is_error` and zero tokens, not the exit code.
- **Model preflight is unsolved upstream.** Codex returns HTTP 400 "model is not supported when using Codex with a ChatGPT account" without saying why. Issue #49396 (2026-09-29, open) notes there is no per-account model-list check (https://github.com/openai/codex/issues/49396). Plus accounts lost the 5.2 / 5.3-codex models in June 2026 (https://www.thinkfacility.com/errors/codex-model-is-not-supported-when-using-codex-with-a-chatgpt-account/). Practical preflight is a tiny `codex exec` probe on the pinned model with a short timeout.
- **openai/codex-plugin-cc** (33.7k stars): `/codex:rescue`, `status`, `result` and `cancel`, with job records on disk. It wraps the Codex app server and has an optional stop-time review gate (https://github.com/openai/codex-plugin-cc; launched 2026-03-30 per https://the-decoder.com/openai-launches-a-codex-plugin-that-runs-inside-anthropics-claude-code/).
- **`codex mcp-server`** exposes the tools `codex` (prompt, model, sandbox, approval-policy, cwd) and `codex-reply` (threadId) (https://cookbook.openai.com/examples/codex/codex_mcp_agents_sdk/building_consistent_workflows_codex_cli_agents_sdk). Community bidirectional bridges exist, e.g. Dunqing/claude-codex-bridge (https://github.com/Dunqing/claude-codex-bridge). Their maturity is unverified.
- **MCP 2026-07-28 spec** (final 2026-07-28) adds the official **Tasks** extension: a durable task handle with `tasks/get`, `tasks/update` and `tasks/cancel` (https://blog.modelcontextprotocol.io/posts/2026-07-28/). A 2026-08-08 talk title is "Why aren't any agents supporting them?" (https://www.sean-weldon.com/blog/2026-08-08-mcp-tasks-async-why-arent-any-agents-supporting-them-cornelia-davis-temporal). **Treat client support as thin.**
- **ACP** is editor-to-agent. Adapters exist for Claude Code (claude-agent-acp) and Codex (codex-acp). Zed and JetBrains run an ACP Registry (Jan 2026) (https://zed.dev/blog/acp-progress-report). ACP is not built for agent-to-agent delegation.
- **A2A** reached v1.0 in Jan 2026 under the Linux Foundation. It is enterprise and cross-organization; I found no local coding-agent use (https://opensource.googleblog.com/2026/04/a-year-of-open-collaboration-celebrating-the-anniversary-of-a2a.html). Overkill here.

## 3. Swarms and subagents

- **Anthropic research system:** multi-agent used about 15x the tokens of chat, and token usage explained 80% of performance variance. Subagents return condensed summaries and write their outputs to external storage (https://www.anthropic.com/engineering/multi-agent-research-system, 2025-06-13).
- **Cognition (2026-04-22):** what works is "multiple agents contribute intelligence … while writes stay single-threaded". The shape is map-reduce-and-manage. A clean-context reviewer catches about 2 bugs per PR. Small models still can't tell when to escalate (https://cognition.com/blog/multi-agents-working).
- **Codex subagents** inherit the parent's sandbox. They are capped by `agents.max_concurrent_threads_per_session` (legacy name `max_threads`), and the docs warn they "consume more tokens" (https://learn.chatgpt.com/docs/agent-configuration/subagents, accessed 2026-10-01).
- **Claude:** use subagents when only the result matters. Dynamic workflows and `/batch` (5-30 worktree subagents) are for large migrations (https://code.claude.com/docs/en/agents).
- **ruflo / claude-flow** (73.6k stars, 687 open issues) claims "swarms" and "self-learning". Its benchmarks measure cold start and RSS, not task success (https://github.com/ruvnet/claude-flow). **I found no evidence it helps under quota limits.**

## 4. Small local model

- Routing paper (2026-03-26): Qwen2.5-3B reached 0.783 exact-match routing accuracy. **No model met the 0.85 viability bar** (https://arxiv.org/abs/2604.02367).
- Agent Skill Framework (rev. 2026-06-18): "very small models struggle with reliable skill selection"; models of 30-80B benefit (https://arxiv.org/abs/2602.16653).
- Cognition: the escalation judgment of smaller models is unsolved (link above).
- **Conclusion:** a 4B model can pre-sort, tag, summarize logs and draft. Its output must be a hint that a deterministic check or a cloud model confirms. It should not pick a model, a target, or whether something passed.

## 5. Handoff and memory

- **AGENTS.md** went to the Linux Foundation's Agentic AI Foundation alongside MCP. It is in 60k+ repos (https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation, 2025-12-09).
- **Agent Skills (SKILL.md)** is an open standard adopted by Claude Code, Codex, Gemini CLI, Cursor, and **pi** (https://agentskills.io, accessed 2026-10-01).
- **Anthropic long-running harness:** a `claude-progress.txt` progress file, a JSON feature list with `passes` booleans, `init.sh`, and git commits. Each session starts by reading the git log and the progress file and running a smoke test (https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents, 2025-11-26).
- **Amp** replaced compaction with "handoff" to a fresh thread (2026-01) (https://ampcode.com/news/handoff). A search summary says it later went back to compaction around 2026-05; **I did not verify that.**

## Recommended practices for this setup

1. **A wrapper script, `aos delegate`, with a receipt for every run.** It calls `codex exec --json --output-schema receipt.schema.json -o receipt.json`, or `claude -p --output-format json`. It appends one JSONL line to a ledger: task, vendor, model, worktree, exit status, `is_error`, tokens or `total_cost_usd`, duration, and test result. It decides failure from `is_error`, `turn.failed` and zero tokens, never from the exit code (bug #79500). Fixes failure (4).
2. **Preflight before dispatch.** Run a cached cheap probe (one-line `codex exec` on the pinned model, about 30 s timeout). It must also confirm that the test command exists inside the delegate's sandbox, for example `--sandbox workspace-write` plus a `which <tool>` step. Fail fast with the reason. Fixes (1) and (2). Upstream gives no model-list API, so the evidence is thin.
3. **One worktree per delegated run, with writes kept single-threaded.** Delegates write only in their own worktree or branch, and one session merges. This is backed by both Claude's docs and Cognition. Fixes part of (3).
4. **Leases and presence before writing shared files (HANDOFF.md etc.).** Lightest option: a lock file with a TTL (owner, session, expiry) checked by a hook and by scheduled jobs. Heavier option: Agent Mail Rust for `file_reservation` plus inboxes across Claude and Codex. Pilot it before relying on it: 180 stars and a nonstandard license. Fixes (3).
5. **Turn HANDOFF.md into a structured, append-only ledger.** Use a `progress.jsonl` or Beads issues (`bd ready` / `--claim`) in place of a free-form file that agents overwrite. This follows Anthropic's progress-file and feature-JSON pattern, and Beads has Windows binaries and Codex/Claude setup.
6. **Treat local-model output as advisory, and verify it.** The `nar` result is logged as a hint with its score. An action needs a deterministic check (tests, schema, `git diff`) or cloud-model confirmation. Fixes (5).
7. **Cap concurrency at 2 per vendor, and use parallelism for reading, not writing.** Use reviewers and researchers in clean context. Leave agent teams off: they are experimental, have no resume, and don't work from `-p`.
8. **Don't adopt A2A, swarm frameworks (ruflo), or Docker sandboxes (container-use)** now. They cost setup and quota for no evidence of benefit here. Revisit MCP Tasks once Claude Code and Codex clients support it.
