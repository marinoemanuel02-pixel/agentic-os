# Optional task contracts. Host-owned metadata; compatible with PowerShell 5.1.

function Get-AosTaskPath([string]$Id) {
    Assert-AosCoordId $Id
    return (Join-Path (Join-Path (Get-AosCoordDir) 'tasks') ($Id + '.json'))
}

function Get-AosTaskRecord([string]$Id) {
    $row=Read-AosCoordJsonFile (Get-AosTaskPath $Id)
    if ($row -and ($row -isnot [Collections.IDictionary] -or $row['id'] -ne $Id -or $row['version'] -ne 1)) { throw 'invalid task record' }
    return $row
}

function Get-AosReparseTag([string]$Path) {
    # The reparse tag of an item, 0 when it is not a reparse point or cannot be read; PowerShell does not expose it.
    if (-not ('AosReparseTag' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AosReparseTag {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FindData {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
        public uint SizeHigh, SizeLow, Tag, Reserved1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string FileName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string AlternateName;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr FindFirstFileW(string name, out FindData data);
    [DllImport("kernel32.dll")]
    static extern bool FindClose(IntPtr handle);
    public static uint Of(string path) {
        FindData data;
        IntPtr handle = FindFirstFileW(path, out data);
        if (handle == new IntPtr(-1)) return 0;
        FindClose(handle);
        return (data.Attributes & 0x400) != 0 ? data.Tag : 0;
    }
}
'@
    }
    $full=[IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\?\')) { }
    elseif ($full.StartsWith('\\')) { $full='\\?\UNC\'+$full.Substring(2) }
    else { $full='\\?\'+$full }
    return [uint32][AosReparseTag]::Of($full)
}

function Test-AosCloudReparseTag([uint32]$Tag) {
    # IO_REPARSE_TAG_CLOUD and CLOUD_1..CLOUD_F are 0x9000001A with the 0xF000 bits free; OneDrive Files On-Demand uses 0x9000A01A.
    return (($Tag -band [uint32]4294905855) -eq [uint32]2415919130)
}

function Test-AosCloudReparse([string]$Path) { return (Test-AosCloudReparseTag (Get-AosReparseTag $Path)) }

function Resolve-AosTaskFile([string]$Repo,[string]$Path) {
    if (-not $Path -or [IO.Path]::IsPathRooted($Path) -or $Path -match '[:\x00-\x1f]' -or
        @($Path.Replace('\','/').Split('/') | Where-Object { $_ -in @('','..','.git','.') }).Count) { throw 'unsafe relative task path' }
    $root=[IO.Path]::GetFullPath($Repo).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath((Join-Path $root $Path))
    if (-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'unsafe relative task path' }
    $part=$root
    foreach ($segment in $Path.Replace('\','/').Split('/')) {
        $part=Join-Path $part $segment
        if (Test-Path -LiteralPath $part) {
            $item=Get-Item -LiteralPath $part -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                # Only cloud-sync placeholders (OneDrive Files On-Demand) may be reparse points: they report no LinkType and carry a cloud tag. Everything else stays refused.
                if ($item.LinkType -or -not (Test-AosCloudReparse $part)) { throw 'unsafe relative task path through a link' }
            }
        }
    }
    return $full
}

function Get-AosArtifactManifest([string]$Repo,[string[]]$Files) {
    $rows=@(foreach ($name in @($Files)) {
        $path=Resolve-AosTaskFile $Repo $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing artifact: $name" }
        [ordered]@{path=$name.Replace('\','/');sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    })
    return $rows
}

function Test-AosArtifactManifest([string]$Repo,$Artifacts) {
    foreach ($artifact in @($Artifacts)) {
        try {
            $path=Resolve-AosTaskFile $Repo ([string]$artifact['path'])
            if ($artifact['missing']) { if (Test-Path -LiteralPath $path) {return $false};continue }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $artifact['sha256']) { return $false }
        } catch { return $false }
    }
    return $true
}

function Register-AosTaskContract([string]$Path,[string]$Repo) {
    $c=Read-AosCoordJsonFile $Path
    $fields=@('version','id','objective','task_class','depends_on','allow','verify','artifacts','context','route_reason','review','budget')
    if ($c -isnot [Collections.IDictionary] -or $c['version'] -ne 1 -or -not $c['objective'] -or
        $c['task_class'] -notin @('mechanical','implementation','sequential','diagnosis','research','consequential') -or
        @($c.Keys | Where-Object { $_ -notin $fields }).Count) { throw 'invalid task contract or unknown field' }
    Assert-AosCoordId ([string]$c['id'])
    $repoPath=Get-AosCheckout $Repo
    foreach ($name in @('depends_on','allow','artifacts','context')) {
        if ($c.Contains($name) -and $c[$name] -isnot [array]) { throw "task $name must be an array" }
        if (-not $c.Contains($name)) { $c[$name]=@() }
    }
    if (@($c['artifacts']).Count -gt 32 -or @($c['context']).Count -gt 8) { throw 'task packet has too many files' }
    foreach ($dep in @($c['depends_on'])) { Assert-AosCoordId ([string]$dep) }
    foreach ($file in @($c['artifacts'])) { $null=Resolve-AosTaskFile $repoPath ([string]$file) }
    foreach ($glob in @($c['allow'])) {
        if (-not $glob -or [IO.Path]::IsPathRooted($glob) -or $glob -match '(^|[/\\])\.\.?([/\\]|$)|:|(^|[/\\])\.git([/\\]|$)') { throw 'unsafe relative allow pattern' }
    }
    foreach ($ref in @($c['context'])) {
        if ($ref -isnot [Collections.IDictionary] -or @($ref.Keys | Where-Object {$_ -notin @('path','start_line','end_line')}).Count -or
            [int]$ref['start_line'] -lt 1 -or [int]$ref['end_line'] -lt [int]$ref['start_line'] -or
            [int]$ref['end_line']-[int]$ref['start_line'] -ge 120) { throw 'invalid task context range' }
        $null=Resolve-AosTaskFile $repoPath ([string]$ref['path'])
    }
    if ($c['budget']) {
        if ($c['budget'] -isnot [Collections.IDictionary] -or @($c['budget'].Keys | Where-Object {$_ -notin @('timeout_minutes','max_turns')}).Count) { throw 'invalid task budget' }
        foreach ($key in @('timeout_minutes','max_turns')) {
            if ($c['budget'].Contains($key)) {
                $n=0; $max=100; if ($key -eq 'timeout_minutes') { $max=120 }
                if (-not [int]::TryParse([string]$c['budget'][$key],[ref]$n) -or $n -lt 1 -or $n -gt $max) { throw 'invalid task budget limit' }
            }
        }
    }
    return (Invoke-AosCoordLocked {
        $id=[string]$c['id']; $old=Get-AosTaskRecord $id
        $json=ConvertTo-Json -InputObject $c -Depth 15 -Compress
        if ($old) {
            if ($old['repo'] -ne $repoPath -or (ConvertTo-Json -InputObject $old['contract'] -Depth 15 -Compress) -cne $json) { throw 'task identity already registered differently' }
            return [pscustomobject]$old
        }
        $visit={ param($node,$trail)
            if ($trail -contains $node) { throw 'task dependency cycle' }
            $deps=@(); if ($node -eq $id) { $deps=@($c['depends_on']) } else { $r=Get-AosTaskRecord $node; if ($r) { $deps=@($r['contract']['depends_on']) } }
            foreach ($next in $deps) { & $visit ([string]$next) @($trail+$node) }
        }
        & $visit $id @()
        $row=[ordered]@{version=1;id=$id;repo=$repoPath;contract=$c;state='pending';active_run='';accepted_run='';attempts=@();artifacts=@();updated=Get-AosUtcStamp}
        Write-AosCoordJson (Get-AosTaskPath $id) $row
        return [pscustomobject]$row
    })
}

function Read-AosEvidenceReceipt([string]$RunId) {
    Assert-AosCoordId $RunId
    $r=Read-AosCoordJsonFile (Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $RunId) 'receipt.json')
    if (-not $r -or $r['id'] -ne $RunId) { throw 'missing or mismatched evidence receipt' }
    return $r
}

function Test-AosHostReceipt($Receipt,[string]$Repo,[string]$TaskId) {
    return ($Receipt -is [Collections.IDictionary] -and $Receipt['accepted'] -eq $true -and $Receipt['outcome'] -eq 'accepted' -and
        $Receipt['verify'] -is [Collections.IDictionary] -and $null -ne $Receipt['verify']['exit_code'] -and
        $Receipt['verify']['exit_code'] -eq 0 -and $Receipt['repo'] -eq $Repo -and
        (-not $TaskId -or $Receipt['task_id'] -eq $TaskId))
}

function Test-AosTaskReady([string]$Id,[string]$Repo) {
    return (Invoke-AosCoordLocked {
        $row=Get-AosTaskRecord $Id; if (-not $row) { throw 'unknown task' }
        $reasons=@();$inputs=@()
        foreach ($depId in @($row['contract']['depends_on'])) {
            $dep=Get-AosTaskRecord ([string]$depId)
            if (-not $dep -or $dep['state'] -ne 'accepted' -or -not $dep['accepted_run']) { $reasons+="prerequisite not accepted: $depId";continue }
            try {
                $r=Read-AosEvidenceReceipt $dep['accepted_run']
                if (-not (Test-AosHostReceipt $r $dep['repo'] $dep['id']) -or
                    -not (Test-AosArtifactManifest $Repo $dep['artifacts'])) { throw 'receipt or input artifacts changed' }
                $inputs+= [ordered]@{task_id=$depId;run_id=$dep['accepted_run'];commit=$r['commit'];artifacts=@($dep['artifacts'])}
            } catch { $reasons+="prerequisite invalid: $depId ($($_.Exception.Message))" }
        }
        return [pscustomobject]@{Ready=($reasons.Count -eq 0);Reasons=$reasons;Inputs=$inputs}
    })
}

function Start-AosTaskAttempt([string]$Id,[string]$RunId) {
    Assert-AosCoordId $RunId
    return (Invoke-AosCoordLocked {
        $row=Get-AosTaskRecord $Id; if (-not $row) { throw 'unknown task' }
        if ($row['active_run'] -or $row['state'] -eq 'accepted' -or @($row['attempts']) -contains $RunId) { throw 'task already active, accepted or attempt id reused' }
        $ready=Test-AosTaskReady -Id $Id -Repo $row['repo']
        if (-not $ready.Ready) { throw ($ready.Reasons -join '; ') }
        $row['active_run']=$RunId;$row['state']='running';$row['attempts']=@($row['attempts'])+@($RunId);$row['inputs']=@($ready.Inputs)
        Write-AosCoordJson (Get-AosTaskPath $Id) $row
        return [pscustomobject]$row
    })
}

function Complete-AosTaskAttempt([string]$Id,[string]$RunId) {
    return (Invoke-AosCoordLocked {
        $row=Get-AosTaskRecord $Id
        if (-not $row -or $row['active_run'] -ne $RunId) { throw 'completion is not the active task attempt' }
        $r=Read-AosEvidenceReceipt $RunId
        $state='failed';$manifest=@()
        if (Test-AosHostReceipt $r $row['repo'] $Id) {
            try {
                $ready=Test-AosTaskReady $Id $row['repo']
                if (-not $ready.Ready) { throw 'prerequisite changed during execution' }
                $manifest=Get-AosArtifactManifest -Repo $r['workdir'] -Files @($row['contract']['artifacts'])
            }
            catch {
                # A genuine completed host receipt proves this attempt ended, even if its output failed.
                $row['state']='failed';$row['active_run']='';$row['artifacts']=@();$row['failure_reason']=$_.Exception.Message
                $row['updated']=Get-AosUtcStamp
                Write-AosCoordJson (Get-AosTaskPath $Id) $row
                throw
            }
            $state='accepted'
        }
        elseif ($r['accepted'] -eq $true -or $r['outcome'] -eq 'accepted') { throw 'invalid accepted task receipt' }
        elseif ($r['outcome'] -eq 'needs-inspection') {
            $row['state']='needs-inspection';$row['updated']=Get-AosUtcStamp
            Write-AosCoordJson (Get-AosTaskPath $Id) $row
            return [pscustomobject]$row
        }
        $row['state']=$state;$row['active_run']='';$row['artifacts']=@($manifest)
        if ($state -eq 'accepted') { $row['accepted_run']=$RunId }
        $row['updated']=Get-AosUtcStamp
        Write-AosCoordJson (Get-AosTaskPath $Id) $row
        return [pscustomobject]$row
    })
}

function Get-AosTaskPacket([string]$Id,[string]$Repo,[int]$MaxChars=12000) {
    if ($MaxChars -lt 100 -or $MaxChars -gt 12000) { throw 'packet limit must be 100..12000 characters' }
    $row=Get-AosTaskRecord $Id; if (-not $row) { throw 'unknown task' }
    $ready=Test-AosTaskReady $Id $Repo; if (-not $ready.Ready) { throw ($ready.Reasons -join '; ') }
    $c=$row['contract'];$lines=@("Task: $Id", "Objective: $($c['objective'])", "Class: $($c['task_class'])",
        "Allowed writes: $(@($c['allow']) -join ', ')", "Host check: $($c['verify'])", 'Accepted inputs:', (ConvertTo-Json -InputObject @($ready.Inputs) -Depth 10 -Compress))
    foreach ($ref in @($c['context'])) {
        $path=Resolve-AosTaskFile $Repo $ref['path']
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "context file missing: $($ref['path'])" }
        $text=[IO.File]::ReadAllLines($path)
        $start=[int]$ref['start_line'];$end=[Math]::Min([int]$ref['end_line'],$text.Length)
        $lines+="Context $($ref['path']):${start}-${end}"
        if ($start -le $end) { $lines+=@($text[($start-1)..($end-1)]) }
    }
    foreach ($p in @(Get-AosProcedures -Repo $row['repo'] -TaskClass $c['task_class'] | Select-Object -First 3)) { $lines+="Verified procedure $($p.id): $($p.text)" }
    $packet=$lines -join "`n"
    if ($packet.Length -gt $MaxChars) { throw 'task packet exceeds character budget; narrow context references' }
    return $packet
}
