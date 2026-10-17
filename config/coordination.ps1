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
