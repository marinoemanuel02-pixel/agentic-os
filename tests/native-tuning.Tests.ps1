Describe 'native tuning isolated suite' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
        $savedNativeEnvironment = @{}
        foreach ($name in @('AOS_COORD','AOS_ROUTING','AOS_CLAUDE_HOME')) {
            $savedNativeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        function New-NativeSignal([string]$Phase = 'start', [string]$Handle = 'handle-1', [string]$Run = 'run-1') {
            return (ConvertTo-Json -Compress -InputObject ([ordered]@{
                id = [guid]::NewGuid().ToString(); run_id = $Run; session_id = 'session-1';
                agent_id = $Handle; agent_type = 'Explore'; phase = $Phase; source = 'claude-hook';
                observed_at = [DateTime]::UtcNow.ToString('o'); transcript_ref = $null
            }))
        }
        function Write-NativeSignals([string[]]$Lines, [switch]$Incomplete) {
            $directory = Join-Path $env:AOS_COORD 'native-signals'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $text = $Lines -join "`n"
            if (-not $Incomplete) { $text += "`n" }
            [IO.File]::WriteAllText((Join-Path $directory 'run-1.jsonl'), $text, (New-Object Text.UTF8Encoding($false)))
        }
    }
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $env:AOS_ROUTING = Join-Path $caseRoot 'routing.json'
        $env:AOS_CLAUDE_HOME = Join-Path $caseRoot 'claude'
        Mock Invoke-AosProcess -ModuleName aos { throw 'CLI must be mocked or versions supplied' }
        InModuleScope aos {
            (Reserve-AosActor -Id run-1 -Vendor claude -Task task-1 -Workers 1).Ok | Should -BeTrue
            $null = Set-AosActorState -Id run-1 -State running
            $null = Set-AosRunState -Id run-1 -State running
        }
    }
    AfterAll {
        foreach ($name in $savedNativeEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedNativeEnvironment[$name])
        }
    }

    It 'gates Claude capabilities at documented thresholds without CLI calls' {
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $old = Get-AosNativeCapabilities -ClaudeVersion '2.1.286' -CodexVersion '0.157.1'
            $old.claude.version | Should -Be '2.1.286'
            $old.claude.perInvocationEffort | Should -BeFalse
            $old.claude.compactWindow | Should -BeFalse
            $old.claude.maxTurnsPartial | Should -BeTrue
            (Get-AosNativeCapabilities -ClaudeVersion '2.1.292' -CodexVersion '').claude.perInvocationEffort | Should -BeTrue
            $new = Get-AosNativeCapabilities -ClaudeVersion '2.1.296' -CodexVersion ''
            $new.claude.compactWindow | Should -BeTrue
            $new.claude.unknownFieldDiagnostics | Should -BeTrue
            Should -Invoke Invoke-AosProcess -Times 0
        }
    }
    It 'keeps unknown and arbitrary future Codex support false with evidence and limitations' {
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $known = Get-AosNativeCapabilities -ClaudeVersion '' -CodexVersion '0.157.1'
            $known.codex.nativeRoleFiles | Should -BeTrue
            $known.codex.evidence | Should -Not -BeNullOrEmpty
            foreach ($version in @('', 'not-version', '99.0.0')) {
                $caps = Get-AosNativeCapabilities -ClaudeVersion '' -CodexVersion $version
                $caps.codex.nativeRoleFiles | Should -BeFalse
                $caps.codex.limitations.Count | Should -BeGreaterThan 0
                $caps.claude.perInvocationEffort | Should -BeFalse
            }
            Should -Invoke Invoke-AosProcess -Times 0
        }
    }
    It 'probes only --version via the process wrapper when versions are omitted' {
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            Mock Invoke-AosProcess {
                param($Exe, $Arguments, $StdoutFile)
                ($Arguments -join ' ') | Should -Be '--version'
                $text = '0.157.1'; if ($Exe -eq 'claude') { $text = '2.1.286 (Claude Code)' }
                [IO.File]::WriteAllText($StdoutFile, $text)
                return [pscustomobject]@{ Code = 0 }
            }
            $caps = Get-AosNativeCapabilities
            $caps.claude.version | Should -Be '2.1.286'
            $caps.codex.version | Should -Be '0.157.1'
            Should -Invoke Invoke-AosProcess -Times 2
        }
    }
    It 'resolves local route requests separately from unknown observed settings and advisory budgets' {
        [IO.File]::WriteAllText($env:AOS_ROUTING, '{"codex":{"light":{"model":"account-model","effort":"low"}}}')
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $caps = Get-AosNativeCapabilities -ClaudeVersion '2.1.286' -CodexVersion '0.157.1'
            $role = Get-AosNativeRole -Vendor codex -Role explore -Tier light -MaxTurns 8 -Capabilities $caps
            $role.requested_model | Should -Be 'account-model'
            $role.requested_effort | Should -Be 'low'
            $role.observed_model | Should -BeNullOrEmpty
            $role.observed_effort | Should -BeNullOrEmpty
            $role.max_turns | Should -Be 8
            $role.settings.model | Should -Be 'account-model'
            $role.settings.model_reasoning_effort | Should -Be 'low'
            $role.settings.Contains('max_turns') | Should -BeFalse
            $role.limitations.Count | Should -BeGreaterThan 0
            { Get-AosNativeRole -Vendor codex -Role explore -MaxTurns 101 -Capabilities $caps } | Should -Throw
            (Get-AosNativeRole -Vendor claude -Role implement -Capabilities $caps).max_turns | Should -Be 24
            (Get-AosNativeRole -Vendor claude -Role verify -Capabilities $caps).max_turns | Should -Be 16
        }
    }
    It 'renders managed roles from local mapping and leaves unrelated config plus second-run bytes and times intact' {
        [IO.File]::WriteAllText($env:AOS_ROUTING, '{"codex":{"light":{"model":"account-model","effort":"low"}},"claude":{"light":{"model":"account-model","effort":"low"}}}')
        InModuleScope aos -Parameters @{ Case = $caseRoot } {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $codex = Join-Path $Case 'codex'; $claude = Join-Path $Case 'claude'
            New-Item -ItemType Directory -Path $codex -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $codex 'config.toml'), '# personal sandbox settings')
            $caps = Get-AosNativeCapabilities -ClaudeVersion '2.1.296' -CodexVersion '0.157.1'
            $null = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps
            $toml = Join-Path $codex 'agents\aos-explore.toml'
            $markdown = Join-Path $claude 'agents\aos-explore.md'
            [IO.File]::ReadAllText($toml) | Should -Match 'model = "account-model"'
            [IO.File]::ReadAllText($toml) | Should -Match 'model_reasoning_effort = "low"'
            [IO.File]::ReadAllText($markdown) | Should -Match 'maxTurns: 12'
            [IO.File]::ReadAllText($markdown) | Should -Match 'effort: "low"'
            $before = [IO.File]::ReadAllText($toml); $stamp = [IO.File]::GetLastWriteTimeUtc($toml)
            $null = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps
            [IO.File]::ReadAllText($toml) | Should -BeExactly $before
            [IO.File]::GetLastWriteTimeUtc($toml) | Should -Be $stamp
            [IO.File]::ReadAllText((Join-Path $codex 'config.toml')) | Should -BeExactly '# personal sandbox settings'
            $profile = Read-AosJson (Join-Path $codex 'aos-native-capabilities.json')
            $profile.capabilities.version | Should -Be '0.157.1'
            $profile.capabilities.evidence | Should -Not -BeNullOrEmpty
            $profile.roles.explore.observed_model | Should -BeNullOrEmpty
        }
    }
    It 'dry-run creates nothing and skips unowned role collisions while backing up changed managed roles' {
        InModuleScope aos -Parameters @{ Case = $caseRoot } {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $codex = Join-Path $Case 'codex'; $claude = Join-Path $Case 'claude'
            $caps = Get-AosNativeCapabilities -ClaudeVersion '2.1.286' -CodexVersion '0.157.1'
            $null = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps -DryRun
            Test-Path -LiteralPath $codex | Should -BeFalse
            New-Item -ItemType Directory -Path (Join-Path $codex 'agents') -Force | Out-Null
            $collision = Join-Path $codex 'agents\aos-explore.toml'
            [IO.File]::WriteAllText($collision, '# personal role')
            Mock Backup-AosFile { param($Path) return $Path + '.backup' }
            $null = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps
            [IO.File]::ReadAllText($collision) | Should -BeExactly '# personal role'
            $owned = Join-Path $codex 'agents\aos-verify.toml'
            [IO.File]::AppendAllText($owned, '# stale managed text')
            $null = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $caps
            Should -Invoke Backup-AosFile -Times 1 -ParameterFilter { $Path -eq $owned }
            [IO.File]::ReadAllText((Join-Path $claude 'agents\aos-explore.md')) | Should -Not -Match '(?m)^effort:'
        }
    }
    It 'imports observed start and stop with exact native identity and preserves unknown model settings' {
        Write-NativeSignals @((New-NativeSignal), (New-NativeSignal -Phase stop))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $result = Import-AosNativeSignals -RunId run-1
            $result.imported | Should -Be 2
            $child = (Read-AosActorStore).actors['run-1-native-1']
            $child.state | Should -Be 'done'
            $child.handle | Should -Be 'handle-1'
            $child.evidence | Should -Match '^native-signals/run-1.jsonl#'
            $child.Contains('observed_model') | Should -BeFalse
            @((Get-AosRunState run-1).native_signal_ids).Count | Should -Be 2
        }
    }
    It 'duplicate and resumed start observations do not allocate actors or rewrite replay state' {
        $first = New-NativeSignal
        Write-NativeSignals @($first, $first, (New-NativeSignal))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $result = Import-AosNativeSignals -RunId run-1
            $result.imported | Should -Be 2
            $store = Read-AosActorStore
            @($store.actors.Keys).Count | Should -Be 2
            $store.actors['run-1-native-1'].state | Should -Be 'running'
            $path = Join-Path $env:AOS_COORD 'delegations\run-1\run.json'
            $stamp = [IO.File]::GetLastWriteTimeUtc($path)
            (Import-AosNativeSignals -RunId run-1).imported | Should -Be 0
            [IO.File]::GetLastWriteTimeUtc($path) | Should -Be $stamp
        }
    }
    It 'conflicting handles require inspection without replacing or releasing the active child' {
        Write-NativeSignals @((New-NativeSignal), (New-NativeSignal -Handle handle-2))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $null = Import-AosNativeSignals -RunId run-1
            (Get-AosRunState run-1).state | Should -Be 'needs-inspection'
            $store = Read-AosActorStore
            $store.actors['run-1'].state | Should -Be 'suspect'
            $store.actors['run-1-native-1'].state | Should -Be 'running'
            $store.actors['run-1-native-1'].handle | Should -Be 'handle-1'
        }
    }
    It 'start after terminal child marks inspection and never silently revives the child' {
        Write-NativeSignals @((New-NativeSignal), (New-NativeSignal -Phase stop), (New-NativeSignal))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $null = Import-AosNativeSignals -RunId run-1
            (Get-AosRunState run-1).state | Should -Be 'needs-inspection'
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'done'
        }
    }
    It 'foreign stops malformed events and unmatched runs cannot establish completion' {
        Write-NativeSignals @('{broken}', (New-NativeSignal -Run foreign-run), (New-NativeSignal -Handle '../escape'),
            (New-NativeSignal), (New-NativeSignal -Phase stop -Handle foreign-handle))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $result = Import-AosNativeSignals -RunId run-1
            $result.diagnostics.Count | Should -BeGreaterThan 0
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'running'
            { Import-AosNativeSignals -RunId '../escape' } | Should -Throw
        }
    }
    It 'incomplete trailing event awaits a later complete line before changing state' {
        $start = New-NativeSignal
        Write-NativeSignals @($start) -Incomplete
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            (Import-AosNativeSignals -RunId run-1).imported | Should -Be 0
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'reserved'
        }
        Write-NativeSignals @($start)
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            (Import-AosNativeSignals -RunId run-1).imported | Should -Be 1
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'running'
        }
    }
    It 'wrong reserved actor kind parent or vendor cannot be completed by hook metadata' {
        Write-NativeSignals @((New-NativeSignal -Phase stop))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $store = Read-AosActorStore
            $store.actors['run-1-native-1'].vendor = 'codex'
            Write-AosCoordJson -Path (Join-Path $env:AOS_COORD 'actors.json') -Value $store
            $result = Import-AosNativeSignals -RunId run-1
            $result.diagnostics.Count | Should -BeGreaterThan 0
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'reserved'
            foreach ($field in @('kind','parent')) {
                $store = Read-AosActorStore
                $store.actors['run-1-native-1'].vendor = 'claude'
                $store.actors['run-1-native-1'].kind = 'native'
                $store.actors['run-1-native-1'].parent = 'run-1'
                $store.actors['run-1-native-1'][$field] = 'foreign'
                if ($field -eq 'kind') { $store.actors['run-1-native-1'][$field] = 'lead' }
                Write-AosCoordJson -Path (Join-Path $env:AOS_COORD 'actors.json') -Value $store
                $signalPath = Join-Path $env:AOS_COORD 'native-signals\run-1.jsonl'
                $signal = Read-AosJson $signalPath
                $signal.id = [guid]::NewGuid().ToString()
                Write-AosText -Path $signalPath -Text ((ConvertTo-Json $signal -Compress) + "`n")
                (Import-AosNativeSignals -RunId run-1).diagnostics.Count | Should -BeGreaterThan 0
                (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'reserved'
            }
        }
    }
    It 'metadata without a timestamp or typed IDs cannot establish observed lifecycle evidence' {
        $missingStamp = New-NativeSignal | ConvertFrom-Json
        $missingStamp.observed_at = $null
        $numericId = New-NativeSignal | ConvertFrom-Json
        $numericId.session_id = 42
        Write-NativeSignals @((ConvertTo-Json $missingStamp -Compress), (ConvertTo-Json $numericId -Compress))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            (Import-AosNativeSignals -RunId run-1).imported | Should -Be 0
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'reserved'
        }
    }
    It 'stop from another session cannot release a matching handle in this run' {
        $foreign = New-NativeSignal -Phase stop | ConvertFrom-Json
        $foreign.session_id = 'other-session'
        Write-NativeSignals @((New-NativeSignal), (ConvertTo-Json $foreign -Compress))
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $result = Import-AosNativeSignals -RunId run-1
            $result.imported | Should -Be 1
            (Read-AosActorStore).actors['run-1-native-1'].state | Should -Be 'running'
        }
    }
    It 'steering writes only for an active app-server run and its exact current turn' {
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $path = Join-Path $env:AOS_COORD 'delegations\run-1\run.json'
            $run = Get-AosRunState run-1
            $run.transport = 'app-server'; $run.active_turn_id = 'turn-1'
            Write-AosCoordJson -Path $path -Value $run
            $sent = Send-AosTurnSteering -RunId run-1 -Text 'Narrow the check' -ExpectedTurnId turn-1
            $request = Read-AosJson (Join-Path $env:AOS_COORD 'delegations\run-1\steering.json')
            $request.id | Should -Be $sent.id
            $request.expected_turn_id | Should -Be 'turn-1'
            { Send-AosTurnSteering -RunId run-1 -Text no -ExpectedTurnId old-turn } | Should -Throw
            $run.state = 'done'; Write-AosCoordJson -Path $path -Value $run
            { Send-AosTurnSteering -RunId run-1 -Text no -ExpectedTurnId turn-1 } | Should -Throw
            $run.state = 'running'; $run.transport = 'exec'; Write-AosCoordJson -Path $path -Value $run
            { Send-AosTurnSteering -RunId run-1 -Text no -ExpectedTurnId turn-1 } | Should -Throw
        }
    }
}
