---
name: second-opinion
description: Get an independent review from the OTHER vendor (Claude <-> GPT/Codex) and report both verdicts without merging them. Use before landing risky changes (auth, payments, data, migrations, deletes, releases, security), when no test could catch a mistake, when stuck after two failed attempts, or when the user says "second opinion", "cross-check", "have codex look", "have claude look", "double-check this". Not for routine or easily reverted edits.
---

# Second opinion (cross-vendor)

## 1. Decide it is worth it

Worth it when being wrong is expensive or when tests can't discriminate. Say which in one line.
If neither applies, say so and skip — two vendors cost two quotas.

## 2. Write your own review first

Before asking anyone, write down your own findings (file:line, defect, severity). Do this first so
the other review can't anchor you.

## 3. Ask the other vendor, blind

Give it the change and the goal — not your findings. Independence is the point.

| You are in  | Review                                   | Challenge the design                          | Delegate (e.g. write a failing test) |
|-------------|------------------------------------------|-----------------------------------------------|--------------------------------------|
| Claude Code | `codex exec --profile review "<PROMPT>"` | same, with an adversarial `<PROMPT>`          | `/codex:rescue <task>` or the `codex-rescue` subagent |
| Codex       | `$cc:review`                             | `$cc:adversarial-review <focus>`              | `$cc:rescue <task>`                  |

In Claude Code, `/codex:review` and `/codex:adversarial-review` are user-only commands (the plugin
sets `disable-model-invocation`): you cannot call them. Suggest them to the user when a richer
git-aware review is wanted; otherwise run the shell command yourself.

If a plugin is missing, use the shell from the repo root, with the same prompt either way:
- Claude -> Codex: `codex exec --profile review "<PROMPT>" </dev/null` (in Git Bash the `</dev/null`
  matters: with stdin left open, `codex exec` waits forever for extra input; PowerShell doesn't need it)
- Codex -> Claude: `claude -p "<PROMPT>"`

Build `<PROMPT>` from the real request, never a generic "review my changes":
`Goal: <what the change must achieve and how we'll know>. Review <SCOPE> for bugs, risky
assumptions and missing tests. Cite file:line. Do not modify files.` where `<SCOPE>` is exactly
one of: the uncommitted changes; the commits in `<base>..HEAD` (e.g. `main..HEAD` - commits made
under the commit-early rule are otherwise missed); or the plan in `<path>` (for plan critique).

## 4. Report

Keep the two voices apart:
- **Both flagged** — same location and same defect. This is the strongest signal.
- **Only <this vendor>** / **Only <other vendor>** — each with file:line.
- **Reviewer status** — completed / failed / unreachable. A failed review is not "no issues".

Then give your recommendation, labelled as yours. Verify each proposed fix (test or code reading)
before applying it — the reviewer can be wrong too.

## Rules

- Only a different vendor is a second opinion. A same-model subagent is not.
- Never merge both reviews into one list; disagreement is the information you paid for.
- Findings in the same file are not agreement unless they are the same defect at the same place.

## Log

- 2026-09-27 — created with the agentic-os setup; replaces the review/cold modules of the old `rig`.
- 2026-09-27 — fallback prompt now carries the goal and an explicit scope (commit range, working
  tree or plan file), after GPT-6-Astra's review found it only covered uncommitted changes.
- 2026-09-27 — Claude Code row corrected: `/codex:review` and `/codex:adversarial-review` are
  user-only; the agent reviews through `codex exec --profile review` and delegates via `/codex:rescue`.
  Found by asking Claude what it had loaded after install.
- 2026-09-27 — `</dev/null` added to the Bash form: a review launched from Git Bash hung at
  "Reading additional input from stdin" and never started.
