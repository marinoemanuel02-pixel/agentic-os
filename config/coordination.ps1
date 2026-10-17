# Internal aos coordination helpers. Dot-sourced into the aos module; PS 5.1 and ASCII only.

function Resolve-AosTaskRoute {
    param([string]$Vendor, [string]$Tier = 'standard', [string]$Model, [string]$Effort)
    if ($Vendor -notin @('claude', 'codex')) { throw 'routing needs claude or codex' }
    if (-not $Tier) { $Tier = 'standard' }
    if ($Tier -notin @('light', 'standard', 'deep')) { throw 'tier must be light, standard or deep' }
    $routePath = $env:AOS_ROUTING
    if (-not $routePath) { $routePath = Join-Path (Get-AosStateDir) 'routing.json' }
    $mapping = $null
    if (Test-Path -LiteralPath $routePath) {
        $mapping = Read-AosJson $routePath
        if ($mapping -isnot [System.Collections.IDictionary]) { throw 'routing map must be a JSON object' }
    }
    $selectedTier = $Tier
    $reason = 'vendor default; no cost saving measured'
    $entry = $null
    if ($mapping -and $mapping[$Vendor]) {
        if ($mapping[$Vendor] -isnot [System.Collections.IDictionary]) { throw 'vendor routing map must be an object' }
        $entry = $mapping[$Vendor][$Tier]
    }
    if (-not $entry -and $Tier -ne 'standard') {
        $selectedTier = 'standard'
        $reason = "$Tier tier unmapped; using standard/default, cost unknown"
        if ($mapping -and $mapping[$Vendor]) { $entry = $mapping[$Vendor]['standard'] }
    }
    elseif ($entry) { $reason = 'local tier mapping; cost saving not inferred' }
    if ($entry) {
        if ($entry -isnot [System.Collections.IDictionary]) { throw 'tier routing must be an object' }
        if (-not $Model) { $Model = [string]$entry['model'] }
        if (-not $Effort) { $Effort = [string]$entry['effort'] }
    }
    if ($Effort) {
        $Effort = $Effort.ToLowerInvariant()
        $allowed = @('low', 'medium', 'high', 'xhigh', 'max')
        if ($Vendor -eq 'codex') { $allowed += @('none', 'minimal', 'ultra') }
        if ($Effort -notin $allowed) { throw "unsupported $Vendor effort: $Effort" }
    }
    return [pscustomobject]@{ Model = $Model; Effort = $Effort; Tier = $selectedTier; Reason = $reason }
}

function Assert-AosCoordId([string]$Id) {
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$' -or
        $Id -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'invalid coordination id' }
}

function Write-AosCoordJson([string]$Path, $Value) {
    # Call under the coordination lock. Readers see the old or the new complete JSON document.
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $temp = Join-Path $dir ('.coord-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, ((ConvertTo-Json -InputObject $Value -Depth 20) + "`n"), $script:Utf8NoBom)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Read-AosCoordJsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    $reader = New-Object IO.StreamReader($stream, $script:Utf8NoBom)
    try { return (ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $reader.ReadToEnd() -ErrorAction Stop)) }
    finally { $reader.Dispose() }
}

function Test-AosActorActive($Actor) {
    return ($null -ne $Actor -and $Actor['state'] -in @('reserved', 'running', 'waiting-input', 'suspect'))
}

function Read-AosActorStore {
    $path = Join-Path (Get-AosCoordDir) 'actors.json'
    if (-not (Test-Path -LiteralPath $path)) { return [ordered]@{ version = 1; actors = [ordered]@{} } }
    $store = Read-AosCoordJsonFile $path
    if ($store -isnot [Collections.IDictionary] -or $store['version'] -ne 1 -or
        $store['actors'] -isnot [Collections.IDictionary]) { throw 'invalid actor registry; inspect it before admitting work' }
    foreach ($key in @($store['actors'].Keys)) {
        $row = $store['actors'][$key]
        Assert-AosCoordId $key
        if ($row -isnot [Collections.IDictionary] -or $row['id'] -ne $key -or
            $row['vendor'] -notin @('claude','codex') -or $row['kind'] -notin @('lead','delegate','native') -or
            $row['state'] -notin @('reserved','running','waiting-input','suspect','done','failed','cancelled')) {
            throw 'invalid actor row; admission stopped'
        }
    }
    return $store
}

