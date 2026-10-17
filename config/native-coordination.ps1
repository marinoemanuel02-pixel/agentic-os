# Internal native role and lifecycle helpers. Dot-sourced into aos; ASCII and PS 5.1 compatible.

function ConvertTo-AosNativeVersion([string]$Text) {
    if ($Text -match '(?:^|\s)(\d+\.\d+\.\d+)(?:\s|$)') { return $Matches[1] }
    return $null
}

function Read-AosNativeVersion([string]$Vendor) {
    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $result = Invoke-AosProcess -Exe $Vendor -Arguments @('--version') -StdoutFile $outFile -StderrFile $errFile -TimeoutSeconds 15
        if ($result.Code -eq 0) { return (ConvertTo-AosNativeVersion ([IO.File]::ReadAllText($outFile))) }
    }
    catch { }
    finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Get-AosNativeCapabilities {
    param([AllowEmptyString()][string]$ClaudeVersion, [AllowEmptyString()][string]$CodexVersion)
    if (-not $PSBoundParameters.ContainsKey('ClaudeVersion')) { $ClaudeVersion = Read-AosNativeVersion claude }
    if (-not $PSBoundParameters.ContainsKey('CodexVersion')) { $CodexVersion = Read-AosNativeVersion codex }
    $claudeText = ConvertTo-AosNativeVersion $ClaudeVersion
    $codexText = ConvertTo-AosNativeVersion $CodexVersion
    $claude = $null; if ($claudeText) { $claude = [version]$claudeText }
    $claudeKnown = [bool]($claude -and $claude -ge [version]'2.1.246')
    $effort = [bool]($claude -and $claude -ge [version]'2.1.292')
    $compact = [bool]($claude -and $claude -ge [version]'2.1.296')
    # Exact reviewed release, not an open-ended minimum-version guess. Update only after schema review.
    $codexKnown = $codexText -eq '0.157.1'
    $claudeLimits = @('Native role instructions do not establish a separate sandbox or global admission cap.')
    if (-not $claudeKnown) { $claudeLimits += 'Native role and partial turn-limit behavior unavailable for this version.' }
    if (-not $effort) { $claudeLimits += 'Per-invocation effort unverified; no effort override rendered.' }
    if (-not $compact) { $claudeLimits += 'Compact-window and unknown-field diagnostics unavailable for this version.' }
    $codexLimits = @('Native max-turn enforcement unverified; max_turns is an advisory task budget.',
        'Role files do not establish a separate sandbox or a global two-actor cap.')
    if (-not $codexKnown) { $codexLimits += 'This Codex release has no reviewed native-role capability record.' }
    return [pscustomobject][ordered]@{
        claude = [pscustomobject][ordered]@{
            version=$claudeText; nativeRoleFiles=$claudeKnown; model=$claudeKnown; perInvocationEffort=$effort;
            compactWindow=$compact; unknownFieldDiagnostics=$compact; maxTurnsPartial=$claudeKnown;
            evidence='https://code.claude.com/docs/en/sub-agents (reviewed 2026-10-17; child settings unobserved)';
            limitations=@($claudeLimits)
        }
        codex = [pscustomobject][ordered]@{
            version=$codexText; nativeRoleFiles=$codexKnown; model=$codexKnown; reasoningEffort=$codexKnown;
            maxTurns=$false; concurrentThreadLimitSetting=$codexKnown;
            evidence='https://learn.chatgpt.com/docs/agent-configuration/subagents (0.157.1 reviewed 2026-10-17; child settings unobserved)';
            limitations=@($codexLimits)
        }
    }
}

function Get-AosNativeRole {
    param([ValidateSet('claude','codex')][string]$Vendor, [ValidateSet('explore','implement','verify')][string]$Role,
        [ValidateSet('light','standard','deep')][string]$Tier, [ValidateRange(1,100)][int]$MaxTurns = 12, $Capabilities)
    if (-not $Vendor -or -not $Role) { throw 'native role needs vendor and role' }
    $definition = (Read-AosJson (Join-Path $script:Root 'config\native-roles.json'))['roles'][$Role]
    if (-not $definition) { throw 'native role definition missing' }
    if (-not $Tier) { $Tier = [string]$definition['default_tier'] }
    if (-not $PSBoundParameters.ContainsKey('MaxTurns')) { $MaxTurns = [int]$definition['max_turns'] }
    if (-not $Capabilities) { $Capabilities = Get-AosNativeCapabilities }
    $support = $Capabilities.$Vendor
    $route = Resolve-AosTaskRoute -Vendor $Vendor -Tier $Tier
    $settings = [ordered]@{}
    $limitations = @($support.limitations)
    if ($support.nativeRoleFiles) {
        if ($route.Model -and $support.model) { $settings['model'] = $route.Model }
        if ($Vendor -eq 'claude') {
            if ($route.Effort -and $support.perInvocationEffort) { $settings['effort'] = $route.Effort }
            if ($support.maxTurnsPartial) { $settings['maxTurns'] = $MaxTurns }
        }
        elseif ($route.Effort -and $support.reasoningEffort) { $settings['model_reasoning_effort'] = $route.Effort }
    }
    if ($route.Effort -and -not $settings.Contains('effort') -and -not $settings.Contains('model_reasoning_effort')) {
        $limitations += 'Requested effort omitted because native support is unverified.'
    }
    return [pscustomobject][ordered]@{
        vendor=$Vendor; role=$Role; tier=$route.Tier; route_reason=$route.Reason;
        description=$definition['description']; instructions=$definition['instructions']; max_turns=$MaxTurns;
        requested_model=$route.Model; requested_effort=$route.Effort; observed_model=$null; observed_effort=$null;
        settings=$settings; limitations=@($limitations)
    }
}

