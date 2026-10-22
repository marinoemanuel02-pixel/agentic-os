Describe 'aos coord actors filters' {
# Specification: `aos coord actors` takes --active, --vendor <claude|codex> and --task <id> (combined with AND), and the
# tuning commands accept and ignore `--as <agent>`. Fixture actors are leads only, so no parent/task pairing is needed.
# Invoke-AosCoordControl is called directly; the tuning backends that touch other state are mocked.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    function New-CaFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }
    # Runs `aos coord <args>` and returns everything it printed. A thrown error is returned as its message, so a missing
    # option shows up in the failure text instead of aborting the helper.
    function Invoke-CaCoord([string[]]$CoordArgs) {
        InModuleScope aos -Parameters @{ A = $CoordArgs } {
            param($A)
            $global:LASTEXITCODE = $null
            try { Invoke-AosCoordControl -Arguments $A *>&1 | Out-String }
            catch { 'THROWN: ' + $_.Exception.Message }
        }
    }
    # Sorted actor ids from the JSON array a successful `actors` call printed.
    function Get-CaIds([string]$Text) {
        $t = $Text.Trim()
        if (-not $t.StartsWith('[')) { throw "not a JSON array: $t" }
        $rows = @($t | ConvertFrom-Json)
        return @($rows | ForEach-Object { $_.id } | Sort-Object)
    }
}

BeforeEach {
    # Short component names keep PS 5.1 TestDrive cleanup within path limits.
    $caseRoot = New-CaFolder (Join-Path $TestDrive ('a' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
    $savedCoord = $env:AOS_COORD
    $env:AOS_COORD = Join-Path $caseRoot 'c'
    Mock Update-AosPath -ModuleName aos { }
    Mock Test-AosCommand -ModuleName aos { return $false }
    Mock Invoke-AosCapture -ModuleName aos { throw 'Unexpected external command in a test.' }
    Mock Get-AosCodexConfigText -ModuleName aos { throw 'Unexpected config read in a test.' }
    Mock Get-AosRouteReport -ModuleName aos { @{ routes = @() } }
    Mock Sync-AosNativeRoles -ModuleName aos { @{ DryRun = $true; Changes = @() } }
    InModuleScope aos {
        foreach ($f in @(
            @('cl-run', 'claude', 't-claude', 'running'), @('cl-old', 'claude', 't-old', 'done'),
            @('cx-run', 'codex', 't-codex', 'running'), @('cx-old', 'codex', 't-old', 'done'))) {
            $r = Reserve-AosActor -Id $f[0] -Vendor $f[1] -Task $f[2] -Kind 'lead'
            if (-not $r.Ok) { throw "fixture reserve failed: $($r.Reason)" }
            $null = Set-AosActorState -Id $f[0] -State $f[3]
        }
    }
}

AfterEach { $env:AOS_COORD = $savedCoord }

It 'lists every actor as a JSON array when no option is given' {
    $out = Invoke-CaCoord @('actors')
    Get-CaIds $out | Should -Be @('cl-old', 'cl-run', 'cx-old', 'cx-run')
}

It 'keeps only active actors with --active' {
    $out = Invoke-CaCoord @('actors', '--active')
    Get-CaIds $out | Should -Be @('cl-run', 'cx-run')
}

It 'keeps only claude actors with --vendor claude' {
    $out = Invoke-CaCoord @('actors', '--vendor', 'claude')
    Get-CaIds $out | Should -Be @('cl-old', 'cl-run')
}

It 'keeps only codex actors with --vendor codex' {
    $out = Invoke-CaCoord @('actors', '--vendor', 'codex')
    Get-CaIds $out | Should -Be @('cx-old', 'cx-run')
}

It 'keeps only the actors of one task with --task' {
    $out = Invoke-CaCoord @('actors', '--task', 't-old')
    Get-CaIds $out | Should -Be @('cl-old', 'cx-old')
}

It 'combines --vendor and --active with AND' {
    $out = Invoke-CaCoord @('actors', '--vendor', 'codex', '--active')
    Get-CaIds $out | Should -Be @('cx-run')
}

It 'combines --vendor and --task with AND' {
    $out = Invoke-CaCoord @('actors', '--vendor', 'claude', '--task', 't-old')
    Get-CaIds $out | Should -Be @('cl-old')
}

It 'prints [] when the filters match nothing' {
    $out = Invoke-CaCoord @('actors', '--active', '--task', 't-old')
    $out.Trim() | Should -Be '[]'
}

It 'refuses any other vendor, naming the allowed ones' {
    $out = Invoke-CaCoord @('actors', '--vendor', 'gemini')
    $out | Should -Match 'vendor must be claude or codex'
    $out | Should -Not -Match '"id"'
}

It 'accepts and ignores --as on coord report' {
    $out = Invoke-CaCoord @('report', '--as', 'claude')
    $out | Should -Not -Match 'unknown or incomplete option'
    Should -Invoke Get-AosRouteReport -ModuleName aos -Times 1 -Exactly
}

It 'accepts and ignores --as on coord roles --dry-run' {
    $out = Invoke-CaCoord @('roles', '--dry-run', '--as', 'claude')
    $out | Should -Not -Match 'unknown or incomplete option'
    Should -Invoke Sync-AosNativeRoles -ModuleName aos -Times 1 -Exactly
}
}
