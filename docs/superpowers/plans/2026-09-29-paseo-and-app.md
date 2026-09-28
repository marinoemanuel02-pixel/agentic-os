# Paseo, a local agent and the aos plugin (phone app) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the Android phone, start and steer sessions on this PC with Claude Code, Codex and an agent that runs on the local model, and use a Paseo plugin to see agentic-os status and nar calibration and to give nar feedback.

**Architecture:** Paseo's daemon runs on the PC and pairs with the Paseo Android app. Its providers are Claude Code and Codex (the official CLIs, so the subscriptions) plus one local-model agent. That agent talks to an Ollama variant, `aos-agent`, which aos derives from the default model with a 16K context: Qwen3.5-4B holds 16K entirely on the 6 GB GPU. The agent harness is chosen by measurement, because its prompt must fit that context with room left for work. The plugin (TypeScript, `nar-tools/paseo-plugin`) adds panels that run only fixed commands.

**Tech Stack:** PowerShell 5.1 + 7 and Pester 5 (agentic-os); Python 3.13 (nar CLI additions); TypeScript per Paseo's plugin tooling (plugin); Ollama 0.34.4; Paseo (Windows install per Task 3).

**Spec:** `docs/superpowers/specs/2026-09-28-local-stack-design.md` (build steps 4 and 5).

## Global Constraints

- Everything from the step 1-2 plan still holds: ASCII, PowerShell 5.1 and 7, tests first and seen failing, idempotent, nothing created under AppData from inside the desktop apps, no absolute paths in repos, no secrets in files, model tags only in `config/local.json`.
- Measured on this laptop (2026-09-29): qwen3.5:4b holds a 16K context 100% on the GPU (3.30 GB); 32K spills 23% to the CPU; Codex's own prompt is ~45K tokens. An agent harness on the local model is adopted only if its prompt plus a 4K working margin fits 16K.
- The plugin never runs user- or model-supplied commands. It runs only fixed commands with validated arguments: `aos status`, `nar status`, and `nar feedback <call_id> <index>` (call_id 32 hex characters, index a small non-negative integer).
- Installs come only from official sources, and each one is listed with its source and approximate size for the user's approval before it runs. The phone pairing and any consent screens are the user's.

---

### Task 1: The `aos-agent` model variant (agentic-os)

**Files:**
- Modify: `config/local.json` (keys `agent_model`, `agent_num_ctx`), `aos.psm1` (`Get-AosAgentModelfile`, `Sync-AosAgentModel`; calls from `Install-AosLocal` and `Invoke-AosLocalAdopt`; a status line)
- Test: `tests/aos.Tests.ps1` (`Describe 'Agent model variant'`)

