# Runs tests/Run-Tests.ps1 under Windows PowerShell 5.1 and PowerShell 7 with a full-name wildcard filter
# (AOS_TEST_FILTER). Exit 0 only when both shells pass; used as the host verification command for focused work.
param([Parameter(Mandatory = $true)][string]$Filter)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Run-Tests.ps1'
$failed = 0
foreach ($shell in @('powershell', 'pwsh')) {
    $exe = Get-Command $shell -ErrorAction SilentlyContinue
    if (-not $exe) { Write-Host "$shell was not found"; $failed++; continue }
    $env:AOS_TEST_FILTER = $Filter
    & $exe.Source -NoProfile -ExecutionPolicy Bypass -File $runner
    if ($LASTEXITCODE -ne 0) { Write-Host "$shell failed with exit code $LASTEXITCODE"; $failed++ }
}
Remove-Item Env:\AOS_TEST_FILTER -ErrorAction SilentlyContinue
if ($failed -gt 0) { exit 1 }
exit 0
