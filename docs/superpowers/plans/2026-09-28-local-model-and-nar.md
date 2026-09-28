# Local model layer and nar-tools v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An `aos install local` layer that runs a local model through Ollama, and a new `nar-tools` repo whose `nar` MCP tools score options in one forward pass of that model, learn calibration from outcomes without regressing, and gate local model upgrades - registered in Claude Code and Codex.

**Architecture:** agentic-os gains a `local` layer (Ollama via winget, model tags in `config/local.json`, generated `~\.aos\local.json` and Codex `local` profile) plus MCP placeholders so `nar` registers from a venv under `~\.aos`. `nar-tools` (Python, uv) is a small package: an Ollama client, single-pass letter scoring, temperature calibration, append-only storage, the promotion gate, a service layer, a FastMCP stdio server, and the bake-off. Build steps 1 and 2 of the spec; the gateway, Paseo and OpenCode (steps 3-5) get their own plans. One deliberate move from the spec's step 1: OpenCode's Ollama provider config and its `nar` registration go to the step-4 plan, where OpenCode is installed and the config can be verified.

**Tech Stack:** PowerShell 5.1 + 7 and Pester 5 (agentic-os); Python 3.13, uv, `mcp` (FastMCP) 1.x, `httpx`, pytest (nar-tools); Ollama 0.12.11 or newer.

**Spec:** `docs/superpowers/specs/2026-09-28-local-stack-design.md`

## Global Constraints

- `aos.psm1` and `bootstrap.ps1` stay ASCII-only and run under Windows PowerShell 5.1 and PowerShell 7: no `??`, no ternary, no `&&`/`||`.
- Tests first: every new test is run and seen failing before its code exists (agentic-os rule 3).
- Tests use `$TestDrive`, `$env:AOS_BACKUPS`, `tmp_path` and fakes - never the real profile, registry, network, npm config or a live Ollama. Live checks happen only in Task 13.
- Idempotent: a second `aos sync` / `aos install local` changes nothing.
- Nothing is installed or cloned under AppData from inside the desktop apps: state in `~\.aos`, models in `~\.ollama`, the nar venv in `~\.aos\venvs\nar-tools`.
- Local model tags live only in `config/local.json` and change only through `aos local adopt` (the eval gate). Cloud models stay unnamed.
- No absolute paths in either repo; `{{home}}` / `{{projects}}` placeholders resolve at run time.
- No secrets in files.
- `nar` data (task text) stays in `NAR_HOME` (default `~\.aos\nar`), never in OneDrive or git.
- At most 20 options per `nar_choose` (Ollama returns at most 20 alternatives per position).
- Promotion rule: a refitted calibrator replaces the current one only if Brier score AND expected calibration error on the held-out calls are both no worse. Model rule: gated metrics (tool-call success, `nar_choose` accuracy, calibration error) no worse than the current default; hard limits: fully on the 6 GB GPU and at least 15 tokens/s.

## Review Focus

1. Ollama not running, or the model not pulled, when an agent calls a nar tool -> a structured `{"unavailable": true, "reason": ...}` result, never an exception (test in Task 10).
2. The model's first token is not an option letter (it starts thinking, writes prose, answers in lowercase) -> equal probabilities with `letter_signal: false`, never a crash or a confident wrong pick (test in Task 5).
3. Bad inputs: fewer than 2 or more than 20 options, empty or duplicate options, a `task_type` with path characters, more than 50 items to classify -> an error result and nothing logged (tests in Task 9).
4. Feedback for an unknown `call_id`, an out-of-range index, a boolean, or text matching no option -> an error and nothing appended (tests in Task 9).
5. Claude, Codex and OpenCode each run their own `nar-mcp` process; two refits at once -> the refit lock admits one, lines stay whole (tests in Task 7; `gate.refit` holds the lock).

## File Structure

agentic-os (branch `local-stack`):
- `config/local.json` (new): default/optional/candidate model tags, Ollama URL, speed floor.
- `packages.json` (modify): new `local` list with `Ollama.Ollama`.
- `config/mcp.json` (modify): `nar` server with `{{home}}` placeholders and `requires`.
- `aos.psm1` (modify): local layer, local state, Codex `local` profile, MCP placeholders and `Add-AosMcpServer`, nar venv, `aos nar`, `aos local adopt`, status lines.
- `bootstrap.ps1` (modify): `local` in the layer list.
- `tests/aos.Tests.ps1` (modify): Describe blocks for each aos task.
- `agents-home/AGENTS.md`, `README.md`, `docs/decisions.md`, `docs/routing.md` (modify, Task 14).

nar-tools (new repo `Desktop\1-Projects\nar-tools`):
- `pyproject.toml`, `uv.lock`, `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.gitattributes`, `.github/workflows/ci.yml`
- `src/nar_tools/__init__.py`, `ollama.py` (HTTP client), `scoring.py` (letters -> log-probs), `calibration.py` (temperature, Brier, ECE), `store.py` (JSONL, calibrators, lock), `gate.py` (the promotion rule), `service.py` (what the tools do), `server.py` (FastMCP), `evaluate.py` (bake-off), `cli.py` (`nar`)
- `src/nar_tools/evals/choose.jsonl`, `tools.jsonl`, `toolset.json`
- `tests/test_*.py`, one per module.

## Who does what

Tasks 1, 2 and 12 (agentic-os): Codex writes the Pester tests (at least the ones below), Claude implements. Tasks 3-11 (nar-tools): Codex implements test and code per task in its sandbox; Claude reviews each task's diff, runs the tests and commits (Codex's sandbox cannot write `.git`). Tasks 13-14: Claude, with the user for the downloads.

---

### Task 1: The `local` layer in aos

**Files:**
- Create: `config/local.json`
- Modify: `packages.json` (add `local` list), `aos.psm1` (new functions after `Get-AosProjectsDir`; `$script:Layers`; `Install-AosLayer` switch; `Get-AosStatus`), `bootstrap.ps1` (ValidateSet)
- Test: `tests/aos.Tests.ps1` (new `Describe 'Local model layer'` inside the outer Describe)

**Interfaces:**
- Produces: `Get-AosLocalConfigPath`, `Get-AosLocalConfig` (ordered dictionary or `$null`), `Get-AosStateDir` (`~\.aos`), `Test-AosOllamaModel -List <ollama list text> -Tag <tag>` (bool), `Sync-AosLocalState [-DryRun]` (writes `~\.aos\local.json` with `default` and `ollama_url`), `Install-AosLocal [-DryRun]`.

- [ ] **Step 1: Write the failing tests** (append inside the outer `Describe 'aos isolated suite'`, before its closing brace)

```powershell
Describe 'Local model layer' {
    BeforeEach {
        $stateDir = Join-Path $caseRoot 'state'
        Mock Get-AosStateDir -ModuleName aos { $stateDir }
        Mock Get-AosLocalConfig -ModuleName aos {
            [ordered]@{ default = 'openbmb/minicpm5-2b:q8_0'; optional = @('qwen3.5:4b'); ollama_url = 'http://127.0.0.1:11434' }
        }
        Mock Install-AosWingetPackage -ModuleName aos { }
        Mock Install-AosNarTools -ModuleName aos { }
        Mock Write-AosWarn -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'ollama' }
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME                        ID     SIZE      MODIFIED`nopenbmb/minicpm5-2b:q8_0    abc    2.7 GB    1 day ago" }
        } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'success' } } -ParameterFilter { $CommandLine -like 'ollama pull *' }
    }

    It 'matches Ollama tags exactly, treating a bare name as :latest' {
        InModuleScope aos {
            $list = "NAME ID SIZE`nqwen3.5:4b x 3.4 GB`nllama3.2:latest y 2.0 GB"
            Test-AosOllamaModel -List $list -Tag 'qwen3.5:4b' | Should -BeTrue
            Test-AosOllamaModel -List $list -Tag 'QWEN3.5:4B' | Should -BeTrue
            Test-AosOllamaModel -List $list -Tag 'llama3.2' | Should -BeTrue
            Test-AosOllamaModel -List $list -Tag 'qwen3.5' | Should -BeFalse
            Test-AosOllamaModel -List $list -Tag 'qwen3.5:4b-q8_0' | Should -BeFalse
        }
    }

    It 'pulls only the configured models that are missing and writes the local state file' {
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'ollama pull qwen3.5:4b' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -eq 'ollama pull openbmb/minicpm5-2b:q8_0' }
        $state = Get-Content -Raw (Join-Path $stateDir 'local.json') | ConvertFrom-Json
        $state.default | Should -BeExactly 'openbmb/minicpm5-2b:q8_0'
        $state.ollama_url | Should -BeExactly 'http://127.0.0.1:11434'
        Should -Invoke Install-AosNarTools -ModuleName aos -Times 1 -Exactly
    }

    It 'pulls nothing and writes nothing in DryRun' {
        InModuleScope aos { Install-AosLocal -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama pull *' }
        Test-Path -LiteralPath (Join-Path $stateDir 'local.json') | Should -BeFalse
        Should -Invoke Install-AosWingetPackage -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Id -eq 'Ollama.Ollama' -and $DryRun }
    }

    It 'warns and pulls nothing when ollama is not on PATH' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'ollama' }
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'ollama' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }

    It 'leaves the local state file untouched when it already says the same thing' {
        InModuleScope aos { Sync-AosLocalState }
        $before = (Get-Item -LiteralPath (Join-Path $stateDir 'local.json')).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50
        InModuleScope aos { Sync-AosLocalState }
        (Get-Item -LiteralPath (Join-Path $stateDir 'local.json')).LastWriteTimeUtc | Should -Be $before
    }
}
```

`Install-AosNarTools` is mocked here and implemented in Task 12; add a stub now so the mock has a target:

```powershell
function Install-AosNarTools([switch]$DryRun) { }
```

- [ ] **Step 2: Run the tests, see them fail**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1`
Expected: the 5 new tests FAIL (`Get-AosStateDir` / `Install-AosLocal` not found); the existing 124 pass.

- [ ] **Step 3: Implement**

`config/local.json`:

```json
{
  "_readme": [
    "Local models served by Ollama (aos install local). The only file in this repo that names models.",
    "default: the local brain; change it only with `aos local adopt <tag>` after `aos nar eval` passes.",
    "optional: also pulled (qwen3.5:4b reads images; MiniCPM5-2B is text-only).",
    "candidates: tags for the next bake-off; pulled by hand (`ollama pull <tag>`), not by aos."
  ],
  "default": "openbmb/minicpm5-2b:q8_0",
  "optional": ["qwen3.5:4b"],
  "candidates": ["openbmb/minicpm5-2b:q8_0", "qwen3.5:4b", "granite4.2:3b"],
  "ollama_url": "http://127.0.0.1:11434",
  "min_tokens_per_s": 15
}
```

`packages.json`: add after `"base": [...]`:

```json
  "local": [
    { "id": "Ollama.Ollama",              "why": "local model runtime (CUDA on the GTX 1660 Ti); models live in ~\\.ollama" }
  ],
```

`aos.psm1`: `$script:Layers = @('base', 'engines', 'brain', 'bridges', 'refs', 'local')`; in `Install-AosLayer`'s switch add `'local'   { Install-AosLocal -DryRun:$DryRun }`; add after `Get-AosProjectsDir`:

```powershell
function Get-AosLocalConfigPath { return (Join-Path $script:Root 'config\local.json') }

function Get-AosLocalConfig {
    $path = Get-AosLocalConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Read-AosJson $path
}

function Get-AosStateDir { return (Join-Path $HOME '.aos') }

function Test-AosOllamaModel([string]$List, [string]$Tag) {
    # `ollama list` prints one model per line, NAME first; a bare name means :latest.
    $want = $Tag
    if ($want -notmatch ':') { $want = "${want}:latest" }
    foreach ($line in ($List -split "`r?`n")) {
        $name = ($line.Trim() -split '\s+')[0]
        if ($name -ieq $want) { return $true }
    }
    return $false
}

function Sync-AosLocalState([switch]$DryRun) {
    # ~\.aos\local.json tells nar which model is the local default. Compared by value, not text:
    # PowerShell 5.1 and 7 format JSON differently, and either may run aos.
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { return }
    $target = Join-Path (Get-AosStateDir) 'local.json'
    $have = Read-AosJson $target
    if ($have -and ($have['default'] -eq $cfg['default']) -and ($have['ollama_url'] -eq $cfg['ollama_url'])) { Write-AosOk "$target up to date"; return }
    if ($DryRun) { Write-AosDry "would write $target"; return }
    $state = [ordered]@{ default = $cfg['default']; ollama_url = $cfg['ollama_url'] }
    Write-AosText -Path $target -Text ((ConvertTo-Json -InputObject $state -Depth 5) + "`n")
    Write-AosOk "wrote $target"
}

