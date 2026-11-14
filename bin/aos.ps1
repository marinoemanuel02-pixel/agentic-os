# Entry point for shells without the aos profile function: Git Bash, cmd, pwsh -NoProfile and Windows
# PowerShell 5.1. The shims aos sync writes to ~\.local\bin run this file. The exit code is the one aos
# sets (aos test, aos delegate, aos claim do), otherwise that of the last native command aos ran, or 0.
try {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -DisableNameChecking -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine(('aos: module import failed: ' + $_.Exception.Message) -replace '[\r\n]+', ' ')
    exit 1
}
$global:LASTEXITCODE = 0
aos @args
exit [int]$global:LASTEXITCODE
