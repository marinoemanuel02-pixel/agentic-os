# aos.psm1 - the `aos` command: install, sync, check and update the agentic-os setup.
#
# Runs in Windows PowerShell 5.1 and PowerShell 7. Every step is idempotent: running it
# twice changes nothing the second time unless something drifted. Keep this file ASCII-only
# (Windows PowerShell 5.1 misreads BOM-less UTF-8).

$script:Root = $PSScriptRoot
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Layers = @('base', 'engines', 'brain', 'bridges', 'refs', 'local', 'media')
$script:OptInLayers = @('media')   # big downloads: installed only when named, never by `aos install` / `all`
. (Join-Path $PSScriptRoot 'config\coordination.ps1')
. (Join-Path $PSScriptRoot 'config\task-contracts.ps1')
. (Join-Path $PSScriptRoot 'config\coordination-learning.ps1')
. (Join-Path $PSScriptRoot 'config\native-coordination.ps1')
. (Join-Path $PSScriptRoot 'config\readiness.ps1')

# Windows PowerShell 5.1 serializes some arrays as {"value":[...],"Count":n} unless this is removed.
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue }

#region output ----------------------------------------------------------------------------

function Write-AosStep([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-AosOk([string]$Text)   { Write-Host "  ok   $Text" -ForegroundColor Green }
function Write-AosWarn([string]$Text) { Write-Host "  !!   $Text" -ForegroundColor Yellow }
function Write-AosInfo([string]$Text) { Write-Host "       $Text" }
function Write-AosDry([string]$Text)  { Write-Host "  dry  $Text" -ForegroundColor DarkGray }

#endregion
#region helpers ---------------------------------------------------------------------------

function Test-AosCommand([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-AosCodexStandaloneBin {
    # The official Codex installer keeps the active release behind this junction in HOME. Its own PATH
    # folder under %LOCALAPPDATA% can be private to a packaged app (MSIX), so aos also puts this on PATH.
    return (Join-Path $HOME '.codex\packages\standalone\current\bin')
}

function Update-AosPath {
    # Pick up PATH entries installers just wrote to the registry, keeping this session's own.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    # Plus the two agents' own install folders, in case this terminal predates their PATH entries.
    $agentBins = @((Join-Path $HOME '.local\bin'), (Get-AosCodexStandaloneBin), (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin')) |
        Where-Object { Test-Path -LiteralPath $_ }
    $sources = @($env:Path,
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        ([string]::Join(';', @($agentBins))))
    foreach ($source in $sources) {
        if (-not $source) { continue }
        foreach ($p in $source.Split(';')) {
            $e = [Environment]::ExpandEnvironmentVariables($p.Trim())
            if ($e -and $seen.Add($e)) { $parts.Add($e) }
        }
    }
    $env:Path = [string]::Join(';', $parts)
}

function Edit-AosUserPath {
    # Edits the raw user PATH (keeps %VARS% and the ExpandString type), then tells Windows so new
    # terminals see the change. User scope only; the machine PATH is never touched.
    param([string[]]$Add = @(), [string[]]$Remove = @(), [switch]$DryRun)
    $norm = { param($p) [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\').ToLowerInvariant() }
    $changed = @()
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = New-Object 'System.Collections.Generic.List[string]'
        foreach ($e in $raw.Split(';')) { if ($e.Trim()) { $entries.Add($e.Trim()) } }
        foreach ($r in $Remove) {
            $target = & $norm $r
            foreach ($hit in @($entries | Where-Object { (& $norm $_) -eq $target })) { [void]$entries.Remove($hit); $changed += "removed $hit" }
        }
        foreach ($a in $Add) {
            $target = & $norm $a
            if (@($entries | Where-Object { (& $norm $_) -eq $target }).Count -eq 0) { $entries.Add($a); $changed += "added $a" }
        }
        if ($changed.Count -eq 0) { Write-AosOk 'user PATH already correct'; return }
        if ($DryRun) { foreach ($c in $changed) { Write-AosDry "user PATH: would have $c" }; return }
        $key.SetValue('Path', [string]::Join(';', $entries), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    finally { $key.Close() }
    # Setting and clearing a throwaway variable makes Windows broadcast the environment change.
    [Environment]::SetEnvironmentVariable('AOS_ENV_REFRESH', '1', 'User')
    [Environment]::SetEnvironmentVariable('AOS_ENV_REFRESH', $null, 'User')
    foreach ($c in $changed) { Write-AosOk "user PATH: $c" }
    Update-AosPath
}

function Invoke-AosCapture([string]$CommandLine) {
    # Runs through cmd so stderr is merged natively (5.1 wraps native stderr in error records).
    $out = cmd /c "$CommandLine 2>&1"
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($out | Out-String).Trim()) }
}

function ConvertTo-AosHashtable($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-AosHashtable $p.Value }
        return $h
    }
    if ($Value -is [System.Collections.IDictionary]) { return $Value }
    if (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Value) { [void]$list.Add((ConvertTo-AosHashtable $item)) }
        return , ($list.ToArray())
    }
    return $Value
}

function Read-AosJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $text)
}

function Merge-AosTree($Base, $Overlay) {
    # Objects merge recursively, arrays become a de-duplicated union, scalars from $Overlay win.
    foreach ($key in @($Overlay.Keys)) {
        $o = $Overlay[$key]
        $hasBase = $Base.Contains($key)
        if ($hasBase -and ($Base[$key] -is [System.Collections.IDictionary]) -and ($o -is [System.Collections.IDictionary])) {
            Merge-AosTree $Base[$key] $o
        }
        elseif ($hasBase -and ($Base[$key] -is [array]) -and ($o -is [array])) {
            $merged = New-Object System.Collections.ArrayList
            $seen = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($x in (@($Base[$key]) + @($o))) {
                $k = ConvertTo-Json -InputObject $x -Depth 20 -Compress
                if ($seen.Add($k)) { [void]$merged.Add($x) }
            }
            $Base[$key] = $merged.ToArray()
        }
        else {
            $Base[$key] = $o
        }
    }
}

function Write-AosText([string]$Path, [string]$Text, [switch]$Bom) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $enc = $script:Utf8NoBom
    if ($Bom) { $enc = $script:Utf8Bom }
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-AosBackupRoot {
    # Where aos parks whatever it replaces. AOS_BACKUPS redirects it (the test suite uses a temp dir).
    if ($env:AOS_BACKUPS) { return $env:AOS_BACKUPS }
    return (Join-Path $HOME '.aos-backups')
}

function New-AosBackupPath([string]$Label = '') {
    # A fresh, not-yet-existing path under the backup root. Moving into an existing folder nests
    # inside it silently, so a same-second collision gets a numeric suffix instead.
    $root = Get-AosBackupRoot
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $base = Join-Path $root ((Get-Date -Format 'yyyyMMdd-HHmmss') + $Label)
    $path = $base
    $n = 1
    while (Test-Path -LiteralPath $path) { $n++; $path = "$base-$n" }
    return $path
}

function Move-AosItem([string]$Source, [string]$Destination) {
    # True only when the destination exists AND the source is gone; any error means false. An
    # existing destination is refused: Move-Item would silently nest the source inside it.
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    if (Test-Path -LiteralPath $Destination) { return $false }
    try {
        # Rename directories as a unit. Move-Item can partially move a tree when a file is locked.
        # Cross-volume directory moves fail closed rather than copying only part of the data.
        if ([System.IO.Directory]::Exists($Source)) {
            [System.IO.Directory]::Move($Source, $Destination)
        }
        else { [System.IO.File]::Move($Source, $Destination) }
    }
    catch { return $false }
    return ((Test-Path -LiteralPath $Destination) -and -not (Test-Path -LiteralPath $Source))
}

function Backup-AosFile([string]$Path) {
    # Throws on any failure, whatever the caller's ErrorActionPreference: no write may follow a failed backup.
    $dest = New-AosBackupPath
    try {
        New-Item -ItemType Directory -Force -Path $dest -ErrorAction Stop | Out-Null
        # New-Item -Force reports nothing when a parent is a file.
        if (-not (Test-Path -LiteralPath $dest -PathType Container)) { throw "cannot create $dest" }
        Copy-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
    }
    catch { throw "backup of $Path failed: $($_.Exception.Message)" }
    return (Join-Path $dest (Split-Path -Leaf $Path))
}

function Set-AosManagedBlock {
    # Owns only the text between $Start and $End; everything else in the file is left alone.
    param(
        [string]$Path, [string]$Body, [string]$Start, [string]$End,
        [ValidateSet('Top', 'Bottom')][string]$Position = 'Bottom',
        [switch]$Bom, [switch]$DryRun
    )
    $existing = ''
    if (Test-Path -LiteralPath $Path) { $existing = [System.IO.File]::ReadAllText($Path) }
    $block = $Start + "`n" + $Body.Trim() + "`n" + $End
    $pattern = '(?s)' + [regex]::Escape($Start) + '.*?' + [regex]::Escape($End)
    if ([regex]::IsMatch($existing, $pattern)) {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block }
        $new = [regex]::Replace($existing, $pattern, $evaluator)
    }
    elseif ($Position -eq 'Top') {
        $new = $block + "`n"
        if ($existing.Length -gt 0) { $new = $block + "`n`n" + $existing }
    }
    else {
        $sep = ''
        if ($existing.Length -gt 0) {
            $sep = "`n"
            if (-not $existing.EndsWith("`n")) { $sep = "`n`n" }
        }
        $new = $existing + $sep + $block + "`n"
    }
    if ($new -eq $existing) { Write-AosOk "$Path up to date"; return }
    if ($DryRun) { Write-AosDry "would update the agentic-os block in $Path"; return }
    Write-AosText -Path $Path -Text $new -Bom:$Bom
    Write-AosOk "updated $Path"
}

function Set-AosJunction {
    # Directory junctions need no admin rights or Developer Mode, and work across C: and D:.
    param([string]$Link, [string]$Target, [switch]$DryRun)
    $Target = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')
    if (Test-Path -LiteralPath $Link) {
        $item = Get-Item -LiteralPath $Link -Force
        if ($item.LinkType -eq 'Junction' -or $item.LinkType -eq 'SymbolicLink') {
            $current = @($item.Target)[0]
            if ($current -and ([System.IO.Path]::GetFullPath($current).TrimEnd('\') -ieq $Target)) {
                Write-AosOk "$Link -> $Target"; return
            }
            if ($DryRun) { Write-AosDry "would repoint $Link from $current to $Target"; return }
            [System.IO.Directory]::Delete($Link, $false)   # removes the link itself, never the target's files
        }
        elseif ($item.PSIsContainer) {
            $children = @(Get-ChildItem -LiteralPath $Link -Force)
            if ($children.Count -gt 0) {
                if ($DryRun) { Write-AosDry "would move existing $Link to the backups, then link it"; return }
                $holder = New-AosBackupPath
                New-Item -ItemType Directory -Force -Path $holder | Out-Null
                $backup = Join-Path $holder $item.Name
                if (-not (Move-AosItem -Source $Link -Destination $backup)) {
                    Write-AosWarn "could not move the existing $Link out of the way (files in use?); not linked"
                    return
                }
                Write-AosWarn "moved the existing $Link to $backup - merge anything you need into $Target"
            }
            else {
                if ($DryRun) { Write-AosDry "would replace empty folder $Link with a link to $Target"; return }
                [System.IO.Directory]::Delete($Link, $false)
            }
        }
        else {
            Write-AosWarn "$Link is a file, not a folder; left alone"; return
        }
    }
    elseif ($DryRun) { Write-AosDry "would link $Link -> $Target"; return }
    $parent = Split-Path -Parent $Link
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
    Write-AosOk "$Link -> $Target"
}

function Test-AosWinget([string]$Id) {
    $null = winget list --id $Id -e --accept-source-agreements --disable-interactivity
    return ($LASTEXITCODE -eq 0)
}

function Test-AosInstalledAsMsix([string]$Id) {
    # winget can't switch installer technology on upgrade, so an MSIX copy of a package pinned to
    # MSI has to be migrated by hand. Get-AppxPackage may be unavailable in some pwsh sessions.
    try { return [bool](Get-AppxPackage -Name $Id -ErrorAction Stop) } catch { return $false }
}

function Install-AosWingetPackage([string]$Id, [string]$Why, [string]$InstallerType, [switch]$SkipDependencies, [switch]$DryRun) {
    if (Test-AosWinget $Id) {
        if ((@('wix', 'msi') -contains $InstallerType) -and (Test-AosInstalledAsMsix $Id)) {
            Write-AosWarn "$Id is installed as the MSIX package but must be the $InstallerType edition. Migrate: winget uninstall --id $Id -e, then aos install base"
            return
        }
        Write-AosOk "$Id"; return
    }
    $extra = @()
    if ($InstallerType) { $extra = @('--installer-type', $InstallerType) }
    if ($SkipDependencies) { $extra += '--skip-dependencies' }   # e.g. yt-dlp would pull a second ffmpeg
    if ($DryRun) { Write-AosDry "winget install --id $Id -e $($extra -join ' ')   ($Why)"; return }
    Write-AosInfo "installing $Id - $Why"
    winget install --id $Id -e @extra --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    if ($LASTEXITCODE -eq 0) { Write-AosOk "$Id installed" }
    else { Write-AosWarn "${Id}: winget exit code $LASTEXITCODE (a UAC prompt may have been declined)" }
}

function Get-AosPackages { return Read-AosJson (Join-Path $script:Root 'packages.json') }

function Get-AosClaudePlugins {
    $names = New-Object 'System.Collections.Generic.List[string]'
    $settings = Read-AosJson (Join-Path $HOME '.claude\settings.json')
    if ($settings -and $settings.Contains('enabledPlugins')) {
        foreach ($k in @($settings['enabledPlugins'].Keys)) {
            if ($settings['enabledPlugins'][$k]) { $names.Add([string]$k) }
        }
    }
    return , ($names.ToArray())
}

function Get-AosCodexConfigText {
    $path = Join-Path $HOME '.codex\config.toml'
    if (Test-Path -LiteralPath $path) { return [System.IO.File]::ReadAllText($path) }
    return ''
}

function Get-AosCodexPlugins {
    # Enabled Codex plugin ids. `codex plugin list` is authoritative: plugins from a remote catalog
    # (superpowers@openai-curated-remote) never appear in config.toml. The config.toml tables
    # ([plugins."id"] with enabled = true) are the fallback when the CLI is unavailable.
    $ids = New-Object 'System.Collections.Generic.List[string]'
    if (Test-AosCommand codex) {
        $r = Invoke-AosCapture 'codex plugin list'
        if ($r.Code -eq 0) {
            foreach ($m in [regex]::Matches($r.Text, '(?m)^\s*(\S+@\S+)\s+installed, enabled\b')) { $ids.Add($m.Groups[1].Value) }
            return , ($ids.ToArray())
        }
    }
    $sections = [regex]::Matches((Get-AosCodexConfigText), '(?ms)^\[plugins\."([^"]+)"\][ \t]*\r?$(.*?)(?=^\[|\z)')
    foreach ($m in $sections) {
        if ($m.Groups[2].Value -match '(?m)^[ \t]*enabled[ \t]*=[ \t]*true\b') { $ids.Add($m.Groups[1].Value) }
    }
    return , ($ids.ToArray())
}

function Test-AosCcBridge {
    return (@(Get-AosCodexPlugins | Where-Object { $_ -match '(?i)^cc(-plugin-codex)?@|@sendbird' }).Count -gt 0)
}

function Get-AosCodexAgentsText {
    $src = [System.IO.File]::ReadAllText((Join-Path $script:Root 'agents-home\AGENTS.md'))
    $header = '<!-- GENERATED by agentic-os (aos sync) from agents-home/AGENTS.md. Edit the source, not this copy. -->'
    return $header + "`n`n" + $src
}

function Get-AosCodexProfiles {
    # config/codex/<name>.config.toml -> ~/.codex/<name>.config.toml (Codex 0.134+ profile files).
    $list = @()
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'config\codex') -Filter '*.config.toml' -File -ErrorAction SilentlyContinue)) {
        $header = "# GENERATED by agentic-os (aos sync) from config/codex/$($f.Name). Edit the repo copy, not this file."
        $list += [pscustomobject]@{
            Name   = $f.Name.Replace('.config.toml', '')
            Target = Join-Path $HOME ".codex\$($f.Name)"
            Text   = $header + "`n" + [System.IO.File]::ReadAllText($f.FullName)
        }
    }
    # No Codex profile for the local model: Codex's agent prompt (~45K tokens) needs a 64K context, which
    # spills the 2B model 27% onto the CPU of the 6 GB GPU. The local model is used through the nar tools.
    return $list
}

#endregion
#region layers ----------------------------------------------------------------------------

function Install-AosBase([switch]$DryRun) {
    $pkgs = Get-AosPackages
    Write-AosStep 'Base tools (winget; approve any UAC prompts that appear)'
    foreach ($p in $pkgs['base']) { Install-AosWingetPackage -Id $p['id'] -Why $p['why'] -InstallerType $p['installerType'] -DryRun:$DryRun }
    Update-AosPath

    Write-AosStep 'git defaults (only where unset)'
    if (Test-AosCommand git) {
        foreach ($pair in @(@('init.defaultBranch', 'main'), @('core.longpaths', 'true'))) {
            $current = git config --global --get $pair[0]
            if ($current) { Write-AosOk "$($pair[0]) = $current"; continue }
            if ($DryRun) { Write-AosDry "git config --global $($pair[0]) $($pair[1])"; continue }
            git config --global $pair[0] $pair[1]
            Write-AosOk "$($pair[0]) = $($pair[1])"
        }
    }
    else { Write-AosWarn 'git is not on PATH yet (open a new terminal, then re-run)' }

    Write-AosStep 'npm global tools (prefix ~\.npm-global)'
    Install-AosNpmTools -Packages $pkgs['npm'] -DryRun:$DryRun

    Write-AosStep 'VS Code extensions'
    if (Test-AosCommand code) {
        $installed = @(code --list-extensions)
        foreach ($x in $pkgs['vscode']) {
            if ($installed -contains $x['id']) { Write-AosOk $x['id']; continue }
            if ($DryRun) { Write-AosDry "code --install-extension $($x['id'])"; continue }
            code --install-extension $x['id'] --force | Out-Host
        }
    }
    else { Write-AosWarn 'VS Code not on PATH yet; extensions skipped (re-run later)' }

    Install-AosPester -DryRun:$DryRun
}

function Get-AosNpmPrefix {
    # Global npm tools live in HOME: a new %APPDATA%\npm created from inside a packaged app stays private to it.
    return (Join-Path $HOME '.npm-global')
}