function Install-AosLocal([switch]$DryRun) {
    Update-AosPath
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { Write-AosWarn 'config/local.json missing'; return }
    Write-AosStep 'Local models (Ollama; models in ~\.ollama)'
    foreach ($p in (Get-AosPackages)['local']) { Install-AosWingetPackage -Id $p['id'] -Why $p['why'] -DryRun:$DryRun }
    Update-AosPath
    if (-not (Test-AosCommand ollama)) {
        if (-not $DryRun) { Write-AosWarn 'ollama is not on PATH yet: open a new terminal, then aos install local' }
        return
    }
    $list = (Invoke-AosCapture 'ollama list').Text
    foreach ($tag in @(@($cfg['default']) + @($cfg['optional']) | Where-Object { $_ })) {
        if (Test-AosOllamaModel -List $list -Tag $tag) { Write-AosOk "model $tag"; continue }
        if ($DryRun) { Write-AosDry "ollama pull $tag"; continue }
        Write-AosInfo "pulling $tag (a large download)"
        $r = Invoke-AosCapture "ollama pull $tag"
        if ($r.Code -eq 0) { Write-AosOk "pulled $tag" } else { Write-AosWarn "ollama pull $tag failed (exit $($r.Code))" }
    }
    Sync-AosLocalState -DryRun:$DryRun
    Install-AosNarTools -DryRun:$DryRun
}
```

`Get-AosStatus`: after the Tools section add:

```powershell
    $local = Get-AosLocalConfig
    if ($local) {
        Write-AosStep 'Local models'
        if (-not (Test-AosCommand ollama)) { Write-AosWarn 'ollama missing (aos install local)' }
        else {
            $r = Invoke-AosCapture 'ollama list'
            if ($r.Code -ne 0) { Write-AosWarn 'ollama is installed but not running (start the Ollama app)' }
            elseif (Test-AosOllamaModel -List $r.Text -Tag $local['default']) { Write-AosOk "default model $($local['default'])" }
            else { Write-AosWarn "default model $($local['default']) not pulled (aos install local)" }
        }
    }
```

`bootstrap.ps1`: `[ValidateSet('all','base','engines','brain','bridges','refs','local')]`.

`Show-AosHelp`: the install line reads `base | engines | brain | bridges | refs | local | all`.

- [ ] **Step 4: Run the tests, see them pass**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module .\aos.psm1 -Force -DisableNameChecking; aos test; exit $LASTEXITCODE"`
Expected: static checks ok; all tests pass in both shells (124 + 5).

- [ ] **Step 5: Commit**

```bash
git add config/local.json packages.json aos.psm1 bootstrap.ps1 tests/aos.Tests.ps1
git commit -m "aos: local layer (Ollama, models from config/local.json, ~/.aos/local.json)"
```

---

### Task 2: Codex `local` profile from `config/local.json`

**Files:**
- Modify: `aos.psm1` (`Get-AosCodexProfiles`)
- Test: `tests/aos.Tests.ps1` (`Describe 'Codex local profile'`)

**Interfaces:**
- Consumes: `Get-AosLocalConfig` (Task 1).
- Produces: a profile object `Name = 'local'`, `Target = ~\.codex\local.config.toml`; `aos sync` writes it through the existing `Sync-AosCodexProfiles`.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'Codex local profile' {
    It 'generates a local profile from config/local.json' {
        Mock Get-AosLocalConfig -ModuleName aos { [ordered]@{ default = 'openbmb/minicpm5-2b:q8_0' } }
        InModuleScope aos {
            $p = @(Get-AosCodexProfiles | Where-Object { $_.Name -eq 'local' })
            $p.Count | Should -Be 1
            $p[0].Target | Should -BeExactly (Join-Path $HOME '.codex\local.config.toml')
            $p[0].Text | Should -Match '(?m)^model_provider = "ollama"$'
            $p[0].Text | Should -Match '(?m)^model = "openbmb/minicpm5-2b:q8_0"$'
            $p[0].Text | Should -Match '^# GENERATED by agentic-os'
        }
    }

    It 'generates no local profile without a local config' {
        Mock Get-AosLocalConfig -ModuleName aos { $null }
        InModuleScope aos { @(Get-AosCodexProfiles | Where-Object { $_.Name -eq 'local' }).Count | Should -Be 0 }
    }
}
```

- [ ] **Step 2: Run, see them fail** (`tests\Run-Tests.ps1`; expected: 2 new FAIL)

- [ ] **Step 3: Implement** - at the end of `Get-AosCodexProfiles`, before `return $list`:

```powershell
    # The local profile names a model, so it is generated from config/local.json (the one file that may).
    $local = Get-AosLocalConfig
    if ($local -and $local['default']) {
        $text = @(
            '# GENERATED by agentic-os (aos sync) from config/local.json. Edit the repo copy, not this file.',
            '# codex --profile local : the local model through Ollama (offline and private; much weaker than the cloud models).',
            'model_provider = "ollama"',
            ('model = "' + $local['default'] + '"')
        ) -join "`n"
        $list += [pscustomobject]@{ Name = 'local'; Target = (Join-Path $HOME '.codex\local.config.toml'); Text = $text + "`n" }
    }
```

- [ ] **Step 4: Run, see them pass** (`aos test`; both shells green)

- [ ] **Step 5: Commit**

```bash
git add aos.psm1 tests/aos.Tests.ps1
git commit -m "aos: generate the Codex local profile from config/local.json"
```

---

### Task 3: nar-tools repository scaffold

**Files:**
- Create (via `aos new nar-tools`): `Desktop\1-Projects\nar-tools\{AGENTS.md,CLAUDE.md,.gitignore,.gitattributes}` and git init
- Create: `pyproject.toml`, `src/nar_tools/__init__.py`, `tests/test_smoke.py`, `.github/workflows/ci.yml`
- Modify: `AGENTS.md` (fill the template)

**Interfaces:**
- Produces: importable package `nar_tools` with `__version__`; console scripts `nar` (`nar_tools.cli:main`) and `nar-mcp` (`nar_tools.server:main`) declared now, implemented in Tasks 10-11.

- [ ] **Step 1: Create the project**

Run (pwsh): `aos new nar-tools` - expect `created AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.gitattributes`, `git init` in `Desktop\1-Projects\nar-tools`.

- [ ] **Step 2: Write the failing smoke test** `tests/test_smoke.py`

```python
import nar_tools


def test_package_imports_and_has_a_version():
    assert nar_tools.__version__ == "0.1.0"
```

- [ ] **Step 3: Add the project files**

`pyproject.toml`:

```toml
[project]
name = "nar-tools"
version = "0.1.0"
description = "Calibrated single-pass (non-autoregressive) option scoring with a local model, as MCP tools"
requires-python = ">=3.13"
dependencies = ["mcp>=1.10,<2", "httpx>=0.27,<1"]

[project.scripts]
nar = "nar_tools.cli:main"
nar-mcp = "nar_tools.server:main"

[dependency-groups]
dev = ["pytest>=8"]