function Reserve-AosActor {
    param([string]$Id, [string]$Vendor, [string]$Task, [string]$Parent, [string]$Kind = 'lead',
        [string]$Handle, [string]$Evidence, [int]$ProcessId = 0, [string]$ProcessStarted, [int]$Workers = 0)
    try {
        Assert-AosCoordId $Id
        if (-not $Task) { $Task = $Id }
        Assert-AosCoordId $Task
        if ($Parent) { Assert-AosCoordId $Parent }
        if ($Vendor -notin @('claude','codex') -or $Kind -notin @('lead','delegate','native') -or $Workers -notin @(0,1)) {
            throw 'invalid actor vendor, kind or worker allowance'
        }
        return (Invoke-AosCoordLocked {
            $store = Read-AosActorStore
            $rows = $store['actors']
            $old = $rows[$Id]
            if ($old) {
                if (-not (Test-AosActorActive $old) -or $old['vendor'] -ne $Vendor -or $old['task'] -ne $Task -or
                    $old['parent'] -ne $Parent -or $old['kind'] -ne $Kind -or [int]$old['workers'] -ne $Workers) {
                    throw 'actor identity already exists; use a new id for another attempt'
                }
                return [pscustomobject]@{ Ok = $true; Reason = 'already reserved'; Actor = [pscustomobject]$old }
            }
            if ($Parent) {
                $owner = $rows[$Parent]
                if (-not (Test-AosActorActive $owner) -or $owner['task'] -ne $Task -or $Kind -eq 'lead' -or
                    $owner['kind'] -eq 'native' -or ($Kind -eq 'delegate' -and $owner['kind'] -ne 'lead') -or
                    ($Kind -eq 'native' -and $owner['vendor'] -ne $Vendor)) { throw 'invalid parent or delegation depth' }
            }
            elseif ($Kind -eq 'native') { throw 'native work requires an active parent' }
            $active = @($rows.Values | Where-Object { $_['vendor'] -eq $Vendor -and (Test-AosActorActive $_) }).Count
            if ($active + 1 + $Workers -gt 2) { throw "busy: $Vendor has insufficient actor slots" }
            $childId = $Id + '-native-1'
            if ($Workers) {
                Assert-AosCoordId $childId
                if ($rows.Contains($childId) -or $Kind -eq 'native') { throw 'invalid native allowance' }
            }
            if ($ProcessId -gt 0 -and -not $ProcessStarted) {
                try { $ProcessStarted = (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o') }
                catch { throw 'cannot establish actor process identity' }
            }
            $stamp = Get-AosUtcStamp
            $row = [ordered]@{ id=$Id; vendor=$Vendor; task=$Task; parent=$Parent; kind=$Kind; state='reserved';
                workers=$Workers; handle=$Handle; evidence=$Evidence; coverage='cooperative'; text='';
                process_id=$ProcessId; process_started=$ProcessStarted; created=$stamp; updated=$stamp }
            $rows[$Id] = $row
            if ($Workers) {
                $rows[$childId] = [ordered]@{ id=$childId; vendor=$Vendor; task=$Task; parent=$Id; kind='native';
                    state='reserved'; workers=0; handle=''; evidence=''; coverage='cooperative'; text='reserved allowance';
                    process_id=0; process_started=''; created=$stamp; updated=$stamp }
            }
            Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'actors.json') -Value $store
            return [pscustomobject]@{ Ok = $true; Reason = 'reserved'; Actor = [pscustomobject]$row }
        })
    }
    catch { return [pscustomobject]@{ Ok = $false; Reason = $_.Exception.Message; Actor = $null } }
}

function Get-AosActors {
    return (Invoke-AosCoordLocked { $store = Read-AosActorStore; @($store['actors'].Values | ForEach-Object { [pscustomobject]$_ }) })
}

function Set-AosActorState {
    param([string]$Id, [string]$State, [string]$Text, [string]$Handle, [string]$Evidence,
        [int]$ProcessId = 0, [string]$ProcessStarted)
    Assert-AosCoordId $Id
    if ($State -notin @('reserved','running','waiting-input','suspect','done','failed','cancelled')) { throw 'invalid actor state' }
    return (Invoke-AosCoordLocked {
        $store = Read-AosActorStore
        $row = $store['actors'][$Id]
        if (-not $row) { throw 'unknown actor' }
        if (-not (Test-AosActorActive $row)) {
            if ($row['state'] -eq $State) { return [pscustomobject]$row }
            throw 'terminal actor cannot change state'
        }
        $terminal = $State -in @('done','failed','cancelled')
        if ($row['kind'] -eq 'native') {
            if ($State -eq 'running' -and (-not $Handle -or -not $Evidence)) { throw 'native launch needs a handle and evidence reference' }
            if ($terminal -and $row['handle'] -and -not $Evidence) { throw 'native termination needs its own evidence' }
        }
        if ($terminal) {
            $children = @($store['actors'].Values | Where-Object { $_['parent'] -eq $Id -and (Test-AosActorActive $_) })
            foreach ($child in $children) {
                if ($child['kind'] -ne 'native' -or $child['handle'] -or $child['state'] -ne 'reserved') { throw 'active children need terminal evidence before parent completion' }
            }
            foreach ($child in $children) { $child['state']='cancelled'; $child['text']='allowance never launched'; $child['updated']=Get-AosUtcStamp }
        }
        $row['state']=$State; $row['text']=$Text; $row['updated']=Get-AosUtcStamp
        if ($Handle) { $row['handle']=$Handle }
        if ($Evidence) { $row['evidence']=$Evidence }
        if ($ProcessId -gt 0) { $row['process_id']=$ProcessId; $row['process_started']=$ProcessStarted }
        Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'actors.json') -Value $store
        return [pscustomobject]$row
    })
}

