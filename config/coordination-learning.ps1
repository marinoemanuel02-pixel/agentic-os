# Local measurements, checkpoints and outcome-backed procedures. No model or network calls.

function Set-AosReceiptPhase($Receipt,[Diagnostics.Stopwatch]$Clock,[string]$Phase) {
    if ($Receipt['_phase']) {
        $name=[string]$Receipt['_phase']
        $Receipt['phase_seconds'][$name]=[Math]::Round(([double]$Receipt['phase_seconds'][$name]+$Clock.Elapsed.TotalSeconds-[double]$Receipt['_phase_started']),4)
    }
    $Receipt['_phase']=$Phase;$Receipt['_phase_started']=$Clock.Elapsed.TotalSeconds
}

function Set-AosReceiptAnnotation([string]$RunId,[int]$Corrections=-1,[double]$IntegrationSeconds=-1,[double]$ReviewSeconds=-1,[string]$ReviewText) {
    if ($Corrections -lt -1 -or $IntegrationSeconds -lt -1 -or $ReviewSeconds -lt -1) { throw 'annotations cannot be negative' }
    return (Invoke-AosCoordLocked {
        $r=Read-AosEvidenceReceipt $RunId
        if ($Corrections -ge 0) { $r['corrections']=$Corrections }
        if (-not $r['phase_seconds']) { $r['phase_seconds']=[ordered]@{} }
        if ($IntegrationSeconds -ge 0) { $r['phase_seconds']['integration']=$IntegrationSeconds }
        if ($ReviewSeconds -ge 0) { $r['phase_seconds']['review']=$ReviewSeconds }
        if ($ReviewText) { if ($ReviewText.Length -gt 2000) { throw 'review note too large' };$r['review_choice']=$ReviewText }
        Write-AosCoordJson (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'receipt.json') $r
        return [pscustomobject]$r
    })
}

function Get-AosRouteReport {
    $root=Join-Path (Get-AosCoordDir) 'delegations';$rows=@();$bad=@()
    if (Test-Path -LiteralPath $root) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory)) {
            $file=Join-Path $dir.FullName 'receipt.json'
            if (-not (Test-Path -LiteralPath $file)) { continue }
            try {
                $r=Read-AosCoordJsonFile $file
                if ($r -isnot [Collections.IDictionary] -or $r['id'] -ne $dir.Name -or -not $r['outcome']) { throw 'invalid receipt identity or outcome' }
                $rows+=,$r
            } catch { $bad+= [ordered]@{id=$dir.Name;error=$_.Exception.Message} }
        }
    }
    $groups=@(foreach ($group in @($rows | Group-Object { @($_['task_class'],$_['vendor'],$_['tier'],$_['transport']) -join '|' })) {
        $items=@($group.Group);$observed=@($items | Where-Object {$_['usage_observed'] -eq $true})
        $input=$null;$output=$null
        if ($observed.Count) {
            $input=0L;$output=0L
            foreach ($r in $observed) { $input+=[long]$r['usage']['input'];$output+=[long]$r['usage']['output'] }
        }
        $timed=@($items | Where-Object {$null -ne $_['seconds']})
        $mean=$null; if ($timed.Count) { $mean=($timed | ForEach-Object {[double]$_['seconds']} | Measure-Object -Average).Average }
        [ordered]@{route=$group.Name;attempts=$items.Count;accepted=@($items | Where-Object {$_['accepted'] -eq $true -and $_['outcome'] -eq 'accepted'}).Count;
            measured_seconds=$timed.Count;mean_seconds=$mean;usage_unknown=($items.Count-$observed.Count);observed_input=$input;observed_output=$output;
            corrections_known=@($items | Where-Object {$null -ne $_['corrections']}).Count;attempt_ids=@($items | ForEach-Object {$_['id']})}
    })
    return [pscustomobject]@{attempts=$rows.Count;accepted=@($rows | Where-Object {$_['accepted'] -eq $true -and $_['outcome'] -eq 'accepted'}).Count;
        usage_unknown=@($rows | Where-Object {$_['usage_observed'] -ne $true}).Count;groups=$groups;unreadable=$bad;subscription_savings=$null;
        comparison='Compare only matching task classes and fixed checks; final outcome, corrections and end-to-end time precede usage.'}
}

