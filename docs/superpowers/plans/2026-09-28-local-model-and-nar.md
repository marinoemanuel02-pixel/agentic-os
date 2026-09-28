# Local model layer and nar-tools v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An `aos install local` layer that runs a local model through Ollama, and a new `nar-tools` repo whose `nar` MCP tools score options in one forward pass of that model, learn calibration from outcomes without regressing, and gate local model upgrades - registered in Claude Code and Codex.

**Architecture:** agentic-os gains a `local` layer (Ollama via winget, model tags in `config/local.json`, generated `~\.aos\local.json` and Codex `local` profile) plus MCP placeholders so `nar` registers from a venv under `~\.aos`. `nar-tools` (Python, uv) is a small package: an Ollama client, single-pass letter scoring, temperature calibration per model and task type, append-only storage with OS file locks, the promotion gate, a service layer, a FastMCP stdio server, and the bake-off. Build steps 1 and 2 of the spec; the gateway, Paseo and OpenCode (steps 3-5) get their own plans. One deliberate move from the spec's step 1: OpenCode's Ollama provider config and its `nar` registration go to the step-4 plan, where OpenCode is installed and the config can be verified.

**Tech Stack:** PowerShell 5.1 + 7 and Pester 5 (agentic-os); Python 3.13, uv, `mcp` 1.x (FastMCP; v2 renamed it `MCPServer`, a later migration), pydantic `Strict` (bundled with mcp), `httpx`, pytest (nar-tools); Ollama 0.12.11 or newer.

**Spec:** `docs/superpowers/specs/2026-09-28-local-stack-design.md`

## Global Constraints

- `aos.psm1` and `bootstrap.ps1` stay ASCII-only and run under Windows PowerShell 5.1 and PowerShell 7: no `??`, no ternary, no `&&`/`||`.
- Tests first: every new test is run and seen failing before its code exists (agentic-os rule 3).
- Tests use `$TestDrive`, `$env:AOS_BACKUPS`, `tmp_path` and fakes - never the real profile, registry, network, npm config or a live Ollama. Live checks happen only in Task 13.
- Idempotent: a second `aos sync` / `aos install local` changes nothing.
- Nothing is installed or cloned under AppData from inside the desktop apps: state in `~\.aos`, models in `~\.ollama`, the nar venv in `~\.aos\venvs\nar-tools`; uv never downloads a Python (`UV_PYTHON_DOWNLOADS=never`, the venv uses the system Python 3.13).
- Local model tags live only in `config/local.json` and change only through `aos local adopt` (the eval gate). Cloud models stay unnamed.
- No absolute paths in either repo; `{{home}}` / `{{projects}}` placeholders resolve at run time.
- No secrets in files.
- `nar` data (task text) stays in `NAR_HOME` (default `~\.aos\nar`), never in OneDrive or git.
- Calibration is kept per model AND task type: a new model starts uncalibrated (temperature 1) and never inherits another model's temperature or outcomes.
- Cross-process locks are OS file locks (`msvcrt.locking` on Windows): the OS releases them if a holder dies; they are never taken over on a timer.
- At most 20 options per `nar_choose` (Ollama returns at most 20 alternatives per position).
- `aos nar` arguments use long options (`--option`): PowerShell reads `-o` as its own `-OutVariable`/`-OutBuffer` (verified in 5.1 and 7).
- Promotion rule: a refitted calibrator replaces the current one only if Brier score AND expected calibration error on the held-out calls are both no worse. Model rule: gated metrics (tool-call success, `nar_choose` accuracy, calibration error with the calibration each model would really use) no worse than a successfully measured current default; hard limits: fully on the 6 GB GPU and at least `min_tokens_per_s` (15) tokens/s.

## Review Focus

1. Ollama not running, or the model not pulled, when an agent calls a nar tool -> a structured `{"unavailable": true, "reason": ...}` result, never an exception (test in Task 10).
2. The model's generated first token is not an option letter (it starts thinking, writes prose, answers in lowercase or with a letter outside the options), even when letters appear among the alternatives -> equal probabilities with `letter_signal: false`, never a confident pick from a low-probability alternative (tests in Task 5).
3. Bad inputs: fewer than 2 or more than 20 options, empty or duplicate options, a `task_type` with path characters, more than 50 items to classify, a boolean as feedback outcome through MCP -> an error result and nothing logged (tests in Tasks 9 and 10).
4. Feedback for an unknown `call_id`, an out-of-range index, or text matching no option -> an error and nothing appended (tests in Task 9).
5. Claude, Codex and OpenCode each run their own `nar-mcp` process: concurrent appends keep every line whole; a live refit holder is never evicted; a crashed holder's lock is released by the OS (multi-process tests in Task 7).

## Plan review (Codex, before any code)

All 14 findings accepted: clipped NLL broke the temperature search (Task 6, log-softmax); the generated token was ignored (Tasks 4-5); a failed baseline could authorize adoption (Task 11); the lock could evict a live holder (Task 7, OS locks); calibration leaked across models and the eval used T=1 (Tasks 7-9, 11); uv could download Python into AppData (Tasks 3, 12); `-o` breaks `aos nar` (Tasks 12-13); `aos sync` skipped the local state (Task 12); gate tests could not tell AND from OR (Tasks 8, 11); MCP feedback rejected integers and accepted booleans (Task 10); invalid tool calls scored as success (Task 11); a torn line swallowed the next record (Task 7); rollback overwrote version history (Task 7); GPU share, reliability and the speed floor were never reported or used (Tasks 1, 9, 11).

## File Structure

agentic-os (branch `local-stack`):
- `config/local.json` (new): default/optional/candidate model tags, Ollama URL, speed floor.
- `packages.json` (modify): new `local` list with `Ollama.Ollama`.
- `config/mcp.json` (modify): `nar` server with `{{home}}` placeholders and `requires`.
- `aos.psm1` (modify): local layer, local state, GPU check, Codex `local` profile, MCP placeholders and `Add-AosMcpServer`, nar venv, `aos nar`, `aos local adopt`, status lines, `Sync-AosBrain` wiring.
- `bootstrap.ps1` (modify): `local` in the layer list.
- `tests/aos.Tests.ps1` (modify): Describe blocks for each aos task.
- `agents-home/AGENTS.md`, `README.md`, `docs/decisions.md`, `docs/routing.md` (modify, Task 14).

nar-tools (new repo `Desktop\1-Projects\nar-tools`):
- `pyproject.toml`, `uv.lock`, `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.gitattributes`, `.github/workflows/ci.yml`
- `src/nar_tools/__init__.py`, `ollama.py` (HTTP client), `scoring.py` (letters -> log-probs), `calibration.py` (temperature, Brier, ECE), `store.py` (JSONL, calibrators, OS locks), `gate.py` (the promotion rule), `service.py` (what the tools do), `server.py` (FastMCP), `evaluate.py` (bake-off), `cli.py` (`nar`)
- `src/nar_tools/evals/choose.jsonl`, `tools.jsonl`, `toolset.json`
- `tests/test_*.py`, one per module.

## Who does what

Tasks 1, 2 and 12 (agentic-os): Codex writes the Pester tests (at least the ones below), Claude implements. Tasks 3-11 (nar-tools): Codex implements test and code per task in its sandbox; Claude reviews each task's diff, runs the tests and commits (Codex's sandbox cannot write `.git`). Tasks 13-14: Claude, with the user for the downloads.

---

### Task 1: The `local` layer in aos

**Files:**
- Create: `config/local.json`
- Modify: `packages.json` (add `local` list), `aos.psm1` (new functions after `Get-AosProjectsDir`; `$script:Layers`; `Install-AosLayer` switch; `Get-AosStatus`; help), `bootstrap.ps1` (ValidateSet)
- Test: `tests/aos.Tests.ps1` (new `Describe 'Local model layer'` inside the outer Describe)

**Interfaces:**
- Produces: `Get-AosLocalConfigPath`, `Get-AosLocalConfig` (ordered dictionary or `$null`), `Get-AosStateDir` (`~\.aos`), `Test-AosOllamaModel -List <ollama list text> -Tag <tag>` (bool), `Test-AosOllamaGpu -PsText <ollama ps text> -Tag <tag>` (`'gpu'`, `'split'` or `'absent'`), `Sync-AosLocalState [-DryRun]` (writes `~\.aos\local.json`: `default`, `ollama_url`, `min_tokens_per_s`), `Install-AosLocal [-DryRun]`, and a stub `Install-AosNarTools` (real in Task 12).

- [ ] **Step 1: Write the failing tests** (append inside the outer `Describe 'aos isolated suite'`, before its closing brace), and add the stub `function Install-AosNarTools([switch]$DryRun) { }` to `aos.psm1` so the mock has a target.

