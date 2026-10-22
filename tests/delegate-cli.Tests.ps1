Describe 'delegate command line with a write contract' {
# Regression: `aos delegate <vendor> --task t.md --contract c.json --write` was refused with 'write scope conflicts with
# contract' whenever the contract had a write scope and the command line repeated no --allow, because the parser passed
# an absent option as @($null). The documented command line must work; an explicit, different scope must still be refused.
# The command-line dispatcher is called on purpose (not Invoke-AosDelegate); only the preflight and the processes are mocked.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    function New-CliFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }
    function Write-CliFile([string]$Path, [string]$Text) {
        New-CliFolder (Split-Path -Parent $Path) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

BeforeEach {
    # Short component names keep PS 5.1 TestDrive cleanup within path limits.
    $caseRoot = New-CliFolder (Join-Path $TestDrive ('d' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
    $savedCoord = $env:AOS_COORD
    $env:AOS_COORD = Join-Path $caseRoot 'c'
    $repo = New-CliFolder (Join-Path $caseRoot 'r')
    & git -C $repo init -q
    & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
    $task = Join-Path $caseRoot 't.md'
    Write-CliFile $task 'Write the output file'
    $id = 'cli-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $contract = Join-Path $caseRoot 'contract.json'
    Write-CliFile $contract ('{"version":1,"id":"' + $id + '","objective":"Write the output file","task_class":"implementation","depends_on":[],"allow":["src/out.txt"],"verify":"git diff --check","artifacts":[],"context":[],"route_reason":"command line path","review":"lead","budget":{"timeout_minutes":3,"max_turns":4}}')
    Mock Update-AosPath -ModuleName aos { }
    Mock Test-AosCommand -ModuleName aos { return $false }
    Mock Invoke-AosCapture -ModuleName aos { throw 'Unexpected external command in a test.' }
    Mock Get-AosCodexConfigText -ModuleName aos { throw 'Unexpected config read in a test.' }
    Mock Get-AosWorktreesDir -ModuleName aos { Join-Path $caseRoot 'w' }
    Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok = $true; Model = 'fixture-model'; Reasons = @() } }
    Mock Invoke-AosProcess -ModuleName aos { @{ Code = 0; TimedOut = $false; KillFailed = $false; Cancelled = $false } }
}

AfterEach { $env:AOS_COORD = $savedCoord }

It 'does not refuse a write contract when the command line repeats no --allow' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write') *>&1 | Out-String
    }
    $out | Should -Not -Match 'conflicts with contract'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 1 -Exactly
}

It 'accepts an explicit --allow that matches the contract scope' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write', '--allow', 'src/out.txt') *>&1 | Out-String
    }
    $out | Should -Not -Match 'conflicts with contract'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 1 -Exactly
}

It 'still refuses an explicit --allow that differs from the contract scope, before probing' {
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write', '--allow', 'elsewhere/**') *>&1 | Out-String
    }
    $out | Should -Match 'write scope conflicts with contract'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 0 -Exactly
    Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
}

It 'compares explicit --allow entries with the contract scope as a set, ignoring their order' {
    Write-CliFile $contract ('{"version":1,"id":"' + $id + '","objective":"Write two files","task_class":"implementation","depends_on":[],"allow":["src/a.txt","src/b.txt"],"verify":"git diff --check","artifacts":[],"context":[],"route_reason":"command line path","review":"lead","budget":{"timeout_minutes":3,"max_turns":4}}')
    $reordered = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write', '--allow', 'src/b.txt', '--allow', 'src/a.txt') *>&1 | Out-String
    }
    $reordered | Should -Not -Match 'conflicts with contract'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 1 -Exactly
    $subset = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write', '--allow', 'src/a.txt') *>&1 | Out-String
    }
    $subset | Should -Match 'write scope conflicts with contract'
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 1 -Exactly
}

It 'tells the user plainly and exits 1 when a write contract has no scope, without launching' {
    Write-CliFile $contract ('{"version":1,"id":"' + $id + '","objective":"No scope","task_class":"implementation","depends_on":[],"allow":[],"verify":"git diff --check","artifacts":[],"context":[],"route_reason":"command line path","review":"lead","budget":{"timeout_minutes":3,"max_turns":4}}')
    $out = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write') *>&1 | Out-String
    }
    $out | Should -Match 'write contract needs a nonempty allow scope'
    $global:LASTEXITCODE | Should -Be 1
    Should -Invoke Test-AosDelegatePreflight -ModuleName aos -Times 0 -Exactly
    Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
}

It 'does not register or touch a worktree when the scope conflict is refused' {
    InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } {
        param($T, $R, $C)
        Invoke-AosCoordCommand -Command 'delegate' -Arguments @('codex', '--task', $T, '--contract', $C, '--repo', $R, '--write', '--allow', 'elsewhere/**') *>&1 | Out-Null
    }
    Test-Path -LiteralPath (Join-Path $caseRoot 'w') | Should -BeFalse
}
}