**Interfaces:**
- Consumes: `Get-AosLocalConfig`, `Get-AosStateDir`, `Test-AosOllamaModel` (step 1 plan).
- Produces: `Get-AosAgentModelfile -From <tag> -NumCtx <int>` (string), `Sync-AosAgentModel [-DryRun]` (creates `agent_model` from the default tag with `PARAMETER num_ctx`, records `agent_from`/`agent_num_ctx` in `~\.aos\local.json`, idempotent), used later by the agent harness config.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'Agent model variant' {
    BeforeEach {
        $stateDir = Join-Path $caseRoot 'state'
        Mock Get-AosStateDir -ModuleName aos { $stateDir }
        Mock Get-AosLocalConfig -ModuleName aos {
            [ordered]@{ default = 'qwen3.5:4b'; agent_model = 'aos-agent'; agent_num_ctx = 16384; ollama_url = 'http://127.0.0.1:11434'; min_tokens_per_s = 15 }
        }
        Mock Write-AosWarn -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'ollama' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nqwen3.5:4b x 3.4 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'success' } } -ParameterFilter { $CommandLine -like 'ollama create *' }
    }

    It 'builds a Modelfile from the default tag with the context size' {
        InModuleScope aos {
            $text = Get-AosAgentModelfile -From 'qwen3.5:4b' -NumCtx 16384
            $text | Should -Match '(?m)^FROM qwen3\.5:4b$'
            $text | Should -Match '(?m)^PARAMETER num_ctx 16384$'
        }
    }

    It 'creates the variant when it is missing and records its source' {
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent -f *' }
        $state = Get-Content -Raw (Join-Path $stateDir 'local.json') | ConvertFrom-Json
        $state.agent_from | Should -BeExactly 'qwen3.5:4b'
        $state.agent_num_ctx | Should -Be 16384
    }

    It 'does nothing when the variant exists and was built from the same default and context' {
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nqwen3.5:4b x 3.4 GB`naos-agent:latest y 3.4 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Write-TestFile (Join-Path $stateDir 'local.json') '{ "agent_from": "qwen3.5:4b", "agent_num_ctx": 16384 }'
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama create *' }
    }

    It 'rebuilds the variant after the default model changes' {
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nqwen3.5:4b x 3.4 GB`naos-agent:latest y 3.4 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Write-TestFile (Join-Path $stateDir 'local.json') '{ "agent_from": "old:tag", "agent_num_ctx": 16384 }'
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent -f *' }
    }

    It 'keeps the agent keys when the local state is rewritten for a new default' {
        Write-TestFile (Join-Path $stateDir 'local.json') '{ "default": "old:tag", "agent_from": "old:tag", "agent_num_ctx": 16384 }'
        InModuleScope aos { Sync-AosLocalState }
        $state = Get-Content -Raw (Join-Path $stateDir 'local.json') | ConvertFrom-Json
        $state.default | Should -BeExactly 'qwen3.5:4b'
        $state.agent_from | Should -BeExactly 'old:tag'      # kept, so Sync-AosAgentModel sees the mismatch and rebuilds
    }

    It 'creates nothing in DryRun or when the default model is not pulled' {
        InModuleScope aos { Sync-AosAgentModel -DryRun }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama create *' }
    }
}
```

- [ ] **Step 2: Run, see them fail** (`pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1`; the 6 new tests FAIL, the other 144 pass)

- [ ] **Step 3: Implement**

`config/local.json`: add `"agent_model": "aos-agent"` and `"agent_num_ctx": 16384`, and a `_readme` line: `"agent_model: an Ollama variant of the default with agent_num_ctx context, for agent harnesses (OpenAI-compatible clients cannot set the context size). 16K holds 100% on the 6 GB GPU with qwen3.5:4b."`

`aos.psm1`, after `Sync-AosLocalState`:

```powershell
function Get-AosAgentModelfile([string]$From, [int]$NumCtx) {
    return "FROM $From`nPARAMETER num_ctx $NumCtx`n"
}

function Sync-AosAgentModel([switch]$DryRun) {
    # Agent harnesses reach the local model through OpenAI-compatible APIs, which cannot set Ollama's
    # context size, so they use this variant of the default model instead.
    $cfg = Get-AosLocalConfig
    if (-not $cfg -or -not $cfg['agent_model']) { return }
    if (-not (Test-AosCommand ollama)) { Write-AosWarn 'ollama missing; agent model not created (aos install local)'; return }
    $name = [string]$cfg['agent_model']; $from = [string]$cfg['default']; $ctx = [int]$cfg['agent_num_ctx']
    $list = (Invoke-AosCapture 'ollama list').Text
    if (-not (Test-AosOllamaModel -List $list -Tag $from)) { Write-AosWarn "default model $from not pulled; $name not created"; return }
    $statePath = Join-Path (Get-AosStateDir) 'local.json'
    $state = Read-AosJson $statePath
    if ($state -and ($state['agent_from'] -eq $from) -and ([int]$state['agent_num_ctx'] -eq $ctx) -and (Test-AosOllamaModel -List $list -Tag $name)) {
        Write-AosOk "$name ($from, context $ctx)"; return
    }
    if ($DryRun) { Write-AosDry "ollama create $name from $from with num_ctx $ctx"; return }
    $file = Join-Path (Get-AosStateDir) 'agent.Modelfile'
    Write-AosText -Path $file -Text (Get-AosAgentModelfile -From $from -NumCtx $ctx)
    $r = Invoke-AosCapture "ollama create $name -f `"$file`""
    if ($r.Code -ne 0) { Write-AosWarn "ollama create $name failed (exit $($r.Code))"; return }
    if (-not $state) { $state = [ordered]@{} }
    $state['agent_from'] = $from; $state['agent_num_ctx'] = $ctx
    Write-AosText -Path $statePath -Text ((ConvertTo-Json -InputObject $state -Depth 5) + "`n")
    Write-AosOk "created $name from $from (context $ctx)"
}
```

Call `Sync-AosAgentModel -DryRun:$DryRun` in `Install-AosLocal` after `Sync-AosLocalState`, and `Sync-AosAgentModel` in `Invoke-AosLocalAdopt` after `Sync-AosLocalState` (the variant follows the default).

`Sync-AosLocalState` must keep keys it does not own when it rewrites the file: build the output from the existing state (or a new `[ordered]@{}`) and set only `default`, `ollama_url` and `min_tokens_per_s` on it, instead of writing a fresh three-key object. It still compares only its own three keys, so the `agent_*` keys never make it rewrite the file.

- [ ] **Step 4: Run, see them pass** (`aos test`: all green in both shells)

- [ ] **Step 5: Commit** (`git commit -m "aos: aos-agent, the local model with a 16K context for agent harnesses"`)

---

### Task 2: `nar feedback` on the command line (nar-tools)

The plugin's feedback buttons run this fixed command, so feedback keeps one writer (the store, with its
locks) instead of a second implementation in TypeScript.

**Files:**
- Modify: `src/nar_tools/cli.py`
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: `NarService.feedback(call_id, outcome)` (step 2 plan; validates the call and the outcome).
- Produces: `nar feedback CALL_ID OUTCOME` - prints the service's JSON and exits 0; exits 1 with `{"error": ...}` on stderr for an unknown call, a bad outcome, or a `call_id` that is not 32 lowercase hex characters (checked before the store is touched).

- [ ] **Step 1: Write the failing tests** (append to `tests/test_cli.py`)

```python
from nar_tools.store import NarStore