function Resolve-AosActors {
    return (Invoke-AosCoordLocked {
        $store = Read-AosActorStore
        foreach ($row in @($store['actors'].Values)) {
            if (-not (Test-AosActorActive $row) -or $row['kind'] -eq 'native' -or [int]$row['process_id'] -le 0) { continue }
            try {
                $live = [Diagnostics.Process]::GetProcessById([int]$row['process_id'])
                try {
                    $started = ConvertFrom-AosUtcStamp ([string]$row['process_started'])
                    if ($started -and [Math]::Abs(($live.StartTime.ToUniversalTime() - $started).TotalSeconds) -gt 1) {
                        $row['state']='suspect'; $row['text']='process identity changed; inspect before release'
                    }
                }
                finally { $live.Dispose() }
            }
            catch [ArgumentException] {
                $run=Get-AosRunState ([string]$row['id'])
                if ($run -and $run['state'] -in @('preparing','reserved','running','waiting-input','suspect','needs-inspection')) {
                    # The model can exit before host verification and receipt finalization finish.
                    $row['state']='suspect'; $row['text']='model process ended; host completion unconfirmed'
                }
                else { $row['state']='failed'; $row['text']='own process confirmed ended' }
            }
            catch { $row['state']='suspect'; $row['text']='process state unavailable; not released' }
        }
        foreach ($row in @($store['actors'].Values)) {
            $parent = $store['actors'][[string]$row['parent']]
            if ($row['kind'] -eq 'native' -and $row['state'] -eq 'reserved' -and -not $row['handle'] -and
                $parent -and -not (Test-AosActorActive $parent)) { $row['state']='cancelled'; $row['text']='allowance never launched' }
        }
        Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'actors.json') -Value $store
        @($store['actors'].Values | ForEach-Object { [pscustomobject]$_ })
    })
}

function Get-AosActorTreeRoot($Rows, [string]$Id) {
    $seen = @{}
    while ($Id) {
        if ($seen.ContainsKey($Id) -or -not $Rows[$Id]) { throw 'invalid actor ancestry' }
        $seen[$Id]=$true
        $row=$Rows[$Id]
        if (-not $row['parent']) { return $Id }
        $Id=[string]$row['parent']
    }
}

