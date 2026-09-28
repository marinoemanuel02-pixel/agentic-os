<#
.SYNOPSIS
    Set up (or repair) this machine for the Claude + GPT workflow. Safe to re-run.

.DESCRIPTION
    Layers, in order:
      base     winget tools (git, gh, pwsh, node, python, uv, rg, fd, jq, fzf, delta, VS Code, Obsidian)
      engines  Claude Code CLI (native installer) and Codex CLI (winget)
      brain    one AGENTS.md + one skills folder for both agents, merged settings, MCP servers
      bridges  codex plugin in Claude Code, cc-plugin-codex in Codex, superpowers
      refs     shallow clones of the reference repos in refs/repos.json
    Run it from the repo's final location: the brain layer links ~/.agents to this folder.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
.EXAMPLE
    pwsh -File .\bootstrap.ps1 -Layer brain,bridges
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'base', 'engines', 'brain', 'bridges', 'refs', 'local')]
    [string[]]$Layer = @('all'),
    [switch]$DryRun
)

Import-Module (Join-Path $PSScriptRoot 'aos.psm1') -Force -DisableNameChecking
Install-AosLayer -Layer $Layer -DryRun:$DryRun
