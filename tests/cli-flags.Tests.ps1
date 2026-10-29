Describe 'aos command flags' {
# Specification: `aos sync --dry-run` (GNU spelling) must preview like `-DryRun`; on 2026-10-29 it was silently
# taken as a positional and ran a real sync into ~/.claude and ~/.codex. Commands without positionals refuse leftovers.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
}

BeforeEach {
    Mock Sync-AosBrain -ModuleName aos { }
    Mock Update-Aos -ModuleName aos { }
}

It 'treats --dry-run on sync as a preview' {
    aos sync --dry-run
    Should -Invoke Sync-AosBrain -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun -eq $true }
}

It 'refuses an unknown argument to sync without syncing' {
    $global:LASTEXITCODE = $null
    $out = aos sync --dryrun *>&1 | Out-String
    $out | Should -Match 'unexpected argument'
    $out | Should -Match '--dryrun'
    $global:LASTEXITCODE | Should -Be 1
    Should -Invoke Sync-AosBrain -ModuleName aos -Times 0 -Exactly
}

It 'refuses an unknown argument to update without updating' {
    $global:LASTEXITCODE = $null
    $null = aos update now *>&1 | Out-String
    $global:LASTEXITCODE | Should -Be 1
    Should -Invoke Update-Aos -ModuleName aos -Times 0 -Exactly
}
}
