---
name: handoff
description: Write HANDOFF.md so another session - often the other vendor (Claude Code or Codex) - can continue this work cold, from files alone. Use when a usage limit is near or hit, when switching vendors, before ending a long session, or when the user says "hand off", "handoff", "switch to codex", "switch to claude", "save state", "out of tokens", "hit the limit". Not for describing finished work (that belongs in the commit message or PR).
---

# Handoff

Goal: the next agent resumes from `HANDOFF.md` alone, with no chat history.

## Steps

1. Find the root: `git rev-parse --show-toplevel`. If this is not a git repo, use the current
   directory and say so in the file.
2. Record the state. Do not commit, stash or reset anything on your own:
   - `git branch --show-current`
   - `git status --short`
   - `git log --oneline -5`
   - `git diff --stat` and `git diff --staged --stat`
3. Check who holds the checkout: `aos who`. If another live session (not yours) holds it, do not
   touch its `HANDOFF.md`: leave `aos note "<handoff summary>" --as <claude|codex>` instead and tell
   the user. A scheduled or background run that finds the checkout held stops here.
4. Write `HANDOFF.md` at the root, replacing any previous one, with exactly these sections:
   - **Goal** — the request in the user's words, and what "done" means.
   - **State** — branch; what is committed; what is uncommitted (from step 2); what works right now.
   - **Verified** — commands you actually ran in this session, with their result. Nothing else.
   - **Not verified** — assumptions, checks you did not run, open questions. Write "none" only if true.
   - **Next steps** — numbered, smallest first, with exact commands and file paths.
   - **Traps** — what wasted time: flaky tests, wrong paths, environment quirks.
   - **Written by** — vendor and local date/time, e.g. `Claude Code, 2026-09-27 18:40`.
   For managed coordination work, also use `aos coord checkpoint save <id> --repo . --task <id>
   --next-check <check>` and link its JSON from **State**. Run `aos coord checkpoint check <id>
   --repo .` before continuing. It preserves tracked content and detects drift, but required
   untracked/ignored files need separate preservation. Active actors require inspection; a checkpoint
   never establishes that they stopped. Retain the source checkout until recovery is verified.
5. Check it: re-read the file. Every line under **Verified** must match a command you ran in this
   session. Delete any that don't. No secrets, tokens or `.env` contents anywhere in the file.
6. Tell the user how to resume, in one short block:
   - In Codex (CLI or app, same folder): `Read HANDOFF.md and continue from Next steps.`
   - In Claude Code (same folder): `Read HANDOFF.md and continue from Next steps.`
   - From Claude Code, the user can also type `/codex:transfer` (a user-only command) to move the
     session into Codex. Write HANDOFF.md anyway, so the state survives whichever route is taken.

## Failure modes

- Not a git repo: skip the git commands, list changed files by hand, and say so under **Not verified**.
- Nothing left to do: say so plainly; don't invent next steps.
- If `HANDOFF.md` is not wanted in history, suggest adding it to `.gitignore`. Don't add it yourself.

## Log

- 2026-09-27 — created with the agentic-os setup.
