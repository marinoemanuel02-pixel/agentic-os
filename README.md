# agentic-os

Claude (Claude Code) and GPT (Codex) set up as one workflow on this Windows machine:
one contract and one skills folder for both, each agent able to coordinate execution with the
other vendor's native workers, choose useful review or hand off, and one command to manage the setup.

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
| **media** | free media tools the agents drive from the command line: ffmpeg, ImageMagick, pandoc, yt-dlp, DuckDB, Inkscape, Blender, OBS, Audacity, Kdenlive, GIMP, Krita, LMMS (about 1.3 GB). Opt-in: `aos install media`, never part of `all`. Not in it: Playwright browsers, Whisper models, ComfyUI (large, your choice) | `packages.json` (winget); `agents-home/skills/media-tools` |
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
| Start a new video | `aos video new name` -> `Desktop\1-Projects\videos\name` from `templates/video` (pipeline tools, kit, stage docs), plus a render app in `~\.aos\video\name` linked to the shared Remotion install, and `PREFLIGHT.md` (rules, past verdicts, stage times) |
| Teach the video pipeline | `aos video verdict name <the user's words>` and `aos video log name <stage> <minutes>` record into the ledger; `aos video preflight name` refreshes `PREFLIGHT.md`; rules in `agents-home/video/video-rules.md` marked `[check: x]` run as `tools/checks/x.mjs` in the project's QA |
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

For existing-footage editing, the [local footage workflow](tools/footage/README.md) provides inventory,
offline word timestamps, transcript search, reviewed cuts and FFmpeg export. For a quota handoff,
`aos coord continuation check <checkpoint-id> --repo . --from claude --to codex` checks cold state
and observed capacity; see [selected additions](docs/picked-stack-additions.md).

The optional [read-only Claude status mod](plugins/aos-status/README.md) adds `/aos-status` using the
native mod system. It is installed and enabled under the operator's explicit review exception of
20 October; native tests passed, while rendering in a live Desktop session remains unverified.

The approved optional [stack additions](docs/stack-additions.md) add local video frames, document
conversion, selected repository exports, design references and on-demand code navigation. The guide
also records the media/connector installs and OmniRoute's operational free text-worker route.
Use `python tools/stack.py omniroute-task --packet task.txt --output candidate.json` for one
checked request, or `python tools/stack.py verify --output <new-evidence-folder> --live` to repeat
the fourteen-product workflow checks. Open VoiceStudio first for its speech check; see the guide
for exact scopes and remaining limits.

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

The local model (Pi, model `aos/aos-agent`, started with `pi` in a terminal) asks before every command or file
change it wants to make; reading files needs no approval. Its project directory is only the starting location,
not a repository sandbox: native tools run on the PC under your Windows account and can target other
user-accessible paths. Windows ACLs and the approval prompt remain the boundaries, so the model must verify paths
outside the project before changing them. The synced Pi extension also provides a small permission-gated
`web_search` tool that returns public search results with source URLs; it is a search operation, not a browser or
desktop-control bridge. It is a 4B model with a 16K context: good for small, well-defined tasks; it can misreport
what happened, so check its claims.

Keep the PC reachable (your Windows settings, once): keep it plugged in; Settings > System >
Power > sleep: Never when plugged in; Control Panel > Power Options > "Choose what closing the lid
does" > Plugged in: Do nothing. The Claude app only holds the PC awake while a session is working.

## Shared folders and Inbox

`config/places.json` lists shared repositories, vaults and folders using runtime placeholders.
`aos place ls --json` reports the resolved paths and whether they exist. Add an existing folder with
`aos place add <folder> [--name <name>] [--kind repo|vault|folder]`; commit the resulting config change.
`aos new` adds the created project too. `aos sync` writes `~/.aos/places.json` for agents and tools.
Missing folders are left absent; only a missing Inbox is created.

Notes and links go into the Inbox with the `inbox` skill.
For photos or other files, use Android Share -> OneDrive -> Desktop/Inbox; OneDrive syncs them separately.
The shared `inbox` skill can propose filing items into configured vaults and waits for confirmation before moving them.

## Several agents at once

The lead agent decides whether to work inline or delegate, using the `coordination` skill and
the task's scope, tools and available capacity. Small tasks stay inline; a separate delegation choice
is not required for every task. The shared state lives in `~\.aos\coord` (outside OneDrive):

- **Claims.** The first edit in a checkout claims it for that session (a hook in both agents); another
  session's edits there are blocked with the holder's name until the claim ends (session end) or
  expires (60 minutes without edits). `aos who` lists claims and recent events; `aos note <text> --as
  <agent>` leaves a message there; `aos claim|release [<path>] --as <agent>` do it by hand.
- **Delegation.** `aos delegate codex|claude --task task.md` accepts `--write --verify "<command>"
  [--allow <glob>]`, `--tier light|standard|deep`,
  `--effort <supported-value>`, `--parent <actor-id>` and `--workers 0|1`. The lead selects a tier
  for the work; it does not promise lower cost or quota use. A writer works in its own worktree, and
  the host checks its receipt and verification result. One writer owns each checkout at a time,
  including native workers. Use `aos delegate ls|show|clean` to inspect or clean managed runs. See
  [docs/routing.md](docs/routing.md) and the shared `coordination` skill.
  Optional checked task contracts, routing reports, evaluation fixtures, native roles/events,
  App Server transport and recovery/procedure commands are described in
  [docs/coordination-tuning.md](docs/coordination-tuning.md).
- **Actors and runs.** `aos coord reserve|observe|finish|actors|reconcile` manages cooperative actor
  reservations and state. An actor id is routing metadata; registration alone does not prove a native
  worker ran. Use observed native tool-handle or transcript evidence for that claim. The two-actor
  per-vendor limit is the configured policy; native routes without enforceable spawn controls remain
  cooperative.
- **Messages and status.** `aos coord send|inbox|ack|wait|status|cancel` exchanges addressed messages
  within a task tree, reads run state, or requests cancellation. Inbox reads do not acknowledge a
  message; acknowledgement is explicit. A cancellation request does not prove process termination.
  `wait` is bounded to 45 seconds. Read the current implementation's usage text for exact arguments.
- **Notes between agents.** `aos note "<text>" --as <claude|codex>` writes to the shared ledger; a PostToolUse hook
  (`config/hooks/aos-notes.mjs`) shows each agent the other's unread notes after its next shell or edit call.
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
| MCP server for both (or one: add `"agents": ["claude"]`) | `config/mcp.json`, and a row in `agents-home/skills/tool-catalog/SKILL.md` | `aos sync` |
| What the agents know they can use | `agents-home/skills/tool-catalog/SKILL.md` | `aos sync` |
| A tool | `packages.json` | `aos install base` |
| A reference repo | `refs/repos.json` | `aos refs` |
| A plugin | install it, then add it to `Install-AosBridges` in `aos.psm1` | so a rebuild reproduces it |

Sync also removes MCP servers it previously registered when they leave `config/mcp.json` or no longer target an agent.

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
  templates/video/       what aos video new adds on top (pipeline tools, Remotion kit, stage docs, delegate task)
  refs/repos.json        essential repos (clones go to ~\.aos\refs, outside OneDrive and AppData;
                         override with $env:AOS_REFS)
  docs/routing.md        who does what, limits playbook
  docs/decisions.md      why it is built this way, with sources
  tests/                 Pester 5 suite (written by Codex) + Run-Tests.ps1 (used by aos test)
  .github/workflows/     ci.yml: aos test on windows-latest for every push
```
