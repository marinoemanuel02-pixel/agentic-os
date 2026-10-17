# Global agent contract

Loaded by both agents on every session: Codex reads a synced copy at `~/.codex/AGENTS.md`,
Claude Code imports it from `~/.claude/CLAUDE.md`. The source is `agents-home/AGENTS.md` in the
agentic-os repo — edit it there, then run `aos sync`. A project's own `AGENTS.md` adds to this
file and wins where the two conflict. Keep this file short: every line costs tokens on every
request, on both subscriptions.

## The machine

- Windows 11, native (not WSL). Shells: PowerShell 7 (`pwsh`) and Git Bash. Quote paths with
  spaces. Prefer PowerShell for Windows-specific work.
- Encoding: when a script shells out or prints non-ASCII text, set UTF-8 explicitly (Python:
  `encoding="utf-8", errors="replace"` on `subprocess.run` and stdout). This has broken scripts here.
- Line endings: let `.gitattributes` decide. Don't rewrite CRLF/LF in lines you didn't change.
- Home base is the Desktop (`C:\Users\marin\OneDrive\Desktop`, synced by OneDrive): `agentic-os\`
  is this setup, active projects live in `1-Projects\` (`aos new <name>` creates them there).
  Keep heavy caches out of it where you can (clones, model files, large media); OneDrive uploads everything.
- The Claude and Codex desktop apps are MSIX packages: a new file or folder that they, or anything
  they launch, create under `AppData` can stay private to that app. Put tools, clones and worktrees
  under the home folder (`~\.local\bin`, `~\.npm-global`, `~\.aos`), never under AppData.
- `D:` holds archives and backups (`legacy\`, `PC backup ...`). Open them only when a task needs
  them; write there only when asked.
- Local model: Ollama on this laptop (`aos install local`; the tag is in agentic-os `config/local.json`).
  Private and offline, much weaker than the cloud models. The `nar` MCP tools score options in one pass
  of it: use them for choices among known alternatives, then report the real outcome with `nar_feedback`.
  To sort many short texts by topic or type before spending cloud tokens, `nar classify --backend embed` (or
  `nar_classify`) labels up to 50 per call; its labels are hints, so check a sample first. It keeps item text in
  `~/.aos/nar`: never pass secrets.

## How to work

1. Read before you change. If the request is ambiguous, ask one precise question instead of guessing.
2. Make the smallest change that solves the problem. No speculative abstractions, drive-by
   refactors, or reformatting of code you didn't touch.
3. Define "done" as something checkable, then check it: run the test, build or linter. A new test
   must be seen failing without the fix before its pass means anything.
4. Never edit the tests you are being measured by to make them pass.
5. Report exactly what you ran, what passed, and what you skipped and why. "Nothing found" is a
   valid result — don't pad it. A crashed tool or unreachable reviewer is a failure, not a clean result.
6. Commit early, on a branch. Uncommitted work that exists on one machine is the cheapest loss to prevent.
7. Never write secrets into files, commits, logs or chat. Keys live in the Windows secret store
   (`aos secret`). If you see a secret in plaintext, say where — don't repeat it.
8. Don't store absolute paths in repos; resolve them at run time (`git rev-parse --show-toplevel`).

## Writing about the operator's own material

- Describe; don't coin names. A label he never used must not enter his notes as his vocabulary.
- A summary never outruns its source: summarize only text that exists and that you actually read.
- Unknown stays unknown: write null or "not found", never a plausible guess.

## Two vendors, one workflow

Both are on entry plans (Claude Pro, ChatGPT Plus), each with a 5-hour and a weekly limit. The
second vendor is for **independence** (a reviewer that doesn't share your blind spots) and for
**capacity** (keep working when one limit is hit).

The lead agent owns the result and decides when another worker is useful. Keep small, reversible
work inline; split only when parallel work, a tool advantage, independent reasoning or capacity can
repay startup and integration cost. Choose light, standard or deep effort from the task, and let each
vendor's available tools and subscription limits shape the route. No model tier promises savings.
Keep at most 2 active actors per vendor, including coordinators and native workers.

**Second opinion** — run the `second-opinion` skill when being wrong is expensive (auth, money,
data, migrations, deletes, releases, security) or when no test could catch the mistake.
- From Claude Code, the agent itself: `codex exec --profile review "<prompt>" </dev/null` (read-only
  review; without `</dev/null` it waits for stdin in Git Bash), or
  `/codex:rescue <task>` / the `codex-rescue` subagent to hand Codex a task. `/codex:review` and
  `/codex:adversarial-review` are user-only commands: suggest them to the user, don't try to call them.
- From Codex: `$cc:review`, `$cc:adversarial-review <focus>`, `$cc:rescue <task>`.
- Only the other vendor counts. A subagent of the same model is not independent.
- Keep the two verdicts separate: both flagged / only one flagged. Agreement means same location
  and same defect, not the same file. Never blend them into one voice.

**Split authorship for risky fixes** — the other vendor writes the failing test; this one writes the fix.

**Plans before big work** — for work over about an hour, write the plan to a file. Choose an
independent critique when its risk or uncertainty makes it useful.

**Capacity** — when a limit is close, don't stall: run the `handoff` skill (writes `HANDOFF.md`),
then continue on the other vendor from that file.

## Coordination (one PC, several agents)

- Edits claim the checkout for your session (a guard hook). A blocked edit means another live session
  holds it: tell the user or work in a worktree; never work around the guard. `aos who` shows claims.
  The hook sees only edit tools: before writing in a checkout with a shell command, check `aos who` yourself.
- Follow `coordination` for task tiers, worker routing, run status, addressed messages and review choice.
  The lead integrates and verifies results. One writer owns a checkout at a time, including native
  children; use an exclusive handoff or separate worktrees for concurrent edits.
- Local-model output (nar, Pi) is a hint: check it against the files or tests before acting on or relaying it.

## Skills and tools

- Shared skills live in `~/.agents/skills` (the repo's `agents-home/skills`). Add a skill there
  once, then run `aos sync` so Claude gets a link too. Never a second copy per vendor.
  `~/.claude/skills/synced` belongs to the Claude app; leave it alone.
- A procedure is callable only as a `SKILL.md`. A note that describes a procedure is not.
- Before saying a capability is missing, or choosing among tools, read the `tool-catalog` skill: it
  lists every skill, MCP server, CLI, media app and agent here, and which one to try first.
- Prefer CLIs (`gh`, `rg`, `git`) over MCP servers when both work: tool schemas are loaded on
  every request. A new capability tool may be added on first need; a convenience one waits for the need to repeat.
- Use subagents for broad searches so the main context stays small.