def _logged_call(tmp_path):
    NarStore(tmp_path).log_call({"call_id": "a" * 32, "model": "m", "task_type": "general",
                                 "raw_logprobs": [0.0, -1.0], "options": ["x", "y"]})


def test_feedback_records_an_outcome(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    _logged_call(tmp_path)
    assert cli.main(["feedback", "a" * 32, "1"]) == 0
    assert json.loads(capsys.readouterr().out)["outcome"] == 1
    assert NarStore(tmp_path).feedback()[-1]["outcome"] == 1


def test_feedback_refuses_a_malformed_call_id_without_touching_the_store(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    _logged_call(tmp_path)
    assert cli.main(["feedback", "../../x", "1"]) == 1
    assert "call_id" in capsys.readouterr().err
    assert NarStore(tmp_path).feedback() == []


def test_feedback_for_an_unknown_call_fails(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    assert cli.main(["feedback", "b" * 32, "0"]) == 1
    assert "unknown call_id" in capsys.readouterr().err
```

- [ ] **Step 2: Run, see them fail** (`uv run pytest tests/test_cli.py -q`: 3 new FAIL, argparse rejects `feedback`)

- [ ] **Step 3: Implement** - in `cli.main`, add the subparser and the branch:

```python
    fb = sub.add_parser("feedback", help="record which option was right for a call")
    fb.add_argument("call_id")
    fb.add_argument("outcome", help="0-based index or the option's exact text")
```

```python
        elif args.cmd == "feedback":
            if not re.fullmatch(r"[0-9a-f]{32}", args.call_id):
                raise ValueError("call_id must be 32 lowercase hex characters")
            outcome = int(args.outcome) if args.outcome.isdigit() else args.outcome
            out = NarService(OllamaClient(), NarStore()).feedback(args.call_id, outcome)
```

(add `import re` at the top; `NarService.feedback` never calls Ollama.)

- [ ] **Step 4: Run, see them pass** (`uv run pytest -q`: whole suite green)

- [ ] **Step 5: Commit** (`git commit -m "nar: feedback from the command line"`)

---

### Task 3: `nar recent` - calls still waiting for an outcome (nar-tools)

**Files:** Modify `src/nar_tools/store.py` (`recent_unlabelled`), `src/nar_tools/cli.py`. Test: `tests/test_store.py`, `tests/test_cli.py`.

**Interfaces:** Produces `NarStore.recent_unlabelled(limit: int = 10) -> list[dict]` (newest first; keys `call_id, model, task_type, question, options, choice_index` where `choice_index` is the argmax of the logged `raw_logprobs`) and `nar recent [--limit N]` (JSON list; N clamped to 1..50).

- [ ] **Step 1: Failing tests**

```python
def test_recent_unlabelled_lists_newest_first_and_skips_labelled(tmp_path):
    s = NarStore(tmp_path)
    for i in range(3):
        s.log_call({**call(f"c{i}", raw=(-1.0, -0.1)), "question": f"q{i}"})
    s.log_feedback({"call_id": "c1", "outcome": 0})
    rows = s.recent_unlabelled(limit=10)
    assert [r["call_id"] for r in rows] == ["c2", "c0"]
    assert rows[0]["choice_index"] == 1 and rows[0]["question"] == "q2"
```

```python
def test_recent_prints_json_and_clamps_the_limit(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NAR_HOME", str(tmp_path))
    _logged_call(tmp_path)
    assert cli.main(["recent", "--limit", "999"]) == 0
    rows = json.loads(capsys.readouterr().out)
    assert rows[0]["call_id"] == "a" * 32
```

- [ ] **Step 2:** run, see them fail (`uv run pytest -q`).
- [ ] **Step 3: Implement**

```python
    def recent_unlabelled(self, limit: int = 10) -> list[dict]:
        labelled = {f.get("call_id") for f in self.feedback()}
        rows = []
        for c in reversed(self.calls()):
            if c.get("call_id") in labelled or "raw_logprobs" not in c:
                continue
            raw = c["raw_logprobs"]
            rows.append({"call_id": c["call_id"], "model": c.get("model"), "task_type": c.get("task_type"),
                         "question": c.get("question"), "options": c.get("options"),
                         "choice_index": max(range(len(raw)), key=raw.__getitem__)})
            if len(rows) >= limit:
                break
        return rows
```

CLI: `r = sub.add_parser("recent", help="calls still waiting for an outcome"); r.add_argument("--limit", type=int, default=10)` and `elif args.cmd == "recent": out = NarStore().recent_unlabelled(max(1, min(50, args.limit)))`.

- [ ] **Step 4:** run, see them pass. **Step 5:** commit (`nar: recent unlabelled calls`).

---

### Task 4: npm tools with a different command name; the Paseo CLI and agent harness candidates (agentic-os)

`Install-AosNpmTools` checks `<prefix>\<name>.cmd`, which is wrong for scoped packages
(`@getpaseo/cli` installs `paseo.cmd`).

**Files:** Modify `aos.psm1` (`Install-AosNpmTools`, `Install-AosLocal`), `packages.json` (new `local_npm` list). Test: `tests/aos.Tests.ps1`.

**Interfaces:** package entries may carry `bin` (the command it installs); `Install-AosNpmTools` checks `<prefix>\<bin or name>.cmd`. `Install-AosLocal` installs `local_npm` with `Install-AosNpmTools`.

- [ ] **Step 1: Failing test** (in `Describe 'Round 3: Install-AosNpmTools'`'s style)

```powershell
    It 'checks the command a package installs, not the package name' {
        Write-TestFile (Join-Path $npmPrefix 'paseo.cmd') ''
        InModuleScope aos { Install-AosNpmTools -Packages @(@{ name = '@getpaseo/cli'; bin = 'paseo'; why = 'test' }) }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }
```

(uses that Describe's mocks: `Get-AosNpmPrefix` -> `$npmPrefix`, `Use-AosNpmPrefix` mocked, npm present.)

- [ ] **Step 2:** run, see it fail (it installs because `@getpaseo/cli.cmd` does not exist).
- [ ] **Step 3: Implement** - in `Install-AosNpmTools`: `$bin = $name; if ($n.Contains('bin') -and $n['bin']) { $bin = $n['bin'] }` and test `Join-Path $prefix "$bin.cmd"`. In `packages.json` add:

```json
  "local_npm": [
    { "name": "@getpaseo/cli", "bin": "paseo",    "why": "Paseo: the daemon the phone app connects to (state in ~\\.paseo)" },
    { "name": "opencode-ai",   "bin": "opencode", "why": "OpenCode: agent-harness candidate for the local model (Task 5 decides)" }
  ],
```

In `Install-AosLocal`, after the models: `Install-AosNpmTools -Packages (Get-AosPackages)['local_npm'] -DryRun:$DryRun`.
Also verify in this step, and record in the commit message, the npm package names and sizes the user
approves (`npm view @getpaseo/cli version dist.unpackedSize`, `npm view opencode-ai version dist.unpackedSize`).

- [ ] **Step 4:** `aos test` green. **Step 5:** commit (`aos: npm tools by command name; Paseo CLI and OpenCode in the local layer`).

---

### Task 5: Which agent harness fits the local model (live measurement, no code)

- [ ] **Step 1:** with the user's approval of the downloads, run `aos install local` (pulls nothing new; creates `aos-agent`; installs `paseo` and `opencode` into `~\.npm-global`).
- [ ] **Step 2: Measure OpenCode's prompt.** Run one prompt against `aos-agent` with a temporary config
  (`OPENCODE_CONFIG_CONTENT` = the Task 6 provider block): `opencode run --model ollama/aos-agent "Reply with OK"`.
  If the prompt does not fit, Ollama's error states `n_prompt_tokens`; if it fits, read `prompt_eval_count`
  for that request from `%LOCALAPPDATA%\Ollama\server.log` (or repeat with `aos-agent` rebuilt at 4K context
  so the overflow error reports the size). Record the prompt size with the nar and context7 MCP servers enabled.
- [ ] **Step 3: Decide.** OpenCode is adopted if its prompt plus 4K fits 16K. If not, measure Paseo's `pi`
  provider the same way (verify its package name and Ollama setup first) and adopt it if it fits. If
  neither fits, stop: record the numbers in `docs/decisions.md`, skip Task 6, and keep the local model
  reachable only through `nar` (the phone still gets Claude Code and Codex). Write the result to the ledger.

---

### Task 6: OpenCode configured for the local model and nar (agentic-os; only if Task 5 adopted OpenCode)

**Files:** Modify `aos.psm1` (`Get-AosOpenCodeConfigPath`, `Get-AosOpenCodeOverlay`, `Sync-AosOpenCode`; call from `Sync-AosBrain`). Test: `tests/aos.Tests.ps1` (`Describe 'OpenCode config'`).

**Interfaces:** `Get-AosOpenCodeOverlay` returns the ordered overlay: `provider.ollama` (`npm` `@ai-sdk/openai-compatible`, `name` `Ollama (local)`, `options.baseURL` = `ollama_url` + `/v1`, `models` = { `<agent_model>`: { `name`: `<agent_model>` } }) and `mcp` built from `config/mcp.json` (stdio -> `{ type: local, command: [command] + args, enabled: true }`, http -> `{ type: remote, url, enabled: true }`, servers whose `requires` is missing are left out). `Sync-AosOpenCode [-DryRun]` merges it into `~\.config\opencode\opencode.json` with `Merge-AosTree`, backs up the old file first, and writes nothing when the merge changes nothing.

- [ ] **Step 1: Failing tests**

```powershell
Describe 'OpenCode config' {
    BeforeEach {
        $cfgPath = Join-Path $caseRoot 'opencode\opencode.json'
        Mock Get-AosOpenCodeConfigPath -ModuleName aos { $cfgPath }
        Mock Get-AosLocalConfig -ModuleName aos { [ordered]@{ default = 'qwen3.5:4b'; agent_model = 'aos-agent'; agent_num_ctx = 16384; ollama_url = 'http://127.0.0.1:11434' } }
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{
                context7 = [ordered]@{ transport = 'http'; url = 'https://mcp.context7.com/mcp' }
                nar = [ordered]@{ transport = 'stdio'; command = '{{projects}}\nar-mcp.exe'; args = @(); requires = '{{projects}}\nar-mcp.exe' } } }
        }
        $savedProjects = $env:AOS_PROJECTS; $env:AOS_PROJECTS = Join-Path $caseRoot 'projects'
    }
    AfterEach { $env:AOS_PROJECTS = $savedProjects }

    It 'adds the Ollama provider with the agent model and the MCP servers, keeping the user''s keys' {
        Write-TestFile $cfgPath '{ "theme": "mine", "provider": { "other": { "name": "kept" } } }'
        Write-TestFile (Join-Path $env:AOS_PROJECTS 'nar-mcp.exe') ''
        InModuleScope aos { Sync-AosOpenCode }
        $j = Get-Content -Raw $cfgPath | ConvertFrom-Json
        $j.theme | Should -BeExactly 'mine'
        $j.provider.other.name | Should -BeExactly 'kept'
        $j.provider.ollama.options.baseURL | Should -BeExactly 'http://127.0.0.1:11434/v1'
        $j.provider.ollama.models.'aos-agent'.name | Should -BeExactly 'aos-agent'
        $j.mcp.context7.type | Should -BeExactly 'remote'
        $j.mcp.nar.command[0] | Should -BeExactly (Join-Path $env:AOS_PROJECTS 'nar-mcp.exe')
    }

    It 'leaves out servers whose required file is missing' {
        InModuleScope aos { Sync-AosOpenCode }
        (Get-Content -Raw $cfgPath | ConvertFrom-Json).mcp.PSObject.Properties.Name | Should -Not -Contain 'nar'
    }

    It 'writes nothing on a second run or in DryRun' {
        InModuleScope aos { Sync-AosOpenCode -DryRun }
        Test-Path -LiteralPath $cfgPath | Should -BeFalse
        InModuleScope aos { Sync-AosOpenCode }
        $before = (Get-Item -LiteralPath $cfgPath).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50
        InModuleScope aos { Sync-AosOpenCode }
        (Get-Item -LiteralPath $cfgPath).LastWriteTimeUtc | Should -Be $before
    }
}
```

- [ ] **Step 2:** run, see them fail. **Step 3:** implement (reuse `Expand-AosPlaceholders`, `Merge-AosTree`, `Backup-AosFile`, `Write-AosText`; compare the merged tree with the current one via `ConvertTo-Json -Depth 20 -Compress` before writing). **Step 4:** `aos test` green. **Step 5:** commit (`aos: OpenCode on the local agent model, with the MCP servers`).

---

### Task 7: Paseo on this PC (live, the user present for pairing)

- [ ] **Step 1:** from Windows Terminal (not inside the Claude app, so the daemon's environment has the full
  PATH): `paseo daemon start`, `paseo daemon status`, then `paseo provider diagnostic claude`, `... codex`,
  `... opencode` (each must report the CLI found).
- [ ] **Step 2:** enable plugins (verify the exact key at `packages/server/src/server/config.ts:627` of the clone
  and set it with `paseo daemon config set`), `paseo daemon restart`.
- [ ] **Step 3 (user):** install Paseo from the Play Store on the phone; on the PC run `paseo daemon pair --relay`;
  scan the QR in the app (Add connection -> Scan QR code). Keep the QR private.
- [ ] **Step 4:** from the phone, start one short session each with Claude Code, Codex and the local agent;
  approve one permission prompt from the phone (spec criterion 1).
- [ ] **Step 5 (offer, not do):** starting the daemon at login needs a Startup-folder shortcut or scheduled task:
  ask the user.

---

### Task 8: The aos plugin (nar-tools/paseo-plugin)

**Files:** `paseo plugin init <abs path>\nar-tools\paseo-plugin`, then `paseo-plugin.json` (id `aos`,
`requirements.paseo` `>=0.10.0`), `shared/rpc.ts` (four `defineRpc` contracts), `server/commands.ts` (pure:
build argv, validate input, parse output), `server/commands.test.ts` (Vitest), `index.server.ts`
(`server.handle` for each RPC, `execFile` with the argv from `commands.ts`, 20 s timeout), `client/panel.tsx`
and `index.client.tsx` (`addWorkspacePanel` "agentic-os": status text, calibration per model/task type,
recent calls with one button per option that calls `narFeedback`). Model the files on
`plugin-examples/local-plugin` in the clone; read `packages/plugin/src/client/contracts.ts` and
`packages/plugin/src/server/contracts.ts` for exact signatures.

**Interfaces (commands.ts):**
- `aosStatusArgv(): [string, string[]]` -> `["pwsh", ["-NoLogo", "-NonInteractive", "-Command", "aos status"]]` (the user's profile loads aos).
- `narArgv(narExe: string, sub: "status" | "recent" | "feedback", input?: { callId: string; index: number }): [string, string[]]`
  - `feedback` requires `callId` to match `/^[0-9a-f]{32}$/` and `index` to be an integer 0..19, else throws `Error("invalid feedback")`.
- `narExePath(home: string): string` -> `<home>\.aos\venvs\nar-tools\Scripts\nar.exe`.
- `stripAnsi(text: string): string` for `aos status` output.

- [ ] **Step 1: Failing tests** `server/commands.test.ts`

```ts
import { describe, expect, it } from "vitest";
import { aosStatusArgv, narArgv, narExePath, stripAnsi } from "./commands";

describe("commands", () => {
  it("runs aos status through pwsh with fixed arguments", () => {
    expect(aosStatusArgv()).toEqual(["pwsh", ["-NoLogo", "-NonInteractive", "-Command", "aos status"]]);
  });
  it("builds nar commands from a fixed list", () => {
    expect(narArgv("nar.exe", "status")).toEqual(["nar.exe", ["status"]]);
    expect(narArgv("nar.exe", "recent")).toEqual(["nar.exe", ["recent", "--limit", "10"]]);
    expect(narArgv("nar.exe", "feedback", { callId: "a".repeat(32), index: 2 })).toEqual(["nar.exe", ["feedback", "a".repeat(32), "2"]]);
  });
  it.each([
    { callId: "../../x", index: 0 }, { callId: "A".repeat(32), index: 0 },
    { callId: "a".repeat(32), index: -1 }, { callId: "a".repeat(32), index: 20 }, { callId: "a".repeat(32), index: 1.5 },
  ])("refuses invalid feedback %o", (input) => {
    expect(() => narArgv("nar.exe", "feedback", input)).toThrow("invalid feedback");
  });
  it("finds nar in the aos venv and strips colour codes", () => {
    expect(narExePath("C:\\Users\\u")).toBe("C:\\Users\\u\\.aos\\venvs\\nar-tools\\Scripts\\nar.exe");
    expect(stripAnsi("\u001b[32mok\u001b[0m")).toBe("ok");
  });
});
```

- [ ] **Step 2:** `npx vitest run` fails (module missing).
- [ ] **Step 3: Implement** `server/commands.ts`:

```ts
const CALL_ID = /^[0-9a-f]{32}$/;

export function aosStatusArgv(): [string, string[]] {
  return ["pwsh", ["-NoLogo", "-NonInteractive", "-Command", "aos status"]];
}

export function narExePath(home: string): string {
  return `${home}\\.aos\\venvs\\nar-tools\\Scripts\\nar.exe`;
}

export function narArgv(narExe: string, sub: "status" | "recent" | "feedback",
                        input?: { callId: string; index: number }): [string, string[]] {
  if (sub === "status") return [narExe, ["status"]];
  if (sub === "recent") return [narExe, ["recent", "--limit", "10"]];
  if (!input || !CALL_ID.test(input.callId) || !Number.isInteger(input.index) || input.index < 0 || input.index > 19) {
    throw new Error("invalid feedback");
  }
  return [narExe, ["feedback", input.callId, String(input.index)]];
}

export function stripAnsi(text: string): string {
  return text.replace(/\u001b\[[0-9;]*[A-Za-z]/g, "");
}
```

Then the RPCs, server handlers and the panel (typecheck is the test for them: `npm run typecheck`).
Add `vitest` to devDependencies and a `test` script (`vitest run`).
- [ ] **Step 4:** `npx vitest run` and `npm run typecheck` pass.
- [ ] **Step 5:** `paseo plugin install <abs path>`; the panel shows on the phone; a feedback tap appears in
  `aos nar status` as one more labelled call. Commit (`paseo-plugin: agentic-os panel with nar feedback`).

---

## Review Focus

1. A tampered or malformed feedback request from the phone (`callId` with path characters, index out of
   range or fractional) is refused before any command runs (Task 8 tests).
2. The daemon started from inside the Claude app would inherit a partial PATH and write to a private
   AppData: Task 7 starts it from Windows Terminal and checks each provider with `paseo provider diagnostic`.
3. OpenCode's prompt larger than the 16K context: measured in Task 5 before anything depends on it; the
   plan stops rather than adopt a harness that spills to the CPU.
4. The user's own OpenCode settings survive `aos sync` (Task 6 test keeps unknown keys and providers).
5. `aos-agent` goes stale after `aos local adopt`: Task 1 rebuilds it when the default changes.