```powershell
Describe 'Local model layer' {
    BeforeEach {
        $stateDir = Join-Path $caseRoot 'state'
        Mock Get-AosStateDir -ModuleName aos { $stateDir }
        Mock Get-AosLocalConfig -ModuleName aos {
            [ordered]@{ default = 'openbmb/minicpm5-2b:q8_0'; optional = @('qwen3.5:4b'); ollama_url = 'http://127.0.0.1:11434'; min_tokens_per_s = 15 }
        }
        Mock Install-AosWingetPackage -ModuleName aos { }
        Mock Install-AosNarTools -ModuleName aos { }
        Mock Write-AosWarn -ModuleName aos { }
        Mock Write-AosOk -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'ollama' }
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME                        ID     SIZE      MODIFIED`nopenbmb/minicpm5-2b:q8_0    abc    2.7 GB    1 day ago" }
        } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'success' } } -ParameterFilter { $CommandLine -like 'ollama pull *' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'OK' } } -ParameterFilter { $CommandLine -like 'ollama run *' }
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME                        ID     SIZE      PROCESSOR    CONTEXT    UNTIL`nopenbmb/minicpm5-2b:q8_0    abc    3.9 GB    100% GPU     4096       4 minutes from now" }
        } -ParameterFilter { $CommandLine -eq 'ollama ps' }
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

    It 'reads the GPU share from ollama ps' {
        InModuleScope aos {
            $ps = "NAME ID SIZE PROCESSOR`na:1 x 3 GB 100% GPU 4096 now`nb:1 y 9 GB 48%/52% CPU/GPU 4096 now"
            Test-AosOllamaGpu -PsText $ps -Tag 'a:1' | Should -BeExactly 'gpu'
            Test-AosOllamaGpu -PsText $ps -Tag 'b:1' | Should -BeExactly 'split'
            Test-AosOllamaGpu -PsText $ps -Tag 'c:1' | Should -BeExactly 'absent'
        }
    }

    It 'pulls only the configured models that are missing, checks the GPU and writes the local state file' {
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'ollama pull qwen3.5:4b' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -eq 'ollama pull openbmb/minicpm5-2b:q8_0' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'entirely on the GPU' }
        $state = Get-Content -Raw (Join-Path $stateDir 'local.json') | ConvertFrom-Json
        $state.default | Should -BeExactly 'openbmb/minicpm5-2b:q8_0'
        $state.ollama_url | Should -BeExactly 'http://127.0.0.1:11434'
        $state.min_tokens_per_s | Should -Be 15
        Should -Invoke Install-AosNarTools -ModuleName aos -Times 1 -Exactly
    }

    It 'warns when the default model does not fit the GPU' {
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME ID SIZE PROCESSOR`nopenbmb/minicpm5-2b:q8_0 abc 7.9 GB 35%/65% CPU/GPU 4096 now" }
        } -ParameterFilter { $CommandLine -eq 'ollama ps' }
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'partly on the CPU' }
    }

    It 'pulls, runs and writes nothing in DryRun' {
        InModuleScope aos { Install-AosLocal -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama pull *' -or $CommandLine -like 'ollama run *' }
        Test-Path -LiteralPath (Join-Path $stateDir 'local.json') | Should -BeFalse
        Should -Invoke Install-AosWingetPackage -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Id -eq 'Ollama.Ollama' -and $DryRun }
    }

    It 'warns and runs nothing when ollama is not on PATH' {
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

- [ ] **Step 2: Run the tests, see them fail**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1`
Expected: the 7 new tests FAIL (functions not found); the existing 124 pass.

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

`packages.json`, after the `base` list:

```json
  "local": [
    { "id": "Ollama.Ollama",              "why": "local model runtime (CUDA on the GTX 1660 Ti); models live in ~\\.ollama" }
  ],
```

`aos.psm1`: `$script:Layers = @('base', 'engines', 'brain', 'bridges', 'refs', 'local')`; in `Install-AosLayer`'s switch add `'local'   { Install-AosLocal -DryRun:$DryRun }`; in `Show-AosHelp` the install line lists `base | engines | brain | bridges | refs | local | all`; add after `Get-AosProjectsDir`:

```powershell
function Get-AosLocalConfigPath { return (Join-Path $script:Root 'config\local.json') }

function Get-AosLocalConfig {
    $path = Get-AosLocalConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Read-AosJson $path
}

function Get-AosStateDir { return (Join-Path $HOME '.aos') }

function Get-AosOllamaName([string]$Tag) {
    # Ollama shows a bare name with :latest.
    if ($Tag -notmatch ':') { return "${Tag}:latest" }
    return $Tag
}

function Test-AosOllamaModel([string]$List, [string]$Tag) {
    $want = Get-AosOllamaName $Tag
    foreach ($line in ($List -split "`r?`n")) {
        if ((($line.Trim() -split '\s+')[0]) -ieq $want) { return $true }
    }
    return $false
}

function Test-AosOllamaGpu([string]$PsText, [string]$Tag) {
    # `ollama ps` PROCESSOR column: "100% GPU" when the model fits the GPU, "35%/65% CPU/GPU" when split.
    $want = Get-AosOllamaName $Tag
    foreach ($line in ($PsText -split "`r?`n")) {
        if ((($line.Trim() -split '\s+')[0]) -ieq $want) {
            if ($line -match '\b100% GPU\b') { return 'gpu' }
            return 'split'
        }
    }
    return 'absent'
}

function Sync-AosLocalState([switch]$DryRun) {
    # ~\.aos\local.json tells nar the local default, the Ollama URL and the speed floor. Compared by
    # value, not text: Windows PowerShell 5.1 and PowerShell 7 format JSON differently.
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { return }
    $target = Join-Path (Get-AosStateDir) 'local.json'
    $want = [ordered]@{ default = $cfg['default']; ollama_url = $cfg['ollama_url']; min_tokens_per_s = $cfg['min_tokens_per_s'] }
    $have = Read-AosJson $target
    $same = [bool]$have
    if ($have) { foreach ($k in @($want.Keys)) { if ([string]$have[$k] -ne [string]$want[$k]) { $same = $false } } }
    if ($same) { Write-AosOk "$target up to date"; return }
    if ($DryRun) { Write-AosDry "would write $target"; return }
    Write-AosText -Path $target -Text ((ConvertTo-Json -InputObject $want -Depth 5) + "`n")
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
    $default = [string]$cfg['default']
    if (-not $DryRun -and (Test-AosOllamaModel -List (Invoke-AosCapture 'ollama list').Text -Tag $default)) {
        $null = Invoke-AosCapture "ollama run $default `"Reply with OK`""   # load it once, then ask where it runs
        switch (Test-AosOllamaGpu -PsText (Invoke-AosCapture 'ollama ps').Text -Tag $default) {
            'gpu'   { Write-AosOk "$default runs entirely on the GPU" }
            'split' { Write-AosWarn "$default does not fit the GPU and runs partly on the CPU (slower)" }
            default { Write-AosWarn "$default did not load (see ollama ps)" }
        }
    }
    Sync-AosLocalState -DryRun:$DryRun
    Install-AosNarTools -DryRun:$DryRun
}
```

`Get-AosStatus`, after the Tools section:

```powershell
    $local = Get-AosLocalConfig
    if ($local) {
        Write-AosStep 'Local models'
        if (-not (Test-AosCommand ollama)) { Write-AosWarn 'ollama missing (aos install local)' }
        else {
            $r = Invoke-AosCapture 'ollama list'
            if ($r.Code -ne 0) { Write-AosWarn 'ollama is installed but not running (start the Ollama app)' }
            elseif (-not (Test-AosOllamaModel -List $r.Text -Tag $local['default'])) { Write-AosWarn "default model $($local['default']) not pulled (aos install local)" }
            else {
                switch (Test-AosOllamaGpu -PsText (Invoke-AosCapture 'ollama ps').Text -Tag $local['default']) {
                    'gpu'   { Write-AosOk "default model $($local['default']) (loaded, 100% GPU)" }
                    'split' { Write-AosWarn "default model $($local['default']) is loaded split across CPU and GPU" }
                    default { Write-AosOk "default model $($local['default']) (not loaded right now)" }
                }
            }
        }
    }
```

`bootstrap.ps1`: `[ValidateSet('all','base','engines','brain','bridges','refs','local')]`.

- [ ] **Step 4: Run the tests, see them pass**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module .\aos.psm1 -Force -DisableNameChecking; aos test; exit $LASTEXITCODE"`
Expected: static checks ok; all tests pass in both shells.

- [ ] **Step 5: Commit**

```bash
git add config/local.json packages.json aos.psm1 bootstrap.ps1 tests/aos.Tests.ps1
git commit -m "aos: local layer (Ollama, models from config/local.json, GPU check, ~/.aos/local.json)"
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

- [ ] **Step 2: Run, see them fail** (`tests\Run-Tests.ps1`; 2 new FAIL)

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

- [ ] **Step 5: Commit** (`git add aos.psm1 tests/aos.Tests.ps1; git commit -m "aos: generate the Codex local profile from config/local.json"`)

---

### Task 3: nar-tools repository scaffold

**Files:**
- Create (via `aos new nar-tools`): `Desktop\1-Projects\nar-tools\{AGENTS.md,CLAUDE.md,.gitignore,.gitattributes}` and git init
- Create: `pyproject.toml`, `src/nar_tools/__init__.py`, `tests/test_smoke.py`, `.github/workflows/ci.yml`
- Modify: `AGENTS.md` (fill the template)

**Interfaces:**
- Produces: package `nar_tools` with `__version__`; console scripts `nar` (`nar_tools.cli:main`) and `nar-mcp` (`nar_tools.server:main`), implemented in Tasks 10-11.

- [ ] **Step 1: Create the project** - `aos new nar-tools` (expect `created AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.gitattributes`, `git init` in `Desktop\1-Projects\nar-tools`).

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

`tests/conftest.py`:

```python
import pytest


@pytest.fixture(autouse=True)
def isolated_state(tmp_path, monkeypatch):
    """No test reads or writes the user's real ~/.aos: local state and NAR_HOME point into tmp_path."""
    monkeypatch.setenv("AOS_LOCAL_STATE", str(tmp_path / "aos-local.json"))
    monkeypatch.setenv("NAR_HOME", str(tmp_path / "nar-home"))
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
local model (Ollama); a learning loop that refits calibration per model and task type from outcome
feedback and promotes a new calibrator only if it is no worse on held-out calls; and `nar eval`, the
bake-off that gates local model upgrades. Design: agentic-os
`docs/superpowers/specs/2026-09-28-local-stack-design.md`.

## Commands

Keep the dev venv out of OneDrive and never let uv download a Python into AppData (once per shell):
`$env:UV_PROJECT_ENVIRONMENT = "$HOME\.aos\venvs\nar-tools-dev"; $env:UV_PYTHON_DOWNLOADS = "never"`

- Install: `uv sync`
- Test: `uv run pytest -q`
- Server (stdio): `uv run nar-mcp`
- CLI: `uv run nar status`, `uv run nar eval --models a,b`, `uv run nar fit --task-type general`

## Done means

- `uv run pytest -q` passes. Unit tests never call a live Ollama (fakes or `httpx.MockTransport`).

## Conventions

- Python 3.13, standard library first; runtime dependencies only `mcp` and `httpx`.
- Data lives in `NAR_HOME` (default `~\.aos\nar`), never in the repo or OneDrive.
- Calibration is per model and task type. Cross-process locks are OS file locks (`store.file_lock`).
- The promotion rule in `gate.py` is the product: a candidate replaces the current calibrator only if
  Brier score and ECE on the held-out calls are both no worse.

## Risky areas (get a second opinion from the other vendor before changing)

- `gate.py` and `calibration.py` (the non-regressive rule); `store.py` locking and appends.
```

- [ ] **Step 4: Run it**

Run: `$env:UV_PROJECT_ENVIRONMENT = "$HOME\.aos\venvs\nar-tools-dev"; $env:UV_PYTHON_DOWNLOADS = "never"; uv sync; uv run pytest -q`
Expected: `1 passed`; `uv.lock` created; `uv sync` used the system Python 3.13 (no download).

- [ ] **Step 5: Commit** (`git add -A; git commit -m "nar-tools: project scaffold, uv, CI"`)

---

### Task 4: Ollama client

**Files:**
- Create: `src/nar_tools/ollama.py`
- Test: `tests/test_ollama.py`

**Interfaces:**
- Produces: `class OllamaUnavailable(RuntimeError)`; `@dataclass(frozen=True) TokenLogprob(token: str, logprob: float)`; `@dataclass(frozen=True) FirstToken(token: str, logprob: float, top: tuple[TokenLogprob, ...])`; `local_state(path: Path | None = None) -> dict`; `class OllamaClient(base_url=None, timeout=120.0, transport=None)` with `first_token(model: str, messages: list[dict], top: int = 20) -> FirstToken`, `chat(model, messages, tools=None, num_predict=None) -> dict`, `loaded_models() -> list[dict]`, `unload(model) -> None`.

- [ ] **Step 1: Write the failing tests** `tests/test_ollama.py`

```python
import json

import httpx
import pytest

from nar_tools.ollama import FirstToken, OllamaClient, OllamaUnavailable, TokenLogprob, local_state


def client_with(handler):
    return OllamaClient(base_url="http://ollama.test", transport=httpx.MockTransport(handler))


def test_first_token_keeps_the_generated_token_and_the_alternatives():
    seen = {}

    def handler(request):
        seen.update(json.loads(request.content))
        return httpx.Response(200, json={
            "message": {"role": "assistant", "content": "B"},
            "logprobs": [{"token": "B", "logprob": -0.1,
                          "top_logprobs": [{"token": "B", "logprob": -0.1}, {"token": "A", "logprob": -2.5}]}]})

    first = client_with(handler).first_token("m", [{"role": "user", "content": "q"}])
    assert first == FirstToken("B", -0.1, (TokenLogprob("B", -0.1), TokenLogprob("A", -2.5)))
    assert seen["options"]["num_predict"] == 1 and seen["options"]["temperature"] == 0
    assert seen["logprobs"] is True and seen["top_logprobs"] == 20
    assert seen["think"] is False and seen["stream"] is False


def test_unreachable_ollama_raises_unavailable():
    def handler(request):
        raise httpx.ConnectError("refused", request=request)

    with pytest.raises(OllamaUnavailable, match="cannot reach Ollama"):
        client_with(handler).first_token("m", [])


def test_missing_logprobs_explains_the_version_floor():
    def handler(request):
        return httpx.Response(200, json={"message": {"content": "B"}})

    with pytest.raises(OllamaUnavailable, match="0.12.11"):
        client_with(handler).first_token("m", [])


def test_retries_without_think_when_the_model_rejects_it():
    bodies = []

    def handler(request):
        body = json.loads(request.content)
        bodies.append(body)
        if "think" in body:
            return httpx.Response(400, json={"error": "\"m\" does not support thinking"})
        return httpx.Response(200, json={"logprobs": [{"token": "A", "logprob": -0.2,
                                                       "top_logprobs": [{"token": "A", "logprob": -0.2}]}]})

    assert client_with(handler).first_token("m", []).token == "A"
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

- [ ] **Step 2: Run, see them fail** (`uv run pytest tests/test_ollama.py -q` -> `ModuleNotFoundError`)

- [ ] **Step 3: Implement** `src/nar_tools/ollama.py`

```python
"""Minimal Ollama client: the first generated token with its alternatives, chat with tools, loaded models."""
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


@dataclass(frozen=True)
class FirstToken:
    """The token the model actually generated first, and the most likely alternatives at that position."""
    token: str
    logprob: float
    top: tuple[TokenLogprob, ...]


def local_state(path: Path | None = None) -> dict:
    """~/.aos/local.json, written by `aos install local` and `aos sync`: default model, URL, speed floor."""
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

    def first_token(self, model: str, messages: list[dict], top: int = 20) -> FirstToken:
        """One forward pass: the generated first token of the reply and its top alternatives."""
        body = {"model": model, "messages": messages, "stream": False, "think": False,
                "logprobs": True, "top_logprobs": top,
                "options": {"num_predict": 1, "temperature": 0, "seed": 0}}
        entries = self._chat(body).get("logprobs") or []
        if not entries:
            raise OllamaUnavailable(f"{model} returned no logprobs (needs Ollama 0.12.11 or newer)")
        e = entries[0]
        alternatives = tuple(TokenLogprob(str(t["token"]), float(t["logprob"])) for t in e.get("top_logprobs") or [])
        return FirstToken(str(e.get("token", "")), float(e.get("logprob", 0.0)), alternatives)

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

- [ ] **Step 4: Run, see them pass** (6 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: Ollama client (first token with alternatives)"`)

---

### Task 5: Single-pass letter scoring

**Files:**
- Create: `src/nar_tools/scoring.py`
- Test: `tests/test_scoring.py`

**Interfaces:**
- Consumes: `FirstToken`, `TokenLogprob` (Task 4).
- Produces: `LETTERS = "ABCDEFGHIJKLMNOPQRST"`, `MAX_OPTIONS = 20`, `build_messages(question: str, options: list[str]) -> list[dict]`, `letter_logprobs(first: FirstToken, n_options: int) -> tuple[list[float], bool]`.

- [ ] **Step 1: Write the failing tests** `tests/test_scoring.py`

```python
import math

import pytest

from nar_tools.ollama import FirstToken, TokenLogprob
from nar_tools.scoring import LETTERS, build_messages, letter_logprobs


def first(token, *alternatives):
    top = tuple(TokenLogprob(t, lp) for t, lp in alternatives)
    return FirstToken(token, top[0].logprob if top else -0.1, top)


def test_build_messages_letters_each_option():
    msgs = build_messages("Pick one", ["red", "green"])
    user = msgs[-1]["content"]
    assert "A. red" in user and "B. green" in user
    assert msgs[0]["role"] == "system" and "one capital letter" in msgs[0]["content"]


def test_variants_of_a_letter_add_up():
    lps, signal = letter_logprobs(first("A", ("A", math.log(0.5)), (" A", math.log(0.2)), ("B", math.log(0.3))), 2)
    assert signal is True
    assert math.isclose(math.exp(lps[0]), 0.7, rel_tol=1e-9)
    assert math.isclose(math.exp(lps[1]), 0.3, rel_tol=1e-9)


def test_decorated_letters_count_and_lowercase_does_not():
    lps, _ = letter_logprobs(first("**C", ("**C", math.log(0.4)), ("(B", math.log(0.3)), ("a", math.log(0.2))), 3)
    assert math.isclose(math.exp(lps[2]), 0.4) and math.isclose(math.exp(lps[1]), 0.3)
    assert lps[0] < math.log(0.2)          # "a" is not option A: A only gets the floor


def test_a_generated_non_letter_means_no_signal_even_with_letter_alternatives():
    lps, signal = letter_logprobs(first("<think>", ("<think>", -0.01), ("A", -8.0), ("B", -9.0)), 4)
    assert signal is False and lps == [0.0, 0.0, 0.0, 0.0]


def test_a_generated_letter_outside_the_options_means_no_signal():
    lps, signal = letter_logprobs(first("C", ("C", -0.1), ("A", -3.0)), 2)
    assert signal is False and lps == [0.0, 0.0]


def test_missing_letters_get_a_floor_below_every_alternative():
    lps, signal = letter_logprobs(first("B", ("B", -0.2), ("The", -3.2)), 3)
    assert signal is True and lps[1] == -0.2
    assert lps[0] == lps[2] == -3.2 - math.log(2.0)


@pytest.mark.parametrize("n", [0, 1, len(LETTERS) + 1])
def test_option_count_limits(n):
    with pytest.raises(ValueError):
        letter_logprobs(first("A", ("A", -0.1)), n)
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/scoring.py`

```python
"""Single-pass option scoring: the next-token distribution over option letters."""
from __future__ import annotations

import math

from nar_tools.ollama import FirstToken, TokenLogprob

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


def letter_logprobs(first: FirstToken, n_options: int) -> tuple[list[float], bool]:
    """Log-probability of each option's letter as the first token, and whether the answer was a letter.

    If the token the model actually generated is not one of the option letters (it began thinking,
    wrote prose, or named a letter outside the options) there is no signal: every option gets the same
    score, however the alternatives look. Otherwise "A", " A", "**A" and "(A" all count for A (their
    probabilities add up), lowercase does not, and a letter missing from the alternatives gets a floor
    below the least likely alternative.
    """
    if not 2 <= n_options <= MAX_OPTIONS:
        raise ValueError(f"need 2 to {MAX_OPTIONS} options, got {n_options}")
    valid = LETTERS[:n_options]
    chosen = first.token.strip(_STRIP)
    if not (len(chosen) == 1 and chosen in valid):
        return [0.0] * n_options, False
    candidates = list(first.top) or [TokenLogprob(first.token, first.logprob)]
    found: dict[int, float] = {}
    for t in candidates:
        key = t.token.strip(_STRIP)
        if len(key) == 1 and key in valid:
            i = valid.index(key)
            found[i] = _logaddexp(found[i], t.logprob) if i in found else t.logprob
    floor = min(t.logprob for t in candidates) - math.log(2.0)
    return [found.get(i, floor) for i in range(n_options)], True
```

- [ ] **Step 4: Run, see them pass** (10 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: letter scoring that trusts only a generated letter"`)

---

### Task 6: Calibration

**Files:**
- Create: `src/nar_tools/calibration.py`
- Test: `tests/test_calibration.py`

**Interfaces:**
- Produces: `@dataclass(frozen=True) Sample(logprobs: tuple[float, ...], outcome: int)`, `softmax(xs)`, `log_softmax(xs)`, `calibrate(logprobs, temperature) -> list[float]`, `nll(samples, temperature) -> float`, `fit_temperature(samples, lo=0.05, hi=20.0, iterations=100) -> float`, `brier(samples, temperature) -> float`, `ece(samples, temperature, bins=10) -> float`.

- [ ] **Step 1: Write the failing tests** `tests/test_calibration.py`

```python
import math

import pytest

from nar_tools.calibration import Sample, brier, calibrate, ece, fit_temperature, nll


def samples(raw, right_a, right_b):
    return [Sample(raw, 0)] * right_a + [Sample(raw, 1)] * right_b


def test_temperature_one_is_the_raw_distribution():
    p = calibrate([math.log(0.8), math.log(0.2)], 1.0)
    assert math.isclose(p[0], 0.8) and math.isclose(p[1], 0.2)


def test_high_temperature_flattens_and_low_sharpens():
    assert calibrate([0.0, -3.0], 100.0)[0] < 0.51
    assert calibrate([0.0, -3.0], 0.1)[0] > 0.999


def test_fit_recovers_the_right_temperature():
    # Says 95% A (log-odds 3); A is right 73 of 100: 1 / (1 + e^(-3/T)) = 0.73 -> T = 3 / ln(73/27)
    assert math.isclose(fit_temperature(samples((0.0, -3.0), 73, 27)), 3 / math.log(73 / 27), rel_tol=1e-3)


def test_fit_is_right_for_very_confident_scores_too():
    # Regression: with log-odds 10, clipped probabilities made the search run to T = 0.05.
    assert math.isclose(fit_temperature(samples((0.0, -10.0), 73, 27)), 10 / math.log(73 / 27), rel_tol=1e-3)


def test_fitted_temperature_lowers_nll_brier_and_ece():
    s = samples((0.0, -3.0), 73, 27)
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


def log_softmax(xs) -> list[float]:
    m = max(xs)
    lse = m + math.log(sum(math.exp(x - m) for x in xs))
    return [x - lse for x in xs]


def calibrate(logprobs, temperature: float) -> list[float]:
    if temperature <= 0:
        raise ValueError("temperature must be positive")
    return softmax([lp / temperature for lp in logprobs])


def nll(samples, temperature: float) -> float:
    """Mean negative log-likelihood, computed in log space: no clipping, so it stays convex in 1/T."""
    if temperature <= 0:
        raise ValueError("temperature must be positive")
    return -sum(log_softmax([lp / temperature for lp in s.logprobs])[s.outcome] for s in samples) / len(samples)


def fit_temperature(samples, lo: float = 0.05, hi: float = 20.0, iterations: int = 100) -> float:
    """The temperature with the lowest negative log-likelihood (golden-section search over 1/T)."""
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

- [ ] **Step 4: Run, see them pass** (7 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: temperature scaling in log space, Brier and ECE"`)

---

### Task 7: Storage, per-model calibrators and OS locks

**Files:**
- Create: `src/nar_tools/store.py`
- Test: `tests/test_store.py`

**Interfaces:**
- Produces: `nar_home() -> Path`, `check_task_type(task_type) -> str` (ValueError unless `^[a-z0-9][a-z0-9_-]{0,39}$`), `model_slug(model) -> str`, `file_lock(path: Path, timeout: float)` (context manager; `TimeoutError`), `IDENTITY = {"version": 0, "temperature": 1.0}`, `class NarStore(root=None)` with `log_call(record)`, `log_feedback(record)`, `log_promotion(record)`, `calls()`, `feedback()`, `promotions()`, `find_call(call_id) -> dict | None`, `labelled(model, task_type) -> list[tuple[str, list[float], int]]`, `feedback_count(model, task_type) -> int`, `current(model, task_type) -> dict`, `promote(model, task_type, calibrator) -> dict` (call under `lock()`), `lock(timeout=10.0)`. Call records carry `model` and `task_type`.

- [ ] **Step 1: Write the failing tests** `tests/test_store.py`

```python
import json
import multiprocessing
import os
import time

import pytest

from nar_tools.store import NarStore, check_task_type, model_slug


def call(cid, model="m", task_type="general", raw=(0.0, -1.0)):
    return {"call_id": cid, "model": model, "task_type": task_type, "raw_logprobs": list(raw), "options": ["x", "y"]}


def _hold_lock(root, seconds, ready):
    with NarStore(root).lock(timeout=5):
        ready.set()
        time.sleep(seconds)


def _die_holding_lock(root, ready):
    NarStore(root).lock(timeout=5).__enter__()
    ready.set()
    time.sleep(0.5)
    os._exit(1)        # a crash: the lock is never released by our code


def _append_many(root, worker, n):
    s = NarStore(root)
    for i in range(n):
        s.log_call({**call(f"{worker}-{i}"), "pad": "x" * 500})


def test_append_and_read_round_trip(tmp_path):
    s = NarStore(tmp_path)
    s.log_call(call("c1", raw=(-0.1, -2.0)))
    s.log_feedback({"call_id": "c1", "outcome": 1})
    assert s.find_call("c1")["options"] == ["x", "y"]
    assert s.labelled("m", "general") == [("c1", [-0.1, -2.0], 1)]


def test_calls_are_partitioned_by_model_and_type_and_latest_feedback_wins(tmp_path):
    s = NarStore(tmp_path)
    s.log_call(call("c1"))
    s.log_call(call("c2", task_type="triage"))
    s.log_call(call("c3", model="other"))
    for cid, o in (("c1", 0), ("c1", 1), ("c2", 0), ("c3", 0)):
        s.log_feedback({"call_id": cid, "outcome": o})
    assert s.labelled("m", "general") == [("c1", [0.0, -1.0], 1)]
    assert s.feedback_count("m", "general") == 2
    assert s.labelled("other", "general") == [("c3", [0.0, -1.0], 0)]


def test_a_torn_line_never_swallows_the_next_record(tmp_path):
    s = NarStore(tmp_path)
    s.log_call(call("c1"))
    with open(tmp_path / "calls.jsonl", "ab") as f:
        f.write(b'{"call_id": "torn", "task_')          # a crash mid-write, no newline
    s.log_call(call("c2"))
    assert [c["call_id"] for c in s.calls()] == ["c1", "c2"]


def test_bad_bytes_do_not_break_reading(tmp_path):
    s = NarStore(tmp_path)
    s.log_call(call("c1"))
    with open(tmp_path / "calls.jsonl", "ab") as f:
        f.write(b'\xff\xfe not json\n')
    s.log_call(call("c2"))
    assert [c["call_id"] for c in s.calls()] == ["c1", "c2"]


def test_calibrators_start_at_identity_and_are_kept_per_model(tmp_path):
    s = NarStore(tmp_path)
    assert s.current("m", "general") == {"version": 0, "temperature": 1.0}
    with s.lock():
        s.promote("m", "general", {"temperature": 2.0})
    assert s.current("m", "general")["temperature"] == 2.0
    assert s.current("other", "general") == {"version": 0, "temperature": 1.0}
    assert (tmp_path / "calibrators" / "m" / "general" / "v1.json").exists()


def test_rollback_then_promote_never_overwrites_history(tmp_path):
    s = NarStore(tmp_path)
    with s.lock():
        s.promote("m", "general", {"temperature": 2.0})
        s.promote("m", "general", {"temperature": 3.0})
    (tmp_path / "current.json").write_text(json.dumps({"m/general": 1}), encoding="utf-8")   # roll back to v1
    v2 = (tmp_path / "calibrators" / "m" / "general" / "v2.json").read_text(encoding="utf-8")
    with s.lock():
        record = s.promote("m", "general", {"temperature": 4.0})
    assert record["version"] == 3
    assert (tmp_path / "calibrators" / "m" / "general" / "v2.json").read_text(encoding="utf-8") == v2


def test_lock_excludes_a_second_holder_in_this_process(tmp_path):
    s = NarStore(tmp_path)
    with s.lock():
        with pytest.raises(TimeoutError):
            with s.lock(timeout=0.1):
                pass
    with s.lock(timeout=0.1):
        pass


def test_a_live_holder_is_never_evicted_and_a_dead_one_is_released(tmp_path):
    ctx = multiprocessing.get_context("spawn")
    ready = ctx.Event()
    holder = ctx.Process(target=_hold_lock, args=(str(tmp_path), 3.0, ready))
    holder.start()
    assert ready.wait(30)
    with pytest.raises(TimeoutError):
        with NarStore(tmp_path).lock(timeout=0.5):
            pass
    holder.join(30)
    with NarStore(tmp_path).lock(timeout=2):
        pass
    ready = ctx.Event()
    crasher = ctx.Process(target=_die_holding_lock, args=(str(tmp_path), ready))
    crasher.start()
    assert ready.wait(30)
    crasher.join(30)
    with NarStore(tmp_path).lock(timeout=2):     # the OS released the dead holder's lock
        pass


def test_concurrent_writers_keep_every_line(tmp_path):
    ctx = multiprocessing.get_context("spawn")
    workers = [ctx.Process(target=_append_many, args=(str(tmp_path), w, 50)) for w in range(4)]
    for w in workers:
        w.start()
    for w in workers:
        w.join(60)
    assert len(NarStore(tmp_path).calls()) == 200


@pytest.mark.parametrize("bad", ["", "General", "../x", "a b", "x" * 41])
def test_task_type_is_a_safe_name(bad):
    with pytest.raises(ValueError):
        check_task_type(bad)


def test_model_slug_is_a_safe_folder_name():
    assert model_slug("openbmb/minicpm5-2b:q8_0") == "openbmb_minicpm5-2b_q8_0"
    with pytest.raises(ValueError):
        model_slug("::")
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/store.py`

```python
"""Local, append-only storage for nar calls, feedback, calibrators (per model and task type) and decisions."""
from __future__ import annotations

import json
import os
import re
import time
from contextlib import contextmanager
from pathlib import Path

if os.name == "nt":
    import msvcrt
else:
    import fcntl

TASK_TYPE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,39}$")
IDENTITY = {"version": 0, "temperature": 1.0}   # before any promotion: the raw model probabilities


def nar_home() -> Path:
    return Path(os.environ.get("NAR_HOME") or (Path.home() / ".aos" / "nar"))


def check_task_type(task_type) -> str:
    if not isinstance(task_type, str) or not TASK_TYPE.match(task_type):
        raise ValueError("task_type must be 1-40 characters: lowercase letters, digits, '-' or '_'")
    return task_type


def model_slug(model) -> str:
    """A folder-safe form of an Ollama tag: calibration is kept per model."""
    slug = re.sub(r"[^a-z0-9._-]", "_", str(model).lower()).strip("._")
    if not slug:
        raise ValueError("model name is empty")
    return slug


@contextmanager
def file_lock(path: Path, timeout: float):
    """An OS lock on a file: released by the OS if the holder dies, never taken over on a timer."""
    path.parent.mkdir(parents=True, exist_ok=True)
    f = open(path, "a+b")
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                if os.name == "nt":
                    f.seek(0)
                    msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise TimeoutError(f"{path.name} is held by another nar process; try again") from None
                time.sleep(0.05)
        try:
            yield
        finally:
            if os.name == "nt":
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    finally:
        f.close()


def _load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


class NarStore:
    def __init__(self, root: Path | None = None) -> None:
        self.root = Path(root) if root else nar_home()
        self.root.mkdir(parents=True, exist_ok=True)

    # append-only logs ---------------------------------------------------------------
    def _append(self, name: str, record: dict) -> None:
        line = (json.dumps(record, ensure_ascii=False) + "\n").encode("utf-8")
        with file_lock(self.root / "append.lock", timeout=10.0):
            with open(self.root / name, "ab+") as f:
                f.seek(0, os.SEEK_END)
                if f.tell() > 0:
                    f.seek(-1, os.SEEK_END)
                    if f.read(1) != b"\n":
                        f.write(b"\n")   # a crash left half a record: never glue the next one onto it
                f.write(line)

    def _read(self, name: str) -> list[dict]:
        path = self.root / name
        if not path.exists():
            return []
        out = []
        for raw in path.read_bytes().decode("utf-8", errors="replace").splitlines():
            if not raw.strip():
                continue
            try:
                out.append(json.loads(raw))
            except ValueError:
                continue   # a torn or damaged line never breaks the store
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

    def labelled(self, model: str, task_type: str) -> list[tuple[str, list[float], int]]:
        """(call_id, raw log-probabilities, outcome) for this model's calls of this type; latest feedback wins."""
        outcome = {f["call_id"]: f["outcome"] for f in self.feedback() if "call_id" in f and "outcome" in f}
        return [(c["call_id"], c["raw_logprobs"], outcome[c["call_id"]]) for c in self.calls()
                if c.get("model") == model and c.get("task_type") == task_type and c.get("call_id") in outcome]

    def feedback_count(self, model: str, task_type: str) -> int:
        ids = {c.get("call_id") for c in self.calls() if c.get("model") == model and c.get("task_type") == task_type}
        return sum(1 for f in self.feedback() if f.get("call_id") in ids)

    # calibrators --------------------------------------------------------------------
    def _key(self, model: str, task_type: str) -> str:
        return f"{model_slug(model)}/{check_task_type(task_type)}"

    def _folder(self, model: str, task_type: str) -> Path:
        return self.root / "calibrators" / model_slug(model) / check_task_type(task_type)

    def current(self, model: str, task_type: str) -> dict:
        version = _load_json(self.root / "current.json", {}).get(self._key(model, task_type))
        if not version:
            return dict(IDENTITY)
        return _load_json(self._folder(model, task_type) / f"v{version}.json", dict(IDENTITY))

    def promote(self, model: str, task_type: str, calibrator: dict) -> dict:
        """Write a new version (numbers are never reused, even after a rollback) and point
        current.json at it with an atomic replace. Call it while holding lock()."""
        folder = self._folder(model, task_type)
        folder.mkdir(parents=True, exist_ok=True)
        existing = [int(p.stem[1:]) for p in folder.glob("v*.json") if p.stem[1:].isdigit()]
        record = {**calibrator, "model": model, "task_type": task_type, "version": max(existing, default=0) + 1}
        (folder / f"v{record['version']}.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
        pointer = _load_json(self.root / "current.json", {})
        pointer[self._key(model, task_type)] = record["version"]
        tmp = self.root / f"current.json.{os.getpid()}.tmp"
        tmp.write_text(json.dumps(pointer, indent=2), encoding="utf-8")
        os.replace(tmp, self.root / "current.json")
        return record

    def lock(self, timeout: float = 10.0):
        """The refit lock: one refit and promotion at a time, across every nar process."""
        return file_lock(self.root / "refit.lock", timeout)
```

- [ ] **Step 4: Run, see them pass** (14 passed; the multi-process tests take a few seconds)

- [ ] **Step 5: Commit** (`git commit -m "nar: append-only store, per-model calibrators, OS file locks"`)

---

### Task 8: The promotion gate

**Files:**
- Create: `src/nar_tools/gate.py`
- Test: `tests/test_gate.py`

**Interfaces:**
- Consumes: `Sample`, `fit_temperature`, `brier`, `ece` (Task 6); `NarStore` (Task 7).
- Produces: `MIN_TRAIN = 20`, `MIN_HELDOUT = 5`, `REFIT_EVERY = 20`, `LOCK_TIMEOUT = 10.0`, `is_heldout(call_id) -> bool`, `should_promote(cand_brier, cand_ece, cur_brier, cur_ece) -> bool`, `@dataclass Decision(model, task_type, promoted, reason, candidate_temperature=None, candidate_brier=None, candidate_ece=None, current_version=0, current_brier=None, current_ece=None, n_train=0, n_heldout=0)`, `refit(store, model, task_type) -> Decision`.

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


def add(store, call_ids, raw, outcomes, model="m", task_type="general"):
    for cid, o in zip(call_ids, outcomes):
        store.log_call({"call_id": cid, "model": model, "task_type": task_type,
                        "raw_logprobs": list(raw), "options": ["a", "b"]})
        store.log_feedback({"call_id": cid, "outcome": o})


def test_split_is_stable_and_about_one_in_five():
    sample = [uuid.uuid4().hex for _ in range(2000)]
    assert 0.15 < sum(gate.is_heldout(c) for c in sample) / len(sample) < 0.25
    assert [gate.is_heldout(c) for c in sample[:50]] == [gate.is_heldout(c) for c in sample[:50]]


@pytest.mark.parametrize("cand_brier,cand_ece,expected", [
    (0.1, 0.1, True),    # better on both
    (0.2, 0.2, True),    # equal is no worse
    (0.1, 0.3, False),   # calibration error got worse
    (0.3, 0.1, False),   # Brier score got worse
])
def test_should_promote_needs_both_metrics_no_worse(cand_brier, cand_ece, expected):
    assert gate.should_promote(cand_brier, cand_ece, 0.2, 0.2) is expected


def test_too_few_labels_changes_nothing(tmp_path):
    s = NarStore(tmp_path)
    add(s, ids(5, False), (0.0, -3.0), [0] * 5)
    d = gate.refit(s, "m", "general")
    assert d.promoted is False and "not enough" in d.reason
    assert s.current("m", "general")["version"] == 0 and len(s.promotions()) == 1


def test_a_better_calibrator_is_promoted(tmp_path):
    s = NarStore(tmp_path)
    raw = (0.0, -3.0)                       # says 95% A; A is right about 73% of the time everywhere
    add(s, ids(100, False), raw, [0] * 73 + [1] * 27)
    add(s, ids(30, True), raw, [0] * 22 + [1] * 8)
    d = gate.refit(s, "m", "general")
    assert d.promoted is True and s.current("m", "general")["version"] == 1
    assert math.isclose(s.current("m", "general")["temperature"], d.candidate_temperature)


def test_a_worse_calibrator_is_never_promoted(tmp_path):
    s = NarStore(tmp_path)
    raw = (0.0, -3.0)
    add(s, ids(100, False), raw, [0] * 50 + [1] * 50)   # training says: flatten to 50/50
    add(s, ids(30, True), raw, [0] * 30)                # held-out says: the raw 95% was right
    d = gate.refit(s, "m", "general")
    assert d.promoted is False and "worse" in d.reason
    assert s.current("m", "general")["version"] == 0 and s.promotions()[-1]["promoted"] is False


def test_a_refit_never_touches_another_model(tmp_path):
    s = NarStore(tmp_path)
    raw = (0.0, -3.0)
    add(s, ids(100, False), raw, [0] * 73 + [1] * 27, model="a")
    add(s, ids(30, True), raw, [0] * 22 + [1] * 8, model="a")
    assert gate.refit(s, "a", "general").promoted is True
    assert s.current("b", "general") == {"version": 0, "temperature": 1.0}
    assert gate.refit(s, "b", "general").promoted is False


def test_refit_holds_the_lock(tmp_path, monkeypatch):
    s = NarStore(tmp_path)
    monkeypatch.setattr(gate, "LOCK_TIMEOUT", 0.1)
    with s.lock():
        with pytest.raises(TimeoutError):
            gate.refit(s, "m", "general")
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


def should_promote(cand_brier: float, cand_ece: float, cur_brier: float, cur_ece: float) -> bool:
    """No worse on BOTH the held-out Brier score and the held-out calibration error."""
    return cand_brier <= cur_brier and cand_ece <= cur_ece


@dataclass
class Decision:
    model: str
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


def refit(store: NarStore, model: str, task_type: str) -> Decision:
    with store.lock(timeout=LOCK_TIMEOUT):
        rows = store.labelled(model, task_type)
        train = [Sample(tuple(lp), o) for cid, lp, o in rows if not is_heldout(cid)]
        held = [Sample(tuple(lp), o) for cid, lp, o in rows if is_heldout(cid)]
        current = store.current(model, task_type)
        d = Decision(model, task_type, False, "", current_version=current["version"],
                     n_train=len(train), n_heldout=len(held))
        if len(train) < MIN_TRAIN or len(held) < MIN_HELDOUT:
            d.reason = f"not enough labelled calls (train {len(train)}/{MIN_TRAIN}, held-out {len(held)}/{MIN_HELDOUT})"
        else:
            t = fit_temperature(train)
            d.candidate_temperature = t
            d.candidate_brier, d.candidate_ece = brier(held, t), ece(held, t)
            d.current_brier, d.current_ece = brier(held, current["temperature"]), ece(held, current["temperature"])
            if abs(t - current["temperature"]) < 1e-6:
                d.reason = "unchanged"
            elif should_promote(d.candidate_brier, d.candidate_ece, d.current_brier, d.current_ece):
                store.promote(model, task_type, {"temperature": t, "brier": d.candidate_brier, "ece": d.candidate_ece,
                                                 "n_train": len(train), "n_heldout": len(held), "fitted_at": time.time()})
                d.promoted, d.reason = True, "no worse on held-out calls"
            else:
                d.reason = "worse on held-out calls; kept the current calibrator"
        store.log_promotion({"at": time.time(), **asdict(d)})
        return d
```

- [ ] **Step 4: Run, see them pass** (10 passed)

- [ ] **Step 5: Commit** (`git commit -m "nar: the non-regressive promotion gate, per model"`)

---

### Task 9: The service layer

**Files:**
- Create: `src/nar_tools/service.py`
- Test: `tests/test_service.py`

**Interfaces:**
- Consumes: `OllamaClient.first_token`, `local_state` (Task 4); `build_messages`, `letter_logprobs`, `MAX_OPTIONS` (Task 5); `calibrate`, `Sample`, `brier`, `ece` (Task 6); `NarStore`, `check_task_type` (Task 7); `gate.refit`, `gate.is_heldout`, `gate.REFIT_EVERY`, `gate.MIN_HELDOUT` (Task 8).
- Produces: `MAX_ITEMS = 50`; `class NarService(client, store, model=None)` with `choose(question, options, task_type="general") -> dict` (keys `call_id, choice, choice_index, confidence, options[{option, probability}], letter_signal, calibrator_version, model`), `classify(items, labels, task_type="general") -> {"results": [...]}`, `feedback(call_id, outcome) -> {"recorded", "call_id", "outcome", "refit"}`, `status() -> {"model", "store", "calibration": {model: {task_type: {calls, labelled, calibrator, reliability}}}, "last_decision"}`. Every input error is a `ValueError`.

- [ ] **Step 1: Write the failing tests** `tests/test_service.py`

```python
import math

import pytest

from nar_tools import gate
from nar_tools.ollama import FirstToken, TokenLogprob
from nar_tools.service import NarService
from nar_tools.store import NarStore


class FakeClient:
    def __init__(self):
        top = (TokenLogprob("B", math.log(0.6)), TokenLogprob("A", math.log(0.3)), TokenLogprob("C", math.log(0.1)))
        self.first = FirstToken("B", math.log(0.6), top)
        self.calls = 0

    def first_token(self, model, messages, top=20):
        self.calls += 1
        return self.first


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


def test_choose_uses_this_models_calibrator(tmp_path):
    svc = make(tmp_path)
    with svc.store.lock():
        svc.store.promote("test-model", "general", {"temperature": 50.0})
        svc.store.promote("other-model", "general", {"temperature": 0.05})
    r = svc.choose("Which?", ["x", "y", "z"])
    assert r["calibrator_version"] == 1 and r["confidence"] < 0.35     # T=50 flattens; T=0.05 was not used


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


def test_every_twentieth_outcome_triggers_a_refit_for_that_model(tmp_path, monkeypatch):
    seen = []
    monkeypatch.setattr(gate, "refit", lambda store, m, t: seen.append((m, t)) or gate.Decision(m, t, False, "stub"))
    svc = make(tmp_path)
    for i in range(40):
        cid = svc.choose("Which?", ["x", "y"])["call_id"]
        r = svc.feedback(cid, 0)
        assert (r["refit"] is not None) == ((i + 1) % 20 == 0)
    assert seen == [("test-model", "general")] * 2


def test_classify_scores_each_item(tmp_path):
    svc = make(tmp_path)
    out = svc.classify(["i1", "i2"], ["bug", "feature", "question"])
    assert len(out["results"]) == 2 and svc.client.calls == 2
    with pytest.raises(ValueError):
        svc.classify([], ["a", "b"])
    with pytest.raises(ValueError):
        svc.classify(["x"] * 51, ["a", "b"])


def test_status_counts_calls_labels_and_reliability(tmp_path):
    svc = make(tmp_path)
    cid = svc.choose("Which?", ["x", "y"])["call_id"]
    svc.choose("Which?", ["x", "y"], task_type="triage")
    svc.feedback(cid, 1)
    general = svc.status()["calibration"]["test-model"]["general"]
    assert general["calls"] == 1 and general["labelled"] == 1
    assert general["calibrator"] == {"version": 0, "temperature": 1.0}
    assert general["reliability"] is None               # fewer than MIN_HELDOUT held-out outcomes
    assert svc.status()["calibration"]["test-model"]["triage"]["labelled"] == 0
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
from nar_tools.calibration import Sample, brier, calibrate, ece
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
        raw, signal = letter_logprobs(self.client.first_token(self.model, build_messages(str(question), opts)), len(opts))
        cal = self.store.current(self.model, task_type)
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
        if self.store.feedback_count(call["model"], call["task_type"]) % gate.REFIT_EVERY == 0:
            result["refit"] = asdict(gate.refit(self.store, call["model"], call["task_type"]))
        return result

    def _reliability(self, model: str, task_type: str, temperature: float) -> dict | None:
        held = [Sample(tuple(lp), o) for cid, lp, o in self.store.labelled(model, task_type) if gate.is_heldout(cid)]
        if len(held) < gate.MIN_HELDOUT:
            return None
        return {"brier": round(brier(held, temperature), 4), "ece": round(ece(held, temperature), 4), "n_heldout": len(held)}

    def status(self) -> dict:
        calls = self.store.calls()
        labelled_ids = {f.get("call_id") for f in self.store.feedback()}
        calibration: dict = {}
        for model, task_type in sorted({(c.get("model"), c.get("task_type")) for c in calls if c.get("model")}):
            of_kind = [c for c in calls if c.get("model") == model and c.get("task_type") == task_type]
            current = self.store.current(model, task_type)
            calibration.setdefault(model, {})[task_type] = {
                "calls": len(of_kind),
                "labelled": sum(1 for c in of_kind if c.get("call_id") in labelled_ids),
                "calibrator": current,
                "reliability": self._reliability(model, task_type, current["temperature"])}
        decisions = self.store.promotions()
        return {"model": self.model, "store": str(self.store.root), "calibration": calibration,
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
- Produces: FastMCP app `mcp` named `nar` with tools `nar_choose`, `nar_classify`, `nar_feedback` (`outcome` strictly an integer or a string; booleans rejected), `nar_status`; `get_service()`; `main()` (stdio). Results: the service's dict, or `{"unavailable": True, "reason"}` / `{"error"}`.

- [ ] **Step 1: Write the failing tests** `tests/test_server.py`

```python
import asyncio

import pytest
from mcp.server.fastmcp.exceptions import ToolError

from nar_tools import server
from nar_tools.ollama import OllamaUnavailable


class Down:
    def choose(self, *args):
        raise OllamaUnavailable("cannot reach Ollama at http://127.0.0.1:11434 (ConnectError)")

    def classify(self, *args):
        raise ValueError("give a list of 1 to 50 items")


class Recorder:
    def __init__(self):
        self.args = None

    def feedback(self, call_id, outcome):
        self.args = (call_id, outcome)
        return {"recorded": True}


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


def test_feedback_takes_an_index_or_text_through_mcp(monkeypatch):
    rec = Recorder()
    monkeypatch.setattr(server, "get_service", lambda: rec)
    asyncio.run(server.mcp.call_tool("nar_feedback", {"call_id": "c1", "outcome": 1}))
    assert rec.args == ("c1", 1)
    asyncio.run(server.mcp.call_tool("nar_feedback", {"call_id": "c1", "outcome": "yes"}))
    assert rec.args == ("c1", "yes")


def test_feedback_rejects_a_boolean_through_mcp(monkeypatch):
    rec = Recorder()
    monkeypatch.setattr(server, "get_service", lambda: rec)
    with pytest.raises(ToolError):
        asyncio.run(server.mcp.call_tool("nar_feedback", {"call_id": "c1", "outcome": True}))
    assert rec.args is None
```

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** `src/nar_tools/server.py`

```python
"""The `nar` MCP server (stdio): calibrated single-pass option scoring with the local model."""
from __future__ import annotations

from typing import Annotated

from mcp.server.fastmcp import FastMCP
from pydantic import Strict

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
def nar_feedback(call_id: str, outcome: Annotated[int, Strict()] | Annotated[str, Strict()]) -> dict:
    """Record which option was actually right for an earlier nar_choose or nar_classify result: the
    option's 0-based index or its exact text. Every 20 outcomes per model and task type, nar refits its
    calibration and keeps the new one only if it is no worse on held-out calls."""
    return _safe(lambda: get_service().feedback(call_id, outcome))


@mcp.tool()
def nar_status() -> dict:
    """The local model in use; calls, outcomes, calibrator and held-out reliability per model and task
    type; and the last refit decision."""
    return _safe(lambda: get_service().status())


def main() -> None:
    mcp.run()   # stdio
```

- [ ] **Step 4: Run, see them pass** (5 passed; full suite green)

- [ ] **Step 5: Commit** (`git commit -m "nar: FastMCP stdio server with four tools"`)

---

### Task 11: The bake-off and the `nar` CLI

**Files:**
- Create: `src/nar_tools/evals/choose.jsonl`, `src/nar_tools/evals/tools.jsonl`, `src/nar_tools/evals/toolset.json`, `src/nar_tools/evaluate.py`, `src/nar_tools/cli.py`
- Test: `tests/test_evaluate.py`, `tests/test_cli.py`

**Interfaces:**
- Consumes: Tasks 4-9.
- Produces: `load_jsonl(name)`, `load_toolset()`, `@dataclass ModelResult(model, tool_success=0.0, choose_accuracy=0.0, choose_ece=1.0, tokens_per_s=0.0, fully_on_gpu=False, temperature=1.0, errors=[])`, `evaluate(client, model, temperature=1.0) -> ModelResult`, `verdict(candidate, baseline, min_tps) -> {"passes", "reasons"}`, `run(models, client=None, baseline_model=None, out_dir=None, store=None) -> dict` (writes `<NAR_HOME>/eval/<stamp>.json` and `latest.json`: `created_at, machine, baseline, min_tokens_per_s, models, verdicts`); `cli.main(argv=None) -> int` with `eval --models a,b [--baseline t]`, `fit [--model m] [--task-type t]`, `status`, `choose QUESTION --option A --option B [--task-type t]`.

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

`src/nar_tools/evals/tools.jsonl` (17 cases; `expect: null` means making no call is right; free-text arguments are not compared, but every required argument must be present and non-empty):

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

import pytest

from nar_tools import evaluate
from nar_tools.evaluate import ModelResult, verdict
from nar_tools.ollama import FirstToken, TokenLogprob
from nar_tools.store import NarStore

REQUIRED = {t["function"]["name"]: t["function"]["parameters"]["required"] for t in evaluate.load_toolset()}


class ScriptedClient:
    """Answers every eval task correctly (with every required argument), fast, fully on the GPU."""

    def __init__(self, on_gpu=True, tps=40.0, extra_call=False, drop_required=False):
        self.on_gpu, self.tps, self.extra_call, self.drop_required = on_gpu, tps, extra_call, drop_required
        self.unloaded = []

    def first_token(self, model, messages, top=20):
        user = messages[-1]["content"]
        case = next(c for c in evaluate.load_jsonl("choose.jsonl") if c["question"] in user)
        letter = "ABCDEFGHIJKLMNOPQRST"[case["answer"]]
        other = "B" if letter == "A" else "A"
        return FirstToken(letter, math.log(0.9), (TokenLogprob(letter, math.log(0.9)), TokenLogprob(other, math.log(0.1))))

    def chat(self, model, messages, tools=None, num_predict=None):
        if tools is None:
            return {"message": {"content": "..."}, "eval_count": int(self.tps * 2), "eval_duration": 2_000_000_000}
        case = next(c for c in evaluate.load_jsonl("tools.jsonl") if c["prompt"] == messages[-1]["content"])
        if case["expect"] is None:
            return {"message": {"content": "hello"}}
        name = case["expect"]["name"]
        args = dict(case["expect"]["arguments"])
        for required in REQUIRED[name]:
            args.setdefault(required, "filled in")
        if self.drop_required:
            args.pop(REQUIRED[name][0])
        calls = [{"function": {"name": name, "arguments": args}}]
        if self.extra_call:
            calls.append({"function": {"name": "set_timer", "arguments": {"minutes": 1}}})
        return {"message": {"tool_calls": calls}}

    def loaded_models(self):
        return [{"name": "m", "model": "m", "size": 100, "size_vram": 100 if self.on_gpu else 60}]

    def unload(self, model):
        self.unloaded.append(model)


def result(**kw):
    base = dict(model="new", tool_success=0.8, choose_accuracy=0.8, choose_ece=0.10, tokens_per_s=40, fully_on_gpu=True)
    base.update(kw)
    return ModelResult(**base)


def test_eval_data_is_well_formed():
    choose = evaluate.load_jsonl("choose.jsonl")
    assert len(choose) >= 30
    assert all(0 <= c["answer"] < len(c["options"]) <= 20 for c in choose)
    counts = [[c["answer"] for c in choose].count(i) for i in range(4)]
    assert max(counts) - min(counts) <= 2
    assert all(c["expect"] is None or c["expect"]["name"] in REQUIRED for c in evaluate.load_jsonl("tools.jsonl"))


def test_a_perfect_model_scores_full_marks_and_is_unloaded():
    client = ScriptedClient()
    r = evaluate.evaluate(client, "m")
    assert r.tool_success == 1.0 and r.choose_accuracy == 1.0
    assert r.fully_on_gpu is True and r.tokens_per_s >= 15 and r.errors == []
    assert client.unloaded == ["m"]


@pytest.mark.parametrize("flaw", ["extra_call", "drop_required"])
def test_invalid_tool_calls_are_not_successes(flaw):
    assert evaluate.evaluate(ScriptedClient(**{flaw: True}), "m").tool_success < 0.2


def test_verdict_passes_when_no_worse_and_within_limits():
    base = result(model="old")
    assert verdict(result(), base, 15)["passes"] is True                       # equal is no worse
    assert verdict(result(tool_success=0.9, choose_ece=0.05), base, 15)["passes"] is True


@pytest.mark.parametrize("change,phrase", [
    (dict(tool_success=0.7), "tool calls"),
    (dict(choose_accuracy=0.7), "accuracy"),
    (dict(choose_ece=0.2), "calibration"),
    (dict(tokens_per_s=9), "tokens/s"),
    (dict(fully_on_gpu=False), "GPU"),
])
def test_each_gated_metric_and_limit_blocks_on_its_own(change, phrase):
    v = verdict(result(**change), result(model="old"), 15)
    assert v["passes"] is False and phrase in " ".join(v["reasons"])


def test_a_baseline_that_could_not_be_measured_blocks_adoption():
    v = verdict(result(tool_success=0.1), result(model="old", errors=["tools: unreachable"]), 15)
    assert v["passes"] is False and "could not be measured" in " ".join(v["reasons"])


def test_run_evaluates_each_model_with_its_deployed_calibration(tmp_path, monkeypatch):
    store = NarStore(tmp_path / "nar")
    with store.lock():
        store.promote("m", "general", {"temperature": 2.0})
    seen = {}
    real = evaluate.evaluate
    monkeypatch.setattr(evaluate, "evaluate", lambda c, m, temperature=1.0: seen.setdefault(m, temperature) and real(c, m, temperature))
    report = evaluate.run(["new"], client=ScriptedClient(), baseline_model="m", out_dir=tmp_path, store=store)
    assert seen == {"new": 1.0, "m": 2.0}
    assert report["baseline"] == "m" and (tmp_path / "latest.json").exists()
```

```python
import json

from nar_tools import cli


def test_fit_prints_a_decision(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    assert cli.main(["fit", "--model", "m", "--task-type", "general"]) == 0
    assert "not enough" in json.loads(capsys.readouterr().out)["reason"]


def test_errors_exit_nonzero(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    assert cli.main(["fit", "--model", "m", "--task-type", "../x"]) == 1
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
from nar_tools.store import NarStore, nar_home

EVALS = Path(__file__).resolve().parent / "evals"
SPEED_PROMPT = "Explain in about 150 words why a test should fail before its fix is written."
DEFAULT_MIN_TOKENS_PER_S = 15.0


@dataclass
class ModelResult:
    model: str
    tool_success: float = 0.0
    choose_accuracy: float = 0.0
    choose_ece: float = 1.0
    tokens_per_s: float = 0.0
    fully_on_gpu: bool = False
    temperature: float = 1.0
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


def _call_ok(calls: list, expect: dict | None, required: dict[str, list[str]]) -> bool:
    if expect is None:
        return not calls
    if len(calls) != 1:
        return False                      # exactly one call: extra calls are not free
    fn = calls[0].get("function") or {}
    args = fn.get("arguments") or {}
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except ValueError:
            return False
    if fn.get("name") != expect["name"]:
        return False
    if any(str(args.get(r, "")).strip() == "" for r in required.get(expect["name"], [])):
        return False                      # every required argument present and non-empty
    return _args_match(expect["arguments"], args)


def eval_tools(client, model: str) -> float:
    toolset = load_toolset()
    required = {t["function"]["name"]: t["function"]["parameters"].get("required", []) for t in toolset}
    cases = load_jsonl("tools.jsonl")
    ok = 0
    for case in cases:
        reply = client.chat(model, [{"role": "user", "content": case["prompt"]}], tools=toolset)
        ok += _call_ok((reply.get("message") or {}).get("tool_calls") or [], case["expect"], required)
    return ok / len(cases)


def eval_choose(client, model: str, temperature: float) -> tuple[float, float]:
    cases, samples, correct = load_jsonl("choose.jsonl"), [], 0
    for case in cases:
        first = client.first_token(model, build_messages(case["question"], case["options"]))
        raw, _ = letter_logprobs(first, len(case["options"]))
        samples.append(Sample(tuple(raw), case["answer"]))
        correct += max(range(len(raw)), key=raw.__getitem__) == case["answer"]
    return correct / len(cases), ece(samples, temperature)


def eval_speed(client, model: str) -> tuple[float, bool]:
    reply = client.chat(model, [{"role": "user", "content": SPEED_PROMPT}], num_predict=200)
    tps = reply.get("eval_count", 0) / max(reply.get("eval_duration", 0) / 1e9, 1e-9)
    on_gpu = any((m.get("name") == model or m.get("model") == model) and m.get("size", 0) > 0
                 and m.get("size_vram", 0) >= m.get("size", 0) for m in client.loaded_models())
    return tps, on_gpu


def evaluate(client, model: str, temperature: float = 1.0) -> ModelResult:
    """Measure one model; `temperature` is the calibration it would really be used with."""
    r = ModelResult(model, temperature=temperature)
    try:
        try:
            r.tool_success = eval_tools(client, model)
        except (OllamaUnavailable, KeyError, ValueError) as e:
            r.errors.append(f"tools: {e}")
        try:
            r.choose_accuracy, r.choose_ece = eval_choose(client, model, temperature)
        except (OllamaUnavailable, KeyError, ValueError) as e:
            r.errors.append(f"choose: {e}")
        try:
            r.tokens_per_s, r.fully_on_gpu = eval_speed(client, model)
        except (OllamaUnavailable, KeyError, ValueError) as e:
            r.errors.append(f"speed: {e}")
    finally:
        try:
            client.unload(model)
        except OllamaUnavailable:
            pass
    return r


def verdict(candidate: ModelResult, baseline: ModelResult | None, min_tps: float) -> dict:
    reasons = []
    if candidate.errors:
        reasons.append("errors: " + "; ".join(candidate.errors))
    if not candidate.fully_on_gpu:
        reasons.append("does not run entirely on the GPU")
    if candidate.tokens_per_s < min_tps:
        reasons.append(f"{candidate.tokens_per_s:.1f} tokens/s is below {min_tps:g}")
    if baseline is not None and baseline.model != candidate.model:
        if baseline.errors:
            reasons.append("the current default could not be measured: " + "; ".join(baseline.errors))
        else:
            if candidate.tool_success < baseline.tool_success:
                reasons.append("fewer successful tool calls than the current default")
            if candidate.choose_accuracy < baseline.choose_accuracy:
                reasons.append("lower nar_choose accuracy than the current default")
            if candidate.choose_ece > baseline.choose_ece:
                reasons.append("worse calibration than the current default")
    return {"passes": not reasons, "reasons": reasons}


def run(models: list[str], client=None, baseline_model: str | None = None, out_dir: Path | None = None,
        store: NarStore | None = None) -> dict:
    client = client or OllamaClient()
    store = store or NarStore()
    state = local_state()
    baseline_model = baseline_model or state.get("default")
    min_tps = float(state.get("min_tokens_per_s") or DEFAULT_MIN_TOKENS_PER_S)
    names = list(dict.fromkeys(models + ([baseline_model] if baseline_model else [])))
    results = {m: evaluate(client, m, temperature=store.current(m, "general")["temperature"]) for m in names}
    base = results.get(baseline_model) if baseline_model else None
    report = {"created_at": time.time(), "machine": platform.node(), "baseline": baseline_model,
              "min_tokens_per_s": min_tps,
              "models": {m: asdict(r) for m, r in results.items()},
              "verdicts": {m: verdict(r, base, min_tps) for m, r in results.items()}}
    out = Path(out_dir) if out_dir else nar_home() / "eval"
    out.mkdir(parents=True, exist_ok=True)
    text = json.dumps(report, indent=2)
    (out / f"{time.strftime('%Y%m%d-%H%M%S')}.json").write_text(text, encoding="utf-8")
    (out / "latest.json").write_text(text, encoding="utf-8")
    return report
```

`src/nar_tools/cli.py`:

```python
"""The `nar` command: eval, fit, status, choose. Long options only (PowerShell owns -o)."""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict

from nar_tools import gate
from nar_tools.evaluate import run
from nar_tools.ollama import OllamaClient, OllamaUnavailable, local_state
from nar_tools.service import NarService
from nar_tools.store import NarStore


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="nar", description="Calibrated single-pass scoring with the local model")
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("eval", help="bake-off; writes <NAR_HOME>/eval/latest.json")
    e.add_argument("--models", required=True, help="comma-separated Ollama tags")
    e.add_argument("--baseline", help="tag to compare against (default: the current default model)")
    f = sub.add_parser("fit", help="refit, and maybe promote, one model's calibrator for one task type")
    f.add_argument("--model", help="Ollama tag (default: the current default model)")
    f.add_argument("--task-type", default="general")
    sub.add_parser("status", help="calls, outcomes, calibrators, reliability, last decision")
    c = sub.add_parser("choose", help="score options once (manual check)")
    c.add_argument("question")
    c.add_argument("--option", action="append", required=True)
    c.add_argument("--task-type", default="general")
    args = p.parse_args(argv)
    try:
        if args.cmd == "eval":
            report = run([m.strip() for m in args.models.split(",") if m.strip()], baseline_model=args.baseline)
            out = {k: report[k] for k in ("baseline", "min_tokens_per_s", "verdicts", "models")}
        elif args.cmd == "fit":
            model = args.model or local_state().get("default")
            if not model:
                raise ValueError("no model given and no local default configured (aos install local)")
            out = asdict(gate.refit(NarStore(), model, args.task_type))
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

- [ ] **Step 5: Commit** (`git commit -m "nar: strict bake-off (nar eval) and CLI"`)

---

### Task 12: aos registers nar, runs it from ~\.aos, syncs its state, and adopts models through the gate

**Files:**
- Modify: `aos.psm1` (`Get-AosMcpManifest`, `Expand-AosPlaceholders`, `Test-AosMcpCurrent`, `Add-AosMcpServer`, `Sync-AosMcp`, `Get-AosStatus` MCP section, `Sync-AosBrain`, `Get-AosNarVenv`, `Get-AosNarHome`, `Install-AosNarTools` (replace the Task 1 stub), `Invoke-AosLocalAdopt`, `Invoke-AosNar`, dispatcher `local` and `nar`, help), `config/mcp.json`
- Test: `tests/aos.Tests.ps1` (`Describe 'MCP placeholders and nar registration'`, `Describe 'aos local adopt'`, `Describe 'Brain sync includes the local state'`, `Describe 'aos nar dispatch'`)

**Interfaces:**
- Consumes: Task 1 functions; `Sync-AosCodexProfiles` (existing); the report format from Task 11 (`baseline`, `verdicts[tag].passes`, `verdicts[tag].reasons`).
- Produces: `aos local adopt <tag> [-DryRun]`, `aos nar <args>` (runs `~\.aos\venvs\nar-tools\Scripts\nar.exe`, arguments forwarded unchanged), `nar` registered in Claude Code and Codex by `aos sync` once the venv exists, `aos sync` refreshing `~\.aos\local.json`.

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

Describe 'Brain sync includes the local state' {
    BeforeEach {
        foreach ($f in 'Set-AosJunction', 'Sync-AosClaudeSkills', 'Set-AosManagedBlock', 'Sync-AosCodexAgents',
                       'Sync-AosClaudeSettings', 'Sync-AosCodexProfiles', 'Sync-AosMcp', 'Sync-AosProfile', 'Sync-AosLocalState') {
            Mock $f -ModuleName aos { }
        }
    }

    It 'refreshes ~\.aos\local.json and passes DryRun through' {
        InModuleScope aos { Sync-AosBrain -DryRun }
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'aos nar dispatch' {
    It 'forwards long options unchanged' {
        Mock Invoke-AosNar -ModuleName aos { }
        aos nar choose 'Which is larger?' --option 7 --option 12
        Should -Invoke Invoke-AosNar -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join '|') -ceq 'choose|Which is larger?|--option|7|--option|12'
        }
    }
}
```

- [ ] **Step 2: Run, see them fail** (`tests\Run-Tests.ps1`; the 11 new tests FAIL)

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
    # nar-tools (Desktop\1-Projects\nar-tools) runs from a venv under ~\.aos: outside OneDrive, and on the
    # system Python (uv must not download one into AppData, which a packaged app can make private).
    $repo = Join-Path (Get-AosProjectsDir) 'nar-tools'
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'pyproject.toml'))) { Write-AosInfo "nar-tools not found in $repo; skipped"; return }
    if (-not (Test-AosCommand uv)) { Write-AosWarn 'uv missing (aos install base)'; return }
    $venv = Get-AosNarVenv
    if ($DryRun) { Write-AosDry "uv sync --frozen --no-dev (venv $venv)"; return }
    $saved = @{}
    $vars = @{ UV_PROJECT_ENVIRONMENT = $venv; UV_LINK_MODE = 'copy'; UV_PYTHON_DOWNLOADS = 'never' }
    foreach ($k in @($vars.Keys)) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
    try { $r = Invoke-AosCapture "uv sync --frozen --no-dev --directory `"$repo`"" }
    finally { foreach ($k in @($vars.Keys)) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') } }
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

`Sync-AosBrain`, after `Sync-AosCodexProfiles -DryRun:$DryRun`:

```powershell
    Write-AosStep 'Local model state (~\.aos\local.json, read by nar)'
    Sync-AosLocalState -DryRun:$DryRun
```

`Get-AosStatus` MCP section: read the manifest with `Get-AosMcpManifest`, and at the top of the per-server loop:

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
  aos nar <args>             the nar CLI from its venv in ~\.aos (long options: --option, not -o)
```

- [ ] **Step 4: Run, see them pass** (`aos test`: all green in both shells)

- [ ] **Step 5: Commit**

```bash
git add aos.psm1 config/mcp.json tests/aos.Tests.ps1
git commit -m "aos: nar registration with run-time paths, aos nar, aos local adopt, local state in sync"
```

---

### Task 13: Install, bake-off, adopt, register (live)

**Files:** none changed except `config/local.json` if a candidate is adopted.

- [ ] **Step 1: Preview, then install** (downloads: Ollama via winget, then `openbmb/minicpm5-2b:q8_0` 2.7 GB and `qwen3.5:4b` 3.4 GB)

Run: `aos install local -DryRun`, then `aos install local`.
Expected: `Ollama.Ollama installed`, both models `pulled`, `<default> runs entirely on the GPU` (or a warning to report), `wrote ~\.aos\local.json`, `nar-tools ready in ~\.aos\venvs\nar-tools`. `ollama --version` is 0.12.11 or newer.

- [ ] **Step 2: Pull the remaining candidate** (2.2 GB): `ollama pull granite4.2:3b`

- [ ] **Step 3: Bake-off**

Run: `aos nar eval --models openbmb/minicpm5-2b:q8_0,qwen3.5:4b,granite4.2:3b`
Expected: per model tool success, choose accuracy, ECE, tokens/s, GPU, and verdicts against the default. Keep the numbers for `docs/decisions.md`.

- [ ] **Step 4: Adopt if a candidate passes and is better**

If a non-default candidate passes and beats the default on the gated metrics: `aos local adopt <tag>`, commit `config/local.json`. If the default fails a hard limit or could not be measured, stop and report to the user before changing anything.

- [ ] **Step 5: Register and check**

Run: `aos sync` (registers `nar` in Claude Code and Codex; refreshes `~\.aos\local.json`), `aos status` (Local models ok; claude/codex: nar ok).
Run: `codex exec --profile local "Reply with the single word OK" </dev/null` - the Codex local profile works through Ollama.
Run: `codex exec "Call the nar_choose tool with question 'Which is a prime number?' and options ['21','29','33'], then print its JSON" </dev/null` - result has `choice` 29 and a `call_id`.
Run: `claude -p "Use the nar_choose MCP tool once: question 'Which planet is closest to the Sun?', options Venus, Mercury, Mars. Print the tool's JSON." --allowedTools mcp__nar__nar_choose` - same shape.
Run the outside-the-package probe (WMI, as in round 3) with `aos status` and `aos nar status`: all ok.

- [ ] **Step 6: Ask the user for the offline check** (criterion 2): with Wi-Fi off, in Windows Terminal: `aos nar choose "Which is larger?" --option 7 --option 12` returns a result.

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
- **Default:** <the tag in config/local.json after Task 13 Step 4>, because <the verdict's reasons>.
- **nar**: one forward pass per choice (Ollama logprobs); temperature calibration per model and task
  type; promotion only if Brier and ECE on held-out calls are no worse; OS file locks; data in ~\.aos\nar.
- **Plan review by Codex before code**: 14 findings, all accepted (list in the plan).
```

- [ ] **Step 3: `aos sync`** so Codex's copy of the contract updates; `aos test` green.
- [ ] **Step 4: Reviews** - Codex reviews agentic-os `main..local-stack` and nar-tools `main` read-only (`codex exec --profile review`); fix findings with tests first.
- [ ] **Step 5: CI and merge** - push `local-stack`, CI green, fast-forward `main`, push. nar-tools: push to its GitHub repo (if the user approved creating it), CI green.
