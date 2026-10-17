# Narrow entry for headless workers. Resolve the checkout at runtime; no embedded installation path.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
try { aos coord @args; exit $LASTEXITCODE }
catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
