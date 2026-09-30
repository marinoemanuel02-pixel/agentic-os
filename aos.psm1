# aos.psm1 - the `aos` command: install, sync, check and update the agentic-os setup.
#
# Runs in Windows PowerShell 5.1 and PowerShell 7. Every step is idempotent: running it
# twice changes nothing the second time unless something drifted. Keep this file ASCII-only
# (Windows PowerShell 5.1 misreads BOM-less UTF-8).

$script:Root = $PSScriptRoot
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Layers = @('base', 'engines', 'brain', 'bridges', 'refs', 'local', 'phone')

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

function Install-AosWingetPackage([string]$Id, [string]$Why, [string]$InstallerType, [switch]$DryRun) {
    if (Test-AosWinget $Id) {
        if ((@('wix', 'msi') -contains $InstallerType) -and (Test-AosInstalledAsMsix $Id)) {
            Write-AosWarn "$Id is installed as the MSIX package but must be the $InstallerType edition. Migrate: winget uninstall --id $Id -e, then aos install base"
            return
        }
        Write-AosOk "$Id"; return
    }
    $extra = @()
    if ($InstallerType) { $extra = @('--installer-type', $InstallerType) }
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
        # The command it installs: a scoped package (@getpaseo/cli) installs paseo.cmd, not its own name.
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
    Merge-AosTree $current $overlay
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

function Sync-AosMcp([switch]$DryRun) {
    # Registered = present AND pointing where the manifest says; a changed URL or command is re-added.
    $manifest = Get-AosMcpManifest
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
        foreach ($agent in @('claude', 'codex')) {
            if (-not (Test-AosCommand $agent)) { Write-AosWarn "$agent missing; $name not registered there"; continue }
            $getCmd = "claude mcp get $name"
            if ($agent -eq 'codex') { $getCmd = "codex mcp get $name --json" }
            $got = Invoke-AosCapture $getCmd
            if (Test-AosMcpCurrent $got $needles) { Write-AosOk "${agent}: $name"; continue }
            if ($DryRun) { Write-AosDry "$agent mcp add $name"; continue }
            if ($got.Code -eq 0) {
                $rm = "claude mcp remove $name --scope user"
                if ($agent -eq 'codex') { $rm = "codex mcp remove $name" }
                $null = Invoke-AosCapture $rm
                Write-AosInfo "${agent}: $name changed; re-adding"
            }
            if (Add-AosMcpServer -Agent $agent -Name $name -Http $isHttp -Url ([string]$s['url']) -Command $cmd) { Write-AosOk "${agent}: added $name" }
            else { Write-AosWarn "${agent}: adding $name failed" }
        }
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

    Write-AosStep 'Claude Code settings (merged into yours, never replaced)'
    Sync-AosClaudeSettings -DryRun:$DryRun

    Write-AosStep 'Codex profiles (~/.codex/<name>.config.toml; config.toml itself stays the app''s)'
    Sync-AosCodexProfiles -DryRun:$DryRun

    Write-AosStep 'Local model state (~\.aos\local.json, read by nar)'
    Sync-AosLocalState -DryRun:$DryRun

    Write-AosStep 'Places (shared folders and Paseo projects)'
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
    return (Join-Path ([Environment]::GetFolderPath('Desktop')) '1-Projects')
}

function Get-AosNarVenv { return (Join-Path (Get-AosStateDir) 'venvs\nar-tools') }

function Get-AosDesktopDir { return [Environment]::GetFolderPath('Desktop') }
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

function Install-AosPhone([switch]$DryRun) {
    # Paseo: its daemon runs the agents on this PC; the Paseo Android app pairs with it by QR code.
    Update-AosPath
    Write-AosStep 'Phone (Paseo daemon; state in ~\.paseo)'
    Install-AosNpmTools -Packages (Get-AosPackages)['phone_npm'] -DryRun:$DryRun
    Sync-AosPaseo -DryRun:$DryRun
    Sync-AosPaseoAutostart -DryRun:$DryRun
    # Registering the plugin needs a running daemon, started with the user's environment.
    Start-AosPaseoDaemon -DryRun:$DryRun
    Sync-AosPaseoPlugin -DryRun:$DryRun
}

function Get-AosPaseoAutostartCommand {
    # What the logon task runs: `paseo daemon start` in a hidden PowerShell. At logon it gets the user's
    # full environment, which a daemon started from inside the Claude or Codex app would not have.
    $ps = Get-Command pwsh -ErrorAction SilentlyContinue
    $exe = 'powershell.exe'
    if ($ps) { $exe = $ps.Source }
    $paseo = Join-Path (Get-AosNpmPrefix) 'paseo.cmd'
    return @{ Execute = $exe; Arguments = "-NoProfile -WindowStyle Hidden -Command `"& '$paseo' daemon start`"" }
}

function Sync-AosPaseoAutostart([switch]$DryRun) {
    # A per-user scheduled task, not a Startup-folder shortcut: the Startup folder is under AppData,
    # where a file created from inside the desktop apps can stay private to them.
    if (-not (Test-AosCommand paseo)) { return }
    $name = 'agentic-os Paseo daemon'
    $want = Get-AosPaseoAutostartCommand
    $task = Get-AosLogonTaskState $name
    if ($task) {
        $a = @($task.Actions)[0]
        $same = $a -and $a.Execute -eq $want.Execute -and $a.Arguments -eq $want.Arguments
        # Registering again repairs drift: disabled, no logon trigger for this user, battery rules.
        $healthy = $task.Enabled -eq $true -and $task.HasCurrentUserLogonTrigger -eq $true -and
            $task.DisallowStartIfOnBatteries -eq $false -and $task.StopIfGoingOnBatteries -eq $false
        if ($same -and $healthy) { Write-AosOk "logon task '$name'"; return }
    }
    if ($DryRun) { Write-AosDry "register logon task '$name': $($want.Execute) $($want.Arguments)"; return }
    try {
        Register-AosLogonTask -Name $name -Execute $want.Execute -Arguments $want.Arguments `
            -Description 'Starts the Paseo daemon at logon (agentic-os: aos install phone)'
        Write-AosOk "logon task '$name' registered"
    }
    catch { Write-AosWarn "could not register the logon task '$name': $($_.Exception.Message)" }
}

function Test-AosPaseoDaemonRunning {
    # `paseo daemon status` exits 0 whether or not the daemon runs; the text says which.
    return ((Invoke-AosCapture 'paseo daemon status').Text -match 'localDaemon:\s*running')
}

function Start-AosPaseoDaemon([switch]$DryRun) {
    # Through the logon task, never directly: a daemon started from inside the desktop apps inherits
    # their MSIX environment. Waits up to 60 s for it to report running.
    if (-not (Test-AosCommand paseo)) { return }
    $name = 'agentic-os Paseo daemon'
    if ($DryRun) { Write-AosDry "start the Paseo daemon if stopped (logon task '$name')"; return }
    if (Test-AosPaseoDaemonRunning) { Write-AosOk 'Paseo daemon running'; return }
    try { Start-AosLogonTask -Name $name }
    catch { Write-AosWarn "could not start the logon task '$name': $($_.Exception.Message)"; return }
    $waited = 0
    while ($waited -lt 60) {
        Start-Sleep -Seconds 2
        $waited += 2
        if (Test-AosPaseoDaemonRunning) { Write-AosOk 'Paseo daemon started'; return }
    }
    Write-AosWarn "the Paseo daemon did not report running within 60 s (paseo daemon status)"
}

function Get-AosLogonTaskState([string]$Name) {
    # A thin wrapper: Get-ScheduledTask is CDXML and cannot be mocked, so tests mock this.
    $t = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $t) { return $null }
    return (ConvertTo-AosLogonTaskState $t)
}

