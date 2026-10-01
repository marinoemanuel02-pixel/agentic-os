---
name: penpot-local
description: Use Penpot (free design tool) from an agent through its local MCP server, started only when needed. Use for "design in Penpot", "edit the Penpot file", design-to-code or tokens work; not for anything that needs no Penpot.
---

# Penpot, local and on demand

The local Penpot MCP server is installed under `~\.aos\penpot-mcp` (about 130 MB, plus a 130 MB pnpm cache in
`%LOCALAPPDATA%\pnpm`). It is **not** registered in any agent config and not running by default: a registered
server that is down shows as a failed connector in every session. Start it for the job, stop it after.

## Start (the user's design session)

1. Run `pwsh -File <repo>\agents-home\skills\penpot-local\start-penpot-mcp.ps1` in a terminal and leave it open.
   Background run for an agent: Bash/PowerShell with `run_in_background`. It serves the plugin on port 4400, the
   MCP endpoint on `http://localhost:4401/mcp` and a WebSocket on 4402; it downloads nothing at start.
2. In design.penpot.app, open a file, then Plugins > Load from URL > `http://localhost:4400/manifest.json`, run
   the plugin and press Connect to MCP server. Keep that browser tab active and the plugin window open.
   Chromium may block https to http://localhost; allow local network access or use Firefox.
3. Connect the agent for this session only: `claude mcp add --transport http penpot-local http://localhost:4401/mcp`
   (Claude Code), then `/mcp` shows it. This writes `~/.claude.json`: ask the user first, and remove it afterwards
   with `claude mcp remove penpot-local`. Codex: `codex mcp add penpot-local --url http://localhost:4401/mcp`
   (check `codex mcp add --help` first; the syntax has changed between versions).

## Use

Five tools: `execute_code`, `high_level_overview`, `penpot_api_info`, `export_shape`, `import_image`. The server
acts on the focused page of the one active Penpot tab. Start read-only (list pages, show components), say what
you will change before you change it, and prefer small reversible steps: write operations edit the live file.

## Stop

Ctrl+C in the terminal, or stop the process listening on port 4401. Remove the MCP registration.

## Rules

- No Penpot key is needed in local mode; never paste the user's remote MCP key (`aos secret penpot-mcp`) here.
- Do not run `npx @penpot/mcp` directly: its launcher downloads pnpm and 130 MB of dependencies on first start.
- If `start-penpot-mcp.ps1` says it is not installed, tell the user; do not install without their approval and
  the measured size.