function Read-AosMessageStore {
    $path=Join-Path (Get-AosCoordDir) 'messages.json'
    if (-not (Test-Path -LiteralPath $path)) { return [ordered]@{ version=1; messages=[ordered]@{} } }
    $store=Read-AosCoordJsonFile $path
    if ($store -isnot [Collections.IDictionary] -or $store['version'] -ne 1 -or
        $store['messages'] -isnot [Collections.IDictionary]) { throw 'invalid message store; no messages acknowledged' }
    return $store
}

function Send-AosTaskMessage {
    param([string]$From, [string]$To, [string]$Text, [string]$ReplyTo)
    Assert-AosCoordId $From; Assert-AosCoordId $To
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 8000) { throw 'message text must contain 1-8000 characters' }
    if ($ReplyTo) { Assert-AosCoordId $ReplyTo }
    return (Invoke-AosCoordLocked {
        $actors=(Read-AosActorStore)['actors']
        if (-not $actors[$From] -or -not $actors[$To] -or $actors[$From]['task'] -ne $actors[$To]['task'] -or
            (Get-AosActorTreeRoot $actors $From) -ne (Get-AosActorTreeRoot $actors $To)) { throw 'messages must stay within one task tree' }
        $store=Read-AosMessageStore
        if ($ReplyTo) {
            $original=$store['messages'][$ReplyTo]
            if (-not $original -or $From -notin @($original['from'],$original['to']) -or
                $To -notin @($original['from'],$original['to'])) { throw 'reply does not refer to this actor pair' }
        }
        $id=[guid]::NewGuid().ToString('N')
        $message=[ordered]@{ id=$id; from=$From; to=$To; task=$actors[$From]['task']; text=$Text;
            reply_to=$ReplyTo; created=(Get-AosUtcStamp); acknowledged=$false }
        $store['messages'][$id]=$message
        Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'messages.json') -Value $store
        return [pscustomobject]$message
    })
}

function Get-AosTaskInbox {
    param([string]$Actor, [string[]]$AckIds)
    Assert-AosCoordId $Actor
    return (Invoke-AosCoordLocked {
        $actors=(Read-AosActorStore)['actors']
        if (-not $actors[$Actor]) { throw 'unknown inbox actor' }
        $store=Read-AosMessageStore
        $changed=$false
        foreach ($id in @($AckIds | Where-Object { $_ })) {
            Assert-AosCoordId $id
            $message=$store['messages'][$id]
            if ($message -and $message['to'] -eq $Actor -and -not $message['acknowledged']) {
                $message['acknowledged']=$true; $changed=$true
            }
        }
        if ($changed) { Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'messages.json') -Value $store }
        @($store['messages'].Values | Where-Object { $_['to'] -eq $Actor -and -not $_['acknowledged'] } |
            ForEach-Object { [pscustomobject]$_ })
    })
}

function Get-AosRunState([string]$Id) {
    Assert-AosCoordId $Id
    $path=Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $Id) 'run.json'
    $run=Read-AosCoordJsonFile $path
    if ($null -ne $run -and ($run -isnot [Collections.IDictionary] -or $run['id'] -ne $Id)) { throw 'invalid active run record' }
    return $run
}

