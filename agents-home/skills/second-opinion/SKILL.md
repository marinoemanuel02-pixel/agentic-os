---
name: second-opinion
description: Get an independent review from the other vendor when the user asks, the risk is consequential, or tests cannot resolve important uncertainty. Not for routine reversible work with useful checks.
---

# Second opinion (cross-vendor)

## 1. Decide it is worth it

This skill is conditional; ordinary work does not trigger a review. Use it when the user asks, being
wrong could cause consequential harm (auth, money, destructive data changes, migrations, releases or
security), or important uncertainty remains that available checks cannot resolve. State the reason
briefly. A small reversible change with meaningful checks can stay inline. Skip duplicate review of
the same revision and scope; two vendors consume two subscription windows.

## 2. Write your own review first

Before asking anyone, write down your own findings (file:line, defect, severity). Do this first so
the other review can't anchor you.

## 3. Ask the other vendor, blind

Give it the change and the goal — not your findings. Independence is the point.

| You are in  | Review                                   | Challenge the design                          | Delegate (e.g. write a failing test) |
|-------------|------------------------------------------|-----------------------------------------------|--------------------------------------|
| Claude Code | `aos delegate codex --task <file>`       | same, with an adversarial task file           | `aos delegate codex --task <file> --write --verify <cmd>` |
| Codex       | `aos delegate claude --task <file>` or `$cc:review` | `$cc:adversarial-review <focus>`   | `aos delegate claude --task <file> --write --verify <cmd>` |

`aos delegate` checks the model and tools first, runs a writer in its own worktree, commits there on
the host, verifies on the host and writes a receipt (`aos delegate show <id>`); read the diff before
merging the `delegate/<id>` branch. The raw commands below remain the fallback.

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
- 2026-10-01 — `aos delegate` is the default route (preflight, receipts, host verify); found while
  a hand-typed `codex exec` used a model the account rejects and its delegate could not run its tests.
- 2026-09-27 — `</dev/null` added to the Bash form: a review launched from Git Bash hung at
  "Reading additional input from stdin" and never started.
