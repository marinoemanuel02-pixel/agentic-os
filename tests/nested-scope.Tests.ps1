Describe 'delegate write scope with new files in new directories' {
# Regression: `git status --porcelain` collapses a new untracked directory to `?? src/`.
# The write result must list individual files, or --allow rejects legitimate new files.
# Real git status is used on purpose; only the preflight and the model process are mocked.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    function New-NestedFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }
    function Write-NestedFile([string]$Path, [string]$Text) {
        New-NestedFolder (Split-Path -Parent $Path) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

BeforeEach {
    # Short component names keep PS 5.1 TestDrive cleanup within path limits.
    $caseRoot = New-NestedFolder (Join-Path $TestDrive ('n' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
    $savedCoord = $env:AOS_COORD
    $env:AOS_COORD = Join-Path $caseRoot 'c'
    $repo = New-NestedFolder (Join-Path $caseRoot 'r')
    & git -C $repo init -q
    & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
    $task = Join-Path $caseRoot 't.md'
    Write-NestedFile $task 'Write a file in a new directory'
    Mock Update-AosPath -ModuleName aos { }
    Mock Test-AosCommand -ModuleName aos { return $false }
    Mock Invoke-AosCapture -ModuleName aos { throw 'Unexpected external command in a test.' }
    Mock Get-AosCodexConfigText -ModuleName aos { throw 'Unexpected config read in a test.' }
    Mock Get-AosWorktreesDir -ModuleName aos { Join-Path $caseRoot 'w' }
    Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } }
    Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'cmd.exe' } {
        Write-NestedFile $StdoutFile 'host verification'
        @{ Code=0; TimedOut=$false; KillFailed=$false }
    }
}

AfterEach { $env:AOS_COORD = $savedCoord }

It 'accepts a new file inside a new directory that is within the allow scope' {
    Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'codex.exe' } {
        Write-NestedFile (Join-Path $WorkingDirectory 'src/allowed.txt') 'allowed'
        Write-NestedFile $StdoutFile '{"type":"turn.completed"}'
        Write-NestedFile $Arguments[[Array]::IndexOf($Arguments, '-o') + 1] '{"status":"done","summary":"new file","files_changed":["src/allowed.txt"],"tests_run":[],"unverified":[]}'
        @{ Code=0; TimedOut=$false; KillFailed=$false }
    }
    $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'git diff --check' -Allow @('src/allowed.txt') }
    $r.outcome | Should -Be 'accepted'
    $r.accepted | Should -BeTrue
    @($r.changed) | Should -Contain 'src/allowed.txt'
    @($r.outside_allow).Count | Should -Be 0
}

It 'rejects a second new file in the same new directory and names it in outside_allow' {
    Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'codex.exe' } {
        Write-NestedFile (Join-Path $WorkingDirectory 'src/allowed.txt') 'allowed'
        Write-NestedFile (Join-Path $WorkingDirectory 'src/extra.txt') 'extra'
        Write-NestedFile $StdoutFile '{"type":"turn.completed"}'
        Write-NestedFile $Arguments[[Array]::IndexOf($Arguments, '-o') + 1] '{"status":"done","summary":"two new files","files_changed":["src/allowed.txt","src/extra.txt"],"tests_run":[],"unverified":[]}'
        @{ Code=0; TimedOut=$false; KillFailed=$false }
    }
    $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'git diff --check' -Allow @('src/allowed.txt') }
    $r.outcome | Should -Be 'rejected'
    $r.accepted | Should -BeFalse
    @($r.outside_allow) | Should -Contain 'src/extra.txt'
    @($r.outside_allow) | Should -Not -Contain 'src/allowed.txt'
}
}