function Set-AosRunState {
    param([string]$Id, [string]$State, [string]$Text, [int]$ProcessId=0, [string]$ProcessStarted, [switch]$Cancel)
    Assert-AosCoordId $Id
    if ($State -notin @('preparing','reserved','running','waiting-input','suspect','done','failed','cancelled',
        'accepted','rejected','busy','preflight-failed','timed-out','needs-inspection')) { throw 'invalid run state' }
    return (Invoke-AosCoordLocked {
        $run=Get-AosRunState $Id
        if (-not $run) {
            $actors=(Read-AosActorStore)['actors']
            if (-not $actors[$Id] -and $State -in @('running','preparing','waiting-input','reserved')) { throw 'active run needs an admitted actor' }
            $parent=''; if ($actors[$Id]) { $parent=[string]$actors[$Id]['parent'] }
            $run=[ordered]@{ id=$Id; actor=$Id; parent=$parent; state=$State; text=''; sequence=0;
                cancel_requested=$false; process_id=0; process_started=''; updated=''; waiting_seconds=0.0; waiting_since='' }
        }
        if (-not $run.Contains('waiting_seconds')) { $run['waiting_seconds']=0.0 }
        if ($run['waiting_since'] -and $State -ne 'waiting-input') {
            $since=[DateTime]::Parse($run['waiting_since']).ToUniversalTime()
            $run['waiting_seconds']=[Math]::Round(([double]$run['waiting_seconds']+[Math]::Max(0,([DateTime]::UtcNow-$since).TotalSeconds)),4)
            $run['waiting_since']=''
        }
        if ($State -eq 'waiting-input' -and -not $run['waiting_since']) { $run['waiting_since']=Get-AosUtcStamp }
        $run['state']=$State; $run['text']=$Text; $run['sequence']=[long]$run['sequence']+1; $run['updated']=Get-AosUtcStamp
        if ($ProcessId -gt 0) { $run['process_id']=$ProcessId; $run['process_started']=$ProcessStarted }
        if ($Cancel) { $run['cancel_requested']=$true }
        Write-AosCoordJson -Path (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $Id) 'run.json') -Value $run
        return [pscustomobject]$run
    })
}

function Get-AosReadonlyInbox([string]$Actor) {
    Assert-AosCoordId $Actor
    $actors=(Read-AosActorStore)['actors']
    if (-not $actors[$Actor]) { throw 'unknown inbox actor' }
    $store=Read-AosMessageStore
    @($store['messages'].Values | Where-Object { $_['to'] -eq $Actor -and -not $_['acknowledged'] } |
        ForEach-Object { [pscustomobject]$_ })
}

function Send-AosTaskQuestion([string]$RunId, [string]$To, [string]$Text, [string]$ReplyTo) {
    # Publish only after both waiting-state writes succeed. Roll back failed transitions under
    # the same lock so a delivered question cannot leave idle supervision in the old state.
    return (Invoke-AosCoordLocked {
        $actorsBefore=Read-AosActorStore
        $runBefore=Get-AosRunState $RunId
        if (-not $runBefore) { throw 'question needs an active run' }
        $runPath=Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'run.json'
        try {
            $null=Set-AosActorState -Id $RunId -State waiting-input -Text $Text
            $null=Set-AosRunState -Id $RunId -State waiting-input -Text $Text
            return (Send-AosTaskMessage -From $RunId -To $To -Text $Text -ReplyTo $ReplyTo)
        }
        catch {
            Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) 'actors.json') -Value $actorsBefore
            Write-AosCoordJson -Path $runPath -Value $runBefore
            throw
        }
    })
}