function Get-AosTrackedManifest([string]$Repo) {
    $r=Invoke-AosGit -Dir $Repo -Arguments @('ls-files','-z')
    if ($r.Code -ne 0) { throw 'checkpoint needs a git repository' }
    $files=@($r.Out.Split([char]0) | Where-Object { $_ })
    foreach ($name in $files) {
        $path=Resolve-AosTaskFile $Repo $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Get-AosArtifactManifest $Repo @($name) }
        else { [ordered]@{path=$name;sha256=$null;missing=$true} }
    }
}

function Save-AosCheckpoint([string]$Id,[string]$Repo,[string[]]$TaskIds=@(),[string]$NextCheck) {
    Assert-AosCoordId $Id
    if (-not $NextCheck -or $NextCheck.Length -gt 4000) { throw 'checkpoint needs a bounded next check' }
    $repoPath=Get-AosCheckout $Repo
    $head=Invoke-AosGit -Dir $repoPath -Arguments @('rev-parse','HEAD')
    if ($head.Code -ne 0) { throw 'checkpoint needs a committed base' }
    return (Invoke-AosCoordLocked {
        $tasks=@(foreach ($taskId in @($TaskIds)) {
            $t=Get-AosTaskRecord $taskId
            if (-not $t -or $t['repo'] -ne $repoPath) { throw 'checkpoint task is missing or belongs to another repository' }
            [ordered]@{id=$taskId;state=$t['state'];active_run=$t['active_run'];accepted_run=$t['accepted_run'];artifacts=@($t['artifacts'])}
        })
        $actors=@(Get-AosActors | Where-Object {$_.state -in @('reserved','running','waiting-input','suspect')})
        $actorIds=@($actors | ForEach-Object {$_.id})
        $messages=@((Read-AosMessageStore)['messages'].Values | Where-Object {-not $_['acknowledged'] -and ($actorIds -contains $_['to'])} | ForEach-Object {$_['id']})
        $manifest=@(Get-AosTrackedManifest $repoPath)
        $snapshotDir=Join-Path (Join-Path (Get-AosCoordDir) 'checkpoints') ($Id+'.files')
        foreach ($entry in $manifest) {
            if ($entry['missing']) { continue }
            $blob=Join-Path $snapshotDir $entry['sha256']
            if (-not (Test-Path -LiteralPath $blob)) {
                New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null
                Copy-Item -LiteralPath (Resolve-AosTaskFile $repoPath $entry['path']) -Destination $blob
            }
            if ((Get-FileHash -LiteralPath $blob -Algorithm SHA256).Hash -ne $entry['sha256']) { throw 'checkpoint snapshot verification failed' }
        }
        $row=[ordered]@{version=1;id=$Id;repo=$repoPath;revision=$head.Out.Trim();artifacts=$manifest;snapshot_dir=($Id+'.files');
            tasks=$tasks;active_actors=@($actors | Select-Object id,state,handle,kind);unanswered_messages=$messages;next_check=$NextCheck;created=Get-AosUtcStamp}
        $path=Join-Path (Join-Path (Get-AosCoordDir) 'checkpoints') ($Id+'.json')
        Write-AosCoordJson $path $row
        Write-AosText -Path ([IO.Path]::ChangeExtension($path,'md')) -Text ("# Continuation $Id`n`nRevision: $($row.revision)`n`nNext check: $NextCheck`n`nRead the adjacent JSON, verify artifacts and inspect active actors before continuing.`n")
        return [pscustomobject]$row
    })
}

