Describe 'native upgrade to reviewed Codex 0.163.0' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
        $savedNativeEnvironment = @{}
        foreach ($name in @('AOS_COORD','AOS_ROUTING','AOS_CLAUDE_HOME')) {
            $savedNativeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
    }
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $env:AOS_ROUTING = Join-Path $caseRoot 'routing.json'
        $env:AOS_CLAUDE_HOME = Join-Path $caseRoot 'claude'
        Mock Invoke-AosProcess -ModuleName aos { throw 'no CLI or network call is allowed; versions must be supplied' }
    }
    AfterAll {
        foreach ($name in $savedNativeEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedNativeEnvironment[$name])
        }
    }

    It 'renders Codex 0.163.0 roles with supported settings, keeps unrelated config, and stays idempotent' {
        [IO.File]::WriteAllText($env:AOS_ROUTING, '{"codex":{"light":{"model":"fake-local-model","effort":"low"},"standard":{"model":"fake-local-model","effort":"low"}}}')
        InModuleScope aos -Parameters @{ Case = $caseRoot } {
            param($Case)
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $codex = Join-Path $Case 'codex'; $claude = Join-Path $Case 'claude'
            New-Item -ItemType Directory -Path $codex -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $codex 'config.toml'), '# personal sandbox settings')

            $caps = Get-AosNativeCapabilities -ClaudeVersion '2.1.296' -CodexVersion '0.163.0'
            $caps.codex.version | Should -Be '0.163.0'
            $caps.codex.nativeRoleFiles | Should -BeTrue
            $caps.codex.maxTurns | Should -BeFalse

            $first = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps
            foreach ($name in @('explore','implement','verify')) {
                $toml = Join-Path $codex ('agents\aos-' + $name + '.toml')
                Test-Path -LiteralPath $toml -PathType Leaf | Should -BeTrue
                $text = [IO.File]::ReadAllText($toml)
                $text | Should -Match 'model = "fake-local-model"'
                $text | Should -Match 'model_reasoning_effort = "low"'
                $text | Should -Not -Match '(?m)^max_turns\s*='
                $text | Should -Not -Match 'observed_'
            }
            [IO.File]::ReadAllText((Join-Path $codex 'config.toml')) | Should -BeExactly '# personal sandbox settings'
            @($first | Where-Object { $_.vendor -eq 'codex' -and $_.status -eq 'written' }).Count | Should -Be 3

            $toml = Join-Path $codex 'agents\aos-explore.toml'
            $before = [IO.File]::ReadAllText($toml); $stamp = [IO.File]::GetLastWriteTimeUtc($toml)
            $second = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps
            @($second | Where-Object { $_.vendor -eq 'codex' -and $_.status -ne 'unchanged' }).Count | Should -Be 0
            [IO.File]::ReadAllText($toml) | Should -BeExactly $before
            [IO.File]::GetLastWriteTimeUtc($toml) | Should -Be $stamp

            $profile = Read-AosJson (Join-Path $codex 'aos-native-capabilities.json')
            $profile.capabilities.version | Should -Be '0.163.0'
            $profile.roles.explore.observed_model | Should -BeNullOrEmpty
            $profile.roles.explore.observed_effort | Should -BeNullOrEmpty
            $profile.roles.explore.settings.Contains('max_turns') | Should -BeFalse

            $future = Get-AosNativeCapabilities -ClaudeVersion '2.1.296' -CodexVersion '0.164.0'
            $future.codex.nativeRoleFiles | Should -BeFalse
            Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
        }
    }
}