function Receive-AosCoordEvent([string]$RunId, [string]$JsonLine) {
    # Only completed vendor tool output is a transport. Assistant prose is never a request.
    $event=$null
    try { $event=ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $JsonLine -ErrorAction Stop) } catch { return }
    if ($event['type'] -in @('turn.started','turn.completed','turn.failed','account.rate_limits')) {
        Invoke-AosCoordLocked {
            $state=Get-AosRunState $RunId
            if ($state -and $state['actor'] -eq $RunId -and $state['transport'] -eq 'app-server') {
                if ($event['type'] -eq 'turn.started') { $state['active_turn_id']=$event['turn_id'];$state['thread_id']=$event['thread_id'] }
                elseif ($event['type'] -in @('turn.completed','turn.failed')) { $state['active_turn_id']='' }
                else { $state['rate_limits']=$event['rate_limits'];$state['rate_limits_by_limit_id']=$event['rate_limits_by_limit_id'] }
                Write-AosCoordJson (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'run.json') $state
            }
        }
    }
    $outputs=@()
    if ($event['type'] -eq 'item.completed' -and $event['item']['type'] -eq 'command_execution') {
        $outputs+= [string]$event['item']['aggregated_output']
    }
    elseif ($event['type'] -eq 'user' -and $event['message']) {
        foreach ($block in @($event['message']['content'])) {
            if ($block['type'] -ne 'tool_result') { continue }
            if ($block['content'] -is [string]) { $outputs+=$block['content'] }
            else { foreach ($part in @($block['content'])) { if ($part['type'] -eq 'text') { $outputs+=[string]$part['text'] } } }
        }
    }
    foreach ($output in $outputs) {
        foreach ($line in ($output -split '\r?\n')) {
            if ($line -notmatch '^AOS_COORD_REQUEST:(\{.*\})$') { continue }
            if ($line.Length -gt 12000) { throw 'coordination request too large' }
            $request=ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $Matches[1] -ErrorAction Stop)
            $run=Get-AosRunState $RunId
            if (-not $run -or $run['actor'] -ne $RunId) { throw 'request has no supervised actor' }
            switch ([string]$request['op']) {
                { $_ -in @('send','question') } {
                    if ($request['op'] -eq 'question') {
                        $null=Send-AosTaskQuestion -RunId $RunId -To ([string]$request['to']) -Text ([string]$request['text']) -ReplyTo ([string]$request['reply_to'])
                    }
                    else { $null=Send-AosTaskMessage -From $RunId -To ([string]$request['to']) -Text ([string]$request['text']) -ReplyTo ([string]$request['reply_to']) }
                }
                'ack' { $null=Get-AosTaskInbox -Actor $RunId -AckIds @($request['ack_ids']) }
                'status' {
                    if ($request['state'] -notin @('running','waiting-input')) { throw 'worker status must be running or waiting-input' }
                    $null=Set-AosActorState -Id $RunId -State $request['state'] -Text ([string]$request['text'])
                    $null=Set-AosRunState -Id $RunId -State $request['state'] -Text ([string]$request['text'])
                }
                default { throw 'unsupported worker coordination operation' }
            }
        }
    }
}

function Read-AosClaudeResult([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text=[IO.File]::ReadAllText($Path)
    try {
        $single=ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $text -ErrorAction Stop)
        if ($single -is [Collections.IDictionary]) { return $single }
    } catch { }
    $result=$null
    foreach ($line in ($text -split '\r?\n')) {
        try {
            $item=ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $line -ErrorAction Stop)
            if ($item['type'] -eq 'result') { $result=$item }
        } catch { }
    }
    return $result
}

function Invoke-AosWorkerCoord([string[]]$Arguments) {
    $actor=$env:AOS_ACTOR_ID
    Assert-AosCoordId $actor
    if ($env:AOS_RUN_ID -ne $actor) { throw 'worker actor/run identity mismatch' }
    $sub=@($Arguments)[0]
    $p=ConvertFrom-AosCliArgs @($Arguments | Select-Object -Skip 1) @() @('to','text','reply-to','state','seconds') @('ack')
    if (@($p.Pos).Count) { throw 'worker identity is supplied by the host; omit positional actor ids' }
    if ($sub -in @('inbox','wait')) {
        $seconds=0; if ($p.Opts['seconds']) { $seconds=[int]$p.Opts['seconds'] }
        if ($seconds -lt 0 -or $seconds -gt 45) { throw 'wait must be between 0 and 45 seconds' }
        $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
        do {
            $messages=@(Get-AosReadonlyInbox $actor)
            if ($sub -eq 'inbox' -or $messages.Count -or [DateTime]::UtcNow -ge $deadline) { break }
            Start-Sleep -Milliseconds 200
        } while ($true)
        [Console]::WriteLine((ConvertTo-Json -InputObject $messages -Depth 10 -Compress)); return
    }
    if ($sub -eq 'status' -and -not $p.Opts['state']) {
        [Console]::WriteLine((ConvertTo-Json -InputObject (Get-AosRunState $actor) -Depth 10 -Compress)); return
    }
    if ($sub -notin @('send','question','ack','status')) { throw 'worker supports send|question|inbox|wait|ack|status only' }
    $request=[ordered]@{ op=$sub; id=[guid]::NewGuid().ToString('N'); to=$p.Opts['to']; text=$p.Opts['text'];
        reply_to=$p.Opts['reply-to']; state=$p.Opts['state']; ack_ids=@($p.Opts['ack']) }
    [Console]::WriteLine(('AOS_COORD_REQUEST:' + (ConvertTo-Json -InputObject $request -Depth 10 -Compress)))
}