function Test-AosCheckpoint([string]$Id,[string]$Repo) {
    Assert-AosCoordId $Id
    $row=Read-AosCoordJsonFile (Join-Path (Join-Path (Get-AosCoordDir) 'checkpoints') ($Id+'.json'))
    if (-not $row -or $row['id'] -ne $Id -or $row['version'] -ne 1) { throw 'checkpoint not found or malformed' }
    $reasons=@();$repoPath=Get-AosCheckout $Repo
    if ($row['repo'] -ne $repoPath) { $reasons+='repository differs' }
    $head=Invoke-AosGit -Dir $repoPath -Arguments @('rev-parse','HEAD')
    if ($head.Code -ne 0 -or $head.Out.Trim() -ne $row['revision']) { $reasons+='revision changed' }
    if (-not (Test-AosArtifactManifest $repoPath $row['artifacts'])) { $reasons+='preserved file manifest changed' }
    foreach ($entry in @($row['artifacts'])) {
        if ($entry['missing']) { continue }
        if ($entry['sha256'] -notmatch '^[A-Fa-f0-9]{64}$') { $reasons+='invalid snapshot hash';continue }
        $blob=Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'checkpoints') ($Id+'.files')) $entry['sha256']
        if (-not (Test-Path -LiteralPath $blob -PathType Leaf) -or (Get-FileHash -LiteralPath $blob -Algorithm SHA256).Hash -ne $entry['sha256']) { $reasons+='snapshot missing or changed' }
    }
    $live=@(Get-AosActors | Where-Object {$_.state -in @('reserved','running','waiting-input','suspect')})
    if ($live.Count) { $reasons+='active actors need inspection; no slot was released' }
    foreach ($task in @($row['tasks'])) {
        $current=Get-AosTaskRecord $task['id']
        if (-not $current -or $current['state'] -ne $task['state'] -or $current['active_run'] -ne $task['active_run'] -or
            $current['accepted_run'] -ne $task['accepted_run']) { $reasons+='task state changed: '+$task['id'] }
        if (-not (Test-AosArtifactManifest $repoPath $task['artifacts'])) { $reasons+='task artifacts changed: '+$task['id'] }
    }
    return [pscustomobject]@{Valid=($reasons.Count -eq 0);Reasons=$reasons;Checkpoint=$row;ActiveActors=$live}
}

function Test-AosQuotaContinuation([string]$CheckpointId,[string]$Repo,[string]$FromVendor,[string]$ToVendor) {
    Assert-AosCoordId $CheckpointId
    if ($FromVendor -notin @('claude','codex') -or $ToVendor -notin @('claude','codex') -or $FromVendor -eq $ToVendor) {
        throw 'quota continuation needs two distinct supported vendors'
    }
    $reasons=@();$checkpoint=$null;$capacity=$null;$source=$null;$target=$null
    try {
        $checkpoint=Test-AosCheckpoint -Id $CheckpointId -Repo $Repo
        $reasons+=@($checkpoint.Reasons)
    } catch { $reasons+='checkpoint unavailable: '+$_.Exception.Message }
    try { $capacity=Get-AosCapacity -Now ([datetime]::UtcNow) }
    catch { $reasons+='capacity observations unavailable' }
    if ($capacity -and $capacity.Contains($FromVendor)) { $source=$capacity[$FromVendor] }
    if ($capacity -and $capacity.Contains($ToVendor)) { $target=$capacity[$ToVendor] }
    if (-not $source -or $source.state -ne 'limited') { $reasons+='source quota limit is not currently confirmed' }
    if (-not $target -or $target.state -notin @('ok','low') -or $null -eq $target.remaining -or
        $target.remaining -le 0 -or $target.remaining -gt 100) {
        $reasons+='target capacity is limited or unconfirmed; inspect usage and record a current observation'
    }
    $nextCheck=$null
    if ($checkpoint -and $checkpoint.Checkpoint) { $nextCheck=$checkpoint.Checkpoint.next_check }
    return [pscustomobject]@{
        Ready=($reasons.Count -eq 0);Reasons=$reasons;CheckpointId=$CheckpointId;FromVendor=$FromVendor;ToVendor=$ToVendor
        NextCheck=$nextCheck
        SourceCapacity=($source | Select-Object state,remaining,resets,reported,source)
        TargetCapacity=($target | Select-Object state,remaining,resets,reported,source)
        Action='Inspect HANDOFF.md and preserved material, then run NextCheck before further edits. No model was launched.'
    }
}

