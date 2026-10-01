# Starts the local Penpot MCP server and plugin server (ports 4401 and 4400) and stays in the foreground.
# Stop it with Ctrl+C, or: Stop-Process -Id (Get-NetTCPConnection -LocalPort 4401 -State Listen).OwningProcess
$ErrorActionPreference = 'Stop'
$base = Join-Path $HOME '.aos\penpot-mcp'
$root = Join-Path $base 'node_modules\@penpot\mcp'
if (-not (Test-Path -LiteralPath (Join-Path $root 'packages\server\dist\index.js'))) {
    Write-Host "Penpot MCP is not installed in $base (see the penpot-local skill). Nothing was downloaded."
    exit 2
}
$env:Path = (Join-Path $base 'bin') + ';' + $env:Path   # pnpm.cmd shim: corepack pnpm
Set-Location -LiteralPath $root
pnpm run start