function Use-AosNpmPrefix([switch]$DryRun) {
    if (-not (Test-AosCommand npm)) { Write-AosWarn 'npm missing; global npm tools skipped (aos install base)'; return }
    $override = [Environment]::GetEnvironmentVariable('NPM_CONFIG_PREFIX')
    if ($override) { Write-AosWarn "NPM_CONFIG_PREFIX=$override overrides ~\.npmrc for your own npm -g installs (aos passes --prefix)" }
    $want = Get-AosNpmPrefix
    $lines = @((Invoke-AosCapture 'npm config get prefix').Text -split "`r?`n" | Where-Object { $_.Trim() })
    $have = ''
    if ($lines.Count -gt 0) { $have = $lines[-1].Trim() }
    if ($have.TrimEnd('\') -ieq $want.TrimEnd('\')) { Write-AosOk "npm prefix = $want" }
    elseif ($DryRun) { Write-AosDry "npm config set prefix `"$want`"   (now: $have)" }
    else {
        $r = Invoke-AosCapture "npm config set prefix `"$want`""
        if ($r.Code -eq 0) { Write-AosOk "npm prefix = $want (was $have)" } else { Write-AosWarn "npm config set prefix failed: $($r.Text)" }
    }
    Edit-AosUserPath -Add '%USERPROFILE%\.npm-global' -DryRun:$DryRun
}

function Install-AosNpmTools([object[]]$Packages, [switch]$DryRun) {
    Use-AosNpmPrefix -DryRun:$DryRun
    if (-not (Test-AosCommand npm)) { return }
    $prefix = Get-AosNpmPrefix
    foreach ($n in $Packages) {
        $name = $n['name']
        # The command it installs: a scoped package (@scope/name) installs <bin>.cmd, not its own name.
        $bin = $name
        if ($n['bin']) { $bin = [string]$n['bin'] }
        # Only a copy in our prefix counts: one found elsewhere on PATH can be private to a packaged app.
        if (Test-Path -LiteralPath (Join-Path $prefix "$bin.cmd")) { Write-AosOk $name; continue }
        if ($DryRun) { Write-AosDry "npm install -g $name   ($($n['why']))"; continue }
        # An explicit prefix: a failed config write or an NPM_CONFIG_PREFIX override can't redirect it.
        $r = Invoke-AosCapture "npm install -g $name --prefix `"$prefix`""
        if ($r.Code -eq 0) { Write-AosOk "$name installed in $prefix" } else { Write-AosWarn "npm install -g $name failed (exit $($r.Code))" }
    }
    Update-AosPath
}

function Use-AosLocalBin {
    # Make an installed-but-not-yet-on-PATH claude.exe usable in this session.
    $localBin = Join-Path $HOME '.local\bin'
    if ((Test-Path -LiteralPath (Join-Path $localBin 'claude.exe')) -and -not (Test-AosCommand claude)) { $env:Path = "$localBin;$env:Path" }
}

function Invoke-AosCodexInstaller {
    powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://chatgpt.com/codex/install.ps1 | iex' | Out-Host
}

function Install-AosEngines([switch]$DryRun) {
    Update-AosPath
    Use-AosLocalBin
    Write-AosStep 'Claude Code CLI (native installer; updates itself)'
    if (Test-AosCommand claude) { Write-AosOk ('claude ' + (Invoke-AosCapture 'claude --version').Text.Trim()) }
    elseif ($DryRun) { Write-AosDry 'irm https://claude.ai/install.ps1 | iex   (in a child process)' }
    else {
        powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' | Out-Host
        Update-AosPath
        Use-AosLocalBin
        if (Test-AosCommand claude) { Write-AosOk ('claude ' + (Invoke-AosCapture 'claude --version').Text.Trim()) }
    }
    # The native installer puts claude.exe in ~\.local\bin but may leave that folder off PATH.
    $pathAdd = @(); $pathRemove = @()
    if (Test-Path -LiteralPath (Join-Path $HOME '.local\bin\claude.exe')) { $pathAdd += '%USERPROFILE%\.local\bin' }
    # A winget Codex install (no codex.exe alias without Developer Mode) leaves its folder on PATH after removal.
    $stale = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe'
    if (-not (Test-Path -LiteralPath $stale)) { $pathRemove += $stale }

    Write-AosStep 'Codex CLI (official installer from releases.openai.com; updates itself; shares ~/.codex with the app)'
    # Look for the standalone CLI itself: the Codex app's bundled codex.exe can be on PATH without it.
    $codexBin = Get-AosCodexStandaloneBin
    $codexExe = Join-Path $codexBin 'codex.exe'
    if (Test-Path -LiteralPath $codexExe) { Write-AosOk "codex CLI in $codexBin" }
    elseif ($DryRun) { Write-AosDry 'irm https://chatgpt.com/codex/install.ps1 | iex   (in a child process)' }
    else {
        Invoke-AosCodexInstaller
        if (Test-Path -LiteralPath $codexExe) { Write-AosOk "codex CLI in $codexBin" }
        else { Write-AosWarn "codex.exe not found in $codexBin after the installer ran (did its layout change?)" }
    }
    # The installer's own PATH folder (%LOCALAPPDATA%\Programs\OpenAI\Codex\bin) can be private to a
    # packaged app when the installer ran inside one; this entry works from every terminal and app.
    if (Test-Path -LiteralPath $codexExe) { $pathAdd += '%USERPROFILE%\.codex\packages\standalone\current\bin' }
    Edit-AosUserPath -Add $pathAdd -Remove $pathRemove -DryRun:$DryRun
    if (-not $DryRun) {
        if (-not (Test-AosCommand claude)) { Write-AosWarn 'claude not found after install; open a new terminal and run: claude --version' }
        if (-not (Test-AosCommand codex)) { Write-AosWarn 'codex not found after install; open a new terminal and run: codex --version' }
    }
}

function Sync-AosCodexAgents([switch]$DryRun) {
    $target = Join-Path $HOME '.codex\AGENTS.md'
    $want = Get-AosCodexAgentsText
    if (Test-Path -LiteralPath $target) {
        $have = [System.IO.File]::ReadAllText($target)
        if ($have -eq $want) { Write-AosOk "$target in sync"; return }
        if ($DryRun) { Write-AosDry "would refresh $target from agents-home/AGENTS.md"; return }
        if (-not $have.StartsWith('<!-- GENERATED by agentic-os')) {
            $saved = Backup-AosFile $target
            Write-AosWarn "your previous $target was saved to $saved"
        }
    }
    elseif ($DryRun) { Write-AosDry "would write $target (copy of agents-home/AGENTS.md)"; return }
    Write-AosText -Path $target -Text $want
    Write-AosOk "wrote $target"
}

function Sync-AosClaudeSettings([switch]$DryRun) {
    $target = Join-Path $HOME '.claude\settings.json'
    $overlay = Read-AosJson (Join-Path $script:Root 'config\claude\settings.json')
    $current = Read-AosJson $target
    if ($null -eq $current) { $current = [ordered]@{} }
    if ($overlay.Contains('statusLine')) {
        if ($current.Contains('statusLine')) { $overlay.Remove('statusLine') }   # never replace your own status line
        elseif (-not (Test-AosCommand ccusage)) {
            $overlay.Remove('statusLine')
            Write-AosWarn 'ccusage not installed yet; status line skipped (run aos sync again after the base layer)'
        }
    }
    $before = ConvertTo-Json -InputObject $current -Depth 20 -Compress
    $hooks = $null
    if ($overlay.Contains('hooks')) { $hooks = Expand-AosHookTree $overlay['hooks']; $overlay.Remove('hooks') }
    Merge-AosTree $current $overlay
    if ($null -ne $hooks) {
        # Our hooks are replaced as a unit (also when the repo moved); the user's own are kept.
        if (-not ($current['hooks'] -is [System.Collections.IDictionary])) { $current['hooks'] = [ordered]@{} }
        Merge-AosOwnedHooks $current['hooks'] $hooks
    }
    $after = ConvertTo-Json -InputObject $current -Depth 20 -Compress
    if ($before -eq $after) { Write-AosOk "$target already has these settings"; return }
    if ($DryRun) { Write-AosDry "would merge config/claude/settings.json into $target"; return }
    if (Test-Path -LiteralPath $target) {
        $saved = Backup-AosFile $target
        Write-AosInfo "previous settings saved to $saved"
    }
    Write-AosText -Path $target -Text ((ConvertTo-Json -InputObject $current -Depth 20) + "`n")
    Write-AosOk "merged into $target"
}

function Get-AosMcpManifest { return Read-AosJson (Join-Path $script:Root 'config\mcp.json') }

function Expand-AosPlaceholders([string]$Text) {
    # Repo files hold no absolute paths; these resolve on the machine at run time.
    return $Text.Replace('{{projects}}', (Get-AosProjectsDir)).Replace('{{home}}', $HOME)
}

function Test-AosMcpCurrent($Result, [string[]]$Needles) {
    if ($Result.Code -ne 0) { return $false }
    $text = ([string]$Result.Text).Replace('\\', '\')   # codex prints JSON: its backslashes arrive doubled
    foreach ($n in $Needles) { if ($text.IndexOf($n, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }
    return $true
}

function Add-AosMcpServer([string]$Agent, [string]$Name, [bool]$Http, [string]$Url, [string[]]$Command) {
    if ($Agent -eq 'claude') {
        if ($Http) { claude mcp add --scope user --transport http $Name $Url | Out-Host }
        else { claude mcp add --scope user $Name -- @Command | Out-Host }
    }
    else {
        if ($Http) { codex mcp add $Name --url $Url | Out-Host }
        else { codex mcp add $Name -- @Command | Out-Host }
    }
    return ($LASTEXITCODE -eq 0)
}

function Get-AosMcpTargets($Server) {
    # Optional "agents": ["claude"] keeps a server out of the other agent (default: both).
    $targets = @('claude', 'codex')
    if ($Server.Contains('agents')) { $targets = @($targets | Where-Object { @($Server['agents']) -contains $_ }) }
    return $targets
}

function Get-AosMcpStatePath {
    if ($env:AOS_MCP_STATE) { return $env:AOS_MCP_STATE }
    return (Join-Path (Get-AosStateDir) 'mcp-registered.json')
}

function Sync-AosMcp([switch]$DryRun) {
    # Registered = present AND pointing where the manifest says; a changed URL or command is re-added.
    $manifest = Get-AosMcpManifest
    $statePath = Get-AosMcpStatePath
    $state = [ordered]@{ claude = @(); codex = @() }
    if (Test-Path -LiteralPath $statePath) {
        $saved = Read-AosJson $statePath
        foreach ($agent in @('claude', 'codex')) {
            if ($saved.Contains($agent)) { $state[$agent] = @($saved[$agent]) }
        }
    }
    $before = ConvertTo-Json -InputObject $state -Depth 5 -Compress
    foreach ($name in @($manifest['servers'].Keys)) {
        $s = $manifest['servers'][$name]
        if ($s.Contains('requires')) {
            $need = Expand-AosPlaceholders ([string]$s['requires'])
            if (-not (Test-Path -LiteralPath $need)) { Write-AosInfo "$name skipped: $need not found yet"; continue }
        }
        $isHttp = ($s['transport'] -eq 'http')
        $cmd = @()
        if ($isHttp) { $needles = @([string]$s['url']) }
        else {
            $cmd = @(Expand-AosPlaceholders ([string]$s['command'])) + @(@($s['args']) | Where-Object { $null -ne $_ } | ForEach-Object { Expand-AosPlaceholders ([string]$_) })
            $needles = $cmd
        }
        foreach ($agent in @(Get-AosMcpTargets $s)) {
            if (-not (Test-AosCommand $agent)) { Write-AosWarn "$agent missing; $name not registered there"; continue }
            $getCmd = "claude mcp get $name"
            if ($agent -eq 'codex') { $getCmd = "codex mcp get $name --json" }
            $got = Invoke-AosCapture $getCmd
            if (Test-AosMcpCurrent $got $needles) {
                if (-not $DryRun -and $state[$agent] -notcontains $name) { $state[$agent] = @($state[$agent]) + @($name) }
                Write-AosOk "${agent}: $name"
                continue
            }
            if ($DryRun) { Write-AosDry "$agent mcp add $name"; continue }
            if ($got.Code -eq 0) {
                $rm = "claude mcp remove $name --scope user"
                if ($agent -eq 'codex') { $rm = "codex mcp remove $name" }
                $null = Invoke-AosCapture $rm
                Write-AosInfo "${agent}: $name changed; re-adding"
            }
            if (Add-AosMcpServer -Agent $agent -Name $name -Http $isHttp -Url ([string]$s['url']) -Command $cmd) {
                if ($state[$agent] -notcontains $name) { $state[$agent] = @($state[$agent]) + @($name) }
                Write-AosOk "${agent}: added $name"
            }
            else { Write-AosWarn "${agent}: adding $name failed" }
        }
    }
    foreach ($agent in @('claude', 'codex')) {
        foreach ($name in @($state[$agent])) {
            $wanted = $false
            if ($manifest['servers'].Contains($name)) {
                $wanted = (@(Get-AosMcpTargets $manifest['servers'][$name]) -contains $agent)
            }
            if ($wanted) { continue }
            if ($DryRun) { Write-AosDry "$agent mcp remove $name (dropped from config/mcp.json)"; continue }
            if (-not (Test-AosCommand $agent)) { Write-AosWarn "$agent missing; $name not removed there"; continue }
            $rm = "claude mcp remove $name --scope user"
            if ($agent -eq 'codex') { $rm = "codex mcp remove $name" }
            $result = Invoke-AosCapture $rm
            if ($result.Code -ne 0) { Write-AosWarn "${agent}: removing $name failed: $($result.Text)"; continue }
            $state[$agent] = @($state[$agent] | Where-Object { $_ -ne $name })
            Write-AosOk "${agent}: removed $name"
        }
    }
    if (-not $DryRun -and $before -ne (ConvertTo-Json -InputObject $state -Depth 5 -Compress)) {
        Write-AosText -Path $statePath -Text ((ConvertTo-Json -InputObject $state -Depth 5) + "`n")
    }
}

function Show-AosMcpStatus {
    $manifest = Get-AosMcpManifest
    $claudeList = ''; $codexList = ''
    $haveCodex = Test-AosCommand codex
    if (Test-AosCommand claude) { $claudeList = (Invoke-AosCapture 'claude mcp list').Text }
    if ($haveCodex) { $codexList = (Invoke-AosCapture 'codex mcp list').Text }
    else { Write-AosWarn 'codex is not on PATH here: its MCP and plugin checks are skipped' }
    foreach ($name in @($manifest['servers'].Keys)) {
        $s = $manifest['servers'][$name]
        if ($s.Contains('requires') -and -not (Test-Path -LiteralPath (Expand-AosPlaceholders ([string]$s['requires'])))) { Write-AosInfo "${name}: not set up yet"; continue }
        $pattern = '(?im)^\W*' + [regex]::Escape($name) + '\b'
        $targets = @(Get-AosMcpTargets $s)
        if ($targets -contains 'claude') {
            if ($claudeList -match $pattern) { Write-AosOk "claude: $name" } else { Write-AosWarn "claude: $name not registered (aos sync)" }
        }
        if (-not $haveCodex -or $targets -notcontains 'codex') { continue }
        if ($codexList -match $pattern) { Write-AosOk "codex: $name" } else { Write-AosWarn "codex: $name not registered (aos sync)" }
    }
}

function Sync-AosCodexProfiles([switch]$DryRun) {
    foreach ($p in (Get-AosCodexProfiles)) {
        if (Test-Path -LiteralPath $p.Target) {
            $have = [System.IO.File]::ReadAllText($p.Target)
            if ($have -eq $p.Text) { Write-AosOk "codex --profile $($p.Name)"; continue }
            if ($DryRun) { Write-AosDry "would refresh $($p.Target)"; continue }
            if (-not $have.StartsWith('# GENERATED by agentic-os')) { Write-AosWarn ("your previous $($p.Target) was saved to " + (Backup-AosFile $p.Target)) }
        }
        elseif ($DryRun) { Write-AosDry "would write $($p.Target)"; continue }
        Write-AosText -Path $p.Target -Text $p.Text
        Write-AosOk "codex --profile $($p.Name) -> $($p.Target)"
    }
}

function Get-AosPs51Policy {
    # The user's real Windows PowerShell 5.1 policy. A -ExecutionPolicy Bypass parent passes its
    # process policy down through this variable, so hide it from the child while asking.
    $saved = $env:PSExecutionPolicyPreference
    Remove-Item Env:PSExecutionPolicyPreference -ErrorAction SilentlyContinue
    try { return ((powershell.exe -NoProfile -Command 'Get-ExecutionPolicy' | Out-String).Trim()) }
    finally { if ($saved) { $env:PSExecutionPolicyPreference = $saved } }
}

function Sync-AosProfile([switch]$DryRun) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $module = (Join-Path $script:Root 'aos.psm1').Replace("'", "''")
    $body = "Import-Module '$module' -DisableNameChecking"
    $start = '# >>> agentic-os >>>'
    $end = '# <<< agentic-os <<<'
    Set-AosManagedBlock -Path (Join-Path $docs 'PowerShell\profile.ps1') -Body $body -Start $start -End $end -Position Bottom -Bom -DryRun:$DryRun

    # Windows PowerShell 5.1 defaults to Restricted on Windows 11: it refuses to load any profile
    # script, so a profile there only prints an error at every start. Write it only where allowed.
    $legacy = Join-Path $docs 'WindowsPowerShell\profile.ps1'
    $policy = Get-AosPs51Policy
    if (@('RemoteSigned', 'Unrestricted', 'Bypass') -contains $policy) {
        Set-AosManagedBlock -Path $legacy -Body $body -Start $start -End $end -Position Bottom -Bom -DryRun:$DryRun
        return
    }
    $pattern = '(?s)' + [regex]::Escape($start) + '.*?' + [regex]::Escape($end)
    if ((Test-Path -LiteralPath $legacy) -and [regex]::IsMatch([System.IO.File]::ReadAllText($legacy), $pattern)) {
        if ($DryRun) { Write-AosDry "would take the aos block out of $legacy (5.1 policy: $policy)"; return }
        $rest = [regex]::Replace([System.IO.File]::ReadAllText($legacy), $pattern, '').Trim()
        $saved = Backup-AosFile $legacy
        if ($rest.Length -eq 0) { Remove-Item -LiteralPath $legacy } else { Write-AosText -Path $legacy -Text ($rest + "`n") -Bom }
        Write-AosOk "took the aos block out of the Windows PowerShell 5.1 profile (policy $policy blocks it; backup: $saved)"
    }
    else { Write-AosOk "Windows PowerShell 5.1: no aos profile (policy $policy blocks profile scripts); aos lives in pwsh" }
}

function Sync-AosClaudeSkills {
    # ~/.claude/skills belongs to Claude: the desktop app syncs account skills into its synced\
    # folder. So it stays a real folder and only our shared skills are linked in, one per skill.
    # (-Dir and -RepoSkills exist so the migration can be tested in a sandbox.)
    param([switch]$DryRun, [string]$Dir, [string]$RepoSkills)
    $dir = $Dir
    if (-not $dir) { $dir = Join-Path $HOME '.claude\skills' }
    $repoSkills = $RepoSkills
    if (-not $repoSkills) { $repoSkills = Join-Path $script:Root 'agents-home\skills' }
    $repoSkillsFull = [System.IO.Path]::GetFullPath($repoSkills).TrimEnd('\')
    $item = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        # Earlier layout: the whole folder was a link into an agentic-os checkout (maybe one that has
        # since moved). Migrate only such a link; a link of the user's own is left alone.
        $oldTarget = [System.IO.Path]::GetFullPath(@($item.Target)[0]).TrimEnd('\')
        if (-not $oldTarget.EndsWith('\agents-home\skills', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-AosWarn "$dir is a link of your own (to $oldTarget); left alone - link skills into it by hand"
            return
        }
        if ($DryRun) { Write-AosDry "would turn $dir back into a real folder and link skills one by one"; return }
        # Stage the app's synced\ from wherever the old link pointed, before unlinking; any failure stops here.
        $oldSynced = Join-Path $oldTarget 'synced'
        $staged = $null
        if (Test-Path -LiteralPath $oldSynced) {
            $staged = New-AosBackupPath '-synced-migration'
            if (-not (Move-AosItem -Source $oldSynced -Destination $staged)) {
                throw "could not stage $oldSynced (files in use?); nothing was changed - close the Claude app and run aos sync again"
            }
        }
        [System.IO.Directory]::Delete($dir, $false)
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if ($staged) {
            if (-not (Move-AosItem -Source $staged -Destination (Join-Path $dir 'synced'))) {
                throw "could not move the staged synced skills from $staged into $dir\synced; they are safe in $staged"
            }
            Write-AosOk "moved the Claude app's synced skills from $oldTarget back to $dir\synced"
        }
        Write-AosOk "$dir is a real folder again"
    }
    elseif (-not $item) {
        if ($DryRun) { Write-AosDry "would create $dir" } else { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    }
    # A Claude session started before that change keeps writing synced\ to the old resolved path (the
    # repo) until it restarts. Park such a stray copy outside the repo; the real one is $dir\synced.
    $stray = Join-Path $repoSkills 'synced'
    if (Test-Path -LiteralPath $stray) {
        if ($DryRun) { Write-AosDry "would move the stray $stray to ~/.aos-backups" }
        else {
            $dest = New-AosBackupPath '-stray-synced'
            if (Move-AosItem -Source $stray -Destination $dest) { Write-AosWarn "moved a stray copy of the Claude app's synced skills out of the repo to $dest (restart the Claude app so it stops)" }
            else { Write-AosWarn "could not move the stray $stray (files in use?); left in place, will retry on the next sync" }
        }
    }
    foreach ($s in @(Get-ChildItem -LiteralPath $repoSkills -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath (Join-Path $s.FullName 'SKILL.md'))) { continue }
        Set-AosJunction -Link (Join-Path $dir $s.Name) -Target $s.FullName -DryRun:$DryRun
    }
    # Links to skills that have since left the repo would dangle; remove just the link.
    foreach ($link in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.LinkType })) {
        $t = [System.IO.Path]::GetFullPath(@($link.Target)[0]).TrimEnd('\')
        if ($t.StartsWith($repoSkillsFull + '\', [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath (Join-Path $t 'SKILL.md'))) {
            if ($DryRun) { Write-AosDry "would remove the dangling link $($link.FullName)" }
            else { [System.IO.Directory]::Delete($link.FullName, $false); Write-AosOk "removed the dangling link $($link.FullName)" }
        }
    }
}

function Sync-AosBrain([switch]$DryRun) {
    $root = $script:Root
    $agentsHome = Join-Path $root 'agents-home'
    Update-AosPath

    Write-AosStep 'Shared brain: one skills folder and one AGENTS.md for both agents'
    Set-AosJunction -Link (Join-Path $HOME '.agents') -Target $agentsHome -DryRun:$DryRun
    Sync-AosClaudeSkills -DryRun:$DryRun
    $claudeMd = [System.IO.File]::ReadAllText((Join-Path $root 'config\claude\CLAUDE.md'))
    Set-AosManagedBlock -Path (Join-Path $HOME '.claude\CLAUDE.md') -Body $claudeMd -Position Top `
        -Start '<!-- >>> agentic-os (managed by aos sync; edit config/claude/CLAUDE.md in the repo) >>> -->' `
        -End '<!-- <<< agentic-os <<< -->' -DryRun:$DryRun
    Sync-AosCodexAgents -DryRun:$DryRun

    Write-AosStep 'Codex plugin repairs (cc hooks on Windows)'
    Repair-AosCcHooks -DryRun:$DryRun

    Write-AosStep 'Coordination hooks for Codex (~\.codex\hooks.json: write guard, presence)'
    Sync-AosCodexHooks -DryRun:$DryRun

    Write-AosStep 'Claude Code settings (merged into yours, never replaced)'
    Sync-AosClaudeSettings -DryRun:$DryRun

    Write-AosStep 'Codex profiles (~/.codex/<name>.config.toml; config.toml itself stays the app''s)'
    Sync-AosCodexProfiles -DryRun:$DryRun

    Write-AosStep 'Native worker role definitions (capability-gated; requested settings remain unobserved)'
    Sync-AosNativeRoles -DryRun:$DryRun | ForEach-Object { Write-AosInfo ("$($_.vendor) $($_.role): $($_.status)") }

    Write-AosStep 'Local model state (~\.aos\local.json, read by nar)'
    Sync-AosLocalState -DryRun:$DryRun

    Write-AosStep 'Places (shared folders)'
    Sync-AosPlaces -DryRun:$DryRun

    Write-AosStep 'Local agent model (config/local.json agent_model: the default with a larger context)'
    Sync-AosAgentModel -DryRun:$DryRun

    Write-AosStep 'Pi on the local model (~\.pi\agent: provider aos, compaction, permission gate)'
    Sync-AosPi -DryRun:$DryRun

    Write-AosStep 'MCP servers (same list in both agents)'
    Sync-AosMcp -DryRun:$DryRun

    Write-AosStep 'Shell integration (the aos command in new terminals)'
    Sync-AosProfile -DryRun:$DryRun
}

function Install-AosBridges([switch]$DryRun) {
    Update-AosPath
    Write-AosStep 'Claude Code plugins: codex bridge + superpowers'
    if (-not (Test-AosCommand claude)) { Write-AosWarn 'claude missing; install the engines layer first' }
    else {
        $enabled = Get-AosClaudePlugins
        if ($enabled -contains 'codex@openai-codex') { Write-AosOk 'codex@openai-codex' }
        elseif ($DryRun) { Write-AosDry 'claude plugin marketplace add openai/codex-plugin-cc; claude plugin install codex@openai-codex' }
        else {
            claude plugin marketplace add openai/codex-plugin-cc | Out-Host
            claude plugin install codex@openai-codex | Out-Host
            if ($LASTEXITCODE -eq 0) { Write-AosOk 'codex@openai-codex installed' } else { Write-AosWarn "codex plugin install failed (exit $LASTEXITCODE)" }
        }
        if (@($enabled | Where-Object { $_ -like 'superpowers@*' }).Count -gt 0) { Write-AosOk 'superpowers' }
        elseif ($DryRun) { Write-AosDry 'claude plugin install superpowers@claude-plugins-official' }
        else {
            claude plugin install superpowers@claude-plugins-official | Out-Host
            if ($LASTEXITCODE -ne 0) {
                claude plugin marketplace add anthropics/claude-plugins-official | Out-Host
                claude plugin install superpowers@claude-plugins-official | Out-Host
            }
            if ($LASTEXITCODE -eq 0) { Write-AosOk 'superpowers installed' } else { Write-AosWarn "superpowers install failed (exit $LASTEXITCODE)" }
        }
    }

    Write-AosStep 'Codex plugin: cc-plugin-codex (Claude review/rescue from inside Codex)'
    if (Test-AosCcBridge) { Write-AosOk 'cc-plugin-codex' }
    elseif (-not (Test-AosCommand npx)) { Write-AosWarn 'npx missing; install the base layer first' }
    elseif ($DryRun) { Write-AosDry 'npx -y cc-plugin-codex install' }
    else {
        npx -y cc-plugin-codex install | Out-Host
        if ($LASTEXITCODE -eq 0) { Write-AosOk 'cc-plugin-codex installed' } else { Write-AosWarn "cc-plugin-codex install failed (exit $LASTEXITCODE)" }
    }
    Repair-AosCcHooks -DryRun:$DryRun

    Write-AosStep 'Codex plugin: superpowers (from the openai-curated-remote marketplace)'
    if (@(Get-AosCodexPlugins | Where-Object { $_ -like 'superpowers@*' }).Count -gt 0) { Write-AosOk 'superpowers' }
    elseif (-not (Test-AosCommand codex)) { Write-AosWarn 'codex missing; install the engines layer first' }
    elseif ($DryRun) { Write-AosDry 'codex plugin add superpowers@openai-curated-remote' }
    else {
        codex plugin add superpowers@openai-curated-remote | Out-Host
        if ($LASTEXITCODE -eq 0) { Write-AosOk 'superpowers installed in Codex' } else { Write-AosWarn "codex plugin add superpowers failed (exit $LASTEXITCODE)" }
    }
}

function Get-AosRefsDir {
    # Clones live outside the repo (OneDrive; clones are re-creatable) and outside AppData (a folder a
    # packaged app creates there can stay private to it).
    if ($env:AOS_REFS) { return $env:AOS_REFS }
    return (Join-Path $HOME '.aos\refs')
}

function Get-AosProjectsDir {
    if ($env:AOS_PROJECTS) { return $env:AOS_PROJECTS }
    return (Join-Path (Get-AosDesktopDir) '1-Projects')
}

function Get-AosNarVenv { return (Join-Path (Get-AosStateDir) 'venvs\nar-tools') }

function Get-AosShellFolder([string]$Name) { return [Environment]::GetFolderPath($Name) }

function Get-AosDesktopDir {
    # Codex's sandbox (a restricted token) reports no Desktop shell folder at all.
    $d = Get-AosShellFolder 'Desktop'
    if (-not [string]::IsNullOrWhiteSpace($d)) { return $d }
    if ($env:OneDrive) {
        $od = Join-Path $env:OneDrive 'Desktop'
        if (Test-Path -LiteralPath $od) { return $od }
    }
    return (Join-Path $HOME 'Desktop')
}
function Get-AosPlacesConfigPath { return (Join-Path $script:Root 'config\places.json') }

function Resolve-AosPlacePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $out = $Path.Replace('{{desktop}}', (Get-AosDesktopDir)).Replace('{{projects}}', (Get-AosProjectsDir)).Replace('{{home}}', $HOME)
    if ($out -match '\{\{[^}]*\}\}' -or -not [IO.Path]::IsPathRooted($out)) { return $null }
    try { return [IO.Path]::GetFullPath($out) } catch { return $null }
}

function Get-AosPlaces {
    $cfgPath = Get-AosPlacesConfigPath
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $null }
    $r = Read-AosJsonOrWarn $cfgPath
    if (-not $r.Ok) { return $null }
    $seen = @{}
    $inboxes = 0
    foreach ($p in $r.Value['places']) {
        if (-not ($p -is [Collections.IDictionary])) { Write-AosWarn 'invalid place entry (skipped)'; continue }
        $name = [string]$p['name']; $kind = [string]$p['kind']
        $path = Resolve-AosPlacePath ([string]$p['path'])
        if ([string]::IsNullOrWhiteSpace($name) -or $seen.ContainsKey($name) -or
            @('repo', 'vault', 'folder', 'inbox') -notcontains $kind -or -not $path -or
            ($kind -eq 'inbox' -and $inboxes -gt 0)) { Write-AosWarn "invalid or duplicate place '$name' (skipped)"; continue }
        $seen[$name] = $true
        if ($kind -eq 'inbox') { $inboxes++ }
        [ordered]@{ name = $name; kind = $kind; path = $path; exists = (Test-Path -LiteralPath $path -PathType Container) }
    }
    if ($inboxes -eq 0) { Write-AosWarn 'places: no inbox configured' }
}

function Get-AosNarHome {
    if ($env:NAR_HOME) { return $env:NAR_HOME }
    return (Join-Path (Get-AosStateDir) 'nar')
}

function Install-AosNarTools([switch]$DryRun) {
    # nar-tools (Desktop\1-Projects\nar-tools) runs from a venv under ~\.aos: outside OneDrive, and on the
    # system Python (uv must not download one into AppData, which a packaged app can make private).
    $repo = Join-Path (Get-AosProjectsDir) 'nar-tools'
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'pyproject.toml'))) { Write-AosInfo "nar-tools not found in $repo; skipped"; return }
    if (-not (Test-AosCommand uv)) { Write-AosWarn 'uv missing (aos install base)'; return }
    $venv = Get-AosNarVenv
    if ($DryRun) { Write-AosDry "uv sync --frozen --no-dev (venv $venv)"; return }
    $saved = @{}
    $vars = @{ UV_PROJECT_ENVIRONMENT = $venv; UV_LINK_MODE = 'copy'; UV_PYTHON_DOWNLOADS = 'never' }
    foreach ($k in @($vars.Keys)) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
    try { $r = Invoke-AosCapture "uv sync --frozen --no-dev --directory `"$repo`"" }
    finally { foreach ($k in @($vars.Keys)) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') } }
    if ($r.Code -eq 0) { Write-AosOk "nar-tools ready in $venv" } else { Write-AosWarn "uv sync for nar-tools failed (exit $($r.Code))" }
}

function Invoke-AosLocalAdopt([string]$Tag, [switch]$DryRun) {
    # The only way the default local model changes: the latest `nar eval` must say it is no worse.
    if (-not $Tag) { Write-AosWarn 'usage: aos local adopt <ollama tag>'; return }
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { Write-AosWarn 'config/local.json missing'; return }
    if ($cfg['default'] -eq $Tag) {
        # Still reconcile: repeating an adopt is how a failed rebuild of the agent variant is retried.
        Write-AosOk "$Tag is already the default"
        Sync-AosLocalState -DryRun:$DryRun
        Sync-AosAgentModel -DryRun:$DryRun
        return
    }
    $reportPath = Join-Path (Get-AosNarHome) 'eval\latest.json'
    $report = Read-AosJson $reportPath
    if (-not $report) { Write-AosWarn "no eval report at $reportPath (run: aos nar eval --models $Tag)"; return }
    if ($report['baseline'] -ne $cfg['default']) { Write-AosWarn "the latest report compared against $($report['baseline']), not the current default $($cfg['default']); run aos nar eval again"; return }
    if (-not ($report['verdicts'] -and $report['verdicts'].Contains($Tag))) { Write-AosWarn "the latest report has no verdict for $Tag (run: aos nar eval --models $Tag)"; return }
    $v = $report['verdicts'][$Tag]
    if (-not $v['passes']) { Write-AosWarn ("$Tag did not pass: " + (@($v['reasons']) -join '; ')); return }
    if ($DryRun) { Write-AosDry "would make $Tag the default in config/local.json"; return }
    $cfg['default'] = $Tag
    Write-AosText -Path (Get-AosLocalConfigPath) -Text ((ConvertTo-Json -InputObject $cfg -Depth 10) + "`n")
    Write-AosOk "default local model is now $Tag (commit config/local.json)"
    Sync-AosLocalState
    Sync-AosCodexProfiles
    Sync-AosAgentModel
}

function Invoke-AosNar([string[]]$Arguments) {
    $exe = Join-Path (Get-AosNarVenv) 'Scripts\nar.exe'
    if (-not (Test-Path -LiteralPath $exe)) { Write-AosWarn 'nar-tools is not installed (aos install local)'; return }
    & $exe @Arguments
    $global:LASTEXITCODE = $LASTEXITCODE
}

function Get-AosLocalConfigPath { return (Join-Path $script:Root 'config\local.json') }

function Get-AosLocalConfig {
    $path = Get-AosLocalConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Read-AosJson $path
}

function Get-AosStateDir { return (Join-Path $HOME '.aos') }

function Get-AosOllamaName([string]$Tag) {
    # Ollama shows a bare name with :latest.
    if ($Tag -notmatch ':') { return "${Tag}:latest" }
    return $Tag
}

function Test-AosOllamaModel([string]$List, [string]$Tag) {
    $want = Get-AosOllamaName $Tag
    foreach ($line in ($List -split "`r?`n")) {
        if ((($line.Trim() -split '\s+')[0]) -ieq $want) { return $true }
    }
    return $false
}

function Test-AosOllamaGpu([string]$PsText, [string]$Tag) {
    # `ollama ps` PROCESSOR column: "100% GPU" when the model fits the GPU, "35%/65% CPU/GPU" when split.
    $want = Get-AosOllamaName $Tag
    foreach ($line in ($PsText -split "`r?`n")) {
        if ((($line.Trim() -split '\s+')[0]) -ieq $want) {
            if ($line -match '\b100% GPU\b') { return 'gpu' }
            return 'split'
        }
    }
    return 'absent'
}

function Sync-AosLocalState([switch]$DryRun) {
    # ~\.aos\local.json tells nar the local default, the Ollama URL and the speed floor. Compared by
    # value, not text: Windows PowerShell 5.1 and PowerShell 7 format JSON differently.
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { return }
    $target = Join-Path (Get-AosStateDir) 'local.json'
    $want = [ordered]@{ default = $cfg['default']; ollama_url = $cfg['ollama_url']; min_tokens_per_s = $cfg['min_tokens_per_s'] }
    # embed_model is optional and never pulled here: nar uses it for classify --backend embed once the user pulled it.
    if ($cfg['embed_model']) { $want['embed_model'] = [string]$cfg['embed_model'] }
    $have = Read-AosJson $target
    $same = [bool]$have
    if ($have) { foreach ($k in @($want.Keys)) { if ([string]$have[$k] -ne [string]$want[$k]) { $same = $false } } }
    if ($same) { Write-AosOk "$target up to date"; return }
    if ($DryRun) { Write-AosDry "would write $target"; return }
    Write-AosText -Path $target -Text ((ConvertTo-Json -InputObject $want -Depth 5) + "`n")
    Write-AosOk "wrote $target"
}

function Get-AosAgentModelfile([string]$From, [int]$NumCtx) {
    return "FROM $From`nPARAMETER num_ctx $NumCtx`n"
}

function Get-AosModelfileFacts([string]$Text) {
    # From `ollama show <tag> --modelfile`: the weight blobs (FROM lines), num_ctx, and a normalized
    # definition to compare two models by: """ blocks verbatim, other directives in order, PARAMETER
    # lines as a sorted set; comments, blank lines and num_ctx outside """ blocks are ignored.
    $from = New-Object 'System.Collections.Generic.List[string]'
    $body = New-Object 'System.Collections.Generic.List[string]'
    $params = New-Object 'System.Collections.Generic.List[string]'
    $ctx = $null
    $inQuote = $false
    foreach ($line in ($Text -split "`r?`n")) {
        $odd = (([regex]::Matches($line, '"""')).Count % 2) -eq 1
        if ($inQuote) { $body.Add($line); if ($odd) { $inQuote = $false }; continue }
        $t = $line.Trim()
        if ($odd) { $body.Add($t); $inQuote = $true; continue }
        if (-not $t -or $t.StartsWith('#')) { continue }
        if ($t -match '^PARAMETER\s+num_ctx\s+(\d+)$') { $ctx = [int]$Matches[1]; continue }
        if ($t -match '^PARAMETER\s') { if (-not $params.Contains($t)) { $params.Add($t) }; continue }
        if ($t -match '^FROM\s+(.+)$') { $from.Add($Matches[1].Trim()) }
        $body.Add($t)
    }
    $sorted = $params.ToArray()
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    return @{ From = @($from); NumCtx = $ctx; Definition = ((@($body) + '' + @($sorted)) -join "`n") }
}

function Test-AosAgentModel([string]$Name, [string]$From, [int]$NumCtx) {
    # What Ollama holds is the truth, not bookkeeping: the variant must be the default's definition
    # (weights, template, renderer, parameters, license) plus the configured context.
    # Returns 'ok', 'stale' or 'missing'.
    $variant = Invoke-AosCapture "ollama show $Name --modelfile"
    if ($variant.Code -ne 0) { return 'missing' }
    $v = Get-AosModelfileFacts $variant.Text
    if ($v.NumCtx -ne $NumCtx -or $v.From.Count -eq 0) { return 'stale' }
    $base = Invoke-AosCapture "ollama show $From --modelfile"
    if ($base.Code -ne 0) { return 'stale' }
    $b = Get-AosModelfileFacts $base.Text
    if ($b.From.Count -eq 0 -or -not ($v.Definition -ceq $b.Definition)) { return 'stale' }
    return 'ok'
}

function Sync-AosAgentModel([switch]$DryRun) {
    # Agent harnesses reach the local model through OpenAI-compatible APIs, which cannot set Ollama's
    # context size, so they use this variant of the default model (config/local.json agent_model).
    $cfg = Get-AosLocalConfig
    if (-not $cfg -or -not $cfg['agent_model']) { return }
    if (-not (Test-AosCommand ollama)) { Write-AosWarn 'ollama missing: the agent model is not created (aos install local)'; return }
    $name = [string]$cfg['agent_model']; $from = [string]$cfg['default']; $ctx = [int]$cfg['agent_num_ctx']
    if (-not (Test-AosOllamaModel -List (Invoke-AosCapture 'ollama list').Text -Tag $from)) {
        Write-AosWarn "default model $from is not pulled: $name not created (aos install local)"; return
    }
    $state = Test-AosAgentModel -Name $name -From $from -NumCtx $ctx
    if ($state -eq 'ok') { Write-AosOk "$name ($from, context $ctx)"; return }
    if ($DryRun) { Write-AosDry "ollama create $name from $from with num_ctx $ctx   ($state)"; return }
    $file = Join-Path (Get-AosStateDir) 'agent.Modelfile'
    Write-AosText -Path $file -Text (Get-AosAgentModelfile -From $from -NumCtx $ctx)
    $r = Invoke-AosCapture "ollama create $name -f `"$file`""
    if ($r.Code -ne 0) { Write-AosWarn "ollama create $name failed (exit $($r.Code))"; return }
    $null = Invoke-AosCapture "ollama run $name `"Reply with OK`""   # load it once, then ask where it runs
    switch (Test-AosOllamaGpu -PsText (Invoke-AosCapture 'ollama ps').Text -Tag $name) {
        'gpu'   { Write-AosOk "$name ($from, context $ctx) runs entirely on the GPU" }
        'split' { Write-AosWarn "$name does not fit the GPU at context $ctx and runs partly on the CPU (slower)" }
        default { Write-AosWarn "$name did not load (see ollama ps)" }
    }
}

function Show-AosAgentModelStatus($Local) {
    # One `aos status` line for the agent variant; the caller has checked that ollama runs.
    if (-not $Local -or -not $Local['agent_model']) { return }
    $name = [string]$Local['agent_model']; $from = [string]$Local['default']; $ctx = [int]$Local['agent_num_ctx']
    switch (Test-AosAgentModel -Name $name -From $from -NumCtx $ctx) {
        'ok'    { Write-AosOk "$name ($from, context $ctx)" }
        'stale' { Write-AosWarn "$name is not $from with context $ctx (aos sync)" }
        default { Write-AosWarn "$name missing (aos install local)" }
    }
}

function Install-AosLocal([switch]$DryRun) {
    Update-AosPath
    $cfg = Get-AosLocalConfig
    if (-not $cfg) { Write-AosWarn 'config/local.json missing'; return }
    Write-AosStep 'Local models (Ollama; models in ~\.ollama)'
    foreach ($p in (Get-AosPackages)['local']) { Install-AosWingetPackage -Id $p['id'] -Why $p['why'] -DryRun:$DryRun }
    Update-AosPath
    if (-not (Test-AosCommand ollama)) {
        if (-not $DryRun) { Write-AosWarn 'ollama is not on PATH yet: open a new terminal, then aos install local' }
        return
    }
    $list = (Invoke-AosCapture 'ollama list').Text
    foreach ($tag in @(@($cfg['default']) + @($cfg['optional']) | Where-Object { $_ })) {
        if (Test-AosOllamaModel -List $list -Tag $tag) { Write-AosOk "model $tag"; continue }
        if ($DryRun) { Write-AosDry "ollama pull $tag"; continue }
        Write-AosInfo "pulling $tag (a large download)"
        $r = Invoke-AosCapture "ollama pull $tag"
        if ($r.Code -eq 0) { Write-AosOk "pulled $tag" } else { Write-AosWarn "ollama pull $tag failed (exit $($r.Code))" }
    }
    $default = [string]$cfg['default']
    if (-not $DryRun -and (Test-AosOllamaModel -List (Invoke-AosCapture 'ollama list').Text -Tag $default)) {
        $null = Invoke-AosCapture "ollama run $default `"Reply with OK`""   # load it once, then ask where it runs
        switch (Test-AosOllamaGpu -PsText (Invoke-AosCapture 'ollama ps').Text -Tag $default) {
            'gpu'   { Write-AosOk "$default runs entirely on the GPU" }
            'split' { Write-AosWarn "$default does not fit the GPU and runs partly on the CPU (slower)" }
            default { Write-AosWarn "$default did not load (see ollama ps)" }
        }
    }
    Sync-AosLocalState -DryRun:$DryRun
    Sync-AosAgentModel -DryRun:$DryRun
    Install-AosNarTools -DryRun:$DryRun
    $harness = (Get-AosPackages)['local_npm']
    if ($harness) {
        Write-AosStep 'Local agent harness (npm, in ~\.npm-global)'
        Install-AosNpmTools -Packages $harness -DryRun:$DryRun
    }
    Sync-AosPi -DryRun:$DryRun
}

function Install-AosMedia([switch]$DryRun) {
    # Free media tools the agents drive from the command line (the media-tools skill documents each one).
    # Opt-in: `aos install media`. Playwright browsers, Whisper models and ComfyUI are not installed here.
    Update-AosPath
    Write-AosStep 'Media tools (free; command-line tools and apps, about 1.3 GB in all)'
    foreach ($p in (Get-AosPackages)['media']) {
        Install-AosWingetPackage -Id $p['id'] -Why $p['why'] -SkipDependencies:([bool]$p['skipDependencies']) -DryRun:$DryRun
    }
    Update-AosPath
}

function Get-AosPiDir {
    # Pi's agent directory. PI_CODING_AGENT_DIR moves it for Pi and for aos alike.
    # A leading ~ or a relative path resolves like PowerShell does (home, current location).
    if ($env:PI_CODING_AGENT_DIR) { return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($env:PI_CODING_AGENT_DIR) }
    return (Join-Path $HOME '.pi\agent')
}

function Get-AosPiOverlay {
    # What aos owns in Pi's files, from config/local.json; $null when no agent model is configured.
    $cfg = Get-AosLocalConfig
    if (-not $cfg -or -not $cfg['agent_model']) { return $null }
    $name = [string]$cfg['agent_model']
    $model = [ordered]@{
        id = $name; name = "$name (local)"; input = @('text'); reasoning = $false
        contextWindow = [int]$cfg['agent_num_ctx']; maxTokens = 4096
        # Ollama 0.34 honours max_tokens (Pi sends max_completion_tokens by default) and has no "developer" role.
        compat = [ordered]@{ maxTokensField = 'max_tokens'; supportsDeveloperRole = $false; supportsStore = $false }
    }
    return @{
        Provider = [ordered]@{
            baseUrl = ([string]$cfg['ollama_url']).TrimEnd('/') + '/v1'
            api = 'openai-completions'
            apiKey = 'ollama'   # a dummy key makes the model available; Ollama ignores it
            models = @($model)
        }
        OverrideKey = "aos/$name"
        # Pi's defaults (reserve 16384, keep 20000) do not fit a 16K window.
        Override = [ordered]@{ reserveTokens = 4096; keepRecentTokens = 4096 }
    }
}

function Read-AosJsonOrWarn([string]$Path) {
    # @{ Ok; Value }: Ok is false when the file exists but is not JSON (then it is left alone).
    try {
        $ErrorActionPreference = 'Stop'
        return @{ Ok = $true; Value = (Read-AosJson $Path) }
    }
    catch {
        Write-AosWarn "$Path is not valid JSON: left alone (fix it by hand, then aos sync)"
        return @{ Ok = $false; Value = $null }
    }
}

function Copy-AosTree($Value) {
    if ($null -eq $Value) { return [ordered]@{} }
    return ConvertTo-AosHashtable (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 20))
}

function Set-AosJsonFile([string]$Path, $Old, $New, [string]$Label, [switch]$DryRun) {
    # Both sides are serialized by this shell, so 5.1 and 7 each compare like with like.
    $a = ''
    if ($null -ne $Old) { $a = ConvertTo-Json -InputObject $Old -Depth 20 -Compress }
    $b = ConvertTo-Json -InputObject $New -Depth 20 -Compress
    if ($a -ceq $b) { Write-AosOk "$Label up to date"; return }
    if ($DryRun) { Write-AosDry "would update $Path ($Label)"; return }
    if (Test-Path -LiteralPath $Path) { $null = Backup-AosFile $Path }
    Write-AosText -Path $Path -Text ((ConvertTo-Json -InputObject $New -Depth 20) + "`n")
    Write-AosOk "updated $Path ($Label)"
}

function Sync-AosPi([switch]$DryRun) {
    # Pi on the local model. aos owns providers.aos in models.json, three
    # settings and the aos-permission-gate extension; everything else in Pi's folder is the user's.
    if (-not (Test-AosCommand pi)) { Write-AosInfo 'pi is not installed: Pi setup skipped (aos install local)'; return }
    $o = Get-AosPiOverlay
    if (-not $o) { return }
    $dir = Get-AosPiDir

    $path = Join-Path $dir 'models.json'
    $r = Read-AosJsonOrWarn $path
    if ($r.Ok) {
        $new = Copy-AosTree $r.Value
        if (-not ($new['providers'] -is [System.Collections.IDictionary])) { $new['providers'] = [ordered]@{} }
        $new['providers']['aos'] = $o.Provider
        Set-AosJsonFile -Path $path -Old $r.Value -New $new -Label 'Pi provider aos (local model)' -DryRun:$DryRun
    }

    $path = Join-Path $dir 'settings.json'
    $r = Read-AosJsonOrWarn $path
    if ($r.Ok) {
        $new = Copy-AosTree $r.Value
        $new['enableInstallTelemetry'] = $false
        if (-not ($new['compaction'] -is [System.Collections.IDictionary])) { $new['compaction'] = [ordered]@{} }
        $new['compaction']['enabled'] = $true   # global in Pi; a 16K window cannot work without it
        if (-not ($new['compaction']['modelOverrides'] -is [System.Collections.IDictionary])) { $new['compaction']['modelOverrides'] = [ordered]@{} }
        $new['compaction']['modelOverrides'][$o.OverrideKey] = $o.Override
        Set-AosJsonFile -Path $path -Old $r.Value -New $new -Label 'Pi settings (compaction, telemetry off)' -DryRun:$DryRun
    }

    $src = Join-Path $script:Root 'config\pi\extensions\aos-permission-gate.ts'
    $dest = Join-Path $dir 'extensions\aos-permission-gate.ts'
    $want = [System.IO.File]::ReadAllText($src)
    $have = $null
    if (Test-Path -LiteralPath $dest) { $have = [System.IO.File]::ReadAllText($dest) }
    if ($have -ceq $want) { Write-AosOk 'Pi permission gate up to date' }
    elseif ($DryRun) { Write-AosDry "would install $dest" }
    else {
        if ($null -ne $have) { $null = Backup-AosFile $dest }
        Write-AosText -Path $dest -Text $want
        Write-AosOk "installed $dest"
    }

    $src = Join-Path $script:Root 'config\pi\extensions\aos-file-tools.ts'
    $dest = Join-Path $dir 'extensions\aos-file-tools.ts'
    $want = [System.IO.File]::ReadAllText($src)
    $have = $null
    if (Test-Path -LiteralPath $dest) { $have = [System.IO.File]::ReadAllText($dest) }
    if ($have -ceq $want) { Write-AosOk 'Pi file tools up to date' }
    elseif ($DryRun) { Write-AosDry "would install $dest" }
    else {
        if ($null -ne $have) { $null = Backup-AosFile $dest }
        Write-AosText -Path $dest -Text $want
        Write-AosOk "installed $dest"
    }

    $src = Join-Path $script:Root 'config\pi\extensions\aos-web-search.ts'
    $dest = Join-Path $dir 'extensions\aos-web-search.ts'
    $want = [System.IO.File]::ReadAllText($src)
    $have = $null
    if (Test-Path -LiteralPath $dest) { $have = [System.IO.File]::ReadAllText($dest) }
    if ($have -ceq $want) { Write-AosOk 'Pi web search extension up to date' }
    elseif ($DryRun) { Write-AosDry "would install $dest" }
    else {
        if ($null -ne $have) { $null = Backup-AosFile $dest }
        Write-AosText -Path $dest -Text $want
        Write-AosOk "installed $dest"
    }
}

function Sync-AosRefs([switch]$DryRun) {
    Update-AosPath
    $dest = Get-AosRefsDir
    Write-AosStep "Reference repos (refs/repos.json -> $dest, shallow)"
    if (-not (Test-AosCommand git)) { Write-AosWarn 'git missing; install the base layer first'; return }
    $manifest = Read-AosJson (Join-Path $script:Root 'refs\repos.json')
    foreach ($r in $manifest['repos']) {
        $slug = $r['slug']
        if ($r.Contains('clone') -and -not $r['clone']) { Write-AosInfo "link only: https://github.com/$slug"; continue }
        $dir = Join-Path (Join-Path $dest $r['shelf']) $slug.Replace('/', '\')   # <shelf>\<owner>\<name>: two repos may share a name
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
            if ($DryRun) { Write-AosDry "git pull $slug"; continue }
            git -C $dir pull --ff-only --quiet
            if ($LASTEXITCODE -eq 0) { Write-AosOk "pulled $slug" } else { Write-AosWarn "pull failed: $slug" }
        }
        else {
            if ($DryRun) { Write-AosDry "git clone --depth 1 $slug"; continue }
            git clone --depth 1 --quiet "https://github.com/$slug.git" $dir
            if ($LASTEXITCODE -eq 0) { Write-AosOk "cloned $slug" } else { Write-AosWarn "clone failed: $slug" }
        }
    }
}

function Show-AosNextSteps {
    Write-AosStep 'One-time steps only you can do'
    Write-AosInfo '1. Open a NEW PowerShell 7 window (pwsh) so PATH and the aos command load.'
    Write-AosInfo '2. Claude Code: run  claude  once and sign in with your Claude Pro account.'
    Write-AosInfo '3. Codex: run  codex login status  (the desktop app already signed you in; if not: codex login).'
    Write-AosInfo '4. GitHub: run  gh auth login.  Git identity (once):  git config --global user.name "Your Name"'
    Write-AosInfo '   and  git config --global user.email "you@example.com"'
    Write-AosInfo '5. In Claude Code: /codex:setup  (add --enable-review-gate to have Codex review before Claude stops; costs Codex quota).'
    Write-AosInfo '6. Restart the Codex app so it loads its new plugins; then in Codex: $cc:setup'
    Write-AosInfo '7. Optional: Settings > Apps > Advanced app settings > App execution aliases: turn off python.exe/python3.exe.'
    Write-AosInfo '8. Windows PowerShell 5.1 blocks profile scripts by default. Use pwsh, or run yourself:'
    Write-AosInfo '   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
    Write-AosInfo '9. Phone: install the Claude and ChatGPT apps, then README "From your phone" (aos remote;'
    Write-AosInfo '   Codex app > Settings > Connections > Control this PC).'
    Write-AosInfo 'Then: aos status'
}

function Install-AosLayer {
    param([string[]]$Layer = @('all'), [switch]$DryRun)
    if ($Layer -contains 'all') { $Layer = @($script:Layers | Where-Object { $script:OptInLayers -notcontains $_ }) }
    Update-AosPath   # a terminal opened before an install still gets the new tools
    foreach ($l in $Layer) {
        if ($script:Layers -notcontains $l) { Write-AosWarn "unknown layer '$l' (choose from: $($script:Layers -join ', '), all)"; return }
    }
    if ($DryRun) { Write-AosInfo 'DRY RUN: checks only; nothing is installed or written.' }
    foreach ($l in $script:Layers) {
        if ($Layer -notcontains $l) { continue }
        switch ($l) {
            'base'    { Install-AosBase -DryRun:$DryRun }
            'engines' { Install-AosEngines -DryRun:$DryRun }
            'brain'   { Sync-AosBrain -DryRun:$DryRun }
            'bridges' { Install-AosBridges -DryRun:$DryRun }
            'refs'    { Sync-AosRefs -DryRun:$DryRun }
            'local'   { Install-AosLocal -DryRun:$DryRun }
            'media'   { Install-AosMedia -DryRun:$DryRun }
        }
    }
    Show-AosNextSteps
}

#endregion
#region status, update, usage -----------------------------------------------------------

function Get-AosStatus {
    Update-AosPath
    $root = $script:Root
    Write-AosStep "agentic-os at $root"

    Write-AosStep 'Tools'
    foreach ($t in @('git', 'gh', 'pwsh', 'node', 'npm', 'py', 'uv', 'rg', 'fd', 'jq', 'fzf', 'delta', 'code', 'claude', 'codex', 'ccusage')) {
        if (Test-AosCommand $t) {
            $v = (Invoke-AosCapture "$t --version").Text.Split("`n")[0].Trim()
            Write-AosOk ('{0,-8} {1}' -f $t, $v)
        }
        else { Write-AosWarn ('{0,-8} missing' -f $t) }
    }
    if (-not (Test-Path -LiteralPath (Join-Path (Get-AosCodexStandaloneBin) 'codex.exe'))) {
        Write-AosWarn "standalone Codex CLI not found in $(Get-AosCodexStandaloneBin) (aos install engines)"
    }
    foreach ($n in (Get-AosPackages)['npm']) {
        if (-not (Test-Path -LiteralPath (Join-Path (Get-AosNpmPrefix) "$($n['name']).cmd"))) { Write-AosWarn "$($n['name']) is not in $(Get-AosNpmPrefix) (aos install base)" }
    }
    $ps7 = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($ps7 -and $ps7.Source -like '*\WindowsApps\*') { Write-AosWarn 'pwsh is the Store (MSIX) edition: what it installs under AppData stays private to it. Reinstall: winget install --id Microsoft.PowerShell -e --installer-type wix' }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py -and $py.Source -like '*\WindowsApps\*') { Write-AosWarn 'python is the Microsoft Store stub; use py, or turn off the python.exe App execution alias' }

    $local = Get-AosLocalConfig
    if ($local) {
        Write-AosStep 'Local models'
        if (-not (Test-AosCommand ollama)) { Write-AosWarn 'ollama missing (aos install local)' }
        else {
            $r = Invoke-AosCapture 'ollama list'
            if ($r.Code -ne 0) { Write-AosWarn 'ollama is installed but not running (start the Ollama app)' }
            elseif (-not (Test-AosOllamaModel -List $r.Text -Tag $local['default'])) { Write-AosWarn "default model $($local['default']) not pulled (aos install local)" }
            else {
                switch (Test-AosOllamaGpu -PsText (Invoke-AosCapture 'ollama ps').Text -Tag $local['default']) {
                    'gpu'   { Write-AosOk "default model $($local['default']) (loaded, 100% GPU)" }
                    'split' { Write-AosWarn "default model $($local['default']) is loaded split across CPU and GPU" }
                    default { Write-AosOk "default model $($local['default']) (not loaded right now)" }
                }
                Show-AosAgentModelStatus $local
            }
        }
    }

    Write-AosStep 'Logins'
    if (Test-AosCommand codex) {
        $r = Invoke-AosCapture 'codex login status'
        if ($r.Code -eq 0) { Write-AosOk ('codex: ' + $r.Text.Split("`n")[0]) } else { Write-AosWarn 'codex: not logged in (codex login)' }
    }
    if (Test-AosCommand claude) {
        $r = Invoke-AosCapture 'claude auth status'   # JSON; exit code 1 when logged out
        $method = ''
        if ($r.Text -match '"authMethod"\s*:\s*"([^"]+)"') { $method = $Matches[1] }
        if ($r.Code -eq 0 -and $r.Text -match '"loggedIn"\s*:\s*true') { Write-AosOk "claude: logged in ($method)" }
        else { Write-AosWarn 'claude: not logged in (run claude once and sign in with Claude Pro)' }
    }
    if (Test-AosCommand gh) {
        if ((Invoke-AosCapture 'gh auth status').Code -eq 0) { Write-AosOk 'gh: logged in' } else { Write-AosWarn 'gh: not logged in (gh auth login)' }
    }

    Write-AosStep 'Shared brain'
    $pairs = @(, @((Join-Path $HOME '.agents'), (Join-Path $root 'agents-home')))
    foreach ($s in @(Get-ChildItem -LiteralPath (Join-Path $root 'agents-home\skills') -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $s.FullName 'SKILL.md')) { $pairs += , @((Join-Path $HOME ".claude\skills\$($s.Name)"), $s.FullName) }
    }
    foreach ($pair in $pairs) {
        $item = Get-Item -LiteralPath $pair[0] -Force -ErrorAction SilentlyContinue
        $ok = $false
        if ($item -and $item.LinkType) {
            $t = @($item.Target)[0]
            $ok = ([System.IO.Path]::GetFullPath($t).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($pair[1]).TrimEnd('\'))
        }
        if ($ok) { Write-AosOk "$($pair[0]) -> $($pair[1])" } else { Write-AosWarn "$($pair[0]) is not linked to the repo (aos sync)" }
    }
    $codexAgents = Join-Path $HOME '.codex\AGENTS.md'
    if ((Test-Path -LiteralPath $codexAgents) -and ([System.IO.File]::ReadAllText($codexAgents) -eq (Get-AosCodexAgentsText))) { Write-AosOk '~/.codex/AGENTS.md in sync' }
    else { Write-AosWarn '~/.codex/AGENTS.md missing or stale (aos sync)' }
    $claudeMd = Join-Path $HOME '.claude\CLAUDE.md'
    if ((Test-Path -LiteralPath $claudeMd) -and ([System.IO.File]::ReadAllText($claudeMd) -match '@~/\.agents/AGENTS\.md')) { Write-AosOk '~/.claude/CLAUDE.md imports ~/.agents/AGENTS.md' }
    else { Write-AosWarn '~/.claude/CLAUDE.md does not import the shared AGENTS.md (aos sync)' }
    foreach ($p in (Get-AosCodexProfiles)) {
        if ((Test-Path -LiteralPath $p.Target) -and ([System.IO.File]::ReadAllText($p.Target) -eq $p.Text)) { Write-AosOk "codex --profile $($p.Name)" }
        else { Write-AosWarn "codex --profile $($p.Name): ~/.codex/$($p.Name).config.toml missing or stale (aos sync)" }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $root 'agents-home\skills') -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $d.FullName 'SKILL.md')) { Write-AosOk "skill: $($d.Name)" }
        elseif ($d.Name -eq 'synced') { Write-AosWarn 'stray copy of the Claude app''s synced skills in the repo: restart the Claude app, then aos sync' }
        else { Write-AosWarn "skill folder without SKILL.md: $($d.Name)" }
    }

    Show-AosMcpStatus

    Write-AosStep 'Cross-vendor bridges'
    $enabled = Get-AosClaudePlugins
    foreach ($want in @('codex@openai-codex', 'superpowers@claude-plugins-official')) {
        if ($enabled -contains $want) { Write-AosOk "claude plugin: $want" } else { Write-AosWarn "claude plugin missing: $want (aos install bridges)" }
    }
    if (Test-AosCcBridge) { Write-AosOk 'codex plugin: cc-plugin-codex' } else { Write-AosWarn 'codex plugin: cc-plugin-codex not detected (aos install bridges, then $cc:setup in Codex)' }
    if (@(Get-AosCodexPlugins | Where-Object { $_ -like 'superpowers@*' }).Count -gt 0) { Write-AosOk 'codex plugin: superpowers' }
    elseif ($haveCodex) { Write-AosWarn 'codex plugin: superpowers not enabled (aos install bridges)' }

    Write-AosStep 'Hygiene'
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $suspect = '(?i)(api[_-]?key|auth[_-]?token|secret|password)\s*=\s*["''][^"'']{12,}|sk-[A-Za-z0-9_-]{20,}'
    $clean = $true
    foreach ($f in @((Join-Path $docs 'PowerShell\profile.ps1'), (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'),
                     (Join-Path $docs 'WindowsPowerShell\profile.ps1'), (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'))) {
        if ((Test-Path -LiteralPath $f) -and ([System.IO.File]::ReadAllText($f) -match $suspect)) {
            Write-AosWarn "possible plaintext secret in $f - move it to: aos secret set <name>"; $clean = $false
        }
    }
    if ($clean) { Write-AosOk 'no plaintext secrets found in PowerShell profiles' }
    Write-AosInfo 'Limits: /usage in Claude Code, /status in Codex, or aos usage for local history.'
    Write-AosStep 'Places'
    Show-AosPlacesStatus
}

function Update-Aos([switch]$DryRun) {
    Update-AosPath
    $pkgs = Get-AosPackages
    Write-AosStep 'winget upgrades'
    foreach ($p in $pkgs['base']) {
        $id = $p['id']
        if (-not (Test-AosWinget $id)) { Write-AosWarn "$id not installed (aos install base)"; continue }
        $extra = @()
        if ($p['installerType']) { $extra = @('--installer-type', $p['installerType']) }
        if ((@('wix', 'msi') -contains $p['installerType']) -and (Test-AosInstalledAsMsix $id)) {
            Write-AosWarn "$id is the MSIX edition; winget can't upgrade it into $($p['installerType']). Migrate: winget uninstall --id $id -e, then aos install base"
            continue
        }
        if ($DryRun) { Write-AosDry "winget upgrade --id $id $($extra -join ' ')"; continue }
        $null = winget upgrade --id $id -e @extra --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        switch ($LASTEXITCODE) {
            0 { Write-AosOk "$id up to date" }
            -1978335189 { Write-AosOk "$id already latest" }
            default { Write-AosWarn "${id}: winget exit code $LASTEXITCODE" }
        }
    }

    Write-AosStep 'Claude Code'
    if (Test-AosCommand claude) {
        if ($DryRun) { Write-AosDry 'claude update; claude plugin marketplace update; claude plugin update ...' }
        else {
            claude update | Out-Host
            claude plugin marketplace update | Out-Host
            foreach ($name in (Get-AosClaudePlugins)) { claude plugin update $name | Out-Host }
        }
    }

    Write-AosStep 'Codex CLI'
    if ($DryRun) { Write-AosDry 'irm https://chatgpt.com/codex/install.ps1 | iex   (re-run installs the latest release)' }
    else { Invoke-AosCodexInstaller }

    Write-AosStep 'Codex-side bridge and npm tools'
    if (Test-AosCommand npm) {
        Use-AosNpmPrefix -DryRun:$DryRun
        foreach ($n in $pkgs['npm']) {
            if ($DryRun) { Write-AosDry "npm install -g $($n['name'])@latest"; continue }
            npm install -g "$($n['name'])@latest" --prefix (Get-AosNpmPrefix) | Out-Host
        }
        if (Test-AosCcBridge) {
            if ($DryRun) { Write-AosDry 'npx -y cc-plugin-codex@latest install' } else { npx -y cc-plugin-codex@latest install | Out-Host }
        }
    }
    Write-AosInfo 'The Codex desktop app and its plugins update through the Microsoft Store and the app itself.'

    Sync-AosRefs -DryRun:$DryRun
    Sync-AosBrain -DryRun:$DryRun
}

function Install-AosPester([switch]$DryRun) {
    # Pester 5 for BOTH shells: Windows PowerShell 5.1 ships only Pester 3.4. PowerShell 7's
    # PSResourceGet installs its own copy and saves one into the 5.1 module folder (the inbox
    # PowerShellGet 1.0 of 5.1 can't install it cleanly).
    Write-AosStep 'Pester 5 (test framework, for aos test)'
    if (-not (Test-AosCommand pwsh)) { Write-AosWarn 'pwsh missing; Pester skipped'; return }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $targets = @(
        @{ Shell = 'pwsh'; Dir = (Join-Path $docs 'PowerShell\Modules') },
        @{ Shell = 'powershell'; Dir = (Join-Path $docs 'WindowsPowerShell\Modules') }
    )
    foreach ($t in $targets) {
        $has = & $t.Shell -NoProfile -Command "[bool](Get-Module -ListAvailable -Name Pester | Where-Object { `$_.Version -ge [version]'5.5.0' })"
        if ("$has".Trim() -eq 'True') { Write-AosOk "Pester 5 for $($t.Shell)"; continue }
        if ($DryRun) { Write-AosDry "save Pester 5 into $($t.Dir)"; continue }
        New-Item -ItemType Directory -Force -Path $t.Dir | Out-Null
        pwsh -NoProfile -Command "Save-PSResource -Name Pester -Version '[5.5.0,6.0)' -Path '$($t.Dir.Replace("'", "''"))' -TrustRepository -Quiet"
        if ($LASTEXITCODE -eq 0) { Write-AosOk "Pester 5 saved for $($t.Shell)" } else { Write-AosWarn "Pester install for $($t.Shell) failed (exit $LASTEXITCODE)" }
    }
}

function Invoke-AosTest {
    # Static checks, then the Pester suite under BOTH Windows PowerShell 5.1 and PowerShell 7.
    # Fails loudly on parse errors, non-ASCII bytes, missing Pester 5, zero tests or any failure.
    Update-AosPath
    $root = $script:Root
    $failed = $false
    Write-AosStep 'Static checks'
    foreach ($f in @('aos.psm1', 'bootstrap.ps1', 'tests\Run-Tests.ps1', 'config\coordination.ps1', 'config\task-contracts.ps1', 'config\coordination-learning.ps1', 'config\native-coordination.ps1', 'config\readiness.ps1', 'tools\coordination-eval.ps1', 'tools\coord.ps1', 'tools\coordination-smoke.ps1')) {
        $path = Join-Path $root $f
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { $failed = $true; foreach ($err in $errors) { Write-AosWarn "${f}:$($err.Extent.StartLineNumber) $($err.Message)" } }
        else { Write-AosOk "$f parses" }
        $bad = @([System.IO.File]::ReadAllBytes($path) | Where-Object { $_ -gt 127 }).Count
        if ($bad) { $failed = $true; Write-AosWarn "$f has $bad non-ASCII bytes" } else { Write-AosOk "$f is ASCII" }
    }
    $runner = Join-Path $root 'tests\Run-Tests.ps1'
    foreach ($shell in @('powershell', 'pwsh')) {
        Write-AosStep "Pester suite under $shell"
        if (-not (Test-AosCommand $shell)) { Write-AosWarn "$shell not found"; $failed = $true; continue }
        & $shell -NoProfile -ExecutionPolicy Bypass -File $runner | Out-Host
        if ($LASTEXITCODE -ne 0) { $failed = $true; Write-AosWarn "${shell}: suite failed (exit $LASTEXITCODE)" }
        else { Write-AosOk "${shell}: all tests passed" }
    }
    if ($failed) { Write-AosWarn 'aos test: FAILED'; $global:LASTEXITCODE = 1 }
    else { Write-AosOk 'aos test: all green'; $global:LASTEXITCODE = 0 }
}

function Show-AosUsage {
    # Uses the installed ccusage only: no npx download-and-run on every call.
    Update-AosPath
    if (-not (Test-AosCommand ccusage)) { Write-AosWarn 'ccusage is not installed (aos install base)'; return }
    Write-AosStep 'Claude Code: current 5-hour block (local logs)'
    ccusage blocks --active
    Write-AosStep 'Codex: recent days (local logs)'
    ccusage codex daily
    Write-AosInfo 'These are estimates from local logs. The authoritative limits: /usage in Claude Code, /status in Codex.'
}

#endregion
#region projects and secrets ---------------------------------------------------------------

function New-AosProject([string]$Path) {
    if (-not $Path) { Write-AosWarn 'usage: aos new <name>  (or a full path)'; return }
    Update-AosPath
    if ([System.IO.Path]::IsPathRooted($Path)) { $full = $Path }
    elseif ($Path -notmatch '[\\/]' -and $Path -notmatch '^\.') { $full = Join-Path (Get-AosProjectsDir) $Path }   # bare name -> Desktop\1-Projects
    else { $full = Join-Path (Get-Location).Path $Path }
    $full = [System.IO.Path]::GetFullPath($full)
    New-Item -ItemType Directory -Force -Path $full | Out-Null
    $name = Split-Path -Leaf $full
    Write-AosStep "Project $name"
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $script:Root 'templates\project') -File -Force) {
        $targetName = $f.Name
        if ($targetName.StartsWith('_')) { $targetName = '.' + $targetName.Substring(1) }   # _gitignore -> .gitignore
        $target = Join-Path $full $targetName
        if (Test-Path -LiteralPath $target) { Write-AosInfo "kept existing $targetName"; continue }
        Write-AosText -Path $target -Text ([System.IO.File]::ReadAllText($f.FullName).Replace('{{name}}', $name))
        Write-AosOk "created $targetName"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $full '.git'))) {
        if (-not (Test-AosCommand git)) { Write-AosWarn 'git missing; not initialised' }
        else {
            git -C $full init --quiet
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $full '.git'))) { Write-AosOk 'git init' }
            else { Write-AosWarn "git init failed (exit $LASTEXITCODE)" }
        }
    }
    $null = Add-AosPlace -Path $full -Kind repo
    Write-AosInfo 'Next: fill in the Commands section of AGENTS.md, then open the folder in Claude Code or Codex.'
}

