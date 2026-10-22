Describe 'aos ready: readiness gate before cross-vendor work' {
# Executable specification for config\readiness.ps1. Real git repositories are used on purpose; claims, capacity,
# actors and the task-path resolver are mocked so no test reads the real coordination state or a vendor home.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    function New-ReadyFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }
    function Invoke-ReadyGit([string]$Repo, [string[]]$Arguments) {
        & git -C $Repo -c user.name=Fixture -c user.email=fixture@example.invalid -c core.autocrlf=false @Arguments 2>$null | Out-Null
    }
    function New-ReadyRepo([string]$Path, [switch]$Empty) {
        New-ReadyFolder $Path | Out-Null
        Invoke-ReadyGit $Path @('init', '-q')
        if (-not $Empty) {
            [System.IO.File]::WriteAllText((Join-Path $Path 'a.txt'), "one`n")
            Invoke-ReadyGit $Path @('add', 'a.txt')
        }
        Invoke-ReadyGit $Path @('commit', '--allow-empty', '-qm', 'initial')
        return $Path
    }
    # A check function is called with named arguments inside the module.
    function Get-ReadyCheck([string]$Function, [hashtable]$Arguments) {
        InModuleScope aos -Parameters @{ F = $Function; A = $Arguments } { param($F, $A) & $F @A }
    }
    # Mock bodies are rebuilt from text because a mock runs in module scope and cannot see test variables.
    function New-ReadyCapacity([string]$Vendor, [string]$State, [int]$Remaining, [string]$Resets = '') {
        $resetsText = '$null'
        if ($Resets) { $resetsText = "[datetime]::Parse('$Resets', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)" }
        return [scriptblock]::Create("[ordered]@{ '$Vendor' = [pscustomobject]@{ vendor='$Vendor'; remaining=$Remaining; resets=$resetsText; reported=[datetime]::UtcNow; source='reported'; note=''; state='$State'; window='' } }")
    }
    function New-ReadyActors([string[]]$Rows) {
        $items = @($Rows | ForEach-Object { $p = $_ -split ':'; "[pscustomobject]@{ id='$($p[0])'; vendor='$($p[1])'; state='$($p[2])' }" })
        return [scriptblock]::Create('@(' + ($items -join ',') + ')')
    }
    $readyNow = [datetime]::SpecifyKind([datetime]'2026-10-22T10:00:00', [System.DateTimeKind]::Utc)
}

BeforeEach {
    # Short component names keep PS 5.1 TestDrive cleanup within path limits.
    $caseRoot = New-ReadyFolder (Join-Path $TestDrive ('r' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
    $savedCoord = $env:AOS_COORD
    $env:AOS_COORD = Join-Path $caseRoot 'c'
}

AfterEach {
    $env:AOS_COORD = $savedCoord
    Remove-Variable -Name ReadyTestPath -Scope Global -ErrorAction SilentlyContinue
}

Context 'repository check' {
    It 'fails outside a git repository' {
        $dir = New-ReadyFolder (Join-Path $caseRoot 'plain')
        $r = Get-ReadyCheck 'Test-AosReadinessRepository' @{ Path = $dir }
        $r.name | Should -Be 'repository'
        $r.status | Should -Be 'fail'
        $r.detail | Should -Match 'not a git repository'
    }
    It 'is ok for a clean repository on a branch' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'clean')
        $r = Get-ReadyCheck 'Test-AosReadinessRepository' @{ Path = $repo }
        $r.status | Should -Be 'ok'
        $r.detail | Should -Match 'clean'
    }
    It 'warns about uncommitted changes and counts them' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'dirty')
        [System.IO.File]::WriteAllText((Join-Path $repo 'b.txt'), "two`n")
        $r = Get-ReadyCheck 'Test-AosReadinessRepository' @{ Path = $repo }
        $r.status | Should -Be 'warn'
        $r.detail | Should -Match '1 uncommitted'
    }
    It 'warns on a detached HEAD' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'detached')
        Invoke-ReadyGit $repo @('checkout', '-q', '--detach')
        $r = Get-ReadyCheck 'Test-AosReadinessRepository' @{ Path = $repo }
        $r.status | Should -Be 'warn'
        $r.detail | Should -Match 'detached'
    }
}

