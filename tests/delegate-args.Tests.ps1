Describe 'aos delegate arguments' {
# Specification: in the command-line branch for `aos delegate <codex|claude> ...` a positional argument is refused before
# anything else happens ('unexpected argument' plus the offending text, exit code 1, no preflight, process or worktree).
# The command-line dispatcher is called on purpose (not Invoke-AosDelegate); only the preflight and the processes are mocked.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    function New-DaFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }
}

BeforeEach {
    # Short component names keep PS 5.1 TestDrive cleanup within path limits.
    $caseRoot = New-DaFolder (Join-Path $TestDrive ('g' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
    $savedCoord = $env:AOS_COORD
    $env:AOS_COORD = Join-Path $caseRoot 'c'
    $repo = New-DaFolder (Join-Path $caseRoot 'r')
    & git -C $repo init -q
    & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
    $task = Join-Path $caseRoot 't.md'
    [System.IO.File]::WriteAllText($task, 'Read the repository', (New-Object System.Text.UTF8Encoding($false)))
    Mock Update-AosPath -ModuleName aos { }
    Mock Test-AosCommand -ModuleName aos { return $false }
    Mock Invoke-AosCapture -ModuleName aos { throw 'Unexpected external command in a test.' }
    Mock Get-AosCodexConfigText -ModuleName aos { throw 'Unexpected config read in a test.' }
    Mock Get-AosWorktreesDir -ModuleName aos { Join-Path $caseRoot 'w' }
    Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok = $true; Model = 'fixture-model'; Reasons = @() } }
    Mock Invoke-AosProcess -ModuleName aos { @{ Code = 0; TimedOut = $false; KillFailed = $false; Cancelled = $false } }
}

AfterEach { $env:AOS_COORD = $savedCoord }

It 'refuses a stray value after a switch, naming it, before the preflight' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo } {
        param($T, $R)
        $global:LASTEXITCODE = $null
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--repo', $R, '--write', 'true') *>&1 | Out-String
    }
    $out | Should -Match 'unexpected argument'
    $out | Should -Match 'true'
    $global:LASTEXITCODE | Should -Be 1
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 0 -Exactly
    Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
}

It 'refuses a leading positional for claude too and creates no worktree' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo } {
        param($T, $R)
        $global:LASTEXITCODE = $null
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('claude', 'stray-word', '--task', $T, '--repo', $R) *>&1 | Out-String
    }
    $out | Should -Match 'unexpected argument'
    $out | Should -Match 'stray-word'
    $global:LASTEXITCODE | Should -Be 1
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 0 -Exactly
    Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
    Test-Path -LiteralPath (Join-Path $caseRoot 'w') | Should -BeFalse
}

It 'still reaches the preflight once with --task and no stray positionals' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo } {
        param($T, $R)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--repo', $R) *>&1 | Out-String
    }
    $out | Should -Not -Match 'unexpected argument'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 1 -Exactly
}

It 'still reaches the preflight once for a valid write command line' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo } {
        param($T, $R)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--repo', $R, '--write', '--allow', 'src/out.txt', '--verify', 'git diff --check') *>&1 | Out-String
    }
    $out | Should -Not -Match 'unexpected argument'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 1 -Exactly
}

It 'leaves delegate show with a positional id unaffected' {
    $out = InModuleScope aos {
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('show', 'no-such-run') *>&1 | Out-String
    }
    $out | Should -Not -Match 'unexpected argument'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 0 -Exactly
}
}