function Get-AosVideoMediaDir([string]$Name) {
    # Heavy media (renders, stems, the render app) stays outside OneDrive.
    if ($env:AOS_VIDEO_HOME) { return (Join-Path $env:AOS_VIDEO_HOME $Name) }
    return (Join-Path $HOME (Join-Path '.aos\video' $Name))
}

function Get-AosRemotionModules {
    # The shared Remotion + three.js install (about 480 MB), made once and linked into every video project.
    if ($env:AOS_REMOTION_MODULES) { return $env:AOS_REMOTION_MODULES }
    return (Join-Path $HOME '.aos\scratch\video-agi-race\node_modules')
}

function New-AosVideo([string]$Name) {
    # A video project = the video template (pipeline tools, kit, stage docs) + a normal project + a render app
    # outside OneDrive that links the shared node_modules and this project's src/.
    if (-not $Name -or $Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$') {
        Write-AosWarn 'usage: aos video new <name>  (letters, digits, - _ . ; becomes Desktop\1-Projects\videos\<name>)'
        return
    }
    $full = Join-Path (Join-Path (Get-AosProjectsDir) 'videos') $Name
    $src = Join-Path $script:Root 'templates\video'
    Write-AosStep "Video $Name"
    New-Item -ItemType Directory -Force -Path $full | Out-Null
    foreach ($f in Get-ChildItem -LiteralPath $src -File -Recurse -Force) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        $leaf = Split-Path -Leaf $rel
        if ($leaf.StartsWith('_')) {
            $parent = Split-Path -Parent $rel
            $rel = '.' + $leaf.Substring(1)   # _gitignore -> .gitignore
            if ($parent) { $rel = Join-Path $parent $rel }
        }
        $target = Join-Path $full $rel
        if (Test-Path -LiteralPath $target) { Write-AosInfo "kept existing $rel"; continue }
        Write-AosText -Path $target -Text ([System.IO.File]::ReadAllText($f.FullName).Replace('{{name}}', $Name))
    }
    Write-AosOk "template files in $full"
    New-AosProject -Path $full
    $media = Get-AosVideoMediaDir $Name
    foreach ($d in @('app\public\vo', 'renders', 'frames', 'audio', 'qa')) { New-Item -ItemType Directory -Force -Path (Join-Path $media $d) | Out-Null }
    $srcLink = Join-Path $media 'app\src'
    if (-not (Test-Path -LiteralPath $srcLink)) { New-Item -ItemType Junction -Path $srcLink -Target (Join-Path $full 'src') | Out-Null }
    $modLink = Join-Path $media 'app\node_modules'
    $mods = Get-AosRemotionModules
    if (Test-Path -LiteralPath $modLink) { Write-AosOk 'render app already linked to node_modules' }
    elseif (Test-Path -LiteralPath $mods) {
        New-Item -ItemType Junction -Path $modLink -Target $mods | Out-Null
        Write-AosOk "render app in $media\app (node_modules -> $mods)"
    }
    else { Write-AosWarn "shared Remotion install not found at ${mods}: install it once (about 480 MB; ask first), then run aos video new $Name again" }
    # The preflight report is made once here; afterwards it is refreshed only on request (aos video preflight).
    if (-not (Test-Path -LiteralPath (Join-Path $full 'PREFLIGHT.md'))) { $null = Write-AosVideoPreflight -Name $Name }
    Write-AosInfo 'Next: read PREFLIGHT.md (invariant rules and the craft frontier), then fill brief.md and rubric.md.'
}

