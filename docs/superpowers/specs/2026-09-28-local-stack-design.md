# Local stack, on-demand tools, calibrated NAR tool, phone app - design

Status: design approved in chat on 2026-09-28 (sections 1 and 2); this file awaits the user's review.
Next step after approval: an implementation plan (superpowers writing-plans), critiqued by Codex
before any code.

## Goal

What the user asked for (2026-09-28):
- use an offline, local model stack that runs on this laptop, with the best recently released models;
- an ad hoc repo for reinforcement learning toward calibrated decisions that leverages a
  **non-autoregressive** model, used as additional tooling "when the operation would benefit from
  using it";
- the popular repos that give LLMs access to many tools, loaded only when a task needs them;
- all of it usable from the phone (Android) through an ad hoc app.

Chosen approach: **A - Paseo as the phone app plus our own plugin** (over a from-scratch app and
over Open WebUI). Default local model: **MiniCPM5-2B**, subject to a local bake-off.

### Success criteria (each one checkable)

1. From the Android phone, away from home, start a session on this PC with each of Claude Code,
   Codex and the local model, and answer a permission prompt from the phone.
2. With the PC offline, the local model answers a prompt and a `nar_choose` call succeeds.
3. An agent finds, adds and uses a tool server it did not start with, through the gateway; a
   session that does not need it never loads it.
4. `nar_choose` returns calibrated probabilities; after feedback the calibrator is refitted; a
   calibrator that is worse on the held-out calls is never promoted (automated test).
5. A new local model becomes the default only if the eval says it is no worse than the current one.
6. `aos status`, run in a terminal outside both desktop apps, reports the local layer, the gateway
   and `nar` as ok.

## Constraints

- Hardware: i7-9750H (6 cores / 12 threads), 16 GB RAM, GTX 1660 Ti 6 GB (Turing, CUDA 7.5).
  Anything that does not fit 6 GB of VRAM runs split with the CPU and is several times slower.
