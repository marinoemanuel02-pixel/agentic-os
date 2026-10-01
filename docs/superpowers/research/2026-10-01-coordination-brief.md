# Research brief: coordinating coding agents across vendors (as of October 2026)

Context. One Windows 11 PC runs three agents on the same repositories:
- Claude Code (Anthropic; desktop app and CLI; has subagents, agent teams, hooks, skills, MCP, plugins),
- Codex (OpenAI; desktop app and `codex exec` CLI; has subagents/multi-agent, skills, MCP, automations, sandbox),
- Pi, a small open-source coding harness running a local 4B model through Ollama (16K context).
A phone talks to them through Paseo (a daemon that runs these CLIs as sessions). Both cloud vendors are on
entry subscriptions with 5-hour and weekly limits, so quota is scarce. Shared state today: an AGENTS.md
contract, a shared skills folder, a HANDOFF.md file, git branches/worktrees, and an MCP server ("nar") that
scores options with the local model.

Observed failures to solve: (1) a delegated Codex run failed on a model the account cannot use, with no
preflight; (2) the delegate could not run the tests it wrote (sandbox lacked the tool); (3) a scheduled
agent rewrote HANDOFF.md while another agent's live session was working in the same repo, neither knowing
of the other; (4) delegation is hand-typed shell commands with no record of result, cost or failure;
(5) a weak local model's confident pick was relayed without verification.

Find the CURRENT best practices and concrete open-source projects (last ~6 months matter most) for:
1. Cross-agent / cross-vendor coordination of coding agents on one machine: shared task boards or issue
   trackers for agents, mailboxes/messaging between agents, file reservations/leases/locks, presence
   ("who is working where"), and how they avoid clobbering each other (worktrees, branch-per-agent, etc.).
2. Delegation protocols: how one agent hands a task to another and gets a structured, verifiable result
   back (task spec format, result/receipt format, exit status, cost/usage accounting, timeouts, retries,
   model/quota preflight). Include Claude Code <-> Codex specifically (plugins, MCP bridges, `codex exec`
   / `claude -p` wrappers, `codex mcp-server`, Agent Client Protocol (ACP), A2A).
3. Swarms / subagent teams: when parallel subagents help vs hurt, orchestrator-worker patterns, how
   leading teams keep context small, how results are merged, and how to cap concurrency under quota.
4. Using a small local model inside such a system: what jobs it is reliably good for (routing, triage,
   classification, summarizing logs) vs what it should never decide; verification patterns.
5. Handoff and memory between sessions/vendors: what formats and conventions are converging (AGENTS.md,
   skills/SKILL.md standard, handoff files, structured progress ledgers).

For every claim give the source URL and its date. Prefer primary sources (official docs, changelogs,
repos with recent commits, engineering blog posts by Anthropic/OpenAI/known practitioners). Name repos with
their star count or activity level if visible. Separate "widely adopted" from "new/experimental".
Flag anything that needs Docker, a paid service, or large downloads.

End with: the 5-8 practices most applicable to the setup above, each with the concrete mechanism you would
adopt (tool, file format, or protocol) and why. Be concrete and skeptical; say when evidence is thin.
Keep the whole report under ~1500 words.