# Video learning loop: the user's verdicts and stage timings go to the coordination ledger (append-safe, outside
# the repo); `aos video preflight` turns rules + ledger into PREFLIGHT.md at the start of the next video.

$script:VideoStages = @('brief', 'look', 'structure', 'production', 'qa', 'delivery', 'retro', 'revision')

function Test-AosVideoName([string]$Name) { return ($Name -and $Name -match '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$') }

function Get-AosVideoRulesPath {
    if ($env:AOS_VIDEO_RULES) { return $env:AOS_VIDEO_RULES }
    return (Join-Path $script:Root 'agents-home\video\video-rules.md')
}

function Get-AosVideoFamily([string]$Name) {
    # alignment-3, alignment, Alignment-v2 -> alignment: versions of one video share their verdicts.
    return ($Name.ToLowerInvariant() -replace '-v?\d+$', '')
}

function Add-AosVideoVerdict([string]$Name, [string]$Text) {
    if (-not (Test-AosVideoName $Name) -or -not $Text -or -not $Text.Trim()) {
        Write-AosWarn 'usage: aos video verdict <name> <the user''s words, verbatim>'
        return
    }
    Add-AosLedgerEvent ([ordered]@{ type = 'video-verdict'; video = $Name; text = $Text })
    Write-AosOk "verdict on $Name recorded"
}

function Add-AosVideoStage([string]$Name, [string]$Stage, [string]$Minutes, [string]$Note = '') {
    $usage = 'usage: aos video log <name> <' + ($script:VideoStages -join '|') + '> <minutes> [note]'
    $m = 0.0
    $styles = [System.Globalization.NumberStyles]::Float
    $ok = (Test-AosVideoName $Name) -and ($script:VideoStages -contains $Stage) -and
        [double]::TryParse($Minutes, $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$m) -and $m -ge 0
    if (-not $ok) { Write-AosWarn $usage; return }
    if ($null -eq $Note) { $Note = '' }
    Add-AosLedgerEvent ([ordered]@{ type = 'video-stage'; video = $Name; stage = $Stage; minutes = $m; note = $Note })
    Write-AosOk "$Name $Stage $m min recorded"
}

function Format-AosNumber([double]$Value) { return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }

function Get-AosVideoFrontierPath {
    if ($env:AOS_VIDEO_FRONTIER) { return $env:AOS_VIDEO_FRONTIER }
    return (Join-Path $script:Root 'agents-home\video\frontier.md')
}

function Write-AosVideoPreflight([string]$Name, [switch]$Verdicts) {
    # Agents start from the invariants and the craft frontier (best so far, next target); raw verdicts are an
    # audit trail, shown only with -Verdicts and never stored in PREFLIGHT.md, so old critiques do not read as limits.
    $nl = "`n"
    $events = @(Get-AosLedger -Last 0)
    $family = Get-AosVideoFamily $Name
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("# Preflight: $Name$nl$nl")
    [void]$sb.Append("Generated by ``aos video preflight $Name`` from the video rules, the craft frontier and the coordination ledger. Refresh it with that command; do not edit it.$nl$nl")
    [void]$sb.Append("## Invariants$nl$nl")
    $rulesPath = Get-AosVideoRulesPath
    if (Test-Path -LiteralPath $rulesPath) {
        foreach ($line in [System.IO.File]::ReadAllLines($rulesPath)) {
            # Stage headings in the rules file become sub-headings here, so the report reads stage by stage.
            if ($line -match '^## (.+)$') { [void]$sb.Append("$nl### $($Matches[1])$nl$nl"); continue }
            if ($line -notmatch '^- R\d{2} ') { continue }
            $out = $line
            if ($line -match '\[check: ([a-z-]+)\]') { $out += " (runs tools/checks/$($Matches[1]).mjs from tools/qa.sh)" }
            [void]$sb.Append($out + $nl)
        }
    }
    else { [void]$sb.Append("- rules file not found: $rulesPath$nl") }
    [void]$sb.Append("$nl## Frontier$nl$nl")
    $frontierPath = Get-AosVideoFrontierPath
    if (Test-Path -LiteralPath $frontierPath) {
        $frontier = [System.IO.File]::ReadAllText($frontierPath).Replace("`r`n", $nl)
        # Only the file's own title line goes; the body is inserted as written.
        if ($frontier -match '^# [^\n]*\n') { $frontier = $frontier.Substring($Matches[0].Length) }
        [void]$sb.Append($frontier)
        if (-not $frontier.EndsWith($nl)) { [void]$sb.Append($nl) }
    }
    else { [void]$sb.Append("- frontier file not found: $frontierPath$nl") }
    [void]$sb.Append("$nl## Stage minutes$nl$nl")
    $stages = @($events | Where-Object { $_['type'] -eq 'video-stage' -and $_['stage'] })
    if ($stages.Count -eq 0) { [void]$sb.Append("- none recorded$nl") }
    foreach ($s in $script:VideoStages) {
        $vals = @($stages | Where-Object { $_['stage'] -eq $s } | ForEach-Object { [double]$_['minutes'] } | Sort-Object)
        if ($vals.Count -eq 0) { continue }
        $mid = [int][Math]::Floor($vals.Count / 2)
        $median = $vals[$mid]
        if ($vals.Count % 2 -eq 0) { $median = ($vals[$mid - 1] + $vals[$mid]) / 2 }
        $runs = 'runs'
        if ($vals.Count -eq 1) { $runs = 'run' }
        [void]$sb.Append("- ${s}: median $(Format-AosNumber $median) min ($($vals.Count) $runs)$nl")
    }
    [void]$sb.Append("$nl## Delegations$nl$nl")
    $dels = @($events | Where-Object { $_['type'] -eq 'delegate' })
    if ($dels.Count -eq 0) { [void]$sb.Append("- none recorded$nl") }
    foreach ($g in @($dels | Group-Object { [string]$_['outcome'] } | Sort-Object Name)) {
        [void]$sb.Append("- $($g.Name): $($g.Count)$nl")
    }
    [void]$sb.Append("$nl### Capacity and split$nl$nl")
    [void]$sb.Append("- At the start and at every gate: ``aos capacity`` (both vendors' windows and resets) and ``aos who`` (claims, notes).$nl")
    [void]$sb.Append("- Write the split (who builds what until when) in an ``aos note`` and HANDOFF.md; a limited vendor's next task goes to the other one at once (R34).$nl")
    [void]$sb.Append("- Codex delegations: a task file with Read only: and Done = lines (R40).$nl")
    $report = $sb.ToString()
    $folder = Join-Path (Join-Path (Get-AosProjectsDir) 'videos') $Name
    if ((Test-AosVideoName $Name) -and (Test-Path -LiteralPath $folder -PathType Container)) {
        Write-AosText -Path (Join-Path $folder 'PREFLIGHT.md') -Text $report
    }
    if (-not $Verdicts) { return $report }
    $fmt = { param($e) '- ' + ([string]$e['ts']).Substring(0, 10) + ' ' + $e['video'] + ': "' + $e['text'] + '"' }
    $all = @($events | Where-Object { $_['type'] -eq 'video-verdict' -and $_['video'] })
    $mine = @($all | Where-Object { (Get-AosVideoFamily ([string]$_['video'])) -eq $family })
    $others = @($all | Where-Object { (Get-AosVideoFamily ([string]$_['video'])) -ne $family })
    if ($others.Count -gt 5) { $others = $others[($others.Count - 5)..($others.Count - 1)] }
    $audit = New-Object System.Text.StringBuilder
    [void]$audit.Append("$nl## Verdicts (audit only)$nl$nl")
    if (($mine.Count + $others.Count) -eq 0) { [void]$audit.Append("- none recorded$nl") }
    foreach ($e in @($mine + $others)) { [void]$audit.Append((& $fmt $e) + $nl) }
    return ($report + $audit.ToString())
}

function Invoke-AosVideo([string[]]$Arguments) {
    $a = @($Arguments | Where-Object { $null -ne $_ })
    $sub = $null
    if ($a.Count -gt 0) { $sub = $a[0] }
    $name = $null
    if ($a.Count -gt 1) { $name = $a[1] }
    switch ($sub) {
        'new' { New-AosVideo -Name $name }
        'verdict' {
            $text = ''
            if ($a.Count -gt 2) { $text = ($a[2..($a.Count - 1)] -join ' ') }
            Add-AosVideoVerdict -Name $name -Text $text
        }
        'log' {
            $stage = $null; $min = $null; $note = ''
            if ($a.Count -gt 2) { $stage = $a[2] }
            if ($a.Count -gt 3) { $min = $a[3] }
            if ($a.Count -gt 4) { $note = ($a[4..($a.Count - 1)] -join ' ') }
            Add-AosVideoStage -Name $name -Stage $stage -Minutes $min -Note $note
        }
        'preflight' {
            if (-not (Test-AosVideoName $name)) { Write-AosWarn 'usage: aos video preflight <name> [--verdicts]'; return }
            $audit = ($a.Count -gt 2) -and ($a[2] -eq '--verdicts')
            Write-AosVideoPreflight -Name $name -Verdicts:$audit
        }
        default { Write-AosWarn 'usage: aos video new|verdict|log|preflight <name> ...' }
    }
}

# Secrets: one DPAPI-encrypted file per key in ~\.aos\secrets. Only your Windows account on this
# machine can decrypt them (not Codex's sandbox users), and every app and terminal sees the same
# store: SecretStore kept its vault under %LOCALAPPDATA%, which a packaged app can make private.
# This protects against the real past failure (keys in plaintext files and backups), not against
# malware running as you.

function Get-AosSecretsDir {
    if ($env:AOS_SECRETS) { return $env:AOS_SECRETS }
    return (Join-Path $HOME '.aos\secrets')
}

function Test-AosSecretName([string]$Name) {
    # The name becomes a file name: no paths, and no Windows device names (CON, NUL, COM1, ...).
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$') { return $false }
    return ($Name.Split('.')[0] -notmatch '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$')
}

function Set-AosSecret([string]$Name, [System.Security.SecureString]$Value) {
    if (-not (Test-AosSecretName $Name)) { Write-AosWarn "not a valid secret name: '$Name' (letters, digits, _ . - ; up to 64)"; return $false }
    $dir = Get-AosSecretsDir
    $path = Join-Path $dir "$Name.secret"
    $tmp = "$path.$([guid]::NewGuid().ToString('N')).tmp"   # per write: two setters never share one
    try {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
        [System.IO.File]::WriteAllText($tmp, (ConvertFrom-SecureString -SecureString $Value))
        # Swap the new file in whole, so a failed write never leaves half a key behind.
        # [NullString]::Value: a plain $null reaches a .NET string parameter as "" (an invalid backup path).
        if (Test-Path -LiteralPath $path) { [System.IO.File]::Replace($tmp, $path, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $path) }
    }
    catch {
        if (Test-Path -LiteralPath $tmp) { [System.IO.File]::Delete($tmp) }
        Write-AosWarn "could not store ${Name}: $($_.Exception.Message)"
        return $false
    }
    return $true
}

function Get-AosSecret([string]$Name) {
    if (-not (Test-AosSecretName $Name)) { Write-AosWarn "not a valid secret name: '$Name'"; return $null }
    $path = Join-Path (Get-AosSecretsDir) "$Name.secret"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-AosWarn "no secret named $Name (aos secret set $Name)"; return $null }
    try { $secure = ConvertTo-SecureString ([System.IO.File]::ReadAllText($path).Trim()) -ErrorAction Stop }
    catch { Write-AosWarn "cannot decrypt ${Name}: it was stored by another Windows user or machine"; return $null }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-AosSecretNames {
    $dir = Get-AosSecretsDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return }
    Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -like '*.secret' } |
        ForEach-Object { $_.Name.Substring(0, $_.Name.Length - '.secret'.Length) } | Sort-Object
}

function Remove-AosSecret([string]$Name) {
    if (-not (Test-AosSecretName $Name)) { Write-AosWarn "not a valid secret name: '$Name'"; return $false }
    $path = Join-Path (Get-AosSecretsDir) "$Name.secret"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-AosWarn "no secret named $Name"; return $false }
    [System.IO.File]::Delete($path)
    return $true
}

function Invoke-AosSecret([string]$Action, [string]$Name) {
    if (@('set', 'get', 'list', 'remove') -notcontains $Action) { Write-AosWarn 'usage: aos secret set|get|list|remove <name>'; return }
    if ($Action -ne 'list' -and -not $Name) { Write-AosWarn "usage: aos secret $Action <name>"; return }
    switch ($Action) {
        'set' {
            if (-not (Test-AosSecretName $Name)) { Write-AosWarn "not a valid secret name: '$Name' (letters, digits, _ . - ; up to 64)"; return }
            $value = Read-Host "Value for '$Name' (input hidden)" -AsSecureString
            if ($value.Length -eq 0) { Write-AosWarn 'empty value; nothing stored'; return }
            if (Set-AosSecret -Name $Name -Value $value) { Write-AosOk "stored $Name in $(Get-AosSecretsDir)" }
        }
        'get'    { Get-AosSecret -Name $Name }
        'list'   { Get-AosSecretNames }
        'remove' { if (Remove-AosSecret -Name $Name) { Write-AosOk "removed $Name" } }
    }
}

function Invoke-AosClaudeRemote([string]$Dir) {
    Push-Location -LiteralPath $Dir -ErrorAction Stop   # never start Claude in the caller's folder instead
    try { claude remote-control --capacity 2 } finally { Pop-Location }
}

function Start-AosRemote([string]$Dir, [switch]$DryRun) {
    # Claude Code Remote Control as a server: the Claude mobile app (Code) can start and steer sessions
    # in this folder while the window stays open. Two at a time: same-folder sessions share files.
    if (-not (Test-AosCommand claude)) { Write-AosWarn 'claude missing (aos install engines)'; return }
    $projects = Get-AosProjectsDir
    if (-not $Dir) { $path = [Environment]::GetFolderPath('Desktop') }
    elseif (Test-Path -LiteralPath $Dir -PathType Container) { $path = (Resolve-Path -LiteralPath $Dir).ProviderPath }
    elseif (-not [System.IO.Path]::IsPathRooted($Dir) -and (Test-Path -LiteralPath (Join-Path $projects $Dir) -PathType Container)) { $path = Join-Path $projects $Dir }
    else { Write-AosWarn "no folder '$Dir' here or in $projects"; return }
    Write-AosStep "Remote Control in $path"
    Write-AosInfo 'On the phone: Claude app > Code. Leave this window open (Ctrl+C stops it); at most 2 sessions.'
    Write-AosInfo 'First time in this folder? Run claude here once and accept the workspace trust prompt.'
    if ($DryRun) { Write-AosDry "claude remote-control --capacity 2   (in $path)"; return }
    Invoke-AosClaudeRemote -Dir $path
}

#endregion
#region video assets ----------------------------------------------------------------------
# aos asset: the shared Node tool in agents-home/video/assets (rule R35). API keys reach the child only as
# environment variables (never arguments, files or logs); a missing key just makes its search source skip.

$script:AssetKeys = @('pexels', 'pixabay', 'freesound')

function Get-AosAssetEnv {
    $vars = @{}
    $have = @(Get-AosSecretNames)
    foreach ($k in $script:AssetKeys) {
        if ($have -contains $k) {
            $v = Get-AosSecret $k
            if ($v) { $vars['AOS_KEY_' + $k.ToUpperInvariant()] = $v }
        }
    }
    return $vars
}