function Write-AosManagedNativeFile([string]$Path, [string]$Text, [string]$Marker, [switch]$DryRun) {
    if (Test-Path -LiteralPath $Path) {
        $old = [IO.File]::ReadAllText($Path)
        if ($old -ceq $Text) { return 'unchanged' }
        if (-not $old.Contains($Marker)) { Write-AosWarn "unmanaged native role left alone: $Path"; return 'skipped-unowned' }
        if ($DryRun) { return 'would-update' }
        $null = Backup-AosFile $Path
    }
    elseif ($DryRun) { return 'would-create' }
    Write-AosText -Path $Path -Text $Text
    return 'written'
}

function Sync-AosNativeRoles {
    param([string]$CodexHome, [string]$ClaudeHome, [switch]$DryRun, $Capabilities)
    if (-not $CodexHome) { $CodexHome = Get-AosCodexHome }
    if (-not $ClaudeHome) { $ClaudeHome = $env:AOS_CLAUDE_HOME; if (-not $ClaudeHome) { $ClaudeHome = Join-Path $HOME '.claude' } }
    if (-not $Capabilities) { $Capabilities = Get-AosNativeCapabilities }
    $marker = '# Generated by agentic-os native roles (managed).'
    $results = @()
    foreach ($vendor in @('claude','codex')) {
        $root = $CodexHome; if ($vendor -eq 'claude') { $root = $ClaudeHome }
        $support = $Capabilities.$vendor
        $profiles = [ordered]@{}
        foreach ($name in @('explore','implement','verify')) {
            $role = Get-AosNativeRole -Vendor $vendor -Role $name -Capabilities $Capabilities
            $profiles[$name] = $role
            if (-not $support.nativeRoleFiles) {
                $results += [pscustomobject]@{ vendor=$vendor; role=$name; status='unsupported' }; continue
            }
            $lines = @()
            $extension = 'toml'
            if ($vendor -eq 'claude') {
                $extension = 'md'
                $lines = @('---', $marker, ('name: aos-' + $name), ('description: ' + (ConvertTo-Json $role.description -Compress)))
                foreach ($key in $role.settings.Keys) {
                    $lines += $key + ': ' + (ConvertTo-Json -InputObject $role.settings[$key] -Compress)
                }
                $lines += @('---', '', $role.instructions, '', 'Report partial work when the turn budget is reached. Requested settings are not observations.')
            }
            else {
                $lines = @($marker, ('name = "aos-' + $name + '"'), ('description = ' + (ConvertTo-Json $role.description -Compress)),
                    ('developer_instructions = ' + (ConvertTo-Json ($role.instructions + ' Advisory turn budget: ' + $role.max_turns + '. Return partial work if it cannot be completed.') -Compress)))
                foreach ($key in $role.settings.Keys) { $lines += $key + ' = ' + (ConvertTo-Json -InputObject $role.settings[$key] -Compress) }
            }
            $target = Join-Path (Join-Path $root 'agents') ('aos-' + $name + '.' + $extension)
            $status = Write-AosManagedNativeFile -Path $target -Text (($lines -join "`n") + "`n") -Marker $marker -DryRun:$DryRun
            $results += [pscustomobject]@{ vendor=$vendor; role=$name; status=$status }
        }
        $profile = [ordered]@{ managed_by='agentic-os-native-roles'; capabilities=$support; roles=$profiles }
        $null = Write-AosManagedNativeFile -Path (Join-Path $root 'aos-native-capabilities.json') `
            -Text ((ConvertTo-Json -InputObject $profile -Depth 12) + "`n") -Marker 'agentic-os-native-roles' -DryRun:$DryRun
    }
    return $results
}