Context 'claim check' {
    It 'is ok when no live claim holds the checkout' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'free')
        Mock Get-AosClaims -ModuleName aos { @() }
        $r = Get-ReadyCheck 'Test-AosReadinessClaim' @{ Path = $repo }
        $r.name | Should -Be 'claim'
        $r.status | Should -Be 'ok'
        $r.detail | Should -Match 'unclaimed'
    }
    It 'warns with the holder when a live claim holds this checkout' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'held')
        $co = InModuleScope aos -Parameters @{ P = $repo } { param($P) Get-AosCheckout $P }
        Mock Get-AosClaims -ModuleName aos -MockWith ([scriptblock]::Create(
            "@([ordered]@{ checkout='$co'; agent='codex'; session='s-7'; since='2026-10-22T07:00:00Z'; expires='2026-10-22T08:00:00Z'; note='building' })"))
        $r = Get-ReadyCheck 'Test-AosReadinessClaim' @{ Path = $repo }
        $r.status | Should -Be 'warn'
        $r.detail | Should -Match 'codex'
        $r.detail | Should -Match 's-7'
    }
    It 'ignores a claim on a different checkout' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'mine')
        Mock Get-AosClaims -ModuleName aos {
            @([ordered]@{ checkout = 'Z:\somewhere\else'; agent = 'codex'; session = 's-8'; since = '2026-10-22T07:00:00Z'; expires = '2026-10-22T08:00:00Z'; note = '' })
        }
        (Get-ReadyCheck 'Test-AosReadinessClaim' @{ Path = $repo }).status | Should -Be 'ok'
    }
}

Context 'capacity check' {
    It 'is ok when the vendor has room' {
        Mock Get-AosCapacity -ModuleName aos -MockWith (New-ReadyCapacity 'claude' 'ok' 94)
        $r = Get-ReadyCheck 'Test-AosReadinessCapacity' @{ Vendor = 'claude'; Now = $readyNow }
        $r.name | Should -Be 'capacity:claude'
        $r.status | Should -Be 'ok'
        $r.detail | Should -Match '94'
    }
    It 'warns when the window is low, stale or already past its reset' {
        foreach ($state in @('low', 'stale', 'reset')) {
            Mock Get-AosCapacity -ModuleName aos -MockWith (New-ReadyCapacity 'codex' $state 20)
            $r = Get-ReadyCheck 'Test-AosReadinessCapacity' @{ Vendor = 'codex'; Now = $readyNow }
            $r.status | Should -Be 'warn'
            $r.detail | Should -Match $state
        }
    }
    It 'fails a limited vendor and says when it resets' {
        Mock Get-AosCapacity -ModuleName aos -MockWith (New-ReadyCapacity 'codex' 'limited' 0 '2026-10-22T12:00:00Z')
        $r = Get-ReadyCheck 'Test-AosReadinessCapacity' @{ Vendor = 'codex'; Now = $readyNow }
        $r.name | Should -Be 'capacity:codex'
        $r.status | Should -Be 'fail'
        $r.detail | Should -Match 'limited'
        $r.detail | Should -Match '2026-10-22T12:00Z'
    }
    It 'warns when no capacity was ever reported for the vendor' {
        Mock Get-AosCapacity -ModuleName aos -MockWith (New-ReadyCapacity 'claude' 'ok' 94)
        $r = Get-ReadyCheck 'Test-AosReadinessCapacity' @{ Vendor = 'codex'; Now = $readyNow }
        $r.status | Should -Be 'warn'
        $r.detail | Should -Match 'no capacity report'
    }
}

Context 'actors check' {
    It 'counts only active actors of the vendor against the cap of two' {
        Mock Get-AosActors -ModuleName aos -MockWith (New-ReadyActors @('l1:codex:running', 'n1:codex:reserved', 'old:codex:done', 'x:codex:failed', 'c1:claude:running'))
        $codex = Get-ReadyCheck 'Test-AosReadinessActors' @{ Vendor = 'codex' }
        $codex.name | Should -Be 'actors:codex'
        $codex.status | Should -Be 'fail'
        $codex.detail | Should -Match '2'
        $claude = Get-ReadyCheck 'Test-AosReadinessActors' @{ Vendor = 'claude' }
        $claude.status | Should -Be 'ok'
        $claude.detail | Should -Match '1'
    }
    It 'is ok with no active actors and ignores finished ones' {
        Mock Get-AosActors -ModuleName aos -MockWith (New-ReadyActors @('a:claude:done', 'b:claude:cancelled'))
        $r = Get-ReadyCheck 'Test-AosReadinessActors' @{ Vendor = 'claude' }
        $r.status | Should -Be 'ok'
        $r.detail | Should -Match '0'
    }
}

