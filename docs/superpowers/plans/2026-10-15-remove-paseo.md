# Paseo Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Paseo from this PC and from the agentic-os and nar-tools repos in four checked stages, with the Claude / Codex / local-model orchestration unaffected.

**Architecture:** Stage 0 cuts two hidden dependencies (live nar sits on a Paseo branch; video voice loads sherpa-onnx from inside the Paseo package). Stage 1 stops the daemon and parks the skill copies (reversible). Stage 2 removes the code, tests and docs on branch `remove-paseo`, test-first, with a tombstone test that fails while any tracked file still names the tool. Stage 3 moves what is left into a holding folder and runs the first full `aos sync` since 2026-10-12. Each stage starts only on the operator's word.

**Tech Stack:** PowerShell 5.1 + 7, Pester 5.5+ (`tests/aos.Tests.ps1`), Node (voice tools), Python/uv + pytest (nar-tools), git.

**Spec:** `docs/superpowers/specs/2026-10-15-remove-paseo-design.md` (approved 2026-10-15, with the planning-time amendments at its end, which the operator confirms when reviewing this plan). Codex's critique of the spec: `2026-10-15-remove-paseo-codex-critique.md`.

## Global Constraints

- `aos.psm1`, `bootstrap.ps1` and `tests/Run-Tests.ps1` stay ASCII-only and run under Windows PowerShell 5.1 and PowerShell 7: no `??`, no ternary, no `&&`/`||`. Test code in `tests/aos.Tests.ps1` obeys the same.
- Run `aos test` after each task's repo edits and before its commit (it checks parsing and ASCII, then runs `tests/` under both shells; CI runs the same on every push). The filtered runs inside a task (`AOS_TEST_FILTER`) are only for seeing one block fail and then pass.
- Tests use `$TestDrive` and `$env:AOS_BACKUPS`, never the real profile, registry or network.
- Every sync step stays idempotent: a second `aos sync` changes nothing. Merge into the user's files, never replace them, and back up to `~/.aos-backups/` first.
- `docs/decisions.md` is append-only: a changed decision gets a new dated entry on top.
- No model names in the repo. No absolute paths in the repo (resolve at run time).
- Anything that writes to `~/.claude`, `~/.codex` or the user PATH gets a second opinion from the other vendor first (Stage 1 and Stage 3 steps below are in the plan Codex reviews).
- One writer per checkout: run `aos who` before editing a checkout; a blocked edit means another live session holds it - stop and tell the operator.
- An agent never permanently deletes. Removed folders, skill copies, the Paseo package and its shims move to the holding folder `$bk\removed` (no `npm uninstall`: a move keeps the undo free of a 538 MB download); the operator deletes it. A step that needs a download or install states the source and size and waits for a yes.
- Stage order 0, 1, 2, 3. Stages 0 and 1 delete nothing from the repo. Do not start a stage without the operator's word.
- Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

Failure modes the spec implies that no unit test exercises. Each is pinned to the task that owns it.

1. **Live nar switched off its branch while sessions hold `nar-mcp` open.** Expected: nothing changes, because Python source outside `paseo-plugin/` is identical on both branches. Pinned in Task 2 by an empty `git diff` outside the plugin and by `nar status` / `nar classify` working from the live venv afterwards.
2. **A delivered film's voice tool still names the removed path.** Expected: sealed and dirty films are skipped and listed, never edited; the list is recorded in `decisions.md`. Pinned in Task 3 (`voice-plan.json`) and Task 8 (decisions entry).
3. **The daemon relaunched by something other than the known logon task** (Run key, Startup folder, another task, a restart window). Expected: none exists, checked right after the stop and again 6+ minutes later. Pinned in Task 5.
4. **`aos sync` or `aos status` run while the `paseo` command still exists** (Stage 2 is merged before Stage 3 uninstalls it). Expected: neither calls it. Pinned in Task 7 (tests with `Test-AosCommand` forced true).
5. **A second `aos sync` after the removal.** Expected: no output line reports a change and `~/.aos-backups` gains no file (a write would add a backup). Pinned in Task 12.

## File Structure

| Path | Change | Task |
|---|---|---|
| `tests/Run-Tests.ps1` | modify: opt-in `AOS_TEST_FILTER` | 6 |
| `tests/aos.Tests.ps1` | modify: 7 Describe blocks and 4 Places cases removed, 2 tests rewritten, 4 new blocks | 3, 6, 7, 8 |
| `aos.psm1` | modify: delete the phone layer, daemon, task, plugin and Places-registration code | 6, 7 |
| `packages.json`, `bootstrap.ps1`, `refs/repos.json` | modify | 6, 8 |
| `templates/video/tools/make-voice.cjs` | modify: 2-line sherpa loader | 3 |
| `README.md`, `docs/routing.md`, `docs/decisions.md`, `agents-home/skills/tool-catalog/SKILL.md`, `agents-home/skills/media-tools/SKILL.md`, `config/pi/extensions/aos-permission-gate.ts` | modify | 8 |
| 4 historical plan/spec files | modify: one status line | 8 |
| `nar-tools` repo: `paseo-plugin/` | delete (tag `archive/paseo-plugin` first) | 2, 9 |
| Film repos' `tools/make-voice.cjs` | modify only if unsealed and clean | 3 |
| Memory notes (`nar-embed-backend.md`, `MEMORY.md`, new `paseo-removed.md`) | modify / create | 12 |
| `~/.aos/scratch/remove-paseo/` (outside the repo) | create: `env.ps1`, `helpers.ps1`, scripts | 1 |

---

## Stage 0 - cut the hidden dependencies

### Task 1: Preflight, scratch helpers, branch, baseline

**Files:**
- Create (outside the repo): `~/.aos/scratch/remove-paseo/env.ps1`, `~/.aos/scratch/remove-paseo/helpers.ps1`
- Create: the backup folder `~/.aos-backups/remove-paseo-<stamp>/`
- Branch: `remove-paseo` in agentic-os

**Interfaces:**
- Produces: `env.ps1` defines `$root` (agentic-os checkout), `$nar`, `$videos`, `$work`, `$bk`, and `Invoke-Aos`. `helpers.ps1` defines `Read-AosFile`, `Save-AosFile`, `Replace-Once`, `Replace-Span`, `Remove-LinesMatching`, `Remove-Describe`, `Insert-BeforeLine`, `Insert-AfterLine`. Every later task starts with `. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1` (shell state does not persist between tool calls).

- [ ] **Step 1: Create the scratch folder and `env.ps1`** (PowerShell 7)

