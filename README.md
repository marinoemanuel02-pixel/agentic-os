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
| **refs** | shallow clones of the repos worth reading | `refs/repos.json` -> `~\.aos\refs` |
| **local** | Ollama and the local model; the `nar` tools (calibrated single-pass scoring); Pi, the agent harness on the local model | `config/local.json`, `Desktop\1-Projects\nar-tools`; models in `~\.ollama` |
| **phone** | Paseo: its daemon runs Claude Code, Codex and Pi on this PC for the Paseo Android app | `packages.json` (npm); state in `~\.paseo` |
| **aos** | `aos status / sync / update / usage / new / secret / remote` | `aos.psm1` |

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
| Store an API key | `aos secret set <name>` (encrypted to your Windows login in `~\.aos\secrets`, never a plaintext file); scripts read it with `aos secret get <name>` |
| Work from your phone | see [From your phone](#from-your-phone) |
| Use the local model | agents call the `nar` tools on their own when a choice benefits; `aos nar choose "..." --option A --option B` by hand; `ollama run <tag>` to chat |
| Try a newer local model | `ollama pull <tag>`, `aos nar eval --models <tag>`, then `aos local adopt <tag>` (only if no worse) |
| Check the setup's own code | `aos test` (parse, ASCII, Pester under PowerShell 5.1 and 7; CI runs it on every push) |

Which agent to use for what, and how to stretch two entry plans: [docs/routing.md](docs/routing.md).

Tools, clones and keys live under your home folder, not AppData: both desktop apps are MSIX
packages, and a folder they (or the agents in them) create under AppData can stay private to that app.

## From your phone

Install the **Claude** and **ChatGPT** apps on the phone and sign in with the same accounts as on
the PC. Phone sessions run on the PC, with your files, tools, `aos` and both bridges; the phone
sends prompts and approvals.

| You want to | Do | Needs |
|---|---|---|
| Follow or steer a session started on the PC | Claude app > Code. Sessions started in the Claude desktop app appear there (Remote Control is on for new sessions: Settings > Claude Code) | PC awake, Claude app running |
| Start Claude sessions on the PC from the phone | On the PC: `aos remote` (Desktop hub) or `aos remote <project>`, and leave that window open. Then Claude app > Code | PC awake; at most 2 sessions at once |
| Use Codex on the PC from the phone | Once: Codex app > Settings > Connections > Control this PC > Set up, and scan the QR code with the ChatGPT app. Then ChatGPT app > Codex | PC awake, online and unlocked |
| Work while the PC is off | Claude app > Code (cloud session) or ChatGPT app > Codex (cloud task), on a GitHub repo | Push first: they see only what was pushed |
| Claude Code, Codex **and the local model** from one app | **Paseo** (Android, Play Store). Once: on the PC, in Windows Terminal, `paseo daemon pair --relay`, and scan the QR code in the app (Add connection > Scan QR code); keep the QR private. Then pick a provider per session: Claude, Codex, or Pi with model `aos/aos-agent` (the local model) | The Paseo daemon running on the PC: `paseo daemon start` from Windows Terminal, not from inside the Claude app |
| See agentic-os status and nar calibration; label nar's recent choices | Paseo app > a workspace > **+** > **agentic-os** (the aos plugin). A tap on the right option records it; the call leaves the list | Paseo paired |
| Coordinate the three providers in one project conversation | Paseo workspace > **+** > **Coordinator**, select a registered project and Open conversation. Choose Auto, Local or a discovered cloud model in the conversation. The panel shows local health, quota, native tasks, Stop linked tasks and explicit recovery | aos plugin on tested Paseo 0.10.1; Ollama running for Local |

The local model in Paseo (Pi) asks before every command or file change it wants to make: the question
shows up in the app as Allow / Deny, and nothing runs until you answer. Reading files needs no approval.
Its project directory is only the starting location, not a repository sandbox: native tools run on the PC
under the Paseo daemon's Windows account and can target other user-accessible paths. Windows ACLs and the
phone approval gate remain the boundaries, so the model must verify paths outside the project before changing them.
The synced Pi extension also provides a small permission-gated `web_search` tool that returns public
search results with source URLs; it is a search operation, not a browser or desktop-control bridge.
It is a 4B model with a 16K context: good for small, well-defined tasks; it can misreport what happened,
so check its claims. Voice input in Paseo is off: turning it on downloads about 1 GB of speech models
(`paseo daemon config set features.dictation.enabled true`; for Italian also set
`features.dictation.stt.model parakeet-tdt-0.6b-v3-int8`), then `paseo daemon restart`.

Keep the PC reachable (your Windows settings, once): keep it plugged in; Settings > System >
Power > sleep: Never when plugged in; Control Panel > Power Options > "Choose what closing the lid
does" > Plugged in: Do nothing. The Claude app only holds the PC awake while a session is working.

## Shared folders and Inbox

`config/places.json` lists shared repositories, vaults and folders using runtime placeholders.
`aos place ls --json` reports the resolved paths and whether they exist. Add an existing folder with
`aos place add <folder> [--name <name>] [--kind repo|vault|folder]`; commit the resulting config change.
`aos new` adds the created project too. `aos sync` registers existing Places with Paseo and writes
`~/.aos/places.json` for agents and tools. Missing folders are left absent; only a missing Inbox is created.
If Paseo is unavailable, the local registry is still saved and registration is reported as skipped.

The agentic-os phone panel has an Inbox box for notes and optional HTTP(S) links, plus recent captures.
Save creates a new UTF-8 Markdown file in the configured Inbox and never overwrites another note.
After a lost reply, the panel keeps your text: refresh the recent list before saving again.
For photos or other files, use Android Share -> OneDrive -> Desktop/Inbox; OneDrive syncs them separately.
The shared `inbox` skill can propose filing items into configured vaults and waits for confirmation before moving them.

## Several agents at once

Claude Code and Codex share one coordination layer in `~\.aos\coord` (outside OneDrive):

- **Claims.** The first edit in a checkout claims it for that session (a hook in both agents); another
  session's edits there are blocked with the holder's name until the claim ends (session end) or
  expires (60 minutes without edits). `aos who` lists claims and recent events; `aos note <text> --as
  <agent>` leaves a message there; `aos claim|release [<path>] --as <agent>` do it by hand.
- **Delegation.** `aos delegate codex --task task.md` (read-only) or `aos delegate codex --task task.md
  --write --verify "<test command>" [--allow <glob>]`. The model is probed once a day, the verify tool
  is checked inside the delegate's sandbox, a writer works in `~\.aos\worktrees\<repo>-<id>` on
  `delegate/<id>`, the host commits and verifies, and the receipt says accepted or why not.
  `aos delegate ls | show <id> | clean <id>`.
- After `aos sync` changes Codex hooks (also after a cc plugin update, which aos repairs), trust them
  once in Codex with `/hooks`.

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
  refs/repos.json        essential repos (clones go to ~\.aos\refs, outside OneDrive and AppData;
                         override with $env:AOS_REFS)
  docs/routing.md        who does what, limits playbook
  docs/decisions.md      why it is built this way, with sources
  tests/                 Pester 5 suite (written by Codex) + Run-Tests.ps1 (used by aos test)
  .github/workflows/     ci.yml: aos test on windows-latest for every push
```
