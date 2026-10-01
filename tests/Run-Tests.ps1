# Runs the Pester suite in the current shell. `aos test` calls this once under Windows PowerShell
# 5.1 and once under PowerShell 7 (-NoProfile -ExecutionPolicy Bypass).
# Exit codes: 0 all passed, 1 failures, 2 Pester 5 missing, 3 no tests discovered.
$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.5.0' } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    # Codex's sandbox sees the unredirected Documents folder on PSModulePath, while Pester was installed
    # into the OneDrive one (any localized name). Look there by path; AOS_PESTER_DIR overrides.
    $roots = @()
    if ($env:AOS_PESTER_DIR) { $roots += $env:AOS_PESTER_DIR }
    if ($env:OneDrive -and (Test-Path -LiteralPath $env:OneDrive)) {
        foreach ($docs in @(Get-ChildItem -LiteralPath $env:OneDrive -Directory -ErrorAction SilentlyContinue)) {
            foreach ($sub in @('PowerShell\Modules\Pester', 'WindowsPowerShell\Modules\Pester')) {
                $roots += (Join-Path $docs.FullName $sub)
            }
        }
    }
    $found = @()
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($psd in @(Get-ChildItem -LiteralPath $r -Filter 'Pester.psd1' -Recurse -Depth 2 -ErrorAction SilentlyContinue)) {
            $v = $null
            if ([version]::TryParse($psd.Directory.Name, [ref]$v) -and $v -ge [version]'5.5.0') {
                $found += [pscustomobject]@{ Version = $v; Path = $psd.FullName }
            }
        }
    }
    $pester = $found | Sort-Object Version -Descending | Select-Object -First 1
}
if (-not $pester) {
    Write-Host "Pester 5.5+ is not installed for PowerShell $($PSVersionTable.PSVersion) (only the inbox 3.4 counts as missing). Run: aos install base"
    exit 2
}
Import-Module $pester.Path -Force

# Every test must stay out of the real profile: backups go to a throwaway folder for the whole run.
$env:AOS_BACKUPS = Join-Path ([System.IO.Path]::GetTempPath()) ('aos-test-backups-' + [guid]::NewGuid().ToString('N'))
# Coordination state (claims, ledger, delegations) likewise never touches ~/.aos/coord.
$env:AOS_COORD = Join-Path ([System.IO.Path]::GetTempPath()) ('aos-test-coord-' + [guid]::NewGuid().ToString('N'))
# And Codex's home (hooks.json, plugin cache, models cache): a brain sync under test must never write ~/.codex.
$env:CODEX_HOME = Join-Path ([System.IO.Path]::GetTempPath()) ('aos-test-codex-' + [guid]::NewGuid().ToString('N'))
# Same for Pi's agent directory: a test that reaches Sync-AosPi unmocked must never touch ~/.pi/agent.
$env:PI_CODING_AGENT_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ('aos-test-pi-' + [guid]::NewGuid().ToString('N'))

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.PassThru = $true
# Filesystem-only suite: never create Pester fixtures in the user registry.
$config.TestRegistry.Enabled = $false
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if ($result.TotalCount -eq 0) { Write-Host 'No tests were discovered.'; exit 3 }
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { exit 1 }
exit 0
