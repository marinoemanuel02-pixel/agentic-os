# Local process fixture only: no models, account calls or user-profile writes.
param([string]$OutputPath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$utf8=New-Object Text.UTF8Encoding($false)
$modulePath=(Resolve-Path (Join-Path $PSScriptRoot '..\aos.psm1')).ProviderPath
$module=Import-Module $modulePath -Force -DisableNameChecking -PassThru
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('aos-coordination-smoke-'+[guid]::NewGuid().ToString('N'))
$saved=@{}
foreach ($name in @('AOS_COORD','AOS_WORKTREES','AOS_BACKUPS')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$responder=$null
try {
    $env:AOS_COORD=Join-Path $fixture 'coord'
    $env:AOS_WORKTREES=Join-Path $fixture 'worktrees'
    $env:AOS_BACKUPS=Join-Path $fixture 'backups'
    New-Item -ItemType Directory -Path $fixture | Out-Null
    & $module {
        foreach ($r in @((Reserve-AosActor -Id lead -Vendor codex -Task smoke),
            (Reserve-AosActor -Id worker -Vendor claude -Task smoke -Parent lead -Kind delegate),
            (Reserve-AosActor -Id allowance -Vendor codex -Task smoke -Parent lead -Kind native))) {
            if (-not $r.Ok) { throw $r.Reason }
        }
        Set-AosRunState -Id worker -State preparing | Out-Null
    }
    $busy=& $module { Reserve-AosActor -Id third -Vendor codex -Task other }
    $value='fixture-'+[guid]::NewGuid().ToString('N')
    $replyScript=Join-Path $fixture 'reply.ps1'
    $reply=@'
$ErrorActionPreference='Stop'
$m=Import-Module $env:FIXTURE_MODULE -Force -DisableNameChecking -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(15)
do {
    $question=@(& $m { Get-AosTaskInbox lead })
    if ($question.Count) {
        & $m { param($Q) Send-AosTaskMessage -From lead -To worker -Text 'FIXTURE_VALUE' -ReplyTo $Q.id | Out-Null } $question[0]
        exit 0
    }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $deadline)
exit 8
'@
    [IO.File]::WriteAllText($replyScript,$reply.Replace('FIXTURE_VALUE',$value),$utf8)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=(Get-Command powershell.exe -ErrorAction Stop).Source
    $psi.Arguments=& $module { param($P) ConvertTo-AosArgString @('-NoProfile','-ExecutionPolicy','Bypass','-File',$P) } $replyScript
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.EnvironmentVariables['FIXTURE_MODULE']=$modulePath
    $responder=New-Object Diagnostics.Process; $responder.StartInfo=$psi; [void]$responder.Start()
    $workerPath=Join-Path $fixture 'worker.ps1'
    [IO.File]::WriteAllText($workerPath,@'
$ErrorActionPreference='Stop'
$m=Import-Module $env:FIXTURE_MODULE -Force -DisableNameChecking -PassThru
$marker='AOS_COORD_REQUEST:{"op":"question","to":"lead","text":"Which fixture value is required?"}'
[Console]::WriteLine((ConvertTo-Json -Compress -Depth 8 @{type='item.completed';item=@{type='command_execution';aggregated_output=$marker}}))
$deadline=[DateTime]::UtcNow.AddSeconds(12)
do {
    $inbox=@(& $m { Get-AosReadonlyInbox worker })
    if ($inbox.Count) { [Console]::WriteLine(('REPLY:'+ $inbox[0].text)); exit 0 }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $deadline)
exit 9
'@,$utf8)
    $run=& $module { param($P,$M,$O) Start-AosProcessCore -Exe powershell.exe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$P) `
        -TimeoutSeconds 18 -IdleSeconds 2 -LiveRunId worker -StdoutFile $O -Environment @{FIXTURE_MODULE=$M} } `
        $workerPath $modulePath (Join-Path $fixture 'events.jsonl')
    $replyOk=($run.Code -eq 0 -and $run.Out.Contains('REPLY:'+$value))
    if (-not $responder.WaitForExit(1000) -or $responder.ExitCode -ne 0) { throw 'fixture responder did not finish successfully' }
    & $module { Set-AosActorState worker done | Out-Null; Set-AosRunState worker accepted | Out-Null }
    $cancel=& $module {
        Reserve-AosActor -Id cancel -Vendor claude -Task smoke -Parent lead -Kind delegate | Out-Null
        Set-AosRunState -Id cancel -State preparing -Cancel | Out-Null
        $r=Start-AosProcessCore -Exe powershell.exe -Arguments @('-NoProfile','-Command','Start-Sleep 30') -TimeoutSeconds 8 -LiveRunId cancel
        $stopped=(-not (Get-Process -Id (Get-AosRunState cancel).process_id -ErrorAction SilentlyContinue))
        Set-AosActorState cancel cancelled | Out-Null
        return ($r.Cancelled -and -not $r.KillFailed -and $stopped)
    }
    $failed=& $module {
        Reserve-AosActor -Id failed -Vendor claude -Task smoke -Parent lead -Kind delegate | Out-Null
        $caught=$false
        try { Start-AosProcessCore -Exe 'aos-no-such-fixture.exe' -LiveRunId failed | Out-Null } catch { $caught=$true }
        Set-AosActorState failed failed -Text 'launch never started' | Out-Null
        return ($caught -and @(Get-AosActors | Where-Object { $_.id -eq 'failed' -and $_.state -eq 'failed' }).Count -eq 1)
    }
    $evidence=[ordered]@{ reply_required=$true; reply_received_while_alive=$replyOk; cancel_confirmed=[bool]$cancel;
        third_actor_refused=(-not $busy.Ok); launch_failure_cleaned=[bool]$failed;
        real_profile_untouched=((& $module { Get-AosCoordDir }) -eq (Join-Path $fixture 'coord'));
        worker_exit=$run.Code; transport='completed tool-output fixture'; model_calls=0 }
    if (@($evidence.Keys | Where-Object { $evidence[$_] -is [bool] -and -not $evidence[$_] }).Count) { throw 'coordination smoke acceptance failed' }
    $json=ConvertTo-Json -InputObject $evidence -Depth 10
    if ($OutputPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,$utf8) }
    [Console]::WriteLine($json)
}
finally {
    if ($responder) {
        if (-not $responder.HasExited) { $responder.Kill(); [void]$responder.WaitForExit(5000) }
        $responder.Dispose()
    }
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    $resolved=[IO.Path]::GetFullPath($fixture)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