Context 'task-path check' {
    It 'is ok when a tracked file resolves as a task path' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'paths')
        $r = Get-ReadyCheck 'Test-AosReadinessTaskPaths' @{ Path = $repo }
        $r.name | Should -Be 'task-paths'
        $r.status | Should -Be 'ok'
        $r.detail | Should -Match 'a\.txt'
    }
    It 'fails with the resolver message when task paths are refused here' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'refused')
        Mock Resolve-AosTaskFile -ModuleName aos { throw 'unsafe relative task path through a link' }
        $r = Get-ReadyCheck 'Test-AosReadinessTaskPaths' @{ Path = $repo }
        $r.status | Should -Be 'fail'
        $r.detail | Should -Match 'through a link'
    }
    It 'warns when the repository has no tracked file to probe' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'empty') -Empty
        $r = Get-ReadyCheck 'Test-AosReadinessTaskPaths' @{ Path = $repo }
        $r.status | Should -Be 'warn'
        $r.detail | Should -Match 'no tracked file'
    }
}

Context 'unpushed check' {
    It 'warns that commits with no remote copy exist only on this machine' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'local')
        $r = Get-ReadyCheck 'Test-AosReadinessUnpushed' @{ Path = $repo }
        $r.name | Should -Be 'unpushed'
        $r.status | Should -Be 'warn'
        $r.detail | Should -Match '1 commit'
        $r.detail | Should -Match 'only on this machine'
    }
    It 'is ok once every commit is on a remote, and warns again after a new commit' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'pushed')
        $bare = New-ReadyFolder (Join-Path $caseRoot 'bare')
        Invoke-ReadyGit $bare @('init', '-q', '--bare')
        Invoke-ReadyGit $repo @('remote', 'add', 'origin', $bare)
        Invoke-ReadyGit $repo @('push', '-q', 'origin', 'HEAD:refs/heads/main')
        $ok = Get-ReadyCheck 'Test-AosReadinessUnpushed' @{ Path = $repo }
        $ok.status | Should -Be 'ok'
        $ok.detail | Should -Match 'remote'
        Invoke-ReadyGit $repo @('commit', '--allow-empty', '-qm', 'second')
        $again = Get-ReadyCheck 'Test-AosReadinessUnpushed' @{ Path = $repo }
        $again.status | Should -Be 'warn'
        $again.detail | Should -Match '1 commit'
    }
}

Context 'aggregation and verdict' {
    It 'returns the eight named checks in order, each with a status and a detail' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'all')
        Mock Get-AosClaims -ModuleName aos { @() }
        Mock Get-AosCapacity -ModuleName aos {
            [ordered]@{
                claude = [pscustomobject]@{ vendor = 'claude'; remaining = 94; resets = $null; reported = [datetime]::UtcNow; source = 'reported'; note = ''; state = 'ok'; window = '' }
                codex  = [pscustomobject]@{ vendor = 'codex'; remaining = 50; resets = $null; reported = [datetime]::UtcNow; source = 'reported'; note = ''; state = 'ok'; window = '' }
            }
        }
        Mock Get-AosActors -ModuleName aos { @() }
        $checks = @(InModuleScope aos -Parameters @{ P = $repo } { param($P) Get-AosReadinessChecks -Path $P })
        @($checks | ForEach-Object { $_.name }) | Should -Be @('repository', 'claim', 'capacity:claude', 'capacity:codex', 'actors:claude', 'actors:codex', 'task-paths', 'unpushed')
        foreach ($c in $checks) {
            $c.status | Should -BeIn @('ok', 'warn', 'fail')
            [string]$c.detail | Should -Not -BeNullOrEmpty
        }
    }
    It 'turns a throwing check into a failed check and still runs the others' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'boom')
        Mock Get-AosClaims -ModuleName aos { @() }
        Mock Get-AosCapacity -ModuleName aos { [ordered]@{} }
        Mock Get-AosActors -ModuleName aos { @() }
        Mock Test-AosReadinessClaim -ModuleName aos { throw 'boom' }
        $checks = @(InModuleScope aos -Parameters @{ P = $repo } { param($P) Get-AosReadinessChecks -Path $P })
        $checks.Count | Should -Be 8
        $claim = $checks | Where-Object { $_.name -eq 'claim' }
        $claim.status | Should -Be 'fail'
        $claim.detail | Should -Match 'boom'
        ($checks | Where-Object { $_.name -eq 'repository' }).status | Should -Be 'ok'
    }
    It 'derives the verdict: any fail beats any warn beats ok' {
        InModuleScope aos {
            $ok = [pscustomobject]@{ name = 'a'; status = 'ok'; detail = 'x' }
            $warn = [pscustomobject]@{ name = 'b'; status = 'warn'; detail = 'x' }
            $fail = [pscustomobject]@{ name = 'c'; status = 'fail'; detail = 'x' }
            Get-AosReadinessVerdict @($ok, $ok) | Should -Be 'ok'
            Get-AosReadinessVerdict @($ok, $warn) | Should -Be 'warn'
            Get-AosReadinessVerdict @($ok, $warn, $fail) | Should -Be 'fail'
            Get-AosReadinessVerdict @() | Should -Be 'ok'
        }
    }
}

