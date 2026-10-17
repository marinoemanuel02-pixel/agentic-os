[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Alias('Case')][string[]]$CaseIds,
    [ValidateRange(1,3)][int]$Trials = 1,
    [ValidateSet('codex','claude')][string]$Vendor = 'codex',
    [ValidateSet('light','standard','deep')][string]$Tier = 'standard',
    [ValidateRange(0,1)][int]$Workers = 0,
    [ValidateSet('exec','app-server')][string]$Transport = 'exec',
    [string]$Parent,
    [switch]$Execute,
    [switch]$PrepareOnly
)

$script:AosEvalRoot = Split-Path -Parent $PSScriptRoot

function Get-AosEvalModule {
    $path = Join-Path $script:AosEvalRoot 'aos.psm1'
    $module = Get-Module aos | Where-Object { $_.Path -eq $path } | Select-Object -First 1
    if (-not $module) { $module = Import-Module $path -PassThru -DisableNameChecking }
    return $module
}

function Assert-AosEvalRelativePath([string]$Path) {
    if (-not $Path -or $Path -notmatch '^[A-Za-z0-9][A-Za-z0-9_./-]{0,159}$') { throw 'unsafe evaluation fixture path' }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('','..','.','.git') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw 'unsafe evaluation fixture path'
        }
    }
}

function Read-AosEvalManifest([string]$Path) {
    if (-not $Path) { $Path = Join-Path $script:AosEvalRoot 'config\delegate\eval-cases.json' }
    $module = Get-AosEvalModule
    $manifest = & $module { param($File) Read-AosJson $File } $Path
    $classes = @('mechanical','implementation','sequential','diagnosis','research','consequential')
    if (-not $manifest -or $manifest.version -ne 1 -or $manifest.cases -isnot [array] -or $manifest.cases.Count -ne 6 -or
        @($manifest.Keys | Where-Object { $_ -notin @('version','cases') }).Count) {
        throw 'evaluation manifest needs version 1 and six cases'
    }
    $seen = @{}
    foreach ($entry in $manifest.cases) {
        if ($entry -isnot [Collections.IDictionary] -or $entry.id -notin $classes -or $entry.task_class -ne $entry.id -or
            $entry.checker -ne $entry.id -or $seen.ContainsKey([string]$entry.id) -or
            $entry.objective -isnot [string] -or $entry.task -isnot [string] -or
            [string]::IsNullOrWhiteSpace($entry.objective) -or [string]::IsNullOrWhiteSpace($entry.task) -or
            $entry.task.Length -gt 8000 -or $entry.files -isnot [Collections.IDictionary] -or
            $entry.files.Count -lt 1 -or $entry.files.Count -gt 8 -or $entry.allow -isnot [array] -or
            $entry.allow.Count -lt 1 -or $entry.allow.Count -gt 8 -or
            @($entry.Keys | Where-Object { $_ -notin @('id','task_class','checker','objective','task','allow','files') }).Count) {
            throw 'invalid evaluation case fields or checker identity'
        }
        $seen[[string]$entry.id] = $true
        foreach ($file in $entry.files.Keys) {
            Assert-AosEvalRelativePath $file
            if ($entry.files[$file] -isnot [string] -or $entry.files[$file].Length -gt 65536 -or
                ($entry.files[$file] -split "`n").Count -gt 120) { throw 'fixture source exceeds the bounded context packet' }
        }
        foreach ($file in $entry.allow) {
            if ($file -isnot [string]) { throw 'evaluation output paths must be strings' }
            Assert-AosEvalRelativePath $file
        }
    }
    return $manifest
}

function Invoke-AosEvalGit($Module, [string]$Repo, [string[]]$Arguments) {
    $result = & $Module { param($Dir,$GitArgs) Invoke-AosGit -Dir $Dir -Arguments $GitArgs } $Repo $Arguments
    if ($result.Code -ne 0) { throw 'evaluation fixture git operation failed' }
    return $result.Out
}

function Invoke-AosEvalDelegate($Module, [hashtable]$Parameters) {
    return (& $Module {
        param($Options)
        $command = Get-Command Invoke-AosDelegate -CommandType Function
        if (-not $command.Parameters.ContainsKey('ContractFile') -or -not $command.Parameters.ContainsKey('Transport')) {
            throw 'evaluation execution needs the task-contract and transport integration'
        }
        Invoke-AosDelegate @Options
    } $Parameters)
}