function Invoke-AosCoordControl([string[]]$Arguments) {
    if (Invoke-AosTuningControl $Arguments) { return }
    $sub = @($Arguments)[0]
    $rest = @($Arguments | Select-Object -Skip 1)
    $p = ConvertFrom-AosCliArgs $rest @() @('as','task','parent','kind','workers','handle','evidence','process','started','state','text','to','reply-to','seconds') @('ack')
    $id = @($p.Pos)[0]
    switch ($sub) {
        'reserve' {
            $workers = 0; if ($p.Opts['workers']) { $workers=[int]$p.Opts['workers'] }
            $r = Reserve-AosActor -Id $id -Vendor $p.Opts['as'] -Task $p.Opts['task'] -Parent $p.Opts['parent'] `
                -Kind $(if ($p.Opts['kind']) { $p.Opts['kind'] } else { 'lead' }) -Workers $workers `
                -Handle $p.Opts['handle'] -Evidence $p.Opts['evidence'] -ProcessId ([int]$p.Opts['process']) -ProcessStarted $p.Opts['started']
            $global:LASTEXITCODE=0; if (-not $r.Ok) { $global:LASTEXITCODE=1 }
            Write-Host (ConvertTo-Json -InputObject $r -Depth 10)
        }
        'actors' { Write-Host (ConvertTo-Json -InputObject @(Get-AosActors) -Depth 10); $global:LASTEXITCODE=0 }
        'reconcile' { Write-Host (ConvertTo-Json -InputObject @(Resolve-AosActors) -Depth 10); $global:LASTEXITCODE=0 }
        'send' {
            $r=Send-AosTaskMessage -From $id -To $p.Opts['to'] -Text $p.Opts['text'] -ReplyTo $p.Opts['reply-to']
            Write-Host (ConvertTo-Json -InputObject $r -Depth 10); $global:LASTEXITCODE=0
        }
        { $_ -in @('inbox','ack','wait') } {
            $seconds=0; if ($p.Opts['seconds']) { $seconds=[int]$p.Opts['seconds'] }
            if ($seconds -lt 0 -or $seconds -gt 45) { throw 'wait must be between 0 and 45 seconds' }
            $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
            do {
                $messages=@(Get-AosTaskInbox -Actor $id -AckIds @($p.Opts['ack']))
                if ($sub -ne 'wait' -or $messages.Count -gt 0 -or [DateTime]::UtcNow -ge $deadline) { break }
                Start-Sleep -Milliseconds 200
            } while ($true)
            Write-Host (ConvertTo-Json -InputObject $messages -Depth 10); $global:LASTEXITCODE=0
        }
        { $_ -in @('status','cancel') } {
            $run=Get-AosRunState $id
            $state=$p.Opts['state']; if (-not $state -and $run) { $state=[string]$run['state'] }
            if (-not $state) { $state='running' }
            if ($p.Opts['state'] -or $sub -eq 'cancel') {
                $run=Set-AosRunState -Id $id -State $state -Text $p.Opts['text'] -Cancel:($sub -eq 'cancel')
            }
            Write-Host (ConvertTo-Json -InputObject $run -Depth 10); $global:LASTEXITCODE=0
        }
        { $_ -in @('observe','finish') } {
            $state=$p.Opts['state']; if (-not $state) { if ($sub -eq 'finish') { $state='done' } else { $state='running' } }
            $r = Set-AosActorState -Id $id -State $state -Text $p.Opts['text'] -Handle $p.Opts['handle'] `
                -Evidence $p.Opts['evidence'] -ProcessId ([int]$p.Opts['process']) -ProcessStarted $p.Opts['started']
            Write-Host (ConvertTo-Json -InputObject $r -Depth 10); $global:LASTEXITCODE=0
        }
        default { throw 'usage: aos coord reserve|observe|finish|actors|reconcile|send|inbox|ack|wait|status|cancel' }
    }
}
