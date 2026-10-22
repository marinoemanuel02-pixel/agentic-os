# Read-only readiness checks. Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Test-AosReadinessRepository([string]$Path) {
    $git = Invoke-AosGit -Dir $Path -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($git.Code -ne 0 -or $git.Out -ne 'true') {
        return [pscustomobject]@{ name = 'repository'; status = 'fail'; detail = 'not a git repository' }
    }
    $head = Invoke-AosGit -Dir $Path -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($head.Code -ne 0) {
        return [pscustomobject]@{ name = 'repository'; status = 'warn'; detail = 'detached HEAD' }
    }
    $git = Invoke-AosGit -Dir $Path -Arguments @('status', '--porcelain')
    if ($git.Code -ne 0) { throw $git.Err }
    $count = @($git.Out -split "`r?`n" | Where-Object { $_ }).Count
    if ($count -gt 0) {
        return [pscustomobject]@{ name = 'repository'; status = 'warn'; detail = "branch $($head.Out), $count uncommitted change(s)" }
    }
    return [pscustomobject]@{ name = 'repository'; status = 'ok'; detail = "branch $($head.Out), clean" }
}

function Test-AosReadinessClaim([string]$Path) {
    $checkout = Get-AosCheckout $Path
    foreach ($claim in @(Get-AosClaims)) {
        if ($claim['checkout'] -ieq $checkout) {
            return [pscustomobject]@{ name = 'claim'; status = 'warn'; detail = "$($claim['agent']) ($($claim['session'])) holds this checkout until $($claim['expires'])" }
        }
    }
    return [pscustomobject]@{ name = 'claim'; status = 'ok'; detail = 'unclaimed' }
}

function Test-AosReadinessCapacity([string]$Vendor, [datetime]$Now) {
    $capacity = Get-AosCapacity -Now $Now
    $entry = $capacity[$Vendor]
    $name = "capacity:$Vendor"
    if ($null -eq $entry) {
        return [pscustomobject]@{ name = $name; status = 'warn'; detail = "no capacity report: run aos capacity set $Vendor <percent>" }
    }
    switch ($entry.state) {
        'limited' {
            $reset = 'unknown'
            if ($null -ne $entry.resets) {
                $reset = ([datetime]$entry.resets).ToUniversalTime().ToString('yyyy-MM-ddTHH:mmZ', [Globalization.CultureInfo]::InvariantCulture)
            }
            return [pscustomobject]@{ name = $name; status = 'fail'; detail = "limited until ${reset}: re-split to the other vendor" }
        }
        'low' { return [pscustomobject]@{ name = $name; status = 'warn'; detail = "$($entry.remaining) % left, low" } }
        'stale' { return [pscustomobject]@{ name = $name; status = 'warn'; detail = 'stale capacity report: a fresh reading is needed' } }
        'reset' { return [pscustomobject]@{ name = $name; status = 'warn'; detail = 'reset has passed: a fresh reading is needed' } }
        'ok' {
            $minutes = [Math]::Max(0, [Math]::Floor(($Now.ToUniversalTime() - ([datetime]$entry.reported).ToUniversalTime()).TotalMinutes))
            $age = "$minutes min"
            if ($minutes -ge 60) { $age = "$([Math]::Floor($minutes / 60)) h" }
            return [pscustomobject]@{ name = $name; status = 'ok'; detail = "$($entry.remaining) % left, ok, reported $age ago ($($entry.source))" }
        }
        default { return [pscustomobject]@{ name = $name; status = 'warn'; detail = "unknown capacity state: $($entry.state)" } }
    }
}

function Test-AosReadinessActors([string]$Vendor) {
    $count = @(Get-AosActors | Where-Object {
        $_.vendor -eq $Vendor -and (Test-AosActorActive @{ state = $_.state })
    }).Count
    $status = 'ok'
    if ($count -ge $script:AosActorCapPerVendor) { $status = 'fail' }
    return [pscustomobject]@{ name = "actors:$Vendor"; status = $status; detail = "$count of $script:AosActorCapPerVendor slots in use" }
}