function Get-AosEvalReceiptField($Receipt, [string]$Name) {
    if ($null -eq $Receipt) { return $null }
    if ($Receipt -is [Collections.IDictionary]) { return $Receipt[$Name] }
    $property = $Receipt.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Invoke-AosCoordinationEval {
    param(
        [Parameter(Mandatory=$true)][string]$OutputRoot, [Alias('Case')][string[]]$CaseIds,
        [ValidateRange(1,3)][int]$Trials = 1,
        [ValidateSet('codex','claude')][string]$Vendor = 'codex',
        [ValidateSet('light','standard','deep')][string]$Tier = 'standard',
        [ValidateRange(0,1)][int]$Workers = 0,
        [ValidateSet('exec','app-server')][string]$Transport = 'exec',
        [string]$Parent, [switch]$Execute, [switch]$PrepareOnly
    )
    if ([string]::IsNullOrWhiteSpace($OutputRoot) -or $OutputRoot -match '^[\\/]{2}') { throw 'OutputRoot must be a local directory' }
    if ($Execute -and $PrepareOnly) { throw 'choose execution or preparation only' }
    if ($Transport -eq 'app-server' -and $Vendor -ne 'codex') { throw 'app-server transport requires Codex' }
    if ($Execute -and (-not $Parent -or -not $CaseIds -or $CaseIds.Count -eq 0)) { throw 'execution requires an active lead Parent and explicit Case selection' }
    $manifest = Read-AosEvalManifest
    $selected = @($manifest.cases)
    if ($CaseIds -and $CaseIds.Count) {
        if (@($CaseIds | Where-Object { $_ -notin @($manifest.cases.id) }).Count -or
            @($CaseIds | Select-Object -Unique).Count -ne $CaseIds.Count) { throw 'unknown or duplicate evaluation case' }
        $selected = @($manifest.cases | Where-Object { $_.id -in $CaseIds })
    }
    $module = Get-AosEvalModule
    if ($Execute) {
        & $module {
            param($Lead)
            Assert-AosCoordId $Lead
            Invoke-AosCoordLocked {
                $actor = (Read-AosActorStore)['actors'][$Lead]
                if (-not $actor -or $actor['kind'] -ne 'lead' -or $actor['state'] -notin @('running','waiting-input')) {
                    throw 'evaluation execution requires an active lead actor'
                }
            }
        } $Parent
    }
    $base = [IO.Path]::GetFullPath($OutputRoot)
    if (Test-Path -LiteralPath $base -PathType Leaf) { throw 'OutputRoot is a file' }
    $runRoot = Join-Path $base ('evaluation-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $runRoot) { throw 'evaluation output collision; no existing fixture will be reused' }
    New-Item -ItemType Directory -Path $runRoot -Force -ErrorAction Stop | Out-Null
    $grader = Join-Path $script:AosEvalRoot 'tools\coordination-eval-grade.mjs'
    $rows = @()
    foreach ($entry in $selected) {
        for ($trial = 1; $trial -le $Trials; $trial++) {
            $id = 'eval-' + $entry.id + '-t' + $trial + '-' + [guid]::NewGuid().ToString('N').Substring(0,12)
            $trialRoot = Join-Path $runRoot $id
            $repo = Join-Path $trialRoot 'repo'
            New-Item -ItemType Directory -Path $repo -ErrorAction Stop | Out-Null
            foreach ($file in $entry.files.Keys) {
                $target = Join-Path $repo $file
                $directory = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
                [IO.File]::WriteAllText($target, $entry.files[$file], (New-Object Text.UTF8Encoding($false)))
            }
            [IO.File]::WriteAllText((Join-Path $repo '.gitattributes'), "* text eol=lf`n", (New-Object Text.UTF8Encoding($false)))
            $null = Invoke-AosEvalGit $module $repo @('init','--quiet')
            $null = Invoke-AosEvalGit $module $repo @('add','--all')
            $null = Invoke-AosEvalGit $module $repo @('-c','user.name=AOS offline evaluation','-c','user.email=evaluation@localhost',
                '-c','commit.gpgsign=false','-c','core.hooksPath=.aos-no-hooks','commit','--quiet','-m','Initial offline evaluation fixture')
            if (Invoke-AosEvalGit $module $repo @('status','--porcelain')) { throw 'evaluation fixture baseline is dirty' }
            $verify = 'node "' + $grader + '" ' + $entry.checker + ' "."'
            $context = @($entry.files.Keys | ForEach-Object {
                [ordered]@{ path=$_; start_line=1; end_line=[Math]::Max(1,($entry.files[$_] -split "`n").Count) }
            })
            $contract = [ordered]@{ version=1; id=$id; objective=$entry.objective; task_class=$entry.task_class;
                depends_on=@(); allow=@($entry.allow); verify=$verify; artifacts=@($entry.allow); context=$context;
                route_reason='Fixed offline evaluation inputs and host outcome checks; no cost saving inferred.';
                review='fixed host checker; synthetic fixture only'; budget=[ordered]@{timeout_minutes=3;max_turns=12} }
            $taskPath = Join-Path $trialRoot 'task.md'; $contractPath = Join-Path $trialRoot 'contract.json'
            [IO.File]::WriteAllText($taskPath, ($entry.objective + "`n`n" + $entry.task + "`n`n" +
                'The host grader is outside this repo and must not be changed. Report the actual checks and any incomplete work.' + "`n"), (New-Object Text.UTF8Encoding($false)))
            [IO.File]::WriteAllText($contractPath, ((ConvertTo-Json $contract -Depth 12) + "`n"), (New-Object Text.UTF8Encoding($false)))
            $row = [ordered]@{ case_id=$entry.id; task_class=$entry.task_class; trial=$trial; id=$id; repo=$repo;
                task=$taskPath; contract=$contractPath; receipt_ref=$null; accepted=$null; outcome='prepared';
                measurements=[ordered]@{elapsed_seconds=$null;phase_seconds=$null;observed_model=$null;observed_effort=$null;
                    input_tokens=$null;cached_input_tokens=$null;output_tokens=$null;corrections=$null} }
            if ($Execute) {
                $parameters = @{ Vendor=$Vendor;TaskFile=$taskPath;ContractFile=$contractPath;Write=$true;Verify=$verify;
                    Allow=@($entry.allow);Repo=$repo;TimeoutMinutes=3;Parent=$Parent;Workers=$Workers;Tier=$Tier;Transport=$Transport }
                $receipt = Invoke-AosEvalDelegate -Module $module -Parameters $parameters
                $row.accepted = Get-AosEvalReceiptField $receipt 'accepted'
                $row.outcome = Get-AosEvalReceiptField $receipt 'outcome'
                foreach ($pair in @(@('elapsed_seconds','seconds'),@('phase_seconds','phase_seconds'),@('observed_model','observed_model'),
                    @('observed_effort','observed_effort'),@('corrections','corrections'))) {
                    $row.measurements[$pair[0]] = Get-AosEvalReceiptField $receipt $pair[1]
                }
                if ((Get-AosEvalReceiptField $receipt 'usage_observed') -eq $true) {
                    $usage = Get-AosEvalReceiptField $receipt 'usage'
                    $row.measurements.input_tokens = Get-AosEvalReceiptField $usage 'input'
                    $row.measurements.cached_input_tokens = Get-AosEvalReceiptField $usage 'cached'
                    $row.measurements.output_tokens = Get-AosEvalReceiptField $usage 'output'
                }
                $receiptId = Get-AosEvalReceiptField $receipt 'id'
                if ($receiptId) {
                    $row.receipt_ref = & $module { param($Id) Assert-AosCoordId $Id; Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $Id) 'receipt.json' } $receiptId
                }
            }
            $rows += [pscustomobject]$row
        }
    }
    $mode = 'prepare-only'; if ($Execute) { $mode = 'execute' }
    $report = [pscustomobject][ordered]@{version=1;mode=$mode;root=$runRoot;trials=$rows;subscription_savings=$null;
        limitations=@('Deterministic fixture checks do not measure model quality or subscription savings.')}
    [IO.File]::WriteAllText((Join-Path $runRoot 'report.json'), ((ConvertTo-Json $report -Depth 16) + "`n"), (New-Object Text.UTF8Encoding($false)))
    return $report
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-AosCoordinationEval @PSBoundParameters }
