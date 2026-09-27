# Working on agentic-os

This repo configures Claude Code and Codex on this machine. The contract both agents follow day
to day is `agents-home/AGENTS.md`; this file is only about changing the repo itself.

- Read `README.md` (what and how) and `docs/decisions.md` (why) before changing behaviour.
- `aos.psm1` and `bootstrap.ps1` stay ASCII-only and must run under Windows PowerShell 5.1 and
  PowerShell 7: no `??`, no ternary, no `&&`/`||`. Parse-check after every edit with
  `[System.Management.Automation.Language.Parser]::ParseFile()`.
- Every step stays idempotent: a second `aos sync` changes nothing. Merge into the user's files,
  never replace them, and back up to `~/.aos-backups/` first.
- Preview before applying: `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun`.
- No model names in the repo; they change. Profiles tune effort and sandbox only.
- `docs/decisions.md` is append-only: a changed decision gets a new dated entry on top.
- Anything that writes to `~/.claude`, `~/.codex` or the user PATH gets a second opinion from the
  other vendor first (`second-opinion` skill).
