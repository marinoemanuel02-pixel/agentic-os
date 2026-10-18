# Coordination refinement and recent releases

Checked 2026-10-18 for the user's overnight continuation request. This follows implementation of
the six additions in the [earlier research](2026-10-17-coordination-tuning.md). The bounded goal is
verified coordination within the existing subscriptions, with explicit limits and recovery.

## Recent changes selected

- **Codex CLI 0.163.0, October 15.** Its official release notes describe better interruption,
  preservation of permissions on resume, parallel read tools and command-output cleanup. These
  are relevant to this stack's supervised workers and continuation. The native platform package
  was staged separately, its archive integrity checked, protocol schemas compared, and an actual
  ChatGPT-authenticated App Server check passed before activation. The copied release was checked
  again for identical file hashes, version and authentication. The native-role capability record
  now recognizes this reviewed release and the previous one; arbitrary future versions stay unknown.
  Source opened: [official changelog](https://learn.chatgpt.com/docs/changelog).
- **Claude Code 2.1.302, October 16.** The first-party release notes include fixes for PowerShell
  command discovery, plugin startup, cache reuse and subagent behavior. The candidate authenticated
  through the existing Pro subscription and produced an isolated test artifact. The official exact
  version install then completed, preserving the previous binary. A post-install read-only task and
  host check passed. Source opened: [first-party release](https://github.com/anthropics/claude-code/releases/tag/v2.1.302).

These are compatibility and maintenance improvements, not measured subscription savings. No new
API service, credential, model pin, MCP server or general orchestration framework was needed.

## How the architecture was assessed

The lead checked dependency semantics, scope, receipt acceptance, native identity, context bounds,
recovery and measured-versus-unknown settings. Claude independently reviewed the core implementation,
auth and settings changes, wrote safety/regression tests, checked evaluation files, and assessed the
upgrade plan. Some review passes explicitly left the spec or tests unread; they are partial reviews,
not blanket assurances. The lead checked their findings against the accepted design and host results.

The useful additions remain small extensions to the existing dispatcher: a task can run inline,
go to the other vendor, or use one reserved native child. The lead decides whether a second opinion
repays its cost. Artifacts and host checks connect dependent work, rather than requiring every result
to receive the same review. Recovery retains uncertain ownership and evidence.

Official documentation supports native roles and explicit concurrency controls, but that does not
establish a machine-wide limit for arbitrary clients. The shared registry's global admission is
cooperative, lifecycle observations occur after launch, and a role's instructions do not establish a
separate sandbox. Installed CLI capability records do not establish a running desktop harness's
version. Source opened: [native configuration documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents).

The recent OpenAI maintenance account uses clear acceptance criteria, source evidence and measured
comparisons. Applying those practices here supports bounded tasks and outcome-based routing; its
results are not measurements of this machine. Source opened, published October 14:
[maintenance workflow account](https://developers.openai.com/blog/maintaining-software-with-the-gpt-6-family).

## Adoption and recovery decisions

An installer inspection rejected the proposed deferred-selection path: the downloaded Codex script
permits it only for daemon installs and also prunes staging directories. The installer was not run.
Instead, the complete verified native package was copied to a new release directory, every file was
checked, and only the official installer's atomic junction helpers were used for selection. Their
activation and rollback were exercised in a separate fixture first. The previous release and an
independently hashed backup remain available. User PATH and AppData tools were not changed by this
Codex activation. Claude used its official exact-version installer with a verified binary backup.

The independent upgrade-plan review identified the non-atomic rename gap and asked for copied-release
checks. The final operation avoids that gap and includes those checks. Parent supervision confirms
worker termination; no unrelated process or checkout was interrupted to make a test possible.

Live fixture checks demonstrate functioning routes, not broad quality rankings. The first mechanical
evaluation passed with no lead correction. A paired baseline and representative production cases
are still needed before claiming a routing speed or quota improvement. The implementation provides
the measurements and runner for that work without changing routes from one successful example.

See [commands and limits](../coordination-tuning.md) and the
[implementation validation record](../validation/2026-10-18-coordination-tuning.md) for
actual test counts, review coverage and rollout evidence. External archive recovery remains unverified,
so the source worktrees are retained.
