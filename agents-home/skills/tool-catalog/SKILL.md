---
name: tool-catalog
description: What this machine's agents can use and which one to reach for first: skills, MCP servers, CLIs, media apps, the other vendor, the local model. Read when choosing a tool, or before saying a capability is missing.
---

# Tool catalog

Check here before concluding something cannot be done. Each row says what it is for and where it is documented.
Skills load on demand (`Skill` in Claude, the skills list in Codex and Pi). Everything is free except the two
subscriptions (Claude and ChatGPT).

## Skills (shared, `agents-home/skills`)

| Skill | Use it for |
|---|---|
| `handoff` | writing `HANDOFF.md` when a limit is near or work moves to the other vendor |
| `second-opinion` | independent review by the other vendor before risky changes |
| `inbox` | saving a note or link to the global Inbox, filing Inbox items into vaults (with confirmation) |
| `media-tools` | ffmpeg, ImageMagick, pandoc, yt-dlp, Whisper, DuckDB, Playwright, Blender, Inkscape, Kdenlive, GIMP, OBS from the command line |
| `penpot-local` | Penpot design work through its local MCP server, started only when needed |
| `research` | cited web research with the agents' own free web search and fetch |
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
`aos` itself: `status`, `sync`, `test`, `new`, `video new` (a video project from the template), `who` (claims), `note`, `delegate codex|claude` (hand a task to the other
vendor), `secret` (keys; never print them), `place` (known folders), `install <layer>`.

## Other agents

| Agent | Reach it with | Good for |
|---|---|---|
| Codex | `/codex:rescue`, `codex-rescue` subagent, `codex exec --profile review "<prompt>" </dev/null`, `aos delegate codex` | well-specified implementation, tests, mechanical refactors, reviews |
| Claude Code | `$cc:rescue`, `$cc:review`, `aos delegate claude` | ambiguous or design work, prose, UI, cited research with many fetched pages |
| Pi on the local model (Paseo) | phone sessions; `web_search`, `file_search`, `text_read`, `pc_status` | small, well-defined tasks; its claims need checking |

## Browser and desktop

Claude Code has its own in-app browser and, when granted, Chrome and computer-use tools; use the browser
tools for web pages before computer use. Paseo is how the phone reaches Claude, Codex and Pi on this PC.

## How to use this list

1. Name the need, find the row, use the first match. If two fit, take the cheaper (command line, then skill, then server).
2. If nothing fits, say what is missing; do not invent a tool. Adding one is the user's call (see `docs/decisions.md`).
3. A tool you could not reach this session (not connected, not installed, wrong vendor) is reported as such, never as "not possible".
4. When you add a skill or server, add its row here; the test fails until you do.