function Invoke-AosAsset([string[]]$Arguments) {
    if (-not $Arguments -or $Arguments.Count -eq 0) { throw 'usage: aos asset <search|fetch|capture|proxy|registry|credits|budget> ...' }
    if ($Arguments[0] -eq 'budget' -and ($Arguments -contains '--approve') -and -not ($Arguments -contains '--by-user')) {
        throw 'aos asset budget --approve records the user''s approval: add --by-user only after the user approved the amount'
    }
    $tool = Join-Path $script:Root 'agents-home\video\assets\asset.mjs'
    # Invoke-AosProcess hands output back through files only; show both, then drop them.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('aos-asset-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $outFile = Join-Path $tmp 'out.txt'
        $errFile = Join-Path $tmp 'err.txt'
        $r = Invoke-AosProcess -Exe 'node' -Arguments (@('--no-warnings', $tool) + $Arguments) -WorkingDirectory (Get-Location).ProviderPath `
            -TimeoutSeconds 3600 -Environment (Get-AosAssetEnv) -StdoutFile $outFile -StderrFile $errFile
        foreach ($f in @($outFile, $errFile)) {
            if (Test-Path -LiteralPath $f) {
                $text = [System.IO.File]::ReadAllText($f)
                if ($text.Trim()) { Write-Host $text.TrimEnd() }
            }
        }
        $global:LASTEXITCODE = $r.Code
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

#endregion
#region the aos command ------------------------------------------------------------------

function Show-AosHelp {
    Write-Host @'
aos - agentic-os control

  aos status                 what is installed, linked, logged in and in sync
  aos install [layers]       base | engines | brain | bridges | refs | local | media | all   (add -DryRun to preview; media is opt-in, not in all)
  aos sync                   re-apply shared AGENTS.md, skills links, settings, Codex block, MCP
  aos update                 upgrade everything (winget, Claude Code, plugins, npm tools, refs), then sync
  aos usage                  local usage history for Claude Code and Codex
  aos test                   parse/ASCII checks + the Pester suite under PowerShell 5.1 and 7
  aos new <name>             new project in Desktop\1-Projects: AGENTS.md, CLAUDE.md (@AGENTS.md), .gitignore, git init
  aos video new <name>       new video project in Desktop\1-Projects\videos (video template + render app in ~\.aos\video)
  aos video verdict <name> <words>         record the user's verdict on a video, verbatim (coordination ledger)
  aos video log <name> <stage> <min> [note] record how long a stage took (brief|look|structure|production|qa|...)
  aos video preflight <name> [--verdicts]  rules + craft frontier + stage times -> PREFLIGHT.md (--verdicts: audit, output only)
  aos asset <search|fetch|capture|proxy|registry|credits|budget>   import real material into a film (rights ledger, budget)
  aos place ls [--json]      list shared places, including missing folders
  aos place add <folder> [--name <n>] [--kind repo|vault|folder]   add a place, then sync
  aos refs                   clone/pull the reference repos in refs/repos.json (into ~\.aos\refs)
  aos secret set|get|list|remove <name>    keys encrypted to your Windows login (~\.aos\secrets)
  aos remote [folder]        let the Claude phone app start sessions here (default: Desktop); keep it open
  aos local adopt <tag>      make a model the local default, only if the latest nar eval says it is no worse
  aos nar <args>             the nar CLI from its venv in ~\.aos (long options: --option, not -o)
  aos where                  path of this repo
  aos who [--json]           live checkout claims and the latest coordination events
  aos claim|release [<path>] --as <agent>   hold or free a checkout (edits claim automatically via hooks)
  aos note <text> --as <agent>              leave a message other agents see in aos who
  aos capacity [set <vendor> <pct> ...]    each vendor's known window left (R34); set what the app's usage card shows
  aos ready [<path>] [--json]   readiness gate before cross-vendor work: repo, claims, both vendors' capacity, actor slots, task paths, unpushed commits.
  aos delegate codex|claude --task <file> [--write [--verify <cmd>] [--allow <glob>]...] [--contract <json>]
                [--tier light|standard|deep] [--effort <e>] [--parent <lead-id>] [--workers 0|1] [--repo <path>]
                [--model <m>] [--needs <cmd>] [--setup <cmd>] [--timeout <min>] [--idle <min>] [--transport exec|app-server]
                             hand a task to the other vendor; receipt in ~\.aos\coord (ls [--last N] | show <id> | clean <id> [--force])
  aos coord <command>        reserve|observe|finish|actors|reconcile (actors), send|inbox|ack|wait (messages), status|cancel|steer (runs),
                             task|report|annotate|capabilities|roles|native|checkpoint|procedure|continuation (tuning);
                             a lead reserves itself first: aos coord reserve <id> --as <vendor> --task <t>  (docs/coordination-tuning.md)
'@
}

function aos {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Command = 'help',
        [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
        [switch]$DryRun
    )
    $a1 = $null; $a2 = $null
    if ($Rest) { $a1 = $Rest[0]; if ($Rest.Count -gt 1) { $a2 = $Rest[1] } }
    switch ($Command) {
        'status'  { Get-AosStatus }
        'install' { $l = @($Rest | Where-Object { $_ }); if ($l.Count -eq 0) { $l = @('all') }; Install-AosLayer -Layer $l -DryRun:$DryRun }
        'sync'    { Sync-AosBrain -DryRun:$DryRun }
        'update'  { Update-Aos -DryRun:$DryRun }
        'usage'   { Show-AosUsage }
        'test'    { Invoke-AosTest }
        'new'     { New-AosProject -Path $a1 }
        'video'   { Invoke-AosVideo -Arguments @($Rest) }
        'asset'   { Invoke-AosAsset -Arguments @($Rest) }
        'place'   { Invoke-AosPlace -Arguments @($Rest) -DryRun:$DryRun }
        'refs'    { Sync-AosRefs -DryRun:$DryRun }
        'secret'  { Invoke-AosSecret -Action $a1 -Name $a2 }
        'remote'  { Start-AosRemote -Dir $a1 -DryRun:$DryRun }
        'local'   { if ($a1 -eq 'adopt') { Invoke-AosLocalAdopt -Tag $a2 -DryRun:$DryRun } else { Write-AosWarn 'usage: aos local adopt <ollama tag>' } }
        'nar'     { Invoke-AosNar -Arguments @($Rest) }
        'claim'   { Invoke-AosCoordCommand -Command 'claim' -Arguments @($Rest) }
        'release' { Invoke-AosCoordCommand -Command 'release' -Arguments @($Rest) }
        'who'     { Invoke-AosCoordCommand -Command 'who' -Arguments @($Rest) }
        'note'    { Invoke-AosCoordCommand -Command 'note' -Arguments @($Rest) }
        'capacity' { Invoke-AosCapacity -Arguments @($Rest) }
        'ready' { Invoke-AosReady -Arguments @($Rest) }
        'coord' { Invoke-AosCoordControl -Arguments @($Rest) }
        'delegate' { Invoke-AosCoordCommand -Command 'delegate' -Arguments @($Rest) }
        'guard'   { Invoke-AosGuardHook -Agent $a1 -Event $a2 }
        'where'   { $script:Root }
        default   { Show-AosHelp }
    }
}

#endregion

Export-ModuleMember -Function aos, Install-AosLayer, Sync-AosBrain, Get-AosStatus, Update-Aos, New-AosProject, New-AosVideo

function Sync-AosPlaces([switch]$DryRun) {
    $places = @(Get-AosPlaces | Where-Object { $null -ne $_ })
    if ($places.Count -eq 0) { return }
    foreach ($place in $places) {
        if ($place.kind -eq 'inbox' -and -not (Test-Path -LiteralPath $place.path -PathType Container)) {
            if ($DryRun) { Write-AosDry "would create Inbox: $($place.path)" }
            else { New-Item -ItemType Directory -Path $place.path -Force | Out-Null }
        }
        $place.exists = Test-Path -LiteralPath $place.path -PathType Container
        if (-not $place.exists -and $place.kind -ne 'inbox') { Write-AosWarn "Place is missing; left absent: $($place.name)" }
    }
    $path = Join-Path (Get-AosStateDir) 'places.json'
    $r = Read-AosJsonOrWarn $path
    if (-not $r.Ok) { return }
    Set-AosJsonFile -Path $path -Old $r.Value -New ([ordered]@{ places = @($places) }) -Label 'shared Places registry' -DryRun:$DryRun
}

function Get-AosPlaceKind([string]$FullPath) {
    if (Test-Path -LiteralPath (Join-Path $FullPath '.git')) { return 'repo' }
    if (Test-Path -LiteralPath (Join-Path $FullPath '.obsidian')) { return 'vault' }
    return 'folder'
}

function ConvertTo-AosPlacePath([string]$FullPath) {
    # Longest root first ({{projects}} lives inside {{desktop}}); $null outside the home folder.
    $full = [System.IO.Path]::GetFullPath($FullPath).TrimEnd('\')
    foreach ($pair in @(@('{{projects}}', (Get-AosProjectsDir)), @('{{desktop}}', (Get-AosDesktopDir)), @('{{home}}', $HOME))) {
        $root = ([string]$pair[1]).TrimEnd('\')
        if ($full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $pair[0] + $full.Substring($root.Length) }
    }
    return $null
}

function Add-AosPlace([string]$Path, [string]$Name, [string]$Kind, [switch]$DryRun) {
    # Appends to config/places.json (the user commits it), then syncs. $true when added.
    if (-not $Path) { Write-AosWarn 'usage: aos place add <folder> [--name <n>] [--kind repo|vault|folder]'; return $false }
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { Write-AosWarn 'invalid folder path'; return $false }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { Write-AosWarn "no folder at $full"; return $false }
    if (-not $Kind) { $Kind = Get-AosPlaceKind $full }
    if (@('repo', 'vault', 'folder') -notcontains $Kind) { Write-AosWarn "kind must be repo, vault or folder (the inbox is set in config/places.json)"; return $false }
    if (-not $Name) { $Name = Split-Path -Leaf $full }
    $stored = ConvertTo-AosPlacePath $full
    if (-not $stored) { Write-AosWarn "$full is outside your home folder: not added (the repo holds no absolute paths)"; return $false }
    $cfgPath = Get-AosPlacesConfigPath
    $r = Read-AosJsonOrWarn $cfgPath
    if (-not $r.Ok) { return $false }
    $cfg = $r.Value
    if (-not $cfg) { $cfg = [ordered]@{ places = @() } }
    if ($cfg -isnot [Collections.IDictionary] -or ($cfg['places'] -is [string])) { Write-AosWarn 'invalid places configuration; left unchanged'; return $false }
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $cfg['places']) {
        if (-not ($p -is [System.Collections.IDictionary])) { Write-AosWarn 'invalid place entry; configuration left unchanged'; return $false }
        if ([string]$p['name'] -ieq $Name) { Write-AosWarn "a place named '$Name' already exists"; return $false }
        $resolved = Resolve-AosPlacePath ([string]$p['path'])
        if ($resolved -and $resolved.TrimEnd('\') -ieq $full.TrimEnd('\')) { Write-AosWarn "$full is already the place '$($p['name'])'"; return $false }
        $list.Add($p)
    }
    $list.Add([ordered]@{ name = $Name; kind = $Kind; path = $stored })
    $cfg['places'] = $list.ToArray()
    if ($DryRun) { Write-AosDry "would add place '$Name' ($Kind, $stored)"; return $true }
    if (Test-Path -LiteralPath $cfgPath) { $null = Backup-AosFile $cfgPath }
    Write-AosText -Path $cfgPath -Text ((ConvertTo-Json -InputObject $cfg -Depth 6) + "`n")
    Write-AosOk "added place '$Name' ($Kind, $stored) to config/places.json: commit it"
    Sync-AosPlaces
    return $true
}

function Show-AosPlaces([switch]$Json) {
    $places = Get-AosPlaces
    if ($null -eq $places) { Write-AosWarn 'no config/places.json'; return }
    if ($Json) { return (ConvertTo-Json -InputObject ([ordered]@{ places = @($places) }) -Depth 5) }
    foreach ($p in $places) {
        $line = '{0,-16} {1,-7} {2}' -f $p['name'], $p['kind'], $p['path']
        if ($p['exists']) { Write-AosOk $line } else { Write-AosWarn "$line  (missing)" }
    }
}

function Show-AosPlacesStatus {
    $places = Get-AosPlaces
    if ($null -eq $places) { Write-AosInfo 'no config/places.json'; return }
    foreach ($p in $places) {
        if (-not $p['exists']) { Write-AosWarn "$($p['name']) missing: $($p['path'])"; continue }
        Write-AosOk "$($p['name']) ($($p['kind']))"
    }
}

function Invoke-AosPlace([string[]]$Arguments, [switch]$DryRun) {
    $args2 = @($Arguments | Where-Object { $null -ne $_ })
    if ($args2.Count -eq 0) { Write-AosWarn 'usage: aos place ls [--json] | aos place add <folder> [--name <n>] [--kind <k>]'; return }
    $opts = @{}; $pos = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 1; $i -lt $args2.Count; $i++) {
        if ($args2[$i] -eq '--json') { $opts['json'] = $true }
        elseif ($args2[$i] -in @('--name', '--kind') -and $i + 1 -lt $args2.Count) { $opts[$args2[$i].Substring(2)] = $args2[$i + 1]; $i++ }
        elseif ($args2[$i].StartsWith('--')) { Write-AosWarn "unknown or incomplete Places option: $($args2[$i])"; return }
        else { $pos.Add($args2[$i]) }
    }
    if (($args2[0] -eq 'ls' -and ($pos.Count -gt 0 -or $opts.ContainsKey('name') -or $opts.ContainsKey('kind'))) -or
        ($args2[0] -eq 'add' -and ($pos.Count -ne 1 -or $opts.ContainsKey('json')))) { Write-AosWarn 'invalid Places arguments; use aos place ls or aos place add <folder>'; return }
    switch ($args2[0]) {
        'ls'  { Show-AosPlaces -Json:([bool]$opts['json']) }
        'add' { $null = Add-AosPlace -Path ($pos | Select-Object -First 1) -Name $opts['name'] -Kind $opts['kind'] -DryRun:$DryRun }
        default { Write-AosWarn "unknown: aos place $($args2[0])" }
    }
}

#region coordination ------------------------------------------------------------------------
# One writer per checkout (claims), an append-only ledger and delegation receipts: plain files in
# ~\.aos\coord, outside OneDrive. Plan: docs/superpowers/plans/2026-10-01-agent-coordination.md.

function Get-AosCoordDir {
    if ($env:AOS_COORD) { return $env:AOS_COORD }
    return (Join-Path (Get-AosStateDir) 'coord')
}

function Get-AosWorktreesDir {
    # Delegate worktrees. Under a redirected AOS_COORD (tests) they stay beside it, never in ~\.aos.
    if ($env:AOS_WORKTREES) { return $env:AOS_WORKTREES }
    if ($env:AOS_COORD) { return (Join-Path $env:AOS_COORD 'worktrees') }
    return (Join-Path (Get-AosStateDir) 'worktrees')
}

function Get-AosCodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $HOME '.codex')
}

function Get-AosUtcStamp { return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }

function ConvertTo-AosStamp($Value) {
    # PowerShell 7's ConvertFrom-Json turns ISO strings into DateTime; keep one textual UTC form.
    if ($Value -is [DateTime]) {
        $d = $Value
        if ($d.Kind -eq [System.DateTimeKind]::Unspecified) { $d = [DateTime]::SpecifyKind($d, [System.DateTimeKind]::Utc) }
        return $d.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    return [string]$Value
}

function ConvertFrom-AosUtcStamp([string]$Text) {
    $d = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $d }
    return $null
}

function Read-AosSharedText([string]$Path) {
    # Reads while another process may be appending (the ledger): share read AND write.
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs, $script:Utf8NoBom)
        return $sr.ReadToEnd()
    }
    finally { $fs.Dispose() }
}

function Invoke-AosCoordLocked([scriptblock]$Body, [int]$TimeoutMs = 5000) {
    # A lock FILE, not a named mutex: Local\ mutexes are per logon session, and scheduled
    # tasks and hooks can run elsewhere. The OS drops the lock when its process dies.
    # Re-entrant within one process (a claim writes ledger events while holding it).
    if ($script:AosCoordLockHeld) { return (& $Body) }
    $aosLockDir = Get-AosCoordDir
    if (-not (Test-Path -LiteralPath $aosLockDir)) { New-Item -ItemType Directory -Force -Path $aosLockDir | Out-Null }
    $aosLockPath = Join-Path $aosLockDir 'coord.lock'
    $aosLockDeadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $aosLockStream = $null
    while ($null -eq $aosLockStream) {
        try {
            $aosLockStream = New-Object System.IO.FileStream($aosLockPath, [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        }
        catch {
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            if (-not ($inner -is [System.IO.IOException])) { throw }
            if ([DateTime]::UtcNow -ge $aosLockDeadline) { throw "coordination lock busy: $aosLockPath" }
            Start-Sleep -Milliseconds 50
        }
    }
    $script:AosCoordLockHeld = $true
    try { return (& $Body) }
    finally {
        $script:AosCoordLockHeld = $false
        $aosLockStream.Dispose()
    }
}

function Add-AosLedgerEvent([System.Collections.IDictionary]$Event) {
    $e = [ordered]@{ ts = (Get-AosUtcStamp) }
    foreach ($k in @($Event.Keys)) { if ($k -ne 'ts') { $e[$k] = $Event[$k] } }
    $aosLedgerLine = (ConvertTo-Json -InputObject $e -Depth 10 -Compress) + "`n"
    $aosLedgerPath = Join-Path (Get-AosCoordDir) 'ledger.jsonl'
    $null = Invoke-AosCoordLocked { [System.IO.File]::AppendAllText($aosLedgerPath, $aosLedgerLine, $script:Utf8NoBom) }
}

function Get-AosLedger([int]$Last = 20) {
    $path = Join-Path (Get-AosCoordDir) 'ledger.jsonl'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($line in ((Read-AosSharedText $path) -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $e = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $line -ErrorAction Stop)
            if ($e -is [System.Collections.IDictionary] -and $e.Contains('ts')) { $e['ts'] = ConvertTo-AosStamp $e['ts'] }
            [void]$out.Add($e)
        }
        catch { }
    }
    if ($Last -gt 0 -and $out.Count -gt $Last) { return $out.GetRange($out.Count - $Last, $Last).ToArray() }
    return $out.ToArray()
}

#endregion
#region processes -------------------------------------------------------------------------

function ConvertTo-AosArgString([string[]]$Arguments) {
    # One Windows command line for native programs (CommandLineToArgvW / MSVCRT rules).
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Arguments)) {
        if ($null -eq $a) { $a = '' }
        if ($a.Length -gt 0 -and $a -notmatch '[\s"]') { $parts.Add($a); continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq [char]'\') { $bs++; continue }
            if ($ch -eq [char]'"') { [void]$sb.Append('\' * (2 * $bs + 1)); [void]$sb.Append('"'); $bs = 0; continue }
            if ($bs -gt 0) { [void]$sb.Append('\' * $bs); $bs = 0 }
            [void]$sb.Append($ch)
        }
        if ($bs -gt 0) { [void]$sb.Append('\' * (2 * $bs)) }
        [void]$sb.Append('"')
        $parts.Add($sb.ToString())
    }
    return ($parts -join ' ')
}

function Resolve-AosExe([string]$Exe) {
    $path = $Exe
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $cmd = Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { throw "not found: $Exe" }
        $path = $cmd.Source
    }
    if ($path -match '(?i)\.(cmd|bat)$') { throw "refusing to start a batch file (its argument quoting is unreliable): $path" }
    return $path
}

function Add-AosLiveOutput {
    param([string]$Path, [string]$Text, [DateTime]$Deadline)
    # A reader can briefly open the live log without write sharing on Windows. Retry only
    # open-time sharing violations, within a short bound and the process deadline. Do not
    # retry byte-range lock errors: a write could have partially succeeded before that error.
    $until = [DateTime]::UtcNow.AddSeconds(1)
    if ($Deadline -lt $until) { $until = $Deadline }
    while ($true) {
        try {
            [IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom)
            return
        }
        catch {
            $cause = $_.Exception.GetBaseException()
            $code = $cause.HResult -band 65535
            if ($cause -isnot [IO.IOException] -or $code -ne 32 -or [DateTime]::UtcNow -ge $until) { throw }
            $pause = [int][Math]::Max(1, [Math]::Min(10, ($until - [DateTime]::UtcNow).TotalMilliseconds))
            Start-Sleep -Milliseconds $pause
        }
    }
}

function Start-AosProcessCore {
    # Native exe, UTF-8 output captured to strings, optional UTF-8 stdin, a hard timeout that kills
    # the process tree and reports whether the kill worked. IdleSeconds > 0 also kills it when stdout stays
    # silent that long (Stalled): a delegate stuck on a dropped network must not hold its claim for the full timeout.
    param([string]$Exe, [string[]]$Arguments, [string]$ArgumentString, [string]$WorkingDirectory, [string]$StdinFile, [int]$TimeoutSeconds = 60,
        [hashtable]$Environment, [int]$IdleSeconds = 0, [string]$LiveRunId, [string]$StdoutFile, [scriptblock]$Watch)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Resolve-AosExe $Exe
    if ($PSBoundParameters.ContainsKey('ArgumentString')) { $psi.Arguments = $ArgumentString } else { $psi.Arguments = ConvertTo-AosArgString $Arguments }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    if ($Environment) { foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = [string]$Environment[$k] } }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8NoBom
    $psi.StandardErrorEncoding = $script:Utf8NoBom
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $liveWriter = $null
    $pending = ''
    $cancelled = $false
    $streaming = ($IdleSeconds -gt 0 -or [bool]$LiveRunId -or [bool]$Watch)
    try {
    if ($LiveRunId) {
        $identity=$p.StartTime.ToUniversalTime().ToString('o')
        $null=Set-AosActorState -Id $LiveRunId -State running -Text 'process started' -ProcessId $p.Id -ProcessStarted $identity
        $null=Set-AosRunState -Id $LiveRunId -State running -Text 'process started' -ProcessId $p.Id -ProcessStarted $identity
        if ($StdoutFile) {
            [IO.File]::WriteAllText($StdoutFile,'',$script:Utf8NoBom)
            $liveWriter=$StdoutFile
        }
    }
    $outTask = $null
    if (-not $streaming) { $outTask = $p.StandardOutput.ReadToEndAsync() }
    $errTask = $p.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
    $stdinStuck = $false
    $chunks = New-Object System.Text.StringBuilder
    $buffer = New-Object char[] 8192
    $read = $null
    $lastOutput = [DateTime]::UtcNow
    # With IdleSeconds, stdout is read in chunks (so the time of the last output is known) from before stdin is
    # written, and completed reads are pumped while the write waits: a child that writes before it reads must
    # not deadlock against us (Codex review 2). Dot-sourced, so it updates these variables.
    $pump = {
        while ($read -and $read.IsCompleted) {
            $n = $read.Result
            $read = $null
            if ($n -gt 0) {
                [void]$chunks.Append($buffer, 0, $n)
                $lastOutput = [DateTime]::UtcNow
                if ($LiveRunId) {
                    $chunk=New-Object string($buffer,0,$n)
                    if ($liveWriter) { Add-AosLiveOutput -Path $liveWriter -Text $chunk -Deadline $deadline }
                    $pending+=$chunk
                    while (($newline=$pending.IndexOf("`n")) -ge 0) {
                        $line=$pending.Substring(0,$newline).TrimEnd("`r")
                        $pending=$pending.Substring($newline+1)
                        try { Receive-AosCoordEvent -RunId $LiveRunId -JsonLine $line }
                        catch { $null=Set-AosRunState -Id $LiveRunId -State running -Text ('coordination request refused: ' + $_.Exception.Message) }
                    }
                }
                $read = $p.StandardOutput.ReadAsync($buffer, 0, $buffer.Length)
            }
        }
    }
    if ($streaming) { $read = $p.StandardOutput.ReadAsync($buffer, 0, $buffer.Length) }
    try {
        if ($StdinFile) {
            # Raw UTF-8 bytes (Windows PowerShell 5.1 cannot set the stdin encoding), written asynchronously
            # inside the deadline: a child that never reads stdin must not block us past the timeout.
            $bytes = [System.IO.File]::ReadAllBytes($StdinFile)
            $write = $p.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
            if ($streaming) {
                while (-not $write.IsCompleted -and [DateTime]::UtcNow -lt $deadline) { [void]$write.Wait(200); . $pump }
                if ($write.IsCompleted) { $write.Wait(); $p.StandardInput.BaseStream.Flush() } else { $stdinStuck = $true }
            }
            else {
                $left = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
                if ($write.Wait($left)) { $p.StandardInput.BaseStream.Flush() } else { $stdinStuck = $true }
            }
        }
    }
    catch { }
    if (-not $stdinStuck) { try { $p.StandardInput.Close() } catch { } }
    $timedOut = $false
    $killFailed = $false
    $stalled = $false
    $watched = ''
    $nextWatch = [DateTime]::UtcNow
    if ($streaming) {
        # The deadline is checked on every pass (steady output must not outlive it), and a closed stdout keeps the
        # idle clock running until the process exits (Codex review). A stuck stdin skips the loop; the drain below
        # keeps what was written before the kill.
        while (-not $stdinStuck) {
            if ($read) { [void]$read.Wait(200); . $pump }
            elseif (-not $p.HasExited) { Start-Sleep -Milliseconds 200 }
            if ($LiveRunId) {
                if (Test-Path -LiteralPath (Join-Path (Join-Path (Get-AosCoordDir) 'native-signals') ($LiveRunId+'.jsonl'))) { $null=Import-AosNativeSignals -RunId $LiveRunId }
                $liveState=Get-AosRunState $LiveRunId
                if ($liveState['cancel_requested']) { $cancelled=$true; break }
                if ($liveState['state'] -eq 'waiting-input') { $lastOutput=[DateTime]::UtcNow }
            }
            if ($Watch -and [DateTime]::UtcNow -ge $nextWatch) {
                $watched = [string](& $Watch $chunks.ToString())
                $nextWatch = [DateTime]::UtcNow.AddSeconds(5)
                if ($watched) { break }
            }
            if ($p.HasExited) { break }
            if ([DateTime]::UtcNow -ge $deadline) { break }
            if ($IdleSeconds -gt 0 -and ([DateTime]::UtcNow - $lastOutput).TotalSeconds -ge $IdleSeconds) { $stalled = $true; break }
        }
    }
    $remaining = [int][Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
    if ($stalled -or $cancelled -or $watched) { $remaining = 0 }
    if ($stdinStuck -or $watched -or -not $p.WaitForExit($remaining)) {
        $timedOut = -not $cancelled
        $null = cmd /c "taskkill /T /F /PID $($p.Id) 2>&1"
        if (-not $p.WaitForExit(10000)) { $killFailed = $true }
    }
    $out = ''
    $err = ''
    if (-not $killFailed) {
        $p.WaitForExit()
        if ($outTask) { if ($outTask.Wait(5000)) { $out = $outTask.Result } }
        else {
            # Drain what the finished or killed process left in the pipe.
            while ($read -and $read.Wait(5000)) { . $pump }
            $out = $chunks.ToString()
        }
        if ($errTask.Wait(5000)) { $err = $errTask.Result }
    }
    $code = -1
    if ($p.HasExited) { $code = $p.ExitCode }
    return [pscustomobject]@{ Code = $code; TimedOut = $timedOut; KillFailed = $killFailed; Stalled = $stalled; Cancelled = $cancelled; Out = $out; Err = $err; Watched = $watched }
    }
    catch {
        # A host metadata/stream failure must not abandon an untracked live process.
        if (-not $p.HasExited) { $null=cmd /c "taskkill /T /F /PID $($p.Id) 2>&1"; [void]$p.WaitForExit(10000) }
        if (-not $p.HasExited) {
            if ($LiveRunId) { $null=Set-AosActorState -Id $LiveRunId -State suspect -Text 'supervision failed; process not confirmed stopped' }
            $failure=New-Object Exception('supervision failed and process termination could not be confirmed')
            $failure.Data['AosKillFailed']=$true
            throw $failure
        }
        throw
    }
    finally { $p.Dispose() }
}

function Invoke-AosProcess {
    # The one place aos starts a delegate or a verify command; tests mock it.
    param([string]$Exe, [string[]]$Arguments, [string]$ArgumentString, [string]$WorkingDirectory, [string]$StdinFile,
        [string]$StdoutFile, [string]$StderrFile, [int]$TimeoutSeconds = 60, [hashtable]$Environment, [int]$IdleSeconds = 0, [string]$LiveRunId, [scriptblock]$Watch)
    $core = @{ Exe = $Exe; WorkingDirectory = $WorkingDirectory; StdinFile = $StdinFile; TimeoutSeconds = $TimeoutSeconds; Environment = $Environment; IdleSeconds = $IdleSeconds }
    if ($Watch) { $core['Watch'] = $Watch }
    if ($PSBoundParameters.ContainsKey('ArgumentString')) { $core['ArgumentString'] = $ArgumentString } else { $core['Arguments'] = $Arguments }
    if ($LiveRunId) { $core['LiveRunId']=$LiveRunId; $core['StdoutFile']=$StdoutFile }
    $r = Start-AosProcessCore @core
    if ($StdoutFile) { Write-AosText -Path $StdoutFile -Text $r.Out }
    if ($StderrFile) { Write-AosText -Path $StderrFile -Text $r.Err }
    return [pscustomobject]@{ Code = $r.Code; TimedOut = $r.TimedOut; KillFailed = $r.KillFailed; Stalled = $r.Stalled; Cancelled = $r.Cancelled; Watched = $r.Watched }
}

function Invoke-AosGit([string]$Dir, [string[]]$Arguments, [int]$TimeoutSeconds = 60) {
    # git with UTF-8 output (paths with accents) and no console code page in between.
    $r = Start-AosProcessCore -Exe 'git' -Arguments (@('-c', 'core.quotepath=false') + @($Arguments)) -WorkingDirectory $Dir -TimeoutSeconds $TimeoutSeconds
    return [pscustomobject]@{ Code = $r.Code; Out = $r.Out.TrimEnd(); Err = $r.Err.TrimEnd() }
}

function Invoke-AosGitWithIdentity([string]$Dir, [string[]]$Arguments, [int]$TimeoutSeconds = 60) {
    # Fill only missing identity fields for this command; never write git configuration.
    $identity = @()
    foreach ($field in @('name', 'email')) {
        $configured = Invoke-AosGit -Dir $Dir -Arguments @('config', "user.$field")
        if ($configured.Code -ne 0 -or [string]::IsNullOrWhiteSpace($configured.Out)) {
            $fallback = 'aos-delegate'
            if ($field -eq 'email') { $fallback = 'aos-delegate@localhost' }
            $identity += @('-c', "user.$field=$fallback")
        }
    }
    return (Invoke-AosGit -Dir $Dir -Arguments ($identity + @($Arguments)) -TimeoutSeconds $TimeoutSeconds)
}

#endregion
#region claims ----------------------------------------------------------------------------

function Get-AosCheckout([string]$Path) {
    # The git top level holding $Path (a file or folder, existing or about to be created); without git,
    # the nearest existing folder.
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = (Get-Location).ProviderPath }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $dir = $full
    while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path -Parent $dir }
    if (-not $dir) { return $full }
    $top = $null
    try {
        $g = Invoke-AosGit -Dir $dir -Arguments @('rev-parse', '--show-toplevel') -TimeoutSeconds 15
        if ($g.Code -eq 0 -and $g.Out) { $top = ($g.Out -split "`r?`n")[0].Trim().Replace('/', '\') }
    }
    catch { }
    if ($top) { return [System.IO.Path]::GetFullPath($top).TrimEnd('\') }
    return [System.IO.Path]::GetFullPath($dir).TrimEnd('\')
}

function Get-AosClaimKey([string]$Checkout) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($script:Utf8NoBom.GetBytes($Checkout.ToLowerInvariant())) } finally { $sha.Dispose() }
    return ((($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16))
}

function Get-AosClaimPath([string]$Checkout) {
    return (Join-Path (Join-Path (Get-AosCoordDir) 'claims') ((Get-AosClaimKey $Checkout) + '.json'))
}

function Read-AosClaimFile([string]$Path) {
    # $null when missing; throws when present but unreadable or not a claim.
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { throw "empty claim file $Path" }
    $c = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $text -ErrorAction Stop)
    if (-not ($c -is [System.Collections.IDictionary]) -or -not $c['agent'] -or -not $c['expires']) { throw "not a claim: $Path" }
    foreach ($k in @('since', 'renewed', 'expires')) { if ($c.Contains($k)) { $c[$k] = ConvertTo-AosStamp $c[$k] } }
    return $c
}

function Write-AosClaimFile([string]$Path, $Claim) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Claim -Depth 5), $script:Utf8NoBom)
    if (Test-Path -LiteralPath $Path) { [System.IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value) }
    else { [System.IO.File]::Move($tmp, $Path) }
}

function Test-AosClaimLive($Claim) {
    $e = ConvertFrom-AosUtcStamp ([string]$Claim['expires'])
    return ($null -ne $e -and $e -gt [DateTime]::UtcNow)
}

function Format-AosClaimHolder($Claim) {
    $note = [string]$Claim['note']
    if (-not $note) { $note = '(no note)' }
    return ('{0} is held by {1} ({2}) since {3}, until {4}: {5}.' -f $Claim['checkout'], $Claim['agent'], $Claim['session'], $Claim['since'], $Claim['expires'], $note)
}

function Test-AosAgentName([string]$Agent) { return ($Agent -cmatch '^[a-z][a-z0-9:_-]{0,40}$') }

function Invoke-AosClaim {
    param([string]$Path, [string]$Agent, [string]$Session, [string]$Note = '', [int]$TtlMinutes = 60, [switch]$KeepNote)
    $fail = { param($m) [pscustomobject]@{ Ok = $false; Action = 'refused'; Claim = $null; Holder = $null; Message = $m } }
    if (-not (Test-AosAgentName $Agent)) { return (& $fail "invalid agent name '$Agent' (lowercase letters, digits, : _ -)") }
    if ([string]::IsNullOrWhiteSpace($Session)) { return (& $fail 'a session id is required') }
    if ($TtlMinutes -lt 1 -or $TtlMinutes -gt 1440) { return (& $fail "TTL must be 1..1440 minutes, not $TtlMinutes") }
    $aosClaimCheckout = Get-AosCheckout $Path
    $aosClaimFile = Get-AosClaimPath $aosClaimCheckout
    $aosClaimArgs = @{ Agent = $Agent; Session = $Session; Note = $Note; Ttl = $TtlMinutes; KeepNote = [bool]$KeepNote }
    return (Invoke-AosCoordLocked {
        $now = [DateTime]::UtcNow
        $nowText = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $expires = $now.AddMinutes($aosClaimArgs.Ttl).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $old = $null
        $action = 'created'
        try { $old = Read-AosClaimFile $aosClaimFile }
        catch {
            $age = $now - (Get-Item -LiteralPath $aosClaimFile).LastWriteTimeUtc
            if ($age.TotalHours -lt 24) {
                return [pscustomobject]@{ Ok = $false; Action = 'refused'; Claim = $null; Holder = $null
                    Message = "unreadable claim file $aosClaimFile ($($_.Exception.Message)); check it, then delete it if no session owns it" }
            }
            Add-AosLedgerEvent ([ordered]@{ type = 'claim-takeover'; checkout = $aosClaimCheckout; agent = $aosClaimArgs.Agent; session = $aosClaimArgs.Session; previous = 'unreadable claim file older than 24 h' })
            $action = 'taken-over'
        }
        $since = $nowText
        if ($null -ne $old) {
            if ($old['agent'] -eq $aosClaimArgs.Agent -and $old['session'] -eq $aosClaimArgs.Session) {
                $action = 'renewed'
                if ($old['since']) { $since = [string]$old['since'] }
            }
            elseif (Test-AosClaimLive $old) {
                Add-AosLedgerEvent ([ordered]@{ type = 'claim-refused'; checkout = $aosClaimCheckout; agent = $aosClaimArgs.Agent; session = $aosClaimArgs.Session; holder = $old['agent']; holder_session = $old['session'] })
                return [pscustomobject]@{ Ok = $false; Action = 'refused'; Claim = $null; Holder = $old; Message = (Format-AosClaimHolder $old) }
            }
            else {
                Add-AosLedgerEvent ([ordered]@{ type = 'claim-takeover'; checkout = $aosClaimCheckout; agent = $aosClaimArgs.Agent; session = $aosClaimArgs.Session; previous = ('{0} ({1}) expired {2}' -f $old['agent'], $old['session'], $old['expires']) })
                $action = 'taken-over'
            }
        }
        $note = $aosClaimArgs.Note
        if ($action -eq 'renewed' -and ($aosClaimArgs.KeepNote -or -not $note)) { $note = [string]$old['note'] }
        $previous = $null
        if ($action -eq 'taken-over') { $previous = $old }
        $claim = [ordered]@{ checkout = $aosClaimCheckout; agent = $aosClaimArgs.Agent; session = $aosClaimArgs.Session; note = $note
            since = $since; renewed = $nowText; expires = $expires; host_pid = $PID }
        Write-AosClaimFile $aosClaimFile $claim
        if ($action -ne 'renewed') {
            Add-AosLedgerEvent ([ordered]@{ type = 'claim'; action = $action; checkout = $aosClaimCheckout; agent = $aosClaimArgs.Agent; session = $aosClaimArgs.Session; note = $note })
        }
        return [pscustomobject]@{ Ok = $true; Action = $action; Claim = $claim; Holder = $previous; Message = '' }
    })
}

function Invoke-AosRelease([string]$Path, [string]$Agent, [string]$Session) {
    $aosRelCheckout = Get-AosCheckout $Path
    # A finished worktree can already be gone. Never resolve its identity to the nearest parent.
    if ($Path -and -not (Test-Path -LiteralPath $Path)) { $aosRelCheckout=[IO.Path]::GetFullPath($Path).TrimEnd('\') }
    $aosRelFile = Get-AosClaimPath $aosRelCheckout
    $aosRelArgs = @{ Agent = $Agent; Session = $Session }
    return (Invoke-AosCoordLocked {
        $old = $null
        try { $old = Read-AosClaimFile $aosRelFile } catch { }
        if ($null -eq $old) { return [pscustomobject]@{ Ok = $false; Holder = $null; Message = "no readable claim on $aosRelCheckout" } }
        if ($old['agent'] -ne $aosRelArgs.Agent -or $old['session'] -ne $aosRelArgs.Session) {
            return [pscustomobject]@{ Ok = $false; Holder = $old; Message = (Format-AosClaimHolder $old) }
        }
        Remove-Item -LiteralPath $aosRelFile -Force
        Add-AosLedgerEvent ([ordered]@{ type = 'release'; checkout = $aosRelCheckout; agent = $aosRelArgs.Agent; session = $aosRelArgs.Session })
        return [pscustomobject]@{ Ok = $true; Holder = $null; Message = '' }
    })
}

function Get-AosClaims {
    $dir = Join-Path (Get-AosCoordDir) 'claims'
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $c = Read-AosClaimFile $f.FullName } catch { continue }
        if ($null -ne $c -and (Test-AosClaimLive $c)) { [void]$out.Add($c) }
    }
    return $out.ToArray()
}

#endregion
#region guard -----------------------------------------------------------------------------

function Get-AosHookStrings($Value) {
    # Every string inside a hook's tool_input (apply_patch passes the patch as a string or object).
    $out = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return $out }
    if ($Value -is [string]) { $out.Add($Value); return $out }
    if ($Value -is [System.Collections.IDictionary]) { foreach ($k in @($Value.Keys)) { foreach ($s in (Get-AosHookStrings $Value[$k])) { $out.Add($s) } }; return $out }
    if (($Value -is [System.Collections.IEnumerable])) { foreach ($x in $Value) { foreach ($s in (Get-AosHookStrings $x)) { $out.Add($s) } } }
    return $out
}

function Get-AosGuardPaths($HookInput) {
    $cwd = [string]$HookInput['cwd']
    $ti = $HookInput['tool_input']
    $paths = New-Object System.Collections.Generic.List[string]
    if ($ti -is [System.Collections.IDictionary]) {
        foreach ($k in @('file_path', 'notebook_path', 'path')) { if ($ti[$k] -is [string] -and $ti[$k]) { $paths.Add($ti[$k]) } }
    }
    foreach ($s in (Get-AosHookStrings $ti)) {
        foreach ($m in [regex]::Matches($s, '(?m)^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+?)\s*$')) { $paths.Add($m.Groups[1].Value) }
    }
    $full = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        if ([System.IO.Path]::IsPathRooted($p)) { $full.Add($p) }
        elseif ($cwd) { $full.Add((Join-Path $cwd $p)) }
    }
    if ($full.Count -eq 0 -and $cwd) { $full.Add($cwd) }
    return $full
}

