# Checked native-task bridge for API candidates. Compatible with PowerShell 5.1.
param([ValidateSet('prepare','verify','fail')][string]$Action)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$module = Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -PassThru -DisableNameChecking
try {
    $inputText = [Console]::In.ReadToEnd()
    $result = & $module {
        param($Mode,$Json)
        $r = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $Json)
        Assert-AosCoordId $r['id']
        $repo = Get-AosCheckout $r['repo']
        $task = Get-AosTaskRecord $r['id']
        if (-not $task -or $task['repo'] -ne $repo) { throw 'unknown task or repository mismatch' }
        if ($Mode -eq 'prepare') {
            $ready = Test-AosTaskReady $r['id'] $repo
            if (-not $ready.Ready) { throw 'prerequisites are not accepted' }
            $packet = Get-AosTaskPacket $r['id'] $repo
            if (-not $task['contract']['verify']) { throw 'host verifier required' }
            $run = 'swarm-' + [guid]::NewGuid().ToString('N')
            $runDir = Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $run
            $runPath = Join-Path $runDir 'run.json'
            $record = [ordered]@{ id=$run; actor=''; parent=''; worker_kind='api-pool';
                task_id=$r['id']; state='preparing'; cancel_requested=$false; sequence=0;
                process_id=[int]$r['process_id']; process_started=(Get-Process -Id ([int]$r['process_id'])).StartTime.ToUniversalTime().ToString('o');
                updated=Get-AosUtcStamp; text='API candidate; native actors unchanged' }
            # Existing cancellation can use this admitted API run; no native actor is fabricated.
            $null = Start-AosTaskAttempt $r['id'] $run
            Write-AosCoordJson $runPath $record
            return [ordered]@{ id=$r['id']; repo=$repo; run=$run; run_path=$runPath; packet=$packet;
                owner_session=$r['owner_session']; timeout_seconds=[Math]::Min(300,[Math]::Max(60,[int]$task['contract']['budget']['timeout_minutes']*60)) }
        }
        Assert-AosCoordId $r['run']
        if ($task['active_run'] -ne $r['run']) { throw 'run does not own task' }
        $run = Get-AosRunState $r['run']
        if (-not $run -or $run['worker_kind'] -ne 'api-pool' -or $run['task_id'] -ne $r['id']) { throw 'invalid API run' }
        $ok = $false
        $check = [ordered]@{ exit_code=1; argv=@(); artifacts=@() }
        if ($Mode -eq 'verify' -and -not $run['cancel_requested']) {
            $claim = @(Get-AosClaims | Where-Object { $_['checkout'] -eq $repo })
            if ($claim.Count -ne 1 -or -not $r['owner_session'] -or $claim[0]['session'] -ne $r['owner_session']) {
                throw 'host verifier requires the caller checkout claim'
            }
            $ready = Test-AosTaskReady $r['id'] $repo
            if (-not $ready.Ready) { throw 'prerequisite changed' }
            $candidate = [IO.Path]::GetFullPath($r['candidate'])
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'candidate missing' }
            $candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
            # Candidate path is passed through child environment, never interpolated into shell code.
            $oldCandidate = $env:AOS_SWARM_CANDIDATE
            try {
                $env:AOS_SWARM_CANDIDATE = $candidate
                $process = Invoke-AosProcess -Exe 'powershell' -Arguments @('-NoProfile','-NonInteractive','-Command',
                    [string]$task['contract']['verify']) -WorkingDirectory $repo -TimeoutSeconds 120 -IdleSeconds 120
            } finally { $env:AOS_SWARM_CANDIDATE = $oldCandidate }
            $run = Get-AosRunState $r['run']
            $unchanged = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -eq $candidateHash
            if ($process.KillFailed) { throw 'verifier process not confirmed stopped; inspect before completing task' }
            $ok = ($process.Code -eq 0 -and -not $process.TimedOut -and -not $run['cancel_requested'] -and $unchanged)
            $manifest = @()
            if ($ok) {
                $manifest = @(Get-AosArtifactManifest $repo @($task['contract']['artifacts']))
                $ready = Test-AosTaskReady $r['id'] $repo
                $ok = $ready.Ready
            }
            $check = [ordered]@{ exit_code=$process.Code; argv=@('registered contract verifier');
                artifacts=$manifest; candidate_sha256=$r['candidate_sha256']; command=[string]$task['contract']['verify'] }
        }
        $outcome = 'rejected'; if ($ok) { $outcome='accepted' }
        $receipt = [ordered]@{ id=$r['run']; task_id=$r['id']; worker_kind='api-pool'; vendor=$null;
            accepted=$ok; outcome=$outcome; verify=$check; repo=$repo; workdir=$repo;
            commit=(& git -C $repo rev-parse HEAD); candidate_sha256=$r['candidate_sha256'] }
        Write-AosCoordJson (Join-Path (Split-Path -Parent $r['run_path']) 'receipt.json') $receipt
        $null = Complete-AosTaskAttempt $r['id'] $r['run']
        $state='failed'; if ($ok) { $state='accepted' }; if ($run['cancel_requested']) { $state='cancelled' }
        $null = Set-AosRunState -Id $r['run'] -State $state -Text 'API worker ended; host check recorded'
        if ($Mode -eq 'verify' -and -not $ok) { throw 'host acceptance failed' }
        return $receipt
    } $Action $inputText
    [Console]::Out.Write((ConvertTo-Json -InputObject $result -Depth 20 -Compress))
    exit 0
} catch {
    [Console]::Error.WriteLine('API task bridge failed; inspect task/run state. No provider output logged.')
    exit 1
}
