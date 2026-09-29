# Tool gateway (spec build step 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec success criterion 3: an agent finds, adds and uses a tool server it did not start with, through the gateway; a session that does not need it never loads it.

**Architecture:** Docker MCP Toolkit's gateway (`docker mcp gateway run`, stdio) is registered as one MCP server, `docker-gateway`, in Claude Code and Codex through `config/mcp.json` and `aos sync`. Its dynamic mode gives agents internal tools to search the Docker MCP catalog and add a server for the task; each server runs in its own container. No server is enabled by default, so a session starts with the internal tools only. Pi (the local agent) gets no gateway: every tool schema costs prompt in its 16K window (decisions, 2026-09-29).

**Spec:** `docs/superpowers/specs/2026-09-28-local-stack-design.md`, section "2. Tool gateway" and criterion 3.

## Facts measured on this PC (2026-09-29)

- Docker Desktop engine 29.8.1, WSL 2.7.14, `docker mcp` CLI v0.43.3. Feature `dynamic-tools` is already enabled (`docker mcp feature ls`); `mcp-oauth-dcr` enabled; `hooks` shows as an unknown feature.
- `docker mcp gateway run --dry-run --verbose`: no profile ("using empty configuration"), **no catalog** ("dynamic tools will be limited to profile servers. Run `docker mcp catalog pull mcp/docker-mcp-catalog:latest`"), 0 server tools, and 9 internal tools: `mcp-find`, `mcp-add`, `mcp-remove`, `code-mode`, `mcp-exec`, `mcp-config-set`, `mcp-create-profile`, `mcp-activate-profile`, and the `mcp-discover` prompt. It also failed to reach Docker Desktop's OAuth notification pipe from inside the Claude app (non-fatal).
- `--servers` turns dynamic tools off (gateway docs, dynamic_servers.md); `--profile` and `--servers` are exclusive. Defaults per server: 1 CPU, 2 GB memory, `--verify-signatures` and `--block-secrets` on.
- `~\.docker\mcp` holds empty `config.yaml`, `registry.yaml`, `tools.yaml` and `mcp-toolkit.db`.
- Not verified yet: whether `mcp-add` persists beyond the gateway process (registry or profile) or stays per session; the catalog's download size; how Codex approves MCP tool calls from the gateway in the app and in `codex exec` (the latter refuses calls that need approval: HANDOFF trap).

## Global Constraints

- The step 1-2 rules hold (ASCII, PowerShell 5.1 and 7, tests first and seen failing, idempotent, no secrets in files, merge never replace, back up first).
- Downloads with their size go to the user first: the catalog pull (Task 1), and every server image an agent adds. In Claude Code an `mcp-add` call is an MCP tool call, which asks for permission unless allowed; keep it that way (no `mcp__docker-gateway__*` in allow lists).
- Server secrets only through `docker mcp secret`, never files. `~\.wslconfig` (WSL memory cap) only with the user's consent.

---

### Task 1: `aos install gateway` (agentic-os)

- `Sync-AosGateway [-DryRun]`: skip with a warning when `docker` is missing or the engine is down (`docker version` fails); turn `dynamic-tools` on when it is off (`docker mcp feature enable dynamic-tools`); pull the catalog when `docker mcp catalog ls` lacks the Docker catalog (`docker mcp catalog pull mcp/docker-mcp-catalog:latest`, measured size in the confirmation). New layer `gateway` after `local` (bootstrap ValidateSet, `$script:Layers`, README).
- Tests with mocked `Invoke-AosCapture`: each step only when needed; DryRun changes nothing; engine down -> warning and nothing else.

### Task 2: register the gateway (agentic-os)

- `config/mcp.json`: `docker-gateway` = stdio, command `docker`, args `mcp gateway run --memory 1Gb` (no `--servers`, which would turn dynamic tools off). Registration condition: the `docker` command exists (a small extension of `requires`, e.g. `requires_command`, with a test), because Docker Desktop's path differs between per-user and machine installs.
- `aos sync` registers it in Claude Code and Codex (existing `Sync-AosMcp`); `aos status` reports it with the other MCP servers. Tests: the manifest entry, the command condition, registration in both agents.

### Task 3: acceptance (live)

- [ ] Claude Code (`claude -p`, the gateway's `mcp-find`/`mcp-add` allowed for this run only): a task that needs a tool the session does not have, e.g. "What is the title of https://example.com?", must go `mcp-find` -> `mcp-add fetch` -> the fetch tool -> "Example Domain". Record the image pulled and its size.
- [ ] A second session with an unrelated task: no server container starts (`docker ps`), the gateway lists only its internal tools.
- [ ] Whether the added server persists (registry/profile) or stays per session; if it persists, decide with the user whether `mcp-remove` or a clean profile keeps "never loads it" true.
- [ ] Codex: the same task in the Codex app (the user approves the MCP calls once); `codex exec` behaviour recorded.

### Task 4: WSL memory (the user's choice)

- Measure the WSL VM's memory with Ollama's model loaded and one server running. If it presses the 16 GB (Ollama on the GPU still uses RAM), propose `~\.wslconfig` `[wsl2] memory=4GB`; write it only after the user agrees (backup first, merge into an existing file).

### Task 5: plugin panel and docs

- The agentic-os panel's gateway section (deferred from the Paseo plan): catalog size and running server containers, from fixed read-only commands.
- README (layer, daily use), `docs/routing.md`, `docs/decisions.md` (numbers from Task 3).

## Review Focus

1. Dynamic mode stays on (no `--servers`), and nothing enables servers by default.
2. Every download (catalog, server images) reaches the user as a question with a size.
3. The `requires_command` extension and idempotence of `aos sync` with and without Docker running.
4. Whether `mcp-add` changes persistent state, which would break "a session that does not need it never loads it".
