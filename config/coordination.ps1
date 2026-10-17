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

function Test-AosActorActive($Actor) {
    return ($null -ne $Actor -and $Actor['state'] -in @('reserved', 'running', 'waiting-input', 'suspect'))
}

function Read-AosActorStore {
    $path = Join-Path (Get-AosCoordDir) 'actors.json'
    if (-not (Test-Path -LiteralPath $path)) { return [ordered]@{ version = 1; actors = [ordered]@{} } }
    $store = Read-AosJson $path
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
            catch [ArgumentException] { $row['state']='failed'; $row['text']='own process confirmed ended' }
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

function Invoke-AosCoordControl([string[]]$Arguments) {
    $sub = @($Arguments)[0]
    $rest = @($Arguments | Select-Object -Skip 1)
    $p = ConvertFrom-AosCliArgs $rest @() @('as','task','parent','kind','workers','handle','evidence','process','started','state','text') @()
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
        { $_ -in @('observe','finish') } {
            $state=$p.Opts['state']; if (-not $state) { if ($sub -eq 'finish') { $state='done' } else { $state='running' } }
            $r = Set-AosActorState -Id $id -State $state -Text $p.Opts['text'] -Handle $p.Opts['handle'] `
                -Evidence $p.Opts['evidence'] -ProcessId ([int]$p.Opts['process']) -ProcessStarted $p.Opts['started']
            Write-Host (ConvertTo-Json -InputObject $r -Depth 10); $global:LASTEXITCODE=0
        }
        default { throw 'usage: aos coord reserve|observe|finish|actors|reconcile' }
    }
}
