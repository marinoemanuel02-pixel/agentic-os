---
name: tool-catalog
description: "What this machine's agents can use and which one to reach for first: skills, MCP servers, CLIs, media apps, the other vendor, the local model. Read when choosing a tool, or before saying a capability is missing."
---

# Tool catalog

Check here before concluding something cannot be done. Each row says what it is for and where it is documented.
Skills load on demand (`Skill` in Claude, the skills list in Codex and Pi). Everything is free except the two
subscriptions (Claude and ChatGPT).

## Skills (shared, `agents-home/skills`)

| Skill | Use it for |
|---|---|
| `coordination` | choosing inline work or a bounded cross-vendor/native-worker assignment, tracking actors, addressed messages and run state |
| `handoff` | writing `HANDOFF.md` when a limit is near or work moves to the other vendor |
| `second-opinion` | independent review by the other vendor before risky changes |
| `inbox` | saving a note or link to the global Inbox, filing Inbox items into vaults (with confirmation) |
| `media-tools` | ffmpeg, ImageMagick, pandoc, yt-dlp, Whisper, DuckDB, Playwright, Blender, Inkscape, Kdenlive, GIMP, OBS from the command line |
| `watch` | bounded local video frames with source-relative timestamps; view frames before visual claims |
| `frontend-design` | brief-grounded frontend design direction, implementation and visual critique |
| `ui-ux-pro-max` | offline searchable UX, accessibility, style and design-system reference data |
| `penpot-local` | Penpot design work through its local MCP server, started only when needed |
| `research` | cited web research with the agents' own free web search and fetch |
| `video-references` | a reference pack for a film's niche: strong channels watched in the browser without downloading, notes per beat |
| `caveman` | opt-in terse replies, only on an explicit `/caveman` (about a quarter fewer visible tokens in a 3-prompt Haiku test; total tokens did not fall); not for reports or prose |
| `tool-catalog` | this list |

Claude Code adds `superpowers:*` process skills (brainstorming, plans, test-first, debugging, verification) and
the `codex` plugin; Codex has the same superpowers set and the `$cc:*` commands.

## MCP servers (`config/mcp.json`, registered by `aos sync`)

| Server | Agents | Use it for |
|---|---|---|
| `context7` | Claude, Codex | current, version-specific library documentation |
| `nar` | Claude, Codex | scoring options among known alternatives in one local pass; `nar_classify` (or `nar classify` on the command line, which scripts should prefer) labels up to 50 short texts per call, with `backend=embed` for fast multilingual zero-shot sorting by topic or type (needs `ollama pull bge-m3` once). Use it to triage before spending cloud tokens, check a sample against the truth, report outcomes with `nar_feedback` |

Servers cost context on every request: add one only when a command line cannot do the job.

## Command lines (preferred over servers)

`gh` (GitHub), `rg`/`fd`/`jq` (search), `git`, `uv`/`python`, `node`/`npm`, `pwsh`; the media tools above;
`python ~/.video-intel/video_intel.py <reel-url>... [--limit N]` (public reels to local Whisper transcripts in `~/.video-intel/out/`; no cookies needed, profile pages are listed through the browser; Instagram media only, the `video-intel` skill drives it);
`aos` itself: `status`, `sync`, `test`, `ready` (read-only gate before cross-vendor work: repo, claims, both vendors' capacity and actor slots, task paths, unpushed commits), `new`, `video new` (a video project from the template), `who` (claims), `note`, `delegate codex|claude` (hand a task to the other vendor; supports task tier, effort, parent and one native-worker allowance), `coord` (actor reservation, observation, finish, listing, reconciliation, addressed send/inbox/ack/wait and run status/cancellation), `secret` (keys; never print them), `place` (known folders), `install <layer>`.

Coordination tuning: optional `delegate --contract` and Codex `--transport app-server`; `coord task`
for checked dependencies and compact packets, `report`/`annotate` for routing evidence,
`capabilities`/`roles`/`native`/`steer` for supported native controls and lifecycle, and
`checkpoint`/`procedure` for verified continuation and scoped guidance. `continuation check` tests
a cold quota handoff to the other existing vendor without replaying work. The six-case
`tools/coordination-eval.ps1` defaults to model-free preparation. See `docs/coordination-tuning.md`.

Engine shots for video films: Godot 4.7 (`~/.local/bin/godot/`, Movie Maker), Manim CE (venv `~/.aos/venvs/manim`) with TinyTeX (`~/.aos/tinytex`, never on the user PATH); driven only through a film's `tools/render-shot.py` (see the template's `engines/README.md`, rules R55-R57). Unreal, Unity, Autograph and Cavalry need accounts the user creates; their adapters are written but not yet run.

Existing-footage editing: `tools/footage/footage.py` in the setup repo, reached through the `aos`
module's directory. Offline inventory/transcription, timestamp search, draft cuts and checked FFmpeg
export; use the `media-tools` skill's footage reference. Never downloads a model implicitly.

Claude's optional native `aos-status` mod lives in `plugins/aos-status`. Its `/aos-status` command
shows bounded local coordination records and measured context without model calls or writes.
Persistent installation requires the project's independent review; see that directory's README.

Candidate capabilities use `python tools/stack.py capabilities`: `validate`, `list`, `refresh`,
`record` and `status`. Default refresh previews public discovery feeds; `--tool <id>` reads that
original repository, and `--apply` retains observations under `~/.aos/capability-watch`. Treat word
matches as unverified leads. Evidence import and status changes are explicit; nothing installs or
starts a candidate. See `docs/capability-watch.md` for tiers and comparisons with existing routes.

