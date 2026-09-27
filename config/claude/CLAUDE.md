@~/.agents/AGENTS.md

## Claude Code specifics

- The `codex` plugin (openai/codex-plugin-cc) gives you `/codex:rescue` and the `codex-rescue`
  subagent to hand Codex a task. `/codex:review`, `/codex:adversarial-review` and `/codex:transfer`
  are user-only: suggest them, don't call them. For your own read-only second opinion, run
  `codex exec --profile review "<prompt>" </dev/null` (see the `second-opinion` skill).
- Process skills come from the `superpowers` plugin. Use them for non-trivial features
  (brainstorm, plan, test-first, verify) and skip them for small edits.
- Check `/usage` before starting large or parallel work; hand off before the window runs out, not after.