function Get-AosProcedureRoot([string]$Repo) {
    return (Join-Path (Join-Path (Get-AosCoordDir) 'procedures') (Get-AosClaimKey (Get-AosCheckout $Repo)))
}

function Save-AosProcedure {
    param([string]$Id,[string]$Repo,[string]$TaskClass,[string]$Text,[string[]]$EvidenceIds,[string[]]$Files)
    Assert-AosCoordId $Id
    if ($TaskClass -notin @('mechanical','implementation','sequential','diagnosis','research','consequential') -or
        -not $Text -or $Text.Length -gt 2000 -or -not @($Files).Count) { throw 'procedure needs a class, bounded text and file invalidation conditions' }
    $repoPath=Get-AosCheckout $Repo
    $manifest=Get-AosArtifactManifest $repoPath $Files
    $ids=@($EvidenceIds | Sort-Object -Unique)
    if ($ids.Count -lt 2) { throw 'procedure needs two distinct evidence receipts' }
    return (Invoke-AosCoordLocked {
        $evidence=@();$allGood=$true
        foreach ($runId in $ids) {
            $r=Read-AosEvidenceReceipt $runId
            if ($r['repo'] -ne $repoPath -or $r['task_class'] -ne $TaskClass) { throw 'procedure evidence belongs to another repository or class' }
            $good=Test-AosHostReceipt $r $repoPath ''
            if (-not $good) { $allGood=$false }
            $evidence+=[ordered]@{id=$runId;outcome=$r['outcome'];host_verified=$good}
        }
        $state='contradicted';if ($allGood) {$state='verified'}
        $head=Invoke-AosGit -Dir $repoPath -Arguments @('rev-parse','HEAD')
        $row=[ordered]@{version=1;id=$Id;repo=$repoPath;task_class=$TaskClass;text=$Text;state=$state;revision=$head.Out.Trim();
            evidence=$evidence;artifacts=@($manifest);updated=Get-AosUtcStamp;invalidation='Any relevant file hash or evidence outcome changes.'}
        $path=Join-Path (Get-AosProcedureRoot $repoPath) ($Id+'.json')
        $old=Read-AosCoordJsonFile $path
        if ($old) { $row['history']=@($old['history'])+@([ordered]@{state=$old['state'];evidence=$old['evidence'];updated=$old['updated']}) }
        Write-AosCoordJson $path $row
        return [pscustomobject]$row
    })
}

function Get-AosProcedures([string]$Repo,[string]$TaskClass,[switch]$IncludeStale) {
    $repoPath=Get-AosCheckout $Repo;$root=Get-AosProcedureRoot $repoPath
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File | Sort-Object Name)) {
        $row=Read-AosCoordJsonFile $file.FullName
        if (-not $row -or $row['repo'] -ne $repoPath -or $row['task_class'] -ne $TaskClass) { continue }
        $valid=($row['state'] -eq 'verified' -and (Test-AosArtifactManifest $repoPath $row['artifacts']))
        foreach ($entry in @($row['evidence'])) {
            try { if (-not (Test-AosHostReceipt (Read-AosEvidenceReceipt $entry['id']) $repoPath '')) {$valid=$false} } catch {$valid=$false}
        }
        if (-not $valid -and $row['state'] -eq 'verified') { $row['state']='stale' }
        if ($valid -or $IncludeStale) { [pscustomobject]$row }
    }
}

