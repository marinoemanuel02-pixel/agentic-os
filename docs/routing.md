# Routing: which agent, which surface

Tuned for Claude Pro + ChatGPT Plus (both entry plans, each with a 5-hour and a weekly limit).
Defaults, not laws: say "claude only" or "codex only" and they yield.

## Which vendor

| Work | Default | Why |
|---|---|---|
| Unclear goal, design, architecture | Claude Code (plan mode) | judgement-heavy; plan first, code later |
| Debugging that spans many files | Claude Code | holds more of the repo in view |
| Writing, docs, the knowledge base | Claude Code | the KB's skills live on the Claude side |
| Well-specified implementation | Codex | saves Claude's window for judgement |
| Tests, mechanical refactors, renames | Codex (`--profile quick` for trivial ones) | cheap, checkable work |
| Review of anything risky | the other vendor | independence is the point |
| Long or background runs | Codex app worktree or Codex cloud | runs while you do other things |

## The patterns that pay for the second subscription

1. **Cross-review.** The builder never reviews its own work alone. You type `/codex:review` in
   Claude Code (a user-only command; Claude itself uses `codex exec --profile review`), or
   `$cc:review` in Codex. Report both verdicts side by side (the `second-opinion` skill).
2. **Split authorship.** For a risky fix, the other vendor writes the failing test
   (`/codex:rescue write a failing test for ... - don't fix it`), then this one fixes it.
   A test written by whoever wrote the fix tends to pass either way.
3. **Plan critique.** For anything over about an hour, write the plan to a file and have the
   other vendor attack it before any code exists (you type `/codex:adversarial-review`, or ask
   Claude for a second opinion on the plan file).
4. **Failover.** A limit is a handoff, not a stop: `handoff` skill, then the other agent
   continues from `HANDOFF.md`. From Claude Code, `/codex:transfer` also works.
5. **Review gate (optional).** `/codex:setup --enable-review-gate` makes Codex review before
   Claude finishes a turn. Strong, but it spends Codex quota on every turn; turn it on for
   risky repos only.

## Stretching two entry plans

- Check before big work: `/usage` (Claude Code), `/status` (Codex).
- Strongest model or high effort for planning and review; defaults for routine edits.
  In Codex: `--profile deep` to plan, `--profile quick` for mechanical edits.
- At most 2 parallel agents per vendor. Every agent carries the full context preamble, and
  fan-out burns the 5-hour window before any real work happens.
- `/clear` between unrelated tasks; subagents for broad searches; keep MCP servers few.
- Push long, well-specified tasks to Codex cloud (it runs off your machine and your Claude window).

## Which surface

| Situation | Surface |
|---|---|
| Thinking aloud, away from the desk | ChatGPT Voice (plain conversation, no repo) |
| Repo work at the desk | Claude Code (terminal or Claude Desktop's Code tab) and the Codex app |
| From the phone, into a running local session | `claude --remote-control "<name>"` on the PC, then the Claude app > Code |
| From the phone, message-style | Claude Code Channels (Telegram/Discord) into a running session |
| From the phone, Codex | ChatGPT app > Codex (cloud tasks on GitHub repos) |
| Scheduled or recurring | Claude Code routines / Desktop scheduled tasks; Codex automations |
| Research to keep | either chat app's research mode, results saved into the KB `inbox/` |

A surface that can only see what was pushed (ChatGPT with a GitHub connector, Codex cloud)
does not warn you when its copy is stale. Push before you ask it about recent work.
