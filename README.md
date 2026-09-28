# agentic-os

Claude (Claude Code) and GPT (Codex) set up as one workflow on this Windows machine:
one contract and one skills folder for both, each agent able to call the other for review
or to take over, and one command to install, check and update everything.

Built 2026-09-27 for Claude Pro + ChatGPT Plus, replacing the hand-built `rig` layer with
vendor-maintained bridges. The reasons for each choice are in [docs/decisions.md](docs/decisions.md).

## The shape

| Layer | What | Where it lives |
|---|---|---|
| **base** | git + Git Bash, gh, PowerShell 7, Node LTS, Python + uv, rg/fd/jq/fzf/delta, VS Code, Obsidian | `packages.json` (winget) |
| **engines** | Claude Code CLI + Claude Desktop · Codex CLI + ChatGPT/Codex desktop app | native installer / winget / Store |
| **brain** | one `AGENTS.md` and one `skills/` folder read by both agents, merged Claude settings, Codex profiles, MCP servers in both | `agents-home/`, `config/` |
| **bridges** | Claude calls Codex (`/codex:*`), Codex calls Claude (`$cc:*`), superpowers in both | plugins |
| **refs** | shallow clones of the repos worth reading | `refs/repos.json` -> `%LOCALAPPDATA%\agentic-os\refs` |
| **aos** | `aos status / sync / update / usage / new / secret` | `aos.psm1` |

How the pieces connect:

```
                 agents-home/AGENTS.md  +  agents-home/skills/
                    |  (junction ~/.agents, copy ~/.codex/AGENTS.md, import from
                    |   ~/.claude/CLAUDE.md, one junction per skill in ~/.claude/skills)
          +---------+----------+
          |                    |
     Claude Code  <------->  Codex            /codex:review  /codex:rescue  /codex:transfer
   (Claude Pro)   plugins   (ChatGPT Plus)    $cc:review     $cc:rescue
          |                    |
          +---- HANDOFF.md ----+              when one hits its limit, the other continues
```

## Fresh machine: set it up

1. Put this folder on the Desktop (`Desktop\agentic-os`; the Desktop is OneDrive-synced, so it
   survives a reset), ideally also pushed to a private GitHub repo.
2. Preview, then run (approve the UAC prompts winget raises):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun
   ```
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
   ```
3. Do the one-time steps it prints: sign in to Claude Code (`claude auth login`), `gh auth login`,
   restart the Claude and Codex apps (they predate the new PATH), then `$cc:setup` in Codex.
   Use PowerShell 7 (`pwsh`): Windows PowerShell 5.1 blocks profile scripts by default, so `aos`
   is only wired into `pwsh` unless you change that policy yourself.
4. Open a new `pwsh` window and run `aos status`. Every line should be `ok`.

Everything is idempotent: re-running changes nothing unless something drifted. Your existing
settings are merged, never replaced, and backups go to `~/.aos-backups/`.

## Daily use

| You want to | Do |
|---|---|
| Start work in a repo | `claude` in the folder, or open it in the Codex app / Claude Desktop |
| Start a new project | `aos new name` -> `Desktop\1-Projects\name` (AGENTS.md, CLAUDE.md -> @AGENTS.md, .gitignore, git) |
| A second opinion | ask for one; the `second-opinion` skill picks `/codex:review` or `$cc:review` |
| Keep going at a limit | ask for a handoff; the `handoff` skill writes HANDOFF.md for the other agent |
| See what's installed and linked | `aos status` |
| See usage | `/usage` in Claude Code, `/status` in Codex, `aos usage` for local history |
| Update everything | `aos update` (weekly is plenty) |
| Store an API key | `aos secret set <name>` (Windows secret store, never a plaintext file) |
| Check the setup's own code | `aos test` (parse, ASCII, Pester under PowerShell 5.1 and 7; CI runs it on every push) |

Which agent to use for what, and how to stretch two entry plans: [docs/routing.md](docs/routing.md).

## Changing it

| Change | Edit | Then |
|---|---|---|
| Shared rules for both agents | `agents-home/AGENTS.md` | `aos sync` (Codex keeps a copy) |
| Add a skill for both | `agents-home/skills/<name>/SKILL.md` | `aos sync` (links it into `~/.claude/skills`; Codex sees it at once) |
| Claude-only rules | `config/claude/CLAUDE.md` | `aos sync` |
| Claude settings | `config/claude/settings.json` | `aos sync` (merged into yours) |
| Codex profiles | `config/codex/<name>.config.toml` (top-level keys) | `aos sync`, then `codex --profile <name>` |
| MCP server for both | `config/mcp.json` | `aos sync` |
| A tool | `packages.json` | `aos install base` |
| A reference repo | `refs/repos.json` | `aos refs` |
| A plugin | install it, then add it to `Install-AosBridges` in `aos.psm1` | so a rebuild reproduces it |

Rules that keep this upgradeable:
- **No model names** outside the agents' own defaults. Profiles tune effort and sandbox, not models,
  so nothing goes stale when a new model ships.
- **One copy of everything.** A skill or rule lives in one place; links and the synced copy carry it.
- **Add one capability at a time**, against a need that has already repeated.
- **Secrets never touch files** in this repo, profiles, or `HANDOFF.md`.

## Not installed yet (deliberately)

Candidates for later layers, each with the reason to wait:
- **Paseo** (one desktop + phone cockpit for both agents): the native apps plus Remote Control
  and the ChatGPT mobile app cover this today. Revisit if you regularly run 3+ sessions.
- **An always-on agent** (Hermes, OpenClaw): only on your ChatGPT login or API keys, never your
  Claude login (Anthropic's terms). Revisit when there is unattended work that repeats.
- **chezmoi**, if a second machine appears and dotfiles need per-machine templating.
- **WSL2**, if you want Claude Code's sandboxed mode for long autonomous runs.

## Layout

```
agentic-os/
  bootstrap.ps1          entry point (layers, -DryRun)
  aos.psm1               the aos command; all logic lives here
  packages.json          winget / npm / VS Code extensions per layer
  agents-home/           becomes ~/.agents (junction)
    AGENTS.md            the global contract for both agents
    skills/              shared skills (handoff, second-opinion)
  config/
    claude/CLAUDE.md     managed block at the top of ~/.claude/CLAUDE.md
    claude/settings.json merged into ~/.claude/settings.json
    codex/*.config.toml  Codex profiles (review, deep, quick) -> ~/.codex/<name>.config.toml
    mcp.json             MCP servers registered in both agents
  templates/project/     what aos new creates (in Desktop\1-Projects; override with $env:AOS_PROJECTS)
  refs/repos.json        essential repos (clones go to %LOCALAPPDATA%\agentic-os\refs, outside OneDrive;
                         override with $env:AOS_REFS)
  docs/routing.md        who does what, limits playbook
  docs/decisions.md      why it is built this way, with sources
  tests/                 Pester 5 suite (written by Codex) + Run-Tests.ps1 (used by aos test)
  .github/workflows/     ci.yml: aos test on windows-latest for every push
```