- Subscriptions: Claude Pro (its login only in Claude's own apps and Claude Code) and ChatGPT Plus.
  No paid API keys are planned; Paseo drives the official CLIs, which is allowed.
- Windows native. Both desktop apps are MSIX: nothing is installed or cloned under AppData from
  inside them (winget installs and the home folder are fine).
- No secrets in files: `aos secret` for ours, Docker's secret store for tool servers.
- agentic-os rules hold: `aos.psm1` ASCII and 5.1/7-compatible, tests first, idempotent,
  a second opinion before writes to `~/.claude`, `~/.codex` or the user PATH.
- Exception to "no model names in the repo": local model tags live in exactly one file,
  `config/local.json`, which changes only through the eval gate (criterion 5). Cloud models stay unnamed.

## Architecture

Five parts, each with one job.

| Part | What | Where |
|---|---|---|
| 1. Local model | Ollama serving the default model on `localhost:11434` (native API with logprobs, OpenAI-compatible API) | agentic-os: `aos install local`, `config/local.json`; models in `~\.ollama` |
| 2. Tool gateway | Docker's MCP gateway (`docker/mcp-gateway`, MIT) in front of Docker's MCP catalog; agents see a few gateway tools (find / add / call) and start a server only when needed | Docker Desktop (installed by the user); registered through agentic-os `config/mcp.json` |
| 3. NAR tool | `nar` MCP server: single-forward-pass, calibrated scoring of options with the local model | new repo `Desktop\1-Projects\nar-tools` |
| 4. Learning loop | logs every `nar` call, takes outcome feedback, refits calibration, promotes only without regression; the same gate decides local model upgrades | `nar-tools`; data in `~\.aos\nar` |
| 5. Phone | Paseo daemon on the PC (Claude Code, Codex, OpenCode on the local model) + Android app over Paseo's end-to-end-encrypted relay; our plugin adds panels | Paseo from its official release; plugin in `nar-tools/paseo-plugin` |

### 1. Local model layer (agentic-os)

- `aos install local`: winget `Ollama.Ollama`; `ollama pull` each tag in `config/local.json`
  (`default`, plus `optional`); report whether the default runs fully on the GPU (`ollama ps`).
- `config/local.json` also feeds generated config: a Codex profile `local` (open-source provider,
  the default tag) and OpenCode's Ollama provider (OpenCode installed with npm into `~\.npm-global`).
- `aos status` gains: Ollama reachable, default model present, GPU share.
- Candidates for the first bake-off (verified in Ollama's library / OpenBMB's Hugging Face,
  2026-09-28): MiniCPM5-2B Q8_0 (about 5.3 GB of VRAM with context), `qwen3.5:4b` (3.4 GB,
  also reads images), `granite4.2:3b`. Too large for this laptop: `qwen3.8` (27B),
  `laguna-xs-2.1` (20 GB), `qwen3.8-flash-next` (105 GB), 30B models. `qwen3.5:4b` stays installed
  for images if it loses the text bake-off.

### 2. Tool gateway

- Docker Desktop with its MCP Toolkit provides `docker mcp gateway run`, registered as one stdio MCP
  server in Claude Code, Codex and OpenCode. Dynamic mode: agents search the catalog, add a
  server for the task and call it; each server runs in its own container.
- Claude Code already defers MCP tools (tool search), so the gateway costs it little; for Codex and
  the small local model it keeps the visible tool list short.
- WSL2's memory is capped (about 4 GB) so the VM leaves room for Ollama and the agents; that file
  (`~\.wslconfig`) is written only with the user's consent.

### 3. `nar` MCP server (nar-tools)

Python 3.13 with uv, the official MCP Python SDK, stdio transport. Tools:

- `nar_choose(question, options, task_type="general")` -> `call_id`, probability per option,
  `choice`, `confidence`, `calibrator_version`. Up to 20 options.
- `nar_classify(items, labels, task_type)` -> probabilities per item (a batch of `nar_choose`).
- `nar_feedback(call_id, outcome)` -> records which option was right.
- `nar_status()` -> counts, calibrator versions, last promotion, current reliability.

Scoring is the non-autoregressive part: the options are lettered in the prompt, the model runs
**one** forward pass (`num_predict` 1, `logprobs`, `top_logprobs` 20, available since Ollama
0.12.11), and the next-token log-probabilities of the option letters are normalised into a
distribution over all options at once. Letters missing from the top 20 get a floor value. The
calibrator applies a per-task-type temperature.

Tool descriptions tell agents when a call pays off: choosing among candidates (plans, fixes,
answers), triage of many items, and deciding whether to escalate to a stronger model.

A diffusion text backend (parallel infilling) is out of v1: llama.cpp support is a draft and Ollama
cannot run one yet. It stays a watch item and would be a second backend behind the same tools.

### 4. Learning loop (nar-tools)

- Storage (local only, outside OneDrive and git): `~\.aos\nar\calls.jsonl`, `feedback.jsonl`,
  `calibrators\<task_type>\v<N>.json`, `current.json`, `promotions.jsonl`.
- Held-out set: calls whose `call_id` hash mod 5 is 0, so the split is stable over time.
- Refit after every 20 new outcomes for a task type (or on demand, `nar fit`): fit the temperature
  on the training calls by minimising negative log-likelihood; compare candidate and current on the
  held-out calls by Brier score and expected calibration error; promote only if both are no worse.
  Every decision is appended to `promotions.jsonl`; rollback means pointing `current.json` back.
- Model upgrades use the same rule: `nar eval --models a,b,...` runs a fixed task set with
  deterministic decoding (temperature 0, fixed seed) and writes a report. Gated metrics: tool-call
  success rate, `nar_choose` accuracy, and calibration error; the candidate must be no worse than the
  current default on each of them. Hard limits, not comparisons: it runs entirely on the 6 GB GPU and
  generates at least 15 tokens per second on this laptop. `aos local adopt <tag>` changes
  `config/local.json` only if the latest report shows the candidate passing both.

### 5. Phone: Paseo and the plugin

- Paseo desktop for Windows from its official release; daemon on `127.0.0.1:6767`; the user pairs the
  Android app by QR code; remote traffic goes through Paseo's zero-knowledge relay, end-to-end
  encrypted; on home Wi-Fi the phone connects directly.
- Providers: Claude Code and Codex (the subscriptions, through the official CLIs), OpenCode on the
  local model.
- Plugin v1 panels: `aos status` output, the gateway's server list, the calibration dashboard
  (reliability before and after, promotions), and feedback buttons on recent `nar` calls.

## Data flow

1. The user types or speaks in the Paseo app; the relay carries it to the daemon, which starts the
   chosen agent.
2. The agent loads the shared contract and skills, sees the gateway's few tools and `nar`, and adds a
   tool server only when the task needs one.
3. At a choice point the agent may call `nar_choose` and use the calibrated confidence (for example,
   escalate to Claude or Codex below a threshold).
4. When the outcome is known, the agent or the user (plugin button) calls `nar_feedback`; the loop
   refits and promotes only without regression; the dashboard shows the effect.

## Failure handling

- Ollama down: `nar` answers "unavailable" and agents continue without it.
- Gateway or Docker down: agents keep their built-in tools.
- Relay down: direct connection on home Wi-Fi.
- A calibrator or model that fails the gate stays a candidate; nothing is promoted.

## Security

- Tool servers run in containers with no access to the user's files unless a server is given a folder;
  their keys come from Docker's secret store, never files.
- The plugin never runs user- or model-supplied commands; the only commands it runs are the fixed,
  read-only `aos status` and the gateway's server listing. It writes only feedback records.
- Claude Code and Codex keep their own permission prompts; answers come from the phone.
- `nar` logs contain task text; they stay in `~\.aos\nar` (not synced, not committed).

## Testing and acceptance

- nar-tools: pytest with recorded Ollama responses (no live model in unit tests): letter
  extraction and normalisation, the floor for missing letters, temperature fitting, the promotion
  gate (a worse candidate is never promoted; a better one is), storage, MCP tool schemas.
  CI on GitHub Actions (windows-latest).
- agentic-os: Pester tests for `aos install local` / `aos local adopt` / generated configs, with
  mocked Ollama and winget; `aos test` in both shells; CI as today.
- The bake-off eval is also the regression test for model upgrades.
- Acceptance: the six success criteria, run once end to end, criterion 1 from the phone.

## Build order and ownership

Each step is usable on its own. One implementation plan per step, starting with steps 1 and 2 (the
later steps wait on the user's Docker Desktop install and phone pairing).

1. `aos install local` + `config/local.json` + the bake-off -> default model chosen; the contract's
   "No local models" machine fact is replaced by when to use the local model and where it is configured.
2. nar-tools v1: `nar_choose`, `nar_classify`, `nar_feedback`, `nar_status`, the loop and the gate;
   registered in all three agents.
3. Tool gateway, after the user installs Docker Desktop; registered in all three agents.
4. Paseo, pairing, OpenCode on the local model.
5. Paseo plugin.

Codex writes most implementation and tests; Claude designs, reviews and owns agentic-os changes;
Codex critiques the implementation plan before code (plans-before-big-work rule).

## User actions

- Install Docker Desktop and accept its WSL2 setup (Windows features and a reboot are the user's to approve).
- Install Paseo on the phone and pair it by QR code.
- Consent to the `~\.wslconfig` memory cap.

## Out of scope for this spec

- A diffusion (non-autoregressive) text model: a later backend once Ollama or mainline llama.cpp runs one here.
- Reinforcement learning on model weights (LoRA/RL fine-tuning): too slow on a 6 GB GPU.
- Tool catalogs that need accounts (for example Composio).
- Autostart at logon or scheduled jobs (each needs the user's consent; can follow later).

## To verify during implementation

- Paseo's plugin API: a panel can read local files and run a fixed command (step 5 starts here).
- Docker MCP gateway's dynamic-mode options on Windows (step 3 starts here).
- MiniCPM5-2B's tool-calling template under Ollama, and its logprobs output (step 1 bake-off).

## Sources

- Ollama library: https://ollama.com/library/qwen3.5 , https://ollama.com/library/gpt-oss ,
  https://ollama.com/library/laguna-xs-2.1 , https://ollama.com/search?o=newest
- MiniCPM5-2B: https://huggingface.co/openbmb/MiniCPM5-2B-GGUF ,
  https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/ollama.md
- Ollama logprobs (0.12.11): https://github.com/ollama/ollama/pull/18591
- Docker MCP gateway: https://github.com/docker/mcp-gateway ; gateways list: https://github.com/e2b-dev/awesome-mcp-gateways
- Paseo: https://github.com/getpaseo/paseo (docs/architecture.md: daemon, relay, pairing)
- Diffusion LLM status: https://diffusiongemma.org/how-to-run , https://github.com/ggml-org/llama.cpp/discussions/12208
- RL for diffusion LLMs (out of scope): https://github.com/dllm-reasoning/d1
