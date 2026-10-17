# Narrow entry for headless workers. Resolve the checkout at runtime; no embedded installation path.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
try {
    if ($env:AOS_COORD_TRANSPORT -eq 'stdout') {
        & (Get-Module aos) { param($Arguments) Invoke-AosWorkerCoord -Arguments $Arguments } @($args)
        exit 0
    }
    aos coord @args; exit $LASTEXITCODE
}
catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
