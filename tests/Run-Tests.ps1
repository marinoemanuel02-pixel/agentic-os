# Runs the Pester suite in the current shell. `aos test` calls this once under Windows PowerShell
# 5.1 and once under PowerShell 7 (-NoProfile -ExecutionPolicy Bypass).
# Exit codes: 0 all passed, 1 failures, 2 Pester 5 missing, 3 no tests discovered.
$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.5.0' } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host "Pester 5.5+ is not installed for PowerShell $($PSVersionTable.PSVersion) (only the inbox 3.4 counts as missing). Run: aos install base"
    exit 2
}
Import-Module $pester.Path -Force

# Every test must stay out of the real profile: backups go to a throwaway folder for the whole run.
$env:AOS_BACKUPS = Join-Path ([System.IO.Path]::GetTempPath()) ('aos-test-backups-' + [guid]::NewGuid().ToString('N'))

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if ($result.TotalCount -eq 0) { Write-Host 'No tests were discovered.'; exit 3 }
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { exit 1 }
exit 0