function Invoke-AosGuard([string]$Agent, [string]$Event, [string]$InputJson) {
    # Hook entry point for both vendors. Fails OPEN: a broken guard must never block every edit.
    $res = [ordered]@{ Exit = 0; Stdout = ''; Stderr = '' }
    try {
        $in = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $InputJson -ErrorAction Stop)
        if (-not ($in -is [System.Collections.IDictionary])) { throw 'hook input is not a JSON object' }
        $session = [string]$in['session_id']
        # A delegate started by `aos delegate` edits under the claim its wrapper took: same session name.
        if ($env:AOS_DELEGATE_ID) { $session = $env:AOS_DELEGATE_ID }
        if (-not $session) { throw 'no session_id in hook input' }
        $cwd = [string]$in['cwd']
        switch ($Event) {
            'pre-edit' {
                $done = @{}
                foreach ($p in (Get-AosGuardPaths $in)) {
                    $co = Get-AosCheckout $p
                    if ($done.ContainsKey($co.ToLowerInvariant())) { continue }
                    $done[$co.ToLowerInvariant()] = $true
                    $r = Invoke-AosClaim -Path $co -Agent $Agent -Session $session -TtlMinutes 60 -Note 'auto (first edit)' -KeepNote
                    if (-not $r.Ok) {
                        if ($null -eq $r.Holder) { throw $r.Message }
                        $res.Exit = 2
                        $res.Stderr = 'aos: ' + (Format-AosClaimHolder $r.Holder) + ' Do not edit here; coordinate (aos who) or use a worktree.'
                        break
                    }
                }
            }
            'session-start' {
                if ($cwd) {
                    $co = Get-AosCheckout $cwd
                    foreach ($c in (Get-AosClaims)) {
                        if ($c['checkout'] -ne $co) { continue }
                        if ($c['agent'] -eq $Agent -and $c['session'] -eq $session) { continue }
                        $res.Stdout = 'Note: aos: ' + (Format-AosClaimHolder $c) + ' Do not edit here; coordinate (aos who) or use a worktree.'
                    }
                }
            }
            'session-end' {
                foreach ($c in (Get-AosClaims)) {
                    if ($c['agent'] -eq $Agent -and $c['session'] -eq $session) { $null = Invoke-AosRelease -Path $c['checkout'] -Agent $Agent -Session $session }
                }
            }
            default { throw "unknown guard event '$Event'" }
        }
    }
    catch {
        $res.Exit = 0
        $res.Stderr = "aos guard: $($_.Exception.Message) (edit allowed)"
        try { Add-AosLedgerEvent ([ordered]@{ type = 'guard-error'; agent = $Agent; event = $Event; message = $_.Exception.Message }) } catch { }
    }
    return [pscustomobject]$res
}

function Invoke-AosGuardHook([string]$Agent, [string]$Event) {
    # `aos guard <agent> <event>` from a hook: JSON on stdin, then exit with the guard's code.
    $text = [Console]::In.ReadToEnd()
    $r = Invoke-AosGuard -Agent $Agent -Event $Event -InputJson $text
    if ($r.Stdout) { [Console]::Out.WriteLine($r.Stdout) }
    if ($r.Stderr) { [Console]::Error.WriteLine($r.Stderr) }
    exit $r.Exit
}

#endregion
#region hooks sync ------------------------------------------------------------------------

function Expand-AosHookTree($Value) {
    # {{aos}} -> the full path of this module, {{root}} -> this repo, in every string of a hook overlay.
    $module = Join-Path $script:Root 'aos.psm1'
    if ($Value -is [string]) { return $Value.Replace('{{aos}}', $module).Replace('{{root}}', $script:Root) }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in @($Value.Keys)) { $Value[$k] = Expand-AosHookTree $Value[$k] }
        return $Value
    }
    if (($Value -is [System.Collections.IEnumerable])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($x in $Value) { [void]$list.Add((Expand-AosHookTree $x)) }
        return , ($list.ToArray())
    }
    return $Value
}

function Test-AosOwnedHook($Hook) {
    if (-not ($Hook -is [System.Collections.IDictionary])) { return $false }
    foreach ($k in @('command', 'commandWindows', 'command_windows')) { if ([string]$Hook[$k] -match 'aos guard|aos-notes\.mjs|coordination-hook\.mjs') { return $true } }
    return $false
}

function Merge-AosOwnedHooks($Target, $Overlay) {
    # $Target/$Overlay: { <Event>: [ { matcher?, hooks: [ {type, command, ...} ] } ] }. Our entries
    # (recognised by 'aos guard') are removed everywhere, then the overlay's are added once; the user's
    # own hooks are never touched.
    foreach ($ev in @($Target.Keys)) {
        $groups = New-Object System.Collections.ArrayList
        foreach ($g in @($Target[$ev])) {
            if (-not ($g -is [System.Collections.IDictionary])) { [void]$groups.Add($g); continue }
            $kept = @(@($g['hooks']) | Where-Object { -not (Test-AosOwnedHook $_) })
            if ($kept.Count -eq 0 -and @($g['hooks']).Count -gt 0) { continue }
            $g['hooks'] = $kept
            [void]$groups.Add($g)
        }
        if ($groups.Count -eq 0) { $Target.Remove($ev) } else { $Target[$ev] = $groups.ToArray() }
    }
    foreach ($ev in @($Overlay.Keys)) {
        $list = New-Object System.Collections.ArrayList
        if ($Target.Contains($ev)) { foreach ($g in @($Target[$ev])) { [void]$list.Add($g) } }
        foreach ($g in @($Overlay[$ev])) { [void]$list.Add((Copy-AosTree $g)) }
        $Target[$ev] = $list.ToArray()
    }
}

function Get-AosCodexHooksPath { return (Join-Path (Get-AosCodexHome) 'hooks.json') }

function Sync-AosCodexHooks([switch]$DryRun, [string]$Path) {
    $target = $Path
    if (-not $target) { $target = Get-AosCodexHooksPath }
    $overlay = Read-AosJson (Join-Path $script:Root 'config\codex\hooks.json')
    if ($null -eq $overlay -or -not $overlay.Contains('hooks')) { Write-AosWarn 'config/codex/hooks.json missing or empty'; return }
    $read = Read-AosJsonOrWarn $target
    if (-not $read.Ok) { return }
    $old = $read.Value
    $new = Copy-AosTree $old
    if (-not $new.Contains('hooks') -or -not ($new['hooks'] -is [System.Collections.IDictionary])) { $new['hooks'] = [ordered]@{} }
    Merge-AosOwnedHooks $new['hooks'] (Expand-AosHookTree (Copy-AosTree $overlay['hooks']))
    $a = ''
    if ($null -ne $old) { $a = ConvertTo-Json -InputObject $old -Depth 20 -Compress }
    $b = ConvertTo-Json -InputObject $new -Depth 20 -Compress
    if ($a -ceq $b) { Write-AosOk "$target has the aos hooks"; return }
    if ($DryRun) { Write-AosDry "would merge the aos hooks into $target"; return }
    if (Test-Path -LiteralPath $target) { $null = Backup-AosFile $target }
    Write-AosText -Path $target -Text ((ConvertTo-Json -InputObject $new -Depth 20) + "`n")
    Write-AosOk "merged the aos hooks into $target"
    Write-AosWarn 'Codex hooks changed: trust them once in Codex (/hooks)'
}

function Repair-AosCcHooks([switch]$DryRun, [string]$PluginsRoot) {
    # cc-plugin-codex writes "$PLUGIN_ROOT" in its hook commands. Codex runs Windows hooks in
    # PowerShell, where that is an empty variable, and substitutes only ${PLUGIN_ROOT} itself.
    $root = $PluginsRoot
    if (-not $root) { $root = Join-Path (Get-AosCodexHome) 'plugins\cache' }
    $files = @()
    if (Test-Path -LiteralPath $root) {
        foreach ($m in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $cc = Join-Path $m.FullName 'cc'
            if (-not (Test-Path -LiteralPath $cc)) { continue }
            foreach ($v in @(Get-ChildItem -LiteralPath $cc -Directory -ErrorAction SilentlyContinue)) {
                $h = Join-Path $v.FullName 'hooks\hooks.json'
                if (Test-Path -LiteralPath $h) { $files += $h }
            }
        }
    }
    if ($files.Count -eq 0) { Write-AosOk 'no cc plugin hooks to repair'; return }
    foreach ($f in $files) {
        $text = [System.IO.File]::ReadAllText($f)
        # Only inside command/commandWindows values; other fields (notes, docs) keep their text.
        $fix = [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $m.Groups[1].Value + [regex]::Replace($m.Groups[2].Value, '(?<!\{)\$PLUGIN_ROOT(?![A-Za-z0-9_}])', '$${PLUGIN_ROOT}') + '"'
        }
        $new = [regex]::Replace($text, '("(?:command|commandWindows|command_windows)"\s*:\s*")((?:[^"\\]|\\.)*)"', $fix)
        if ($new -ceq $text) { Write-AosOk "cc hooks use `${PLUGIN_ROOT} ($f)"; continue }
        try { $null = ConvertFrom-Json -InputObject $new -ErrorAction Stop }
        catch { Write-AosWarn "repairing $f would break its JSON; left alone"; continue }
        if ($DryRun) { Write-AosDry "would change `$PLUGIN_ROOT to `${PLUGIN_ROOT} in $f"; continue }
        $null = Backup-AosFile $f
        Write-AosText -Path $f -Text $new
        Write-AosOk "repaired $f (`${PLUGIN_ROOT})"
        Write-AosWarn 'cc hooks changed: trust them once in Codex (/hooks)'
    }
}

#endregion
#region delegate --------------------------------------------------------------------------

function Get-AosCodexModelCandidates {
    $d = Read-AosJson (Join-Path (Get-AosCodexHome) 'models_cache.json')
    if ($null -eq $d) { return @() }
    $list = $d
    if ($d -is [System.Collections.IDictionary]) { $list = $d['models'] }
    $rows = @(@($list) | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['slug'] -and $_['visibility'] -eq 'list' })
    return @($rows | Sort-Object { [int]$_['priority'] } | ForEach-Object { [string]$_['slug'] })
}

function Get-AosErrorCategory([string]$Message) {
    if ($Message -match '(?i)not supported') { return 'not-supported' }
    if ($Message -match '(?i)usage limit|rate limit|\b429\b|quota') { return 'quota' }
    if ($Message -match '(?i)\b401\b|unauthori[sz]ed|log ?in|not logged|authentication') { return 'auth' }
    return 'other'
}

function Read-AosCodexEvents([string]$Path) {
    # Facts from `codex exec --json` output. Errors come ONLY from error/turn.failed events.
    $f = [ordered]@{ ThreadId = ''; Input = 0; Cached = 0; Output = 0; UsageObserved = $false; Completed = $false; Messages = @(); Errors = @() }
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]$f }
    $msgs = New-Object System.Collections.Generic.List[string]
    $errs = New-Object System.Collections.Generic.List[string]
    foreach ($line in ([System.IO.File]::ReadAllText($Path) -split "`r?`n")) {
        if (-not $line.StartsWith('{')) { continue }
        $e = $null
        try { $e = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $line -ErrorAction Stop) } catch { continue }
        switch ([string]$e['type']) {
            'thread.started' { $f.ThreadId = [string]$e['thread_id'] }
            'turn.completed' {
                $f.Completed = $true
                $u = $e['usage']
                if ($u -is [System.Collections.IDictionary]) {
                    $f.UsageObserved=($null -ne $u['input_tokens'] -and $null -ne $u['output_tokens'] -and $null -ne $u['cached_input_tokens'])
                    $f.Input += [long]$u['input_tokens']; $f.Cached += [long]$u['cached_input_tokens']; $f.Output += [long]$u['output_tokens']
                }
            }
            'item.completed' {
                $it = $e['item']
                if ($it -is [System.Collections.IDictionary] -and $it['type'] -eq 'agent_message') { $msgs.Add([string]$it['text']) }
            }
            'error' { $errs.Add([string]$e['message']) }
            'turn.failed' {
                $m = $e['error']
                if ($m -is [System.Collections.IDictionary]) { $m = $m['message'] }
                $errs.Add([string]$m)
            }
        }
    }
    $f.Messages = $msgs.ToArray()
    $f.Errors = $errs.ToArray()
    return [pscustomobject]$f
}

function Clear-AosDelegateModelCache([string]$Vendor) {
    $path = Join-Path (Get-AosCoordDir) 'models.json'
    $c = Read-AosJson $path
    if ($null -eq $c -or -not $c.Contains($Vendor)) { return }
    $c.Remove($Vendor)
    Write-AosText -Path $path -Text ((ConvertTo-Json -InputObject $c -Depth 5) + "`n")
}

function Test-AosCodexModelProbe([string]$Model) {
    $dir = Get-AosCoordDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $id = [guid]::NewGuid().ToString('N')
    $stdin = Join-Path $dir "probe-$id.txt"
    $stdout = Join-Path $dir "probe-$id.jsonl"
    Write-AosText -Path $stdin -Text 'Reply with exactly: PONG'
    try {
        $r = Invoke-AosProcess -Exe 'codex.exe' -Arguments @('exec', '-m', $Model, '--profile', 'review', '--json', '--skip-git-repo-check', '-') `
            -WorkingDirectory $dir -StdinFile $stdin -StdoutFile $stdout -TimeoutSeconds 120
        $ev = Read-AosCodexEvents $stdout
    }
    finally { Remove-Item -LiteralPath $stdin, $stdout -Force -ErrorAction SilentlyContinue }
    $category = 'ok'
    $message = ''
    if ($ev.Errors.Count -gt 0) { $message = $ev.Errors[0]; $category = Get-AosErrorCategory $message }
    elseif ($r.TimedOut) { $category = 'other'; $message = 'probe timed out' }
    elseif (-not $ev.Completed -or -not (@($ev.Messages) -match 'PONG')) { $category = 'other'; $message = "probe gave no PONG (exit $($r.Code))" }
    Add-AosLedgerEvent ([ordered]@{ type = 'model-probe'; vendor = 'codex'; model = $Model; category = $category; input = $ev.Input; message = $message })
    return [pscustomobject]@{ Ok = ($category -eq 'ok'); Category = $category; Message = $message }
}

function Resolve-AosDelegateModel([string]$Vendor, [string]$Model) {
    if ($Vendor -eq 'claude') { return [pscustomobject]@{ Ok = $true; Model = $Model; Category = 'ok'; Reason = '' } }
    $cachePath = Join-Path (Get-AosCoordDir) 'models.json'
    $cache = Read-AosJson $cachePath
    $cached = $null
    if ($null -ne $cache -and $cache[$Vendor] -is [System.Collections.IDictionary]) {
        $when = ConvertFrom-AosUtcStamp ([string]$cache[$Vendor]['checked'])
        if ($null -ne $when -and ([DateTime]::UtcNow - $when).TotalHours -lt 24) { $cached = [string]$cache[$Vendor]['model'] }
    }
    $candidates = @()
    if ($Model) {
        if ($cached -eq $Model) { return [pscustomobject]@{ Ok = $true; Model = $Model; Category = 'ok'; Reason = '' } }
        $candidates = @($Model)
    }
    elseif ($cached) { return [pscustomobject]@{ Ok = $true; Model = $cached; Category = 'ok'; Reason = '' } }
    else { $candidates = @(Get-AosCodexModelCandidates | Select-Object -First 2) }
    if ($candidates.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Model = ''; Category = 'other'; Reason = 'no Codex model candidates (models_cache.json missing?); pass --model' } }
    $last = $null
    foreach ($m in $candidates) {
        $p = Test-AosCodexModelProbe $m
        if ($p.Ok) {
            $c = $cache
            if ($null -eq $c) { $c = [ordered]@{} }
            $c[$Vendor] = [ordered]@{ model = $m; checked = (Get-AosUtcStamp) }
            Write-AosText -Path $cachePath -Text ((ConvertTo-Json -InputObject $c -Depth 5) + "`n")
            return [pscustomobject]@{ Ok = $true; Model = $m; Category = 'ok'; Reason = '' }
        }
        $last = $p
        if ($p.Category -ne 'not-supported') { break }
    }
    return [pscustomobject]@{ Ok = $false; Model = ''; Category = $last.Category; Reason = "codex model check failed ($($last.Category)): $($last.Message)" }
}

function Get-AosCommandExe([string]$CommandLine) {
    $t = $CommandLine.Trim()
    if ($t.StartsWith('"')) { $end = $t.IndexOf('"', 1); if ($end -gt 0) { return $t.Substring(1, $end - 1) } }
    return ($t -split '\s+')[0]
}