```powershell
$work = Join-Path $HOME '.aos\scratch\remove-paseo'
New-Item -ItemType Directory -Force $work | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
@"
`$desk   = [Environment]::GetFolderPath('Desktop')
`$root   = Join-Path `$desk 'agentic-os'
`$nar    = Join-Path `$desk '1-Projects\nar-tools'
`$videos = Join-Path `$desk '1-Projects\videos'
`$work   = Join-Path `$HOME '.aos\scratch\remove-paseo'
`$bk     = Join-Path `$HOME '.aos-backups\remove-paseo-$stamp'
function Invoke-Aos([string]`$Line) { & powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '`$root\aos.psm1' -Force; aos `$Line" }
"@ | Set-Content (Join-Path $work 'env.ps1') -Encoding utf8
. (Join-Path $work 'env.ps1')
New-Item -ItemType Directory -Force $bk | Out-Null
(Test-Path (Join-Path $root 'aos.psm1')), (Test-Path $nar), (Test-Path $videos)
```

Expected: `True`, `True`, `True`. If any is `False`, stop: the folders are not where the plan assumes.

- [ ] **Step 2: Create `helpers.ps1`** (CRLF-safe edits; every repo file here is CRLF, so a plain multi-line replace can silently fail to match)

```powershell
@'
$script:EncNoBom = New-Object System.Text.UTF8Encoding($false)
$script:EncBom = New-Object System.Text.UTF8Encoding($true)

function Read-AosFile([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [IO.File]::ReadAllText($Path)
    $eol = "`n"
    if ($text.Contains("`r`n")) { $eol = "`r`n" }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in [regex]::Split($text, '(?<=\n)')) { if ($l -ne '') { $lines.Add($l) } }
    return [pscustomobject]@{ Path = $Path; Bom = $bom; Eol = $eol; Lines = $lines }
}
function Save-AosFile($F) {
    $enc = $script:EncNoBom
    if ($F.Bom) { $enc = $script:EncBom }
    [IO.File]::WriteAllText($F.Path, ($F.Lines -join ''), $enc)
}
function ConvertTo-Eol([string]$Text, [string]$Eol) { return ($Text -replace "`r?`n", $Eol) }

function Replace-Once([string]$Path, [string]$Old, [string]$New) {
    $f = Read-AosFile $Path
    $text = $f.Lines -join ''
    $o = ConvertTo-Eol $Old $f.Eol
    $i = $text.IndexOf($o, [StringComparison]::Ordinal)
    if ($i -lt 0) { throw "Replace-Once: text not found in ${Path}: $Old" }
    if ($text.IndexOf($o, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "Replace-Once: more than one match in ${Path}: $Old" }
    $text = $text.Remove($i, $o.Length).Insert($i, (ConvertTo-Eol $New $f.Eol))
    $enc = $script:EncNoBom
    if ($f.Bom) { $enc = $script:EncBom }
    [IO.File]::WriteAllText($Path, $text, $enc)
}

# Replace the lines from the single line matching $From through the first line matching $To (inclusive;
# with -ExclusiveEnd the $To line is kept) by $New (empty = delete).
function Replace-Span {
    param([string]$Path, [string]$From, [string]$To, [string]$New = '', [switch]$ExclusiveEnd)
    $f = Read-AosFile $Path
    $starts = @(0..($f.Lines.Count - 1) | Where-Object { $f.Lines[$_] -match $From })
    if ($starts.Count -ne 1) { throw "Replace-Span: '$From' matched $($starts.Count) lines in $Path" }
    $s = $starts[0]
    $from2 = $s
    if ($ExclusiveEnd) { $from2 = $s + 1 }
    $e = -1
    for ($i = $from2; $i -lt $f.Lines.Count; $i++) { if ($f.Lines[$i] -match $To) { $e = $i; break } }
    if ($e -lt 0) { throw "Replace-Span: '$To' not found after line $($s + 1) in $Path" }
    $last = $e
    if ($ExclusiveEnd) {
        $last = $e - 1
        # A replacement keeps the blank line(s) that separated the span from the next function; a deletion does not.
        if ($New -ne '') { while ($last -gt $s -and $f.Lines[$last].Trim() -eq '') { $last-- } }
    }
    $f.Lines.RemoveRange($s, $last - $s + 1)
    if ($New -ne '') { $f.Lines.Insert($s, ((ConvertTo-Eol $New $f.Eol).TrimEnd("`r", "`n") + $f.Eol)) }
    Save-AosFile $f
}

function Remove-LinesMatching([string]$Path, [string]$Regex, [int]$Expect) {
    $f = Read-AosFile $Path
    $hits = @(0..($f.Lines.Count - 1) | Where-Object { $f.Lines[$_] -match $Regex })
    if ($hits.Count -ne $Expect) { throw "Remove-LinesMatching: '$Regex' matched $($hits.Count) lines in $Path, expected $Expect" }
    for ($k = $hits.Count - 1; $k -ge 0; $k--) { $f.Lines.RemoveAt($hits[$k]) }
    Save-AosFile $f
}

# Remove a whole top-level Describe block (through the line before the next Describe).
function Remove-Describe([string]$Path, [string]$Name) {
    $f = Read-AosFile $Path
    $start = -1; $end = -1
    for ($i = 0; $i -lt $f.Lines.Count; $i++) {
        if ($start -lt 0) { if ($f.Lines[$i] -match ("^Describe '" + [regex]::Escape($Name) + "' \{")) { $start = $i } }
        elseif ($f.Lines[$i] -match '^Describe ') { $end = $i; break }
    }
    if ($start -lt 0) { throw "Remove-Describe: no Describe '$Name' in $Path" }
    if ($end -lt 0) { throw "Remove-Describe: '$Name' has no following Describe in $Path" }
    $f.Lines.RemoveRange($start, $end - $start)
    Save-AosFile $f
}

function Insert-BeforeLine([string]$Path, [string]$Regex, [string]$Text) {
    $f = Read-AosFile $Path
    $hits = @(0..($f.Lines.Count - 1) | Where-Object { $f.Lines[$_] -match $Regex })
    if ($hits.Count -ne 1) { throw "Insert-BeforeLine: '$Regex' matched $($hits.Count) lines in $Path" }
    $f.Lines.Insert($hits[0], ((ConvertTo-Eol $Text $f.Eol).TrimEnd("`r", "`n") + $f.Eol + $f.Eol))
    Save-AosFile $f
}

# Insert after the FIRST line matching $Regex.
function Insert-AfterLine([string]$Path, [string]$Regex, [string]$Text) {
    $f = Read-AosFile $Path
    $hit = -1
    for ($i = 0; $i -lt $f.Lines.Count; $i++) { if ($f.Lines[$i] -match $Regex) { $hit = $i; break } }
    if ($hit -lt 0) { throw "Insert-AfterLine: '$Regex' not found in $Path" }
    $f.Lines.Insert($hit + 1, ($f.Eol + (ConvertTo-Eol $Text $f.Eol).TrimEnd("`r", "`n") + $f.Eol))
    Save-AosFile $f
}
'@ | Set-Content (Join-Path $work 'helpers.ps1') -Encoding utf8
```

- [ ] **Step 3: Smoke-test the helpers on a throwaway CRLF file**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$t = Join-Path $work 'helper-smoke.txt'
[IO.File]::WriteAllText($t, "one`r`ntwo`r`nthree`r`nfour`r`n")
Replace-Once $t "two`nthree" "TWO-THREE"
Replace-Span $t '^one' '^TWO-THREE' 'ONE'
Remove-LinesMatching $t '^four' 1
([IO.File]::ReadAllText($t)) -replace "`r", '<CR>' -replace "`n", '<LF>'
```

Expected: `ONE<CR><LF>` (one line: the span `one..TWO-THREE` became `ONE`, `four` removed). Any exception, or a lone `<LF>` without `<CR>`, means the helpers are wrong: fix them before using them on the repo.

- [ ] **Step 4: Preflight checks**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'who' | Select-Object -First 3
Invoke-Aos 'capacity' | Tee-Object (Join-Path $bk 'capacity-start.txt')
git -C $root status -sb
```

Expected: `who` prints `no live claims`; if another session holds the agentic-os checkout, stop and tell the operator. `capacity` is recorded: note Codex's window, because Tasks 10 (diff review) and the optional Codex test authorship need it. `git status` shows branch `phone-orchestration-design` and only untracked files (`HANDOFF-media.md`, `agents-home/skills/paseo*`).

- [ ] **Step 5: Create the branch and record the base**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $root switch -c remove-paseo
(git -C $root rev-parse HEAD).Trim() | Set-Content (Join-Path $bk 'base-sha.txt')
Get-Content (Join-Path $bk 'base-sha.txt')
```

Expected: `Switched to a new branch 'remove-paseo'` and a 40-hex SHA.

- [ ] **Step 6: Baseline `aos test`** (run in the background; several minutes)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'test' *> (Join-Path $bk 'baseline-test.txt'); "exit=$LASTEXITCODE" | Add-Content (Join-Path $bk 'baseline-test.txt')
Select-String -Path (Join-Path $bk 'baseline-test.txt') -Pattern 'Tests Passed|exit=' | Select-Object -Last 2
```

Expected: `Tests Passed: N, Failed: 0` and `exit=0`. Record N. If the baseline is red, stop and report: a pre-existing failure is not part of this work, and later results would be unreadable.

- [ ] **Step 7: Report** - no commit in this task (nothing in the repo changed). Tell the operator the branch, base SHA, N, and the Codex window.

---

### Task 2: Stage 0a - nar embed commits to `main`, live checkout off the Paseo branch

**Files (nar-tools repo, not agentic-os):**
- Tag: `archive/paseo-plugin` at the tip of `phone-coordinator-live`
- Branch: `nar-embed` (worktree `~/.aos/worktrees/nar-tools-embed`), then `main` fast-forwarded to it

**Interfaces:**
- Consumes: `$nar` from `env.ps1`; the two commits `90f0614` (embedding backend and `nar classify`) and `f0895d1` (log only 200 characters per item).
- Produces: nar-tools `main` = old `main` + those two commits; the live editable install (`~/.aos/venvs/nar-tools`, source = the `$nar` working tree) runs from `main`.

- [ ] **Step 1: Preconditions**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $nar status --porcelain
git -C $nar rev-parse --abbrev-ref HEAD
git -C $nar rev-parse --short phone-coordinator-live
git -C $nar log --oneline phone-coordinator-live..main | Measure-Object | Select-Object -ExpandProperty Count
```

Expected: no status output (clean), `phone-coordinator-live`, `f0895d1`, `0` (main is 0 behind). Any difference: stop and report.

- [ ] **Step 2: Tag the old tip** (additive; makes the archive findable)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $nar tag archive/paseo-plugin phone-coordinator-live
git -C $nar rev-parse --short 'archive/paseo-plugin^{commit}'
```

Expected: `f0895d1`.

- [ ] **Step 3: Cherry-pick the two commits in a separate worktree** (the live checkout is untouched)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$wt = Join-Path $HOME '.aos\worktrees\nar-tools-embed'
git -C $nar worktree add $wt -b nar-embed main
git -C $wt cherry-pick 90f0614 f0895d1
git -C $wt log --oneline main..nar-embed
git -C $nar diff --stat phone-coordinator-live nar-embed -- . ':(exclude)paseo-plugin'
```

Expected: the log shows exactly two commits (same subjects as `90f0614` and `f0895d1`) and the `diff --stat` prints nothing (identical source outside the plugin). A cherry-pick conflict or a non-empty diff: stop and report.

- [ ] **Step 4: Run the nar-tools tests on the new branch**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$wt = Join-Path $HOME '.aos\worktrees\nar-tools-embed'
Push-Location $wt
uv run --offline pytest -q 2>&1 | Tee-Object (Join-Path $bk 'nar-tests.txt') | Select-Object -Last 5
Pop-Location
```

Expected: a final line like `N passed`. If `--offline` fails because packages are not in the uv cache, run `uv sync --dry-run` in the worktree, show the operator the package list and sizes, and download only on a yes (installs need consent with size); then repeat without `--offline`. Any test failure: stop and report.

- [ ] **Step 5: Move `main`, then the live checkout** (do this when no one is running a nar call; running `nar-mcp` processes keep their loaded code)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $nar merge-base --is-ancestor main nar-embed; "ancestor-exit=$LASTEXITCODE"
git -C $nar branch -f main nar-embed
git -C $nar switch main
git -C $nar status -sb
git -C $nar log --oneline -3
```

Expected: `ancestor-exit=0`, `## main` with no pending changes, and the two embed commits at the top of the log.

- [ ] **Step 6: Verify live nar from the venv**

```powershell
$nare = Join-Path $HOME '.aos\venvs\nar-tools\Scripts\nar.exe'
& $nare status | Select-Object -First 8
& $nare classify --backend embed --label "an invoice or payment request" --label "a poem" --item "Payment of 420 EUR is due within 30 days of receipt." --item "Roses are red, violets are blue."
"exit=$LASTEXITCODE"
```

Expected: `status` prints JSON; `classify` prints JSON with two results and `exit=0` (needs Ollama running with `bge-m3`, which is present). The first item should take the invoice label and the second the poem label; a different label is a quality hint to report, an error or non-zero exit is a stop.

- [ ] **Step 7: Report.** The worktree `~/.aos/worktrees/nar-tools-embed` (it holds a `.venv`) and the branch `nar-embed` are left in place on purpose (they are reused in Task 9). A new Claude/Codex session should call `nar_status` once (checked again in the soak, Task 5). No agentic-os commit.

---

### Task 3: Stage 0b - voice loader outside the Paseo package

**Files:**
- Create (outside the repo): `~/.aos/deps/sherpa-onnx/node_modules/{sherpa-onnx-node,sherpa-onnx-win-x64}` (a 23 MB local copy, no download)
- Modify: `templates/video/tools/make-voice.cjs:7`
- Modify: `tests/aos.Tests.ps1` (new block `Voice tool sherpa path`, inserted before `Describe 'Video input provenance'`)
- Modify (their own repos, only if unsealed and clean): `<film>/tools/make-voice.cjs`

**Interfaces:**
- Produces: the two-line loader every voice tool uses:
  ```js
  const sherpaDir = process.env.AOS_SHERPA_DIR || path.join(home, ".aos/deps/sherpa-onnx/node_modules");
  const sherpa = require(path.join(sherpaDir, "sherpa-onnx-node"));
  ```
  (`home` and `path` are already defined on the lines above it in every voice tool.)
- Produces: `$bk\voice-plan.json` (per film: Project, Files, Sealed, Dirty, Action) used by Task 8 and Task 11.

- [ ] **Step 1: Classify the film repos** (read-only)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$rows = foreach ($p in Get-ChildItem $videos -Directory) {
    $files = @('make-voice.cjs', 'audition.cjs') | ForEach-Object { Join-Path $p.FullName "tools\$_" } |
        Where-Object { (Test-Path $_) -and (Select-String -Path $_ -Pattern '@getpaseo/cli' -Quiet) }
    if (-not $files) { continue }
    $manifest = Join-Path $p.FullName 'exports\input-manifest.json'
    $sealed = (Test-Path $manifest) -and (Select-String -Path $manifest -Pattern '"exports"' -Quiet)
    $dirty = @(git -C $p.FullName status --porcelain).Count
    $action = 'repoint'
    if ($sealed) { $action = 'skip: sealed' } elseif ($dirty -gt 0) { $action = 'skip: uncommitted changes' }
    [pscustomobject]@{ Project = $p.Name; Files = (($files | Split-Path -Leaf) -join ','); Sealed = $sealed; Dirty = $dirty; Action = $action }
}
$rows | Format-Table -AutoSize
$rows | ConvertTo-Json | Set-Content (Join-Path $bk 'voice-plan.json') -Encoding utf8
```

Expected (measured 2026-10-15; re-measure, it may have changed): nine projects. `repoint`: agi-race-2, cant-escape-ai-2, where-you-end. `skip: sealed`: agi-asi-alignment, alignment-now, alignment-now-it. `skip: uncommitted changes`: alignment, alignment-3, cant-escape-ai.

- [ ] **Step 2: Copy the packages out of the Paseo install**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$srcPkg = Join-Path $HOME '.npm-global\node_modules\@getpaseo\cli\node_modules'
$dst = Join-Path $HOME '.aos\deps\sherpa-onnx\node_modules'
New-Item -ItemType Directory -Force $dst | Out-Null
foreach ($n in 'sherpa-onnx-node', 'sherpa-onnx-win-x64') {
    if (Test-Path (Join-Path $dst $n)) { throw "$n already exists in $dst" }
    Copy-Item -Recurse -LiteralPath (Join-Path $srcPkg $n) -Destination $dst
}
Get-ChildItem $dst | Select-Object Name
$pkg = Get-Content (Join-Path $dst 'sherpa-onnx-node\package.json') -Raw | ConvertFrom-Json
"$($pkg.name) $($pkg.version)" | Tee-Object (Join-Path $bk 'sherpa-version.txt')
node -e "const s=require(process.env.USERPROFILE+'/.aos/deps/sherpa-onnx/node_modules/sherpa-onnx-node');console.log(typeof s.OfflineTts)"
```

Expected: the two folder names, the package name and version (the command writes them to `$bk\sherpa-version.txt`), and `function`.

- [ ] **Step 3: Baseline render through the OLD path** (the template is still unchanged)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
@'
function Render-TestLine([string]$Label) {
    $film = Join-Path $work "film-$Label"
    if (Test-Path $film) { throw "label $Label already used" }
    New-Item -ItemType Directory -Force "$film\tools", "$film\src\data" | Out-Null
    $enc = New-Object System.Text.UTF8Encoding($false)
    $src = [IO.File]::ReadAllText((Join-Path $root 'templates\video\tools\make-voice.cjs')).Replace('{{name}}', 'scratch')
    [IO.File]::WriteAllText("$film\tools\make-voice.cjs", $src, $enc)
    [IO.File]::WriteAllText("$film\src\data\lines.json", '[{"id":"T1","text":"Testing one two three."}]', $enc)
    $env:AOS_VIDEO_MEDIA_ROOT = "$film\media"
    & node "$film\tools\make-voice.cjs" 3 1.0 | Out-Host
    return "$film\media\app\public\vo\T1.wav"
}
'@ | Set-Content (Join-Path $work 'render.ps1') -Encoding utf8
@'
const fs = require("fs");
function pcm(file) {
  const b = fs.readFileSync(file);
  const at = b.indexOf(Buffer.from("data")) + 8;
  const body = b.slice(at, at + ((b.length - at) - ((b.length - at) % 2)));
  return new Int16Array(body.buffer.slice(body.byteOffset, body.byteOffset + body.length));
}
const [a, b] = process.argv.slice(2).map(pcm);
if (a.length !== b.length) { console.log(`DIFFERENT LENGTH ${a.length} vs ${b.length}`); process.exit(1); }
let max = 0;
for (let i = 0; i < a.length; i++) max = Math.max(max, Math.abs(a[i] - b[i]));
console.log(`samples=${a.length} maxDiff=${max}`);
process.exit(max <= 2 ? 0 : 1);
'@ | Set-Content (Join-Path $work 'compare-wav.cjs') -Encoding utf8
. (Join-Path $work 'render.ps1')
$old = Render-TestLine 'old'
Test-Path $old
(Get-FileHash $old).Hash | Set-Content (Join-Path $bk 'wav-old.sha256')
```

Expected: the script prints `T1: <seconds> s` and `total ...`, then `True`. If the render fails (model missing, node error), stop: Stage 0b cannot be checked without a baseline.

- [ ] **Step 4: Write the failing test** (insert before `Describe 'Video input provenance'`)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$block = @'
Describe 'Voice tool sherpa path' {
    BeforeAll {
        $voiceTool = Join-Path $PSScriptRoot '..\templates\video\tools\make-voice.cjs'
        function Get-SherpaLoader {
            $t = [IO.File]::ReadAllText($voiceTool)
            $a = [regex]::Match($t, '(?m)^const sherpaDir = .*$').Value.TrimEnd()
            $b = [regex]::Match($t, '(?m)^const sherpa = require\(.*$').Value.TrimEnd()
            if (-not $a -or -not $b) { throw 'make-voice.cjs has no sherpaDir / sherpa loader lines' }
            return ($a + "`n" + $b)
        }
        function New-FakeSherpa([string]$Dir, [string]$Marker) {
            Write-TestFile (Join-Path $Dir 'sherpa-onnx-node\index.js') ("module.exports = { marker: '" + $Marker + "' };")
        }
        function Invoke-SherpaLoader([string]$UserProfile, [string]$Override) {
            $js = 'const path = require("path"); const home = process.env.USERPROFILE;' + "`n" + (Get-SherpaLoader) + "`n" + 'console.log(sherpa.marker);'
            $saved = @{ P = $env:USERPROFILE; D = $env:AOS_SHERPA_DIR }
            $ErrorActionPreference = 'Continue'
            try {
                $env:USERPROFILE = $UserProfile
                if ($Override) { $env:AOS_SHERPA_DIR = $Override } else { Remove-Item Env:AOS_SHERPA_DIR -ErrorAction SilentlyContinue }
                return ((& node -e $js 2>&1 | Out-String).Trim())
            }
            finally {
                $env:USERPROFILE = $saved.P
                if ($null -ne $saved.D) { $env:AOS_SHERPA_DIR = $saved.D } else { Remove-Item Env:AOS_SHERPA_DIR -ErrorAction SilentlyContinue }
            }
        }
    }

    It 'loads the module from AOS_SHERPA_DIR when that is set' {
        $dir = Join-Path $caseRoot 'override'
        New-FakeSherpa $dir 'from-env'
        Invoke-SherpaLoader -UserProfile (Join-Path $caseRoot 'nobody') -Override $dir | Should -Be 'from-env'
    }
    It 'otherwise loads it from .aos/deps/sherpa-onnx/node_modules under the user profile' {
        $profileDir = Join-Path $caseRoot 'profile'
        New-FakeSherpa (Join-Path $profileDir '.aos\deps\sherpa-onnx\node_modules') 'from-deps'
        Invoke-SherpaLoader -UserProfile $profileDir -Override '' | Should -Be 'from-deps'
    }
    It 'fails with an error that names the path it tried when nothing is installed' {
        $profileDir = Join-Path $caseRoot 'empty'
        New-TestFolder $profileDir | Out-Null
        Invoke-SherpaLoader -UserProfile $profileDir -Override '' | Should -Match 'deps.sherpa-onnx.node_modules.sherpa-onnx-node'
    }
}
'@
Insert-BeforeLine (Join-Path $root 'tests\aos.Tests.ps1') "^Describe 'Video input provenance' \{" $block
```

(`Write-TestFile`, `New-TestFolder` and `$caseRoot` come from the suite's own `BeforeAll`/`BeforeEach`; the block must sit inside the outer `Describe 'aos isolated suite'`, which `Insert-BeforeLine` guarantees by anchoring on an inner Describe.)

- [ ] **Step 5: Add the opt-in test filter to the runner** (needed to run one block; own small change)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
Replace-Once (Join-Path $root 'tests\Run-Tests.ps1') "`$config.Output.Verbosity = 'Detailed'" "`$config.Output.Verbosity = 'Detailed'`n# Opt-in: AOS_TEST_FILTER (a wildcard on the full test name) runs only the matching tests.`nif (`$env:AOS_TEST_FILTER) { `$config.Filter.FullName = `$env:AOS_TEST_FILTER }"
git -C $root diff --stat
```

Expected: `tests/Run-Tests.ps1` shows +3 lines.

- [ ] **Step 6: Run the new block - it must fail**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Voice tool sherpa path*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'red-voice.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
Select-String -Path (Join-Path $work 'red-voice.txt') -Pattern 'Tests Passed|no sherpaDir'
```