function ConvertTo-AosLogonTaskState($Task) {
    # The fields Sync-AosPaseoAutostart checks, flattened from the CIM task (Settings, Triggers).
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $mine = $false
    foreach ($t in @($Task.Triggers)) {
        if (-not $t) { continue }
        $logon = ($t.PSObject.TypeNames -join ' ') -match 'MSFT_TaskLogonTrigger'
        if ($logon -and $t.Enabled -ne $false -and ($t.UserId -ieq $me -or $t.UserId -ieq $env:USERNAME)) { $mine = $true }
    }
    return [pscustomobject]@{
        Actions = @($Task.Actions)
        Enabled = [bool]$Task.Settings.Enabled
        HasCurrentUserLogonTrigger = $mine
        DisallowStartIfOnBatteries = [bool]$Task.Settings.DisallowStartIfOnBatteries
        StopIfGoingOnBatteries = [bool]$Task.Settings.StopIfGoingOnBatteries
    }
}

function Start-AosLogonTask([string]$Name) {
    # A thin wrapper: Start-ScheduledTask is CDXML and cannot be mocked, so tests mock this.
    Start-ScheduledTask -TaskName $Name -ErrorAction Stop
}

function Register-AosLogonTask([string]$Name, [string]$Execute, [string]$Arguments, [string]$Description) {
    # A thin wrapper: the ScheduledTasks cmdlets are CDXML and cannot be mocked, so tests mock this.
    $action = New-ScheduledTaskAction -Execute $Execute -Argument $Arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    # A laptop: without these, Windows skips the task when it logs on while on battery.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $null = Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings `
        -Description $Description -Force -ErrorAction Stop
}

