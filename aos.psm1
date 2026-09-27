# aos.psm1 - the `aos` command: install, sync, check and update the agentic-os setup.
#
# Runs in Windows PowerShell 5.1 and PowerShell 7. Every step is idempotent: running it
# twice changes nothing the second time unless something drifted. Keep this file ASCII-only
# (Windows PowerShell 5.1 misreads BOM-less UTF-8).

$script:Root = $PSScriptRoot
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Layers = @('base', 'engines', 'brain', 'bridges', 'refs')

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

function Update-AosPath {
    # Pick up PATH entries installers just wrote to the registry, keeping this session's own.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    # Plus the two agents' own install folders, in case this terminal predates their PATH entries.
    $agentBins = @((Join-Path $HOME '.local\bin'), (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin')) |
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

function Backup-AosFile([string]$Path) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $HOME ".aos-backups\$stamp"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -LiteralPath $Path -Destination $dest -Force
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
                $backup = Join-Path $HOME (".aos-backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "\" + $item.Name)
                if ($DryRun) { Write-AosDry "would move existing $Link to $backup, then link it"; return }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
                Move-Item -LiteralPath $Link -Destination $backup
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
    # Enabled plugin ids from ~/.codex/config.toml: a [plugins."id@marketplace"] table with
    # enabled = true. A cached or disabled plugin does not count (Codex keeps both around).
    $ids = New-Object 'System.Collections.Generic.List[string]'
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

    Write-AosStep 'npm global tools'
    foreach ($n in $pkgs['npm']) {
        if (Test-AosCommand $n['name']) { Write-AosOk $n['name']; continue }
        if (-not (Test-AosCommand npm)) { Write-AosWarn "npm missing; skipped $($n['name'])"; continue }
        if ($DryRun) { Write-AosDry "npm install -g $($n['name'])   ($($n['why']))"; continue }
        npm install -g $n['name'] | Out-Host
        Update-AosPath
        if (Test-AosCommand $n['name']) { Write-AosOk "$($n['name']) installed" } else { Write-AosWarn "$($n['name']) not found after install" }
    }

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
}

function Use-AosLocalBin {
    # Make an installed-but-not-yet-on-PATH claude.exe usable in this session.
    $localBin = Join-Path $HOME '.local\bin'
    if ((Test-Path -LiteralPath (Join-Path $localBin 'claude.exe')) -and -not (Test-AosCommand claude)) { $env:Path = "$localBin;$env:Path" }
}

function Install-AosEngines([switch]$DryRun) {
    Update-AosPath
    Use-AosLocalBin
    Write-AosStep 'Claude Code CLI (native installer; updates itself)'
    if (Test-AosCommand claude) { Write-AosOk ('claude ' + (claude --version)) }
    elseif ($DryRun) { Write-AosDry 'irm https://claude.ai/install.ps1 | iex   (in a child process)' }
    else {
        powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' | Out-Host
        Update-AosPath
        Use-AosLocalBin
        if (Test-AosCommand claude) { Write-AosOk ('claude ' + (claude --version)) }
    }
    # The native installer puts claude.exe in ~\.local\bin but may leave that folder off PATH.
    $pathAdd = @(); $pathRemove = @()
    if (Test-Path -LiteralPath (Join-Path $HOME '.local\bin\claude.exe')) { $pathAdd += '%USERPROFILE%\.local\bin' }
    # A winget Codex install (no codex.exe alias without Developer Mode) leaves its folder on PATH after removal.
    $stale = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe'
    if (-not (Test-Path -LiteralPath $stale)) { $pathRemove += $stale }
    Edit-AosUserPath -Add $pathAdd -Remove $pathRemove -DryRun:$DryRun
    if (-not $DryRun -and -not (Test-AosCommand claude)) { Write-AosWarn 'claude not found after install; open a new terminal and run: claude --version' }

    Write-AosStep 'Codex CLI (official installer from releases.openai.com; updates itself; shares ~/.codex with the app)'
    if (Test-AosCommand codex) { Write-AosOk ('codex ' + (codex --version)) }
    elseif ($DryRun) { Write-AosDry 'irm https://chatgpt.com/codex/install.ps1 | iex   (in a child process)' }
    else {
        powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://chatgpt.com/codex/install.ps1 | iex' | Out-Host
        Update-AosPath
        $bin = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin'
        if (-not (Test-AosCommand codex) -and (Test-Path -LiteralPath (Join-Path $bin 'codex.exe'))) { $env:Path = "$bin;$env:Path" }
        if (Test-AosCommand codex) { Write-AosOk ('codex ' + (codex --version)) }
        else { Write-AosWarn 'codex not found after install; open a new terminal and run: codex --version' }
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

function Sync-AosMcp([switch]$DryRun) {
    # Registered = present AND pointing where the manifest says; a changed URL/command is re-added.
    $manifest = Read-AosJson (Join-Path $script:Root 'config\mcp.json')
    foreach ($name in @($manifest['servers'].Keys)) {
        $s = $manifest['servers'][$name]
        $isHttp = ($s['transport'] -eq 'http')
        $expect = $s['url']
        if (-not $isHttp) { $expect = [string]$s['command'] }
        $cmd = @()
        if (-not $isHttp) { $cmd = @($s['command']) + @($s['args']) }

        if (-not (Test-AosCommand claude)) { Write-AosWarn "claude missing; $name not registered there" }
        else {
            $got = Invoke-AosCapture "claude mcp get $name"
            $current = ($got.Code -eq 0) -and ($got.Text -match [regex]::Escape($expect))
            if ($current) { Write-AosOk "claude: $name" }
            elseif ($DryRun) { Write-AosDry "claude mcp add --scope user $name" }
            else {
                if ($got.Code -eq 0) { $null = Invoke-AosCapture "claude mcp remove $name --scope user"; Write-AosInfo "claude: $name changed; re-adding" }
                if ($isHttp) { claude mcp add --scope user --transport http $name $expect | Out-Host }
                else { claude mcp add --scope user $name -- @cmd | Out-Host }
                if ($LASTEXITCODE -eq 0) { Write-AosOk "claude: added $name" } else { Write-AosWarn "claude: adding $name failed (exit $LASTEXITCODE)" }
            }
        }

        if (-not (Test-AosCommand codex)) { Write-AosWarn "codex missing; $name not registered there" }
        else {
            $got = Invoke-AosCapture "codex mcp get $name --json"
            $current = ($got.Code -eq 0) -and ($got.Text -match [regex]::Escape($expect))
            if ($current) { Write-AosOk "codex: $name" }
            elseif ($DryRun) { Write-AosDry "codex mcp add $name" }
            else {
                if ($got.Code -eq 0) { $null = Invoke-AosCapture "codex mcp remove $name"; Write-AosInfo "codex: $name changed; re-adding" }
                if ($isHttp) { codex mcp add $name --url $expect | Out-Host }
                else { codex mcp add $name -- @cmd | Out-Host }
                if ($LASTEXITCODE -eq 0) { Write-AosOk "codex: added $name" } else { Write-AosWarn "codex: adding $name failed (exit $LASTEXITCODE)" }
            }
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
            $staged = Join-Path $HOME ('.aos-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-synced-migration')
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staged) | Out-Null
            Move-Item -LiteralPath $oldSynced -Destination $staged -ErrorAction Stop
        }
        [System.IO.Directory]::Delete($dir, $false)
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if ($staged) {
            Move-Item -LiteralPath $staged -Destination (Join-Path $dir 'synced') -ErrorAction Stop
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
            $dest = Join-Path $HOME ('.aos-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-stray-synced')
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Move-Item -LiteralPath $stray -Destination $dest
            Write-AosWarn "moved a stray copy of the Claude app's synced skills out of the repo to $dest (restart the Claude app so it stops)"
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
    # Clones live outside the repo: the repo sits in OneDrive, and clones are re-creatable.
    if ($env:AOS_REFS) { return $env:AOS_REFS }
    return (Join-Path $env:LOCALAPPDATA 'agentic-os\refs')
}

function Get-AosProjectsDir {
    if ($env:AOS_PROJECTS) { return $env:AOS_PROJECTS }
    return (Join-Path ([Environment]::GetFolderPath('Desktop')) '1-Projects')
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
    $ps7 = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($ps7 -and $ps7.Source -like '*\WindowsApps\*') { Write-AosWarn 'pwsh is the packaged (MSIX) edition: it cannot see codex/npm tools in AppData. Reinstall: winget install --id Microsoft.PowerShell -e --installer-type wix' }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py -and $py.Source -like '*\WindowsApps\*') { Write-AosWarn 'python is the Microsoft Store stub; use py, or turn off the python.exe App execution alias' }

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
    $manifest = Read-AosJson (Join-Path $root 'config\mcp.json')
    $claudeList = ''; $codexList = ''
    if (Test-AosCommand claude) { $claudeList = (Invoke-AosCapture 'claude mcp list').Text }
    if (Test-AosCommand codex) { $codexList = (Invoke-AosCapture 'codex mcp list').Text }
    foreach ($name in @($manifest['servers'].Keys)) {
        $pattern = '(?im)^\W*' + [regex]::Escape($name) + '\b'
        if ($claudeList -match $pattern) { Write-AosOk "claude: $name" } else { Write-AosWarn "claude: $name not registered (aos sync)" }
        if ($codexList -match $pattern) { Write-AosOk "codex: $name" } else { Write-AosWarn "codex: $name not registered (aos sync)" }
    }

    Write-AosStep 'Cross-vendor bridges'
    $enabled = Get-AosClaudePlugins
    foreach ($want in @('codex@openai-codex', 'superpowers@claude-plugins-official')) {
        if ($enabled -contains $want) { Write-AosOk "claude plugin: $want" } else { Write-AosWarn "claude plugin missing: $want (aos install bridges)" }
    }
    if (Test-AosCcBridge) { Write-AosOk 'codex plugin: cc-plugin-codex' } else { Write-AosWarn 'codex plugin: cc-plugin-codex not detected (aos install bridges, then $cc:setup in Codex)' }
    if (@(Get-AosCodexPlugins | Where-Object { $_ -like 'superpowers@*' }).Count -gt 0) { Write-AosOk 'codex plugin: superpowers' }
    else { Write-AosWarn 'codex plugin: superpowers not enabled (aos install bridges)' }

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
    else { powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://chatgpt.com/codex/install.ps1 | iex' | Out-Host }

    Write-AosStep 'Codex-side bridge and npm tools'
    if (Test-AosCommand npm) {
        foreach ($n in $pkgs['npm']) {
            if ($DryRun) { Write-AosDry "npm install -g $($n['name'])@latest"; continue }
            npm install -g "$($n['name'])@latest" | Out-Host
        }
        if (Test-AosCcBridge) {
            if ($DryRun) { Write-AosDry 'npx -y cc-plugin-codex@latest install' } else { npx -y cc-plugin-codex@latest install | Out-Host }
        }
    }
    Write-AosInfo 'The Codex desktop app and its plugins update through the Microsoft Store and the app itself.'

    Sync-AosRefs -DryRun:$DryRun
    Sync-AosBrain -DryRun:$DryRun
}

function Show-AosUsage {
    Write-AosStep 'Claude Code: current 5-hour block (local logs)'
    if (Test-AosCommand ccusage) { ccusage blocks --active } else { npx -y ccusage@latest blocks --active }
    Write-AosStep 'Codex: recent days (local logs)'
    npx -y '@ccusage/codex@latest' daily
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

function Initialize-AosSecretStore {
    foreach ($m in @('Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore')) {
        if (Get-Module -ListAvailable -Name $m) { continue }
        Write-AosInfo "installing $m from the PowerShell Gallery (published by Microsoft)"
        if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
            Install-PSResource -Name $m -Scope CurrentUser -TrustRepository -Quiet
        }
        else { Install-Module -Name $m -Scope CurrentUser -Repository PSGallery -Force }
    }
    Import-Module Microsoft.PowerShell.SecretManagement
    if (-not (Get-SecretVault -Name aos -ErrorAction SilentlyContinue)) {
        Register-SecretVault -Name aos -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
        # Encrypted per-user store without a password prompt, so scripts can read keys unattended.
        # It protects against the real past failure (keys in plaintext files and backups), not
        # against malware running as you.
        Set-SecretStoreConfiguration -Scope CurrentUser -Authentication None -Interaction None -Confirm:$false
        Write-AosOk 'created the aos vault'
    }
}

function Invoke-AosSecret([string]$Action, [string]$Name) {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        if (-not (Test-AosCommand pwsh)) { Write-AosWarn 'aos secret needs PowerShell 7 (install the base layer)'; return }
        $module = (Join-Path $script:Root 'aos.psm1').Replace("'", "''")
        pwsh -NoProfile -Command "Import-Module '$module' -DisableNameChecking; aos secret '$Action' '$Name'"
        return
    }
    if (@('set', 'get', 'list', 'remove') -notcontains $Action) { Write-AosWarn 'usage: aos secret set|get|list|remove <name>'; return }
    if ($Action -ne 'list' -and -not $Name) { Write-AosWarn "usage: aos secret $Action <name>"; return }
    Initialize-AosSecretStore
    switch ($Action) {
        'set' {
            $value = Read-Host "Value for '$Name' (input hidden)" -AsSecureString
            Set-Secret -Name $Name -SecureStringSecret $value -Vault aos
            Write-AosOk "stored $Name"
        }
        'get'    { Get-Secret -Name $Name -Vault aos -AsPlainText }
        'list'   { Get-SecretInfo -Vault aos | Select-Object -ExpandProperty Name }
        'remove' { Remove-Secret -Name $Name -Vault aos; Write-AosOk "removed $Name" }
    }
}

#endregion
#region the aos command ------------------------------------------------------------------

function Show-AosHelp {
    Write-Host @'
aos - agentic-os control

  aos status                 what is installed, linked, logged in and in sync
  aos install [layers]       base | engines | brain | bridges | refs | all   (add -DryRun to preview)
  aos sync                   re-apply shared AGENTS.md, skills links, settings, Codex block, MCP
  aos update                 upgrade everything (winget, Claude Code, plugins, npm tools, refs), then sync
  aos usage                  local usage history for Claude Code and Codex
  aos new <name>             new project in Desktop\1-Projects: AGENTS.md, CLAUDE.md (@AGENTS.md), .gitignore, git init
  aos refs                   clone/pull the reference repos in refs/repos.json (into %LOCALAPPDATA%\agentic-os\refs)
  aos secret set|get|list|remove <name>    Windows secret store (PowerShell 7)
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
        'new'     { New-AosProject -Path $a1 }
        'refs'    { Sync-AosRefs -DryRun:$DryRun }
        'secret'  { Invoke-AosSecret -Action $a1 -Name $a2 }
        'where'   { $script:Root }
        default   { Show-AosHelp }
    }
}

#endregion

Export-ModuleMember -Function aos, Install-AosLayer, Sync-AosBrain, Get-AosStatus, Update-Aos, New-AosProject
