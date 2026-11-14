Describe 'Codex home resolution' {
# Specification: every file aos writes or reads for Codex follows CODEX_HOME, as hooks and native roles already did.
# AGENTS.md, profile files, config.toml and the status check once used ~/.codex directly, splitting a redirected install.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    $savedCodexHome = $env:CODEX_HOME
}

AfterAll { $env:CODEX_HOME = $savedCodexHome }

BeforeEach {
    $env:CODEX_HOME = Join-Path $TestDrive ('codex-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $env:CODEX_HOME -Force | Out-Null
}

It 'targets profile files inside CODEX_HOME' {
    $targets = @(InModuleScope aos { @(Get-AosCodexProfiles | ForEach-Object { $_.Target }) })
    $targets.Count | Should -BeGreaterThan 0
    foreach ($t in $targets) { $t | Should -BeLike ($env:CODEX_HOME + '\*') }
}

It 'writes AGENTS.md into CODEX_HOME' {
    # Previews first: against a module that ignores CODEX_HOME this must fail without touching the real ~/.codex.
    # Joined by hand: Out-String in Windows PowerShell wraps long paths at the console width.
    $preview = @(InModuleScope aos { Sync-AosCodexAgents -DryRun } *>&1 | ForEach-Object { "$_" }) -join "`n"
    $preview | Should -Match ([regex]::Escape($env:CODEX_HOME))
    InModuleScope aos { Sync-AosCodexAgents } | Out-Null
    Test-Path -LiteralPath (Join-Path $env:CODEX_HOME 'AGENTS.md') | Should -BeTrue
}

It 'reads config.toml from CODEX_HOME' {
    [System.IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'config.toml'), "# fixture-marker`n")
    InModuleScope aos { Get-AosCodexConfigText } | Should -Match 'fixture-marker'
}
}