function Get-AosPaseoPluginDir { return (Join-Path (Get-AosProjectsDir) 'nar-tools\paseo-plugin') }

function Sync-AosPaseoPlugin([switch]$DryRun) {
    # The aos plugin (the agentic-os panel in the Paseo app) lives in nar-tools/paseo-plugin. Paseo
    # compiles it from that folder and supplies its libraries, so the folder needs no node_modules.
    if (-not (Test-AosCommand paseo)) { return }
    $dir = Get-AosPaseoPluginDir
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'paseo-plugin.json'))) { Write-AosWarn "no aos plugin at $dir (nar-tools checkout, branch with paseo-plugin/)"; return }
    $r = Invoke-AosCapture 'paseo plugin ls --json'
    if ($r.Code -ne 0) { Write-AosWarn "paseo plugin ls failed (exit $($r.Code))"; return }
    $have = $null
    # No @() here: ConvertTo-AosHashtable already returns the list whole, and 5.1 and 7 unroll
    # ConvertFrom-Json's array differently; wrapping it again hides the entries.
    $items = ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $r.Text)
    foreach ($p in $items) {
        if ($p -is [System.Collections.IDictionary] -and $p['id'] -eq 'aos') { $have = $p }
    }
    if ($have -and ([string]$have['path']).TrimEnd('\') -ieq $dir.TrimEnd('\')) { Repair-AosPaseoPlugin -Plugin $have -Dir $dir -DryRun:$DryRun; return }
    if ($DryRun) { Write-AosDry "paseo plugin install `"$dir`""; return }
    # Install first: the old registration goes only when Paseo refuses the same id twice.
    $i = Invoke-AosCapture "paseo plugin install `"$dir`""
    if ($i.Code -eq 0) { Write-AosOk "Paseo plugin aos installed from $dir"; return }
    if (-not $have -or $i.Text -notmatch 'already') { Write-AosWarn "paseo plugin install failed (exit $($i.Code)): $($i.Text)"; return }
    $old = [string]$have['path']
    $r = Invoke-AosCapture 'paseo plugin remove aos'
    if ($r.Code -ne 0) { Write-AosWarn "paseo plugin remove aos failed (exit $($r.Code)): the old registration ($old) stays"; return }
    $i = Invoke-AosCapture "paseo plugin install `"$dir`""
    if ($i.Code -eq 0) { Write-AosOk "Paseo plugin aos moved to $dir"; return }
    Write-AosWarn "paseo plugin install failed (exit $($i.Code)): $($i.Text)"
    $b = Invoke-AosCapture "paseo plugin install `"$old`""
    if ($b.Code -eq 0) { Write-AosInfo "restored the old aos plugin path ($old)" }
    else { Write-AosWarn "restoring the old aos plugin path ($old) failed (exit $($b.Code)): paseo plugin install `"$old`"" }
}

function Repair-AosPaseoPlugin($Plugin, [string]$Dir, [switch]$DryRun) {
    # Registered from the right folder: make sure it is enabled and running (a status Paseo does not
    # report counts as running).
    $off = ($Plugin['enabled'] -eq $false)
    $down = $Plugin.Contains('status') -and $Plugin['status'] -ne 'running'
    if (-not $off -and -not $down) { Write-AosOk "Paseo plugin aos ($Dir)"; return }
    if ($DryRun) { Write-AosDry "paseo plugin enable/reload aos (status $($Plugin['status']))"; return }
    if ($off) {
        $e = Invoke-AosCapture 'paseo plugin enable aos'
        if ($e.Code -ne 0) { Write-AosWarn "paseo plugin enable aos failed (exit $($e.Code))"; return }
    }
    $null = Invoke-AosCapture 'paseo plugin reload aos'
    $status = $null
    $r = Invoke-AosCapture 'paseo plugin ls --json'
    if ($r.Code -eq 0) {
        foreach ($p in (ConvertTo-AosHashtable (ConvertFrom-Json -InputObject $r.Text))) {
            if ($p -is [System.Collections.IDictionary] -and $p['id'] -eq 'aos') { $status = $p['status'] }
        }
    }
    if ($status -eq 'running') { Write-AosOk "Paseo plugin aos enabled and running ($Dir)" }
    else { Write-AosWarn "Paseo plugin aos is not running after reload (status $status): see paseo plugin ls" }
}

function Sync-AosPaseo([switch]$DryRun) {
    # The Paseo setting aos needs: plugins on (for the aos plugin). Only through Paseo's CLI, one key at a
    # time: `config get` redacts secret-like values, so aos never reads an object and writes it back.
    if (-not (Test-AosCommand paseo)) { Write-AosInfo 'paseo is not installed: skipped (aos install phone)'; return }
    $r = Invoke-AosCapture 'paseo daemon config get pluginsEnabled --json'
    if ($r.Code -ne 0) { Write-AosWarn "paseo daemon config get failed (exit $($r.Code)): plugins setting unknown"; return }
    if ($r.Text -match '"value"\s*:\s*true') { Write-AosOk 'Paseo plugins enabled'; return }
    if ($DryRun) { Write-AosDry 'paseo daemon config set pluginsEnabled true'; return }
    $cfgHome = Join-Path $HOME '.paseo'
    if ($env:PASEO_HOME) { $cfgHome = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($env:PASEO_HOME) }
    $cfgFile = Join-Path $cfgHome 'config.json'
    if (Test-Path -LiteralPath $cfgFile) { $null = Backup-AosFile $cfgFile }
    $s = Invoke-AosCapture 'paseo daemon config set pluginsEnabled true'
    if ($s.Code -eq 0) { Write-AosOk 'Paseo plugins enabled (a running daemon needs: paseo daemon restart)' }
    else { Write-AosWarn "paseo daemon config set pluginsEnabled failed (exit $($s.Code))" }
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
    # Pi on the local model, for Paseo's pi provider. aos owns providers.aos in models.json, three
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
    if ($Layer -contains 'all') { $Layer = $script:Layers }
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
            'phone'   { Install-AosPhone -DryRun:$DryRun }
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

    Write-AosStep 'MCP servers'
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
        if ($claudeList -match $pattern) { Write-AosOk "claude: $name" } else { Write-AosWarn "claude: $name not registered (aos sync)" }
        if (-not $haveCodex) { continue }
        if ($codexList -match $pattern) { Write-AosOk "codex: $name" } else { Write-AosWarn "codex: $name not registered (aos sync)" }
    }

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
    foreach ($f in @('aos.psm1', 'bootstrap.ps1', 'tests\Run-Tests.ps1')) {
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
    Write-AosInfo 'Next: fill in the Commands section of AGENTS.md, then open the folder in Claude Code or Codex.'
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
#region the aos command ------------------------------------------------------------------

function Show-AosHelp {
    Write-Host @'
aos - agentic-os control

  aos status                 what is installed, linked, logged in and in sync
  aos install [layers]       base | engines | brain | bridges | refs | local | all   (add -DryRun to preview)
  aos sync                   re-apply shared AGENTS.md, skills links, settings, Codex block, MCP
  aos update                 upgrade everything (winget, Claude Code, plugins, npm tools, refs), then sync
  aos usage                  local usage history for Claude Code and Codex
  aos test                   parse/ASCII checks + the Pester suite under PowerShell 5.1 and 7
  aos new <name>             new project in Desktop\1-Projects: AGENTS.md, CLAUDE.md (@AGENTS.md), .gitignore, git init
  aos refs                   clone/pull the reference repos in refs/repos.json (into ~\.aos\refs)
  aos secret set|get|list|remove <name>    keys encrypted to your Windows login (~\.aos\secrets)
  aos remote [folder]        let the Claude phone app start sessions here (default: Desktop); keep it open
  aos local adopt <tag>      make a model the local default, only if the latest nar eval says it is no worse
  aos nar <args>             the nar CLI from its venv in ~\.aos (long options: --option, not -o)
  aos where                  path of this repo
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
        'refs'    { Sync-AosRefs -DryRun:$DryRun }
        'secret'  { Invoke-AosSecret -Action $a1 -Name $a2 }
        'remote'  { Start-AosRemote -Dir $a1 -DryRun:$DryRun }
        'local'   { if ($a1 -eq 'adopt') { Invoke-AosLocalAdopt -Tag $a2 -DryRun:$DryRun } else { Write-AosWarn 'usage: aos local adopt <ollama tag>' } }
        'nar'     { Invoke-AosNar -Arguments @($Rest) }
        'where'   { $script:Root }
        default   { Show-AosHelp }
    }
}

#endregion

Export-ModuleMember -Function aos, Install-AosLayer, Sync-AosBrain, Get-AosStatus, Update-Aos, New-AosProject

function Get-AosPaseoProjectPaths {
    try {
        $r = Invoke-AosCapture 'paseo project ls --json'
        if ($r.Code -ne 0) { return $null }
        $parsed = ConvertFrom-Json -InputObject $r.Text -ErrorAction Stop
        $paths = New-Object 'System.Collections.Generic.List[string]'
        if ($r.Text.TrimStart() -notlike '[[]*') { return $null }
        foreach ($p in $parsed) {
            if (-not $p.path) { return $null }
            $paths.Add(([IO.Path]::GetFullPath([string]$p.path)).TrimEnd('\').ToLowerInvariant())
        }
        return ,$paths.ToArray()
    } catch { return $null }
}

function Register-AosPaseoPlace([string]$Path) {
    # Invoke the npm PowerShell shim with a literal argument, never interpolate a cmd command.
    try {
        $command = Get-Command paseo -ErrorAction Stop
        if ($command.CommandType -eq 'Application' -and $command.Source -match '\.(cmd|bat)$') {
            $shim = [IO.Path]::ChangeExtension($command.Source, '.ps1')
            if (-not (Test-Path -LiteralPath $shim)) { return $false }
            & $shim project create --json -- $Path | Out-Null
        } else { & $command project create --json -- $Path | Out-Null }
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

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
    if (-not (Test-AosCommand paseo)) { Write-AosInfo 'paseo is not installed: Places registration skipped' }
    else {
        $known = Get-AosPaseoProjectPaths
        if ($null -eq $known) { Write-AosWarn 'paseo project ls failed: Places registration skipped; local registry retained' }
        else {
            foreach ($place in $places) {
                if (-not $place.exists) { continue }
                $norm = ([string]$place.path).TrimEnd('\').ToLowerInvariant()
                if ($known -contains $norm) { continue }
                if ($DryRun) { Write-AosDry "would register Paseo project: $($place.name)"; continue }
                if (Register-AosPaseoPlace -Path $place.path) { Write-AosOk "Paseo project registered: $($place.name)"; $known += $norm }
                else { Write-AosWarn "Paseo registration failed for $($place.name)" }
            }
        }
    }
    $path = Join-Path (Get-AosStateDir) 'places.json'
    $r = Read-AosJsonOrWarn $path
    if (-not $r.Ok) { return }
    Set-AosJsonFile -Path $path -Old $r.Value -New ([ordered]@{ places = @($places) }) -Label 'shared Places registry' -DryRun:$DryRun
}