function Import-AosNativeSignals([string]$RunId) {
    Assert-AosCoordId $RunId
    $childId = $RunId + '-native-1'; Assert-AosCoordId $childId
    return (Invoke-AosCoordLocked {
        $run = Get-AosRunState $RunId
        if (-not $run -or $run['actor'] -ne $RunId) { throw 'native signals need a supervised run' }
        $path = Join-Path (Join-Path (Get-AosCoordDir) 'native-signals') ($RunId + '.jsonl')
        $diagnostics = New-Object 'System.Collections.Generic.List[string]'
        $processed = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
        foreach ($seen in @($run['native_signal_ids'])) { if ($seen) { $null = $processed.Add([string]$seen) } }
        $changed = $false; $imported = 0
        if (Test-Path -LiteralPath $path) {
            if ((Get-Item -LiteralPath $path).Length -gt 16777216) { throw 'native signal log too large; inspection required' }
            $text = Read-AosSharedText $path
            $lines = $text -split "`n", 0, 'SimpleMatch'
            # An append may be in flight. Only newline-terminated records are evidence.
            for ($index = 0; $index -lt $lines.Count - 1; $index++) {
                if (-not $lines[$index].Trim()) { continue }
                $signal = $null
                try {
                    $signal = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $lines[$index] -ErrorAction Stop)
                    if ($signal -isnot [Collections.IDictionary] -or $signal['run_id'] -ne $RunId -or $signal['source'] -ne 'claude-hook' -or
                        $signal['phase'] -notin @('start','stop')) { throw 'unmatched signal' }
                    $uuid = [guid]::Empty
                    if (-not [guid]::TryParseExact([string]$signal['id'], 'D', [ref]$uuid)) { throw 'invalid signal id' }
                    if ($signal['session_id'] -isnot [string] -or $signal['agent_id'] -isnot [string] -or
                        -not (ConvertFrom-AosUtcStamp (ConvertTo-AosStamp $signal['observed_at']))) { throw 'invalid signal metadata' }
                    Assert-AosCoordId ([string]$signal['session_id']); Assert-AosCoordId ([string]$signal['agent_id'])
                }
                catch { $diagnostics.Add('Malformed or unmatched native signal ignored.'); continue }
                $eventId = $uuid.ToString()
                if ($processed.Contains($eventId)) { continue }
                $null = $processed.Add($eventId); $changed = $true
                $store = Read-AosActorStore; $owner = $store['actors'][$RunId]; $child = $store['actors'][$childId]
                if (-not $owner -or -not $child -or $owner['vendor'] -ne 'claude' -or $owner['kind'] -notin @('lead','delegate') -or $child['vendor'] -ne 'claude' -or
                    $child['kind'] -ne 'native' -or $child['parent'] -ne $RunId -or $child['task'] -ne $owner['task']) {
                    $diagnostics.Add('Native signal does not match the reserved actor identity.'); continue
                }
                $reference = 'native-signals/' + $RunId + '.jsonl#' + $eventId
                $currentRun = Get-AosRunState $RunId
                $handle = [string]$signal['agent_id']
                if ($signal['phase'] -eq 'start') {
                    if ($child['state'] -eq 'reserved' -and -not $child['handle'] -and (Test-AosActorActive $owner) -and
                        $currentRun['state'] -in @('running','waiting-input')) {
                        $null = Set-AosActorState -Id $childId -State running -Handle $handle -Evidence $reference -Text 'observed Claude native start'
                        $currentRun['native_signal_session_id'] = [string]$signal['session_id']
                        Write-AosCoordJson -Path (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'run.json') -Value $currentRun
                        $imported++
                    }
                    elseif ($child['state'] -in @('running','waiting-input') -and $child['handle'] -eq $handle -and
                        $currentRun['native_signal_session_id'] -eq $signal['session_id']) { $imported++ }
                    else {
                        $null = Set-AosRunState -Id $RunId -State needs-inspection -Text 'native start conflicts with reserved handle or terminal state'
                        if (Test-AosActorActive $owner) { $null = Set-AosActorState -Id $RunId -State suspect -Text 'native lifecycle needs inspection' }
                        $diagnostics.Add('Conflicting native start requires inspection; no actor was allocated or revived.')
                    }
                }
                elseif ($child['state'] -in @('running','waiting-input') -and $child['handle'] -eq $handle -and
                    $currentRun['native_signal_session_id'] -eq $signal['session_id']) {
                    $null = Set-AosActorState -Id $childId -State done -Evidence $reference -Text 'observed Claude native stop'
                    $imported++
                }
                else { $diagnostics.Add('Unmatched native stop ignored; allowance not released.') }
            }
        }
        if ($changed) {
            $run = Get-AosRunState $RunId
            $run['native_signal_ids'] = @($processed | Sort-Object)
            Write-AosCoordJson -Path (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'run.json') -Value $run
        }
        return [pscustomobject]@{ imported=$imported; diagnostics=@($diagnostics.ToArray()) }
    })
}

function Send-AosTurnSteering {
    param([string]$RunId, [string]$Text, [string]$ExpectedTurnId)
    Assert-AosCoordId $RunId; Assert-AosCoordId $ExpectedTurnId
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 8000) { throw 'steering text must contain 1-8000 characters' }
    return (Invoke-AosCoordLocked {
        $run = Get-AosRunState $RunId
        if (-not $run -or $run['actor'] -ne $RunId -or $run['transport'] -ne 'app-server' -or
            $run['state'] -notin @('running','waiting-input') -or $run['active_turn_id'] -ne $ExpectedTurnId) {
            throw 'steering requires the exact active app-server turn'
        }
        $request = [ordered]@{ id=[guid]::NewGuid().ToString(); text=$Text; expected_turn_id=$ExpectedTurnId }
        Write-AosCoordJson -Path (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'steering.json') -Value $request
        return [pscustomobject]$request
    })
}