function Test-AosReadinessTaskPaths([string]$Path) {
    try {
        $git = Invoke-AosGit -Dir $Path -Arguments @('rev-parse', '--show-toplevel')
        if ($git.Code -ne 0) { throw $git.Err }
        $root = $git.Out
        $git = Invoke-AosGit -Dir $root -Arguments @('ls-files')
        if ($git.Code -ne 0) { throw $git.Err }
        $files = @($git.Out -split "`r?`n" | Where-Object { $_ })
        if ($files.Count -eq 0) {
            return [pscustomobject]@{ name = 'task-paths'; status = 'warn'; detail = 'no tracked file to probe' }
        }
        $file = $files[0]
        $null = Resolve-AosTaskFile -Repo $root -Path $file
        return [pscustomobject]@{ name = 'task-paths'; status = 'ok'; detail = "task paths resolve (checked $file)" }
    } catch {
        return [pscustomobject]@{ name = 'task-paths'; status = 'fail'; detail = $_.Exception.Message }
    }
}

function Test-AosReadinessUnpushed([string]$Path) {
    $git = Invoke-AosGit -Dir $Path -Arguments @('rev-list', '--count', 'HEAD', '--not', '--remotes')
    if ($git.Code -ne 0) { throw $git.Err }
    $count = [int]$git.Out
    if ($count -gt 0) {
        $head = Invoke-AosGit -Dir $Path -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($head.Code -ne 0) { throw $head.Err }
        return [pscustomobject]@{ name = 'unpushed'; status = 'warn'; detail = "$count commit(s) on $($head.Out) exist only on this machine: push or back them up" }
    }
    return [pscustomobject]@{ name = 'unpushed'; status = 'ok'; detail = 'every commit is on a remote' }
}

function Get-AosReadinessChecks([string]$Path, [datetime]$Now = [datetime]::UtcNow) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $checks = @(
        @{ name = 'repository'; command = 'Test-AosReadinessRepository'; arguments = @{ Path = $resolved } }
        @{ name = 'claim'; command = 'Test-AosReadinessClaim'; arguments = @{ Path = $resolved } }
        @{ name = 'capacity:claude'; command = 'Test-AosReadinessCapacity'; arguments = @{ Vendor = 'claude'; Now = $Now } }
        @{ name = 'capacity:codex'; command = 'Test-AosReadinessCapacity'; arguments = @{ Vendor = 'codex'; Now = $Now } }
        @{ name = 'actors:claude'; command = 'Test-AosReadinessActors'; arguments = @{ Vendor = 'claude' } }
        @{ name = 'actors:codex'; command = 'Test-AosReadinessActors'; arguments = @{ Vendor = 'codex' } }
        @{ name = 'task-paths'; command = 'Test-AosReadinessTaskPaths'; arguments = @{ Path = $resolved } }
        @{ name = 'unpushed'; command = 'Test-AosReadinessUnpushed'; arguments = @{ Path = $resolved } }
    )
    foreach ($check in $checks) {
        try {
            $parameters = $check.arguments
            & $check.command @parameters
        } catch {
            [pscustomobject]@{ name = $check.name; status = 'fail'; detail = $_.Exception.Message }
        }
    }
}

function Get-AosReadinessVerdict($Checks) {
    if (@($Checks | Where-Object { $_.status -eq 'fail' }).Count) { return 'fail' }
    if (@($Checks | Where-Object { $_.status -eq 'warn' }).Count) { return 'warn' }
    return 'ok'
}

function Invoke-AosReady([string[]]$Arguments) {
    $path = (Get-Location).ProviderPath
    $hasPath = $false
    $json = $false
    foreach ($argument in $Arguments) {
        if ($argument -eq '--json') { $json = $true }
        elseif ($argument.StartsWith('-') -or $hasPath) {
            Write-AosWarn 'usage: aos ready [<path>] [--json]'
            $global:LASTEXITCODE = 1
            return
        } else { $path = $argument; $hasPath = $true }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-AosWarn "path not found: $path"
        $global:LASTEXITCODE = 1
        return
    }
    $resolved = (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
    $checks = @(Get-AosReadinessChecks -Path $resolved)
    $verdict = Get-AosReadinessVerdict $checks
    if ($json) {
        [ordered]@{ verdict = $verdict; checks = @($checks) } | ConvertTo-Json -Depth 4
    } else {
        foreach ($check in $checks) {
            $line = "$($check.name): $($check.detail)"
            switch ($check.status) {
                'ok' { Write-AosOk $line }
                'warn' { Write-AosWarn "warn $line" }
                'fail' { Write-AosWarn "FAIL $line" }
            }
        }
        switch ($verdict) {
            'ok' { Write-AosOk 'ready' }
            'warn' { Write-AosWarn 'ready with warnings' }
            'fail' { Write-AosWarn 'not ready' }
        }
    }
    $global:LASTEXITCODE = 0
    if ($verdict -eq 'fail') { $global:LASTEXITCODE = 1 }
}