function Invoke-AosTuningControl([string[]]$Arguments) {
    $sub=@($Arguments)[0]
    if ($sub -notin @('task','report','annotate','checkpoint','continuation','procedure','capabilities','roles','native','steer')) { return $false }
    $rest=@($Arguments | Select-Object -Skip 1)
    $p=ConvertFrom-AosCliArgs $rest @('include-stale','dry-run') @('as','repo','next-check','class','text','corrections','integration-seconds','review-seconds','turn','from','to') @('task','evidence','file')
    $first=@($p.Pos)[0];$second=@($p.Pos)[1];$repo=$p.Opts['repo'];if (-not $repo) {$repo=(Get-Location).ProviderPath}
    $result=$null;$ok=$true
    switch ($sub) {
        'report' { $result=Get-AosRouteReport }
        'task' {
            switch ($first) {
                'register' {$result=Register-AosTaskContract $second $repo}
                'show' {$result=Get-AosTaskRecord $second}
                'ready' {$result=Test-AosTaskReady $second $repo;$ok=$result.Ready}
                'packet' {$result=Get-AosTaskPacket $second $repo}
                default {throw 'usage: aos coord task register|show|ready|packet <file-or-id> --repo <path>'}
            }
        }
        'annotate' {
            $values=@{RunId=$first}
            foreach ($pair in @(@('corrections','Corrections'),@('integration-seconds','IntegrationSeconds'),@('review-seconds','ReviewSeconds'),@('text','ReviewText'))) {
                if ($p.Opts.Contains($pair[0])) { $values[$pair[1]]=$p.Opts[$pair[0]] }
            }
            $result=Set-AosReceiptAnnotation @values
        }
        'checkpoint' {
            if ($first -eq 'save') {
                $taskIds=@();if ($p.Opts.Contains('task')) {$taskIds=@($p.Opts['task'])}
                $result=Save-AosCheckpoint -Id $second -Repo $repo -TaskIds $taskIds -NextCheck $p.Opts['next-check']
            }
            elseif ($first -eq 'check') {$result=Test-AosCheckpoint $second $repo;$ok=$result.Valid}
            else {throw 'usage: aos coord checkpoint save|check <id> --repo <path> [--task <id>] [--next-check <text>]'}
        }
        'continuation' {
            if ($first -ne 'check') { throw 'usage: aos coord continuation check <checkpoint-id> --repo <path> --from <vendor> --to <vendor>' }
            $result=Test-AosQuotaContinuation -CheckpointId $second -Repo $repo -FromVendor $p.Opts['from'] -ToVendor $p.Opts['to']
            $ok=$result.Ready
        }
        'procedure' {
            if ($first -eq 'save') {$result=Save-AosProcedure -Id $second -Repo $repo -TaskClass $p.Opts['class'] -Text $p.Opts['text'] -EvidenceIds @($p.Opts['evidence']) -Files @($p.Opts['file'])}
            elseif ($first -eq 'list') {$result=@(Get-AosProcedures -Repo $repo -TaskClass $p.Opts['class'] -IncludeStale:([bool]$p.Opts['include-stale']))}
            else {throw 'usage: aos coord procedure save <id>|list --repo <path> --class <class>'}
        }
        'capabilities' {$result=Get-AosNativeCapabilities}
        'roles' {$result=Sync-AosNativeRoles -DryRun:([bool]$p.Opts['dry-run'])}
        'native' {$result=Import-AosNativeSignals -RunId $first}
        'steer' {
            if ($p.Opts['text']) {$result=Send-AosTurnSteering -RunId $first -Text $p.Opts['text'] -ExpectedTurnId $p.Opts['turn']}
            else {$result=Get-AosTurnSteering -RunId $first}
        }
    }
    Write-Host (ConvertTo-Json -InputObject $result -Depth 20)
    $global:LASTEXITCODE=0;if (-not $ok) {$global:LASTEXITCODE=1}
    return $true
}
