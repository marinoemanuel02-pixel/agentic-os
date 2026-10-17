@~/.agents/AGENTS.md

## Claude Code specifics

- The `codex` plugin (openai/codex-plugin-cc) gives you `/codex:rescue` and the `codex-rescue`
  subagent to hand Codex a task. `/codex:review`, `/codex:adversarial-review` and `/codex:transfer`
  are user-only: suggest them, don't call them. For your own read-only second opinion, run
  `codex exec --profile review "<prompt>" </dev/null` (see the `second-opinion` skill).
- Process skills come from the `superpowers` plugin. Use relevant guidance when it improves the task.
  The shared `coordination` policy controls task routing and review: an imported skill does not by
  itself require an extra reviewer, approval pause or highest-effort model for every task.
- Follow the user's existing authorization and the task's repository rules. Choose review for
  consequential risk or unresolved uncertainty; small reversible work with meaningful checks can
  finish inline.
- Check `/usage` before starting large or parallel work; hand off before the window runs out, not after.