[build-system]
requires = ["hatchling>=1.25"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/nar_tools"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

`src/nar_tools/__init__.py`:

```python
"""nar-tools: calibrated single-pass scoring with the local model."""

__version__ = "0.1.0"
```

`.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --locked
      - run: uv run pytest -q
```

`AGENTS.md` (replace the template body):

```markdown
# nar-tools

Instructions for Claude Code and Codex. `CLAUDE.md` imports this file, so write it once here.
The global contract (`~/.agents/AGENTS.md`) already applies; only add what is specific to this project.

## What this is

The `nar` MCP tools: calibrated, single-forward-pass (non-autoregressive) scoring of options with the
local model (Ollama); a learning loop that refits calibration from outcome feedback and promotes a new
calibrator only if it is no worse on held-out calls; and `nar eval`, the bake-off that gates local model
upgrades. Design: agentic-os `docs/superpowers/specs/2026-09-28-local-stack-design.md`.

## Commands

Keep the dev venv out of OneDrive (once per shell):
`$env:UV_PROJECT_ENVIRONMENT = "$HOME\.aos\venvs\nar-tools-dev"`

- Install: `uv sync`
- Test: `uv run pytest -q`
- Server (stdio): `uv run nar-mcp`
- CLI: `uv run nar status`, `uv run nar eval --models a,b`, `uv run nar fit --task-type general`

## Done means

- `uv run pytest -q` passes. Unit tests never call a live Ollama (fakes or `httpx.MockTransport`).

## Conventions

- Python 3.13, standard library first; runtime dependencies only `mcp` and `httpx`.
- Data lives in `NAR_HOME` (default `~\.aos\nar`), never in the repo or OneDrive.
- The promotion rule in `gate.py` is the product: a candidate replaces the current calibrator only if
  Brier score and ECE on the held-out calls are both no worse.

## Risky areas (get a second opinion from the other vendor before changing)

- `gate.py` and `calibration.py` (the non-regressive rule); `store.py` locking.
```

- [ ] **Step 4: Run it**

Run: `$env:UV_PROJECT_ENVIRONMENT = "$HOME\.aos\venvs\nar-tools-dev"; uv sync; uv run pytest -q`
Expected: `1 passed`; `uv.lock` created.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "nar-tools: project scaffold, uv, CI"
```

---

### Task 4: Ollama client

**Files:**
- Create: `src/nar_tools/ollama.py`
- Test: `tests/test_ollama.py`

**Interfaces:**
- Produces: `class OllamaUnavailable(RuntimeError)`; `@dataclass(frozen=True) TokenLogprob(token: str, logprob: float)`; `local_state(path: Path | None = None) -> dict`; `class OllamaClient(base_url=None, timeout=120.0, transport=None)` with `next_token_logprobs(model: str, messages: list[dict], top: int = 20) -> list[TokenLogprob]`, `chat(model, messages, tools=None, num_predict=None) -> dict`, `loaded_models() -> list[dict]`, `unload(model) -> None`.

- [ ] **Step 1: Write the failing tests** `tests/test_ollama.py`

```python
import json

import httpx
import pytest

from nar_tools.ollama import OllamaClient, OllamaUnavailable, TokenLogprob, local_state


def client_with(handler):
    return OllamaClient(base_url="http://ollama.test", transport=httpx.MockTransport(handler))


def test_next_token_logprobs_asks_for_one_token_with_top_20():
    seen = {}

    def handler(request):
        seen.update(json.loads(request.content))
        return httpx.Response(200, json={
            "message": {"role": "assistant", "content": "B"},
            "logprobs": [{"token": "B", "logprob": -0.1,
                          "top_logprobs": [{"token": "B", "logprob": -0.1}, {"token": "A", "logprob": -2.5}]}]})

    top = client_with(handler).next_token_logprobs("m", [{"role": "user", "content": "q"}])
    assert top == [TokenLogprob("B", -0.1), TokenLogprob("A", -2.5)]
    assert seen["options"]["num_predict"] == 1 and seen["options"]["temperature"] == 0
    assert seen["logprobs"] is True and seen["top_logprobs"] == 20
    assert seen["think"] is False and seen["stream"] is False


def test_unreachable_ollama_raises_unavailable():
    def handler(request):
        raise httpx.ConnectError("refused", request=request)

    with pytest.raises(OllamaUnavailable, match="cannot reach Ollama"):
        client_with(handler).next_token_logprobs("m", [])


def test_missing_logprobs_explains_the_version_floor():
    def handler(request):
        return httpx.Response(200, json={"message": {"content": "B"}})

    with pytest.raises(OllamaUnavailable, match="0.12.11"):
        client_with(handler).next_token_logprobs("m", [])


def test_retries_without_think_when_the_model_rejects_it():
    bodies = []

    def handler(request):
        body = json.loads(request.content)
        bodies.append(body)
        if "think" in body:
            return httpx.Response(400, json={"error": "\"m\" does not support thinking"})
        return httpx.Response(200, json={"logprobs": [{"token": "A", "logprob": -0.2,
                                                       "top_logprobs": [{"token": "A", "logprob": -0.2}]}]})

    assert client_with(handler).next_token_logprobs("m", []) == [TokenLogprob("A", -0.2)]
    assert len(bodies) == 2 and "think" not in bodies[1]


def test_unload_sets_keep_alive_zero():
    seen = {}

    def handler(request):
        seen.update(json.loads(request.content))
        return httpx.Response(200, json={"done": True})

    client_with(handler).unload("m")
    assert seen == {"model": "m", "keep_alive": 0}


def test_local_state_reads_the_file_and_tolerates_absence(tmp_path):
    p = tmp_path / "local.json"
    assert local_state(p) == {}
    p.write_text('{"default": "x:1", "ollama_url": "http://h:1"}', encoding="utf-8")
    assert local_state(p)["default"] == "x:1"
```

- [ ] **Step 2: Run, see them fail**

Run: `uv run pytest tests/test_ollama.py -q`
Expected: FAIL, `ModuleNotFoundError: nar_tools.ollama`.

- [ ] **Step 3: Implement** `src/nar_tools/ollama.py`

```python
"""Minimal Ollama client: one-step log-probabilities, chat with tools, loaded models."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

import httpx

DEFAULT_URL = "http://127.0.0.1:11434"


class OllamaUnavailable(RuntimeError):
    """Ollama is not reachable, or the model cannot serve the request."""


@dataclass(frozen=True)
class TokenLogprob:
    token: str
    logprob: float


def local_state(path: Path | None = None) -> dict:
    """~/.aos/local.json, written by `aos install local` and `aos sync`: default model, Ollama URL."""
    p = path or Path(os.environ.get("AOS_LOCAL_STATE") or (Path.home() / ".aos" / "local.json"))
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


class OllamaClient:
    def __init__(self, base_url: str | None = None, timeout: float = 120.0,
                 transport: httpx.BaseTransport | None = None) -> None:
        url = base_url or local_state().get("ollama_url") or DEFAULT_URL
        self.base_url = url.rstrip("/")
        self._http = httpx.Client(base_url=self.base_url, timeout=timeout, transport=transport)

    def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        try:
            r = self._http.request(method, path, json=body)
        except httpx.TransportError as e:
            raise OllamaUnavailable(f"cannot reach Ollama at {self.base_url} ({e.__class__.__name__})") from e
        if r.status_code >= 400:
            raise OllamaUnavailable(f"Ollama {path} returned {r.status_code}: {r.text[:200]}")
        return r.json()

    def _chat(self, body: dict) -> dict:
        try:
            return self._request("POST", "/api/chat", body)
        except OllamaUnavailable as e:
            # `think: false` keeps thinking models from spending the one token on "<think>";
            # a model without thinking support may reject the field, so try once without it.
            if "think" in body and "think" in str(e).lower():
                return self._request("POST", "/api/chat", {k: v for k, v in body.items() if k != "think"})
            raise

    def next_token_logprobs(self, model: str, messages: list[dict], top: int = 20) -> list[TokenLogprob]:
        """One forward pass: the most likely first tokens of the reply, with log-probabilities."""
        body = {"model": model, "messages": messages, "stream": False, "think": False,
                "logprobs": True, "top_logprobs": top,
                "options": {"num_predict": 1, "temperature": 0, "seed": 0}}
        entries = self._chat(body).get("logprobs") or []
        if not entries:
            raise OllamaUnavailable(f"{model} returned no logprobs (needs Ollama 0.12.11 or newer)")
        return [TokenLogprob(str(t["token"]), float(t["logprob"])) for t in entries[0].get("top_logprobs") or []]

    def chat(self, model: str, messages: list[dict], tools: list[dict] | None = None,
             num_predict: int | None = None) -> dict:
        options: dict = {"temperature": 0, "seed": 0}
        if num_predict is not None:
            options["num_predict"] = num_predict
        body: dict = {"model": model, "messages": messages, "stream": False, "think": False, "options": options}
        if tools:
            body["tools"] = tools
        return self._chat(body)

    def loaded_models(self) -> list[dict]:
        return self._request("GET", "/api/ps").get("models") or []

    def unload(self, model: str) -> None:
        """Free the GPU for the next model (keep_alive 0)."""
        self._request("POST", "/api/generate", {"model": model, "keep_alive": 0})
```

- [ ] **Step 4: Run, see them pass** (`uv run pytest tests/test_ollama.py -q` -> 6 passed)

- [ ] **Step 5: Commit** (`git add src/nar_tools/ollama.py tests/test_ollama.py; git commit -m "nar: Ollama client with one-step logprobs"`)

---

### Task 5: Single-pass letter scoring

**Files:**
- Create: `src/nar_tools/scoring.py`
- Test: `tests/test_scoring.py`

**Interfaces:**
- Consumes: `TokenLogprob` (Task 4).
- Produces: `LETTERS = "ABCDEFGHIJKLMNOPQRST"`, `MAX_OPTIONS = 20`, `build_messages(question: str, options: list[str]) -> list[dict]`, `letter_logprobs(top: list[TokenLogprob], n_options: int) -> tuple[list[float], bool]`.

- [ ] **Step 1: Write the failing tests** `tests/test_scoring.py`

```python
import math

import pytest

from nar_tools.ollama import TokenLogprob
from nar_tools.scoring import LETTERS, build_messages, letter_logprobs


def test_build_messages_letters_each_option():
    msgs = build_messages("Pick one", ["red", "green"])
    user = msgs[-1]["content"]
    assert "A. red" in user and "B. green" in user
    assert msgs[0]["role"] == "system" and "one capital letter" in msgs[0]["content"]


def test_variants_of_a_letter_add_up():
    top = [TokenLogprob("A", math.log(0.5)), TokenLogprob(" A", math.log(0.2)), TokenLogprob("B", math.log(0.3))]
    lps, signal = letter_logprobs(top, 2)
    assert signal is True
    assert math.isclose(math.exp(lps[0]), 0.7, rel_tol=1e-9)
    assert math.isclose(math.exp(lps[1]), 0.3, rel_tol=1e-9)


def test_decorated_letters_count_and_lowercase_does_not():
    top = [TokenLogprob("**C", math.log(0.4)), TokenLogprob("(B", math.log(0.3)), TokenLogprob("a", math.log(0.2))]
    lps, _ = letter_logprobs(top, 3)
    assert math.isclose(math.exp(lps[2]), 0.4) and math.isclose(math.exp(lps[1]), 0.3)
    assert lps[0] < math.log(0.2)          # "a" is not option A: A only gets the floor


def test_letters_beyond_the_options_are_ignored():
    lps, signal = letter_logprobs([TokenLogprob("C", -0.1), TokenLogprob("A", -3.0)], 2)
    assert signal is True
    assert lps[0] == -3.0 and lps[1] < -3.0


def test_no_letter_gives_equal_floors_and_no_signal():
    lps, signal = letter_logprobs([TokenLogprob("<think>", -0.05), TokenLogprob("The", -3.2)], 4)
    assert signal is False
    assert len(set(lps)) == 1 and math.isclose(lps[0], -3.2 - math.log(2.0))


@pytest.mark.parametrize("n", [0, 1, len(LETTERS) + 1])
def test_option_count_limits(n):
    with pytest.raises(ValueError):
        letter_logprobs([], n)
```

- [ ] **Step 2: Run, see them fail** (`uv run pytest tests/test_scoring.py -q` -> ModuleNotFoundError)

- [ ] **Step 3: Implement** `src/nar_tools/scoring.py`

```python
"""Single-pass option scoring: the next-token distribution over option letters."""
from __future__ import annotations

import math

from nar_tools.ollama import TokenLogprob

LETTERS = "ABCDEFGHIJKLMNOPQRST"   # at most 20 options: Ollama returns at most 20 alternatives
MAX_OPTIONS = len(LETTERS)
_STRIP = " \t\r\n*().:[]\"'`"

SYSTEM = "You pick the best option. Answer with exactly one capital letter."


def build_messages(question: str, options: list[str]) -> list[dict]:
    lines = [f"{LETTERS[i]}. {text}" for i, text in enumerate(options)]
    user = f"{question.strip()}\n\n" + "\n".join(lines) + "\n\nAnswer with the letter of the best option only."
    return [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]


def _logaddexp(a: float, b: float) -> float:
    m = max(a, b)
    return m + math.log(math.exp(a - m) + math.exp(b - m))


def letter_logprobs(top: list[TokenLogprob], n_options: int) -> tuple[list[float], bool]:
    """Log-probability of each option's letter as the first token, and whether any letter was seen.

    "A", " A", "**A" and "(A" all count for A (their probabilities add up); lowercase does not.
    A letter missing from the candidates gets a floor below the least likely candidate, so every
    option keeps a small, equal share instead of zero.
    """
    if not 2 <= n_options <= MAX_OPTIONS:
        raise ValueError(f"need 2 to {MAX_OPTIONS} options, got {n_options}")
    valid = LETTERS[:n_options]
    found: dict[int, float] = {}
    for t in top:
        key = t.token.strip(_STRIP)
        if len(key) == 1 and key in valid:
            i = valid.index(key)
            found[i] = _logaddexp(found[i], t.logprob) if i in found else t.logprob
    floor = min((t.logprob for t in top), default=0.0) - math.log(2.0)
    return [found.get(i, floor) for i in range(n_options)], bool(found)
```

- [ ] **Step 4: Run, see them pass** (8 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: letter scoring from one step's logprobs"`)

---

### Task 6: Calibration

**Files:**
- Create: `src/nar_tools/calibration.py`
- Test: `tests/test_calibration.py`

**Interfaces:**
- Produces: `@dataclass(frozen=True) Sample(logprobs: tuple[float, ...], outcome: int)`, `softmax(xs) -> list[float]`, `calibrate(logprobs, temperature: float) -> list[float]`, `nll(samples, temperature) -> float`, `fit_temperature(samples, lo=0.05, hi=20.0, iterations=100) -> float`, `brier(samples, temperature) -> float`, `ece(samples, temperature, bins=10) -> float`.

- [ ] **Step 1: Write the failing tests** `tests/test_calibration.py`

```python
import math

import pytest

from nar_tools.calibration import Sample, brier, calibrate, ece, fit_temperature, nll


def overconfident_samples():
    # The scorer always says 95% for A (log-odds 3), but A is right only 73 times out of 100.
    raw = (0.0, -3.0)
    return [Sample(raw, 0)] * 73 + [Sample(raw, 1)] * 27


def test_temperature_one_is_the_raw_distribution():
    p = calibrate([math.log(0.8), math.log(0.2)], 1.0)
    assert math.isclose(p[0], 0.8) and math.isclose(p[1], 0.2)


def test_high_temperature_flattens_and_low_sharpens():
    assert calibrate([0.0, -3.0], 100.0)[0] < 0.51
    assert calibrate([0.0, -3.0], 0.1)[0] > 0.999


def test_fit_recovers_the_right_temperature():
    # 1 / (1 + e^(-3/T)) = 0.73  ->  T = 3 / ln(0.73 / 0.27), about 3.016
    assert math.isclose(fit_temperature(overconfident_samples()), 3 / math.log(0.73 / 0.27), rel_tol=1e-3)


def test_fitted_temperature_lowers_nll_brier_and_ece():
    s = overconfident_samples()
    t = fit_temperature(s)
    assert nll(s, t) < nll(s, 1.0) and brier(s, t) < brier(s, 1.0) and ece(s, t) < ece(s, 1.0)


def test_metric_values_on_one_sample():
    s = [Sample((math.log(0.8), math.log(0.2)), 0)]
    assert math.isclose(brier(s, 1.0), 0.08)
    assert math.isclose(ece(s, 1.0), 0.2)


def test_bad_inputs():
    with pytest.raises(ValueError):
        calibrate([0.0, -1.0], 0.0)
    with pytest.raises(ValueError):
        fit_temperature([])
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/calibration.py`

```python
"""Temperature scaling and calibration metrics for single-pass option scores."""
from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Sample:
    logprobs: tuple[float, ...]   # raw per-option log-probabilities from one forward pass
    outcome: int                  # index of the option that turned out right


def softmax(xs) -> list[float]:
    m = max(xs)
    es = [math.exp(x - m) for x in xs]
    s = sum(es)
    return [e / s for e in es]


def calibrate(logprobs, temperature: float) -> list[float]:
    if temperature <= 0:
        raise ValueError("temperature must be positive")
    return softmax([lp / temperature for lp in logprobs])


def nll(samples, temperature: float) -> float:
    return -sum(math.log(max(calibrate(s.logprobs, temperature)[s.outcome], 1e-12)) for s in samples) / len(samples)


def fit_temperature(samples, lo: float = 0.05, hi: float = 20.0, iterations: int = 100) -> float:
    """The temperature with the lowest negative log-likelihood.

    NLL is convex in the inverse temperature, so a golden-section search over it finds the minimum.
    """
    if not samples:
        raise ValueError("no samples to fit")
    g = (math.sqrt(5) - 1) / 2
    a, b = 1.0 / hi, 1.0 / lo
    c, d = b - g * (b - a), a + g * (b - a)
    fc, fd = nll(samples, 1.0 / c), nll(samples, 1.0 / d)
    for _ in range(iterations):
        if fc < fd:
            b, d, fd = d, c, fc
            c = b - g * (b - a)
            fc = nll(samples, 1.0 / c)
        else:
            a, c, fc = c, d, fd
            d = a + g * (b - a)
            fd = nll(samples, 1.0 / d)
    return 1.0 / ((a + b) / 2)


def brier(samples, temperature: float) -> float:
    total = 0.0
    for s in samples:
        p = calibrate(s.logprobs, temperature)
        total += sum((pi - (1.0 if i == s.outcome else 0.0)) ** 2 for i, pi in enumerate(p))
    return total / len(samples)


def ece(samples, temperature: float, bins: int = 10) -> float:
    """Expected calibration error: how far stated confidence is from observed accuracy, by bin."""
    count = [0] * bins
    conf_sum = [0.0] * bins
    correct_sum = [0.0] * bins
    for s in samples:
        p = calibrate(s.logprobs, temperature)
        conf = max(p)
        k = min(int(conf * bins), bins - 1)
        count[k] += 1
        conf_sum[k] += conf
        correct_sum[k] += 1.0 if p.index(conf) == s.outcome else 0.0
    return sum(abs(correct_sum[k] - conf_sum[k]) for k in range(bins) if count[k]) / len(samples)
```

- [ ] **Step 4: Run, see them pass** (6 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: temperature scaling, Brier and ECE"`)

---

### Task 7: Storage and the refit lock

**Files:**
- Create: `src/nar_tools/store.py`
- Test: `tests/test_store.py`

**Interfaces:**
- Produces: `nar_home() -> Path`, `check_task_type(task_type: str) -> str` (ValueError unless `^[a-z0-9][a-z0-9_-]{0,39}$`), `IDENTITY = {"version": 0, "temperature": 1.0}`, `class NarStore(root: Path | None = None)` with `log_call(record)`, `log_feedback(record)`, `log_promotion(record)`, `calls()`, `feedback()`, `promotions()`, `find_call(call_id) -> dict | None`, `labelled(task_type) -> list[tuple[str, list[float], int]]`, `feedback_count(task_type) -> int`, `current(task_type) -> dict`, `promote(task_type, calibrator: dict) -> dict`, `lock(timeout=10.0, stale_after=120.0)` (context manager, `TimeoutError` on timeout).

- [ ] **Step 1: Write the failing tests** `tests/test_store.py`

```python
import json
import os
import time

import pytest

from nar_tools.store import NarStore, check_task_type


def test_append_and_read_round_trip(tmp_path):
    s = NarStore(tmp_path)
    s.log_call({"call_id": "c1", "task_type": "general", "raw_logprobs": [-0.1, -2.0], "options": ["x", "y"]})
    s.log_feedback({"call_id": "c1", "outcome": 1})
    assert s.find_call("c1")["options"] == ["x", "y"]
    assert s.labelled("general") == [("c1", [-0.1, -2.0], 1)]


def test_latest_feedback_wins_and_other_types_are_excluded(tmp_path):
    s = NarStore(tmp_path)
    s.log_call({"call_id": "c1", "task_type": "general", "raw_logprobs": [0.0, -1.0], "options": ["x", "y"]})
    s.log_call({"call_id": "c2", "task_type": "triage", "raw_logprobs": [0.0, -1.0], "options": ["x", "y"]})
    s.log_feedback({"call_id": "c1", "outcome": 0})
    s.log_feedback({"call_id": "c1", "outcome": 1})
    s.log_feedback({"call_id": "c2", "outcome": 0})
    assert s.labelled("general") == [("c1", [0.0, -1.0], 1)]
    assert s.feedback_count("general") == 2 and s.feedback_count("triage") == 1


def test_a_torn_line_is_skipped(tmp_path):
    s = NarStore(tmp_path)
    s.log_call({"call_id": "c1", "task_type": "general"})
    with open(tmp_path / "calls.jsonl", "ab") as f:
        f.write(b'{"call_id": "c2", "task_')
    assert [c["call_id"] for c in s.calls()] == ["c1"]


def test_current_starts_at_identity_and_promote_bumps_versions(tmp_path):
    s = NarStore(tmp_path)
    assert s.current("general") == {"version": 0, "temperature": 1.0}
    s.promote("general", {"temperature": 2.0})
    s.promote("general", {"temperature": 3.0})
    assert s.current("general")["version"] == 2 and s.current("general")["temperature"] == 3.0
    assert json.loads((tmp_path / "current.json").read_text(encoding="utf-8"))["general"] == 2
    assert (tmp_path / "calibrators" / "general" / "v1.json").exists()


def test_lock_excludes_a_second_holder(tmp_path):
    s = NarStore(tmp_path)
    with s.lock():
        with pytest.raises(TimeoutError):
            with s.lock(timeout=0.1):
                pass
    with s.lock(timeout=0.1):
        pass


def test_a_stale_lock_is_taken_over(tmp_path):
    s = NarStore(tmp_path)
    lock = tmp_path / "refit.lock"
    lock.write_text("12345")
    old = time.time() - 600
    os.utime(lock, (old, old))
    with s.lock(timeout=0.5, stale_after=60):
        assert lock.exists()
    assert not lock.exists()


@pytest.mark.parametrize("bad", ["", "General", "../x", "a b", "x" * 41])
def test_task_type_is_a_safe_name(bad):
    with pytest.raises(ValueError):
        check_task_type(bad)
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/store.py`

```python
"""Local, append-only storage for nar calls, feedback, calibrators and promotion decisions."""
from __future__ import annotations

import json
import os
import re
import time
from contextlib import contextmanager
from pathlib import Path

TASK_TYPE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,39}$")
IDENTITY = {"version": 0, "temperature": 1.0}   # before any promotion: the raw model probabilities


def nar_home() -> Path:
    return Path(os.environ.get("NAR_HOME") or (Path.home() / ".aos" / "nar"))


def check_task_type(task_type: str) -> str:
    if not isinstance(task_type, str) or not TASK_TYPE.match(task_type):
        raise ValueError("task_type must be 1-40 characters: lowercase letters, digits, '-' or '_'")
    return task_type


def _load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


class NarStore:
    def __init__(self, root: Path | None = None) -> None:
        self.root = Path(root) if root else nar_home()
        self.root.mkdir(parents=True, exist_ok=True)

    def _append(self, name: str, record: dict) -> None:
        line = (json.dumps(record, ensure_ascii=False) + "\n").encode("utf-8")
        with open(self.root / name, "ab") as f:   # one write per record keeps lines whole
            f.write(line)

    def _read(self, name: str) -> list[dict]:
        path = self.root / name
        if not path.exists():
            return []
        out = []
        for raw in path.read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            try:
                out.append(json.loads(raw))
            except ValueError:
                continue   # a torn line never breaks the store
        return out

    def log_call(self, record: dict) -> None:
        self._append("calls.jsonl", record)

    def log_feedback(self, record: dict) -> None:
        self._append("feedback.jsonl", record)

    def log_promotion(self, record: dict) -> None:
        self._append("promotions.jsonl", record)

    def calls(self) -> list[dict]:
        return self._read("calls.jsonl")

    def feedback(self) -> list[dict]:
        return self._read("feedback.jsonl")

    def promotions(self) -> list[dict]:
        return self._read("promotions.jsonl")

    def find_call(self, call_id: str) -> dict | None:
        return next((c for c in self.calls() if c.get("call_id") == call_id), None)

    def labelled(self, task_type: str) -> list[tuple[str, list[float], int]]:
        """(call_id, raw log-probabilities, outcome) for calls of this type with feedback; latest wins."""
        outcome = {f["call_id"]: f["outcome"] for f in self.feedback()}
        return [(c["call_id"], c["raw_logprobs"], outcome[c["call_id"]])
                for c in self.calls() if c.get("task_type") == task_type and c.get("call_id") in outcome]

    def feedback_count(self, task_type: str) -> int:
        ids = {c["call_id"] for c in self.calls() if c.get("task_type") == task_type}
        return sum(1 for f in self.feedback() if f.get("call_id") in ids)

    def current(self, task_type: str) -> dict:
        check_task_type(task_type)
        version = _load_json(self.root / "current.json", {}).get(task_type)
        if not version:
            return dict(IDENTITY)
        return _load_json(self.root / "calibrators" / task_type / f"v{version}.json", dict(IDENTITY))

    def promote(self, task_type: str, calibrator: dict) -> dict:
        """Write the next version and point current.json at it (atomic replace)."""
        check_task_type(task_type)
        folder = self.root / "calibrators" / task_type
        folder.mkdir(parents=True, exist_ok=True)
        record = {**calibrator, "version": self.current(task_type)["version"] + 1}
        (folder / f"v{record['version']}.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
        pointer = _load_json(self.root / "current.json", {})
        pointer[task_type] = record["version"]
        tmp = self.root / f"current.json.{os.getpid()}.tmp"
        tmp.write_text(json.dumps(pointer, indent=2), encoding="utf-8")
        os.replace(tmp, self.root / "current.json")
        return record

    @contextmanager
    def lock(self, timeout: float = 10.0, stale_after: float = 120.0):
        """Cross-process lock for refits: Claude, Codex and OpenCode each run their own nar-mcp."""
        path = self.root / "refit.lock"
        deadline = time.monotonic() + timeout
        while True:
            try:
                fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                break
            except FileExistsError:
                try:
                    if time.time() - path.stat().st_mtime > stale_after:
                        path.unlink(missing_ok=True)   # a crashed holder
                        continue
                except FileNotFoundError:
                    continue
                if time.monotonic() > deadline:
                    raise TimeoutError("another nar process is refitting; try again")
                time.sleep(0.05)
        try:
            os.write(fd, str(os.getpid()).encode("ascii"))
            os.close(fd)
            yield
        finally:
            path.unlink(missing_ok=True)
```

- [ ] **Step 4: Run, see them pass** (11 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: append-only store, calibrator versions, refit lock"`)

---

### Task 8: The promotion gate

**Files:**
- Create: `src/nar_tools/gate.py`
- Test: `tests/test_gate.py`

**Interfaces:**
- Consumes: `Sample`, `fit_temperature`, `brier`, `ece` (Task 6); `NarStore` (Task 7).
- Produces: `MIN_TRAIN = 20`, `MIN_HELDOUT = 5`, `REFIT_EVERY = 20`, `is_heldout(call_id: str) -> bool`, `@dataclass Decision(task_type, promoted, reason, candidate_temperature=None, candidate_brier=None, candidate_ece=None, current_version=0, current_brier=None, current_ece=None, n_train=0, n_heldout=0)`, `refit(store: NarStore, task_type: str) -> Decision`.

- [ ] **Step 1: Write the failing tests** `tests/test_gate.py`

```python
import math
import uuid

import pytest

from nar_tools import gate
from nar_tools.store import NarStore


def ids(n, heldout):
    out = []
    while len(out) < n:
        cid = uuid.uuid4().hex
        if gate.is_heldout(cid) == heldout:
            out.append(cid)
    return out


def add(store, call_ids, raw, outcomes, task_type="general"):
    for cid, o in zip(call_ids, outcomes):
        store.log_call({"call_id": cid, "task_type": task_type, "raw_logprobs": list(raw), "options": ["a", "b"]})
        store.log_feedback({"call_id": cid, "outcome": o})


def test_split_is_stable_and_about_one_in_five():
    sample = [uuid.uuid4().hex for _ in range(2000)]
    assert 0.15 < sum(gate.is_heldout(c) for c in sample) / len(sample) < 0.25
    assert [gate.is_heldout(c) for c in sample[:50]] == [gate.is_heldout(c) for c in sample[:50]]


def test_too_few_labels_changes_nothing(tmp_path):
    s = NarStore(tmp_path)
    add(s, ids(5, False), (0.0, -3.0), [0] * 5)
    d = gate.refit(s, "general")
    assert d.promoted is False and "not enough" in d.reason
    assert s.current("general")["version"] == 0 and len(s.promotions()) == 1


def test_a_better_calibrator_is_promoted(tmp_path):
    s = NarStore(tmp_path)
    raw = (0.0, -3.0)                       # says 95% A; A is right about 73% of the time everywhere
    add(s, ids(100, False), raw, [0] * 73 + [1] * 27)
    add(s, ids(30, True), raw, [0] * 22 + [1] * 8)
    d = gate.refit(s, "general")
    assert d.promoted is True and s.current("general")["version"] == 1
    assert math.isclose(s.current("general")["temperature"], d.candidate_temperature)


def test_a_worse_calibrator_is_never_promoted(tmp_path):
    s = NarStore(tmp_path)
    raw = (0.0, -3.0)
    add(s, ids(100, False), raw, [0] * 50 + [1] * 50)   # training says: flatten to 50/50
    add(s, ids(30, True), raw, [0] * 30)                # held-out says: the raw 95% was right
    d = gate.refit(s, "general")
    assert d.promoted is False and "worse" in d.reason
    assert s.current("general")["version"] == 0 and s.promotions()[-1]["promoted"] is False


def test_refit_holds_the_lock(tmp_path, monkeypatch):
    s = NarStore(tmp_path)
    monkeypatch.setattr(gate, "LOCK_TIMEOUT", 0.1)
    with s.lock():
        with pytest.raises(TimeoutError):
            gate.refit(s, "general")
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/gate.py`

```python
"""The non-regressive rule: a refitted calibrator replaces the current one only if it is no worse."""
from __future__ import annotations

import hashlib
import time
from dataclasses import asdict, dataclass

from nar_tools.calibration import Sample, brier, ece, fit_temperature
from nar_tools.store import NarStore

MIN_TRAIN = 20
MIN_HELDOUT = 5
REFIT_EVERY = 20
LOCK_TIMEOUT = 10.0


def is_heldout(call_id: str) -> bool:
    """A stable 1-in-5 split: the same call is always on the same side."""
    return int(hashlib.sha256(call_id.encode("utf-8")).hexdigest(), 16) % 5 == 0


@dataclass
class Decision:
    task_type: str
    promoted: bool
    reason: str
    candidate_temperature: float | None = None
    candidate_brier: float | None = None
    candidate_ece: float | None = None
    current_version: int = 0
    current_brier: float | None = None
    current_ece: float | None = None
    n_train: int = 0
    n_heldout: int = 0


def refit(store: NarStore, task_type: str) -> Decision:
    with store.lock(timeout=LOCK_TIMEOUT):
        rows = store.labelled(task_type)
        train = [Sample(tuple(lp), o) for cid, lp, o in rows if not is_heldout(cid)]
        held = [Sample(tuple(lp), o) for cid, lp, o in rows if is_heldout(cid)]
        current = store.current(task_type)
        d = Decision(task_type, False, "", current_version=current["version"], n_train=len(train), n_heldout=len(held))
        if len(train) < MIN_TRAIN or len(held) < MIN_HELDOUT:
            d.reason = f"not enough labelled calls (train {len(train)}/{MIN_TRAIN}, held-out {len(held)}/{MIN_HELDOUT})"
        else:
            t = fit_temperature(train)
            d.candidate_temperature = t
            d.candidate_brier, d.candidate_ece = brier(held, t), ece(held, t)
            d.current_brier, d.current_ece = brier(held, current["temperature"]), ece(held, current["temperature"])
            if abs(t - current["temperature"]) < 1e-6:
                d.reason = "unchanged"
            elif d.candidate_brier <= d.current_brier and d.candidate_ece <= d.current_ece:
                store.promote(task_type, {"temperature": t, "brier": d.candidate_brier, "ece": d.candidate_ece,
                                          "n_train": len(train), "n_heldout": len(held), "fitted_at": time.time()})
                d.promoted, d.reason = True, "no worse on held-out calls"
            else:
                d.reason = "worse on held-out calls; kept the current calibrator"
        store.log_promotion({"at": time.time(), **asdict(d)})
        return d
```

- [ ] **Step 4: Run, see them pass** (5 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: the non-regressive promotion gate"`)

---

### Task 9: The service layer

**Files:**
- Create: `src/nar_tools/service.py`
- Test: `tests/test_service.py`

**Interfaces:**
- Consumes: `OllamaClient`, `local_state` (Task 4); `build_messages`, `letter_logprobs`, `MAX_OPTIONS` (Task 5); `calibrate` (Task 6); `NarStore`, `check_task_type` (Task 7); `gate.refit`, `gate.REFIT_EVERY` (Task 8).
- Produces: `MAX_ITEMS = 50`; `class NarService(client, store, model=None)` with `choose(question, options, task_type="general") -> dict` (keys `call_id, choice, choice_index, confidence, options[{option, probability}], letter_signal, calibrator_version, model`), `classify(items, labels, task_type="general") -> {"results": [...]}`, `feedback(call_id, outcome) -> {"recorded", "call_id", "outcome", "refit"}`, `status() -> dict`. Every input error is a `ValueError`.

- [ ] **Step 1: Write the failing tests** `tests/test_service.py`

```python
import math

import pytest

from nar_tools import gate
from nar_tools.ollama import TokenLogprob
from nar_tools.service import NarService
from nar_tools.store import NarStore


class FakeClient:
    def __init__(self):
        self.top = [TokenLogprob("B", math.log(0.6)), TokenLogprob("A", math.log(0.3)), TokenLogprob("C", math.log(0.1))]
        self.calls = 0

    def next_token_logprobs(self, model, messages, top=20):
        self.calls += 1
        return self.top


def make(tmp_path):
    return NarService(FakeClient(), NarStore(tmp_path), model="test-model")


def test_choose_returns_calibrated_probabilities_and_logs_the_call(tmp_path):
    svc = make(tmp_path)
    r = svc.choose("Which?", ["x", "y", "z"])
    assert r["choice"] == "y" and r["choice_index"] == 1
    assert math.isclose(sum(o["probability"] for o in r["options"]), 1.0, abs_tol=1e-3)
    assert r["calibrator_version"] == 0 and r["letter_signal"] is True
    logged = svc.store.find_call(r["call_id"])
    assert logged["options"] == ["x", "y", "z"] and logged["model"] == "test-model"


@pytest.mark.parametrize("options", [["only"], ["a", "a"], ["a", " "], [str(i) for i in range(21)], "ab"])
def test_bad_options_are_rejected_and_nothing_is_logged(tmp_path, options):
    svc = make(tmp_path)
    with pytest.raises(ValueError):
        svc.choose("Which?", options)
    assert svc.store.calls() == [] and svc.client.calls == 0


def test_bad_task_type_or_question_is_rejected(tmp_path):
    svc = make(tmp_path)
    with pytest.raises(ValueError):
        svc.choose("Which?", ["a", "b"], task_type="../x")
    with pytest.raises(ValueError):
        svc.choose("   ", ["a", "b"])
    assert svc.store.calls() == []


def test_no_model_configured(tmp_path, monkeypatch):
    monkeypatch.setattr("nar_tools.service.local_state", lambda: {})
    svc = NarService(FakeClient(), NarStore(tmp_path))
    with pytest.raises(ValueError, match="aos install local"):
        svc.choose("Which?", ["a", "b"])


def test_feedback_by_index_or_text(tmp_path):
    svc = make(tmp_path)
    c1 = svc.choose("Which?", ["x", "y"])["call_id"]
    c2 = svc.choose("Which?", ["x", "y"])["call_id"]
    assert svc.feedback(c1, 0)["outcome"] == 0
    assert svc.feedback(c2, "y")["outcome"] == 1
    assert svc.feedback(c2, "1")["outcome"] == 1


@pytest.mark.parametrize("outcome", [5, -1, "nope", True])
def test_bad_feedback_is_rejected_and_not_recorded(tmp_path, outcome):
    svc = make(tmp_path)
    cid = svc.choose("Which?", ["x", "y"])["call_id"]
    with pytest.raises(ValueError):
        svc.feedback(cid, outcome)
    assert svc.store.feedback() == []


def test_unknown_call_id(tmp_path):
    with pytest.raises(ValueError, match="unknown call_id"):
        make(tmp_path).feedback("missing", 0)


def test_every_twentieth_outcome_triggers_a_refit(tmp_path, monkeypatch):
    seen = []
    monkeypatch.setattr(gate, "refit", lambda store, t: seen.append(t) or gate.Decision(t, False, "stub"))
    svc = make(tmp_path)
    for i in range(40):
        cid = svc.choose("Which?", ["x", "y"])["call_id"]
        r = svc.feedback(cid, 0)
        assert (r["refit"] is not None) == ((i + 1) % 20 == 0)
    assert seen == ["general", "general"]


def test_classify_scores_each_item(tmp_path):
    svc = make(tmp_path)
    out = svc.classify(["i1", "i2"], ["bug", "feature", "question"])
    assert len(out["results"]) == 2 and svc.client.calls == 2
    with pytest.raises(ValueError):
        svc.classify([], ["a", "b"])
    with pytest.raises(ValueError):
        svc.classify(["x"] * 51, ["a", "b"])


def test_status_counts_calls_and_labels(tmp_path):
    svc = make(tmp_path)
    cid = svc.choose("Which?", ["x", "y"])["call_id"]
    svc.choose("Which?", ["x", "y"], task_type="triage")
    svc.feedback(cid, 1)
    st = svc.status()
    assert st["task_types"]["general"] == {"calls": 1, "labelled": 1, "calibrator": {"version": 0, "temperature": 1.0}}
    assert st["task_types"]["triage"]["labelled"] == 0 and st["model"] == "test-model"
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/service.py`

```python
"""What the nar tools do: score in one pass, log, take feedback, refit."""
from __future__ import annotations

import time
import uuid
from dataclasses import asdict

from nar_tools import gate
from nar_tools.calibration import calibrate
from nar_tools.ollama import OllamaClient, local_state
from nar_tools.scoring import MAX_OPTIONS, build_messages, letter_logprobs
from nar_tools.store import NarStore, check_task_type

MAX_ITEMS = 50


def _check_options(options) -> list[str]:
    if not isinstance(options, list) or not 2 <= len(options) <= MAX_OPTIONS:
        raise ValueError(f"give a list of 2 to {MAX_OPTIONS} options")
    cleaned = [str(o).strip() for o in options]
    if any(not o for o in cleaned):
        raise ValueError("options must not be empty")
    if len(set(cleaned)) != len(cleaned):
        raise ValueError("options must be distinct")
    return cleaned


class NarService:
    def __init__(self, client: OllamaClient, store: NarStore, model: str | None = None) -> None:
        self.client = client
        self.store = store
        self.model = model or local_state().get("default")

    def choose(self, question: str, options, task_type: str = "general") -> dict:
        check_task_type(task_type)
        opts = _check_options(options)
        if not str(question).strip():
            raise ValueError("question must not be empty")
        if not self.model:
            raise ValueError("no local model configured (run: aos install local)")
        top = self.client.next_token_logprobs(self.model, build_messages(str(question), opts))
        raw, signal = letter_logprobs(top, len(opts))
        cal = self.store.current(task_type)
        probs = calibrate(raw, cal["temperature"])
        best = max(range(len(opts)), key=probs.__getitem__)
        call_id = uuid.uuid4().hex
        self.store.log_call({"call_id": call_id, "at": time.time(), "task_type": task_type, "model": self.model,
                             "question": str(question), "options": opts, "raw_logprobs": raw,
                             "letter_signal": signal, "calibrator_version": cal["version"]})
        return {"call_id": call_id, "choice": opts[best], "choice_index": best,
                "confidence": round(probs[best], 4),
                "options": [{"option": o, "probability": round(p, 4)} for o, p in zip(opts, probs)],
                "letter_signal": signal, "calibrator_version": cal["version"], "model": self.model}

    def classify(self, items, labels, task_type: str = "general") -> dict:
        if not isinstance(items, list) or not 1 <= len(items) <= MAX_ITEMS:
            raise ValueError(f"give a list of 1 to {MAX_ITEMS} items")
        labels = _check_options(labels)
        check_task_type(task_type)
        return {"results": [self.choose(f"Which label fits this item best?\n\nItem: {item}", labels, task_type)
                            for item in items]}

    def feedback(self, call_id: str, outcome) -> dict:
        call = self.store.find_call(str(call_id))
        if call is None:
            raise ValueError(f"unknown call_id {call_id}")
        opts = call["options"]
        if isinstance(outcome, bool):
            raise ValueError("outcome must be the right option's index or its exact text")
        if isinstance(outcome, int):
            index = outcome
        elif isinstance(outcome, str) and outcome.strip() in opts:
            index = opts.index(outcome.strip())
        elif isinstance(outcome, str) and outcome.strip().isdigit():
            index = int(outcome.strip())
        else:
            raise ValueError("outcome must be the right option's index or its exact text")
        if not 0 <= index < len(opts):
            raise ValueError(f"outcome index must be 0 to {len(opts) - 1}")
        self.store.log_feedback({"call_id": call["call_id"], "at": time.time(), "outcome": index})
        result = {"recorded": True, "call_id": call["call_id"], "outcome": index, "refit": None}
        if self.store.feedback_count(call["task_type"]) % gate.REFIT_EVERY == 0:
            result["refit"] = asdict(gate.refit(self.store, call["task_type"]))
        return result

    def status(self) -> dict:
        calls = self.store.calls()
        labelled_ids = {f.get("call_id") for f in self.store.feedback()}
        per_type = {}
        for t in sorted({c.get("task_type", "general") for c in calls}):
            of_type = [c for c in calls if c.get("task_type") == t]
            per_type[t] = {"calls": len(of_type),
                           "labelled": sum(1 for c in of_type if c.get("call_id") in labelled_ids),
                           "calibrator": self.store.current(t)}
        decisions = self.store.promotions()
        return {"model": self.model, "store": str(self.store.root), "task_types": per_type,
                "last_decision": decisions[-1] if decisions else None}
```

- [ ] **Step 4: Run, see them pass** (19 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: service layer (choose, classify, feedback, status)"`)

---

### Task 10: The MCP server

**Files:**
- Create: `src/nar_tools/server.py`
- Test: `tests/test_server.py`

**Interfaces:**
- Consumes: `NarService` (Task 9), `OllamaClient`, `OllamaUnavailable` (Task 4), `NarStore` (Task 7).
- Produces: FastMCP app `mcp` named `nar` with tools `nar_choose`, `nar_classify`, `nar_feedback`, `nar_status`; `get_service()`; `main()` (stdio). Results: the service's dict, or `{"unavailable": True, "reason"}` / `{"error"}`.

- [ ] **Step 1: Write the failing tests** `tests/test_server.py`

```python
import asyncio

from nar_tools import server
from nar_tools.ollama import OllamaUnavailable


class Down:
    def choose(self, *args):
        raise OllamaUnavailable("cannot reach Ollama at http://127.0.0.1:11434 (ConnectError)")

    def classify(self, *args):
        raise ValueError("give a list of 1 to 50 items")


def test_the_four_tools_are_registered_with_guidance():
    tools = {t.name: t for t in asyncio.run(server.mcp.list_tools())}
    assert set(tools) == {"nar_choose", "nar_classify", "nar_feedback", "nar_status"}
    assert "one forward pass" in tools["nar_choose"].description.lower()


def test_unavailable_ollama_becomes_a_result_not_an_exception(monkeypatch):
    monkeypatch.setattr(server, "get_service", lambda: Down())
    assert server.nar_choose("q", ["a", "b"])["unavailable"] is True


def test_bad_input_becomes_an_error_result(monkeypatch):
    monkeypatch.setattr(server, "get_service", lambda: Down())
    assert "error" in server.nar_classify([], ["a", "b"])
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/server.py`

```python
"""The `nar` MCP server (stdio): calibrated single-pass option scoring with the local model."""
from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from nar_tools.ollama import OllamaClient, OllamaUnavailable
from nar_tools.service import NarService
from nar_tools.store import NarStore

mcp = FastMCP("nar")
_service: NarService | None = None


def get_service() -> NarService:
    global _service
    if _service is None:
        _service = NarService(OllamaClient(), NarStore())
    return _service


def _safe(call):
    try:
        return call()
    except OllamaUnavailable as e:
        return {"unavailable": True, "reason": str(e)}
    except (ValueError, TimeoutError) as e:
        return {"error": str(e)}


@mcp.tool()
def nar_choose(question: str, options: list[str], task_type: str = "general") -> dict:
    """Score 2-20 candidate options in one forward pass of the local model (no text generation) and
    return calibrated probabilities. Use it when a decision among known alternatives benefits from a
    fast, private second signal: picking between plans, fixes or answers; triage; or deciding whether to
    escalate to a stronger model when confidence is low. Keep options short and distinct. When you
    later learn which option was right, report it with nar_feedback(call_id, outcome).
    task_type groups calls that share a calibrator (lowercase, e.g. "code-review", "triage")."""
    return _safe(lambda: get_service().choose(question, options, task_type))


@mcp.tool()
def nar_classify(items: list[str], labels: list[str], task_type: str = "general") -> dict:
    """Label 1-50 items with one of 2-20 labels; each item is scored in one forward pass with calibrated
    probabilities. Use for bulk triage (issues, messages, test failures) where a fast local model is enough."""
    return _safe(lambda: get_service().classify(items, labels, task_type))


@mcp.tool()
def nar_feedback(call_id: str, outcome: str) -> dict:
    """Record which option was actually right for an earlier nar_choose or nar_classify result: the
    option's exact text or its 0-based index. Every 20 outcomes per task type, nar refits its calibration
    and keeps the new one only if it is no worse on held-out calls."""
    return _safe(lambda: get_service().feedback(call_id, outcome))


@mcp.tool()
def nar_status() -> dict:
    """The local model in use, calls and outcomes per task type, current calibrators, last refit decision."""
    return _safe(lambda: get_service().status())


def main() -> None:
    mcp.run()   # stdio
```

- [ ] **Step 4: Run, see them pass** (3 passed; full suite green)

- [ ] **Step 5: Commit** (`git commit -m "nar: FastMCP stdio server with four tools"`)

---

### Task 11: The bake-off and the `nar` CLI

**Files:**
- Create: `src/nar_tools/evals/choose.jsonl`, `src/nar_tools/evals/tools.jsonl`, `src/nar_tools/evals/toolset.json`, `src/nar_tools/evaluate.py`, `src/nar_tools/cli.py`
- Test: `tests/test_evaluate.py`, `tests/test_cli.py`

**Interfaces:**
- Consumes: Tasks 4-9.
- Produces: `load_jsonl(name) -> list[dict]`, `load_toolset() -> list[dict]`, `@dataclass ModelResult(model, tool_success=0.0, choose_accuracy=0.0, choose_ece=1.0, tokens_per_s=0.0, fully_on_gpu=False, errors=[])`, `evaluate(client, model) -> ModelResult`, `verdict(candidate, baseline, min_tps=15.0) -> {"passes", "reasons"}`, `run(models, client=None, baseline_model=None, out_dir=None) -> dict` (writes `<NAR_HOME>/eval/<stamp>.json` and `latest.json` with keys `created_at, machine, baseline, models, verdicts`); `cli.main(argv=None) -> int` with `eval --models a,b [--baseline t]`, `fit [--task-type t]`, `status`, `choose QUESTION -o A -o B [--task-type t]`.

- [ ] **Step 1: Add the eval data**

`src/nar_tools/evals/choose.jsonl` (30 items; answers spread A 8 / B 7 / C 7 / D 8):

```jsonl
{"question": "Which planet is closest to the Sun?", "options": ["Mercury", "Venus", "Mars", "Earth"], "answer": 0}
{"question": "What is 17 * 3?", "options": ["41", "47", "54", "51"], "answer": 3}
{"question": "Which data structure gives O(1) average-time lookup by key?", "options": ["Linked list", "Binary heap", "Hash table", "Stack"], "answer": 2}
{"question": "In Python, what does len('hello') return?", "options": ["4", "5", "6", "It raises an error"], "answer": 1}
{"question": "Which HTTP status code means Not Found?", "options": ["200", "301", "500", "404"], "answer": 3}
{"question": "A test fails only on Windows because a path is built by joining strings with '/'. What is the best fix?", "options": ["Use the platform's path-joining function", "Skip the test on Windows", "Retry the test three times", "Increase the test timeout"], "answer": 0}
{"question": "Which git command shows the commits of the current branch?", "options": ["git stash", "git clean", "git log", "git fetch"], "answer": 2}
{"question": "What is the boiling point of water at sea level, in degrees Celsius?", "options": ["90", "110", "120", "100"], "answer": 3}
{"question": "All cats are mammals and Tom is a cat. Which statement must be true?", "options": ["All mammals are cats", "Tom is a mammal", "Tom is not a mammal", "Some cats are not mammals"], "answer": 1}
{"question": "Which SQL clause filters rows before grouping?", "options": ["WHERE", "HAVING", "ORDER BY", "LIMIT"], "answer": 0}
{"question": "What is the next number in the sequence 2, 4, 8, 16?", "options": ["18", "24", "32", "20"], "answer": 2}
{"question": "A deploy must not break users if the new version fails. Which strategy fits best?", "options": ["Deploy to all servers at once", "Deploy on Friday evening", "Disable monitoring during the deploy", "Canary release with automatic rollback"], "answer": 3}
{"question": "Which of these is a compiled, statically typed language?", "options": ["Rust", "Python", "JavaScript", "Bash"], "answer": 0}
{"question": "What does JSON stand for?", "options": ["Java Standard Object Notation", "JavaScript Object Notation", "Joint Syntax Object Notation", "JSON Serialized Object Network"], "answer": 1}
{"question": "Which of these numbers is prime?", "options": ["21", "27", "33", "29"], "answer": 3}
{"question": "A function opens a file whose name comes from the user. What is the main security risk?", "options": ["Integer overflow", "Path traversal", "Stack alignment", "Slow startup"], "answer": 1}
{"question": "What is the capital of Italy?", "options": ["Milan", "Naples", "Rome", "Turin"], "answer": 2}
{"question": "Which command installs a Python package with pip?", "options": ["pip install requests", "pip get requests", "pip add requests", "pip fetch requests"], "answer": 0}
{"question": "What is 15% of 200?", "options": ["15", "20", "35", "30"], "answer": 3}
{"question": "Two answers to a task disagree and being wrong would be expensive. What should an agent do?", "options": ["Pick one at random", "Delete the tests", "Ask for an independent review or escalate", "Ignore the task"], "answer": 2}
{"question": "Which unit measures electrical resistance?", "options": ["Ohm", "Volt", "Ampere", "Watt"], "answer": 0}
{"question": "In a git merge conflict, what does a line of '<<<<<<<' mark?", "options": ["A deleted file", "The start of the conflicting change", "A commit hash", "A tag name"], "answer": 1}
{"question": "Which sorting algorithm has O(n log n) worst-case time?", "options": ["Bubble sort", "Insertion sort", "Selection sort", "Merge sort"], "answer": 3}
{"question": "How many minutes are in 2.5 hours?", "options": ["120", "140", "150", "160"], "answer": 2}
{"question": "Where is a secret stored most safely on a developer laptop?", "options": ["A plaintext .env file committed to git", "The operating system's credential store", "A comment in the source code", "A public gist"], "answer": 1}
{"question": "Which gas do plants take from the air for photosynthesis?", "options": ["Carbon dioxide", "Oxygen", "Nitrogen", "Helium"], "answer": 0}
{"question": "A CI job passes locally but fails in CI with 'command not found'. What is the most likely cause?", "options": ["The CPU is too fast", "The commit message is too long", "The tool is not installed or not on PATH in CI", "The repository is private"], "answer": 2}
{"question": "What is 2 to the power of 10?", "options": ["512", "1000", "2048", "1024"], "answer": 3}
{"question": "Which word is the opposite of 'increase'?", "options": ["Grow", "Decrease", "Expand", "Raise"], "answer": 1}
{"question": "Which file usually lists a Node.js project's dependencies?", "options": ["package.json", "requirements.txt", "Cargo.toml", "pom.xml"], "answer": 0}
```

`src/nar_tools/evals/toolset.json`:

```json
[
  {"type": "function", "function": {"name": "read_file", "description": "Read a text file from the project and return its contents.", "parameters": {"type": "object", "properties": {"path": {"type": "string", "description": "Path relative to the project root, e.g. src/app.py"}}, "required": ["path"]}}},
  {"type": "function", "function": {"name": "run_tests", "description": "Run the test suite or one test file.", "parameters": {"type": "object", "properties": {"target": {"type": "string", "description": "Test file or folder, e.g. tests/test_app.py"}}, "required": ["target"]}}},
  {"type": "function", "function": {"name": "search_web", "description": "Search the web and return the top results.", "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}}},
  {"type": "function", "function": {"name": "get_weather", "description": "Current weather for a city.", "parameters": {"type": "object", "properties": {"city": {"type": "string", "description": "City name, e.g. Rome"}}, "required": ["city"]}}},
  {"type": "function", "function": {"name": "convert_currency", "description": "Convert an amount between currencies.", "parameters": {"type": "object", "properties": {"amount": {"type": "number"}, "from_currency": {"type": "string", "description": "ISO 4217 code, e.g. EUR"}, "to_currency": {"type": "string", "description": "ISO 4217 code, e.g. USD"}}, "required": ["amount", "from_currency", "to_currency"]}}},
  {"type": "function", "function": {"name": "set_timer", "description": "Start a countdown timer.", "parameters": {"type": "object", "properties": {"minutes": {"type": "number"}}, "required": ["minutes"]}}}
]
```

`src/nar_tools/evals/tools.jsonl` (17 cases; `expect: null` means no tool call is right; free-text arguments are not checked):

```jsonl
{"prompt": "Open the file README.md and show me what is inside.", "expect": {"name": "read_file", "arguments": {"path": "README.md"}}}
{"prompt": "Run the unit tests in tests/test_store.py.", "expect": {"name": "run_tests", "arguments": {"target": "tests/test_store.py"}}}
{"prompt": "What is the weather like in Rome right now?", "expect": {"name": "get_weather", "arguments": {"city": "Rome"}}}
{"prompt": "Convert 250 euros to US dollars.", "expect": {"name": "convert_currency", "arguments": {"amount": 250, "from_currency": "EUR", "to_currency": "USD"}}}
{"prompt": "Set a timer for 15 minutes.", "expect": {"name": "set_timer", "arguments": {"minutes": 15}}}
{"prompt": "Search the web for the Ollama logprobs documentation.", "expect": {"name": "search_web", "arguments": {}}}
{"prompt": "Show me the contents of src/app.py.", "expect": {"name": "read_file", "arguments": {"path": "src/app.py"}}}
{"prompt": "Is it raining in Tokyo?", "expect": {"name": "get_weather", "arguments": {"city": "Tokyo"}}}
{"prompt": "How much is 100 US dollars in Japanese yen?", "expect": {"name": "convert_currency", "arguments": {"amount": 100, "from_currency": "USD", "to_currency": "JPY"}}}
{"prompt": "Run the tests for the tests/test_gate.py file.", "expect": {"name": "run_tests", "arguments": {"target": "tests/test_gate.py"}}}
{"prompt": "Start a 45 minute timer.", "expect": {"name": "set_timer", "arguments": {"minutes": 45}}}
{"prompt": "Look up online how to pair the Paseo app.", "expect": {"name": "search_web", "arguments": {}}}
{"prompt": "Read the file config/local.json.", "expect": {"name": "read_file", "arguments": {"path": "config/local.json"}}}
{"prompt": "What is the temperature in Milan today?", "expect": {"name": "get_weather", "arguments": {"city": "Milan"}}}
{"prompt": "Convert 80 British pounds to euros.", "expect": {"name": "convert_currency", "arguments": {"amount": 80, "from_currency": "GBP", "to_currency": "EUR"}}}
{"prompt": "Just say hello.", "expect": null}
{"prompt": "What is 2 + 2? Answer directly.", "expect": null}
```

- [ ] **Step 2: Write the failing tests** `tests/test_evaluate.py` and `tests/test_cli.py`

```python
import math

from nar_tools import evaluate
from nar_tools.evaluate import ModelResult, verdict
from nar_tools.ollama import TokenLogprob


class ScriptedClient:
    """Answers every eval task correctly, fast, fully on the GPU."""

    def __init__(self, on_gpu=True, tps=40.0):
        self.on_gpu, self.tps = on_gpu, tps
        self.unloaded = []

    def next_token_logprobs(self, model, messages, top=20):
        user = messages[-1]["content"]
        case = next(c for c in evaluate.load_jsonl("choose.jsonl") if c["question"] in user)
        letter = "ABCDEFGHIJKLMNOPQRST"[case["answer"]]
        other = "B" if letter == "A" else "A"
        return [TokenLogprob(letter, math.log(0.9)), TokenLogprob(other, math.log(0.1))]

    def chat(self, model, messages, tools=None, num_predict=None):
        if tools is None:
            return {"message": {"content": "..."}, "eval_count": int(self.tps * 2), "eval_duration": 2_000_000_000}
        case = next(c for c in evaluate.load_jsonl("tools.jsonl") if c["prompt"] == messages[-1]["content"])
        if case["expect"] is None:
            return {"message": {"content": "hello"}}
        return {"message": {"tool_calls": [{"function": {"name": case["expect"]["name"],
                                                         "arguments": case["expect"]["arguments"]}}]}}

    def loaded_models(self):
        return [{"name": "m", "model": "m", "size": 100, "size_vram": 100 if self.on_gpu else 60}]

    def unload(self, model):
        self.unloaded.append(model)


def test_eval_data_is_well_formed():
    choose = evaluate.load_jsonl("choose.jsonl")
    assert len(choose) >= 30
    assert all(0 <= c["answer"] < len(c["options"]) <= 20 for c in choose)
    counts = [[c["answer"] for c in choose].count(i) for i in range(4)]
    assert max(counts) - min(counts) <= 2
    names = {t["function"]["name"] for t in evaluate.load_toolset()}
    assert all(c["expect"] is None or c["expect"]["name"] in names for c in evaluate.load_jsonl("tools.jsonl"))


def test_a_perfect_model_scores_full_marks_and_is_unloaded():
    client = ScriptedClient()
    r = evaluate.evaluate(client, "m")
    assert r.tool_success == 1.0 and r.choose_accuracy == 1.0
    assert r.fully_on_gpu is True and r.tokens_per_s >= 15 and r.errors == []
    assert client.unloaded == ["m"]


def test_verdict_hard_limits_and_comparisons():
    base = ModelResult("old", tool_success=0.8, choose_accuracy=0.8, choose_ece=0.10, tokens_per_s=30, fully_on_gpu=True)
    good = ModelResult("new", tool_success=0.9, choose_accuracy=0.8, choose_ece=0.08, tokens_per_s=40, fully_on_gpu=True)
    assert verdict(good, base)["passes"] is True
    fewer_tools = ModelResult("new", tool_success=0.7, choose_accuracy=0.9, choose_ece=0.05, tokens_per_s=40, fully_on_gpu=True)
    assert verdict(fewer_tools, base)["passes"] is False
    slow = ModelResult("new", tool_success=0.9, choose_accuracy=0.9, choose_ece=0.05, tokens_per_s=9, fully_on_gpu=True)
    assert "tokens/s" in " ".join(verdict(slow, base)["reasons"])
    split = ModelResult("new", tool_success=0.9, choose_accuracy=0.9, choose_ece=0.05, tokens_per_s=40, fully_on_gpu=False)
    assert verdict(split, base)["passes"] is False


def test_run_writes_a_report_with_verdicts(tmp_path):
    report = evaluate.run(["m"], client=ScriptedClient(), baseline_model="m", out_dir=tmp_path)
    assert report["baseline"] == "m" and report["verdicts"]["m"]["passes"] is True
    assert (tmp_path / "latest.json").exists()
```

```python
import json

from nar_tools import cli


def test_fit_prints_a_decision(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    assert cli.main(["fit", "--task-type", "general"]) == 0
    assert "not enough" in json.loads(capsys.readouterr().out)["reason"]


def test_errors_exit_nonzero(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    assert cli.main(["fit", "--task-type", "../x"]) == 1
    assert "task_type" in capsys.readouterr().err
```

Run: `uv run pytest tests/test_evaluate.py tests/test_cli.py -q` -> FAIL (modules missing).

- [ ] **Step 3: Implement** `src/nar_tools/evaluate.py`

```python
"""The bake-off: the same fixed tasks for every local model, and the rule for adopting one."""
from __future__ import annotations

import json
import platform
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

from nar_tools.calibration import Sample, ece
from nar_tools.ollama import OllamaClient, OllamaUnavailable, local_state
from nar_tools.scoring import build_messages, letter_logprobs
from nar_tools.store import nar_home

EVALS = Path(__file__).resolve().parent / "evals"
SPEED_PROMPT = "Explain in about 150 words why a test should fail before its fix is written."
MIN_TOKENS_PER_S = 15.0


@dataclass
class ModelResult:
    model: str
    tool_success: float = 0.0
    choose_accuracy: float = 0.0
    choose_ece: float = 1.0
    tokens_per_s: float = 0.0
    fully_on_gpu: bool = False
    errors: list[str] = field(default_factory=list)


def load_jsonl(name: str) -> list[dict]:
    lines = (EVALS / name).read_text(encoding="utf-8").splitlines()
    return [json.loads(line) for line in lines if line.strip()]


def load_toolset() -> list[dict]:
    return json.loads((EVALS / "toolset.json").read_text(encoding="utf-8"))


def _args_match(expected: dict, got: dict) -> bool:
    for key, want in expected.items():
        have = got.get(key)
        if isinstance(want, (int, float)) and not isinstance(want, bool):
            try:
                if abs(float(have) - float(want)) > 1e-6:
                    return False
            except (TypeError, ValueError):
                return False
        elif str(have).strip().lower() != str(want).strip().lower():
            return False
    return True


def eval_tools(client, model: str) -> float:
    toolset, cases, ok = load_toolset(), load_jsonl("tools.jsonl"), 0
    for case in cases:
        reply = client.chat(model, [{"role": "user", "content": case["prompt"]}], tools=toolset)
        calls = (reply.get("message") or {}).get("tool_calls") or []
        if case["expect"] is None:
            ok += not calls
            continue
        if not calls:
            continue
        fn = calls[0].get("function") or {}
        args = fn.get("arguments") or {}
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except ValueError:
                args = {}
        ok += fn.get("name") == case["expect"]["name"] and _args_match(case["expect"]["arguments"], args)
    return ok / len(cases)


def eval_choose(client, model: str) -> tuple[float, float]:
    cases, samples, correct = load_jsonl("choose.jsonl"), [], 0
    for case in cases:
        raw, _ = letter_logprobs(client.next_token_logprobs(model, build_messages(case["question"], case["options"])),
                                 len(case["options"]))
        samples.append(Sample(tuple(raw), case["answer"]))
        correct += max(range(len(raw)), key=raw.__getitem__) == case["answer"]
    return correct / len(cases), ece(samples, 1.0)


def eval_speed(client, model: str) -> tuple[float, bool]:
    reply = client.chat(model, [{"role": "user", "content": SPEED_PROMPT}], num_predict=200)
    tps = reply.get("eval_count", 0) / max(reply.get("eval_duration", 0) / 1e9, 1e-9)
    on_gpu = any((m.get("name") == model or m.get("model") == model) and m.get("size", 0) > 0
                 and m.get("size_vram", 0) >= m.get("size", 0) for m in client.loaded_models())
    return tps, on_gpu


def evaluate(client, model: str) -> ModelResult:
    r = ModelResult(model)
    try:
        for label, step in (("tools", lambda: setattr(r, "tool_success", eval_tools(client, model))),
                            ("choose", lambda: _set_choose(r, eval_choose(client, model))),
                            ("speed", lambda: _set_speed(r, eval_speed(client, model)))):
            try:
                step()
            except (OllamaUnavailable, KeyError, ValueError) as e:
                r.errors.append(f"{label}: {e}")
    finally:
        try:
            client.unload(model)
        except OllamaUnavailable:
            pass
    return r


def _set_choose(r: ModelResult, value: tuple[float, float]) -> None:
    r.choose_accuracy, r.choose_ece = value


def _set_speed(r: ModelResult, value: tuple[float, bool]) -> None:
    r.tokens_per_s, r.fully_on_gpu = value


def verdict(candidate: ModelResult, baseline: ModelResult | None, min_tps: float = MIN_TOKENS_PER_S) -> dict:
    reasons = []
    if candidate.errors:
        reasons.append("errors: " + "; ".join(candidate.errors))
    if not candidate.fully_on_gpu:
        reasons.append("does not run entirely on the GPU")
    if candidate.tokens_per_s < min_tps:
        reasons.append(f"{candidate.tokens_per_s:.1f} tokens/s is below {min_tps:g}")
    if baseline is not None and baseline.model != candidate.model:
        if candidate.tool_success < baseline.tool_success:
            reasons.append("fewer successful tool calls than the current default")
        if candidate.choose_accuracy < baseline.choose_accuracy:
            reasons.append("lower nar_choose accuracy than the current default")
        if candidate.choose_ece > baseline.choose_ece:
            reasons.append("worse calibration than the current default")
    return {"passes": not reasons, "reasons": reasons}


def run(models: list[str], client=None, baseline_model: str | None = None, out_dir: Path | None = None) -> dict:
    client = client or OllamaClient()
    baseline_model = baseline_model or local_state().get("default")
    names = list(dict.fromkeys(models + ([baseline_model] if baseline_model else [])))
    results = {m: evaluate(client, m) for m in names}
    base = results.get(baseline_model) if baseline_model else None
    report = {"created_at": time.time(), "machine": platform.node(), "baseline": baseline_model,
              "models": {m: asdict(r) for m, r in results.items()},
              "verdicts": {m: verdict(r, base) for m, r in results.items()}}
    out = Path(out_dir) if out_dir else nar_home() / "eval"
    out.mkdir(parents=True, exist_ok=True)
    text = json.dumps(report, indent=2)
    (out / f"{time.strftime('%Y%m%d-%H%M%S')}.json").write_text(text, encoding="utf-8")
    (out / "latest.json").write_text(text, encoding="utf-8")
    return report
```

`src/nar_tools/cli.py`:

```python
"""The `nar` command: eval, fit, status, choose."""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict

from nar_tools import gate
from nar_tools.evaluate import run
from nar_tools.ollama import OllamaClient, OllamaUnavailable
from nar_tools.service import NarService
from nar_tools.store import NarStore


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="nar", description="Calibrated single-pass scoring with the local model")
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("eval", help="bake-off; writes <NAR_HOME>/eval/latest.json")
    e.add_argument("--models", required=True, help="comma-separated Ollama tags")
    e.add_argument("--baseline", help="tag to compare against (default: the current default model)")
    f = sub.add_parser("fit", help="refit, and maybe promote, one task type's calibrator")
    f.add_argument("--task-type", default="general")
    sub.add_parser("status", help="counts, calibrators, last decision")
    c = sub.add_parser("choose", help="score options once (manual check)")
    c.add_argument("question")
    c.add_argument("-o", "--option", action="append", required=True)
    c.add_argument("--task-type", default="general")
    args = p.parse_args(argv)
    try:
        if args.cmd == "eval":
            report = run([m.strip() for m in args.models.split(",") if m.strip()], baseline_model=args.baseline)
            out = {"baseline": report["baseline"], "verdicts": report["verdicts"], "models": report["models"]}
        elif args.cmd == "fit":
            out = asdict(gate.refit(NarStore(), args.task_type))
        elif args.cmd == "status":
            out = NarService(OllamaClient(), NarStore()).status()
        else:
            out = NarService(OllamaClient(), NarStore()).choose(args.question, args.option, args.task_type)
    except (OllamaUnavailable, ValueError, TimeoutError) as err:
        print(json.dumps({"error": str(err)}), file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run, see them pass** (`uv run pytest -q` -> whole suite green)

- [ ] **Step 5: Commit** (`git commit -m "nar: bake-off (nar eval) and CLI"`)

---

### Task 12: aos registers nar, runs it from ~\.aos, and adopts models through the gate

**Files:**
- Modify: `aos.psm1` (`Get-AosMcpManifest`, `Expand-AosPlaceholders`, `Test-AosMcpCurrent`, `Add-AosMcpServer`, `Sync-AosMcp`, `Get-AosStatus` MCP section, `Get-AosNarVenv`, `Install-AosNarTools` (replace the Task 1 stub), `Get-AosNarHome`, `Invoke-AosLocalAdopt`, dispatcher `local` and `nar`, help), `config/mcp.json`
- Test: `tests/aos.Tests.ps1` (`Describe 'MCP placeholders and nar registration'`, `Describe 'aos local adopt'`)

**Interfaces:**
- Consumes: `Get-AosLocalConfig`, `Get-AosLocalConfigPath`, `Get-AosStateDir`, `Sync-AosLocalState` (Task 1); `Sync-AosCodexProfiles` (existing); the report format from Task 11 (`baseline`, `verdicts[tag].passes`, `verdicts[tag].reasons`).
- Produces: `aos local adopt <tag> [-DryRun]`, `aos nar <args>` (runs `~\.aos\venvs\nar-tools\Scripts\nar.exe`), `nar` registered in Claude Code and Codex by `aos sync` once the venv exists.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'MCP placeholders and nar registration' {
    BeforeEach {
        $savedProjects = $env:AOS_PROJECTS
        $env:AOS_PROJECTS = Join-Path $caseRoot 'projects'
        $exe = Join-Path $env:AOS_PROJECTS 'nar-tools\nar-mcp.exe'
        Mock Add-AosMcpServer -ModuleName aos { $true }
        Mock Write-AosInfo -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -in @('claude', 'codex') }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 1; Text = 'No MCP server found' } } -ParameterFilter { $CommandLine -like '* mcp get *' }
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{ nar = [ordered]@{
                transport = 'stdio'; command = '{{projects}}\nar-tools\nar-mcp.exe'; args = @()
                requires = '{{projects}}\nar-tools\nar-mcp.exe' } } }
        }
    }
    AfterEach { $env:AOS_PROJECTS = $savedProjects }

    It 'expands the projects and home placeholders' {
        InModuleScope aos {
            Expand-AosPlaceholders '{{projects}}\x' | Should -BeExactly (Join-Path $env:AOS_PROJECTS 'x')
            Expand-AosPlaceholders '{{home}}\.aos' | Should -BeExactly ($HOME + '\.aos')
        }
    }

    It 'skips a server whose required file does not exist yet' {
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosInfo -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'nar skipped' }
    }

    It 'registers the expanded command in both agents once the file exists' {
        Write-TestFile $exe ''
        InModuleScope aos { Sync-AosMcp }
        # PowerShell names are case-insensitive: the loop variable must not be called $agent.
        foreach ($want in 'claude', 'codex') {
            Should -Invoke Add-AosMcpServer -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Agent -eq $want -and $Command[0] -eq $exe -and -not $Http }
        }
    }

    It 'treats a registration as current when the CLI shows the command, even JSON-escaped' {
        Write-TestFile $exe ''
        $escaped = $exe.Replace('\', '\\')
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "{`"transport`": {`"type`": `"stdio`", `"command`": `"$escaped`"}}" } } -ParameterFilter { $CommandLine -eq 'codex mcp get nar --json' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "nar:`n  Command: $exe" } } -ParameterFilter { $CommandLine -eq 'claude mcp get nar' }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'aos local adopt' {
    BeforeAll {
        function Write-Report($Verdicts, [string]$Baseline = 'old:tag') {
            $report = [ordered]@{ baseline = $Baseline; verdicts = $Verdicts }
            Write-TestFile (Join-Path $env:NAR_HOME 'eval\latest.json') (ConvertTo-Json -Depth 10 -InputObject $report)
        }
    }
    BeforeEach {
        $savedNar = $env:NAR_HOME
        $env:NAR_HOME = Join-Path $caseRoot 'nar'
        $configPath = Join-Path $caseRoot 'local.json'
        Write-TestFile $configPath '{ "default": "old:tag", "optional": [] }'
        Mock Get-AosLocalConfigPath -ModuleName aos { $configPath }
        Mock Sync-AosLocalState -ModuleName aos { }
        Mock Sync-AosCodexProfiles -ModuleName aos { }
        Mock Write-AosWarn -ModuleName aos { }
    }
    AfterEach { $env:NAR_HOME = $savedNar }

    It 'refuses without an eval report' {
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'no eval report' }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 0 -Exactly
    }

    It 'refuses a report made against another baseline' {
        Write-Report @{ 'new:tag' = @{ passes = $true; reasons = @() } } 'other:tag'
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'other:tag' }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
    }

    It 'refuses a candidate that did not pass, naming the reasons' {
        Write-Report @{ 'new:tag' = @{ passes = $false; reasons = @('worse calibration than the current default') } }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'worse calibration' }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
    }

    It 'adopts a passing candidate and regenerates the derived files' {
        Write-Report @{ 'new:tag' = @{ passes = $true; reasons = @() } }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        (Get-Content -Raw $configPath | ConvertFrom-Json).default | Should -BeExactly 'new:tag'
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 1 -Exactly
        Should -Invoke Sync-AosCodexProfiles -ModuleName aos -Times 1 -Exactly
    }

    It 'changes nothing in DryRun' {
        Write-Report @{ 'new:tag' = @{ passes = $true; reasons = @() } }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' -DryRun }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 0 -Exactly
    }
}
```

- [ ] **Step 2: Run, see them fail** (`tests\Run-Tests.ps1`; the 9 new tests FAIL)

- [ ] **Step 3: Implement**

`config/mcp.json`, add to `servers`:

```json
    "nar": {
      "transport": "stdio",
      "command": "{{home}}\\.aos\\venvs\\nar-tools\\Scripts\\nar-mcp.exe",
      "args": [],
      "requires": "{{home}}\\.aos\\venvs\\nar-tools\\Scripts\\nar-mcp.exe",
      "why": "Local, calibrated single-pass (non-autoregressive) scoring of options; agents call it only when a choice among known alternatives benefits from it."
    }
```

`aos.psm1` - replace `Sync-AosMcp` and add the helpers:

```powershell
function Get-AosMcpManifest { return Read-AosJson (Join-Path $script:Root 'config\mcp.json') }

function Expand-AosPlaceholders([string]$Text) {
    # Repo files hold no absolute paths; these resolve on the machine at run time.
    return $Text.Replace('{{projects}}', (Get-AosProjectsDir)).Replace('{{home}}', $HOME)
}

function Test-AosMcpCurrent($Result, [string[]]$Needles) {
    if ($Result.Code -ne 0) { return $false }
    $text = ([string]$Result.Text).Replace('\\', '\')   # codex prints JSON: its backslashes arrive doubled
    foreach ($n in $Needles) { if ($text.IndexOf($n, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }
    return $true
}

function Add-AosMcpServer([string]$Agent, [string]$Name, [bool]$Http, [string]$Url, [string[]]$Command) {
    if ($Agent -eq 'claude') {
        if ($Http) { claude mcp add --scope user --transport http $Name $Url | Out-Host }
        else { claude mcp add --scope user $Name -- @Command | Out-Host }
    }
    else {
        if ($Http) { codex mcp add $Name --url $Url | Out-Host }
        else { codex mcp add $Name -- @Command | Out-Host }
    }
    return ($LASTEXITCODE -eq 0)
}

function Sync-AosMcp([switch]$DryRun) {
    # Registered = present AND pointing where the manifest says; a changed URL or command is re-added.
    $manifest = Get-AosMcpManifest
    foreach ($name in @($manifest['servers'].Keys)) {
        $s = $manifest['servers'][$name]
        if ($s.Contains('requires')) {
            $need = Expand-AosPlaceholders ([string]$s['requires'])
            if (-not (Test-Path -LiteralPath $need)) { Write-AosInfo "$name skipped: $need not found yet"; continue }
        }
        $isHttp = ($s['transport'] -eq 'http')
        $cmd = @()
        if ($isHttp) { $needles = @([string]$s['url']) }
        else {
            $cmd = @(Expand-AosPlaceholders ([string]$s['command'])) + @(@($s['args']) | Where-Object { $null -ne $_ } | ForEach-Object { Expand-AosPlaceholders ([string]$_) })
            $needles = $cmd
        }
        foreach ($agent in @('claude', 'codex')) {
            if (-not (Test-AosCommand $agent)) { Write-AosWarn "$agent missing; $name not registered there"; continue }
            $getCmd = "claude mcp get $name"
            if ($agent -eq 'codex') { $getCmd = "codex mcp get $name --json" }
            $got = Invoke-AosCapture $getCmd
            if (Test-AosMcpCurrent $got $needles) { Write-AosOk "${agent}: $name"; continue }
            if ($DryRun) { Write-AosDry "$agent mcp add $name"; continue }
            if ($got.Code -eq 0) {
                $rm = "claude mcp remove $name --scope user"
                if ($agent -eq 'codex') { $rm = "codex mcp remove $name" }
                $null = Invoke-AosCapture $rm
                Write-AosInfo "${agent}: $name changed; re-adding"
            }
            if (Add-AosMcpServer -Agent $agent -Name $name -Http $isHttp -Url ([string]$s['url']) -Command $cmd) { Write-AosOk "${agent}: added $name" }
            else { Write-AosWarn "${agent}: adding $name failed" }
        }
    }
}

function Get-AosNarVenv { return (Join-Path (Get-AosStateDir) 'venvs\nar-tools') }

function Get-AosNarHome {
    if ($env:NAR_HOME) { return $env:NAR_HOME }
    return (Join-Path (Get-AosStateDir) 'nar')
}

function Install-AosNarTools([switch]$DryRun) {
    # nar-tools (Desktop\1-Projects\nar-tools) runs from a venv under ~\.aos, outside OneDrive and AppData.
    $repo = Join-Path (Get-AosProjectsDir) 'nar-tools'
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'pyproject.toml'))) { Write-AosInfo "nar-tools not found in $repo; skipped"; return }
    if (-not (Test-AosCommand uv)) { Write-AosWarn 'uv missing (aos install base)'; return }
    $venv = Get-AosNarVenv
    if ($DryRun) { Write-AosDry "uv sync --frozen --no-dev (venv $venv)"; return }
    $savedEnv = $env:UV_PROJECT_ENVIRONMENT; $savedLink = $env:UV_LINK_MODE
    $env:UV_PROJECT_ENVIRONMENT = $venv; $env:UV_LINK_MODE = 'copy'
    try { $r = Invoke-AosCapture "uv sync --frozen --no-dev --directory `"$repo`"" }
    finally { $env:UV_PROJECT_ENVIRONMENT = $savedEnv; $env:UV_LINK_MODE = $savedLink }
    if ($r.Code -eq 0) { Write-AosOk "nar-tools ready in $venv" } else { Write-AosWarn "uv sync for nar-tools failed (exit $($r.Code))" }
}

function Invoke-AosLocalAdopt([string]$Tag, [switch]$DryRun) {
    # The only way the default local model changes: the latest `nar eval` must say it is no worse.
    if (-not $Tag) { Write-AosWarn 'usage: aos local adopt <ollama tag>'; return }
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { Write-AosWarn 'config/local.json missing'; return }
    if ($cfg['default'] -eq $Tag) { Write-AosOk "$Tag is already the default"; return }
    $reportPath = Join-Path (Get-AosNarHome) 'eval\latest.json'
    $report = Read-AosJson $reportPath
    if (-not $report) { Write-AosWarn "no eval report at $reportPath (run: aos nar eval --models $Tag)"; return }
    if ($report['baseline'] -ne $cfg['default']) { Write-AosWarn "the latest report compared against $($report['baseline']), not the current default $($cfg['default']); run aos nar eval again"; return }
    if (-not ($report['verdicts'] -and $report['verdicts'].Contains($Tag))) { Write-AosWarn "the latest report has no verdict for $Tag (run: aos nar eval --models $Tag)"; return }
    $v = $report['verdicts'][$Tag]
    if (-not $v['passes']) { Write-AosWarn ("$Tag did not pass: " + (@($v['reasons']) -join '; ')); return }
    if ($DryRun) { Write-AosDry "would make $Tag the default in config/local.json"; return }
    $cfg['default'] = $Tag
    Write-AosText -Path (Get-AosLocalConfigPath) -Text ((ConvertTo-Json -InputObject $cfg -Depth 10) + "`n")
    Write-AosOk "default local model is now $Tag (commit config/local.json)"
    Sync-AosLocalState
    Sync-AosCodexProfiles
}

function Invoke-AosNar([string[]]$Arguments) {
    $exe = Join-Path (Get-AosNarVenv) 'Scripts\nar.exe'
    if (-not (Test-Path -LiteralPath $exe)) { Write-AosWarn 'nar-tools is not installed (aos install local)'; return }
    & $exe @Arguments
    $global:LASTEXITCODE = $LASTEXITCODE
}
```

In `Get-AosStatus`'s MCP section: read the manifest with `Get-AosMcpManifest`, and at the top of the per-server loop:

```powershell
        $s = $manifest['servers'][$name]
        if ($s.Contains('requires') -and -not (Test-Path -LiteralPath (Expand-AosPlaceholders ([string]$s['requires'])))) { Write-AosInfo "${name}: not set up yet"; continue }
```

Dispatcher (`aos`), add:

```powershell
        'local'   { if ($a1 -eq 'adopt') { Invoke-AosLocalAdopt -Tag $a2 -DryRun:$DryRun } else { Write-AosWarn 'usage: aos local adopt <ollama tag>' } }
        'nar'     { Invoke-AosNar -Arguments @($Rest) }
```

Help, add:

```
  aos local adopt <tag>      make a model the local default, only if the latest nar eval says it is no worse
  aos nar <args>             the nar CLI (eval, fit, status, choose) from its venv in ~\.aos
```

- [ ] **Step 4: Run, see them pass** (`aos test`: all green in both shells)

- [ ] **Step 5: Commit**

```bash
git add aos.psm1 config/mcp.json tests/aos.Tests.ps1
git commit -m "aos: nar registration with run-time paths, aos nar, aos local adopt"
```

---

### Task 13: Install, bake-off, adopt, register (live)

**Files:** none changed except `config/local.json` if a candidate is adopted.

- [ ] **Step 1: Preview, then install** (downloads: Ollama via winget, then `openbmb/minicpm5-2b:q8_0` 2.7 GB and `qwen3.5:4b` 3.4 GB)

Run: `aos install local -DryRun`, then `aos install local`.
Expected: `Ollama.Ollama installed`, both models `pulled`, `wrote ~\.aos\local.json`, `nar-tools ready in ~\.aos\venvs\nar-tools`. `ollama --version` reports 0.12.11 or newer (logprobs).

- [ ] **Step 2: Pull the remaining candidate** (2.2 GB): `ollama pull granite4.2:3b`

- [ ] **Step 3: Bake-off**

Run: `aos nar eval --models openbmb/minicpm5-2b:q8_0,qwen3.5:4b,granite4.2:3b`
Expected: a report per model (tool success, choose accuracy, ECE, tokens/s, GPU) and verdicts against the default. Record the numbers for `docs/decisions.md`.

- [ ] **Step 4: Adopt if a candidate passes and is better**

If a non-default candidate passes and is better on the gated metrics: `aos local adopt <tag>`, commit `config/local.json`. If the default fails a hard limit and no candidate passes, stop and report to the user before changing anything.

- [ ] **Step 5: Register and check**

Run: `aos sync` (registers `nar` in Claude Code and Codex), `aos status` (Local models ok; claude/codex: nar ok).
Run: `codex exec --profile local "Reply with the single word OK" </dev/null` - the Codex local profile works through Ollama.
Run: `codex exec "Call the nar_choose tool with question 'Which is a prime number?' and options ['21','29','33'], then print its JSON" </dev/null` - result has `choice` 29 and a `call_id`.
Run: `claude -p "Use the nar_choose MCP tool once: question 'Which planet is closest to the Sun?', options Venus, Mercury, Mars. Print the tool's JSON." --allowedTools mcp__nar__nar_choose` - same shape.
Run the outside-the-package probe (WMI, as in round 3) with `aos status` and `aos nar status`: all ok.

- [ ] **Step 6: Ask the user for the offline check** (criterion 2): with Wi-Fi off, in Windows Terminal: `aos nar choose "Which is larger?" -o 7 -o 12` returns a result.

---

### Task 14: Contract, docs, reviews, merge

**Files:** `agents-home/AGENTS.md`, `README.md`, `docs/decisions.md`, `docs/routing.md`; nar-tools `README.md` (short).

- [ ] **Step 1: Contract** - in `agents-home/AGENTS.md` replace the line `- No local models (6 GB VRAM). All model work is cloud.` with:

```markdown
- Local model: Ollama on this laptop (`aos install local`; the tag is in agentic-os `config/local.json`;
  `codex --profile local`). Private and offline, much weaker than the cloud models. The `nar` MCP tools
  score options in one pass of it: use them for choices among known alternatives, then report the real
  outcome with `nar_feedback`.
```

- [ ] **Step 2: README / routing / decisions**

README layer table, new row after `refs`:

```markdown
| **local** | Ollama and the local model; the `nar` tools (calibrated single-pass scoring) | `config/local.json`, `Desktop\1-Projects\nar-tools`; models in `~\.ollama` |
```

README Daily use, new rows:

```markdown
| Use the local model | `codex --profile local`; agents call the `nar` tools on their own when a choice benefits |
| Try a newer local model | `ollama pull <tag>`, `aos nar eval --models <tag>`, then `aos local adopt <tag>` (only if no worse) |
```

`docs/routing.md` "Which vendor" table, new row:

```markdown
| Private, offline or quick throwaway work; scoring a choice | the local model (`codex --profile local`, `nar` tools) | free, private, works offline; much weaker |
```

`docs/decisions.md`, new entry on top, filled from `~\.aos\nar\eval\latest.json`:

```markdown
## 2026-09-28 - Local model and the nar tools

- **Bake-off on this laptop** (fixed tasks, temperature 0): one line per model with tool success,
  nar_choose accuracy, ECE, tokens/s, on GPU yes/no - copied from the report.
- **Default:** <the tag in config/local.json after Step 4 of Task 13>, because <the verdict's reasons>.
- **nar**: one forward pass per choice (Ollama logprobs), temperature calibration per task type,
  promotion only if Brier and ECE on held-out calls are no worse; data in ~\.aos\nar.
```
- [ ] **Step 3: `aos sync`** so Codex's copy of the contract updates; `aos test` green.
- [ ] **Step 4: Reviews** - Codex reviews agentic-os `main..local-stack` and nar-tools `main` read-only (`codex exec --profile review`); fix findings with tests first.
- [ ] **Step 5: CI and merge** - push `local-stack`, CI green, fast-forward `main`, push. nar-tools: push to its GitHub repo (if the user approved creating it), CI green.