Candidate setup is explicit: `python tools/stack.py capability-setup install <tool>` previews the
pinned download; `--apply` installs under `~/.aos/tools/capabilities`. Installed commands are
`rea`, `pdfcraft`, `blender-agent-sdk`, `logisheets`, `filmcraft`, `photocraft`, `agent-desktop`.
They start only when called; none is registered globally. Use scoped task copies and the examples
in `docs/capability-setup.md`. Blender SDK is the preferred tested headless adapter;
`blender-mcp-benchmark` retains the comparison with observed state/render defects. These remain
evaluation tools, not unrestricted production integrations. Existing artifact/media skills stay
the first route for ordinary documents, sheets, images and video; use these when persistent
application state adds value. ANIS is Linux-only upstream; MCP-PC remains the unselected fallback.
Use `python tools/stack.py capabilities-local list` for this machine's actual pins, trial results
and admission statuses. Ordinary `capabilities` reads the portable seed; installation does not
promote either registry automatically.

Optional stack additions use `python tools/stack.py <tool> ...` from this repo; `list` shows routes.
AnyDoc converts local documents (hosted OCR refused); Repomix exports selected files; RTK OSS
filters explicit commands while preserving their failures. Graphify uses code-only extraction with
LLM backends disabled. Serena is on demand: use the single-project, navigation-only context in
`config/serena-readonly.yml`, tools interface, stdio transport and disabled web dashboard. No global
MCP registration is needed. See `docs/stack-additions.md` for exact commands and verification limits.

The same launcher reaches the CLI-Anything Kdenlive harness, its separate `kdenlive-render` command,
OpenMontage local board, OpenDesign Agent Kit exports, VoiceStudio app and Composio Connect.
The checked renderer uses isolated plugins and refuses unsupported active services. Watch adds local
embedded text captions while retaining the pinned frame extractor. Paid/cloud examples
in upstream documentation are not permission to use them. VoiceStudio's local Supertonic preset
speech passed cold app-owned backend startup, bilingual generation and shutdown through the shared
launcher; `voicestudio --check` only checks cached imports. Composio's consumer key now passes Connect
authentication, discovery and a connected GitHub read. Use `composio tools` or an explicitly
authorized `composio call <tool> --input <json>`; the key comes from `aos secret` in memory.
Do not use the consumer key as developer SDK auth. OmniRoute's saved OpenRouter connection
and restricted free text worker passed. Use `omniroute-task --packet <file> --output <new-json>`:
it loads the encrypted key internally, validates the hash-only restricted policy and live zero-price
catalog, disables fallbacks, and starts/stops only its owned loopback gateway. `omniroute-task --check`
checks readiness without inference; `omniroute-policy check` checks the saved worker policy.
The recovered free API pool is now the shared managed route: `python tools/stack.py swarm
accounts` lists accounts/capabilities; `task` runs a bounded JSON packet, `submit`/`drain` queue
work, and `verify` records actual host acceptance. Registered coordination contracts use
`swarm contract` with checked prerequisites and ordinary host receipts. Both native agents
use the same API queue without adding API accounts to their two-vendor actor registry.
Embedding/reranking, supplied-source research preparation, bounded image questions and
authorized short WAV transcription share its quota and secret controls. See `docs/swarm.md`.
The `omniroute-task` plain-text CLI joins that ledger when the pool registry exists.
Native clients remain normal routes; this is an unaccepted text candidate, not a managed
third-provider writer. The operator waived external review. See the dated trial report in
`docs/research/2026-10-20-stack-trial-results.md` for failures and screened-only candidates.
The later `docs/research/2026-10-20-stack-repairs.md` records repaired routes and remaining limits.
Use `verify --output <new-home-folder> --live` for repeatable checks of all fourteen approved
products; keep VoiceStudio open for speech. Live mode permits Composio discovery and one free
OmniRoute request. Skips, blockers and failures remain explicit. See
`docs/research/2026-10-21-stack-integration.md` for current integration evidence.
`aos` itself: `status`, `sync`, `test`, `new`, `video new` (a video project from the template), `who` (claims), `note`, `delegate codex|claude` (hand a task to the other
vendor, `--max-input` caps its tokens), `secret` (keys; never print them), `place` (known folders), `install <layer>`,
`asset search|fetch|capture|proxy|registry|credits|budget` (real clips, photos, captures and models for a film, with a
rights ledger; rule R35).

## Other agents

| Agent | Reach it with | Good for |
|---|---|---|
| Codex | `/codex:rescue`, `codex-rescue` subagent, `codex exec --profile review "<prompt>" </dev/null`, `aos delegate codex` | Select for its current capability, context and available capacity; it can take scoped work, tests, implementation or an independent review |
| Claude Code | `$cc:rescue`, `$cc:review`, `aos delegate claude` | Select for its current capability, context and available capacity; it can take scoped work, design, writing or an independent review |
| Pi on the local model | terminal sessions (`pi`); `web_search`, `file_search`, `text_read`, `pc_status` | small, well-defined tasks; its claims need checking |

## Browser and desktop

Claude Code has its own in-app browser and, when granted, Chrome and computer-use tools; use the browser
tools for web pages before computer use. From the phone, Claude and Codex are reached through their own apps (README "From your phone").

## How to use this list

1. Name the need, find the row, use the first match. If two fit, take the cheaper (command line, then skill, then server).
2. If nothing fits, say what is missing; do not invent a tool. Adding one is the user's call (see `docs/decisions.md`).
3. A tool you could not reach this session (not connected, not installed, wrong vendor) is reported as such, never as "not possible".
4. When you add a skill or server, add its row here; the test fails until you do.