function Test-AosDelegatePreflight([string]$Vendor, [string]$Model, [string[]]$Needs, [string]$Verify, [string]$WorkDir, [switch]$Write) {
    $reasons = New-Object System.Collections.Generic.List[string]
    $exe = 'codex'
    if ($Vendor -eq 'claude') { $exe = 'claude' }
    if (-not (Test-AosCommand $exe)) { $reasons.Add("$exe is not installed") }
    # Not $model: PowerShell names are case-insensitive, and that would overwrite the -Model parameter.
    $resolvedModel = ''
    if ($reasons.Count -eq 0) {
        $m = Resolve-AosDelegateModel -Vendor $Vendor -Model $Model
        if ($m.Ok) { $resolvedModel = $m.Model } else { $reasons.Add($m.Reason) }
    }
    if ($reasons.Count -eq 0) {
        $sandbox = @('sandbox')
        if ($Write) { $sandbox += @('-c', 'sandbox_mode="workspace-write"') }
        if ($Verify) {
            $vexe = Get-AosCommandExe $Verify
            if ($Vendor -eq 'codex') {
                $r = Invoke-AosProcess -Exe 'codex.exe' -Arguments ($sandbox + @('where.exe', $vexe)) -WorkingDirectory $WorkDir -TimeoutSeconds 60
                if ($r.Code -ne 0) { $reasons.Add("verify needs '$vexe', which the delegate's sandbox cannot find") }
            }
            elseif (-not (Test-AosCommand $vexe)) { $reasons.Add("verify needs '$vexe', which is not installed") }
        }
        foreach ($n in @($Needs | Where-Object { $_ })) {
            $log = Join-Path (Get-AosCoordDir) ('needs-' + [guid]::NewGuid().ToString('N') + '.log')
            if ($Vendor -eq 'codex') {
                $r = Invoke-AosProcess -Exe 'codex.exe' -Arguments ($sandbox + @('cmd.exe', '/d', '/s', '/c', $n)) -WorkingDirectory $WorkDir -StdoutFile $log -TimeoutSeconds 600
            }
            else {
                $r = Invoke-AosProcess -Exe 'cmd.exe' -ArgumentString ('/d /s /c "' + $n + '"') -WorkingDirectory $WorkDir -StdoutFile $log -TimeoutSeconds 600
            }
            if ($r.Code -ne 0) {
                $tail = ''
                if (Test-Path -LiteralPath $log) { $tail = (@([System.IO.File]::ReadAllLines($log) | Where-Object { $_.Trim() }) | Select-Object -Last 1) }
                $reasons.Add("needs failed: $n (exit $($r.Code)): $tail")
            }
            Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]@{ Ok = ($reasons.Count -eq 0); Model = $resolvedModel; Reasons = $reasons.ToArray() }
}

function Get-AosDelegateSlug([string]$Text) {
    $first = (($Text -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $first) { $first = 'task' }
    $s = ([regex]::Replace($first.ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
    if ($s.Length -gt 30) { $s = $s.Substring(0, 30).Trim('-') }
    if (-not $s) { $s = 'task' }
    return $s
}

function Get-AosPorcelainPaths([string]$Text) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Length -lt 4) { continue }
        $p = $line.Substring(3)
        $arrow = $p.IndexOf(' -> ')
        if ($arrow -ge 0) { $p = $p.Substring($arrow + 4) }
        $p = $p.Trim().Trim('"')
        if ($p) { $out.Add($p.Replace('\', '/')) }
    }
    return $out.ToArray()
}

function Test-AosAllowed([string]$RelPath, [string[]]$Allow) {
    foreach ($g in @($Allow | Where-Object { $_ })) {
        if ($RelPath -like ($g.Replace('\', '/').Replace('**', '*'))) { return $true }
    }
    return $false
}

function Get-AosDelegatePrompt([string]$TaskText, [string]$WorkDir, [string]$Branch, [switch]$Write,
    [string]$RunId, [string]$Parent, [int]$Workers=0) {
    $lines = @('', '---', "Working directory: $WorkDir")
    if ($Write) {
        $lines += "Branch: $Branch"
        $lines += 'Edit files only. Do not run git add or git commit: the host commits your changes after you finish.'
    }
    else { $lines += 'Read-only task: do not modify any file.' }
    $lines += 'Your final answer must match the given JSON schema. List every test or check you could not run under "unverified".'
    $lines += 'Never report a test as passed unless you ran it and saw it pass.'
    if ($RunId) {
        $helper=Join-Path $script:Root 'tools\coord.ps1'
        $lines += "Your actor/run id is $RunId; parent actor is '$Parent'. Native-worker allowance: $Workers. No recursive CLI delegation."
        if ($Workers) { $lines += "The reserved native actor is ${RunId}-native-1. Use native harness tools, record actual handle and completion evidence; registration alone is not proof." }
        $lines += 'Use one writer per checkout. Hand exclusive writing to one native child while you remain read-only, or collect its scoped patch after it stops. Integrate into the assigned directory before returning.'
        $lines += "Live coordination helper: powershell -NoProfile -ExecutionPolicy Bypass -File `"$helper`" <command>. Host-scoped metadata travels through tool stdout; project read-only restrictions remain."
        $lines += "Commands: question --to <parent-id> --text <question>; send --to <actor-id> --text <progress>; inbox; ack --ack <message-id>; status --state running|waiting-input --text <progress>."
        $lines += 'Emit a question in a separate completed tool call BEFORE waiting; then wait --seconds 30 in another call. Read replies from your inbox, acknowledge explicitly, and mark status running after a reply. Never put the marker in ordinary prose.'
        $lines += 'If no reply arrives after a bounded wait, return blocked with the exact missing input. Do not invent it. Waiting suspends idle detection but not the hard task deadline.'
    }
    return ($TaskText.TrimEnd() + "`n" + ($lines -join "`n") + "`n")
}

# Vendor capacity (R34): each vendor's last known 5-hour window, written to the coordination ledger by the user
# (`aos capacity set`), by an agent, or by a quota error in a delegate receipt, so both vendors plan from the same
# facts before handing each other work.
$script:CapacityVendors = @('claude', 'codex')
$script:CapacityLowPercent = 30
$script:CapacityStaleHours = 5

function ConvertFrom-AosQuotaReset([string]$Message, [datetime]$Now) {
    # "try again at 6:25 PM" (today, or tomorrow if already past) or "try again at Oct 4th, 2026 1:21 AM"; local time.
    if ($Message -notmatch '(?i)try again at\s+(?:(?<date>[A-Za-z]{3,9} \d{1,2}(?:st|nd|rd|th)?, \d{4})\s+)?(?<time>\d{1,2}:\d{2}\s*[AP]M)(?<utc>\s*UTC)?') { return $null }
    $isUtc = [bool]$Matches['utc']
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $clock = [datetime]::ParseExact((($Matches['time'] -replace '\s+', ' ').ToUpperInvariant() -replace '(\d)([AP]M)', '$1 $2'), 'h:mm tt', $culture)
    if ($Matches['date']) {
        $day = [datetime]::ParseExact(($Matches['date'] -replace '(\d)(st|nd|rd|th)', '$1'), [string[]]@('MMM d, yyyy', 'MMMM d, yyyy'), $culture, [System.Globalization.DateTimeStyles]::None)
        $at = $day.Date.Add($clock.TimeOfDay)
        if ($isUtc) { $at = [datetime]::SpecifyKind($at, [System.DateTimeKind]::Utc).ToLocalTime() }
        return $at
    }
    $at = $Now.Date.Add($clock.TimeOfDay)
    if ($isUtc) { $at = [datetime]::SpecifyKind($Now.ToUniversalTime().Date.Add($clock.TimeOfDay), [System.DateTimeKind]::Utc).ToLocalTime() }
    if ($at -lt $Now) { $at = $at.AddDays(1) }
    return $at
}

function Add-AosCapacityEvent([string]$Vendor, [int]$Remaining, [string]$Resets, [string]$Source, [string]$Note) {
    Add-AosLedgerEvent ([ordered]@{ type = 'capacity'; vendor = $Vendor; remaining = $Remaining; resets = $Resets; source = $Source; note = $Note })
}

function Add-AosCapacityFromError([string]$Vendor, [string]$Message) {
    $at = ConvertFrom-AosQuotaReset -Message $Message -Now ([datetime]::Now)
    $resets = ''
    if ($at) { $resets = $at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Add-AosCapacityEvent -Vendor $Vendor -Remaining 0 -Resets $resets -Source 'delegate' -Note 'quota error in a delegate receipt'
}

function Read-AosCodexLimits {
    # Codex logs its own rate limits (token_count events in ~/.codex/sessions rollouts): the newest 'codex' reading,
    # each window with used percent and reset (UTC). Read-only; $null when there is none. On 2026-10-04 a 5 h reset
    # went unnoticed because capacity knew only a hand-typed percent without a reset time.
    $root = Join-Path (Get-AosCodexHome) 'sessions'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    # Only the tail of the two newest rollouts: one rollout reached 168 MB, and this runs before every delegation
    # (Codex review 2). Readings are written every turn, so the newest one is near the end of a recent file.
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 2)
    $best = $null
    foreach ($f in $files) {
        $tail = 4MB
        $fs = [System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $from = [Math]::Max([long]0, $fs.Length - $tail)
            [void]$fs.Seek($from, [System.IO.SeekOrigin]::Begin)
            $text = (New-Object System.IO.StreamReader($fs, $script:Utf8NoBom)).ReadToEnd()
        } finally { $fs.Dispose() }
        $lines = $text -split "`n"
        if ($from -gt 0) { $lines = @($lines | Select-Object -Skip 1) }
        foreach ($line in $lines) {
            if ($line.IndexOf('"rate_limits"') -lt 0 -or $line.IndexOf('"limit_id":"codex"') -lt 0) { continue }
            try { $e = ConvertFrom-Json -InputObject $line -ErrorAction Stop } catch { continue }
            $rl = $e.payload.rate_limits
            if (-not $rl -or -not $e.timestamp) { continue }
            $ts = [datetime]::Parse([string]$e.timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            if ($best -and $best.observed -ge $ts) { continue }
            $windows = @()
            foreach ($w in @($rl.primary, $rl.secondary)) {
                if (-not $w) { continue }
                $label = 'week'
                if ([int]$w.window_minutes -lt 1440) { $label = [string]([int]([int]$w.window_minutes / 60)) + 'h' }
                $windows += [pscustomobject]@{ label = $label; used = [double]$w.used_percent
                    resets = [DateTimeOffset]::FromUnixTimeSeconds([long]$w.resets_at).UtcDateTime }
            }
            $best = [pscustomobject]@{ observed = $ts; windows = $windows }
        }
    }
    return $best
}

function Get-AosCapacity([datetime]$Now) {
    # Newest capacity event per vendor -> state: limited (0 % and the reset is ahead), reset (the reset has passed),
    # stale (a report older than a window), low (<= 30 %), ok. $Now is UTC. For Codex its own logged limits are used
    # when newer than the last event: a window whose reset has passed counts as empty, the tightest one binds.
    $out = [ordered]@{}
    $events = @(Get-AosLedger -Last 0 | Where-Object { $_['type'] -eq 'capacity' -and $_['vendor'] })
    $codexLog = $null
    try { $codexLog = Read-AosCodexLimits } catch { }
    foreach ($v in $script:CapacityVendors) {
        $last = @($events | Where-Object { $_['vendor'] -eq $v } | Select-Object -Last 1)
        $lastTs = $null
        if ($last.Count -gt 0) { $lastTs = [datetime]::Parse([string]$last[0]['ts'], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
        if ($v -eq 'codex' -and $codexLog -and $codexLog.windows.Count -gt 0 -and (-not $lastTs -or $codexLog.observed -gt $lastTs)) {
            $bind = $null
            foreach ($w in $codexLog.windows) {
                $left = 100 - $w.used
                if ($w.resets -le $Now) { $left = 100 }
                if (-not $bind -or $left -lt $bind.left) { $bind = [pscustomobject]@{ left = $left; w = $w } }
            }
            $remaining = [int][Math]::Floor($bind.left)
            $state = 'ok'
            if ($remaining -le 0) { $state = 'limited' }
            elseif ($remaining -le $script:CapacityLowPercent) { $state = 'low' }
            $note = (@($codexLog.windows | ForEach-Object { '{0} {1} % used, resets {2}' -f $_.label, $_.used, $_.resets.ToLocalTime().ToString('MMM d HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) }) -join '; ')
            $out[$v] = [pscustomobject]@{ vendor = $v; remaining = $remaining; resets = $bind.w.resets; reported = $codexLog.observed; source = 'codex-log'; note = $note; state = $state; window = $bind.w.label }
            continue
        }
        if ($last.Count -eq 0) { continue }
        $e = $last[0]
        $ts = $lastTs
        $resets = $null
        if ($e['resets']) { $resets = [datetime]::Parse((ConvertTo-AosStamp $e['resets']), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
        $remaining = [int]$e['remaining']
        $state = 'ok'
        if ($resets -and $resets -le $Now) { $state = 'reset' }
        elseif ($remaining -le 0 -and $resets) { $state = 'limited' }
        elseif (($Now - $ts).TotalHours -ge $script:CapacityStaleHours) { $state = 'stale' }
        elseif ($remaining -le $script:CapacityLowPercent) { $state = 'low' }
        $out[$v] = [pscustomobject]@{ vendor = $v; remaining = $remaining; resets = $resets; reported = $ts; source = [string]$e['source']; note = [string]$e['note']; state = $state; window = '' }
    }
    return $out
}

function Get-AosCapacityWarning([string]$Vendor) {
    try { $cap = Get-AosCapacity -Now ([datetime]::UtcNow) } catch { return $null }
    if (-not $cap.Contains($Vendor)) { return $null }
    $c = $cap[$Vendor]
    if ($c.state -eq 'limited') { return "$Vendor is limited until $($c.resets.ToLocalTime().ToString('HH:mm')) (quota): give this task to the other vendor, or schedule it after the reset" }
    if ($c.state -eq 'low') { return "$Vendor has about $($c.remaining) % of its window left: keep this task small (a bounded review), and give builds to the other vendor" }
    return $null
}

function Invoke-AosCapacity([string[]]$Arguments) {
    $usage = 'usage: aos capacity [set <claude|codex> <percent left 0-100> [--resets <HH:MM|ISO>] [--note <text>]]'
    $a = @($Arguments | Where-Object { $_ })
    if ($a.Count -ge 1 -and $a[0] -eq 'set') {
        $p = ConvertFrom-AosCliArgs @($a | Select-Object -Skip 1) @() @('resets', 'note') @()
        $vendor = [string]@($p.Pos)[0]
        $pct = -1
        if (@($p.Pos).Count -ge 2) { [void][int]::TryParse([string]@($p.Pos)[1], [ref]$pct) }
        if ($script:CapacityVendors -notcontains $vendor -or $pct -lt 0 -or $pct -gt 100) { Write-AosWarn $usage; return }
        $resets = ''
        if ($p.Opts['resets']) {
            $r = [string]$p.Opts['resets']
            if ($r -match '^\d{1,2}:\d{2}$') {
                $at = [datetime]::Today.Add([timespan]::Parse($r))
                if ($at -lt [datetime]::Now) { $at = $at.AddDays(1) }
                $resets = $at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            else { $resets = ([datetime]::Parse($r)).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        }
        Add-AosCapacityEvent -Vendor $vendor -Remaining $pct -Resets $resets -Source 'reported' -Note ([string]$p.Opts['note'])
        Write-AosOk "capacity: $vendor $pct % left recorded"
        return
    }
    if ($a.Count -ge 1) { Write-AosWarn $usage; return }
    $cap = Get-AosCapacity -Now ([datetime]::UtcNow)
    if ($cap.Count -eq 0) { Write-AosInfo 'capacity: nothing recorded yet (aos capacity set <vendor> <percent left>)'; return }
    foreach ($v in $cap.Keys) {
        $c = $cap[$v]
        $hint = 'free for builds and reviews'
        if ($c.state -eq 'low') { $hint = 'small tasks only (bounded reviews); builds go to the other vendor' }
        elseif ($c.state -eq 'limited') { $hint = 'limited until ' + $c.resets.ToLocalTime().ToString('HH:mm') + ': hand work to the other vendor' }
        elseif ($c.state -eq 'reset') { $hint = 'its reset has passed: check its real usage before a big task' }
        elseif ($c.state -eq 'stale') { $hint = 'report is old: ask for a fresh number before planning' }
        $age = [int]([datetime]::UtcNow - $c.reported).TotalMinutes
        Write-AosInfo ("{0,-6} {1,3} % left, {2} ({3}, {4} min ago) -> {5}" -f $v, $c.remaining, $c.state, $c.source, $age, $hint)
        if ($c.source -eq 'codex-log') { Write-AosInfo ("       {0} binds; {1}" -f $c.window, $c.note) }
    }
}

function Read-AosRolloutUsage {
    param([string]$ThreadId, [long]$FromOffset = 0)
    $usage = @{ Found = $false; Offset = $FromOffset; Input = [long]0; Cached = [long]0; Output = [long]0 }
    if (-not $ThreadId) { return $usage }
    $root = Join-Path (Get-AosCodexHome) 'sessions'
    if (-not (Test-Path -LiteralPath $root)) { return $usage }
    $file = Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.EndsWith('-' + $ThreadId + '.jsonl', [StringComparison]::Ordinal) } | Select-Object -First 1
    if (-not $file) { return $usage }
    $fs = $null
    $reader = $null
    try {
        $fs = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $from = [Math]::Max([long]0, $FromOffset)
        if ($from -gt $fs.Length) { $from = 0 }
        [void]$fs.Seek($from, [IO.SeekOrigin]::Begin)
        $reader = New-Object IO.StreamReader($fs, $script:Utf8NoBom)
        $text = $reader.ReadToEnd()
        # Keep an incomplete final event for the next poll; offsets are bytes, not UTF-16 characters.
        $end = $text.LastIndexOf("`n")
        $tail = $text.Substring($end + 1)
        if ($tail.Trim()) {
            try { $null = ConvertFrom-Json -InputObject $tail -ErrorAction Stop; $end = $text.Length - 1 } catch { }
        }
        if ($end -lt 0) { return $usage }
        $complete = $text.Substring(0, $end + 1)
        $usage.Offset = $from + $script:Utf8NoBom.GetByteCount($complete)
        foreach ($line in ($complete -split "`n")) {
            try { $e = ConvertFrom-Json -InputObject $line -ErrorAction Stop } catch { continue }
            if ($e.type -ne 'event_msg' -or $e.payload.type -ne 'token_count') { continue }
            $u = $e.payload.info.total_token_usage
            if ($null -eq $u) { continue }
            $usage.Found = $true
            $usage.Input = [long]$u.input_tokens
            $usage.Cached = [long]$u.cached_input_tokens
            $usage.Output = [long]$u.output_tokens
        }
    }
    catch { } # Missing, rotating or temporarily locked rollouts are best-effort observations.
    finally { if ($reader) { $reader.Dispose() } elseif ($fs) { $fs.Dispose() } }
    return $usage
}

function Invoke-AosDelegate {
    param([string]$Vendor, [string]$TaskFile, [switch]$Write, [string]$Model, [string[]]$Needs, [string]$Verify,
        [string[]]$Allow, [string[]]$Setup, [int]$TimeoutMinutes = 30, [string]$Repo, [int]$IdleMinutes = 15,
        [string]$Tier = 'standard', [string]$Effort, [string]$Parent, [ValidateRange(0,1)][int]$Workers = 0,
        [string]$ContractFile,[string]$Transport='exec', [int]$MaxInput = 0)
    # The command line hands an absent repeated option over as @($null); count only the values that were given.
    $Needs = @($Needs | Where-Object { $_ }); $Allow = @($Allow | Where-Object { $_ }); $Setup = @($Setup | Where-Object { $_ })
    $refuse = {
        param($m, $category = 'usage')
        Write-AosWarn "delegate refused: $m"
        $global:LASTEXITCODE = 1
        return [pscustomobject]@{ accepted = $false; outcome = 'refused'; error = [ordered]@{ category = $category; message = $m } }
    }
    if ($Vendor -notin @('codex', 'claude')) { return (& $refuse "unknown vendor '$Vendor' (codex or claude)") }
    if ($env:AOS_DELEGATE_ID) { return (& $refuse 'a delegated worker cannot launch another CLI delegate; use its reserved native allowance') }
    if ($Transport -notin @('exec','app-server') -or ($Transport -eq 'app-server' -and $Vendor -ne 'codex')) { return (& $refuse 'transport must be exec, or app-server for Codex') }
    if ($MaxInput -gt 0 -and $Transport -ne 'exec') { return (& $refuse 'max-input is enforced on the exec transport only; drop --max-input or use --transport exec') }
    try { $route = Resolve-AosTaskRoute -Vendor $Vendor -Tier $Tier -Model $Model -Effort $Effort }
    catch { return (& $refuse $_.Exception.Message) }
    $Model = $route.Model
    $Effort = $route.Effort
    # Capacity is advice: a malformed ledger row must never stop a delegation (Codex review).
    try { $capacityWarning = Get-AosCapacityWarning -Vendor $Vendor; if ($capacityWarning) { Write-AosWarn "capacity: $capacityWarning" } } catch { }
    $capacity = $null
    try { $capacity = Get-AosCapacity -Now ([DateTime]::UtcNow) } catch { }
    if ($capacity -and $capacity.Contains($Vendor) -and $capacity[$Vendor].state -eq 'limited') {
        return (& $refuse "$Vendor has fresh limited capacity; do not launch or probe until reset")
    }
    if (-not $TaskFile -or -not (Test-Path -LiteralPath $TaskFile)) { return (& $refuse "task file not found: $TaskFile") }
    $taskText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $TaskFile).ProviderPath)
    # Task boundaries are advice (R40): a contract states scope and verification itself, and a free-text task without
    # the two lines still runs, with a warning, instead of being refused.
    if (-not $ContractFile -and ($taskText -notmatch '(?m)^Read only:' -or $taskText -notmatch '(?m)^Done =')) {
        Write-AosWarn 'task file has no "Read only:" and "Done =" lines (R40): the delegate gets no explicit boundaries'
    }
    $repoDir = $Repo
    if (-not $repoDir) { $repoDir = (Get-Location).ProviderPath }
    $repoDir = Get-AosCheckout $repoDir
    $contractRow=$null;$taskState=@{Owned=$false}
    if ($ContractFile) {
        try {
            $contractRow=Register-AosTaskContract -Path $ContractFile -Repo $repoDir
            $c=$contractRow.contract
            if (-not $c['verify']) { throw 'contract requires a host verification command' }
            if ($Verify -and $Verify -ne $c['verify']) { throw 'verification conflicts with contract' }
            if (@($Allow).Count -and @($c['allow']).Count -and (@($Allow | Sort-Object -Unique) -join '|') -ne (@($c['allow'] | Sort-Object -Unique) -join '|')) { throw 'write scope conflicts with contract' }
            $Verify=[string]$c['verify'];$Allow=@($c['allow'])
            if ($c['budget'] -and $c['budget']['timeout_minutes']) { $TimeoutMinutes=[Math]::Min($TimeoutMinutes,[int]$c['budget']['timeout_minutes']) }
            $ready=Test-AosTaskReady -Id $contractRow.id -Repo $repoDir
            if (-not $ready.Ready) { throw ($ready.Reasons -join '; ') }
        } catch { return (& $refuse $_.Exception.Message) }
    }
    if ($contractRow -and $Write -and @($contractRow.contract['allow']).Count -eq 0) { throw 'write contract needs a nonempty allow scope' }
    if ($Write -and -not $Verify) { return (& $refuse 'write mode needs --verify <command>: the host checks the result, not the delegate') }
    if ($Write -and (Invoke-AosGit -Dir $repoDir -Arguments @('rev-parse', '--show-toplevel')).Code -ne 0) {
        return (& $refuse "write mode needs a git repository: $repoDir")
    }
    $delegations = Join-Path (Get-AosCoordDir) 'delegations'
    if (-not (Test-Path -LiteralPath $delegations)) { New-Item -ItemType Directory -Force -Path $delegations | Out-Null }
    $id = $null
    $dir = $null
    for ($try = 0; $try -lt 20 -and -not $id; $try++) {
        # Seconds alone can collide (same vendor, same first line): add a random suffix, create exclusively.
        $candidate = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 4) + "-$Vendor-" + (Get-AosDelegateSlug $taskText)
        $path = Join-Path $delegations $candidate
        if (Test-Path -LiteralPath $path) { continue }
        try { [void][System.IO.Directory]::CreateDirectory($path) } catch { continue }
        if (@(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { $id = $candidate; $dir = $path }
    }
    if (-not $id) { return (& $refuse 'could not create a unique delegation folder') }
    Write-AosText -Path (Join-Path $dir 'task.md') -Text $taskText
    $started = [DateTime]::UtcNow
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $receipt = [ordered]@{ id = $id; vendor = $Vendor; model = ''; mode = 'read'; repo = $repoDir; workdir = $repoDir; branch = ''; base = ''; commit = ''
        requested_model = $Model; requested_effort = $Effort; requested_tier = $Tier; tier = $route.Tier; route_reason = $route.Reason
        observed_model = $null; observed_models = @(); observed_effort = $null
        started = $started.ToString('yyyy-MM-ddTHH:mm:ssZ'); ended = ''; seconds = 0; exit_code = $null; timed_out = $false; kill_failed = $false
        thread_id = ''; session_id = ''; usage = [ordered]@{ input = 0; cached = 0; output = 0 }; cost_usd = $null
        error = $null; delegate = $null; changed = @(); outside_allow = @(); verify = $null; accepted = $false; outcome = 'failed'
        budget = @{ max_input = $MaxInput; observed = $false; last_input = [long]0; last_cached = [long]0; overshoot = [long]0 }
        task_id='';task_class='unclassified';transport=$Transport;review_choice=$null;corrections=$null;usage_observed=$false;context_chars=0
        phase_seconds=[ordered]@{launch=0.0;execution=$null;verification=$null;waiting=$null;integration=$null;review=$null};_phase='launch';_phase_started=0.0 }
    if ($contractRow) { $receipt.task_id=$contractRow.id;$receipt.task_class=$contractRow.contract['task_class'];$receipt['decision_reason']=$contractRow.contract['route_reason'];$receipt.review_choice=$contractRow.contract['review'] }
    $finish = {
        param($outcome)
        if ($outcome -ne 'needs-inspection' -and $receipt.error -and $receipt.error.category -eq 'over-budget') { $outcome = 'over-budget' }
        Set-AosReceiptPhase $receipt $clock ''
        $waitRun=Get-AosRunState $id
        if ($waitRun) {
            $waiting=[double]$waitRun['waiting_seconds']
            if ($waitRun['waiting_since']) { $waiting+=(Get-AosElapsedSince $waitRun['waiting_since']) }
            # Waiting is a measured subset of execution, not an additional phase to sum.
            $receipt.phase_seconds.waiting=[Math]::Round($waiting,4)
        }
        $receipt.Remove('_phase');$receipt.Remove('_phase_started')
        if ($taskState.Owned) {
            $receipt.outcome=$outcome;$receipt.accepted=($outcome -eq 'accepted')
            $receipt.ended=Get-AosUtcStamp;$receipt.seconds=[int]([DateTime]::UtcNow-$started).TotalSeconds
            Write-AosText -Path (Join-Path $dir 'receipt.json') -Text ((ConvertTo-Json -InputObject $receipt -Depth 10)+"`n")
            try { $null=Complete-AosTaskAttempt -Id $contractRow.id -RunId $id;$taskState.Owned=$false }
            catch {
                $outcome='needs-inspection'
                $failedTask=Get-AosTaskRecord $contractRow.id
                if ($failedTask['state'] -eq 'failed' -and -not $failedTask['active_run']) { $outcome='rejected';$taskState.Owned=$false }
                $receipt.error=[ordered]@{category='task-evidence';message=$_.Exception.Message}
            }
        }
        if ($actorOwned) {
            $actorState = 'failed'
            if ($outcome -eq 'accepted') { $actorState = 'done' }
            if ($outcome -eq 'cancelled') { $actorState = 'cancelled' }
            if ($outcome -eq 'needs-inspection') { $actorState = 'suspect' }
            try { $null = Set-AosActorState -Id $id -State $actorState -Text $outcome }
            catch {
                $outcome = 'needs-inspection'
                $receipt.accepted = $false
                $receipt.error = [ordered]@{ category='children'; message=$_.Exception.Message }
                try { $null = Set-AosActorState -Id $id -State suspect -Text 'completion could not be confirmed' } catch { }
            }
        }
        if ($receipt.error -and $receipt.error.category -eq 'quota') { try { Add-AosCapacityFromError -Vendor $Vendor -Message ([string]$receipt.error.message) } catch { } }
        $receipt.outcome = $outcome
        $receipt.accepted=($outcome -eq 'accepted')
        $receipt.ended = (Get-AosUtcStamp)
        $receipt.seconds = [int]([DateTime]::UtcNow - $started).TotalSeconds
        Write-AosText -Path (Join-Path $dir 'receipt.json') -Text ((ConvertTo-Json -InputObject $receipt -Depth 10) + "`n")
        # Coordination has a fixed state vocabulary; keep the specific outcome in the receipt and ledger.
        if ($outcome -eq 'over-budget') { $null = Set-AosRunState -Id $id -State failed -Text $outcome }
        else { $null = Set-AosRunState -Id $id -State $outcome }
        Add-AosLedgerEvent ([ordered]@{ type = 'delegate'; id = $id; vendor = $Vendor; model = $receipt.model; outcome = $outcome
            seconds = $receipt.seconds; input = $receipt.usage.input; output = $receipt.usage.output })
    }
    $workdir = $repoDir
    $claimed = $false
    $actorOwned = $false
    try {
    $taskId = $id
    if ($Parent) {
        $parentActor = @(Get-AosActors | Where-Object id -eq $Parent | Select-Object -First 1)
        if ($parentActor.Count -eq 0) { throw 'unknown parent actor' }
        $taskId = [string]$parentActor[0].task
    }
    $admission = Reserve-AosActor -Id $id -Vendor $Vendor -Task $taskId -Parent $Parent -Kind delegate -Workers $Workers
    if (-not $admission.Ok) {
        $receipt.error = [ordered]@{ category='admission'; message=$admission.Reason }
        & $finish 'busy'
        return $receipt
    }
    $actorOwned = $true
    $null = Set-AosRunState -Id $id -State preparing
    $activeRun=Get-AosRunState $id;$activeRun['transport']=$Transport
    Write-AosCoordJson (Join-Path $dir 'run.json') $activeRun
    if ($contractRow) { $null=Start-AosTaskAttempt -Id $contractRow.id -RunId $id;$taskState.Owned=$true }
    if ($Write) {
        $receipt.mode = 'write'
        $top = Invoke-AosGit -Dir $repoDir -Arguments @('rev-parse', '--show-toplevel')
        if ($top.Code -ne 0) { return (& $refuse "write mode needs a git repository: $repoDir") }
        $base = (Invoke-AosGit -Dir $repoDir -Arguments @('rev-parse', 'HEAD')).Out
        $receipt.base = $base
        $dirty = (Invoke-AosGit -Dir $repoDir -Arguments @('status', '--porcelain')).Out
        if ($dirty) { Write-AosWarn 'uncommitted changes in the repo: the delegate sees committed HEAD only' }
        $branch = "delegate/$id"
        $workdir = Join-Path (Get-AosWorktreesDir) ((Split-Path -Leaf $repoDir) + "-$id")
        $wt = Invoke-AosGit -Dir $repoDir -Arguments @('worktree', 'add', '-b', $branch, $workdir, $base) -TimeoutSeconds 300
        if ($wt.Code -ne 0) { throw "git worktree add failed: $($wt.Err)" }
        $receipt.branch = $branch
        $receipt.workdir = $workdir
        $cl = Invoke-AosClaim -Path $workdir -Agent $Vendor -Session $id -TtlMinutes ([Math]::Min(1440, $TimeoutMinutes + 30)) -Note "aos delegate $id"
        $claimed = $cl.Ok
        if (-not $claimed) { throw "delegate claim refused: $($cl.Message)" }
        foreach ($s in @($Setup | Where-Object { $_ })) {
            $sr = Invoke-AosProcess -Exe 'cmd.exe' -ArgumentString ('/d /s /c "' + $s + '"') -WorkingDirectory $workdir -TimeoutSeconds 600
            if ($sr.KillFailed) { $receipt.kill_failed=$true; throw "setup could not be stopped: $s" }
            if ($sr.Code -ne 0) { throw "required setup failed (exit $($sr.Code)): $s" }
        }
    }
    $pre = Test-AosDelegatePreflight -Vendor $Vendor -Model $Model -Needs $Needs -Verify $Verify -WorkDir $workdir -Write:$Write
    if (-not $pre.Ok) {
        $receipt.error = [ordered]@{ category = 'preflight'; message = ($pre.Reasons -join '; ') }
        if ($Write) {
            if ($claimed) { $null = Invoke-AosRelease -Path $workdir -Agent $Vendor -Session $id; $claimed=$false }
            $null = Invoke-AosGit -Dir $repoDir -Arguments @('worktree', 'remove', '--force', $workdir)
            $null = Invoke-AosGit -Dir $repoDir -Arguments @('branch', '-D', $receipt.branch)
        }
        & $finish 'preflight-failed'
        Write-AosWarn "delegate $id preflight failed: $($receipt.error.message)"
        $global:LASTEXITCODE = 1
        return $receipt
    }
    $receipt.model = $pre.Model
    $null = Set-AosActorState -Id $id -State running -Text 'model launch'
    $schemaPath = Join-Path $script:Root 'config\delegate\result.schema.json'
    $promptPath = Join-Path $dir 'prompt.md'
    if ($contractRow) { $packet=Get-AosTaskPacket -Id $contractRow.id -Repo $repoDir;$receipt.context_chars=$packet.Length;$taskText+="`n`n$packet" }
    $workerEnvironment=@{ AOS_DELEGATE_ID=$id; AOS_ACTOR_ID=$id; AOS_RUN_ID=$id; AOS_COORD_TRANSPORT='stdout' }
    if ($Workers) {
        $maxTurns=24;if ($contractRow -and $contractRow.contract['budget'] -and $contractRow.contract['budget']['max_turns']) {$maxTurns=[int]$contractRow.contract['budget']['max_turns']}
        $receipt['native_request']=Get-AosNativeRole -Vendor $Vendor -Role implement -Tier $route.Tier -MaxTurns $maxTurns
        $workerEnvironment['AOS_NATIVE_MAX_TURNS']=[string]$maxTurns
        $taskText+="`nNative worker request (requested settings, not observations): " + (ConvertTo-Json -InputObject $receipt['native_request'] -Depth 6 -Compress)
        $taskText+="`nUse the managed aos-implement role or pass its supported settings explicitly through the native harness. The max_turns budget applies to your child. Do not claim enforcement or observed settings that the harness does not expose. Return blocked or partial if the budget is exhausted."
    }
    Write-AosText -Path $promptPath -Text (Get-AosDelegatePrompt -TaskText $taskText -WorkDir $workdir -Branch $receipt.branch -Write:$Write -RunId $id -Parent $Parent -Workers $Workers)
    $result = $null
    Set-AosReceiptPhase $receipt $clock 'execution'
    if ($Vendor -eq 'codex') {
        $mode = 'read-only'
        if ($Write) { $mode = 'workspace-write' }
        $resultPath = Join-Path $dir 'result.json'
        $codexArgs = @('exec', '-m', $pre.Model, '--json', '--output-schema', $schemaPath, '-o', $resultPath,
            '-C', $workdir, '--sandbox', $mode, '--skip-git-repo-check')
        if ($Effort) { $codexArgs += @('-c', ('model_reasoning_effort="' + $Effort + '"')) }
        if ($Workers) { $codexArgs+=@('-c','agents.max_threads=1') }
        $codexArgs += '-'
        $modelExe='codex.exe'
        if ($Transport -eq 'app-server') {
            $modelExe='node.exe'
            $codexArgs=@((Join-Path $script:Root 'tools\codex-app-server.mjs'),'--cwd',$workdir,'--model',$pre.Model,'--sandbox',$mode,'--schema',$schemaPath,'--output',$resultPath,'--run-dir',$dir,'--timeout-seconds',[string]($TimeoutMinutes*60))
            if ($Effort) { $codexArgs+=@('--effort',$Effort) }
        }
        $watchArgs = @{}
        if ($MaxInput -gt 0 -and $Transport -eq 'exec') {
            $watchState = @{ ThreadId = ''; Offset = [long]0 }
            $watchArgs.Watch = {
                param([string]$stdout)
                if (-not $watchState.ThreadId) {
                    foreach ($line in ($stdout -split "`n")) {
                        try { $event = ConvertFrom-Json -InputObject $line -ErrorAction Stop } catch { continue }
                        if ($event.type -eq 'thread.started' -and $event.thread_id) { $watchState.ThreadId = [string]$event.thread_id; break }
                    }
                }
                if (-not $watchState.ThreadId) { return }
                $usage = Read-AosRolloutUsage -ThreadId $watchState.ThreadId -FromOffset $watchState.Offset
                $watchState.Offset = $usage.Offset
                if ($usage.Found) {
                    $receipt.budget.observed = $true
                    $receipt.budget.last_input = $usage.Input
                    $receipt.budget.last_cached = $usage.Cached
                    # Input already includes cached tokens; the budget bounds the total.
                    $receipt.budget.overshoot = [Math]::Max([long]0, $usage.Input - $MaxInput)
                    if ($receipt.budget.overshoot -gt 0) { return 'over-budget' }
                }
            }
        }
        $run = Invoke-AosProcess -Exe $modelExe -Arguments $codexArgs -WorkingDirectory $workdir -StdinFile $promptPath `
            -StdoutFile (Join-Path $dir 'events.jsonl') -StderrFile (Join-Path $dir 'stderr.log') -TimeoutSeconds ($TimeoutMinutes * 60) `
            -Environment $workerEnvironment -LiveRunId $id -IdleSeconds ([Math]::Max(0, $IdleMinutes) * 60) @watchArgs
        $ev = Read-AosCodexEvents (Join-Path $dir 'events.jsonl')
        $receipt.thread_id = $ev.ThreadId
        $receipt.usage_observed=$ev.UsageObserved
        $receipt.usage = [ordered]@{ input = $ev.Input; cached = $ev.Cached; output = $ev.Output }
        if ($ev.Errors.Count -gt 0) {
            $cat = Get-AosErrorCategory $ev.Errors[0]
            $receipt.error = [ordered]@{ category = $cat; message = $ev.Errors[0] }
            if ($cat -eq 'not-supported') { Clear-AosDelegateModelCache 'codex' }
        }
        if (Test-Path -LiteralPath $resultPath) {
            try { $result = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($resultPath)) -ErrorAction Stop) } catch { }
        }
    }
    else {
        $schemaJson = ([System.IO.File]::ReadAllText($schemaPath) -replace '\s+', ' ').Trim()
        $perm = 'plan'
        if ($Write) { $perm = 'acceptEdits' }
        $claudeArgs = @('-p', '--output-format', 'stream-json', '--verbose', '--json-schema', $schemaJson, '--permission-mode', $perm)
        if ($pre.Model) { $claudeArgs += @('--model', $pre.Model) }
        if ($Effort) { $claudeArgs += @('--effort', $Effort) }
        if ($Write) {
            $tools = @()
            foreach ($c in @(@($Verify) + @($Needs) | Where-Object { $_ })) { $tools += ('Bash(' + (Get-AosCommandExe $c) + ':*)') }
            if ($tools.Count) { $claudeArgs += @('--allowedTools') + @($tools | Select-Object -Unique) }
        }
        $outPath = Join-Path $dir 'claude.json'
        $run = Invoke-AosProcess -Exe 'claude.exe' -Arguments $claudeArgs -WorkingDirectory $workdir -StdinFile $promptPath `
            -StdoutFile $outPath -StderrFile (Join-Path $dir 'stderr.log') -TimeoutSeconds ($TimeoutMinutes * 60) `
            -Environment $workerEnvironment -LiveRunId $id
        $cj = Read-AosClaudeResult $outPath
        if ($cj -is [System.Collections.IDictionary]) {
            if ($cj['modelUsage'] -is [System.Collections.IDictionary]) { $receipt.observed_models = @($cj['modelUsage'].Keys | Sort-Object) }
            if ($cj['model']) { $receipt.observed_model = [string]$cj['model'] }
            $receipt.session_id = [string]$cj['session_id']
            $receipt.cost_usd = $cj['total_cost_usd']
            $u = $cj['usage']
            if ($u -is [System.Collections.IDictionary]) {
                $receipt.usage_observed=($null -ne $u['input_tokens'] -and $null -ne $u['output_tokens'])
                $receipt.usage = [ordered]@{ input = [long]$u['input_tokens']; cached = [long]$u['cache_read_input_tokens']; output = [long]$u['output_tokens'] }
            }
            if ($cj['is_error'] -eq $true) {
                $msg = [string]$cj['result']
                $receipt.error = [ordered]@{ category = (Get-AosErrorCategory $msg); message = $msg }
            }
            elseif ($cj['structured_output'] -is [System.Collections.IDictionary]) { $result = $cj['structured_output'] }
            else { try { $result = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject ([string]$cj['result']) -ErrorAction Stop) } catch { } }
        }
        elseif (-not $run.TimedOut) { $receipt.error = [ordered]@{ category = 'other'; message = "no JSON from claude (exit $($run.Code))" } }
    }
    $receipt.exit_code = $run.Code
    if ($run.Watched -eq 'over-budget') {
        $receipt.error = [ordered]@{ category = 'over-budget'; message = "input tokens (cached included) exceeded $MaxInput" }
    }
    if ($Vendor -eq 'claude') {
        $null=Import-AosNativeSignals -RunId $id
        $nativeRun=Get-AosRunState $id
        if ($nativeRun['native_inspection_required'] -or $nativeRun['state'] -eq 'needs-inspection') { $receipt['native_unconfirmed']=$true }
    }
    Set-AosReceiptPhase $receipt $clock 'verification'
    $receipt['cancelled']=[bool]$run.Cancelled
    if ($run.Cancelled) { $receipt.error=[ordered]@{category='cancelled';message='cancellation requested; process stop confirmed separately'} }
    if ($null -eq $receipt.error -and -not $run.TimedOut -and $run.Code -ne 0) {
        $receipt.error = [ordered]@{ category = 'other'; message = "delegate process exited with code $($run.Code)" }
    }
    $receipt.timed_out = [bool]$run.TimedOut
    $receipt.kill_failed = [bool]$run.KillFailed
    $receipt.stalled = [bool]$run.Stalled
    if ($run.Stalled -and $null -eq $receipt.error) {
        $receipt.error = [ordered]@{ category = 'stalled'; message = "no progress for $IdleMinutes min (no codex events; stalled network?), killed before the $TimeoutMinutes min timeout" }
    }
    if ($result -is [System.Collections.IDictionary]) {
        $receipt.delegate = [ordered]@{ status = [string]$result['status']; summary = [string]$result['summary']
            files_changed = @($result['files_changed']); tests_run = @($result['tests_run']); unverified = @($result['unverified']) }
    }
    if ($run.KillFailed) {
        & $finish 'needs-inspection'
        Write-AosWarn "delegate $id timed out and could not be stopped: inspect $workdir (claim kept)"
        $global:LASTEXITCODE = 1
        return $receipt
    }
    if ($Write) {
        $st = Invoke-AosGit -Dir $workdir -Arguments @('status', '--porcelain', '--untracked-files=all')
        $changed = @(Get-AosPorcelainPaths $st.Out)
        $receipt.changed = $changed
        if (@($Allow | Where-Object { $_ }).Count -gt 0) { $receipt.outside_allow = @($changed | Where-Object { -not (Test-AosAllowed $_ $Allow) }) }
        # A timed-out delegate's edits are partial: leave them uncommitted in the worktree for inspection.
        if ($changed.Count -gt 0 -and -not $run.TimedOut -and -not $run.Cancelled -and -not $receipt.error -and $receipt.delegate -and $receipt.delegate.status -eq 'done') {
            $summary = 'changes'
            if ($receipt.delegate -and $receipt.delegate.summary) { $summary = (($receipt.delegate.summary -split "`r?`n")[0]) }
            if ($summary.Length -gt 72) { $summary = $summary.Substring(0, 72) }
            $null = Invoke-AosGit -Dir $workdir -Arguments @('add', '-A')
            $cm = Invoke-AosGitWithIdentity -Dir $workdir -Arguments @('commit', '-q', '-m', "delegate ${id}: $summary")
            if ($cm.Code -eq 0) { $receipt.commit = (Invoke-AosGit -Dir $workdir -Arguments @('rev-parse', 'HEAD')).Out }
        }
    }
    if ($Verify -and -not $run.TimedOut -and -not $run.Cancelled) {
        # Still under the delegate's claim, so no other session edits what is being verified.
        $vlog = Join-Path $dir 'verify.log'
        $vr = Invoke-AosProcess -Exe 'cmd.exe' -ArgumentString ('/d /s /c "' + $Verify + '"') -WorkingDirectory $workdir -StdoutFile $vlog -StderrFile (Join-Path $dir 'verify.err.log') -TimeoutSeconds 1800
        $receipt.verify = [ordered]@{ command = $Verify; exit_code = $vr.Code }
        if ($vr.KillFailed) { $receipt.kill_failed=$true; throw 'verification process could not be stopped' }
        if ($Write) {
            # The verified tree must be the recorded commit: a verify step that rewrites files proves nothing.
            $after = Invoke-AosGit -Dir $workdir -Arguments @('status', '--porcelain')
            $head = (Invoke-AosGit -Dir $workdir -Arguments @('rev-parse', 'HEAD')).Out
            $receipt['verify_changed_tree'] = ([bool]$after.Out -or ($receipt.commit -and $head -ne $receipt.commit))
        }
    }
    if ($contractRow -and -not (Test-AosTaskReady -Id $contractRow.id -Repo $repoDir).Ready) { $receipt.error=[ordered]@{category='task-input';message='prerequisite changed during execution'} }
    $outcome = 'rejected'
    if ($run.Cancelled) { $outcome = 'cancelled' }
    elseif ($receipt['native_unconfirmed']) { $outcome='needs-inspection' }
    elseif ($run.TimedOut) { $outcome = 'timed-out' }
    elseif ($null -ne $receipt.error) { $outcome = 'failed' }
    else {
        $ok = ($null -ne $receipt.delegate -and $receipt.delegate.status -eq 'done')
        # The process must end cleanly too; for Codex, a completed turn is required evidence.
        if ($run.Code -ne 0) { $ok = $false }
        if ($Vendor -eq 'codex' -and -not $ev.Completed) { $ok = $false }
        if ($receipt.Contains('verify_changed_tree') -and $receipt['verify_changed_tree']) { $ok = $false }
        if ($Verify -and ($null -eq $receipt.verify -or $receipt.verify.exit_code -ne 0)) { $ok = $false }
        if ($Write -and (-not $receipt.commit -or @($receipt.outside_allow).Count -gt 0)) { $ok = $false }
        if ($ok) { $outcome = 'accepted' }
    }
    $receipt.accepted = ($outcome -eq 'accepted')
    & $finish $outcome
    $outcome=$receipt.outcome
    $line = "delegate $id ($Vendor $($receipt.model)): $outcome, $($receipt.seconds) s, $($receipt.usage.input) in / $($receipt.usage.output) out tokens"
    if ($receipt.accepted) { Write-AosOk $line } else { Write-AosWarn $line }
    Write-AosInfo (Join-Path $dir 'receipt.json')
    if ($receipt.accepted) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
    return $receipt
    }
    catch {
        if ($_.Exception.Data['AosKillFailed']) { $receipt.kill_failed=$true }
        $receipt.accepted=$false
        $receipt.error=[ordered]@{ category='lifecycle'; message=$_.Exception.Message }
        $failure='failed'; if ($receipt.kill_failed) { $failure='needs-inspection' }
        & $finish $failure
        return $receipt
    }
    finally {
        if (-not $receipt.ended) {
            $receipt.accepted=$false
            $receipt.error=[ordered]@{ category='lifecycle'; message='delegate interrupted before completion' }
            & $finish 'failed'
        }
        if ($claimed -and -not $receipt.kill_failed -and $receipt.outcome -ne 'needs-inspection') {
            $null = Invoke-AosRelease -Path $workdir -Agent $Vendor -Session $id
        }
        $global:LASTEXITCODE=1; if ($receipt.accepted) { $global:LASTEXITCODE=0 }
    }
}

function Show-AosDelegations([int]$Last = 10) {
    $active=@(Get-AosActors | Where-Object { $_.kind -eq 'delegate' -and $_.state -in @('reserved','running','waiting-input','suspect') })
    foreach ($actor in $active) {
        $run=Get-AosRunState $actor.id
        Write-Host (ConvertTo-Json -InputObject $run -Depth 10 -Compress)
    }
    $rows = @(Get-AosLedger -Last 0 | Where-Object { $_['type'] -eq 'delegate' } | Select-Object -Last $Last)
    if ($rows.Count -eq 0) { Write-AosInfo 'no delegations yet'; return }
    foreach ($r in $rows) { Write-Host ('{0}  {1,-16} {2,-8} {3,-12} {4,6} s  {5} in / {6} out' -f $r['ts'], $r['outcome'], $r['vendor'], $r['model'], $r['seconds'], $r['input'], $r['output']); Write-Host "       $($r['id'])" }
}

function Show-AosDelegation([string]$Id) {
    Assert-AosCoordId $Id
    $run=Get-AosRunState $Id
    if ($run -and $run['state'] -in @('preparing','reserved','running','waiting-input','suspect')) {
        Write-Host (ConvertTo-Json -InputObject $run -Depth 10); return
    }
    $path = Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $Id) 'receipt.json'
    if (-not (Test-Path -LiteralPath $path)) { Write-AosWarn "no receipt for $Id"; $global:LASTEXITCODE = 1; return }
    Write-Host ([System.IO.File]::ReadAllText($path))
}

function Remove-AosDelegation([string]$Id, [switch]$Force) {
    $path = Join-Path (Join-Path (Join-Path (Get-AosCoordDir) 'delegations') $Id) 'receipt.json'
    $r = Read-AosJson $path
    if ($null -eq $r) { Write-AosWarn "no receipt for $Id"; $global:LASTEXITCODE = 1; return }
    if ($r['mode'] -ne 'write' -or -not $r['branch']) { Write-AosOk "$Id has no worktree"; return }
    $repo = [string]$r['repo']
    $merged = (Invoke-AosGit -Dir $repo -Arguments @('branch', '--merged', 'HEAD', '--list', $r['branch'])).Out
    if (-not $merged -and -not $Force) { Write-AosWarn "$($r['branch']) is not merged into the current branch of $repo; use --force to drop it"; $global:LASTEXITCODE = 1; return }
    $workdir = [string]$r['workdir']
    if ((Test-Path -LiteralPath $workdir) -and -not $Force) {
        # A timed-out delegate leaves uncommitted partial edits on a branch that still points at base.
        $dirty = (Invoke-AosGit -Dir $workdir -Arguments @('status', '--porcelain')).Out
        if ($dirty) { Write-AosWarn "$workdir has uncommitted changes; inspect them, or use --force to drop them"; $global:LASTEXITCODE = 1; return }
    }
    # --setup may have linked shared folders (node_modules) into the worktree: unlink them first, so a
    # recursive removal can never reach the shared target.
    if (Test-Path -LiteralPath $workdir) {
        $pending = New-Object System.Collections.Stack
        $pending.Push(@{ Path = $workdir; Depth = 0 })
        while ($pending.Count -gt 0) {
            $node = $pending.Pop()
            foreach ($d in @(Get-ChildItem -LiteralPath $node.Path -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($d.Name -eq '.git') { continue }
                if ($d.LinkType) { [System.IO.Directory]::Delete($d.FullName, $false); continue }
                if ($node.Depth -lt 3) { $pending.Push(@{ Path = $d.FullName; Depth = $node.Depth + 1 }) }
            }
        }
    }
    $removeArgs = @('worktree', 'remove')
    if ($Force) { $removeArgs += '--force' }
    $wr = Invoke-AosGit -Dir $repo -Arguments ($removeArgs + @($workdir))
    if ($wr.Code -ne 0 -and (Test-Path -LiteralPath $workdir)) { Write-AosWarn "could not remove ${workdir}: $($wr.Err)"; $global:LASTEXITCODE = 1; return }
    $br = Invoke-AosGit -Dir $repo -Arguments @('branch', '-D', $r['branch'])
    if ($br.Code -ne 0) { Write-AosWarn "removed $workdir, but not $($r['branch']): $($br.Err)"; $global:LASTEXITCODE = 1; return }
    Add-AosLedgerEvent ([ordered]@{ type = 'delegate-clean'; id = $Id; branch = $r['branch'] })
    Write-AosOk "removed $workdir and $($r['branch'])"
    $global:LASTEXITCODE = 0
}

#endregion
#region coordination CLI ------------------------------------------------------------------

function Get-AosParentPid {
    # The calling shell: one CLI session per terminal. CIM works in 5.1 and 7 (Process.Parent is 7 only).
    try { return [int](Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId } catch { return $PID }
}

function ConvertFrom-AosCliArgs([string[]]$Arguments, [string[]]$Switches, [string[]]$Options, [string[]]$Multi) {
    $opts = @{}
    $pos = New-Object System.Collections.Generic.List[string]
    $a = @($Arguments | Where-Object { $null -ne $_ })
    for ($i = 0; $i -lt $a.Count; $i++) {
        $x = $a[$i]
        if ($x.StartsWith('--')) {
            $name = $x.Substring(2)
            if ($Switches -contains $name) { $opts[$name] = $true; continue }
            if (($Options -contains $name -or $Multi -contains $name) -and $i + 1 -lt $a.Count) {
                if ($Multi -contains $name) {
                    if (-not $opts.ContainsKey($name)) { $opts[$name] = New-Object System.Collections.Generic.List[string] }
                    $opts[$name].Add($a[$i + 1])
                }
                else { $opts[$name] = $a[$i + 1] }
                $i++
                continue
            }
            throw "unknown or incomplete option: $x"
        }
        $pos.Add($x)
    }
    return @{ Pos = $pos.ToArray(); Opts = $opts }
}

function Invoke-AosCoordCommand([string]$Command, [string[]]$Arguments) {
    try {
        switch ($Command) {
            'claim' {
                $p = ConvertFrom-AosCliArgs $Arguments @('json') @('as', 'session', 'note', 'ttl') @()
                if (-not $p.Opts['as']) { throw 'usage: aos claim [<path>] --as <agent> [--session <id>] [--note <text>] [--ttl <min>] [--json]' }
                $session = $p.Opts['session']
                if (-not $session) { $session = "$($p.Opts['as'])-$(Get-AosParentPid)" }
                $ttl = 60
                if ($p.Opts['ttl']) { $ttl = [int]$p.Opts['ttl'] }
                $r = Invoke-AosClaim -Path ($p.Pos | Select-Object -First 1) -Agent $p.Opts['as'] -Session $session -Note ([string]$p.Opts['note']) -TtlMinutes $ttl
                if ($p.Opts['json']) { Write-Host (ConvertTo-Json -InputObject $r -Depth 6) }
                elseif ($r.Ok) { Write-AosOk "$($r.Action): $($r.Claim.checkout) for $($r.Claim.agent) ($($r.Claim.session)) until $($r.Claim.expires)" }
                else { Write-AosWarn $r.Message }
                if ($r.Ok) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
            }
            'release' {
                $p = ConvertFrom-AosCliArgs $Arguments @() @('as', 'session') @()
                if (-not $p.Opts['as']) { throw 'usage: aos release [<path>] --as <agent> [--session <id>]' }
                $session = $p.Opts['session']
                if (-not $session) { $session = "$($p.Opts['as'])-$(Get-AosParentPid)" }
                $r = Invoke-AosRelease -Path ($p.Pos | Select-Object -First 1) -Agent $p.Opts['as'] -Session $session
                if ($r.Ok) { Write-AosOk 'released'; $global:LASTEXITCODE = 0 } else { Write-AosWarn $r.Message; $global:LASTEXITCODE = 1 }
            }
            'who' {
                $p = ConvertFrom-AosCliArgs $Arguments @('json') @() @()
                $claims = @(Get-AosClaims)
                $events = @(Get-AosLedger -Last 10)
                if ($p.Opts['json']) { Write-Host (ConvertTo-Json -InputObject ([ordered]@{ claims = $claims; ledger = $events }) -Depth 8) ; return }
                if ($claims.Count -eq 0) { Write-AosInfo 'no live claims' }
                foreach ($c in $claims) { Write-AosOk (Format-AosClaimHolder $c) }
                foreach ($e in $events) {
                    $what = @($e.Keys | Where-Object { $_ -notin @('ts', 'type') } | ForEach-Object { "$_=$($e[$_])" }) -join ' '
                    Write-AosInfo "$($e['ts']) $($e['type']) $what"
                }
            }
            'note' {
                $p = ConvertFrom-AosCliArgs $Arguments @() @('as') @()
                $text = ($p.Pos -join ' ').Trim()
                if (-not $p.Opts['as'] -or -not $text) { throw 'usage: aos note <text> --as <agent>' }
                if (-not (Test-AosAgentName $p.Opts['as'])) { throw "invalid agent name '$($p.Opts['as'])'" }
                Add-AosLedgerEvent ([ordered]@{ type = 'note'; agent = $p.Opts['as']; checkout = (Get-AosCheckout ''); text = $text })
                Write-AosOk 'noted (aos who shows it)'
            }
            'delegate' {
                $sub = @($Arguments)[0]
                $rest = @($Arguments | Select-Object -Skip 1)
                switch ($sub) {
                    'ls' { $p = ConvertFrom-AosCliArgs $rest @() @('last') @(); $n = 10; if ($p.Opts['last']) { $n = [int]$p.Opts['last'] }; Show-AosDelegations -Last $n }
                    'show' { Show-AosDelegation -Id (@($rest)[0]) }
                    'clean' { $p = ConvertFrom-AosCliArgs $rest @('force') @() @(); Remove-AosDelegation -Id ($p.Pos | Select-Object -First 1) -Force:([bool]$p.Opts['force']) }
                    { $_ -in @('codex', 'claude') } {
                        $p = ConvertFrom-AosCliArgs $rest @('write') @('task', 'model', 'tier', 'effort', 'parent', 'workers', 'verify', 'timeout', 'idle', 'max-input', 'repo','contract','transport') @('needs', 'allow', 'setup')
                        if ($p.Pos.Count -gt 0) { throw "unexpected argument: $($p.Pos[0])" }
                        if (-not $p.Opts['task']) { throw 'usage: aos delegate <codex|claude> --task <file> [--write --verify <cmd>] [--model <m>] [--needs <cmd>]... [--allow <glob>]... [--setup <cmd>]... [--timeout <min>] [--idle <min, 0 = off>] [--max-input <tokens, 0 = off>] [--repo <path>] [--contract <json>] [--tier light|standard|deep] [--effort <e>] [--parent <lead-id>] [--workers 0|1] [--transport exec|app-server]' }
                        $t = 30
                        if ($p.Opts['timeout']) { $t = [int]$p.Opts['timeout'] }
                        $idle = 15
                        if ($null -ne $p.Opts['idle']) { $idle = [int]$p.Opts['idle'] }
                        $workers = 0
                        if ($null -ne $p.Opts['workers']) { $workers = [int]$p.Opts['workers'] }
                        $null = Invoke-AosDelegate -Vendor $sub -TaskFile $p.Opts['task'] -Write:([bool]$p.Opts['write']) -Model $p.Opts['model'] `
                            -Needs @($p.Opts['needs']) -Verify $p.Opts['verify'] -Allow @($p.Opts['allow']) -Setup @($p.Opts['setup']) -TimeoutMinutes $t -IdleMinutes $idle -MaxInput ([int]$p.Opts['max-input']) -Repo $p.Opts['repo'] `
                            -Tier $p.Opts['tier'] -Effort $p.Opts['effort'] -Parent $p.Opts['parent'] -Workers $workers -ContractFile $p.Opts['contract'] -Transport $(if ($p.Opts['transport']) {$p.Opts['transport']} else {'exec'})
                    }
                    default { throw 'usage: aos delegate <codex|claude|ls|show|clean> ...' }
                }
            }
        }
    }
    catch { Write-AosWarn $_.Exception.Message; $global:LASTEXITCODE = 1 }
}

#endregion