Expected: `exit=1`, three failures, message `make-voice.cjs has no sherpaDir / sherpa loader lines`. (Exit 3 = the filter matched nothing: fix the insertion.)

- [ ] **Step 7: Change the template**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$old = 'const sherpa = require(path.join(home, ".npm-global/node_modules/@getpaseo/cli/node_modules/sherpa-onnx-node"));'
$new = "const sherpaDir = process.env.AOS_SHERPA_DIR || path.join(home, `".aos/deps/sherpa-onnx/node_modules`");`nconst sherpa = require(path.join(sherpaDir, `"sherpa-onnx-node`"));"
Replace-Once (Join-Path $root 'templates\video\tools\make-voice.cjs') $old $new
node --check (Join-Path $root 'templates\video\tools\make-voice.cjs'); "check-exit=$LASTEXITCODE"
```

Expected: `check-exit=0`.

- [ ] **Step 8: Run the block again - it must pass; then compare renders**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Voice tool sherpa path*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'green-voice.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
. (Join-Path $work 'render.ps1')
$new = Render-TestLine 'new'
$oldWav = Join-Path $work 'film-old\media\app\public\vo\T1.wav'
node (Join-Path $work 'compare-wav.cjs') $oldWav $new; "compare-exit=$LASTEXITCODE"
```

Expected: `exit=0` for the tests (3 passed), and `samples=<n> maxDiff=<0-2>` with `compare-exit=0`. A length difference or `maxDiff` above 2: stop - the copied packages do not behave like the originals.

- [ ] **Step 9: Repoint the eligible films** (one commit per film repo, that file only)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$oldLine = 'const sherpa = require(path.join(home, ".npm-global/node_modules/@getpaseo/cli/node_modules/sherpa-onnx-node"));'
$newLines = "const sherpaDir = process.env.AOS_SHERPA_DIR || path.join(home, `".aos/deps/sherpa-onnx/node_modules`");`nconst sherpa = require(path.join(sherpaDir, `"sherpa-onnx-node`"));"
$plan = Get-Content (Join-Path $bk 'voice-plan.json') -Raw | ConvertFrom-Json
foreach ($r in @($plan | Where-Object { $_.Action -eq 'repoint' })) {
    $repo = Join-Path $videos $r.Project
    # Re-check right before editing: still clean and still unsealed (a film sealed after Step 1 must not be touched).
    if (@(git -C $repo status --porcelain).Count -gt 0) { Write-Warning "$($r.Project) became dirty: skipped"; continue }
    $manifest = Join-Path $repo 'exports\input-manifest.json'
    if ((Test-Path $manifest) -and (Select-String -Path $manifest -Pattern '"exports"' -Quiet)) { Write-Warning "$($r.Project) is sealed now: skipped"; continue }
    # Baseline: render the film's first line through the OLD path into a scratch folder. VO_OUT makes the tool
    # leave the film's own src/data/vo.json alone.
    $id = @(Get-Content (Join-Path $repo 'src\data\lines.json') -Raw | ConvertFrom-Json)[0].id
    $oldWav = Join-Path $work "voice-$($r.Project)-old\$id.wav"
    $newWav = Join-Path $work "voice-$($r.Project)-new\$id.wav"
    $tool = Join-Path $repo 'tools\make-voice.cjs'
    $env:VO_OUT = Split-Path $oldWav -Parent
    & node $tool 3 1.0 $id | Out-Host
    $ok = ($LASTEXITCODE -eq 0) -and (Test-Path $oldWav)
    Remove-Item Env:VO_OUT
    if (-not $ok) { Write-Warning "$($r.Project): the old-path render failed, film left alone"; continue }
    foreach ($name in ($r.Files -split ',')) {
        $file = Join-Path $repo "tools\$name"
        Replace-Once $file $oldLine $newLines
        node --check $file
        if ($LASTEXITCODE -ne 0) { throw "$file does not parse" }
        $js = 'const path=require("path");const home=process.env.USERPROFILE;' + ([regex]::Match([IO.File]::ReadAllText($file), '(?m)^const sherpaDir = .*$').Value.TrimEnd()) + ([regex]::Match([IO.File]::ReadAllText($file), '(?m)^const sherpa = require\(.*$').Value.TrimEnd()) + 'console.log(typeof sherpa.OfflineTts)'
        "$($r.Project)\$name -> " + (& node -e $js)
        git -C $repo add "tools/$name"
    }
    # Same line through the NEW path: the samples must match the baseline.
    $env:VO_OUT = Split-Path $newWav -Parent
    & node $tool 3 1.0 $id | Out-Host
    Remove-Item Env:VO_OUT
    node (Join-Path $work 'compare-wav.cjs') $oldWav $newWav
    if ($LASTEXITCODE -ne 0) { throw "$($r.Project): the new render differs from the old one. Restore the clean file with: git -C `"$repo`" checkout -- tools   - then stop and report." }
    git -C $repo commit -m "tools: load sherpa-onnx from ~/.aos/deps/sherpa-onnx (the Paseo package it came from is being removed)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
}
```

Expected: for each eligible film a line `<film>\make-voice.cjs -> function`, then `samples=<n> maxDiff=<0-2>`, then one commit. A film that became dirty or sealed, or whose old-path render fails, is skipped with a warning and left untouched (it keeps its skip status for the operator).

- [ ] **Step 10: Scan what is left**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Get-ChildItem $videos -Recurse -Include make-voice.cjs, audition.cjs -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node_modules' } |
    Where-Object { Select-String -Path $_.FullName -Pattern '@getpaseo/cli' -Quiet } |
    Select-Object -ExpandProperty FullName
Get-ChildItem (Join-Path $root 'templates\video') -Recurse -File | Select-String -Pattern '@getpaseo/cli' -List | Select-Object -ExpandProperty Path
```

Expected: only the files of films whose Action was `skip`, and nothing under `templates\video`. Save the list: `... | Set-Content (Join-Path $bk 'voice-leftovers.txt')`.

- [ ] **Step 11: Full test run, then commit the repo changes**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'test' *> (Join-Path $work 'stage0-test.txt'); "exit=$LASTEXITCODE"
Select-String -Path (Join-Path $work 'stage0-test.txt') -Pattern 'Tests Passed' | Select-Object -Last 2
```

Expected: `exit=0`, `Failed: 0`, passed count = the baseline N + 3. The template's own pipeline checks (`Video input provenance`, `pipeline.test.mjs`) run inside this suite. Then:

```powershell
git -C $root add tests/Run-Tests.ps1 tests/aos.Tests.ps1 templates/video/tools/make-voice.cjs
git -C $root commit -m "video template: load sherpa-onnx from ~/.aos/deps/sherpa-onnx (AOS_SHERPA_DIR overrides); tests/Run-Tests.ps1: opt-in AOS_TEST_FILTER" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Stage 0 checkpoint (operator)

- [ ] **Step 1: Report to the operator** the results: nar-tools `main` has the embed commits and live nar passed `status` and `classify`; sherpa copied (version from `sherpa-version.txt`); old and new renders identical (`samples`/`maxDiff`); which films were repointed (one commit each) and which were skipped and why (`voice-plan.json`, `voice-leftovers.txt`).
- [ ] **Step 2: Ask the operator two things** and wait: (a) for the skipped films, **leave** them (the old path dies in Stage 3; re-voicing a sealed film needs a new seal anyway) or **keep a junction** at the old Paseo path (Task 11 creates it); (b) permission to start Stage 1. Record the answers in `$bk\decisions.txt` as two lines: `skipped-films=leave` or `skipped-films=junction`, and `stage1=go` (Task 11 reads the first).

---

## Stage 1 - stop it (machine only, reversible)

### Task 5: Unregister, stop, park the skills, soak

**Files:** none in the repo. Machine state: scheduled task `agentic-os Paseo daemon`; the daemon; 18 skill directories in `~/.claude/skills`, `~/.codex/skills`, `<repo>/agents-home/skills`.

**Interfaces:**
- Produces: `$bk\skills-manifest.json` (18 rows `place, name, from, to`), `$bk\rollback.ps1`, `$bk\soak.md`.

- [ ] **Step 1: Write the manifest and rollback script BEFORE moving anything**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$places = [ordered]@{
    claude = Join-Path $HOME '.claude\skills'
    codex  = Join-Path $HOME '.codex\skills'
    repo   = Join-Path $root 'agents-home\skills'
}
$names = 'paseo', 'paseo-advisor', 'paseo-committee', 'paseo-handoff', 'paseo-help', 'paseo-plugin'
$manifest = foreach ($k in $places.Keys) { foreach ($n in $names) {
    [pscustomobject]@{ place = $k; name = $n; from = (Join-Path $places[$k] $n); to = (Join-Path $bk "skills\$k\$n") } } }
if (@($manifest).Count -ne 18) { throw 'manifest is not 18 rows' }
foreach ($r in $manifest) {
    $i = Get-Item -LiteralPath $r.from -Force -ErrorAction Stop
    if (-not $i.PSIsContainer -or $i.LinkType) { throw "$($r.from) is not a real directory" }
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $bk 'skills-manifest.json') -Encoding utf8
@'
# Restores the 18 parked skill directories, then tells you the next command.
$m = Get-Content "$PSScriptRoot\skills-manifest.json" -Raw | ConvertFrom-Json
foreach ($r in $m) {
    if (-not (Test-Path -LiteralPath $r.to)) { Write-Warning "missing in backup: $($r.to)"; continue }
    if (Test-Path -LiteralPath $r.from) { throw "$($r.from) already exists; not overwriting" }
    Move-Item -LiteralPath $r.to -Destination $r.from
}
$bad = @($m | Where-Object { -not (Test-Path -LiteralPath $_.from) -or (Get-Item -LiteralPath $_.from -Force).LinkType })
if ($bad.Count) { Write-Warning "$($bad.Count) paths are missing or are links (aos sync may have replaced them)" } else { Write-Host '18 skill directories restored as real directories.' }
Write-Host 'Now run: aos install phone   (re-creates the logon task and starts the daemon)'
'@ | Set-Content (Join-Path $bk 'rollback.ps1') -Encoding utf8
Get-ChildItem $bk | Select-Object Name
```

Expected: no exception (all 18 are real directories); `skills-manifest.json` and `rollback.ps1` listed.

- [ ] **Step 2: Capture the "before" state**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$paseo = Join-Path $HOME '.npm-global\paseo.cmd'
Get-ScheduledTask -TaskName 'agentic-os Paseo daemon' | Select-Object TaskName, State | Out-File (Join-Path $bk 'task-before.txt')
& $paseo daemon status 2>&1 | Out-File (Join-Path $bk 'daemon-before.txt')
Get-Content (Join-Path $bk 'daemon-before.txt') | Select-Object -First 6
```

- [ ] **Step 3: Unregister the task FIRST, then stop the daemon** (the task repeats every 5 minutes and would restart it)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$paseo = Join-Path $HOME '.npm-global\paseo.cmd'
Unregister-ScheduledTask -TaskName 'agentic-os Paseo daemon' -Confirm:$false
Get-ScheduledTask -TaskName 'agentic-os Paseo daemon' -ErrorAction SilentlyContinue
& $paseo daemon stop 2>&1
& $paseo daemon status 2>&1 | Select-Object -First 6
```

Expected: `Get-ScheduledTask` prints nothing; the status text no longer says `localDaemon: running`.

- [ ] **Step 4: Verify nothing else relaunches it** (right now; repeat in Step 7)

```powershell
Get-NetTCPConnection -LocalPort 6767 -State Listen -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'paseo' -and $_.ProcessId -ne $PID } | Select-Object ProcessId, Name
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) | Select-String -Pattern 'paseo' -SimpleMatch
Get-ChildItem ([Environment]::GetFolderPath('Startup')) | Where-Object Name -match 'paseo'
Get-ScheduledTask | Where-Object { (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ') -match 'paseo' } | Select-Object TaskName
```

Expected: all five print nothing (the process query may show this very shell's helper processes; ignore any whose command line is your own query). A hit is a second launcher: report it before continuing.

- [ ] **Step 5: Park the 18 skill directories** (a move; the manifest drives it)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$m = Get-Content (Join-Path $bk 'skills-manifest.json') -Raw | ConvertFrom-Json
foreach ($r in $m) {
    New-Item -ItemType Directory -Force (Split-Path $r.to -Parent) | Out-Null
    if (Test-Path -LiteralPath $r.to) { throw "$($r.to) already exists" }
    Move-Item -LiteralPath $r.from -Destination $r.to
}
foreach ($d in (Join-Path $HOME '.claude\skills'), (Join-Path $HOME '.codex\skills'), (Join-Path $HOME '.agents\skills')) { "$d : " + @(Get-ChildItem $d -Filter 'paseo*' -ErrorAction SilentlyContinue).Count }
git -C $root status --short | Select-Object -First 5
```

Expected: three counts of `0`. `git status` still lists only `HANDOFF-media.md` as untracked (the `paseo*` directories were untracked and are gone).

- [ ] **Step 6: Preview `aos sync` (read only)**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'sync -DryRun' *> (Join-Path $bk 'sync-dryrun-stage1.txt')
Select-String -Path (Join-Path $bk 'sync-dryrun-stage1.txt') -Pattern 'paseo' -SimpleMatch | Select-Object -First 8
```

Expected: no line proposes to link or create `paseo*` skills. Lines about Paseo being unreachable (Places registration) are expected until Stage 2. Do **not** run `aos sync` for real, `aos install phone`, `aos install all` or `bootstrap.ps1` during the soak: the unchanged code would re-create the task. Show the operator any unrelated drift the preview reports (the last full sync was 2026-10-12).

- [ ] **Step 7: Soak - operator-driven; write `$bk\soak.md` and tick each line**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
@'
# Stage 1 soak checklist (tick with the date)
- [ ] Right after the stop: no listener on 6767, no paseo process (Task 5 step 4)
- [ ] 6+ minutes later: same checks again (past one task repeat)
- [ ] A NEW Claude session: the skill list has no paseo* entries, and nar_status works
- [ ] A NEW Codex session: no paseo* skills
- [ ] After the next sign-in or reboot: no listener on 6767, no paseo process, skills still absent
- [ ] Phone: open Claude app > Code and see/follow a PC session (the premise of the removal)
- [ ] aos test is green (run once during the soak)
'@ | Set-Content (Join-Path $bk 'soak.md') -Encoding utf8
```

If the skills reappear in any of the three places, stop: something writes them (candidates: a Paseo desktop-app install, a Claude/Codex plugin sync). Find the writer before Stage 2. Rollback at any time: `& "$bk\rollback.ps1"`, then `aos install phone`.

- [ ] **Step 8: Hand over to the operator.** Stop. Stage 2 starts on the operator's word, after the soak list is ticked.

---

## Stage 2 - remove from the repo (branch `remove-paseo`)

### Task 6: Remove the phone layer, the daemon and plugin code, and their tests

**Files:**
- Modify: `aos.psm1` (delete `Install-AosPhone` through `Sync-AosPaseo`; lines 10, 432, 819, 1432, 1558, 2389)
- Modify: `packages.json` (the `phone_npm` list; the Pi row's `why`)
- Modify: `bootstrap.ps1` (usage line, `ValidateSet`)
- Modify: `tests/aos.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 helpers; `Install-AosLayer -Layer <name>` warns `unknown layer '<name>' (choose from: ...)` and returns for a name not in `$script:Layers`.
- Produces: `$script:Layers` without `phone`; no function whose name contains `Paseo`, `AosPhone` or `AosLogonTask` except the two Places helpers removed in Task 7.

- [ ] **Step 1: Write the failing test** (insert before `Describe 'Codex local profile'`)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$block = @'
Describe 'Removed phone layer' {
    It 'is not an install layer any more' {
        InModuleScope aos { $script:Layers | Should -Not -Contain 'phone' }
    }

    It 'is rejected as an unknown layer and installs nothing' {
        foreach ($f in 'Install-AosBase', 'Install-AosEngines', 'Sync-AosBrain', 'Install-AosBridges', 'Sync-AosRefs',
                       'Install-AosLocal', 'Install-AosMedia', 'Install-AosNpmTools', 'Show-AosNextSteps') { Mock $f -ModuleName aos { } }
        Mock Write-AosWarn -ModuleName aos { }
        InModuleScope aos { Install-AosLayer -Layer phone }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match "unknown layer 'phone'" }
        foreach ($f in 'Install-AosBase', 'Install-AosEngines', 'Sync-AosBrain', 'Install-AosBridges', 'Sync-AosRefs',
                       'Install-AosLocal', 'Install-AosMedia', 'Install-AosNpmTools') { Should -Invoke $f -ModuleName aos -Times 0 -Exactly }
    }

    It 'leaves no phone package list in packages.json' {
        $pk = Get-Content (Join-Path $PSScriptRoot '..\packages.json') -Raw | ConvertFrom-Json
        $pk.PSObject.Properties.Name | Should -Not -Contain 'phone_npm'
    }
}
'@
Insert-BeforeLine (Join-Path $root 'tests\aos.Tests.ps1') "^Describe 'Codex local profile' \{" $block
```

(The suite's `BeforeEach` already mocks `Test-AosCommand` to `$false` and `Invoke-AosCapture` to throw, so the red run cannot reach a real `paseo` or `npm`.)

- [ ] **Step 2: Run it - it must fail**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Removed phone layer*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'red-layer.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
Select-String -Path (Join-Path $work 'red-layer.txt') -Pattern 'Tests Passed'
```

Expected: `exit=1`, `Failed: 3` (all three: `phone` is still a layer, the warning is never raised, `phone_npm` still exists).

- [ ] **Step 3: Delete the phone layer and daemon code from `aos.psm1`**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$f = Join-Path $root 'aos.psm1'
# 14 functions in one contiguous span: Install-AosPhone ... Sync-AosPaseo (the next function is Get-AosPiDir)
Replace-Span $f '^function Install-AosPhone' '^function Get-AosPiDir' -ExclusiveEnd
Replace-Once $f "'media', 'phone')" "'media')"
Remove-LinesMatching $f "^\s+'phone'\s+\{ Install-AosPhone" 1
Replace-Once $f "# The command it installs: a scoped package (@getpaseo/cli) installs paseo.cmd, not its own name." "# The command it installs: a scoped package (@scope/name) installs <bin>.cmd, not its own name."
Replace-Once $f "Write-AosStep 'Places (shared folders and Paseo projects)'" "Write-AosStep 'Places (shared folders)'"
Replace-Once $f "# Pi on the local model, for Paseo's pi provider. aos owns providers.aos" "# Pi on the local model. aos owns providers.aos"
Replace-Once $f "Local\ mutexes are per logon session, and the Paseo daemon,`n    # scheduled tasks and hooks can run elsewhere." "Local\ mutexes are per logon session, and scheduled`n    # tasks and hooks can run elsewhere."
Select-String -Path $f -Pattern '^function .*(Paseo|AosPhone|LogonTask)' | ForEach-Object { $_.Line }
```

Expected: the last command lists only `Get-AosPaseoProjectPaths` and `Register-AosPaseoPlace` (removed in Task 7). The `Replace-Once` for the mutex comment must succeed on the first try; if the comment's wrapping differs from the text above, read lines 2386-2392 of `aos.psm1` and match them exactly.

- [ ] **Step 4: `packages.json` and `bootstrap.ps1`**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$p = Join-Path $root 'packages.json'
Replace-Span $p '^\s+"phone_npm": \[' '^\s+\],\s*$'
Replace-Once $p 'Pi: the agent harness on the local model, run by Paseo''s pi provider (config in ~\\.pi\\agent)' 'Pi: the agent harness on the local model (config in ~\\.pi\\agent)'
Get-Content $p -Raw | ConvertFrom-Json | Out-Null    # still valid JSON
$b = Join-Path $root 'bootstrap.ps1'
Remove-LinesMatching $b '^\s+phone\s+Paseo, the daemon' 1
Replace-Once $b "'media', 'phone')]" "'media')]"
Select-String -Path $b -Pattern 'phone' -SimpleMatch
```

Expected: no JSON error; the last command prints nothing.

- [ ] **Step 5: Edit and delete tests**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$t = Join-Path $root 'tests\aos.Tests.ps1'
foreach ($n in 'Phone layer', 'Paseo config', 'Paseo aos plugin', 'Paseo daemon at logon', 'Logon task state', 'Paseo daemon startup', 'Paseo daemon logon command') { Remove-Describe $t $n }
# the scoped-package example keeps its meaning with a neutral name
Replace-Once $t '# A scoped package (@getpaseo/cli) installs paseo.cmd, never "@getpaseo/cli.cmd".' '# A scoped package (@example/tool) installs exampletool.cmd, never "@example/tool.cmd".'
Replace-Once $t "'npm install -g @getpaseo/cli*'" "'npm install -g @example/tool*'"
Replace-Once $t "(Join-Path `$npmPrefix 'paseo.cmd')" "(Join-Path `$npmPrefix 'exampletool.cmd')"
Replace-Once $t "name = '@getpaseo/cli'; bin = 'paseo'" "name = '@example/tool'; bin = 'exampletool'"
# the 'Media layer' mock list names a function that no longer exists
Replace-Once $t "'Install-AosPhone', " ''
Select-String -Path $t -Pattern 'Paseo|getpaseo|AosPhone|LogonTask' -CaseSensitive:$false | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

Expected: the remaining matches are only in `Describe 'Places registration'` and `'Places commands'` (Task 7): `Register-AosPaseoPlace`, `Get-AosPaseoProjectPaths`, the `'paseo'` command mocks and the status test. Anything elsewhere: remove or rewrite it the same way and re-run the listing.

- [ ] **Step 6: Run the new block - it must pass; then the whole suite**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Removed phone layer*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'green-layer.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
Invoke-Aos 'test' *> (Join-Path $work 'task6-test.txt'); "exit=$LASTEXITCODE"
Select-String -Path (Join-Path $work 'task6-test.txt') -Pattern 'Tests Passed|ASCII|parse' | Select-Object -Last 4
```

Expected: both `exit=0`. The whole suite's `aos.psm1`/`bootstrap.ps1` ASCII and parse checks pass under 5.1 and 7; the places tests that still mention Paseo pass for now because `Get-AosPaseoProjectPaths`/`Register-AosPaseoPlace` still exist. Record the passed count.

- [ ] **Step 7: Commit**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $root add aos.psm1 packages.json bootstrap.ps1 tests/aos.Tests.ps1
git -C $root commit -m "Remove the phone layer: Paseo daemon, logon task, plugin sync, packages and their tests" -m "aos install phone is now an unknown layer. Seven test blocks go with the code they covered." -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Places stops registering with Paseo

**Files:**
- Modify: `aos.psm1` (`Sync-AosPlaces`, `Show-AosPlacesStatus`; delete `Get-AosPaseoProjectPaths`, `Register-AosPaseoPlace`)
- Modify: `tests/aos.Tests.ps1` (replace `Describe 'Places registration'`; rewrite one case in `Describe 'Places commands'`)

**Interfaces:**
- Consumes: `Sync-AosPlaces [-DryRun]`, `Show-AosPlacesStatus`, `Get-AosPlaces`, `Get-AosStateDir` (unchanged).
- Produces: neither function calls `Test-AosCommand` or `Invoke-AosCapture`.

- [ ] **Step 1: Replace the registration tests with the new ones (red first)**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$t = Join-Path $root 'tests\aos.Tests.ps1'
Remove-Describe $t 'Places registration'
$block = @'
Describe 'Places sync' {
    BeforeEach {
        Mock Get-AosStateDir -ModuleName aos { $caseRoot }
        Mock Get-AosPlaces -ModuleName aos { @([ordered]@{ name='repo'; kind='repo'; path=$caseRoot; exists=$true }) }
        # Even when every command looks installed, Places sync must not consult or call anything external.
        Mock Test-AosCommand -ModuleName aos { $true }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=1; Text='offline' } }
        Mock Write-AosWarn -ModuleName aos { }
    }
    It 'persists the local registry without calling any external command' {
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
        Test-Path (Join-Path $caseRoot 'places.json') | Should -BeTrue
    }
    It 'skips absent configuration' {
        Mock Get-AosPlaces -ModuleName aos { $null }
        { InModuleScope aos { Sync-AosPlaces } } | Should -Not -Throw
        Test-Path (Join-Path $caseRoot 'places.json') | Should -BeFalse
    }
    It 'previews an existing folder without writing the registry' {
        InModuleScope aos { Sync-AosPlaces -DryRun }
        Test-Path (Join-Path $caseRoot 'places.json') | Should -BeFalse
    }
    It 'runs Places sync from brain sync and passes preview through' {
        foreach ($f in 'Set-AosJunction','Sync-AosClaudeSkills','Set-AosManagedBlock','Sync-AosCodexAgents','Sync-AosClaudeSettings','Sync-AosCodexProfiles','Sync-AosLocalState','Sync-AosAgentModel','Sync-AosPi','Sync-AosMcp','Sync-AosProfile','Sync-AosPlaces') { Mock $f -ModuleName aos { } }
        InModuleScope aos { Sync-AosBrain -DryRun }
        Should -Invoke Sync-AosPlaces -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}
'@
Insert-BeforeLine $t "^Describe 'Places persistence' \{" $block
# the status case: no Paseo mock, and it must not call anything external
Replace-Span $t "^\s+It 'shows each place and whether Paseo knows it in aos status' \{" '^\s+\}\s*$' @'
    It 'shows each place in aos status without calling any external command' {
        Mock Test-AosCommand -ModuleName aos { $true }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=1; Text='offline' } }
        InModuleScope aos { Show-AosPlacesStatus }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'in' -and $Text -match 'missing' }
    }
'@
```

(`Mock Invoke-AosCapture` answers `Code=1` so that, in the red run, the still-present registration code takes its "listing failed" path and can never reach the real `paseo project create`.)

- [ ] **Step 2: Run the two blocks - they must fail**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Places sync*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'red-places.txt'); "exit=$LASTEXITCODE"
$env:AOS_TEST_FILTER = '*without calling any external command*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'red-places2.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
```

Expected: both `exit=1`. The `persists the local registry...` case and the `shows each place in aos status...` case fail because `Invoke-AosCapture` was called once (the `project ls`).

- [ ] **Step 3: Remove the Paseo code from Places**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$f = Join-Path $root 'aos.psm1'
# the two Paseo helpers sit right before Sync-AosPlaces
Replace-Span $f '^function Get-AosPaseoProjectPaths' '^function Sync-AosPlaces' -ExclusiveEnd
# the registration block inside Sync-AosPlaces: from the Test-AosCommand paseo line to the closing brace of its else
Replace-Span $f "^\s+if \(-not \(Test-AosCommand paseo\)\) \{ Write-AosInfo 'paseo is not installed: Places registration skipped' \}" '^\s{4}\}\s*$'
# the status function, whole: no external lookup any more
Replace-Span $f '^function Show-AosPlacesStatus' '^function Invoke-AosPlace' @'
function Show-AosPlacesStatus {
    $places = Get-AosPlaces
    if ($null -eq $places) { Write-AosInfo 'no config/places.json'; return }
    foreach ($p in $places) {
        if (-not $p['exists']) { Write-AosWarn "$($p['name']) missing: $($p['path'])"; continue }
        Write-AosOk "$($p['name']) ($($p['kind']))"
    }
}
'@ -ExclusiveEnd
Get-Content $f | Select-String -Pattern 'paseo' -CaseSensitive:$false
```

Expected: the last command prints nothing. If a `Replace-Span` throws "matched 0 lines" the surrounding text differs from the repo: open the function (`Select-String -Path $f -Pattern 'function Sync-AosPlaces' -Context 0,30`) and adjust the regex to the real lines; do not edit by guessing.

- [ ] **Step 4: Read the two functions once**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Select-String -Path (Join-Path $root 'aos.psm1') -Pattern '^function Sync-AosPlaces|^function Show-AosPlacesStatus' -Context 0,22 | ForEach-Object { $_.Context.PostContext }
```

Expected: `Sync-AosPlaces` goes from the `foreach ($place in $places)` existence loop straight to `$path = Join-Path (Get-AosStateDir) 'places.json'` and the `Set-AosJsonFile` call; `Show-AosPlacesStatus` prints `name (kind)` for existing places and `name missing: path` for absent ones. Braces balance (the parse check in the next step proves it).

- [ ] **Step 5: Run the blocks - green - then the whole suite**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Places*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'green-places.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
Invoke-Aos 'test' *> (Join-Path $work 'task7-test.txt'); "exit=$LASTEXITCODE"
Select-String -Path (Join-Path $work 'task7-test.txt') -Pattern 'Tests Passed' | Select-Object -Last 2
Select-String -Path (Join-Path $root 'tests\aos.Tests.ps1'), (Join-Path $root 'aos.psm1') -Pattern 'paseo' -CaseSensitive:$false
```

Expected: both `exit=0`; the final `Select-String` prints nothing (no Paseo left in `aos.psm1` or the tests).

- [ ] **Step 6: Commit**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $root add aos.psm1 tests/aos.Tests.ps1
git -C $root commit -m "Places: stop registering with Paseo; aos status no longer asks it" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Docs, catalogs, config and the tombstone

**Files:**
- Modify: `README.md`, `docs/routing.md`, `docs/decisions.md`, `agents-home/skills/tool-catalog/SKILL.md`, `agents-home/skills/media-tools/SKILL.md`, `refs/repos.json`, `config/pi/extensions/aos-permission-gate.ts`
- Modify (status line only): `docs/superpowers/specs/2026-09-30-phone-orchestration-design.md`, `docs/superpowers/plans/2026-09-29-paseo-and-app.md`, `docs/superpowers/plans/2026-09-30-phone-coordination-v1.md`, `docs/superpowers/plans/2026-10-04-watch-and-steer.md`
- Modify: `tests/aos.Tests.ps1` (new block `Tombstone: removed tool`, inserted before `Describe 'Inbox skill'`)

**Interfaces:**
- Consumes: `$bk\voice-plan.json` (Task 3) to write the "known leftovers" bullet.
- Produces: `git grep -I -i -l paseo` finds nothing outside `docs/decisions.md` and `docs/superpowers/**`; no tracked file outside them contains the text `install phone`.

- [ ] **Step 1: Write the tombstone test (red)**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$block = @'
Describe 'Tombstone: removed tool' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        function Get-TrackedHits([string]$Pattern, [switch]$Fixed) {
            $flags = @('-I', '-i', '-l')
            if ($Fixed) { $flags += '-F' }
            $out = & git -C $repoRoot grep @flags $Pattern -- . ':(exclude)docs/decisions.md' ':(exclude)docs/superpowers' 2>$null
            if ($LASTEXITCODE -eq 1) { return @() }
            if ($LASTEXITCODE -ne 0) { throw "git grep failed with exit code $LASTEXITCODE" }
            return @($out)
        }
    }
    # Tracked files only (working-tree contents). Machine state - untracked skills, other worktrees, ~/.claude -
    # is covered by the stage 1 and stage 3 checks, not by this test.
    It 'leaves no tracked file that names the removed tool' {
        Get-TrackedHits ('pa' + 'seo') | Should -BeNullOrEmpty
    }
    It 'documents no install layer called phone' {
        Get-TrackedHits ('install ' + 'phone') -Fixed | Should -BeNullOrEmpty
    }
}
'@
Insert-BeforeLine (Join-Path $root 'tests\aos.Tests.ps1') "^Describe 'Inbox skill' \{" $block
$env:AOS_TEST_FILTER = '*Tombstone*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'red-tombstone.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
git -C $root grep -I -i -l 'paseo' -- . ':(exclude)docs/decisions.md' ':(exclude)docs/superpowers'
```

Expected: `exit=1`; the `git grep` lists the files still to fix: `README.md`, `docs/routing.md`, `agents-home/skills/tool-catalog/SKILL.md`, `agents-home/skills/media-tools/SKILL.md`, `refs/repos.json`, `config/pi/extensions/aos-permission-gate.ts` (and nothing from `aos.psm1`/tests/templates). That list drives the next steps.

- [ ] **Step 2: README**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$r = Join-Path $root 'README.md'
Remove-LinesMatching $r '^\| \*\*phone\*\* \| Paseo:' 1
Remove-LinesMatching $r '^\| Claude Code, Codex \*\*and the local model\*\* from one app \|' 1
Remove-LinesMatching $r '^\| See agentic-os status and nar calibration; label nar''s recent choices \|' 1
Remove-LinesMatching $r '^\| Coordinate the three providers in one project conversation \|' 1
Replace-Span $r '^The local model in Paseo \(Pi\) asks before' 'paseo daemon restart`\.\s*$' @'
The local model (Pi, model `aos/aos-agent`, started with `pi` in a terminal) asks before every command or file
change it wants to make; reading files needs no approval. Its project directory is only the starting location,
not a repository sandbox: native tools run on the PC under your Windows account and can target other
user-accessible paths. Windows ACLs and the approval prompt remain the boundaries, so the model must verify paths
outside the project before changing them. The synced Pi extension also provides a small permission-gated
`web_search` tool that returns public search results with source URLs; it is a search operation, not a browser or
desktop-control bridge. It is a 4B model with a 16K context: good for small, well-defined tasks; it can misreport
what happened, so check its claims.
'@
Replace-Span $r '^`aos new` adds the created project too\. `aos sync` registers' '^If Paseo is unavailable' @'
`aos new` adds the created project too. `aos sync` writes `~/.aos/places.json` for agents and tools.
Missing folders are left absent; only a missing Inbox is created.
'@
Replace-Span $r '^The agentic-os phone panel has an Inbox box' '^Save creates a new UTF-8 Markdown file' 'Notes and links go into the Inbox with the `inbox` skill.'
Select-String -Path $r -Pattern 'paseo' -CaseSensitive:$false
```

Expected: the last command prints nothing. The `From your phone` table keeps its four first-party rows (Claude app, `aos remote`, Codex app, cloud sessions).

- [ ] **Step 3: routing.md, tool-catalog, media-tools, refs, Pi gate**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$rt = Join-Path $root 'docs\routing.md'
Replace-Once $rt 'Pi on the local model (Paseo, model `aos/aos-agent`)' 'Pi on the local model (`pi`, model `aos/aos-agent`)'
Remove-LinesMatching $rt '^\| From the phone, any of Claude Code, Codex or the local model on this PC, in one app \|' 1
$tc = Join-Path $root 'agents-home\skills\tool-catalog\SKILL.md'
Remove-LinesMatching $tc '^\| `paseo(-advisor|-committee|-handoff|-help|-plugin)?` \|' 6
Replace-Once $tc '| Pi on the local model (Paseo) | phone sessions; `web_search`' '| Pi on the local model | terminal sessions (`pi`); `web_search`'
Replace-Once $tc 'Paseo is how the phone reaches Claude, Codex and Pi on this PC.' 'From the phone, Claude and Codex are reached through their own apps (README "From your phone").'
$mt = Join-Path $root 'agents-home\skills\media-tools\SKILL.md'
Replace-Once $mt "sherpa-onnx from Paseo's install;" 'sherpa-onnx in `~\.aos\deps\sherpa-onnx`;'
Replace-Once $mt 'v0.19 model in `~\.paseo\models` (bm_george)' 'older v0.19 model (bm_george)'
$rp = Join-Path $root 'refs\repos.json'
Replace-Once $rp '"why": "Index of multi-agent cockpits and orchestrators." },' '"why": "Index of multi-agent cockpits and orchestrators." }'
Remove-LinesMatching $rp '"slug": "getpaseo/paseo"' 1
Get-Content $rp -Raw | ConvertFrom-Json | Out-Null     # still valid JSON
Replace-Once (Join-Path $root 'config\pi\extensions\aos-permission-gate.ts') ' * this asks the person: Paseo shows the dialog on the phone. With no UI to ask, the tool is blocked.' ' * this asks the person. With no UI to ask, the tool is blocked.'
git -C $root grep -I -i -l 'paseo' -- . ':(exclude)docs/decisions.md' ':(exclude)docs/superpowers'
```

Expected: the final `git grep` prints nothing. A remaining file: open it, remove or reword the reference (keep surrounding meaning), and re-run it.

- [ ] **Step 4: Status lines on the four historical documents**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$s = 'Superseded 2026-10-15: Paseo was removed from this PC and repo (`2026-10-15-remove-paseo-design.md`). Kept as history.'
foreach ($rel in 'docs\superpowers\specs\2026-09-30-phone-orchestration-design.md', 'docs\superpowers\plans\2026-09-29-paseo-and-app.md', 'docs\superpowers\plans\2026-09-30-phone-coordination-v1.md') {
    Insert-AfterLine (Join-Path $root $rel) '^# ' "> $s"
}
Insert-AfterLine (Join-Path $root 'docs\superpowers\plans\2026-10-04-watch-and-steer.md') '^# ' '> Amended 2026-10-15: Paseo was removed (`2026-10-15-remove-paseo-design.md`). T6 and the Paseo row of the watch table are cancelled; the rest stands.'
git -C $root diff --stat -- docs/superpowers | Select-Object -Last 6
```

Expected: four files, one or two added lines each.

- [ ] **Step 5: The `decisions.md` entry** (newest first: before the 2026-10-12 entry)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$left = @(Get-Content (Join-Path $bk 'voice-plan.json') -Raw | ConvertFrom-Json | Where-Object { $_.Action -ne 'repoint' })
$list = 'none'
if ($left.Count -gt 0) { $list = (($left | ForEach-Object { "$($_.Project) ($($_.Action -replace '^skip: ', ''))" }) -join ', ') }
$entry = @'
## 2026-10-15 - Paseo removed: one phone app for three providers was never used

- **Why.** Paseo (installed 2026-09-29) was meant to give one phone conversation across Claude, Codex and the
  local model. The operator never used it from the phone and defaults to the Claude desktop app. Its agent records
  all date from the 2026-09-29/30 setup and smoke tests, and the daemon was down for days (2026-09-30..10-03)
  without being missed. The orchestration the operator relies on (claims, ledger, `aos delegate`, `aos capacity`,
  the notes hook, the `handoff` and `second-opinion` skills) never ran on Paseo. This reverses the 2026-09-29
  entry "Phone access through Paseo; Pi as the local agent" and returns to the earlier position that Paseo is left
  out until a need repeats.
- **Lost, on purpose.** The local model (Pi + Ollama) from the phone; one thread that fails over between providers
  when a quota runs out (on the phone, open the other app); the agentic-os phone panel (status, nar feedback, Inbox
  box). Claude and Codex stay reachable from the phone through their own apps (README "From your phone").
- **Kept.** Pi, Ollama, nar, `aos remote`, Places (minus the Paseo registration), `aos delegate`, claims, capacity.
- **Hidden dependencies cut first.** The live `nar` is an editable install of the nar-tools checkout, which sat on
  a Paseo-named branch: its two embedding-backend commits moved to nar-tools `main` and the old tip is tagged
  `archive/paseo-plugin`. Video voice loaded sherpa-onnx from inside the Paseo CLI package; it now loads from
  `~\.aos\deps\sherpa-onnx\node_modules` (`AOS_SHERPA_DIR` overrides).
- **Known leftovers.** Film repos whose `tools/make-voice.cjs` still names the removed path: KNOWN_LEFTOVERS_LIST.
  A sealed film's seal covers that file (`tools/checks/input-manifest.mjs`), so it is not edited; re-voicing one
  needs a new seal anyway. The fix is to replace the `const sherpa = require(...)` line with the two loader lines in
  `templates/video/tools/make-voice.cjs`.
- **Undo.** The skills and the removed folders are in `~\.aos-backups\remove-paseo-<stamp>`; `npm install -g
  @getpaseo/cli`, the nar-tools tag `archive/paseo-plugin` and this repo's history before the removal commits bring
  the rest back.
'@
Insert-BeforeLine (Join-Path $root 'docs\decisions.md') '^## 2026-10-12 - A second' $entry
Replace-Once (Join-Path $root 'docs\decisions.md') 'KNOWN_LEFTOVERS_LIST' $list
Select-String -Path (Join-Path $root 'docs\decisions.md') -Pattern 'KNOWN_LEFTOVERS_LIST'
```

Expected: the last command prints nothing; the entry sits above the 2026-10-12 entry and its "Known leftovers" line lists the skipped films (or `none`).

- [ ] **Step 6: Tombstone green, then the whole suite**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$env:AOS_TEST_FILTER = '*Tombstone*'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Run-Tests.ps1') *> (Join-Path $work 'green-tombstone.txt'); "exit=$LASTEXITCODE"
Remove-Item Env:AOS_TEST_FILTER
Invoke-Aos 'test' *> (Join-Path $work 'task8-test.txt'); "exit=$LASTEXITCODE"
Select-String -Path (Join-Path $work 'task8-test.txt') -Pattern 'Tests Passed' | Select-Object -Last 2
```

Expected: both `exit=0`.

- [ ] **Step 7: Commit**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
git -C $root add README.md docs agents-home/skills refs/repos.json config/pi/extensions/aos-permission-gate.ts tests/aos.Tests.ps1
git -C $root status --short
git -C $root commit -m "Docs, catalogs and config: Paseo removed; tombstone test; decisions entry" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected: `git status --short` before the commit shows only the modified tracked files (plus the untracked `HANDOFF-media.md`, which stays out of the commit).

---

### Task 9: nar-tools drops `paseo-plugin/`

**Files (nar-tools repo):** delete `paseo-plugin/` (15 tracked files on `main`).

**Interfaces:**
- Consumes: Task 2's worktree `~/.aos/worktrees/nar-tools-embed` (branch `nar-embed` = `main`, has a `.venv`) and tag `archive/paseo-plugin`.
- Produces: nar-tools `main` without `paseo-plugin/`; live nar unaffected (Python source unchanged).

- [ ] **Step 1: Remove it in the worktree and test**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$wt = Join-Path $HOME '.aos\worktrees\nar-tools-embed'
git -C $wt switch -c remove-paseo-plugin
git -C $wt rm -r -q paseo-plugin
git -C $wt status --short | Select-Object -First 3
git -C $wt diff --cached --stat -- . ':(exclude)paseo-plugin'
Push-Location $wt; uv run --offline pytest -q 2>&1 | Select-Object -Last 3; Pop-Location
```

Expected: `D  paseo-plugin/...` lines; an empty `diff --stat` outside the plugin (no Python source touched); `N passed` (the same N as Task 2).

- [ ] **Step 2: Commit and fast-forward the live checkout**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$wt = Join-Path $HOME '.aos\worktrees\nar-tools-embed'
git -C $wt commit -m "Remove paseo-plugin (archived at tag archive/paseo-plugin)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git -C $nar status --porcelain
git -C $nar merge --ff-only remove-paseo-plugin
git -C $nar ls-files paseo-plugin | Measure-Object | Select-Object -ExpandProperty Count
Get-ChildItem -Force (Join-Path $nar 'paseo-plugin') -ErrorAction SilentlyContinue | Select-Object Name, LinkType
```

Expected: `status --porcelain` prints nothing before the merge; the merge fast-forwards; the tracked count is `0`; what remains of `paseo-plugin\` is only untracked leftovers (typically a `node_modules` junction).

- [ ] **Step 3: Remove the leftover junction and empty folder** (only the link, never its target)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$dir = Join-Path $nar 'paseo-plugin'
foreach ($item in @(Get-ChildItem -Force $dir -ErrorAction SilentlyContinue)) {
    if ($item.LinkType) { [System.IO.Directory]::Delete($item.FullName, $false); "removed link $($item.Name)" }
    else { Write-Warning "left in place (not a link): $($item.FullName)" }
}
if (-not @(Get-ChildItem -Force $dir -ErrorAction SilentlyContinue)) { [System.IO.Directory]::Delete($dir, $false) }
Test-Path $dir
$nare = Join-Path $HOME '.aos\venvs\nar-tools\Scripts\nar.exe'
& $nare status | Select-Object -First 3
```

Expected: `removed link node_modules`, `False` for the folder, and `nar status` still works. Anything "left in place" is reported to the operator and left alone.

---

### Task 10: Stage 2 verification, Codex diff review, finish

**Files:** none changed unless the review finds something.

- [ ] **Step 1: Acceptance checks**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'test' *> (Join-Path $work 'final-test.txt'); "exit=$LASTEXITCODE"
Select-String -Path (Join-Path $work 'final-test.txt') -Pattern 'Tests Passed' | Select-Object -Last 2
git -C $root grep -I -i -l 'paseo' -- . ':(exclude)docs/decisions.md' ':(exclude)docs/superpowers'
Invoke-Aos 'place ls' | Select-Object -First 4
Invoke-Aos 'remote -DryRun' | Select-Object -First 4
pi --version
Invoke-Aos 'sync -DryRun' *> (Join-Path $work 'sync-dryrun-stage2.txt')
Select-String -Path (Join-Path $work 'sync-dryrun-stage2.txt') -Pattern 'paseo' -CaseSensitive:$false
```

Expected: `exit=0` with `Failed: 0` (both shells run inside `aos test`); the `git grep` and the last `Select-String` print nothing; `place ls` lists places without errors; `remote -DryRun` and `pi --version` work. `aos delegate` is covered by the suite's `Delegation preflight` and `aos delegate` blocks (green). If `Invoke-Aos 'remote -DryRun'` prompts or fails for a reason unrelated to Paseo, record it and compare against the baseline branch before blaming the removal.

- [ ] **Step 2: Capacity gate for the review**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'capacity'
```

If Codex shows a window too small for a bounded review (the spec review cost about 75K tokens), do **not** substitute a same-vendor review: record "review pending", tell the operator the numbers and the reset time, and let them choose to wait, reset the window or override. Otherwise continue.

- [ ] **Step 3: Codex reviews the diff (read-only, bounded)**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$base = (Get-Content (Join-Path $bk 'base-sha.txt')).Trim()
git -C $root diff --stat "$base..HEAD" | Out-File (Join-Path $work 'diffstat.txt')
@"
You are an independent reviewer. Read-only: edit nothing, run nothing that writes.
Review the git diff $base..HEAD in this repo (use git diff, git show, git grep only) against the spec
docs/superpowers/specs/2026-10-15-remove-paseo-design.md and the plan docs/superpowers/plans/2026-10-15-remove-paseo.md.
Check, ranked by severity with file:line and a concrete failure scenario:
1. Any behaviour that stays (Places, Pi, install dispatcher, aos status, video template, delegate) that the diff breaks.
2. Any deleted test that covered behaviour which stays (the allowed deletions are listed in the spec, Tests section 4).
3. Any remaining call to, or documentation of, the removed tool or the removed phone layer in tracked files outside docs/decisions.md and docs/superpowers.
4. aos.psm1, bootstrap.ps1, tests/Run-Tests.ps1: non-ASCII bytes; syntax not valid in Windows PowerShell 5.1 (the ?? and ternary operators, && and ||).
5. Whether the new tests (Removed phone layer, Places sync, Voice tool sherpa path, Tombstone: removed tool) can actually fail, and whether the tombstone has a hole.
Maximum 600 words. Say 'nothing found' for any item with no finding, and list anything you could not verify.
"@ | Set-Content (Join-Path $work 'codex-diff-prompt.txt') -Encoding utf8
```

Then run it from Git Bash (the `</dev/null` matters there; without it `codex exec` waits for stdin). `CODEX_MODEL` is the model that last worked on this account (memory note `codex-exec-model-and-sandbox`; the repo records no model names). Run from the agentic-os checkout:

```bash
P="$HOME/.aos/scratch/remove-paseo"
codex exec --profile review -m "$CODEX_MODEL" "$(cat "$P/codex-diff-prompt.txt")" </dev/null >"$P/codex-diff-out.txt" 2>&1; echo "exit=$?"
grep -n -i -E "usage limit|hit your" "$P/codex-diff-out.txt" | head -3
tail -n 60 "$P/codex-diff-out.txt"
```

Expected: `exit=0`, no limit line, and a findings list. A usage-limit line or non-zero exit is a failed review, not a clean one: report it. Fix every finding that is real (test-first when it is behaviour), re-run Step 1, and save Codex's text verbatim to `docs/superpowers/specs/2026-10-15-remove-paseo-codex-diff-review.md` with a disposition line per finding; commit that file.

- [ ] **Step 4: Finish the branch.** Invoke `superpowers:finishing-a-development-branch` and let the operator choose how `remove-paseo` is integrated (it was cut from `phone-orchestration-design`, which is 89 commits ahead of `main`). Stage 3 starts only after the operator's word.

---

## Stage 3 - delete what is left

### Task 11: Move the package out (junction if chosen), then the state folders, to the holding folder

**Files:** machine state only.

**Interfaces:**
- Consumes: `$bk\decisions.txt` (the Task 4 answer about skipped films), Stage 2 merged or accepted by the operator.
- Produces: `$bk\removed\` holding `.paseo`, `getpaseo-ref`, `paseo-plugin-deps`, `npm-@getpaseo` and the three `shim-*` files, for the operator to delete.

- [ ] **Step 1: Gate - voice scan and the operator's per-item yes**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Get-ChildItem $videos -Recurse -Include make-voice.cjs, audition.cjs -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node_modules' } |
    Where-Object { Select-String -Path $_.FullName -Pattern '@getpaseo/cli' -Quiet } | Select-Object -ExpandProperty FullName
Get-Content (Join-Path $bk 'decisions.txt')
"npm package : " + ('{0:N0} MB' -f ((Get-ChildItem (Join-Path $HOME '.npm-global\node_modules\@getpaseo') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB))
"paseo state : " + ('{0:N0} MB' -f ((Get-ChildItem (Join-Path $HOME '.paseo') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB))
"ref clone   : " + ('{0:N0} MB' -f ((Get-ChildItem (Join-Path $HOME '.aos\refs\watch\getpaseo') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB))
```

Expected: the files listed are exactly the skipped films' (the operator already chose leave or junction). Show the sizes and get an explicit yes for Steps 2-4 together or one by one.

- [ ] **Step 2: Move the package and its shims into the holding folder; link the old path if the operator chose that** (one script, so skipped films are never without a voice path for more than a moment)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$prefix = Join-Path $HOME '.npm-global'
$hold = Join-Path $bk 'removed'
New-Item -ItemType Directory -Force $hold | Out-Null
$scope = Join-Path $prefix 'node_modules\@getpaseo'
if ((@(Get-ChildItem $scope -Directory).Name -join ',') -ne 'cli') { throw "unexpected content in $scope" }
foreach ($n in 'paseo', 'paseo.cmd', 'paseo.ps1') { Move-Item -LiteralPath (Join-Path $prefix $n) -Destination (Join-Path $hold "shim-$n") }
Move-Item -LiteralPath $scope -Destination (Join-Path $hold 'npm-@getpaseo')
$choice = ((Get-Content (Join-Path $bk 'decisions.txt')) | Where-Object { $_ -like 'skipped-films=*' }) -replace 'skipped-films=', ''
if ($choice -eq 'junction') {
    $linkPath = Join-Path $scope 'cli\node_modules'
    New-Item -ItemType Directory -Force (Split-Path $linkPath -Parent) | Out-Null
    New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $HOME '.aos\deps\sherpa-onnx\node_modules') | Out-Null
    node -e "const s=require(process.env.USERPROFILE+'/.npm-global/node_modules/@getpaseo/cli/node_modules/sherpa-onnx-node');console.log(typeof s.OfflineTts)"
}
foreach ($n in 'paseo', 'paseo.cmd', 'paseo.ps1') { "$n : " + (Test-Path (Join-Path $prefix $n)) }
Get-Command paseo -ErrorAction SilentlyContinue
```

Expected: the three shims `False`, no `paseo` command, and (junction choice only) `function`. This replaces `npm uninstall -g`: the whole package (538 MB) is intact in the holding folder, so the undo is a move back, not a download. If the junction step fails, put everything back at once with `Move-Item (Join-Path $hold 'npm-@getpaseo') $scope` and the three `shim-*` files back to `$prefix`, then report. If the operator chose "leave", the junction block does not run: say which films will fail if re-voiced.

- [ ] **Step 3: Move the three folders into the holding folder** (a move on the same drive; nothing is deleted)

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$hold = Join-Path $bk 'removed'
New-Item -ItemType Directory -Force $hold, (Join-Path $bk 'paseo-state') | Out-Null
$cfg = Join-Path $HOME '.paseo\config.json'
if (Test-Path $cfg) {
    if (Select-String -Path $cfg -Pattern 'password|secret|token|hash|key' -Quiet) { 'config.json looks like it holds a secret: not copied' | Add-Content (Join-Path $bk 'paseo-state\NOTE.txt') }
    else { Copy-Item $cfg (Join-Path $bk 'paseo-state\config.json') }
}
Copy-Item -Recurse -LiteralPath (Join-Path $HOME '.paseo\agents') -Destination (Join-Path $bk 'paseo-state\agents')
Move-Item -LiteralPath (Join-Path $HOME '.paseo') -Destination (Join-Path $hold '.paseo')
Move-Item -LiteralPath (Join-Path $HOME '.aos\refs\watch\getpaseo') -Destination (Join-Path $hold 'getpaseo-ref')
Move-Item -LiteralPath (Join-Path $HOME '.aos\deps\paseo-plugin-0.10.1') -Destination (Join-Path $hold 'paseo-plugin-deps')
Get-ChildItem $hold -Force | Select-Object Name
foreach ($p in '.paseo', '.aos\refs\watch\getpaseo', '.aos\deps\paseo-plugin-0.10.1') { "$p : " + (Test-Path (Join-Path $HOME $p)) }
```

Expected: three names in the holding folder and `False` for the three old locations. The daemon keypair stays inside `removed\.paseo` and is never copied.

- [ ] **Step 4: Verify the machine is clean**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Get-Command paseo -ErrorAction SilentlyContinue
Get-ScheduledTask | Where-Object { (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ') -match 'paseo' }
Get-NetTCPConnection -LocalPort 6767 -State Listen -ErrorAction SilentlyContinue
foreach ($d in '.claude\skills', '.codex\skills', '.agents\skills') { "$d : " + @(Get-ChildItem (Join-Path $HOME $d) -Filter 'paseo*' -ErrorAction SilentlyContinue).Count }
```

Expected: nothing from the first three, and `0` for each skills folder.

- [ ] **Step 5: Hand the operator their two manual steps.** (a) Delete the holding folder `$bk\removed` when satisfied (about 1.8 GB; it contains the daemon keypair - deleting it also ends the phone pairing for good) and the worktree `~/.aos/worktrees/nar-tools-embed` (it holds a `.venv`). (b) Remove the Paseo app from the phone and its saved connection. The agent does not delete either.

---

### Task 12: Memory, the full `aos sync`, final acceptance

**Files (memory folder, outside the repo):** `nar-embed-backend.md`, `MEMORY.md`, new `paseo-removed.md`. `installs-need-consent-with-size.md` and `video-voice-kokoro-v1.md` mention Paseo only as dated history (an install-size measurement; the rejected v0.19 voice source) and stay unchanged (spec amendment 7, which the operator confirms with this plan).

- [ ] **Step 1: Update the memory notes**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1; . $HOME\.aos\scratch\remove-paseo\helpers.ps1
$mem = Join-Path $HOME '.claude\projects\C--Users-marin-OneDrive-Desktop-agentic-os\memory'
Replace-Once (Join-Path $mem 'nar-embed-backend.md') 'Open: a full `aos sync` was NOT run because it would relink ~/.claude/skills/paseo* to untracked repo copies.' 'Resolved by the 2026-10 Paseo removal: the paseo skills are gone and the embed commits live on nar-tools main.'
Replace-Once (Join-Path $mem 'MEMORY.md') '; full aos sync deliberately not run (paseo relink)' '; on nar-tools main since the Paseo removal'
Select-String -Path (Join-Path $mem 'nar-embed-backend.md') -Pattern 'phone-coordinator-live'
```

Expected: the last command prints nothing; if it prints a line, replace `phone-coordinator-live` with `main (nar-tools)` in that sentence.

- [ ] **Step 2: Add the removal memory and its index line**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$mem = Join-Path $HOME '.claude\projects\C--Users-marin-OneDrive-Desktop-agentic-os\memory'
@'
---
name: paseo-removed
description: Paseo (phone daemon + plugin) was removed from this PC and repo in October 2026; do not re-propose it, and where the replaced pieces live now
metadata:
  type: project
---

Paseo was removed (spec `docs/superpowers/specs/2026-10-15-remove-paseo-design.md`, decision entry 2026-10-15 in
`docs/decisions.md`). The operator never used it from the phone and defaults to the Claude desktop app.

**Why:** the need that justified it (reaching the agents from the phone) never repeated; the orchestration the
operator relies on (claims, `aos delegate`, `aos capacity`, handoff, second-opinion) never ran on it.

**How to apply:** for the phone use the Claude app (Code, Remote Control, `aos remote`) and the Codex app (Control
this PC). Do not propose Paseo or a phone panel again without a repeated need. Pi + Ollama + nar stay (PC only).
Video voice loads sherpa-onnx from `~\.aos\deps\sherpa-onnx\node_modules` (`AOS_SHERPA_DIR`); sealed films' own
`make-voice.cjs` may still name the old path (see the decisions entry). Undo material:
`~\.aos-backups\remove-paseo-<stamp>`, nar-tools tag `archive/paseo-plugin`.
'@ | Set-Content (Join-Path $mem 'paseo-removed.md') -Encoding utf8
Add-Content (Join-Path $mem 'MEMORY.md') '- [Paseo removed](paseo-removed.md) — phone daemon dropped 2026-10; phone = Claude/Codex apps; where voice sherpa and nar live now; undo path'
```

- [ ] **Step 3: The first full `aos sync` since 2026-10-12 - preview, apply, repeat**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos 'sync -DryRun' *> (Join-Path $work 'sync-final-dry.txt'); Get-Content (Join-Path $work 'sync-final-dry.txt')
```

Read the whole preview with the operator: expected changes are the ones accumulated since 2026-10-12 and nothing about Paseo. Unexpected items: stop and ask.

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
$before = @(Get-ChildItem (Join-Path $HOME '.aos-backups') -Recurse -File -ErrorAction SilentlyContinue).Count
Invoke-Aos 'sync' *> (Join-Path $work 'sync-final-1.txt'); "exit=$LASTEXITCODE"
$mid = @(Get-ChildItem (Join-Path $HOME '.aos-backups') -Recurse -File -ErrorAction SilentlyContinue).Count
Invoke-Aos 'sync' *> (Join-Path $work 'sync-final-2.txt'); "exit=$LASTEXITCODE"
$after = @(Get-ChildItem (Join-Path $HOME '.aos-backups') -Recurse -File -ErrorAction SilentlyContinue).Count
"backup files: before=$before afterFirst=$mid afterSecond=$after"
Select-String -Path (Join-Path $work 'sync-final-2.txt') -Pattern '^\s*(updated|linked|created|registered|added|wrote|backed up)' | Select-Object -First 5
git -C $root status --short
```

Expected: both syncs `exit=0`; `afterSecond` equals `afterFirst` (the second run wrote nothing, so no backup was made); the `Select-String` prints nothing; `git status` shows only `HANDOFF-media.md`. If the second run changed something, the sync is not idempotent: stop and report the lines.

- [ ] **Step 4: Final acceptance against the spec** - run each and record the result in `$bk\acceptance.md`:

| Check | Command | Expected |
|---|---|---|
| Tracked tree | `git -C $root grep -I -i -l paseo -- . ':(exclude)docs/decisions.md' ':(exclude)docs/superpowers'` | empty |
| Tests | `Invoke-Aos 'test'` | exit 0, both shells |
| Machine | Task 11 Step 4 commands | empty / `0` |
| nar | `nar.exe classify --backend embed ...` (Task 2 Step 6) | works, from `main` |
| Voice | Task 3 Step 8 compare | `maxDiff` 0-2 |
| Second sync | Step 3 | no change |
| Pi | `pi --version` | prints a version |

- [ ] **Step 5: Leave a note for other agents**

```powershell
. $HOME\.aos\scratch\remove-paseo\env.ps1
Invoke-Aos "note 'Paseo removed: daemon, task, skills, code and docs gone; nar-tools main has the embed commits; voice loads sherpa from ~/.aos/deps; first full aos sync since 10-12 done. See docs/decisions.md 2026-10-15.' --as claude"
```

- [ ] **Step 6: Report** to the operator: what was verified (with the numbers), what is left for them to delete (holding folder, nar worktree, phone app), the skipped films and their consequence.
