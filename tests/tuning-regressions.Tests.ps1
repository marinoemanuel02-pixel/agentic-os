Describe 'coordination tuning follow-up regressions' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
        $savedFollowup = @{}
        foreach ($name in @('AOS_COORD','AOS_ROUTING','AOS_CLAUDE_HOME')) { $savedFollowup[$name] = [Environment]::GetEnvironmentVariable($name) }
        function Write-FollowFile([string]$Path, [string]$Text) {
            $directory = Split-Path -Parent $Path
            if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
            [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
        }
        function New-FollowRepo([string]$Path) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            & git -C $Path init -q
            & git -C $Path config user.name Fixture
            & git -C $Path config user.email fixture@example.invalid
            & git -C $Path commit --allow-empty -qm initial
            return $Path
        }
        function Write-FollowContract([string]$Path, [string]$Id) {
            Write-FollowFile $Path (ConvertTo-Json -Depth 6 -InputObject ([ordered]@{ version = 1; id = $Id; objective = "objective of $Id"
                task_class = 'implementation'; depends_on = @(); allow = @(); verify = 'git diff --check'; artifacts = @('output.txt'); context = @() }))
            return $Path
        }
        function Write-FollowReceipt([string]$Repo, [string]$Run, [string]$TaskId) {
            $r = [ordered]@{ id = $Run; task_id = $TaskId; repo = $Repo; workdir = $Repo; accepted = $true; outcome = 'accepted'
                commit = ''; verify = [ordered]@{ command = 'git diff --check'; exit_code = 0 }; changed = @('output.txt') }
            Write-FollowFile (Join-Path $env:AOS_COORD "delegations\$Run\receipt.json") (ConvertTo-Json -InputObject $r -Depth 8)
        }
        function New-FollowSignal([string]$Run) {
            return (ConvertTo-Json -Compress -InputObject ([ordered]@{ id = [guid]::NewGuid().ToString(); run_id = $Run; session_id = 'session-1'
                agent_id = 'handle-1'; agent_type = 'Explore'; phase = 'start'; source = 'claude-hook'
                observed_at = [DateTime]::UtcNow.ToString('o'); transcript_ref = $null }))
        }
    }
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $env:AOS_ROUTING = Join-Path $caseRoot 'routing.json'
        $env:AOS_CLAUDE_HOME = Join-Path $caseRoot 'claude'
    }
    AfterAll { foreach ($name in $savedFollowup.Keys) { [Environment]::SetEnvironmentVariable($name, $savedFollowup[$name]) } }

    Context 'task acceptance with a missing declared artifact' {
        It 'fails visibly and leaves a genuinely accepted receipt retryable instead of owned by the dead attempt' {
            $repo = New-FollowRepo (Join-Path $caseRoot 'repo')
            $contract = Write-FollowContract (Join-Path $caseRoot 'contract.json') 'artifact-task'
            InModuleScope aos -Parameters @{ F = $contract; R = $repo } {
                param($F, $R)
                $null = Register-AosTaskContract -Path $F -Repo $R
                $null = Start-AosTaskAttempt -Id 'artifact-task' -RunId 'run-art-1'
            }
            Write-FollowReceipt $repo 'run-art-1' 'artifact-task'
            Test-Path -LiteralPath (Join-Path $repo 'output.txt') | Should -BeFalse
            { InModuleScope aos { Complete-AosTaskAttempt -Id 'artifact-task' -RunId 'run-art-1' } } | Should -Throw
            $row = InModuleScope aos { Get-AosTaskRecord -Id 'artifact-task' }
            $row.state | Should -Be 'failed'
            $row.active_run | Should -BeNullOrEmpty
            $row.accepted_run | Should -BeNullOrEmpty
            { InModuleScope aos { Start-AosTaskAttempt -Id 'artifact-task' -RunId 'run-art-2' } } | Should -Not -Throw
        }

        It 'keeps unknown ownership when the receipt is missing or forged' {
            $repo = New-FollowRepo (Join-Path $caseRoot 'repo')
            foreach ($case in @('missing', 'forged')) {
                $id = "own-$case"; $run = "run-own-$case"
                $contract = Write-FollowContract (Join-Path $caseRoot "$id.json") $id
                InModuleScope aos -Parameters @{ F = $contract; R = $repo; I = $id; U = $run } {
                    param($F, $R, $I, $U)
                    $null = Register-AosTaskContract -Path $F -Repo $R
                    $null = Start-AosTaskAttempt -Id $I -RunId $U
                }
                if ($case -eq 'forged') { Write-FollowFile (Join-Path $env:AOS_COORD "delegations\$run\receipt.json") '{ "id": "run-own-forged", "accepted": true, "outcome": ' }
                { InModuleScope aos -Parameters @{ I = $id; U = $run } { param($I, $U) Complete-AosTaskAttempt -Id $I -RunId $U } } | Should -Throw
                $row = InModuleScope aos -Parameters @{ I = $id } { param($I) Get-AosTaskRecord -Id $I }
                $row.active_run | Should -Be $run -Because $case
                $row.state | Should -Be 'running' -Because $case
                { InModuleScope aos -Parameters @{ I = $id } { param($I) Start-AosTaskAttempt -Id $I -RunId 'run-other' } } | Should -Throw
            }
        }

        It 'does not let the host delegate claim accepted when task acceptance fails' {
            $repo = New-FollowRepo (Join-Path $caseRoot 'repo')
            $task = Join-Path $caseRoot 'task.md'; Write-FollowFile $task 'Read the input'
            $contract = Join-Path $caseRoot 'launch-contract.json'
            Write-FollowFile $contract '{"version":1,"id":"launch-missing","objective":"Produce the artifact","task_class":"mechanical","depends_on":[],"allow":[],"verify":"git diff --check","artifacts":["never-written.txt"],"context":[],"route_reason":"fixture","review":"inline","budget":{"timeout_minutes":2,"max_turns":8}}'
            Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok = $true; Model = 'fixture-model'; Reasons = @() } }
            Mock Invoke-AosProcess -ModuleName aos {
                if ($Exe -eq 'cmd.exe') { return @{ Code = 0; TimedOut = $false; KillFailed = $false } }
                [IO.File]::WriteAllText($StdoutFile, '{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}')
                [IO.File]::WriteAllText((Join-Path (Split-Path $StdoutFile -Parent) 'result.json'), '{"status":"done","summary":"read","files_changed":[],"tests_run":[],"unverified":[]}')
                @{ Code = 0; TimedOut = $false; KillFailed = $false; Cancelled = $false }
            }
            $r = InModuleScope aos -Parameters @{ T = $task; R = $repo; C = $contract } { param($T, $R, $C) Invoke-AosDelegate -Vendor codex -TaskFile $T -Repo $R -ContractFile $C }
            $r.accepted | Should -BeFalse
            $r.outcome | Should -Not -Be 'accepted'
            $stored = Get-Content -LiteralPath (Join-Path $env:AOS_COORD "delegations\$($r.id)\receipt.json") -Raw | ConvertFrom-Json
            $stored.accepted | Should -BeFalse
            $stored.outcome | Should -Not -Be 'accepted'
            $row = InModuleScope aos { Get-AosTaskRecord -Id 'launch-missing' }
            $row.state | Should -Be 'failed'
            $row.active_run | Should -BeNullOrEmpty
        }
    }

    It 'keeps a native lifecycle conflict sticky through a later running status and a duplicate reimport' {
        InModuleScope aos {
            (Reserve-AosActor -Id sticky-run -Vendor claude -Task sticky-task).Ok | Should -BeTrue
            $null = Set-AosActorState -Id sticky-run -State running
            $null = Set-AosRunState -Id sticky-run -State running
        }
        $signal = New-FollowSignal 'sticky-run'
        Write-FollowFile (Join-Path $env:AOS_COORD 'native-signals\sticky-run.jsonl') ($signal + "`n")
        InModuleScope aos {
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $null = Import-AosNativeSignals -RunId sticky-run
            (Get-AosRunState sticky-run)['state'] | Should -Be 'needs-inspection'
            $null = Set-AosRunState -Id sticky-run -State running -Text 'ordinary status update'
            $run = Get-AosRunState sticky-run
            $run['native_inspection_required'] | Should -BeTrue
            $null = Import-AosNativeSignals -RunId sticky-run
            (Get-AosRunState sticky-run)['native_inspection_required'] | Should -BeTrue
        }
        # The delegate decides acceptance from this durable flag, not from the transient state string.
        Get-Content -LiteralPath (Join-Path $env:AOS_COORD 'delegations\sticky-run\run.json') -Raw | Should -Match '"native_inspection_required":\s*true'
    }

    Context 'turn steering' {
        BeforeEach {
            InModuleScope aos {
                . (Join-Path $script:Root 'config\native-coordination.ps1')
                $null = Reserve-AosActor -Id steer-run -Vendor codex -Task steer-task
                $null = Set-AosRunState -Id steer-run -State running
                $run = Get-AosRunState steer-run
                $run['transport'] = 'app-server'; $run['active_turn_id'] = 'turn-1'
                Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'delegations\steer-run\run.json') -Value $run
            }
            $steerPath = Join-Path $env:AOS_COORD 'delegations\steer-run\steering.json'
            $ackPath = Join-Path $env:AOS_COORD 'delegations\steer-run\steering-ack.json'
        }

        It 'refuses to overwrite an unacknowledged request and keeps unknown ack identities pending' {
            $first = InModuleScope aos { Send-AosTurnSteering -RunId steer-run -Text 'first request' -ExpectedTurnId turn-1 }
            $bytes = [IO.File]::ReadAllBytes($steerPath)
            { InModuleScope aos { Send-AosTurnSteering -RunId steer-run -Text 'second request' -ExpectedTurnId turn-1 } } | Should -Throw
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($steerPath)) | Should -BeExactly ([Convert]::ToBase64String($bytes))
            $state = InModuleScope aos { Get-AosTurnSteering -RunId steer-run }
            $state.pending | Should -BeTrue
            $state.request.id | Should -Be $first.id
            Write-FollowFile $ackPath '{"id":"someone-else","status":"accepted","turn_id":"turn-1"}'
            (InModuleScope aos { Get-AosTurnSteering -RunId steer-run }).pending | Should -BeTrue
            { InModuleScope aos { Send-AosTurnSteering -RunId steer-run -Text 'third request' -ExpectedTurnId turn-1 } } | Should -Throw
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($steerPath)) | Should -BeExactly ([Convert]::ToBase64String($bytes))
        }

        It 'allows the next request after a matching accepted or rejected acknowledgement' {
            foreach ($status in @('accepted', 'rejected')) {
                $sent = InModuleScope aos -Parameters @{ S = $status } { param($S) Send-AosTurnSteering -RunId steer-run -Text "request before $S" -ExpectedTurnId turn-1 }
                Write-FollowFile $ackPath (ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $sent.id; status = $status; turn_id = 'turn-1' }))
                $state = InModuleScope aos { Get-AosTurnSteering -RunId steer-run }
                $state.pending | Should -BeFalse -Because $status
                $state.ack.status | Should -Be $status
                $next = InModuleScope aos { Send-AosTurnSteering -RunId steer-run -Text 'next request' -ExpectedTurnId turn-1 }
                $next.id | Should -Not -Be $sent.id
                (InModuleScope aos { Get-AosTurnSteering -RunId steer-run }).pending | Should -BeTrue
                Write-FollowFile $ackPath (ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $next.id; status = 'accepted'; turn_id = 'turn-1' }))
            }
        }
    }

    It 'reports existing managed role files as stale for an unreviewed Codex version and leaves unowned files alone' {
        InModuleScope aos -Parameters @{ Case = $caseRoot } {
            param($Case)
            . (Join-Path $script:Root 'config\native-coordination.ps1')
            $codex = Join-Path $Case 'codex'; $claude = Join-Path $Case 'claude'
            $known = Get-AosNativeCapabilities -ClaudeVersion '2.1.296' -CodexVersion '0.157.1'
            $null = Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $known
            $managed = Join-Path $codex 'agents\aos-explore.toml'
            $unowned = Join-Path $codex 'agents\aos-verify.toml'
            [IO.File]::WriteAllText($unowned, '# personal role')
            $managedBytes = [IO.File]::ReadAllText($managed)
            $unknown = Get-AosNativeCapabilities -ClaudeVersion '2.1.296' -CodexVersion '99.0.0'
            $results = @(Sync-AosNativeRoles -CodexHome $codex -ClaudeHome $claude -Capabilities $unknown)
            ($results | Where-Object { $_.vendor -eq 'codex' -and $_.role -eq 'explore' }).status | Should -Be 'unsupported-existing-managed'
            ($results | Where-Object { $_.vendor -eq 'codex' -and $_.role -eq 'verify' }).status | Should -Not -Be 'unsupported-existing-managed'
            [IO.File]::ReadAllText($unowned) | Should -BeExactly '# personal role'
            [IO.File]::ReadAllText($managed) | Should -BeExactly $managedBytes
        }
    }
}