Context 'command' {
    BeforeEach {
        Mock Get-AosReadinessChecks -ModuleName aos {
            $global:ReadyTestPath = $Path
            @([pscustomobject]@{ name = 'repository'; status = 'ok'; detail = 'branch main, clean' },
              [pscustomobject]@{ name = 'unpushed'; status = 'warn'; detail = '3 commits exist only on this machine' })
        }
    }
    It 'prints one line per check and a summary, and exits zero on warnings' {
        $out = InModuleScope aos { Invoke-AosReady -Arguments @('.') *>&1 | Out-String }
        $out | Should -Match 'repository'
        $out | Should -Match 'unpushed'
        $out | Should -Match 'only on this machine'
        $out | Should -Match 'ready with warnings'
        $global:LASTEXITCODE | Should -Be 0
    }
    It 'summarizes an all-ok result as ready' {
        Mock Get-AosReadinessChecks -ModuleName aos { @([pscustomobject]@{ name = 'repository'; status = 'ok'; detail = 'fine' }) }
        $out = InModuleScope aos { Invoke-AosReady -Arguments @('.') *>&1 | Out-String }
        $out | Should -Match 'ready'
        $out | Should -Not -Match 'not ready'
        $out | Should -Not -Match 'with warnings'
        $global:LASTEXITCODE | Should -Be 0
    }
    It 'says not ready and exits 1 when a check fails' {
        Mock Get-AosReadinessChecks -ModuleName aos { @([pscustomobject]@{ name = 'claim'; status = 'fail'; detail = 'held' }) }
        $out = InModuleScope aos { Invoke-AosReady -Arguments @('.') *>&1 | Out-String }
        $out | Should -Match 'not ready'
        $global:LASTEXITCODE | Should -Be 1
    }
    It 'emits the verdict and the checks as JSON with --json' {
        $json = InModuleScope aos { Invoke-AosReady -Arguments @('--json') | Out-String } | ConvertFrom-Json
        $json.verdict | Should -Be 'warn'
        @($json.checks).Count | Should -Be 2
        $json.checks[1].name | Should -Be 'unpushed'
        $json.checks[1].status | Should -Be 'warn'
    }
    It 'checks the given path, or the current directory when none is given' {
        $repo = New-ReadyRepo (Join-Path $caseRoot 'given')
        InModuleScope aos -Parameters @{ P = $repo } { param($P) Invoke-AosReady -Arguments @($P) *>&1 | Out-Null }
        $global:ReadyTestPath | Should -Be (Resolve-Path -LiteralPath $repo).ProviderPath
        Remove-Variable -Name ReadyTestPath -Scope Global
        Push-Location $repo
        try { InModuleScope aos { Invoke-AosReady -Arguments @() *>&1 | Out-Null } } finally { Pop-Location }
        $global:ReadyTestPath | Should -Be (Resolve-Path -LiteralPath $repo).ProviderPath
    }
    It 'rejects an unknown option with a usage line and exit code 1' {
        $out = InModuleScope aos { Invoke-AosReady -Arguments @('--bogus') *>&1 | Out-String }
        $out | Should -Match 'usage: aos ready'
        $global:LASTEXITCODE | Should -Be 1
    }
}

Context 'wiring' {
    It 'is reachable as aos ready and listed in the help' {
        Mock Invoke-AosReady -ModuleName aos { 'routed:' + (@($Arguments) -join ',') }
        (aos ready --json) | Should -Be 'routed:--json'
        $help = InModuleScope aos { Show-AosHelp *>&1 | Out-String }
        $help | Should -Match 'aos ready'
    }
    It 'is parse- and ASCII-checked by aos test and loaded by the module' {
        $module = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\aos.psm1') -Raw
        ([regex]::Matches($module, 'config\\readiness\.ps1')).Count | Should -BeGreaterOrEqual 2    # dot-sourced and in the static-check list
        $file = Join-Path $PSScriptRoot '..\config\readiness.ps1'
        Test-Path -LiteralPath $file | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($file)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
}
