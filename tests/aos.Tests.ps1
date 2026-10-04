Describe 'aos isolated suite' {
# Run with tests/Run-Tests.ps1 (Pester 5.5+); all filesystem fixtures are disposable.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking

    # Fail closed if someone bypasses the runner without redirecting backups.
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    $backupRoot = [System.IO.Path]::GetFullPath($env:AOS_BACKUPS).TrimEnd('\')
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $backupRoot.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'AOS_BACKUPS must be a child of the temporary directory for these tests.'
    }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    function New-TestFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }

    function Write-TestFile([string]$Path, [string]$Text) {
        New-TestFolder (Split-Path -Parent $Path) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }

    function Assert-TestJunction([string]$Link, [string]$Target) {
        $item = Get-Item -LiteralPath $Link -Force -ErrorAction Stop
        $item.LinkType | Should -Be 'Junction'
        [System.IO.Path]::GetFullPath(@($item.Target)[0]).TrimEnd('\') |
            Should -Be ([System.IO.Path]::GetFullPath($Target).TrimEnd('\'))
    }

    function Get-TestTreeState([string]$Root) {
        # Do not traverse junctions, including dangling links. Include timestamps so an
        # unnecessary rewrite/relink is observable even when the content is identical.
        if (-not (Test-Path -LiteralPath $Root)) { return '<missing>' }
        $pending = New-Object System.Collections.Stack
        $pending.Push($Root)
        $rows = @()
        while ($pending.Count -gt 0) {
            $dir = [string]$pending.Pop()
            foreach ($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)) {
                # Directory enumeration can return stale NTFS timestamps.
                $item.Refresh()
                $body = ''
                if ($item.LinkType) { $body = @($item.Target) -join '|' }
                elseif ($item.PSIsContainer) { $pending.Push($item.FullName) }
                else { $body = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($item.FullName)) }
                $rows += [pscustomobject][ordered]@{
                    Path = $item.FullName.Substring($Root.TrimEnd('\').Length)
                    Attributes = [string]$item.Attributes
                    Created = $item.CreationTimeUtc.Ticks
                    Written = $item.LastWriteTimeUtc.Ticks
                    Body = $body
                }
            }
        }
        return (ConvertTo-Json -InputObject @($rows | Sort-Object Path) -Depth 10 -Compress)
    }

    function Remove-TestJunctions([string]$Root) {
        # Pester's eventual recursive TestDrive cleanup must never follow our links.
        $pending = New-Object System.Collections.Stack
        $pending.Push($Root)
        while ($pending.Count -gt 0) {
            foreach ($item in @(Get-ChildItem -LiteralPath ([string]$pending.Pop()) -Force -ErrorAction Stop)) {
                if ($item.LinkType) { [System.IO.Directory]::Delete($item.FullName, $false) }
                elseif ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
    }
}

BeforeEach {
    $caseRoot = New-TestFolder (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
    # These defaults prevent accidental PATH refreshes, CLI execution or profile reads.
    Mock Update-AosPath -ModuleName aos { }
    Mock Test-AosCommand -ModuleName aos { return $false }
    Mock Invoke-AosCapture -ModuleName aos { throw 'Unexpected external command in a test.' }
    Mock Get-AosCodexConfigText -ModuleName aos { throw 'Unexpected config read in a test.' }
}

AfterEach {
    Remove-TestJunctions -Root $TestDrive
}

Describe 'ConvertTo-AosHashtable' {
    It 'converts nested PSCustomObjects to ordered dictionaries without splitting strings' {
        InModuleScope aos {
            $value = [pscustomobject][ordered]@{
                Text = 'a string with spaces'
                Child = [pscustomobject][ordered]@{ First = 1; Second = 'two' }
            }
            $actual = ConvertTo-AosHashtable -Value $value
            ($actual -is [System.Collections.Specialized.OrderedDictionary]) | Should -BeTrue
            ($actual.Child -is [System.Collections.Specialized.OrderedDictionary]) | Should -BeTrue
            (@($actual.Keys) -join ',') | Should -Be 'Text,Child'
            (@($actual.Child.Keys) -join ',') | Should -Be 'First,Second'
            $actual.Child.First | Should -Be 1
            $actual.Text | Should -BeExactly 'a string with spaces'
            ($actual.Text -is [string]) | Should -BeTrue
            (ConvertTo-AosHashtable -Value 'abc') | Should -BeExactly 'abc'
        }
    }

    It 'preserves multiple, single and empty arrays at the root and inside objects' {
        InModuleScope aos {
            foreach ($values in @(@('one', 'two'), @('only'), @())) {
                $actual = ConvertTo-AosHashtable -Value $values
                ($actual -is [array]) | Should -BeTrue
                $actual.Count | Should -Be $values.Count
                (ConvertTo-Json -InputObject $actual -Compress) |
                    Should -BeExactly (ConvertTo-Json -InputObject $values -Compress)
            }
            $actual = ConvertTo-AosHashtable -Value ([pscustomobject]@{
                Many = @('a', 'b'); Single = @('one'); Empty = @()
                Objects = @([pscustomobject]@{ Name = 'nested' })
            })
            ($actual.Many -is [array]) | Should -BeTrue
            $actual.Many.Count | Should -Be 2
            ($actual.Single -is [array]) | Should -BeTrue
            $actual.Single.Count | Should -Be 1
            $actual.Single[0] | Should -Be 'one'
            ($actual.Empty -is [array]) | Should -BeTrue
            $actual.Empty.Count | Should -Be 0
            ($actual.Objects -is [array]) | Should -BeTrue
            ($actual.Objects[0] -is [System.Collections.Specialized.OrderedDictionary]) | Should -BeTrue
            $actual.Objects[0].Name | Should -Be 'nested'
        }
    }
}

Describe 'Merge-AosTree' {
    It 'lets overlay scalars win while recursively merging dictionaries and retaining base-only keys' {
        InModuleScope aos {
            $base = [ordered]@{ Scalar = 'old'; Keep = 42; Nested = [ordered]@{ Keep = 1; Change = 2 } }
            $overlay = [ordered]@{ Scalar = 'new'; Nested = [ordered]@{ Change = 3; Added = 4 } }
            Merge-AosTree -Base $base -Overlay $overlay
            $base.Scalar | Should -Be 'new'
            $base.Keep | Should -Be 42
            $base.Nested.Keep | Should -Be 1
            $base.Nested.Change | Should -Be 3
            $base.Nested.Added | Should -Be 4
        }
    }

    It 'unions string and object arrays without duplicates and produces identical JSON on a second merge' {
        InModuleScope aos {
            $base = [ordered]@{
                Strings = @('a', 'a', 'b')
                Objects = @([ordered]@{ Name = 'one'; Value = 1 })
                Nested = [ordered]@{ Keep = 'base'; Change = 'old' }
            }
            $overlay = [ordered]@{
                Strings = @('b', 'c', 'c')
                Objects = @([ordered]@{ Name = 'one'; Value = 1 }, [ordered]@{ Name = 'two'; Value = 2 })
                Nested = [ordered]@{ Change = 'new' }
            }
            Merge-AosTree -Base $base -Overlay $overlay
            ($base.Strings -is [array]) | Should -BeTrue
            ($base.Strings -join ',') | Should -Be 'a,b,c'
            ($base.Objects -is [array]) | Should -BeTrue
            $base.Objects.Count | Should -Be 2
            $base.Objects[0].Name | Should -Be 'one'
            $base.Objects[0].Value | Should -Be 1
            $base.Objects[1].Name | Should -Be 'two'
            $base.Objects[1].Value | Should -Be 2
            $once = ConvertTo-Json -InputObject $base -Depth 20 -Compress
            Merge-AosTree -Base $base -Overlay $overlay
            (ConvertTo-Json -InputObject $base -Depth 20 -Compress) | Should -BeExactly $once
        }
    }
}

Describe 'Set-AosManagedBlock' {
    It 'creates a missing file with the block at <Position>' -ForEach @(
        @{ Position = 'Top' }, @{ Position = 'Bottom' }
    ) {
        $path = Join-Path $caseRoot 'nested\managed.txt'
        InModuleScope aos -Parameters @{ Path = $path; Position = $Position } {
            param($Path, $Position)
            Set-AosManagedBlock -Path $Path -Start '# start' -End '# end' -Body 'body' -Position $Position
        }
        [System.IO.File]::ReadAllText($path) | Should -BeExactly "# start`nbody`n# end`n"
    }

    It 'inserts a new block at <Position> while keeping existing text' -ForEach @(
        @{ Position = 'Top'; Expected = "# start`nbody`n# end`n`nexisting" },
        @{ Position = 'Bottom'; Expected = "existing`n`n# start`nbody`n# end`n" }
    ) {
        $path = Join-Path $caseRoot 'managed.txt'
        Write-TestFile $path 'existing'
        InModuleScope aos -Parameters @{ Path = $path; Position = $Position } {
            param($Path, $Position)
            Set-AosManagedBlock -Path $Path -Start '# start' -End '# end' -Body 'body' -Position $Position
        }
        [System.IO.File]::ReadAllText($path) | Should -BeExactly $Expected
    }

    It 'replaces a block in place, preserves surrounding text and is byte-identical on a second call' {
        $path = Join-Path $caseRoot 'managed.txt'
        Write-TestFile $path "before`r`n# [start]`nold`n# [end]`r`nafter"
        InModuleScope aos -Parameters @{ Path = $path } {
            param($Path)
            Set-AosManagedBlock -Path $Path -Start '# [start]' -End '# [end]' -Body 'literal $1 and $HOME' -Position Top
        }
        [System.IO.File]::ReadAllText($path) |
            Should -BeExactly ("before`r`n# [start]`n" + 'literal $1 and $HOME' + "`n# [end]`r`nafter")
        $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
        $written = (Get-Item -LiteralPath $path).LastWriteTimeUtc
        InModuleScope aos -Parameters @{ Path = $path } {
            param($Path)
            Set-AosManagedBlock -Path $Path -Start '# [start]' -End '# [end]' -Body 'literal $1 and $HOME' -Position Top
        }
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path)) | Should -BeExactly $before
        (Get-Item -LiteralPath $path).LastWriteTimeUtc | Should -Be $written
    }

    It 'writes UTF-8 without a BOM by default and with a BOM when requested' {
        $plain = Join-Path $caseRoot 'plain.txt'
        $bom = Join-Path $caseRoot 'bom.txt'
        InModuleScope aos -Parameters @{ Plain = $plain; BomPath = $bom } {
            param($Plain, $BomPath)
            Set-AosManagedBlock -Path $Plain -Start '# start' -End '# end' -Body 'body'
            Set-AosManagedBlock -Path $BomPath -Start '# start' -End '# end' -Body 'body' -Bom
        }
        $plainBytes = [System.IO.File]::ReadAllBytes($plain)
        $bomBytes = [System.IO.File]::ReadAllBytes($bom)
        [BitConverter]::ToString($plainBytes, 0, 3) | Should -Not -Be 'EF-BB-BF'
        [BitConverter]::ToString($bomBytes, 0, 3) | Should -Be 'EF-BB-BF'
        [System.IO.File]::ReadAllText($plain) | Should -BeExactly ([System.IO.File]::ReadAllText($bom))
    }

    It 'leaves existing files byte-identical and missing files absent during DryRun' {
        $path = Join-Path $caseRoot 'existing.txt'
        $missing = Join-Path $caseRoot 'missing\file.txt'
        Write-TestFile $path "# start`nold`n# end`n"
        $before = Get-TestTreeState $caseRoot
        InModuleScope aos -Parameters @{ Path = $path; Missing = $missing } {
            param($Path, $Missing)
            Set-AosManagedBlock -Path $Path -Start '# start' -End '# end' -Body 'new' -DryRun
            Set-AosManagedBlock -Path $Missing -Start '# start' -End '# end' -Body 'new' -DryRun
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        Test-Path -LiteralPath $missing | Should -BeFalse
    }
}

Describe 'Move-AosItem' {
    It 'moves a folder with its contents and returns true' {
        $source = New-TestFolder (Join-Path $caseRoot 'source')
        $destination = Join-Path $caseRoot 'destination'
        Write-TestFile (Join-Path $source 'nested\data.txt') 'keep me'
        InModuleScope aos -Parameters @{ Source = $source; Destination = $destination } {
            param($Source, $Destination)
            Move-AosItem -Source $Source -Destination $Destination | Should -BeTrue
        }
        Test-Path -LiteralPath $source | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $destination 'nested\data.txt')) | Should -Be 'keep me'
    }

    It 'returns false without throwing when the source is missing' {
        InModuleScope aos -Parameters @{ Root = $caseRoot } {
            param($Root)
            $source = Join-Path $Root 'missing'
            $destination = Join-Path $Root 'destination'
            Move-AosItem -Source $source -Destination $destination | Should -BeFalse
            Test-Path -LiteralPath $destination | Should -BeFalse
        }
    }

    It 'returns false and changes nothing when the destination already exists' {
        $source = New-TestFolder (Join-Path $caseRoot 'source')
        $destination = New-TestFolder (Join-Path $caseRoot 'destination')
        Write-TestFile (Join-Path $source 'source.txt') 'source'
        Write-TestFile (Join-Path $destination 'destination.txt') 'destination'
        $before = Get-TestTreeState $caseRoot
        InModuleScope aos -Parameters @{ Source = $source; Destination = $destination } {
            param($Source, $Destination)
            Move-AosItem -Source $Source -Destination $Destination | Should -BeFalse
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
    }

    It 'returns false and preserves the source when a contained file is exclusively open' {
        $source = New-TestFolder (Join-Path $caseRoot 'source')
        $destination = Join-Path $caseRoot 'destination'
        $file = Join-Path $source 'locked.txt'
        Write-TestFile $file 'locked content'
        $handle = [System.IO.File]::Open($file, 'Open', 'Read', 'None')
        try {
            InModuleScope aos -Parameters @{ Source = $source; Destination = $destination } {
                param($Source, $Destination)
                Move-AosItem -Source $Source -Destination $Destination | Should -BeFalse
            }
            Test-Path -LiteralPath $source | Should -BeTrue
            Test-Path -LiteralPath $file | Should -BeTrue
            Test-Path -LiteralPath $destination | Should -BeFalse
        }
        finally { $handle.Dispose() }
        [System.IO.File]::ReadAllText($file) | Should -Be 'locked content'
    }
}

Describe 'New-AosBackupPath' {
    It 'uses AOS_BACKUPS, leaves the leaf uncreated and avoids an existing same-second path' {
        # Freeze only the timestamp lookup, making the collision deterministic.
        Mock Get-Date -ModuleName aos { '20000101-000000' } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
        InModuleScope aos -Parameters @{ Label = ('-' + [guid]::NewGuid().ToString('N')) } {
            param($Label)
            $first = New-AosBackupPath -Label $Label
            (Split-Path -Parent $first) | Should -Be ([System.IO.Path]::GetFullPath($env:AOS_BACKUPS).TrimEnd('\'))
            Test-Path -LiteralPath $first | Should -BeFalse
            New-Item -ItemType Directory -Path $first | Out-Null
            $second = New-AosBackupPath -Label $Label
            $second | Should -Not -Be $first
            (Split-Path -Parent $second) | Should -Be (Split-Path -Parent $first)
            (Split-Path -Leaf $second) | Should -Be ('20000101-000000' + $Label + '-2')
            Test-Path -LiteralPath $second | Should -BeFalse
        }
    }
}

Describe 'Set-AosJunction' {
    It 'creates a junction and makes a second call a no-op' {
        $target = New-TestFolder (Join-Path $caseRoot 'target')
        $link = Join-Path $caseRoot 'links\skill'
        Write-TestFile (Join-Path $target 'data.txt') 'target content'
        InModuleScope aos -Parameters @{ Link = $link; Target = $target } {
            param($Link, $Target)
            Set-AosJunction -Link $Link -Target $Target
        }
        Assert-TestJunction $link $target
        $before = Get-TestTreeState $caseRoot
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{ Link = $link; Target = $target } {
            param($Link, $Target)
            Set-AosJunction -Link $Link -Target $Target
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }

    It 'repoints a junction without altering either target' {
        $old = New-TestFolder (Join-Path $caseRoot 'old')
        $target = New-TestFolder (Join-Path $caseRoot 'new')
        $link = Join-Path $caseRoot 'link'
        Write-TestFile (Join-Path $old 'data.txt') 'old content'
        Write-TestFile (Join-Path $target 'data.txt') 'new content'
        New-Item -ItemType Junction -Path $link -Target $old | Out-Null
        InModuleScope aos -Parameters @{ Link = $link; Target = $target } {
            param($Link, $Target)
            Set-AosJunction -Link $Link -Target $Target
        }
        Assert-TestJunction $link $target
        [System.IO.File]::ReadAllText((Join-Path $old 'data.txt')) | Should -Be 'old content'
        [System.IO.File]::ReadAllText((Join-Path $target 'data.txt')) | Should -Be 'new content'
    }

    It 'replaces an empty folder with a junction without creating a backup' {
        $target = New-TestFolder (Join-Path $caseRoot 'target')
        $link = New-TestFolder (Join-Path $caseRoot 'link')
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{ Link = $link; Target = $target } {
            param($Link, $Target)
            Set-AosJunction -Link $Link -Target $Target
        }
        Assert-TestJunction $link $target
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }

    It 'backs up a non-empty folder under AOS_BACKUPS with all files intact before linking' {
        $target = New-TestFolder (Join-Path $caseRoot 'target')
        $link = New-TestFolder (Join-Path $caseRoot 'link')
        $marker = [guid]::NewGuid().ToString('N') + '.txt'
        Write-TestFile (Join-Path $link $marker) 'original content'
        Write-TestFile (Join-Path $link 'nested\other.txt') 'nested content'
        InModuleScope aos -Parameters @{ Link = $link; Target = $target } {
            param($Link, $Target)
            Set-AosJunction -Link $Link -Target $Target
        }
        Assert-TestJunction $link $target
        $saved = @(Get-ChildItem -LiteralPath $env:AOS_BACKUPS -Recurse -File -Filter $marker)
        $saved.Count | Should -Be 1
        $saved[0].FullName.StartsWith($env:AOS_BACKUPS.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        [System.IO.File]::ReadAllText($saved[0].FullName) | Should -Be 'original content'
        [System.IO.File]::ReadAllText((Join-Path $saved[0].DirectoryName 'nested\other.txt')) | Should -Be 'nested content'
        @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
    }

    It 'changes nothing in DryRun for absent links, existing junctions and empty or non-empty folders' {
        $target = New-TestFolder (Join-Path $caseRoot 'target')
        $old = New-TestFolder (Join-Path $caseRoot 'old')
        $junction = Join-Path $caseRoot 'junction'
        New-Item -ItemType Junction -Path $junction -Target $old | Out-Null
        $empty = New-TestFolder (Join-Path $caseRoot 'empty')
        $full = New-TestFolder (Join-Path $caseRoot 'full')
        Write-TestFile (Join-Path $full 'data.txt') 'keep'
        $before = Get-TestTreeState $caseRoot
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{
            Links = @((Join-Path $caseRoot 'missing\link'), $junction, $empty, $full); Target = $target
        } {
            param($Links, $Target)
            foreach ($link in $Links) { Set-AosJunction -Link $link -Target $Target -DryRun }
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }
}

Describe 'Sync-AosClaudeSkills' {
    BeforeEach {
        $repoSkills = New-TestFolder (Join-Path $caseRoot 'new-checkout\agents-home\skills')
        $dir = Join-Path $caseRoot 'claude-skills'
        Write-TestFile (Join-Path $repoSkills 'alpha\SKILL.md') 'new alpha'
        Write-TestFile (Join-Path $repoSkills 'beta\SKILL.md') 'new beta'
    }

    It 'migrates the old checkout junction, taking synced from the old target and linking new repo skills' {
        $old = New-TestFolder (Join-Path $caseRoot 'old-checkout\agents-home\skills')
        Write-TestFile (Join-Path $old 'synced\account\SKILL.md') 'OLD account skill'
        Write-TestFile (Join-Path $old 'alpha\SKILL.md') 'old alpha'
        Write-TestFile (Join-Path $repoSkills 'synced\account\SKILL.md') 'NEW stray account skill'
        New-Item -ItemType Junction -Path $dir -Target $old | Out-Null
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills
        }
        (Get-Item -LiteralPath $dir -Force).LinkType | Should -BeNullOrEmpty
        (Get-Item -LiteralPath $dir).PSIsContainer | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $dir 'synced\account\SKILL.md')) | Should -Be 'OLD account skill'
        Test-Path -LiteralPath (Join-Path $old 'synced') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $old 'alpha\SKILL.md')) | Should -Be 'old alpha'
        Assert-TestJunction (Join-Path $dir 'alpha') (Join-Path $repoSkills 'alpha')
        Assert-TestJunction (Join-Path $dir 'beta') (Join-Path $repoSkills 'beta')
        Test-Path -LiteralPath (Join-Path $repoSkills 'synced') | Should -BeFalse
    }

    It 'leaves a user junction alone when its target does not end in agents-home\skills' {
        $personal = New-TestFolder (Join-Path $caseRoot 'personal-skills')
        Write-TestFile (Join-Path $personal 'synced\keep.txt') 'personal'
        New-Item -ItemType Junction -Path $dir -Target $personal | Out-Null
        $before = Get-TestTreeState $caseRoot
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills
        }
        Assert-TestJunction $dir $personal
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }

    It 'removes a per-skill link after its repo skill moves away while preserving the moved folder' {
        New-TestFolder $dir | Out-Null
        $skill = Join-Path $repoSkills 'retired'
        Write-TestFile (Join-Path $skill 'SKILL.md') 'retired skill'
        Write-TestFile (Join-Path $skill 'data.txt') 'valuable data'
        $link = Join-Path $dir 'retired'
        New-Item -ItemType Junction -Path $link -Target $skill | Out-Null
        $moved = Join-Path $caseRoot 'moved-away'
        [System.IO.Directory]::Move($skill, $moved)
        $before = Get-TestTreeState $moved
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills
        }
        # Enumerate the parent: Test-Path alone can report false for a dangling link.
        @(Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -eq 'retired' }).Count | Should -Be 0
        (Get-TestTreeState $moved) | Should -BeExactly $before
        [System.IO.File]::ReadAllText((Join-Path $moved 'data.txt')) | Should -Be 'valuable data'
    }

    It 'moves a stray repo synced folder under AOS_BACKUPS and preserves the real app folder' {
        $marker = [guid]::NewGuid().ToString('N') + '.txt'
        Write-TestFile (Join-Path $repoSkills ('synced\nested\' + $marker)) 'stray content'
        Write-TestFile (Join-Path $dir 'synced\keep.txt') 'app content'
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills
        }
        Test-Path -LiteralPath (Join-Path $repoSkills 'synced') | Should -BeFalse
        $saved = @(Get-ChildItem -LiteralPath $env:AOS_BACKUPS -Recurse -File -Filter $marker)
        $saved.Count | Should -Be 1
        $saved[0].FullName.StartsWith($env:AOS_BACKUPS.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        [System.IO.File]::ReadAllText($saved[0].FullName) | Should -Be 'stray content'
        [System.IO.File]::ReadAllText((Join-Path $dir 'synced\keep.txt')) | Should -Be 'app content'
    }

    It 'reports could not move, never moved a stray copy, when a stray synced file is locked' {
        New-TestFolder $dir | Out-Null
        $stray = Join-Path $repoSkills 'synced'
        $file = Join-Path $stray 'locked.txt'
        Write-TestFile $file 'locked stray content'
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        $handle = [System.IO.File]::Open($file, 'Open', 'Read', 'None')
        try {
            $output = InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
                param($Dir, $RepoSkills)
                Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills *>&1 | Out-String
            }
            $output | Should -Match 'could not move'
            $output | Should -Not -Match 'moved a stray copy'
            Test-Path -LiteralPath $stray | Should -BeTrue
            Test-Path -LiteralPath $file | Should -BeTrue
        }
        finally { $handle.Dispose() }
        [System.IO.File]::ReadAllText($file) | Should -Be 'locked stray content'
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }

    It 'changes neither the skills tree nor backups on a second run' {
        Write-TestFile (Join-Path $dir 'synced\keep.txt') 'app content'
        Write-TestFile (Join-Path $repoSkills 'synced\stray.txt') 'stray content'
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills
        }
        Assert-TestJunction (Join-Path $dir 'alpha') (Join-Path $repoSkills 'alpha')
        Assert-TestJunction (Join-Path $dir 'beta') (Join-Path $repoSkills 'beta')
        $before = Get-TestTreeState $caseRoot
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }

    It 'leaves the old layout and its synced content unchanged in DryRun' {
        $old = New-TestFolder (Join-Path $caseRoot 'old\agents-home\skills')
        Write-TestFile (Join-Path $old 'synced\keep.txt') 'old app content'
        New-Item -ItemType Junction -Path $dir -Target $old | Out-Null
        $before = Get-TestTreeState $caseRoot
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills -DryRun
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }

    It 'does not create a missing Dir, move a stray copy or remove stale links in DryRun' {
        Write-TestFile (Join-Path $repoSkills 'synced\keep.txt') 'stray'
        $before = Get-TestTreeState $caseRoot
        $backups = Get-TestTreeState $env:AOS_BACKUPS
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills -DryRun
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        Test-Path -LiteralPath $dir | Should -BeFalse
        New-TestFolder $dir | Out-Null
        $retired = New-TestFolder (Join-Path $repoSkills 'retired')
        New-Item -ItemType Junction -Path (Join-Path $dir 'retired') -Target $retired | Out-Null
        $before = Get-TestTreeState $caseRoot
        InModuleScope aos -Parameters @{ Dir = $dir; RepoSkills = $repoSkills } {
            param($Dir, $RepoSkills)
            Sync-AosClaudeSkills -Dir $Dir -RepoSkills $RepoSkills -DryRun
        }
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
        (Get-TestTreeState $env:AOS_BACKUPS) | Should -BeExactly $backups
    }
}

Describe 'Get-AosCodexPlugins' {
    It 'returns only installed, enabled ids from a successful CLI listing' {
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'codex' }
        Mock Invoke-AosCapture -ModuleName aos {
            [pscustomobject]@{ Code = 0; Text = @'
Plugins:
  cc@sendbird installed, enabled
  superpowers@openai-curated-remote installed, enabled
  disabled@example installed, disabled
  cached@example cached, enabled
  available@example not installed, enabled
  bare-name installed, enabled
'@ }
        } -ParameterFilter { $CommandLine -eq 'codex plugin list' }
        InModuleScope aos {
            $actual = Get-AosCodexPlugins
            $actual.Count | Should -Be 2
            $actual | Should -Contain 'cc@sendbird'
            $actual | Should -Contain 'superpowers@openai-curated-remote'
        }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'codex plugin list' }
        Should -Invoke Get-AosCodexConfigText -ModuleName aos -Times 0 -Exactly
    }

    It 'falls back after CLI failure and reads enabled only within each plugin table' {
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'codex' }
        Mock Invoke-AosCapture -ModuleName aos {
            [pscustomobject]@{ Code = 1; Text = 'misleading@example installed, enabled' }
        } -ParameterFilter { $CommandLine -eq 'codex plugin list' }
        Mock Get-AosCodexConfigText -ModuleName aos {
            @'
enabled = true
[plugins."cc@sendbird"]
enabled = true
[plugins."disabled@example"]
enabled = false
[plugins."missing@example"]
path = "cached"
[other]
enabled = true
[plugins."commented@example"]
# enabled = true
[plugins."quoted@example"]
enabled = "true"
[plugins."second@example"]
  enabled = true # enabled deliberately
'@
        }
        InModuleScope aos {
            $actual = Get-AosCodexPlugins
            $actual.Count | Should -Be 2
            $actual | Should -Contain 'cc@sendbird'
            $actual | Should -Contain 'second@example'
        }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'codex plugin list' }
        Should -Invoke Get-AosCodexConfigText -ModuleName aos -Times 1 -Exactly
    }

    It 'uses config without invoking the CLI when codex is unavailable' {
        Mock Get-AosCodexConfigText -ModuleName aos { "[plugins.`"local@example`"]`nenabled = true`n" }
        InModuleScope aos {
            $actual = Get-AosCodexPlugins
            $actual.Count | Should -Be 1
            $actual[0] | Should -Be 'local@example'
        }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Test-AosCcBridge' {
    It 'returns true when cc@sendbird is enabled' {
        Mock Get-AosCodexPlugins -ModuleName aos { return ,@('cc@sendbird') }
        InModuleScope aos { Test-AosCcBridge | Should -BeTrue }
    }

    It 'returns false for unrelated enabled plugins' {
        Mock Get-AosCodexPlugins -ModuleName aos { return ,@('superpowers@openai-curated-remote') }
        InModuleScope aos { Test-AosCcBridge | Should -BeFalse }
    }

    It 'returns false when no plugins are enabled' {
        Mock Get-AosCodexPlugins -ModuleName aos { return ,@() }
        InModuleScope aos { Test-AosCcBridge | Should -BeFalse }
    }
}

Describe 'New-AosProject' {
    BeforeEach { Mock Add-AosPlace -ModuleName aos { $true } }
    It 'creates all four template files, maps underscore names and substitutes the folder name' {
        $project = Join-Path $caseRoot 'project with spaces'
        New-AosProject -Path $project
        $templates = Join-Path $PSScriptRoot '..\templates\project'
        foreach ($entry in @(
            @{ Source = 'AGENTS.md'; Target = 'AGENTS.md' },
            @{ Source = 'CLAUDE.md'; Target = 'CLAUDE.md' },
            @{ Source = '_gitignore'; Target = '.gitignore' },
            @{ Source = '_gitattributes'; Target = '.gitattributes' }
        )) {
            $expected = [System.IO.File]::ReadAllText((Join-Path $templates $entry.Source)).Replace('{{name}}', 'project with spaces')
            [System.IO.File]::ReadAllText((Join-Path $project $entry.Target)) | Should -BeExactly $expected
        }
        [System.IO.File]::ReadAllText((Join-Path $project 'AGENTS.md')) | Should -Match '(?m)^# project with spaces\r?$'
        Test-Path -LiteralPath (Join-Path $project '_gitignore') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $project '_gitattributes') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $project '.git') | Should -BeFalse
        Should -Invoke Update-AosPath -ModuleName aos -Times 1 -Exactly
        Should -Invoke Test-AosCommand -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Name -eq 'git' }
    }

    It 'keeps an existing AGENTS.md byte-identical while creating the other files' {
        $project = New-TestFolder (Join-Path $caseRoot 'existing-project')
        $agents = Join-Path $project 'AGENTS.md'
        Write-TestFile $agents "My instructions`r`nKeep {{name}} literally.`r`n"
        $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agents))
        $written = (Get-Item -LiteralPath $agents).LastWriteTimeUtc
        New-AosProject -Path $project
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agents)) | Should -BeExactly $before
        (Get-Item -LiteralPath $agents).LastWriteTimeUtc | Should -Be $written
        foreach ($name in @('CLAUDE.md', '.gitignore', '.gitattributes')) {
            Test-Path -LiteralPath (Join-Path $project $name) | Should -BeTrue
        }
    }

    It 'initializes a git repository when git is available' {
        if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not installed; template tests still run.'
            return
        }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'git' }
        $project = Join-Path $caseRoot 'git-project'
        New-AosProject -Path $project
        Test-Path -LiteralPath (Join-Path $project '.git\HEAD') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $project '.git\config') | Should -BeTrue
        Should -Invoke Update-AosPath -ModuleName aos -Times 1 -Exactly
        Should -Invoke Test-AosCommand -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Name -eq 'git' }
    }
}

Describe 'New-AosVideo' {
    BeforeEach {
        Mock Add-AosPlace -ModuleName aos { $true }
        $savedVideo = @{ P = $env:AOS_PROJECTS; V = $env:AOS_VIDEO_HOME; M = $env:AOS_REMOTION_MODULES }
        $env:AOS_PROJECTS = New-TestFolder (Join-Path $caseRoot 'projects')
        $env:AOS_VIDEO_HOME = Join-Path $caseRoot 'media'
        $env:AOS_REMOTION_MODULES = New-TestFolder (Join-Path $caseRoot 'shared\node_modules')
    }
    AfterEach {
        $env:AOS_PROJECTS = $savedVideo.P; $env:AOS_VIDEO_HOME = $savedVideo.V; $env:AOS_REMOTION_MODULES = $savedVideo.M
    }

    It 'copies the whole video template with the name substituted, plus the project files' {
        New-AosVideo -Name 'align-1'
        $project = Join-Path $env:AOS_PROJECTS 'videos\align-1'
        $templates = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\templates\video'))
        foreach ($f in Get-ChildItem -LiteralPath $templates -File -Recurse -Force) {
            $rel = $f.FullName.Substring($templates.Length).TrimStart('\')
            if ((Split-Path -Leaf $rel).StartsWith('_')) { continue }
            $expected = [System.IO.File]::ReadAllText($f.FullName).Replace('{{name}}', 'align-1')
            [System.IO.File]::ReadAllText((Join-Path $project $rel)) | Should -BeExactly $expected
        }
        [System.IO.File]::ReadAllText((Join-Path $project '.gitignore')) | Should -Match '(?m)^\*\.mp4\r?$'
        Test-Path -LiteralPath (Join-Path $project '.gitattributes') | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $project 'AGENTS.md')) | Should -Match '(?m)^# align-1 \(video\)\r?$'
        [System.IO.File]::ReadAllText((Join-Path $project 'tools\verify.mjs')) | Should -Not -Match '\{\{name\}\}'
    }

    It 'makes the render app outside the project, linked to the shared install and to src' {
        New-AosVideo -Name 'align-1'
        $app = Join-Path $env:AOS_VIDEO_HOME 'align-1\app'
        (Get-Item -LiteralPath (Join-Path $app 'node_modules')).LinkType | Should -Be 'Junction'
        (Get-Item -LiteralPath (Join-Path $app 'src')).LinkType | Should -Be 'Junction'
        Test-Path -LiteralPath (Join-Path $app 'src\data\plan.ts') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $app 'public\vo') | Should -BeTrue
    }

    It 'keeps edited files on a second run' {
        New-AosVideo -Name 'align-1'
        $brief = Join-Path $env:AOS_PROJECTS 'videos\align-1\brief.md'
        Write-TestFile $brief "my brief`r`n"
        New-AosVideo -Name 'align-1'
        [System.IO.File]::ReadAllText($brief) | Should -BeExactly "my brief`r`n"
    }

    It 'creates a missing preflight once and keeps an edited report on a second run' {
        $oldCoord = $env:AOS_COORD; $oldRules = $env:AOS_VIDEO_RULES
        try {
            $env:AOS_COORD = Join-Path $caseRoot 'coord'
            $env:AOS_VIDEO_RULES = Join-Path $caseRoot 'video-rules.md'
            Write-TestFile $env:AOS_VIDEO_RULES "# Video rules`n- R01 [manual] Approve the brief.`n"
            New-AosVideo -Name 'align-1'
            $report = Join-Path $env:AOS_PROJECTS 'videos\align-1\PREFLIGHT.md'
            [System.IO.File]::ReadAllText($report) | Should -Match '^# Preflight: align-1'
            [System.IO.File]::ReadAllText($report) | Should -Match '## Rules'
            Write-TestFile $report "my preflight`r`n"
            New-AosVideo -Name 'align-1'
            [System.IO.File]::ReadAllText($report) | Should -BeExactly "my preflight`r`n"
        }
        finally { $env:AOS_COORD = $oldCoord; $env:AOS_VIDEO_RULES = $oldRules }
    }

    It 'warns and links no node_modules when the shared install is missing' {
        $env:AOS_REMOTION_MODULES = Join-Path $caseRoot 'missing\node_modules'
        Mock Write-AosWarn -ModuleName aos { }
        New-AosVideo -Name 'align-2'
        Test-Path -LiteralPath (Join-Path $env:AOS_VIDEO_HOME 'align-2\app\node_modules') | Should -BeFalse
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'shared Remotion install not found' }
    }

    It 'refuses a name that is not a plain folder name: <Name>' -ForEach @(@{ Name = '..\escape' }, @{ Name = '' }, @{ Name = 'a b' }) {
        Mock Write-AosWarn -ModuleName aos { }
        New-AosVideo -Name $Name
        Test-Path -LiteralPath (Join-Path $env:AOS_PROJECTS 'videos') | Should -BeFalse
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'usage: aos video new' }
    }
}

Describe 'aos video verdict and log' {
    BeforeEach {
        $oldCoord = $env:AOS_COORD
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
    }
    AfterEach { $env:AOS_COORD = $oldCoord }

    It 'stores the full verdict text and timestamp in one UTF-8 ledger event' {
        $text = 'Keep "wide", then' + [char]0x2014 + 'cut.'
        aos video verdict align-1 'Keep "wide",' ('then' + [char]0x2014 + 'cut.')
        $events = @(InModuleScope aos { Get-AosLedger -Last 0 })
        $events.Count | Should -Be 1
        $events[0].ts | Should -Not -BeNullOrEmpty
        $events[0].type | Should -BeExactly 'video-verdict'
        $events[0].video | Should -BeExactly 'align-1'
        $events[0].text | Should -BeExactly $text
        # JSON escapes the quotes; the non-ASCII dash must be stored as UTF-8, not as a \u escape.
        [System.IO.File]::ReadAllText((Join-Path $env:AOS_COORD 'ledger.jsonl'), [System.Text.Encoding]::UTF8) |
            Should -Match ([regex]::Escape('then' + [char]0x2014 + 'cut.'))
    }

    It 'warns and writes no verdict for <Case>' -ForEach @(
        @{ Case = 'invalid name'; Name = '../escape'; Text = 'good' },
        @{ Case = 'empty text'; Name = 'align-1'; Text = '' }
    ) {
        Mock Write-AosWarn -ModuleName aos { }
        InModuleScope aos -Parameters @{ N = $Name; T = $Text } {
            param($N, $T)
            Add-AosVideoVerdict -Name $N -Text $T
        }
        Test-Path -LiteralPath (Join-Path $env:AOS_COORD 'ledger.jsonl') | Should -BeFalse
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'usage: aos video verdict' }
    }

    It 'accepts stage <Stage> and stores invariant decimal minutes with the joined note' -ForEach @(
        @{ Stage = 'brief' }, @{ Stage = 'look' }, @{ Stage = 'structure' },
        @{ Stage = 'production' }, @{ Stage = 'qa' }, @{ Stage = 'delivery' },
        @{ Stage = 'retro' }, @{ Stage = 'revision' }
    ) {
        aos video log align-1 $Stage '12.5' 'first' 'review'
        $events = @(InModuleScope aos { Get-AosLedger -Last 0 })
        $events.Count | Should -Be 1
        $events[0].ts | Should -Not -BeNullOrEmpty
        $events[0].type | Should -BeExactly 'video-stage'
        $events[0].video | Should -BeExactly 'align-1'
        $events[0].stage | Should -BeExactly $Stage
        $events[0].minutes | Should -Be 12.5
        ($events[0].minutes -is [string]) | Should -BeFalse
        $events[0].note | Should -BeExactly 'first review'
    }

    It 'stores an empty note when no note is supplied' {
        InModuleScope aos { Add-AosVideoStage -Name 'align-1' -Stage 'qa' -Minutes '0' }
        $events = @(InModuleScope aos { Get-AosLedger -Last 0 })
        $events.Count | Should -Be 1
        $events[0].note | Should -BeExactly ''
        $events[0].minutes | Should -Be 0
    }

    It 'warns and writes no stage for <Case>' -ForEach @(
        @{ Case = 'invalid name'; Words = @('log', '../escape', 'qa', '2') },
        @{ Case = 'unknown stage'; Words = @('log', 'align-1', 'editing', '2') },
        @{ Case = 'negative minutes'; Words = @('log', 'align-1', 'qa', '-1') },
        @{ Case = 'non-numeric minutes'; Words = @('log', 'align-1', 'qa', 'soon') },
        @{ Case = 'locale decimal'; Words = @('log', 'align-1', 'qa', '12,5') }
    ) {
        Mock Write-AosWarn -ModuleName aos { }
        aos video @Words
        Test-Path -LiteralPath (Join-Path $env:AOS_COORD 'ledger.jsonl') | Should -BeFalse
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'usage: aos video log' }
    }

    It 'lists all video subcommands in the warning for an unknown action' {
        Mock Write-AosWarn -ModuleName aos { }
        aos video unknown
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            $Text -match 'usage: aos video new\|verdict\|log\|preflight'
        }
    }
}

Describe 'aos video preflight' {
    BeforeEach {
        $savedPreflight = @{ C = $env:AOS_COORD; P = $env:AOS_PROJECTS; R = $env:AOS_VIDEO_RULES }
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $env:AOS_PROJECTS = New-TestFolder (Join-Path $caseRoot 'projects')
        $env:AOS_VIDEO_RULES = Join-Path $caseRoot 'rules.md'
        Write-TestFile $env:AOS_VIDEO_RULES "# Video rules`n- R01 [manual] Approve the brief.`n- R02 [check: frozen-frames] Check the timeline.`n"
    }
    AfterEach {
        $env:AOS_COORD = $savedPreflight.C; $env:AOS_PROJECTS = $savedPreflight.P; $env:AOS_VIDEO_RULES = $savedPreflight.R
    }

    It 'returns a report for a missing project without creating its folder' {
        $report = aos video preflight align-1 | Out-String
        $report | Should -Match '^# Preflight: align-1'
        $headings = @('## Rules', '## Verdicts on align', '## Other recent verdicts',
            '## Stage minutes', '## Delegations')
        $last = -1
        foreach ($heading in $headings) {
            $position = $report.IndexOf($heading, [StringComparison]::Ordinal)
            $position | Should -BeGreaterThan $last
            $last = $position
        }
        $report | Should -Match 'R01.*manual'
        $report | Should -Match 'R02.*check: frozen-frames.*tools/checks/frozen-frames\.mjs'
        $report | Should -Match '(?s)## Stage minutes.*?- none recorded.*?## Delegations.*?- none recorded'
        Test-Path -LiteralPath (Join-Path $env:AOS_PROJECTS 'videos\align-1') | Should -BeFalse
    }

    It 'reports family verdicts, five other verdicts, medians and delegation outcomes' {
        $lines = @(
            '{"ts":"2026-09-01T10:00:00Z","type":"video-verdict","video":"alignment-3","text":"first"}',
            '{"ts":"2026-09-02T10:00:00Z","type":"video-verdict","video":"alignment","text":"second"}',
            '{"ts":"2026-09-03T10:00:00Z","type":"video-verdict","video":"Alignment-v2","text":"third"}',
            '{"ts":"2026-09-04T10:00:00Z","type":"video-verdict","video":"other-1","text":"drop me"}',
            '{"ts":"2026-09-05T10:00:00Z","type":"video-verdict","video":"other-2","text":"keep 1"}',
            '{"ts":"2026-09-06T10:00:00Z","type":"video-verdict","video":"other-3","text":"keep 2"}',
            '{"ts":"2026-09-07T10:00:00Z","type":"video-verdict","video":"other-4","text":"keep 3"}',
            '{"ts":"2026-09-08T10:00:00Z","type":"video-verdict","video":"other-5","text":"keep 4"}',
            '{"ts":"2026-09-09T10:00:00Z","type":"video-verdict","video":"other-6","text":"keep 5"}',
            '{"ts":"2026-09-10T10:00:00Z","type":"video-stage","video":"other-1","stage":"production","minutes":10,"note":""}',
            '{"ts":"2026-09-11T10:00:00Z","type":"video-stage","video":"alignment","stage":"production","minutes":42,"note":""}',
            '{"ts":"2026-09-12T10:00:00Z","type":"video-stage","video":"alignment-3","stage":"production","minutes":50,"note":""}',
            '{"ts":"2026-09-13T10:00:00Z","type":"video-stage","video":"alignment","stage":"qa","minutes":10,"note":""}',
            '{"ts":"2026-09-14T10:00:00Z","type":"video-stage","video":"alignment","stage":"qa","minutes":20,"note":""}',
            '{"ts":"2026-09-15T10:00:00Z","type":"delegate","outcome":"accepted"}',
            '{"ts":"2026-09-16T10:00:00Z","type":"delegate","outcome":"accepted"}',
            '{"ts":"2026-09-17T10:00:00Z","type":"delegate","outcome":"rejected"}'
        )
        # The report must read beyond Get-AosLedger's default 20-event window.
        for ($i = 0; $i -lt 21; $i++) {
            $lines += '{"ts":"2026-09-18T10:00:00Z","type":"note","text":"unrelated"}'
        }
        Write-TestFile (Join-Path $env:AOS_COORD 'ledger.jsonl') ($lines -join "`n")
        $report = aos video preflight 'ALIGNMENT-4' | Out-String
        $report | Should -Match '(?m)^- 2026-09-01 alignment-3: "first"\r?$'
        $report | Should -Match '(?m)^- 2026-09-02 alignment: "second"\r?$'
        $report | Should -Match '(?m)^- 2026-09-03 Alignment-v2: "third"\r?$'
        $report.IndexOf('alignment-3: "first"') | Should -BeLessThan $report.IndexOf('alignment: "second"')
        $report.IndexOf('alignment: "second"') | Should -BeLessThan $report.IndexOf('Alignment-v2: "third"')
        $report | Should -Not -Match 'drop me'
        $report | Should -Match '(?m)^- 2026-09-05 other-2: "keep 1"\r?$'
        foreach ($n in 1..5) { $report | Should -Match ('keep ' + $n) }
        $report | Should -Match '(?m)^- production: median 42 min \(3 runs\)\r?$'
        $report | Should -Match '(?m)^- qa: median 15 min \(2 runs\)\r?$'
        $report | Should -Match '(?m)^- accepted: 2\r?$'
        $report | Should -Match '(?m)^- rejected: 1\r?$'
    }

    It 'overwrites the generated report when the project folder exists' {
        $folder = New-TestFolder (Join-Path $env:AOS_PROJECTS 'videos\align-1')
        $path = Join-Path $folder 'PREFLIGHT.md'
        Write-TestFile $path 'stale report'
        $report = InModuleScope aos { Write-AosVideoPreflight -Name 'align-1' } | Out-String
        $stored = [System.IO.File]::ReadAllText($path)
        $stored.TrimEnd([char[]]@("`r", "`n")) | Should -BeExactly $report.TrimEnd([char[]]@("`r", "`n"))
        $stored | Should -Match '^# Preflight: align-1'
    }
}

Describe 'Video input provenance' {
    It 'runs reviewed export evidence guards (<Check>) in TestDrive fixtures' -ForEach @(
        @{ Check = 'fact coverage and entry-point refusal'; File = 'currency-hardening.test.mjs' },
        @{ Check = 'actual export day'; File = 'currency-export-day.test.mjs' },
        @{ Check = 'dated evidence identity'; File = 'input-manifest-evidence.test.mjs' },
        @{ Check = 'explicit timeless exception'; File = 'currency-wiring.test.mjs' }
    ) {
        $testFile = Join-Path $PSScriptRoot "..\templates\video\tools\checks\$File"
        $savedScratch = $env:AOS_VIDEO_TEST_ROOT
        try {
            $env:AOS_VIDEO_TEST_ROOT = Join-Path $TestDrive 'export-evidence-regressions'
            $result = & node --no-warnings --test $testFile 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because $result
        } finally {
            $env:AOS_VIDEO_TEST_ROOT = $savedScratch
        }
    }

    It 'runs reusable video <Check> regressions in isolated fixtures' -ForEach @(
        @{ Check = 'joins'; File = 'joins.test.mts' },
        @{ Check = 'screen text'; File = 'screen-text.test.mjs' },
        @{ Check = 'pipeline'; File = 'pipeline.test.mjs' },
        @{ Check = 'review sheets'; File = 'review-sheets.test.mts' }
    ) {
        $testFile = Join-Path $PSScriptRoot "..\templates\video\tools\checks\$File"
        $savedScratch = $env:AOS_VIDEO_TEST_ROOT
        try {
            $env:AOS_VIDEO_TEST_ROOT = Join-Path $TestDrive 'video-regressions'
            $result = & node --no-warnings --test $testFile 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because $result
        } finally {
            $env:AOS_VIDEO_TEST_ROOT = $savedScratch
        }
    }

    It 'runs the currency gate and export-day reverify tests (no network: a local fixture server)' -ForEach @(
        @{ Name = 'currency'; File = 'checks\currency.test.mjs' },
        @{ Name = 'reverify'; File = 'reverify.test.mjs' }
    ) {
        $testFile = Join-Path $PSScriptRoot "..\templates\video\tools\$File"
        $result = & node --no-warnings --test $testFile 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $result
    }

    It 'runs the pacing report and render cache tests when ffmpeg is installed (<Name>)' -ForEach @(
        @{ Name = 'pacing'; File = 'checks\pacing.test.mjs' },
        @{ Name = 'render cache'; File = 'cache\cache.test.mjs' }
    ) {
        if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'ffmpeg is not on PATH (CI runners have none); the tests build synthetic H.264 clips' ; return }
        $testFile = Join-Path $PSScriptRoot "..\templates\video\tools\$File"
        $result = & node --no-warnings --test $testFile 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $result
    }

    It 'rejects changed render inputs and mismatched exports in an isolated fixture' {
        $testFile = Join-Path $PSScriptRoot '..\templates\video\tools\checks\input-manifest.test.mjs'
        $savedScratch = $env:AOS_MANIFEST_TEST_ROOT
        try {
            $env:AOS_MANIFEST_TEST_ROOT = Join-Path $TestDrive 'manifest-regressions'
            $result = & node --test $testFile 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because $result
        } finally {
            $env:AOS_MANIFEST_TEST_ROOT = $savedScratch
        }
    }
}

Describe 'Video rules format' {
    It 'has numbered unique rules and wires every check into the video QA script' {
        $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $rules = [System.IO.File]::ReadAllLines((Join-Path $root 'agents-home\video\video-rules.md'))
        $qa = [System.IO.File]::ReadAllText((Join-Path $root 'templates\video\tools\qa.sh'))
        $ids = @()
        foreach ($line in @($rules | Select-Object -Skip 1 | Where-Object { $_.Trim() })) {
            $line | Should -Match '^- R\d{2} \[(manual|check: [a-z-]+)\] \S'
            if ($line -match '^- (R\d{2}) \[(?:manual|check: [a-z-]+)\]') { $ids += $Matches[1] }
            if ($line -match '\[check: ([a-z-]+)\]') {
                $check = $Matches[1]
                Test-Path -LiteralPath (Join-Path $root "templates\video\tools\checks\$check.mjs") | Should -BeTrue
                # invoked by a command, not merely mentioned (a comment naming the script must not satisfy this)
                $runs = @($qa -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\bnode\b' -and $_.Contains("checks/$check.mjs") })
                $runs.Count | Should -BeGreaterThan 0
            }
        }
        $ids.Count | Should -BeGreaterThan 0
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }
}

Describe 'aos' {
    It 'prints help without throwing for <Command>' -ForEach @(
        @{ Command = 'help' }, @{ Command = 'not-a-real-aos-command' }
    ) {
        # The direct invocation also fails this test if the command throws.
        $output = aos -Command $Command *>&1 | Out-String
        $output | Should -Match 'aos - agentic-os control'
        $output | Should -Match 'aos status'
        $output | Should -Match 'aos new <name>'
        $output | Should -Match 'aos secret'
        Should -Invoke Update-AosPath -ModuleName aos -Times 0 -Exactly
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Round 3: standalone Codex installation' {
    BeforeEach {
        # Assert the new seam before mocking it: never fall through to the old installer.
        InModuleScope aos {
            Get-Command Get-AosCodexStandaloneBin -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty -Because 'the standalone installation needs an isolated path seam'
            Get-Command Invoke-AosCodexInstaller -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty -Because 'the official installer must be mockable'
        }
        $standaloneBin = Join-Path $caseRoot 'standalone with spaces\current\bin'
        Mock Get-AosCodexStandaloneBin -ModuleName aos { $standaloneBin }
        Mock Invoke-AosCodexInstaller -ModuleName aos { }
        Mock Edit-AosUserPath -ModuleName aos { }
        Mock Use-AosLocalBin -ModuleName aos { }
        Mock Test-Path -ModuleName aos { $false } -ParameterFilter {
            $LiteralPath -eq (Join-Path $HOME '.local\bin\claude.exe') -or
            $LiteralPath -eq (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe')
        }
        Mock Write-AosWarn -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -in @('claude', 'codex') }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'test version' } } -ParameterFilter {
            $CommandLine -in @('claude --version', 'codex --version')
        }
        # The old implementation invokes these directly. Never run the real CLIs.
        foreach ($cli in @('claude', 'codex')) {
            if (Get-Command $cli -ErrorAction SilentlyContinue) {
                Mock $cli -ModuleName aos { 'test version' }
            }
        }
        foreach ($shell in @('pwsh', 'powershell')) {
            if (Get-Command $shell -ErrorAction SilentlyContinue) {
                Mock $shell -ModuleName aos { throw 'Unexpected child shell in an engine test.' }
            }
        }
    }

    It 'keeps an existing standalone executable and adds its literal home PATH entry' {
        Write-TestFile (Join-Path $standaloneBin 'codex.exe') ''
        InModuleScope aos { Install-AosEngines }
        Should -Invoke Invoke-AosCodexInstaller -ModuleName aos -Times 0 -Exactly
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            @($Add | Where-Object { $_ -ceq '%USERPROFILE%\.codex\packages\standalone\current\bin' }).Count -eq 1 -and -not $DryRun
        }
    }

    It 'installs the missing standalone executable even when desktop Codex is on PATH' {
        Mock Invoke-AosCodexInstaller -ModuleName aos {
            New-Item -ItemType Directory -Path $standaloneBin -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $standaloneBin 'codex.exe'), '')
        }
        InModuleScope aos { Install-AosEngines }
        Should -Invoke Invoke-AosCodexInstaller -ModuleName aos -Times 1 -Exactly
        Test-Path -LiteralPath (Join-Path $standaloneBin 'codex.exe') | Should -BeTrue
    }

    It 'does not install a missing standalone executable in DryRun and previews PATH editing' {
        InModuleScope aos { Install-AosEngines -DryRun }
        Should -Invoke Invoke-AosCodexInstaller -ModuleName aos -Times 0 -Exactly
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 1 -ParameterFilter { $DryRun }
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 0 -Exactly -ParameterFilter { -not $DryRun }
        Test-Path -LiteralPath $standaloneBin | Should -BeFalse
    }

    It 'warns with the standalone path without throwing when the installer creates nothing' {
        InModuleScope aos { Install-AosEngines }
        Should -Invoke Invoke-AosCodexInstaller -ModuleName aos -Times 1 -Exactly
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter {
            $Text -like ('*' + $standaloneBin + '*')
        }
    }
}

Describe 'Round 3: Use-AosNpmPrefix' {
    BeforeEach {
        InModuleScope aos {
            Get-Command Get-AosNpmPrefix -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            Get-Command Use-AosNpmPrefix -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        $npmPrefix = Join-Path $caseRoot 'npm globals'
        Mock Get-AosNpmPrefix -ModuleName aos { $npmPrefix }
        Mock Edit-AosUserPath -ModuleName aos { }
        Mock Write-AosWarn -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'npm' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = (Join-Path $caseRoot 'old-prefix') } } -ParameterFilter {
            $CommandLine -eq 'npm config get prefix'
        }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '' } } -ParameterFilter {
            $CommandLine -like 'npm config set prefix *'
        }
    }

    It 'sets a different prefix to the wanted path and adds the literal home PATH entry' {
        InModuleScope aos { Use-AosNpmPrefix }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            $CommandLine -eq 'npm config get prefix'
        }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            $CommandLine.StartsWith('npm config set prefix ') -and $CommandLine.Contains($npmPrefix)
        }
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            @($Add).Count -eq 1 -and $Add[0] -ceq '%USERPROFILE%\.npm-global' -and -not $DryRun
        }
    }

    It 'does not set an equal prefix for <Variant>' -ForEach @(
        @{ Variant = 'exact spelling' }, @{ Variant = 'different case' }, @{ Variant = 'trailing backslash' }
    ) {
        $currentPrefix = $npmPrefix
        if ($Variant -eq 'different case') { $currentPrefix = $npmPrefix.ToUpperInvariant() }
        if ($Variant -eq 'trailing backslash') { $currentPrefix = $npmPrefix + '\' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $currentPrefix } } -ParameterFilter {
            $CommandLine -eq 'npm config get prefix'
        }
        InModuleScope aos { Use-AosNpmPrefix }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'npm config get prefix' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'npm config set prefix *' }
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            @($Add).Count -eq 1 -and $Add[0] -ceq '%USERPROFILE%\.npm-global' -and -not $DryRun
        }
    }

    It 'does not set a different prefix in DryRun and passes DryRun to PATH editing' {
        InModuleScope aos { Use-AosNpmPrefix -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'npm config set prefix *' }
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            @($Add).Count -eq 1 -and $Add[0] -ceq '%USERPROFILE%\.npm-global' -and $DryRun
        }
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 0 -Exactly -ParameterFilter { -not $DryRun }
    }

    It 'warns and does not read config or edit PATH when npm is missing' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'npm' }
        InModuleScope aos { Use-AosNpmPrefix }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'npm' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
        Should -Invoke Edit-AosUserPath -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Round 3: Install-AosNpmTools' {
    BeforeEach {
        InModuleScope aos {
            foreach ($name in @('Get-AosNpmPrefix', 'Use-AosNpmPrefix', 'Install-AosNpmTools')) {
                Get-Command $name -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because "$name is part of the npm tools contract"
            }
        }
        $npmPrefix = Join-Path $caseRoot 'npm globals'
        $npmCalls = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-AosNpmPrefix -ModuleName aos { $npmPrefix }
        Mock Use-AosNpmPrefix -ModuleName aos { $npmCalls.Add('prefix') }
        Mock Edit-AosUserPath -ModuleName aos { throw 'Install-AosNpmTools should use the mocked prefix helper.' }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -in @('npm', 'fixture-tool', 'second-tool') }
        Mock Invoke-AosCapture -ModuleName aos {
            $npmCalls.Add($CommandLine)
            @{ Code = 0; Text = '' }
        } -ParameterFilter { $CommandLine -match '^npm install -g (fixture-tool|second-tool)(\s|$)' }
    }

    It 'sets up the prefix first and installs each missing package despite unrelated PATH copies' {
        InModuleScope aos {
            Install-AosNpmTools -Packages @(
                @{ name = 'fixture-tool'; why = 'test one' }, @{ name = 'second-tool'; why = 'test two' }
            )
        }
        $npmCalls[0] | Should -BeExactly 'prefix'
        Should -Invoke Use-AosNpmPrefix -ModuleName aos -Times 1 -Exactly -ParameterFilter { -not $DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -match '^npm install -g fixture-tool(\s|$)' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -match '^npm install -g second-tool(\s|$)' }
    }

    It 'does not install when the package command exists in the wanted prefix' {
        Write-TestFile (Join-Path $npmPrefix 'fixture-tool.cmd') ''
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'fixture-tool' }
        InModuleScope aos { Install-AosNpmTools -Packages @(@{ name = 'fixture-tool'; why = 'test' }) }
        Should -Invoke Use-AosNpmPrefix -ModuleName aos -Times 1 -Exactly
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }

    It 'checks the command a package installs, not the package name' {
        # A scoped package (@getpaseo/cli) installs paseo.cmd, never "@getpaseo/cli.cmd".
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '' } } -ParameterFilter { $CommandLine -like 'npm install -g @getpaseo/cli*' }
        Write-TestFile (Join-Path $npmPrefix 'paseo.cmd') ''
        InModuleScope aos { Install-AosNpmTools -Packages @(@{ name = '@getpaseo/cli'; bin = 'paseo'; why = 'test' }) }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }

    It 'does not install a missing package in DryRun and previews prefix setup' {
        InModuleScope aos { Install-AosNpmTools -Packages @(@{ name = 'fixture-tool'; why = 'test' }) -DryRun }
        Should -Invoke Use-AosNpmPrefix -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
        Should -Invoke Use-AosNpmPrefix -ModuleName aos -Times 0 -Exactly -ParameterFilter { -not $DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Round 3: reference clone directory' {
    BeforeEach { $savedRefs = $env:AOS_REFS }
    AfterEach { $env:AOS_REFS = $savedRefs }

    It 'defaults to the home refs directory and honors an explicit override' {
        $env:AOS_REFS = $null
        InModuleScope aos { Get-AosRefsDir | Should -BeExactly (Join-Path $HOME '.aos\refs') }
        $env:AOS_REFS = Join-Path $caseRoot 'custom refs'
        InModuleScope aos { Get-AosRefsDir | Should -BeExactly $env:AOS_REFS }
    }
}

Describe 'Round 3: secret name validation' {
    It 'rejects invalid name <Label>' -ForEach @(
        @{ Label = 'empty'; Name = '' }, @{ Label = 'CON'; Name = 'CON' },
        @{ Label = 'nul'; Name = 'nul' }, @{ Label = 'PRN'; Name = 'PRN' },
        @{ Label = 'aux extension'; Name = 'aux.x' }, @{ Label = 'traversal'; Name = '../x' },
        @{ Label = 'space'; Name = 'a b' }, @{ Label = 'dot first'; Name = '.hidden' },
        @{ Label = 'dash first'; Name = '-x' }, @{ Label = '65 characters'; Name = ('a' * 65) }
        foreach ($number in 0..9) {
            @{ Label = "Com$number"; Name = "Com$number" }
            @{ Label = "LPT$number.key"; Name = "LPT$number.key" }
        }
    ) {
        InModuleScope aos -Parameters @{ Name = $Name } {
            param($Name)
            Get-Command Test-AosSecretName -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            $actual = Test-AosSecretName $Name
            ($actual -is [bool]) | Should -BeTrue
            $actual | Should -BeFalse
        }
    }

    It 'accepts valid name <Label>' -ForEach @(
        @{ Label = 'environment key'; Name = 'OPENAI_API_KEY' }, @{ Label = 'dot and dash'; Name = 'z.ai-key' },
        @{ Label = 'one character'; Name = 'a' }, @{ Label = '64 characters'; Name = ('a' * 64) },
        @{ Label = 'device prefix only'; Name = 'CONSOLE' }, @{ Label = 'long COM prefix'; Name = 'COM10x' },
        @{ Label = 'digit first'; Name = '0_key' }
    ) {
        InModuleScope aos -Parameters @{ Name = $Name } {
            param($Name)
            Get-Command Test-AosSecretName -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            $actual = Test-AosSecretName $Name
            ($actual -is [bool]) | Should -BeTrue
            $actual | Should -BeTrue
        }
    }
}

Describe 'Round 3: DPAPI secret files' {
    BeforeAll {
        $dpapiAvailable = $true
        # Probe with the same mechanism aos uses (ConvertFrom-SecureString). [ProtectedData] is not
        # loaded in Windows PowerShell 5.1, which silently skipped all of these tests there.
        try {
            $null = ConvertFrom-SecureString -SecureString (ConvertTo-SecureString 'probe' -AsPlainText -Force) -ErrorAction Stop
        } catch { $dpapiAvailable = $false }
    }
    BeforeEach {
        if (-not $dpapiAvailable) {
            Set-ItResult -Skipped -Because 'current-user DPAPI unavailable (sandboxed run)'
            return
        }
        $savedSecrets = $env:AOS_SECRETS
        $secretsDir = Join-Path $caseRoot 'isolated secrets'
        $env:AOS_SECRETS = $secretsDir
        Mock Write-AosWarn -ModuleName aos { }
        # Refuse to exercise file operations if a partial fix ignores the test override.
        InModuleScope aos {
            if (Get-Command Get-AosSecretsDir -ErrorAction SilentlyContinue) {
                Get-AosSecretsDir | Should -BeExactly $env:AOS_SECRETS
            }
        }
        # Block the old vault and child-shell paths even during a partial implementation.
        InModuleScope aos {
            if (Get-Command Initialize-AosSecretStore -ErrorAction SilentlyContinue) {
                Mock Initialize-AosSecretStore { throw 'The real SecretStore must never be initialized by a test.' }
            }
        }
        foreach ($shell in @('pwsh', 'powershell')) {
            if (Get-Command $shell -ErrorAction SilentlyContinue) {
                Mock $shell -ModuleName aos { throw 'Secret commands must stay in the current shell.' }
            }
        }
    }
    AfterEach { $env:AOS_SECRETS = $savedSecrets }

    It 'uses AOS_SECRETS when set and otherwise returns the home secrets directory' {
        InModuleScope aos {
            Get-AosSecretsDir | Should -BeExactly $env:AOS_SECRETS
            $env:AOS_SECRETS = $null
            Get-AosSecretsDir | Should -BeExactly (Join-Path $HOME '.aos\secrets')
        }
    }

    It 'rejects an invalid set without writing anything for <Label>' -ForEach @(
        @{ Label = 'empty'; Name = '' }, @{ Label = 'device'; Name = 'LPT9.key' },
        @{ Label = 'traversal'; Name = '../outside' }, @{ Label = 'too long'; Name = ('a' * 65) }
    ) {
        $before = Get-TestTreeState $caseRoot
        InModuleScope aos -Parameters @{ Name = $Name } {
            param($Name)
            $value = ConvertTo-SecureString 'synthetic invalid fixture' -AsPlainText -Force
            $actual = Set-AosSecret -Name $Name -Value $value
            ($actual -is [bool]) | Should -BeTrue
            $actual | Should -BeFalse
        }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
        (Get-TestTreeState $caseRoot) | Should -BeExactly $before
    }

    It 'creates the directory and writes current-user DPAPI ciphertext that round-trips' {
        InModuleScope aos {
            $plain = 'synthetic DPAPI fixture, not a credential'
            $actual = Set-AosSecret -Name 'z.ai-key' -Value (ConvertTo-SecureString $plain -AsPlainText -Force)
            ($actual -is [bool]) | Should -BeTrue
            $actual | Should -BeTrue
            $file = Join-Path $env:AOS_SECRETS 'z.ai-key.secret'
            Test-Path -LiteralPath $file -PathType Leaf | Should -BeTrue
            $ciphertext = [System.IO.File]::ReadAllText($file)
            $ciphertext | Should -Not -Match ([regex]::Escape($plain))
            # Decrypt independently of Get-AosSecret: the file must be DPAPI, not an encoding.
            $secure = ConvertTo-SecureString $ciphertext
            $credential = New-Object System.Management.Automation.PSCredential('fixture', $secure)
            $credential.GetNetworkCredential().Password | Should -BeExactly $plain
            Get-AosSecret -Name 'z.ai-key' | Should -BeExactly $plain
        }
    }

    It 'replaces an existing secret and leaves no temporary file behind' {
        InModuleScope aos {
            Set-AosSecret -Name 'replace-key' -Value (ConvertTo-SecureString 'synthetic first value' -AsPlainText -Force) | Should -BeTrue
            Set-AosSecret -Name 'replace-key' -Value (ConvertTo-SecureString 'synthetic replacement' -AsPlainText -Force) | Should -BeTrue
            Get-AosSecret -Name 'replace-key' | Should -BeExactly 'synthetic replacement'
            $files = @(Get-ChildItem -LiteralPath $env:AOS_SECRETS -Force -Recurse -File)
            @($files | Where-Object { $_.Name -like '*.tmp' }).Count | Should -Be 0
            $files.Count | Should -Be 1
            $files[0].Name | Should -BeExactly 'replace-key.secret'
            [System.IO.File]::ReadAllText($files[0].FullName) | Should -Not -Match 'synthetic replacement'
        }
    }

    It 'warns and returns null without throwing for <Label>' -ForEach @(
        @{ Label = 'missing secret'; Name = 'missing-key' }, @{ Label = 'invalid secret'; Name = '../outside' },
        @{ Label = 'empty name'; Name = '' }
    ) {
        InModuleScope aos -Parameters @{ Name = $Name } {
            param($Name)
            $actual = Get-AosSecret -Name $Name
            ($null -eq $actual) | Should -BeTrue
        }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
        Test-Path -LiteralPath $secretsDir | Should -BeFalse
    }

    It 'returns sorted secret names without extensions and ignores other files' {
        Write-TestFile (Join-Path $secretsDir 'z-last.secret') 'fixture'
        Write-TestFile (Join-Path $secretsDir 'a-first.secret') 'fixture'
        Write-TestFile (Join-Path $secretsDir 'middle.key.secret') 'fixture'
        Write-TestFile (Join-Path $secretsDir 'ignore.txt') 'fixture'
        InModuleScope aos {
            $names = @(Get-AosSecretNames)
            $names.Count | Should -Be 3
            ($names -join '|') | Should -BeExactly 'a-first|middle.key|z-last'
        }
    }

    It 'returns no names for a <State> directory' -ForEach @(
        @{ State = 'missing' }, @{ State = 'empty' }
    ) {
        if ($State -eq 'empty') { New-TestFolder $secretsDir | Out-Null }
        InModuleScope aos { @(Get-AosSecretNames).Count | Should -Be 0 }
    }

    It 'removes only the named secret and returns true' {
        Write-TestFile (Join-Path $secretsDir 'remove-me.secret') 'fixture'
        Write-TestFile (Join-Path $secretsDir 'keep-me.secret') 'keep fixture'
        InModuleScope aos {
            $actual = Remove-AosSecret -Name 'remove-me'
            ($actual -is [bool]) | Should -BeTrue
            $actual | Should -BeTrue
        }
        Test-Path -LiteralPath (Join-Path $secretsDir 'remove-me.secret') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $secretsDir 'keep-me.secret')) | Should -BeExactly 'keep fixture'
    }

    It 'warns and returns false when removing a missing secret' {
        InModuleScope aos {
            $actual = Remove-AosSecret -Name 'missing-key'
            ($actual -is [bool]) | Should -BeTrue
            $actual | Should -BeFalse
        }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
        Test-Path -LiteralPath $secretsDir | Should -BeFalse
    }

    It 'sets with a secure prompt and gets plaintext in this shell without launching another shell' {
        # On 5.1, make the old forwarding path available so the child-shell guard catches it.
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -in @('pwsh', 'powershell') }
        Mock Read-Host -ModuleName aos { ConvertTo-SecureString 'synthetic prompt value' -AsPlainText -Force }
        InModuleScope aos {
            Invoke-AosSecret 'set' 'prompt-key'
            Test-Path -LiteralPath (Join-Path $env:AOS_SECRETS 'prompt-key.secret') | Should -BeTrue
            Invoke-AosSecret 'get' 'prompt-key' | Should -BeExactly 'synthetic prompt value'
        }
        Should -Invoke Read-Host -ModuleName aos -Times 1 -Exactly -ParameterFilter { $AsSecureString }
        Should -Invoke Read-Host -ModuleName aos -Times 0 -Exactly -ParameterFilter { -not $AsSecureString }
        foreach ($shell in @('pwsh', 'powershell')) {
            if (Get-Command $shell -ErrorAction SilentlyContinue) {
                Should -Invoke $shell -ModuleName aos -Times 0 -Exactly
            }
        }
    }

    It 'reads this shell DPAPI file from the other PowerShell version' {
        $otherName = 'powershell'
        if ($PSVersionTable.PSVersion.Major -lt 6) { $otherName = 'pwsh' }
        $otherShell = Get-Command $otherName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $otherShell) {
            Set-ItResult -Skipped -Because "$otherName is not installed; cannot check cross-version DPAPI."
            return
        }
        InModuleScope aos {
            Set-AosSecret -Name 'cross-version' -Value (ConvertTo-SecureString 'synthetic cross-version value' -AsPlainText -Force) | Should -BeTrue
        }
        $modulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\aos.psm1')).Replace("'", "''")
        $escapedDir = $secretsDir.Replace("'", "''")
        # EncodedCommand preserves quoting under both native argument-passing conventions.
        # Only a synthetic value is used; the child inherits no profile and reads this fixture.
        $childCode = @"
`$ErrorActionPreference = 'Stop'
`$env:AOS_SECRETS = '$escapedDir'
Import-Module '$modulePath' -Force -DisableNameChecking
& (Get-Module aos) {
    if ((Get-AosSecretsDir) -cne `$env:AOS_SECRETS) { throw 'Secret directory escaped the test fixture.' }
    Get-AosSecret -Name 'cross-version'
}
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
        $output = & $otherShell.Source -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output | Out-String).Trim() | Should -BeExactly 'synthetic cross-version value'
    }
}

Describe 'Round 3: Start-AosRemote' {
    BeforeEach {
        $savedProjects = $env:AOS_PROJECTS
        $env:AOS_PROJECTS = Join-Path $caseRoot 'projects'
        InModuleScope aos {
            Get-Command Invoke-AosClaudeRemote -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            Get-Command Start-AosRemote -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        Mock Invoke-AosClaudeRemote -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'claude' }
        Mock Write-AosWarn -ModuleName aos { }
    }
    AfterEach { $env:AOS_PROJECTS = $savedProjects }

    It 'starts in the Desktop folder when Dir is omitted' {
        $desktop = [Environment]::GetFolderPath('Desktop')
        InModuleScope aos { Start-AosRemote }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Dir -eq $desktop }
    }

    It 'starts in an existing absolute folder with its full path' {
        $folder = New-TestFolder (Join-Path $caseRoot 'absolute folder')
        InModuleScope aos -Parameters @{ Folder = $folder } {
            param($Folder)
            Start-AosRemote -Dir $Folder
        }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Dir -eq $folder }
    }

    It 'resolves a relative folder against the current location' {
        $folder = New-TestFolder (Join-Path $caseRoot 'relative folder')
        Push-Location $caseRoot
        try { InModuleScope aos { Start-AosRemote -Dir '.\relative folder' } }
        finally { Pop-Location }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Dir -eq $folder }
    }

    It 'resolves a bare project name under AOS_PROJECTS when absent here' {
        $folder = New-TestFolder (Join-Path $env:AOS_PROJECTS 'phone-project')
        Push-Location $caseRoot
        try { InModuleScope aos { Start-AosRemote -Dir 'phone-project' } }
        finally { Pop-Location }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Dir -eq $folder }
    }

    It 'prefers an existing local folder over a same-named project' {
        $folder = New-TestFolder (Join-Path $caseRoot 'same-name')
        New-TestFolder (Join-Path $env:AOS_PROJECTS 'same-name') | Out-Null
        Push-Location $caseRoot
        try { InModuleScope aos { Start-AosRemote -Dir 'same-name' } }
        finally { Pop-Location }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Dir -eq $folder }
    }

    It 'warns without launching Claude for a missing folder' {
        InModuleScope aos -Parameters @{ Folder = (Join-Path $caseRoot 'missing') } {
            param($Folder)
            Start-AosRemote -Dir $Folder
        }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 0 -Exactly
    }

    It 'warns without launching when Claude is missing' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'claude' }
        InModuleScope aos -Parameters @{ Folder = $caseRoot } {
            param($Folder)
            Start-AosRemote -Dir $Folder
        }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'claude' }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 0 -Exactly
    }

    It 'does not launch Claude in DryRun' {
        InModuleScope aos -Parameters @{ Folder = $caseRoot } {
            param($Folder)
            Start-AosRemote -Dir $Folder -DryRun
        }
        Should -Invoke Invoke-AosClaudeRemote -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Round 3: aos remote dispatch' {
    It 'dispatches remote without a directory to Start-AosRemote' {
        InModuleScope aos { Get-Command Start-AosRemote -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
        Mock Start-AosRemote -ModuleName aos { }
        aos remote
        Should -Invoke Start-AosRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { -not $Dir -and -not $DryRun }
    }

    It 'passes the remote directory and DryRun through to Start-AosRemote' {
        InModuleScope aos { Get-Command Start-AosRemote -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty }
        Mock Start-AosRemote -ModuleName aos { }
        aos remote 'phone-project' -DryRun
        Should -Invoke Start-AosRemote -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Dir -eq 'phone-project' -and $DryRun }
    }

    It 'lists aos remote in help' {
        $output = aos help *>&1 | Out-String
        $output | Should -Match '(?m)^\s+aos remote\b'
    }
}

# Failure scenarios from Codex's review of the round-3 code (tests by Claude, seen failing first).
Describe 'Round 3 review fixes' {
    BeforeEach {
        $savedSecrets = $env:AOS_SECRETS
        $savedNpmPrefix = [Environment]::GetEnvironmentVariable('NPM_CONFIG_PREFIX')
        $secretsDir = Join-Path $caseRoot 'isolated secrets'
        $env:AOS_SECRETS = $secretsDir
        Mock Write-AosWarn -ModuleName aos { }
    }
    AfterEach {
        $env:AOS_SECRETS = $savedSecrets
        [Environment]::SetEnvironmentVariable('NPM_CONFIG_PREFIX', $savedNpmPrefix)
    }

    It 'returns null with a warning, not an error, for a secret file it cannot decrypt' {
        # Valid hex that is not a DPAPI blob: ConvertTo-SecureString reports a non-terminating error.
        Write-TestFile (Join-Path $secretsDir 'foreign.secret') ('deadbeef' * 32)
        InModuleScope aos {
            $ErrorActionPreference = 'Continue'   # the user's default; the runner's Stop would hide the bug
            $actual = Get-AosSecret -Name 'foreign' 2>$null
            ($null -eq $actual) | Should -BeTrue
        }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly
    }

    It 'leaves another writer''s temporary file alone' {
        Write-TestFile (Join-Path $secretsDir 'shared-key.secret.tmp') 'another writer'
        InModuleScope aos {
            Set-AosSecret -Name 'shared-key' -Value (ConvertTo-SecureString 'synthetic value' -AsPlainText -Force) | Should -BeTrue
            Get-AosSecret -Name 'shared-key' | Should -BeExactly 'synthetic value'
        }
        [System.IO.File]::ReadAllText((Join-Path $secretsDir 'shared-key.secret.tmp')) | Should -BeExactly 'another writer'
    }

    It 'installs npm tools with an explicit prefix' {
        $npmPrefix = Join-Path $caseRoot 'npm globals'
        Mock Get-AosNpmPrefix -ModuleName aos { $npmPrefix }
        Mock Use-AosNpmPrefix -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'npm' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '' } } -ParameterFilter { $CommandLine -like 'npm install -g *' }
        InModuleScope aos { Install-AosNpmTools -Packages @(@{ name = 'fixture-tool'; why = 'test' }) }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            $CommandLine -like 'npm install -g fixture-tool *' -and $CommandLine.Contains('--prefix') -and $CommandLine.Contains($npmPrefix)
        }
    }

    It 'warns when NPM_CONFIG_PREFIX overrides the user npm config' {
        [Environment]::SetEnvironmentVariable('NPM_CONFIG_PREFIX', (Join-Path $caseRoot 'elsewhere'))
        Mock Get-AosNpmPrefix -ModuleName aos { Join-Path $caseRoot 'npm globals' }
        Mock Edit-AosUserPath -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'npm' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = (Join-Path $caseRoot 'npm globals') } } -ParameterFilter { $CommandLine -eq 'npm config get prefix' }
        InModuleScope aos { Use-AosNpmPrefix }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'NPM_CONFIG_PREFIX' }
    }

    It 'does not start Claude when the folder cannot be entered' {
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            Mock claude -ModuleName aos { throw 'claude must not start outside the requested folder' }
        }
        $here = (Get-Location).ProviderPath
        InModuleScope aos -Parameters @{ Folder = (Join-Path $caseRoot 'vanished') } {
            param($Folder)
            $ErrorActionPreference = 'Continue'   # the user's default; Push-Location's error is non-terminating
            { Invoke-AosClaudeRemote -Dir $Folder 2>$null } | Should -Throw
        }
        if (Get-Command claude -ErrorAction SilentlyContinue) { Should -Invoke claude -ModuleName aos -Times 0 -Exactly }
        (Get-Location).ProviderPath | Should -Be $here
    }
}

Describe 'Local model layer' {
    BeforeEach {
        $stateDir = Join-Path $caseRoot 'state'
        Mock Get-AosStateDir -ModuleName aos { $stateDir }
        Mock Get-AosLocalConfig -ModuleName aos {
            [ordered]@{ default = 'openbmb/minicpm5-2b:q8_0'; optional = @('qwen3.5:4b'); ollama_url = 'http://127.0.0.1:11434'; min_tokens_per_s = 15 }
        }
        Mock Install-AosWingetPackage -ModuleName aos { }
        Mock Install-AosNarTools -ModuleName aos { }
        Mock Install-AosNpmTools -ModuleName aos { }
        Mock Sync-AosPi -ModuleName aos { }
        Mock Write-AosWarn -ModuleName aos { }
        Mock Write-AosOk -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'ollama' }
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME                        ID     SIZE      MODIFIED`nopenbmb/minicpm5-2b:q8_0    abc    2.7 GB    1 day ago" }
        } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'success' } } -ParameterFilter { $CommandLine -like 'ollama pull *' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'OK' } } -ParameterFilter { $CommandLine -like 'ollama run *' }
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME                        ID     SIZE      PROCESSOR    CONTEXT    UNTIL`nopenbmb/minicpm5-2b:q8_0    abc    3.9 GB    100% GPU     4096       4 minutes from now" }
        } -ParameterFilter { $CommandLine -eq 'ollama ps' }
    }

    It 'matches Ollama tags exactly, treating a bare name as :latest' {
        InModuleScope aos {
            $list = "NAME ID SIZE`nqwen3.5:4b x 3.4 GB`nllama3.2:latest y 2.0 GB"
            Test-AosOllamaModel -List $list -Tag 'qwen3.5:4b' | Should -BeTrue
            Test-AosOllamaModel -List $list -Tag 'QWEN3.5:4B' | Should -BeTrue
            Test-AosOllamaModel -List $list -Tag 'llama3.2' | Should -BeTrue
            Test-AosOllamaModel -List $list -Tag 'qwen3.5' | Should -BeFalse
            Test-AosOllamaModel -List $list -Tag 'qwen3.5:4b-q8_0' | Should -BeFalse
        }
    }

    It 'reads the GPU share from ollama ps' {
        InModuleScope aos {
            $ps = "NAME ID SIZE PROCESSOR`na:1 x 3 GB 100% GPU 4096 now`nb:1 y 9 GB 48%/52% CPU/GPU 4096 now"
            Test-AosOllamaGpu -PsText $ps -Tag 'a:1' | Should -BeExactly 'gpu'
            Test-AosOllamaGpu -PsText $ps -Tag 'b:1' | Should -BeExactly 'split'
            Test-AosOllamaGpu -PsText $ps -Tag 'c:1' | Should -BeExactly 'absent'
        }
    }

    It 'pulls only the configured models that are missing, checks the GPU and writes the local state file' {
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'ollama pull qwen3.5:4b' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -eq 'ollama pull openbmb/minicpm5-2b:q8_0' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'entirely on the GPU' }
        $state = Get-Content -Raw (Join-Path $stateDir 'local.json') | ConvertFrom-Json
        $state.default | Should -BeExactly 'openbmb/minicpm5-2b:q8_0'
        $state.ollama_url | Should -BeExactly 'http://127.0.0.1:11434'
        $state.min_tokens_per_s | Should -Be 15
        Should -Invoke Install-AosNarTools -ModuleName aos -Times 1 -Exactly
    }

    It 'warns when the default model does not fit the GPU' {
        Mock Invoke-AosCapture -ModuleName aos {
            @{ Code = 0; Text = "NAME ID SIZE PROCESSOR`nopenbmb/minicpm5-2b:q8_0 abc 7.9 GB 35%/65% CPU/GPU 4096 now" }
        } -ParameterFilter { $CommandLine -eq 'ollama ps' }
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'partly on the CPU' }
    }

    It 'pulls, runs and writes nothing in DryRun' {
        InModuleScope aos { Install-AosLocal -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama pull *' -or $CommandLine -like 'ollama run *' }
        Test-Path -LiteralPath (Join-Path $stateDir 'local.json') | Should -BeFalse
        Should -Invoke Install-AosWingetPackage -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Id -eq 'Ollama.Ollama' -and $DryRun }
    }

    It 'warns and runs nothing when ollama is not on PATH' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'ollama' }
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'ollama' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }

    It 'leaves the local state file untouched when it already says the same thing' {
        InModuleScope aos { Sync-AosLocalState }
        $before = (Get-Item -LiteralPath (Join-Path $stateDir 'local.json')).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50
        InModuleScope aos { Sync-AosLocalState }
        (Get-Item -LiteralPath (Join-Path $stateDir 'local.json')).LastWriteTimeUtc | Should -Be $before
    }

    It 'installs the local agent harness from the local_npm list' {
        Mock Get-AosPackages -ModuleName aos {
            @{ local = @(@{ id = 'Ollama.Ollama'; why = 't' }); local_npm = @(@{ name = '@earendil-works/pi-coding-agent'; bin = 'pi'; why = 't' }) }
        }
        InModuleScope aos { Install-AosLocal -DryRun }
        Should -Invoke Install-AosNpmTools -ModuleName aos -Times 1 -Exactly -ParameterFilter { @($Packages)[0]['bin'] -eq 'pi' -and $DryRun }
    }
}

Describe 'Agent model variant' {
    BeforeEach {
        $stateDir = Join-Path $caseRoot 'state with spaces'
        $blobPath = Join-Path $caseRoot 'models\blobs\sha256-weights'
        $baseModelfile = "# Modelfile generated by Ollama`r`n# FROM qwen3.5:4b`r`nFROM $blobPath`r`nTEMPLATE triple-quoted-template`r`nRENDERER qwen3.5`r`nPARAMETER temperature 1`r`nPARAMETER top_k 20`r`nPARAMETER top_p 0.95`r`nPARAMETER presence_penalty 1.5`r`n"
        $variantModelfile = $baseModelfile.Replace('# FROM qwen3.5:4b', '# FROM aos-agent') + "PARAMETER num_ctx 16384`r`n"
        $responses = @{
            base = @{ Code = 0; Text = $baseModelfile }
            variant = @{ Code = 1; Text = 'model not found' }
            create = @{ Code = 0; Text = 'success' }
            run = @{ Code = 0; Text = 'OK' }
            ps = @{ Code = 0; Text = "NAME ID SIZE PROCESSOR CONTEXT UNTIL`naos-agent:latest abc 3.3 GB 100% GPU 16384 now" }
        }
        Mock Get-AosStateDir -ModuleName aos { $stateDir }
        Mock Get-AosLocalConfig -ModuleName aos {
            [ordered]@{ default = 'qwen3.5:4b'; optional = @(); agent_model = 'aos-agent'; agent_num_ctx = 16384;
                ollama_url = 'http://127.0.0.1:11434'; min_tokens_per_s = 15 }
        }
        foreach ($f in 'Write-AosOk', 'Write-AosWarn', 'Write-AosInfo', 'Write-AosDry', 'Write-AosStep') {
            Mock $f -ModuleName aos { }
        }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'ollama' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nqwen3.5:4b abc 3 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        Mock Invoke-AosCapture -ModuleName aos { $responses.base } -ParameterFilter { $CommandLine -eq 'ollama show qwen3.5:4b --modelfile' }
        Mock Invoke-AosCapture -ModuleName aos { $responses.variant } -ParameterFilter { $CommandLine -eq 'ollama show aos-agent --modelfile' }
        Mock Invoke-AosCapture -ModuleName aos { $responses.create } -ParameterFilter { $CommandLine -like 'ollama create *' }
        Mock Invoke-AosCapture -ModuleName aos { $responses.run } -ParameterFilter { $CommandLine -like 'ollama run *' }
        Mock Invoke-AosCapture -ModuleName aos { $responses.ps } -ParameterFilter { $CommandLine -eq 'ollama ps' }
    }

    It 'generates only the base tag and the requested context with a final newline' {
        InModuleScope aos {
            Get-AosAgentModelfile -From 'qwen3.5:4b' -NumCtx 16384 |
                Should -BeExactly "FROM qwen3.5:4b`nPARAMETER num_ctx 16384`n"
        }
    }

    It 'reports missing when the variant cannot be shown' {
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'missing' }
    }

    It 'reports ok for matching blobs and context, ignoring comments and other parameters' {
        $responses.variant = @{ Code = 0; Text = $variantModelfile }
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'ok' }
    }

    It 'reports stale for different weight blobs' {
        $responses.variant = @{ Code = 0; Text = $variantModelfile.Replace('sha256-weights', 'sha256-old') }
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'stale' }
    }

    It 'reports stale for context <ContextLine>' -ForEach @(
        @{ ContextLine = 'PARAMETER num_ctx 4096' }
        @{ ContextLine = 'PARAMETER num_ctx 163840' }
        @{ ContextLine = '# PARAMETER num_ctx 16384' }
        @{ ContextLine = '' }
    ) {
        $responses.variant = @{ Code = 0; Text = $baseModelfile + $ContextLine + "`n" }
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'stale' }
    }

    It 'reports stale when the base cannot be inspected' {
        $responses.variant = @{ Code = 0; Text = $variantModelfile }
        $responses.base = @{ Code = 1; Text = 'model not found' }
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'stale' }
    }

    It 'reports stale when the default changed something other than its weights (<Change>)' -ForEach @(
        @{ Change = 'template'; Old = 'TEMPLATE triple-quoted-template'; New = 'TEMPLATE a-newer-template' }
        @{ Change = 'parameter'; Old = 'PARAMETER top_k 20'; New = 'PARAMETER top_k 40' }
        @{ Change = 'renderer'; Old = 'RENDERER qwen3.5'; New = 'RENDERER qwen3.6' }
    ) {
        # The variant was built from the old default; the default was re-pulled with the same weights.
        $responses.variant = @{ Code = 0; Text = $variantModelfile }
        $responses.base = @{ Code = 0; Text = $baseModelfile.Replace($Old, $New) }
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'stale' }
    }

    It 'does not accept matching comments without real FROM lines' {
        $responses.variant = @{ Code = 0; Text = "# FROM same-blob`nPARAMETER num_ctx 16384`n" }
        $responses.base = @{ Code = 0; Text = '# FROM same-blob' }
        InModuleScope aos { Test-AosAgentModel -Name 'aos-agent' -From 'qwen3.5:4b' -NumCtx 16384 | Should -BeExactly 'stale' }
    }

    It 'creates a missing variant from the written Modelfile and then loads it to check GPU use' {
        Mock Invoke-AosCapture -ModuleName aos {
            [System.IO.File]::ReadAllText((Join-Path $stateDir 'agent.Modelfile')) |
                Should -BeExactly "FROM qwen3.5:4b`nPARAMETER num_ctx 16384`n"
            $responses.create
        } -ParameterFilter { $CommandLine -like 'ollama create *' }
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            $CommandLine -eq ('ollama create aos-agent -f "' + (Join-Path $stateDir 'agent.Modelfile') + '"')
        }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'ollama run aos-agent "Reply with OK"' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'ollama ps' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'aos-agent.*entirely on the GPU' }
        Test-Path -LiteralPath (Join-Path $stateDir 'local.json') | Should -BeFalse
    }

    It 'warns when the created variant is split across CPU and GPU' {
        $responses.ps.Text = "NAME ID SIZE PROCESSOR`naos-agent:latest abc 7.9 GB 35%/65% CPU/GPU 16384 now"
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'aos-agent.*partly on the CPU' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly -ParameterFilter { $Text -match 'entirely on the GPU' }
    }

    It 'warns when the variant does not load' {
        $responses.run = @{ Code = 1; Text = 'load failed' }
        $responses.ps.Text = 'NAME ID SIZE PROCESSOR'
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'aos-agent.*(load|run)' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }

    It 'leaves the Modelfile untouched and does not create or load when already current' {
        $responses.variant = @{ Code = 0; Text = $variantModelfile }
        Write-TestFile (Join-Path $stateDir 'agent.Modelfile') 'existing bookkeeping is not the source of truth'
        $before = Get-TestTreeState $stateDir
        InModuleScope aos { Sync-AosAgentModel; Sync-AosAgentModel }
        Get-TestTreeState $stateDir | Should -BeExactly $before
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter {
            $CommandLine -like 'ollama create *' -or $CommandLine -like 'ollama run *' -or $CommandLine -eq 'ollama ps'
        }
    }

    It 'recreates a stale variant even when the saved Modelfile is already correct' {
        $responses.variant = @{ Code = 0; Text = $variantModelfile.Replace('sha256-weights', 'sha256-old') }
        Write-TestFile (Join-Path $stateDir 'agent.Modelfile') "FROM qwen3.5:4b`nPARAMETER num_ctx 16384`n"
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent *' }
    }

    It 'warns without reporting success or loading after create fails' {
        $responses.create = @{ Code = 1; Text = 'create failed' }
        InModuleScope aos { Sync-AosAgentModel }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'create.*failed' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama run *' -or $CommandLine -eq 'ollama ps' }
    }

    It 'writes and creates nothing in DryRun' {
        InModuleScope aos { Sync-AosAgentModel -DryRun }
        Test-Path -LiteralPath $stateDir | Should -BeFalse
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama create *' -or $CommandLine -like 'ollama run *' }
        Should -Invoke Write-AosDry -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'ollama create aos-agent' }
    }

    It 'writes and creates nothing when the default has not been pulled' {
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nqwen3.5:4b-other abc 3 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        InModuleScope aos { Sync-AosAgentModel }
        Test-Path -LiteralPath $stateDir | Should -BeFalse
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama create *' -or $CommandLine -like 'ollama run *' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'aos install local' }
    }

    It 'does not run Ollama or write files when Ollama is unavailable' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'ollama' }
        InModuleScope aos { Sync-AosAgentModel }
        Test-Path -LiteralPath $stateDir | Should -BeFalse
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'ollama.*aos install local' }
    }

    It 'retries the variant and refreshes local state when adopting the existing default' {
        Mock Sync-AosLocalState -ModuleName aos { }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'qwen3.5:4b' }
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 1 -Exactly
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent *' }
    }

    It 'passes DryRun through when adopting the existing default' {
        Mock Sync-AosLocalState -ModuleName aos { }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'qwen3.5:4b' -DryRun }
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
        Test-Path -LiteralPath $stateDir | Should -BeFalse
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama create *' -or $CommandLine -like 'ollama run *' }
    }

    It 'rebuilds the variant when adopting a passing candidate' {
        Mock Get-AosNarHome -ModuleName aos { Join-Path $caseRoot 'nar' }
        Mock Get-AosLocalConfigPath -ModuleName aos { Join-Path $caseRoot 'local.json' }
        Mock Sync-AosLocalState -ModuleName aos { }
        Mock Sync-AosCodexProfiles -ModuleName aos { }
        Write-TestFile (Join-Path $caseRoot 'nar\eval\latest.json') '{"baseline":"qwen3.5:4b","verdicts":{"new:tag":{"passes":true}}}'
        # Re-read the disposable config after adopt writes it, as the real helper does.
        Mock Get-AosLocalConfig -ModuleName aos {
            # Read-AosJson is private to the module: call it in the module's scope.
            & (Get-Module aos) { param($p) Read-AosJson $p } (Join-Path $caseRoot 'local.json')
        } -ParameterFilter { Test-Path -LiteralPath (Join-Path $caseRoot 'local.json') }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nnew:tag abc 3 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        [System.IO.File]::ReadAllText((Join-Path $stateDir 'agent.Modelfile')) | Should -BeExactly "FROM new:tag`nPARAMETER num_ctx 16384`n"
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent *' }
    }

    It 'creates the variant from the local install entry point' {
        foreach ($f in 'Install-AosWingetPackage', 'Install-AosNarTools', 'Install-AosNpmTools', 'Sync-AosPi', 'Sync-AosPlaces') { Mock $f -ModuleName aos { } }
        InModuleScope aos { Install-AosLocal }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent *' }
    }

    It 'refreshes the variant through brain sync with DryRun=<Preview>' -ForEach @(@{ Preview = $false }, @{ Preview = $true }) {
        foreach ($f in 'Set-AosJunction', 'Sync-AosClaudeSkills', 'Set-AosManagedBlock', 'Sync-AosCodexAgents',
                       'Sync-AosClaudeSettings', 'Sync-AosCodexProfiles', 'Sync-AosMcp', 'Sync-AosProfile', 'Sync-AosLocalState',
                       'Sync-AosPi', 'Sync-AosPlaces') {
            Mock $f -ModuleName aos { }
        }
        InModuleScope aos -Parameters @{ Preview = $Preview } { param($Preview) Sync-AosBrain -DryRun:$Preview }
        if ($Preview) {
            Test-Path -LiteralPath $stateDir | Should -BeFalse
            Should -Invoke Write-AosDry -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'ollama create aos-agent' }
            Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'ollama create *' }
        }
        else { Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'ollama create aos-agent *' } }
    }

    It 'shows one status line per variant state, and none without an agent model' {
        $local = [ordered]@{ default = 'qwen3.5:4b'; agent_model = 'aos-agent'; agent_num_ctx = 16384 }
        InModuleScope aos -Parameters @{ L = $local } { param($L) Show-AosAgentModelStatus $L }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'aos-agent missing.*aos install local' }
        $responses.variant = @{ Code = 0; Text = $variantModelfile.Replace('sha256-weights', 'sha256-old') }
        InModuleScope aos -Parameters @{ L = $local } { param($L) Show-AosAgentModelStatus $L }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'aos-agent is not qwen3.5:4b.*aos sync' }
        $responses.variant = @{ Code = 0; Text = $variantModelfile }
        InModuleScope aos -Parameters @{ L = $local } { param($L) Show-AosAgentModelStatus $L }
        Should -Invoke Write-AosOk -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'aos-agent \(qwen3.5:4b, context 16384\)' }
        InModuleScope aos { Show-AosAgentModelStatus ([ordered]@{ default = 'qwen3.5:4b' }) }
        # missing: 1 show (variant); stale and ok: 2 each (variant, then base); no agent model: none
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 5 -Exactly -ParameterFilter { $CommandLine -like 'ollama show *' }
    }
}

Describe 'Phone layer' {
    BeforeEach {
        Mock Get-AosPackages -ModuleName aos { @{ phone_npm = @(@{ name = '@getpaseo/cli'; bin = 'paseo'; why = 't' }) } }
        Mock Install-AosNpmTools -ModuleName aos { }
        Mock Sync-AosPaseo -ModuleName aos { }
        Mock Sync-AosPaseoPlugin -ModuleName aos { }
        Mock Sync-AosPaseoAutostart -ModuleName aos { }
    }

    It 'is an install layer, after local' {
        InModuleScope aos {
            $script:Layers | Should -Contain 'phone'
            [array]::IndexOf($script:Layers, 'phone') | Should -BeGreaterThan ([array]::IndexOf($script:Layers, 'local'))
        }
    }

    It 'installs the phone npm packages and passes DryRun through' {
        InModuleScope aos { Install-AosPhone -DryRun }
        Should -Invoke Install-AosNpmTools -ModuleName aos -Times 1 -Exactly -ParameterFilter { @($Packages)[0]['name'] -eq '@getpaseo/cli' -and $DryRun }
    }

    It 'enables Paseo plugins once, through Paseo''s own CLI' {
        Mock Sync-AosPaseo -ModuleName aos { }
        InModuleScope aos { Install-AosPhone -DryRun }
        Should -Invoke Sync-AosPaseo -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }

    It 'is reachable through aos install phone' {
        Mock Install-AosPhone -ModuleName aos { }
        Mock Show-AosNextSteps -ModuleName aos { }
        InModuleScope aos { Install-AosLayer -Layer phone -DryRun }
        Should -Invoke Install-AosPhone -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'Codex local profile' {
    It 'generates no Codex local profile: its agent prompt does not fit a context the GPU holds' {
        # Codex's own prompt is about 45K tokens; a 64K context spills the 2B model 27% onto the CPU.
        Mock Get-AosLocalConfig -ModuleName aos { [ordered]@{ default = 'openbmb/minicpm5-2b:q8_0' } }
        InModuleScope aos { @(Get-AosCodexProfiles | Where-Object { $_.Name -eq 'local' }).Count | Should -Be 0 }
    }
    It 'generates no local profile without a local config' {
        Mock Get-AosLocalConfig -ModuleName aos { $null }
        InModuleScope aos { @(Get-AosCodexProfiles | Where-Object { $_.Name -eq 'local' }).Count | Should -Be 0 }
    }
}

Describe 'MCP placeholders and nar registration' {
    BeforeEach {
        $savedMcpState = $env:AOS_MCP_STATE
        $env:AOS_MCP_STATE = Join-Path $TestDrive 'mcp-registered.json'
        Remove-Item -LiteralPath $env:AOS_MCP_STATE -ErrorAction SilentlyContinue
        $savedProjects = $env:AOS_PROJECTS
        $env:AOS_PROJECTS = Join-Path $caseRoot 'projects'
        $exe = Join-Path $env:AOS_PROJECTS 'nar-tools\nar-mcp.exe'
        Mock Add-AosMcpServer -ModuleName aos { $true }
        Mock Write-AosInfo -ModuleName aos { }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -in @('claude', 'codex') }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 1; Text = 'No MCP server found' } } -ParameterFilter { $CommandLine -like '* mcp get *' }
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{ nar = [ordered]@{
                transport = 'stdio'; command = '{{projects}}\nar-tools\nar-mcp.exe'; args = @()
                requires = '{{projects}}\nar-tools\nar-mcp.exe' } } }
        }
    }
    AfterEach { $env:AOS_PROJECTS = $savedProjects; $env:AOS_MCP_STATE = $savedMcpState }

    It 'removes a recorded server dropped from the manifest' {
        Write-TestFile $env:AOS_MCP_STATE '{"claude":["old"],"codex":[]}'
        Mock Get-AosMcpManifest -ModuleName aos { [ordered]@{ servers = [ordered]@{} } }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '' } } -ParameterFilter { $CommandLine -eq 'claude mcp remove old --scope user' }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'claude mcp remove old --scope user' }
        @((Get-Content $env:AOS_MCP_STATE -Raw | ConvertFrom-Json).claude).Count | Should -Be 0
    }

    It 'leaves unrecorded user servers alone' {
        Mock Get-AosMcpManifest -ModuleName aos { [ordered]@{ servers = [ordered]@{} } }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like '* mcp remove *' }
    }

    It 'keeps recorded servers and state unchanged in dry run' {
        $original = '{"claude":["old"],"codex":[]}'
        Write-TestFile $env:AOS_MCP_STATE $original
        Mock Get-AosMcpManifest -ModuleName aos { [ordered]@{ servers = [ordered]@{} } }
        InModuleScope aos { Sync-AosMcp -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like '* mcp remove *' }
        Get-Content $env:AOS_MCP_STATE -Raw | Should -BeExactly $original
    }

    It 'removes a Claude-only server only from recorded Codex registrations' {
        Write-TestFile $env:AOS_MCP_STATE '{"claude":[],"codex":["research"]}'
        Mock Get-AosMcpManifest -ModuleName aos { [ordered]@{ servers = [ordered]@{ research = [ordered]@{ transport = 'http'; url = 'https://example.test/mcp'; agents = @('claude') } } } }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '' } } -ParameterFilter { $CommandLine -eq 'codex mcp remove research' }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'codex mcp remove research' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -eq 'claude mcp remove research --scope user' }
        @((Get-Content $env:AOS_MCP_STATE -Raw | ConvertFrom-Json).codex).Count | Should -Be 0
    }

    It 'keeps a failed removal recorded for retry' {
        Write-TestFile $env:AOS_MCP_STATE '{"claude":["old"],"codex":[]}'
        Mock Get-AosMcpManifest -ModuleName aos { [ordered]@{ servers = [ordered]@{} } }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 1; Text = 'failed' } } -ParameterFilter { $CommandLine -eq 'claude mcp remove old --scope user' }
        Mock Write-AosWarn -ModuleName aos { }
        InModuleScope aos { Sync-AosMcp }
        @((Get-Content $env:AOS_MCP_STATE -Raw | ConvertFrom-Json).claude) | Should -Contain 'old'
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'removing old failed' }
    }

    It 'expands the projects and home placeholders' {
        InModuleScope aos {
            Expand-AosPlaceholders '{{projects}}\x' | Should -BeExactly (Join-Path $env:AOS_PROJECTS 'x')
            Expand-AosPlaceholders '{{home}}\.aos' | Should -BeExactly ($HOME + '\.aos')
        }
    }

    It 'skips a server whose required file does not exist yet' {
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosInfo -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'nar skipped' }
    }

    It 'registers the expanded command in both agents once the file exists' {
        Write-TestFile $exe ''
        InModuleScope aos { Sync-AosMcp }
        # PowerShell names are case-insensitive: the loop variable must not be called $agent.
        foreach ($want in 'claude', 'codex') {
            Should -Invoke Add-AosMcpServer -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Agent -eq $want -and $Command[0] -eq $exe -and -not $Http }
        }
    }

    It 'treats a registration as current when the CLI shows the command, even JSON-escaped' {
        Write-TestFile $exe ''
        $escaped = $exe.Replace('\', '\\')
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "{`"transport`": {`"type`": `"stdio`", `"command`": `"$escaped`"}}" } } -ParameterFilter { $CommandLine -eq 'codex mcp get nar --json' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "nar:`n  Command: $exe" } } -ParameterFilter { $CommandLine -eq 'claude mcp get nar' }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 0 -Exactly
    }

    It 'registers a server only in the agents its manifest entry lists' {
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{ research = [ordered]@{
                transport = 'http'; url = 'https://example.test/mcp'; agents = @('claude') } } }
        }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Agent -eq 'claude' -and $Http }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 0 -Exactly -ParameterFilter { $Agent -eq 'codex' }
    }

    It 'does not even query Codex for a Claude-only server' {
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{ research = [ordered]@{
                transport = 'http'; url = 'https://example.test/mcp'; agents = @('claude') } } }
        }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'codex mcp *' }
    }

    It 'names the agents a manifest entry targets: both by default, the listed ones otherwise' {
        InModuleScope aos {
            @(Get-AosMcpTargets ([ordered]@{ transport = 'http' })) -join ',' | Should -BeExactly 'claude,codex'
            @(Get-AosMcpTargets ([ordered]@{ agents = @('claude') })) -join ',' | Should -BeExactly 'claude'
            @(Get-AosMcpTargets ([ordered]@{ agents = @('codex') })) -join ',' | Should -BeExactly 'codex'
        }
    }

    It 'does not warn in aos status that a Claude-only server is missing from Codex' {
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{ research = [ordered]@{
                transport = 'http'; url = 'https://example.test/mcp'; agents = @('claude') } } }
        }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'research: https://example.test/mcp' } } -ParameterFilter { $CommandLine -eq 'claude mcp list' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '' } } -ParameterFilter { $CommandLine -eq 'codex mcp list' }
        Mock Write-AosWarn -ModuleName aos { }
        InModuleScope aos { Show-AosMcpStatus }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 0 -Exactly -ParameterFilter { $Text -match 'codex: research' }
    }

    It 'registers a server with no agents list in both agents' {
        Mock Get-AosMcpManifest -ModuleName aos {
            [ordered]@{ servers = [ordered]@{ both = [ordered]@{ transport = 'http'; url = 'https://example.test/both' } } }
        }
        InModuleScope aos { Sync-AosMcp }
        Should -Invoke Add-AosMcpServer -ModuleName aos -Times 2 -Exactly
    }
}

Describe 'Shared tool awareness' {
    BeforeAll { $skills = Join-Path $PSScriptRoot '..\agents-home\skills' }
    It 'has valid frontmatter and a short description for <name>' -ForEach @(@{ name = 'research' }, @{ name = 'tool-catalog' }) {
        $path = Join-Path $skills "$name\SKILL.md"
        Test-Path -LiteralPath $path | Should -BeTrue
        $m = [regex]::Match([IO.File]::ReadAllText($path), "(?s)^---\r?\nname: $name\r?\ndescription: (?<d>[^\r\n]+)\r?\n---")
        $m.Success | Should -BeTrue
        $m.Groups['d'].Value.Length | Should -BeLessOrEqual 250
    }
    It 'lists every shared skill and every registered MCP server in the catalog' {
        $catalog = [IO.File]::ReadAllText((Join-Path $skills 'tool-catalog\SKILL.md'))
        foreach ($dir in Get-ChildItem -LiteralPath $skills -Directory) {
            $catalog.Contains($dir.Name) | Should -BeTrue -Because "skill $($dir.Name) must be in the catalog"
        }
        $manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\config\mcp.json')) | ConvertFrom-Json
        foreach ($server in $manifest.servers.PSObject.Properties.Name) {
            $catalog.Contains($server) | Should -BeTrue -Because "MCP server $server must be in the catalog"
        }
    }
    It 'points both agents at the catalog from the global contract' {
        [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\agents-home\AGENTS.md')).Contains('tool-catalog') | Should -BeTrue
    }
}

Describe 'aos local adopt' {
    BeforeAll {
        function Write-Report($Verdicts, [string]$Baseline = 'old:tag') {
            $report = [ordered]@{ baseline = $Baseline; verdicts = $Verdicts }
            Write-TestFile (Join-Path $env:NAR_HOME 'eval\latest.json') (ConvertTo-Json -Depth 10 -InputObject $report)
        }
    }
    BeforeEach {
        $savedNar = $env:NAR_HOME
        $env:NAR_HOME = Join-Path $caseRoot 'nar'
        $configPath = Join-Path $caseRoot 'local.json'
        Write-TestFile $configPath '{ "default": "old:tag", "optional": [] }'
        Mock Get-AosLocalConfigPath -ModuleName aos { $configPath }
        Mock Sync-AosLocalState -ModuleName aos { }
        Mock Sync-AosCodexProfiles -ModuleName aos { }
        Mock Write-AosWarn -ModuleName aos { }
    }
    AfterEach { $env:NAR_HOME = $savedNar }

    It 'refuses without an eval report' {
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'no eval report' }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 0 -Exactly
    }

    It 'refuses a report made against another baseline' {
        Write-Report @{ 'new:tag' = @{ passes = $true; reasons = @() } } 'other:tag'
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'other:tag' }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
    }

    It 'refuses a candidate that did not pass, naming the reasons' {
        Write-Report @{ 'new:tag' = @{ passes = $false; reasons = @('worse calibration than the current default') } }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'worse calibration' }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
    }

    It 'adopts a passing candidate and regenerates the derived files' {
        Write-Report @{ 'new:tag' = @{ passes = $true; reasons = @() } }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' }
        (Get-Content -Raw $configPath | ConvertFrom-Json).default | Should -BeExactly 'new:tag'
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 1 -Exactly
        Should -Invoke Sync-AosCodexProfiles -ModuleName aos -Times 1 -Exactly
    }

    It 'changes nothing in DryRun' {
        Write-Report @{ 'new:tag' = @{ passes = $true; reasons = @() } }
        InModuleScope aos { Invoke-AosLocalAdopt -Tag 'new:tag' -DryRun }
        (Get-Content -Raw $configPath) | Should -Match '"old:tag"'
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Brain sync includes the local state' {
    BeforeEach {
        foreach ($f in 'Set-AosJunction', 'Sync-AosClaudeSkills', 'Set-AosManagedBlock', 'Sync-AosCodexAgents',
                       'Sync-AosClaudeSettings', 'Sync-AosCodexProfiles', 'Sync-AosMcp', 'Sync-AosProfile', 'Sync-AosLocalState',
                       'Sync-AosAgentModel', 'Sync-AosPi', 'Sync-AosPlaces') {
            Mock $f -ModuleName aos { }
        }
    }

    It 'refreshes ~\.aos\local.json and passes DryRun through' {
        InModuleScope aos { Sync-AosBrain -DryRun }
        Should -Invoke Sync-AosLocalState -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'aos nar dispatch' {
    It 'forwards long options unchanged' {
        Mock Invoke-AosNar -ModuleName aos { }
        aos nar choose 'Which is larger?' --option 7 --option 12
        Should -Invoke Invoke-AosNar -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join '|') -ceq 'choose|Which is larger?|--option|7|--option|12'
        }
    }
}

Describe 'Paseo config' {
    BeforeEach {
        $savedPaseoHome = $env:PASEO_HOME
        $env:PASEO_HOME = Join-Path $caseRoot 'paseo'
        $script:pluginsJson = '{ "source": "configured", "path": "pluginsEnabled", "set": false }'
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'paseo' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $script:pluginsJson } } -ParameterFilter { $CommandLine -eq 'paseo daemon config get pluginsEnabled --json' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = '{ "action": "saved", "applied": false }' } } -ParameterFilter { $CommandLine -like 'paseo daemon config set *' }
        foreach ($f in 'Write-AosOk', 'Write-AosInfo', 'Write-AosDry', 'Write-AosWarn') { Mock $f -ModuleName aos { } }
    }

    AfterEach { $env:PASEO_HOME = $savedPaseoHome }

    It 'backs up the configured Paseo home before changing config' {
        $configPath = Join-Path $env:PASEO_HOME 'config.json'
        Write-TestFile $configPath '{ "privateSetting": "preserve" }'
        Mock Invoke-AosCapture -ModuleName aos {
            $saved = @(Get-ChildItem $env:AOS_BACKUPS -Recurse -Filter config.json | Where-Object {
                [IO.File]::ReadAllText($_.FullName) -eq '{ "privateSetting": "preserve" }'
            })
            $saved.Count | Should -BeGreaterThan 0
            @{ Code = 0; Text = 'saved' }
        } -ParameterFilter { $CommandLine -like 'paseo daemon config set *' }
        InModuleScope aos { Sync-AosPaseo }
    }

    It 'backs up the default Paseo home before changing config' {
        $env:PASEO_HOME = $null
        $configPath = Join-Path $caseRoot '.paseo\config.json'
        Write-TestFile $configPath '{}'
        Mock Backup-AosFile -ModuleName aos { }
        InModuleScope aos -Parameters @{ HomeDir = $caseRoot } {
            param($HomeDir)
            # Function-local HOME shadows the automatic variable without changing the real profile.
            function Invoke-WithTestHome { $HOME = $HomeDir; Sync-AosPaseo }
            Invoke-WithTestHome
        }
        Should -Invoke Backup-AosFile -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Path -eq $configPath }
    }

    It 'does not set config or report success when its backup fails' {
        Write-TestFile (Join-Path $env:PASEO_HOME 'config.json') '{}'
        Mock Backup-AosFile -ModuleName aos { throw 'backup refused' }
        { InModuleScope aos { Sync-AosPaseo } } | Should -Throw '*backup refused*'
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'paseo daemon config set *' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }

    It 'turns plugins on when they are not set' {
        InModuleScope aos { Sync-AosPaseo }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'paseo daemon config set pluginsEnabled true' }
    }

    It 'turns plugins on when they are off' {
        $script:pluginsJson = '{ "source": "configured", "path": "pluginsEnabled", "set": true, "value": false }'
        InModuleScope aos { Sync-AosPaseo }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq 'paseo daemon config set pluginsEnabled true' }
    }

    It 'sets nothing when plugins are already on' {
        $script:pluginsJson = '{ "source": "configured", "path": "pluginsEnabled", "set": true, "value": true }'
        InModuleScope aos { Sync-AosPaseo }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'paseo daemon config set *' }
    }

    It 'sets nothing in DryRun' {
        InModuleScope aos { Sync-AosPaseo -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'paseo daemon config set *' }
        Should -Invoke Write-AosDry -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'pluginsEnabled' }
    }

    It 'warns and sets nothing when the setting cannot be read' {
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 1; Text = 'error' } } -ParameterFilter { $CommandLine -eq 'paseo daemon config get pluginsEnabled --json' }
        InModuleScope aos { Sync-AosPaseo }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'paseo daemon config set *' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
    }

    It 'does nothing without paseo' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'paseo' }
        InModuleScope aos { Sync-AosPaseo }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Paseo aos plugin' {
    BeforeEach {
        $pluginDir = Join-Path $caseRoot 'projects\nar-tools\paseo-plugin'
        Write-TestFile (Join-Path $pluginDir 'paseo-plugin.json') '{ "id": "aos" }'
        $script:pluginList = '[]'
        Mock Get-AosPaseoPluginDir -ModuleName aos { $pluginDir }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'paseo' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $script:pluginList } } -ParameterFilter { $CommandLine -eq 'paseo plugin ls --json' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'ok' } } -ParameterFilter { $CommandLine -like 'paseo plugin install *' -or $CommandLine -eq 'paseo plugin remove aos' }
        foreach ($f in 'Write-AosOk', 'Write-AosDry', 'Write-AosWarn') { Mock $f -ModuleName aos { } }
    }

    It 'installs the plugin from nar-tools when Paseo does not have it' {
        InModuleScope aos { Sync-AosPaseoPlugin }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -eq ('paseo plugin install "' + $pluginDir + '"') }
    }

    It 'does nothing when Paseo already runs it from that folder' {
        $script:pluginList = '[ { "id": "aos", "path": "' + $pluginDir.Replace('\', '\\') + '\\", "enabled": true, "status": "running" } ]'
        InModuleScope aos { Sync-AosPaseoPlugin }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'paseo plugin install *' -or $CommandLine -eq 'paseo plugin remove aos' }
    }

    It 'moves it when Paseo runs it from another folder, and leaves other plugins alone' {
        $script:pluginList = '[ { "id": "other", "path": "C:\\x" }, { "id": "aos", "path": "C:\\old\\paseo-plugin" } ]'
        InModuleScope aos { Sync-AosPaseoPlugin }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -eq 'paseo plugin remove aos' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 1 -Exactly -ParameterFilter { $CommandLine -like 'paseo plugin install *' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like '*remove other*' }
    }

    It 'keeps the old registration on an install failure unrelated to a duplicate id' {
        $script:pluginList = '[ { "id": "aos", "path": "C:\\old\\paseo-plugin" } ]'
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 1; Text = 'build failed' } } -ParameterFilter { $CommandLine -like 'paseo plugin install *' }
        InModuleScope aos { Sync-AosPaseoPlugin }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -eq 'paseo plugin remove aos' }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }

    It 'stops if removing a duplicate registration fails' {
        $script:pluginList = '[ { "id": "aos", "path": "C:\\old\\paseo-plugin" } ]'
        $calls = New-Object 'System.Collections.Generic.List[string]'
        Mock Invoke-AosCapture -ModuleName aos {
            $calls.Add($CommandLine)
            @{ Code = 1; Text = 'Plugin aos already installed' }
        } -ParameterFilter { $CommandLine -like 'paseo plugin install *' }
        Mock Invoke-AosCapture -ModuleName aos {
            $calls.Add($CommandLine)
            @{ Code = 1; Text = 'remove failed' }
        } -ParameterFilter { $CommandLine -eq 'paseo plugin remove aos' }
        InModuleScope aos { Sync-AosPaseoPlugin }
        ($calls -join '|') | Should -Be ('paseo plugin install "' + $pluginDir + '"|paseo plugin remove aos')
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'remove' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }

    It 'restores the old path after a duplicate replacement fails (restore exit <RestoreCode>)' -TestCases @(
        @{ RestoreCode = 0 }, @{ RestoreCode = 1 }
    ) {
        param($RestoreCode)
        $oldDir = Join-Path $caseRoot 'old plugin'
        $script:pluginList = ConvertTo-Json -InputObject @(@{ id = 'aos'; path = $oldDir })
        $calls = New-Object 'System.Collections.Generic.List[string]'
        Mock Invoke-AosCapture -ModuleName aos {
            $calls.Add($CommandLine)
            if ($calls.Count -eq 1) { return @{ Code = 1; Text = 'Plugin aos already installed' } }
            if ($CommandLine -eq 'paseo plugin remove aos') { return @{ Code = 0; Text = 'removed' } }
            if ($CommandLine -eq ('paseo plugin install "' + $oldDir + '"')) { return @{ Code = $RestoreCode; Text = 'restore' } }
            return @{ Code = 1; Text = 'build failed' }
        } -ParameterFilter { $CommandLine -like 'paseo plugin install *' -or $CommandLine -eq 'paseo plugin remove aos' }
        InModuleScope aos { Sync-AosPaseoPlugin }
        ($calls -join '|') | Should -Be ('paseo plugin install "' + $pluginDir + '"|paseo plugin remove aos|paseo plugin install "' + $pluginDir + '"|paseo plugin install "' + $oldDir + '"')
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'install.*failed' }
        if ($RestoreCode -ne 0) { Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'restor.*failed' } }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }

    It 'repairs matching paths with enabled=<Enabled> and status=<Status>' -TestCases @(
        @{ Enabled = $false; Status = 'disabled'; Enables = 1; Reloads = 1; StillFailed = $false },
        @{ Enabled = $true; Status = 'failed'; Enables = 0; Reloads = 1; StillFailed = $true },
        @{ Enabled = $true; Status = 'running'; Enables = 0; Reloads = 0; StillFailed = $false }
    ) {
        param($Enabled, $Status, $Enables, $Reloads, $StillFailed)
        $state = @{ id = 'aos'; path = $pluginDir; enabled = $Enabled; status = $Status }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = (ConvertTo-Json -InputObject @($state)) } } -ParameterFilter { $CommandLine -eq 'paseo plugin ls --json' }
        Mock Invoke-AosCapture -ModuleName aos { $state.enabled = $true; @{ Code = 0; Text = 'enabled' } } -ParameterFilter { $CommandLine -eq 'paseo plugin enable aos' }
        Mock Invoke-AosCapture -ModuleName aos {
            if (-not $StillFailed) { $state.status = 'running' }
            @{ Code = 0; Text = 'reloaded' }
        } -ParameterFilter { $CommandLine -eq 'paseo plugin reload aos' }
        InModuleScope aos { Sync-AosPaseoPlugin }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times $Enables -Exactly -ParameterFilter { $CommandLine -eq 'paseo plugin enable aos' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times $Reloads -Exactly -ParameterFilter { $CommandLine -eq 'paseo plugin reload aos' }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times (1 + $Reloads) -Exactly -ParameterFilter { $CommandLine -eq 'paseo plugin ls --json' }
        if ($StillFailed) {
            Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'not running' }
            Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
        }
    }

    It 'changes nothing in DryRun' {
        InModuleScope aos { Sync-AosPaseoPlugin -DryRun }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly -ParameterFilter { $CommandLine -like 'paseo plugin install *' }
        Should -Invoke Write-AosDry -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'paseo plugin install' }
    }

    It 'warns when nar-tools has no plugin folder' {
        Mock Get-AosPaseoPluginDir -ModuleName aos { Join-Path $caseRoot 'missing' }
        InModuleScope aos { Sync-AosPaseoPlugin }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
    }

    It 'runs from aos install phone' {
        Mock Get-AosPackages -ModuleName aos { @{ phone_npm = @() } }
        foreach ($f in 'Install-AosNpmTools', 'Sync-AosPaseo', 'Sync-AosPaseoPlugin', 'Sync-AosPaseoAutostart') { Mock $f -ModuleName aos { } }
        InModuleScope aos { Install-AosPhone -DryRun }
        Should -Invoke Sync-AosPaseoPlugin -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'Paseo daemon at logon' {
    BeforeEach {
        $script:existingTask = $null
        $script:wantArgs = '-NoProfile -WindowStyle Hidden -Command "& ''C:\u\.npm-global\paseo.cmd'' daemon start"'
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'paseo' }
        Mock Get-AosPaseoAutostartCommand -ModuleName aos { @{ Execute = 'C:\ps\pwsh.exe'; Arguments = $script:wantArgs } }
        Mock Get-AosLogonTaskState -ModuleName aos { $script:existingTask }
        # Register-ScheduledTask is a CDXML command whose dynamic parameters cannot be mocked; aos wraps it
        # in Register-AosLogonTask (checked live: at logon, also on battery).
        Mock Register-AosLogonTask -ModuleName aos { }
        foreach ($f in 'Write-AosOk', 'Write-AosDry', 'Write-AosWarn', 'Write-AosInfo') { Mock $f -ModuleName aos { } }
    }

    It 'registers a task that starts the daemon at logon' {
        InModuleScope aos { Sync-AosPaseoAutostart }
        Should -Invoke Register-AosLogonTask -ModuleName aos -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'agentic-os Paseo daemon' -and $Execute -eq 'C:\ps\pwsh.exe' -and $Arguments -eq $script:wantArgs
        }
    }

    It 'does nothing when the task already runs the same command' {
        $script:existingTask = [pscustomobject]@{
            Actions = @([pscustomobject]@{ Execute = 'C:\ps\pwsh.exe'; Arguments = $script:wantArgs })
            Enabled = $true; HasCurrentUserLogonTrigger = $true; RepeatsEvery5Minutes = $true
            DisallowStartIfOnBatteries = $false; StopIfGoingOnBatteries = $false
        }
        InModuleScope aos { Sync-AosPaseoAutostart }
        Should -Invoke Register-AosLogonTask -ModuleName aos -Times 0 -Exactly
    }

    It 'repairs task drift in <Field>' -TestCases @(
        @{ Field = 'Enabled'; Value = $false },
        @{ Field = 'HasCurrentUserLogonTrigger'; Value = $false },
        @{ Field = 'DisallowStartIfOnBatteries'; Value = $true },
        @{ Field = 'StopIfGoingOnBatteries'; Value = $true },
        @{ Field = 'RepeatsEvery5Minutes'; Value = $false }
    ) {
        param($Field, $Value)
        $script:existingTask = [pscustomobject]@{
            Actions = @([pscustomobject]@{ Execute = 'C:\ps\pwsh.exe'; Arguments = $script:wantArgs })
            Enabled = $true; HasCurrentUserLogonTrigger = $true; RepeatsEvery5Minutes = $true
            DisallowStartIfOnBatteries = $false; StopIfGoingOnBatteries = $false
        }
        $script:existingTask.$Field = $Value
        InModuleScope aos { Sync-AosPaseoAutostart }
        Should -Invoke Register-AosLogonTask -ModuleName aos -Times 1 -Exactly
    }

    It 'replaces the task when its command changed' {
        $script:existingTask = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = 'C:\old\pwsh.exe'; Arguments = 'old' }) }
        InModuleScope aos { Sync-AosPaseoAutostart }
        Should -Invoke Register-AosLogonTask -ModuleName aos -Times 1 -Exactly
    }

    It 'warns instead of failing when Windows refuses the task' {
        Mock Register-AosLogonTask -ModuleName aos { throw 'Access is denied' }
        InModuleScope aos { Sync-AosPaseoAutostart }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'Access is denied' }
    }

    It 'registers nothing in DryRun' {
        InModuleScope aos { Sync-AosPaseoAutostart -DryRun }
        Should -Invoke Register-AosLogonTask -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosDry -ModuleName aos -Times 1
    }

    It 'does nothing without paseo' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'paseo' }
        InModuleScope aos { Sync-AosPaseoAutostart }
        Should -Invoke Register-AosLogonTask -ModuleName aos -Times 0 -Exactly
    }

    It 'runs from aos install phone' {
        Mock Get-AosPackages -ModuleName aos { @{ phone_npm = @() } }
        foreach ($f in 'Install-AosNpmTools', 'Sync-AosPaseo', 'Sync-AosPaseoPlugin', 'Sync-AosPaseoAutostart') { Mock $f -ModuleName aos { } }
        InModuleScope aos { Install-AosPhone -DryRun }
        Should -Invoke Sync-AosPaseoAutostart -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'Logon task state' {
    # Real tasks are CIM objects: the checked fields sit under Settings and Triggers.
    BeforeAll {
        function New-TestTrigger([string]$Class, [string]$User, $Enabled = $true, [string]$Interval = '') {
            $t = [pscustomobject]@{ UserId = $User; Enabled = $Enabled; Repetition = [pscustomobject]@{ Interval = $Interval } }
            $t.PSObject.TypeNames.Insert(0, "Microsoft.Management.Infrastructure.CimInstance#Root/Microsoft/Windows/TaskScheduler/$Class")
            return $t
        }
        function New-TestTask($Triggers, [bool]$Enabled = $true, [bool]$Disallow = $false, [bool]$Stop = $false) {
            [pscustomobject]@{
                Actions = @([pscustomobject]@{ Execute = 'x.exe'; Arguments = 'a' })
                Settings = [pscustomobject]@{ Enabled = $Enabled; DisallowStartIfOnBatteries = $Disallow; StopIfGoingOnBatteries = $Stop }
                Triggers = @($Triggers)
            }
        }
        $me = "$env:USERDOMAIN\$env:USERNAME"
    }

    It 'flattens a healthy task' {
        $task = New-TestTask (New-TestTrigger 'MSFT_TaskLogonTrigger' $me)
        $s = InModuleScope aos -Parameters @{ Task = $task } { param($Task) ConvertTo-AosLogonTaskState $Task }
        $s.Enabled | Should -BeTrue
        $s.HasCurrentUserLogonTrigger | Should -BeTrue
        $s.DisallowStartIfOnBatteries | Should -BeFalse
        $s.StopIfGoingOnBatteries | Should -BeFalse
        @($s.Actions)[0].Execute | Should -Be 'x.exe'
    }

    It 'reads the 5-minute repetition that restarts a daemon that died' {
        $task = New-TestTask (New-TestTrigger 'MSFT_TaskLogonTrigger' $me -Interval 'PT5M')
        $s = InModuleScope aos -Parameters @{ Task = $task } { param($Task) ConvertTo-AosLogonTaskState $Task }
        $s.RepeatsEvery5Minutes | Should -BeTrue
        $task = New-TestTask (New-TestTrigger 'MSFT_TaskLogonTrigger' $me)
        $s = InModuleScope aos -Parameters @{ Task = $task } { param($Task) ConvertTo-AosLogonTaskState $Task }
        $s.RepeatsEvery5Minutes | Should -BeFalse
    }

    It 'reports settings drift' {
        $task = New-TestTask (New-TestTrigger 'MSFT_TaskLogonTrigger' $me) -Enabled $false -Disallow $true -Stop $true
        $s = InModuleScope aos -Parameters @{ Task = $task } { param($Task) ConvertTo-AosLogonTaskState $Task }
        $s.Enabled | Should -BeFalse
        $s.DisallowStartIfOnBatteries | Should -BeTrue
        $s.StopIfGoingOnBatteries | Should -BeTrue
    }

    It 'finds no current-user logon trigger in <Case>' -TestCases @(
        @{ Case = 'another user'; Class = 'MSFT_TaskLogonTrigger'; User = 'OTHER\someone'; On = $true },
        @{ Case = 'a boot trigger'; Class = 'MSFT_TaskBootTrigger'; User = 'SELF'; On = $true },
        @{ Case = 'a disabled trigger'; Class = 'MSFT_TaskLogonTrigger'; User = 'SELF'; On = $false }
    ) {
        param($Case, $Class, $User, $On)
        if ($User -eq 'SELF') { $User = $me }
        $task = New-TestTask (New-TestTrigger $Class $User $On)
        $s = InModuleScope aos -Parameters @{ Task = $task } { param($Task) ConvertTo-AosLogonTaskState $Task }
        $s.HasCurrentUserLogonTrigger | Should -BeFalse
    }
}

Describe 'Pi directory resolution' {
    BeforeEach {
        $savedProjectsForPi = $env:AOS_PROJECTS
        $env:AOS_PROJECTS = Join-Path $caseRoot 'projects'
    }
    AfterEach { $env:AOS_PROJECTS = $savedProjectsForPi }
    It 'resolves place roots and skips unknown placeholders' {
        Mock Get-AosDesktopDir -ModuleName aos { $caseRoot }
        InModuleScope aos -Parameters @{ Root = $caseRoot } {
            param($Root)
            Resolve-AosPlacePath '{{desktop}}\project' | Should -Be (Join-Path $Root 'project')
            Resolve-AosPlacePath '{{unknown}}\project' | Should -BeNullOrEmpty
        }
    }

    It 'validates places, keeps missing folders absent and warns on duplicate names' {
        $cfg = Join-Path $caseRoot 'places.json'
        Mock Get-AosPlacesConfigPath -ModuleName aos { $cfg }
        Mock Get-AosDesktopDir -ModuleName aos { $caseRoot }
        Mock Write-AosWarn -ModuleName aos { }
        Write-TestFile $cfg '{"places":[{"name":"repo","kind":"repo","path":"{{desktop}}\\missing"},{"name":"repo","kind":"folder","path":"{{desktop}}\\other"},{"name":"inbox","kind":"inbox","path":"{{desktop}}\\Inbox"}]}'
        $places = @(InModuleScope aos { Get-AosPlaces })
        $places.Count | Should -Be 2
        $places[0].exists | Should -BeFalse
        Test-Path (Join-Path $caseRoot 'missing') | Should -BeFalse
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly
    }

    BeforeEach { $savedPiDir = $env:PI_CODING_AGENT_DIR }
    AfterEach { $env:PI_CODING_AGENT_DIR = $savedPiDir }

    It 'expands a leading home tilde' {
        $env:PI_CODING_AGENT_DIR = '~\isolated-pi'
        InModuleScope aos { Get-AosPiDir } | Should -Be (Join-Path $HOME 'isolated-pi')
    }

    It 'resolves a relative directory against the PowerShell location' {
        Push-Location $caseRoot
        try {
            $env:PI_CODING_AGENT_DIR = '.\relative-pi'
            InModuleScope aos { Get-AosPiDir } | Should -Be (Join-Path $caseRoot 'relative-pi')
        }
        finally { Pop-Location }
    }
}

Describe 'Backup failure safety' {
    It 'throws on a copy failure even when the caller continues on errors' {
        $missing = Join-Path $caseRoot 'missing.json'
        { InModuleScope aos -Parameters @{ Path = $missing } {
            param($Path)
            $ErrorActionPreference = 'Continue'
            Backup-AosFile $Path 2>$null
        } } | Should -Throw
    }

    It 'throws on a backup directory failure even when the caller continues on errors' {
        $dest = Join-Path $caseRoot 'not-a-directory'
        Write-TestFile $dest 'file'
        Mock New-AosBackupPath -ModuleName aos { Join-Path $dest 'child' }
        Mock Copy-Item -ModuleName aos { }
        { InModuleScope aos {
            $ErrorActionPreference = 'Continue'
            Backup-AosFile 'unused' 2>$null
        } } | Should -Throw
        Should -Invoke Copy-Item -ModuleName aos -Times 0 -Exactly
    }

    It 'does not write JSON or report success after a failed backup' {
        $path = Join-Path $caseRoot 'settings.json'
        Write-TestFile $path '{"keep":true}'
        Mock Backup-AosFile -ModuleName aos { throw 'backup refused' }
        Mock Write-AosOk -ModuleName aos { }
        { InModuleScope aos -Parameters @{ Path = $path } {
            param($Path)
            Set-AosJsonFile -Path $Path -Old @{ keep = $true } -New @{ keep = $false } -Label 'test'
        } } | Should -Throw '*backup refused*'
        [IO.File]::ReadAllText($path) | Should -BeExactly '{"keep":true}'
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }
}

Describe 'Modelfile semantic comparison' {
    It 'detects <Change> within a triple quoted template' -TestCases @(
        @{ Change = 'line order'; Before = "first`nsecond"; After = "second`nfirst" },
        @{ Change = 'hash lines'; Before = "# first`ntext"; After = "# second`ntext" },
        @{ Change = 'indentation'; Before = '  text'; After = 'text' },
        @{ Change = 'blank lines'; Before = "first`n`nsecond"; After = "first`nsecond" }
    ) {
        param($Change, $Before, $After)
        $base = 'FROM weights' + "`n" + 'TEMPLATE """' + "`n$Before`n" + '"""'
        $variant = 'FROM weights' + "`n" + 'TEMPLATE """' + "`n$After`n" + '"""' + "`nPARAMETER num_ctx 16384"
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $base } } -ParameterFilter { $CommandLine -eq 'ollama show base --modelfile' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $variant } } -ParameterFilter { $CommandLine -eq 'ollama show variant --modelfile' }
        InModuleScope aos { Test-AosAgentModel -Name variant -From base -NumCtx 16384 } | Should -Be 'stale'
    }

    It 'compares parameters as a set while ignoring outside comments and num_ctx' {
        $base = "FROM weights`nPARAMETER top_k 20`nPARAMETER temperature 1`n# base"
        $variant = "# variant`nFROM weights`nPARAMETER temperature 1`nPARAMETER top_k 20`nPARAMETER top_k 20`nPARAMETER num_ctx 16384"
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $base } } -ParameterFilter { $CommandLine -eq 'ollama show base --modelfile' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $variant } } -ParameterFilter { $CommandLine -eq 'ollama show variant --modelfile' }
        InModuleScope aos { Test-AosAgentModel -Name variant -From base -NumCtx 16384 } | Should -Be 'ok'
    }

    It 'preserves the order of non-parameter directives' {
        $base = "FROM weights`nMESSAGE user hello`nMESSAGE assistant hi"
        $variant = "FROM weights`nMESSAGE assistant hi`nMESSAGE user hello`nPARAMETER num_ctx 16384"
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $base } } -ParameterFilter { $CommandLine -eq 'ollama show base --modelfile' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = $variant } } -ParameterFilter { $CommandLine -eq 'ollama show variant --modelfile' }
        InModuleScope aos { Test-AosAgentModel -Name variant -From base -NumCtx 16384 } | Should -Be 'stale'
    }
}

Describe 'Paseo daemon startup' {
    BeforeAll {
        # Test-only seams until the new scheduler wrapper and startup function exist.
        InModuleScope aos {
            if (-not (Get-Command Start-AosLogonTask -ErrorAction SilentlyContinue)) {
                function script:Start-AosLogonTask { param($Name) throw 'startup wrapper missing' }
            }
            if (-not (Get-Command Start-AosPaseoDaemon -ErrorAction SilentlyContinue)) {
                function script:Start-AosPaseoDaemon { param([switch]$DryRun) throw 'daemon startup missing' }
            }
        }
    }
    BeforeEach {
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'paseo' }
        Mock Start-AosLogonTask -ModuleName aos { }
        Mock Start-Sleep -ModuleName aos { }
        foreach ($f in 'Write-AosOk', 'Write-AosWarn', 'Write-AosDry') { Mock $f -ModuleName aos { } }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = 'localDaemon: running' } } -ParameterFilter { $CommandLine -eq 'paseo daemon status' }
    }

    It 'does not start an already running daemon' {
        InModuleScope aos { Start-AosPaseoDaemon }
        Should -Invoke Start-AosLogonTask -ModuleName aos -Times 0 -Exactly
        Should -Invoke Start-Sleep -ModuleName aos -Times 0 -Exactly
    }

    It 'starts the logon task and polls until ready' {
        $state = @{ polls = 0 }
        Mock Invoke-AosCapture -ModuleName aos {
            $state.polls++
            if ($state.polls -lt 3) { return @{ Code = 1; Text = 'localDaemon: stopped' } }
            @{ Code = 0; Text = 'localDaemon: running' }
        } -ParameterFilter { $CommandLine -eq 'paseo daemon status' }
        InModuleScope aos { Start-AosPaseoDaemon }
        Should -Invoke Start-AosLogonTask -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Name -eq 'agentic-os Paseo daemon' }
        $state.polls | Should -Be 3
        Should -Invoke Write-AosWarn -ModuleName aos -Times 0 -Exactly
    }

    It 'warns after sixty seconds without readiness' {
        $state = @{ seconds = 0 }
        Mock Start-Sleep -ModuleName aos { $state.seconds += $Seconds }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 1; Text = 'localDaemon: not_ready' } } -ParameterFilter { $CommandLine -eq 'paseo daemon status' }
        InModuleScope aos { Start-AosPaseoDaemon }
        $state.seconds | Should -Be 60
        Should -Invoke Start-AosLogonTask -ModuleName aos -Times 1 -Exactly
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match '60|timed out' }
        Should -Invoke Write-AosOk -ModuleName aos -Times 0 -Exactly
    }

    It 'starts nothing and does not poll in DryRun' {
        InModuleScope aos { Start-AosPaseoDaemon -DryRun }
        Should -Invoke Start-AosLogonTask -ModuleName aos -Times 0 -Exactly
        Should -Invoke Start-Sleep -ModuleName aos -Times 0 -Exactly
    }

    It 'installs phone dependencies in readiness order with DryRun=<DryRun>' -TestCases @(@{ DryRun = $false }, @{ DryRun = $true }) {
        param($DryRun)
        $expectedDryRun = $DryRun
        $calls = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-AosPackages -ModuleName aos { @{ phone_npm = @() } }
        Mock Install-AosNpmTools -ModuleName aos { $calls.Add('npm') }
        Mock Sync-AosPaseo -ModuleName aos { $calls.Add('config') }
        Mock Sync-AosPaseoAutostart -ModuleName aos { $calls.Add('task') }
        Mock Start-AosPaseoDaemon -ModuleName aos { $calls.Add('start') }
        Mock Sync-AosPaseoPlugin -ModuleName aos { $calls.Add('plugin') }
        InModuleScope aos -Parameters @{ DryRun = $DryRun } { param($DryRun) Install-AosPhone -DryRun:$DryRun }
        ($calls -join ',') | Should -Be 'npm,config,task,start,plugin'
        Should -Invoke Start-AosPaseoDaemon -ModuleName aos -Times 1 -Exactly -ParameterFilter { [bool]$DryRun -eq $expectedDryRun }
    }
}

Describe 'Paseo daemon logon command' {
    It 'starts paseo from the npm prefix through PowerShell, hidden, inside a headless console' {
        # conhost --headless: the task repeats every 5 minutes, and a hidden PowerShell alone still flashes.
        InModuleScope aos {
            $c = Get-AosPaseoAutostartCommand
            $c.Execute | Should -Match 'conhost\.exe$'
            $c.Arguments | Should -Match '^--headless "[^"]*(pwsh|powershell)\.exe" -NoProfile -WindowStyle Hidden -Command '
            $c.Arguments | Should -Match ([regex]::Escape((Join-Path (Get-AosNpmPrefix) 'paseo.cmd')))
            $c.Arguments | Should -Match 'daemon start"$'
        }
    }
}

Describe 'Pi on the local model' {
    BeforeEach {
        $piDir = Join-Path $caseRoot 'pi agent'
        $modelsPath = Join-Path $piDir 'models.json'
        $settingsPath = Join-Path $piDir 'settings.json'
        $gatePath = Join-Path $piDir 'extensions\aos-permission-gate.ts'
        $searchPath = Join-Path $piDir 'extensions\aos-web-search.ts'
        Mock Get-AosPiDir -ModuleName aos { $piDir }
        Mock Get-AosLocalConfig -ModuleName aos {
            [ordered]@{ default = 'qwen3.5:4b'; agent_model = 'aos-agent'; agent_num_ctx = 16384; ollama_url = 'http://127.0.0.1:11434/' }
        }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'pi' }
        Mock Backup-AosFile -ModuleName aos { }
        foreach ($f in 'Write-AosOk', 'Write-AosInfo', 'Write-AosDry', 'Write-AosWarn') { Mock $f -ModuleName aos { } }
    }

    It 'adds the aos provider and keeps the user''s providers and keys' {
        Write-TestFile $modelsPath '{ "providers": { "mine": { "baseUrl": "http://x/v1", "api": "openai-completions", "models": [ { "id": "m" } ] } }, "other": 1 }'
        InModuleScope aos { Sync-AosPi }
        $j = Get-Content -Raw $modelsPath | ConvertFrom-Json
        $j.other | Should -Be 1
        $j.providers.mine.models[0].id | Should -BeExactly 'm'
        $p = $j.providers.aos
        $p.baseUrl | Should -BeExactly 'http://127.0.0.1:11434/v1'
        $p.api | Should -BeExactly 'openai-completions'
        $p.apiKey | Should -BeExactly 'ollama'
        @($p.models).Count | Should -Be 1
        $p.models[0].id | Should -BeExactly 'aos-agent'
        $p.models[0].contextWindow | Should -Be 16384
        $p.models[0].maxTokens | Should -Be 4096
        $p.models[0].reasoning | Should -BeFalse
        # Ollama 0.34 honours max_tokens (Pi sends max_completion_tokens by default) and knows no "developer" role.
        $p.models[0].compat.maxTokensField | Should -BeExactly 'max_tokens'
        $p.models[0].compat.supportsDeveloperRole | Should -BeFalse
        $p.models[0].compat.supportsStore | Should -BeFalse
        Should -Invoke Backup-AosFile -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Path -eq $modelsPath }
    }

    It 'replaces the aos provider whole instead of merging into it' {
        Write-TestFile $modelsPath '{ "providers": { "aos": { "baseUrl": "http://old/v1", "extra": true, "models": [ { "id": "aos-agent", "contextWindow": 8192 }, { "id": "stale" } ] } } }'
        InModuleScope aos { Sync-AosPi }
        $p = (Get-Content -Raw $modelsPath | ConvertFrom-Json).providers.aos
        @($p.models).Count | Should -Be 1
        $p.models[0].contextWindow | Should -Be 16384
        $p.PSObject.Properties.Name | Should -Not -Contain 'extra'
    }

    It 'sets the compaction override, compaction on and telemetry off, keeping other settings' {
        # compaction.enabled is global in Pi; the 16K local model cannot work without it, so aos owns it.
        Write-TestFile $settingsPath '{ "theme": "dark", "compaction": { "enabled": false, "keepRecentTokens": 9, "modelOverrides": { "x/y": { "reserveTokens": 1 } } } }'
        InModuleScope aos { Sync-AosPi }
        $s = Get-Content -Raw $settingsPath | ConvertFrom-Json
        $s.theme | Should -BeExactly 'dark'
        $s.compaction.enabled | Should -BeTrue
        $s.compaction.keepRecentTokens | Should -Be 9
        $s.compaction.modelOverrides.'x/y'.reserveTokens | Should -Be 1
        $s.compaction.modelOverrides.'aos/aos-agent'.reserveTokens | Should -Be 4096
        $s.compaction.modelOverrides.'aos/aos-agent'.keepRecentTokens | Should -Be 4096
        $s.enableInstallTelemetry | Should -BeFalse
    }

    It 'installs the permission gate extension from the repo' {
        InModuleScope aos { Sync-AosPi }
        $want = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\config\pi\extensions\aos-permission-gate.ts'))
        [System.IO.File]::ReadAllText($gatePath) | Should -BeExactly $want
    }

    It 'installs the web search extension from the repo' {
        InModuleScope aos { Sync-AosPi }
        $want = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\config\pi\extensions\aos-web-search.ts'))
        [System.IO.File]::ReadAllText($searchPath) | Should -BeExactly $want
    }

    It 'changes nothing on a second run' {
        InModuleScope aos { Sync-AosPi }
        $before = Get-TestTreeState $piDir
        Start-Sleep -Milliseconds 50
        InModuleScope aos { Sync-AosPi }
        Get-TestTreeState $piDir | Should -BeExactly $before
        Should -Invoke Backup-AosFile -ModuleName aos -Times 0 -Exactly
    }

    It 'writes nothing in DryRun' {
        InModuleScope aos { Sync-AosPi -DryRun }
        Test-Path -LiteralPath $piDir | Should -BeFalse
        Should -Invoke Write-AosDry -ModuleName aos -Times 5 -Exactly
    }

    It 'leaves a file it cannot parse alone and warns' {
        Write-TestFile $modelsPath '{ not json'
        InModuleScope aos { Sync-AosPi }
        [System.IO.File]::ReadAllText($modelsPath) | Should -BeExactly '{ not json'
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'models.json' }
    }

    It 'the permission gate blocks on Deny, on a dismissed dialog and without a UI (node --test)' {
        # Enforcement, not just installation: Pi runs a tool only when every tool_call handler allows it.
        $ErrorActionPreference = 'Continue'
        $test = Join-Path $PSScriptRoot '..\config\pi\extensions\aos-permission-gate.test.ts'
        $out = & node --no-warnings --experimental-strip-types --test $test 2>&1
        $LASTEXITCODE | Should -Be 0 -Because (($out | Out-String).Trim())
    }

    It 'the web search extension returns sources using a controlled fixture (node --test)' {
        $ErrorActionPreference = 'Continue'
        $test = Join-Path $PSScriptRoot '..\config\pi\extensions\aos-web-search.test.ts'
        $out = & node --no-warnings --experimental-strip-types --test $test 2>&1
        $LASTEXITCODE | Should -Be 0 -Because (($out | Out-String).Trim())
    }

    It 'installs bounded file tools and verifies retrieval fixtures' {
        InModuleScope aos { Sync-AosPi }
        $src = Join-Path $PSScriptRoot '..\config\pi\extensions\aos-file-tools.ts'
        $dest = Join-Path $piDir 'extensions\aos-file-tools.ts'
        [System.IO.File]::ReadAllText($dest) | Should -BeExactly ([System.IO.File]::ReadAllText($src))
        $ErrorActionPreference = 'Continue'
        $test = Join-Path $PSScriptRoot '..\config\pi\extensions\aos-file-tools.test.ts'
        $out = & node --no-warnings --experimental-strip-types --test $test 2>&1
        $LASTEXITCODE | Should -Be 0 -Because (($out | Out-String).Trim())
    }

    It 'does nothing when pi is not installed' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'pi' }
        InModuleScope aos { Sync-AosPi }
        Test-Path -LiteralPath $piDir | Should -BeFalse
    }

    It 'runs from aos install local and aos sync' {
        foreach ($f in 'Install-AosWingetPackage', 'Install-AosNarTools', 'Install-AosNpmTools', 'Sync-AosLocalState', 'Sync-AosAgentModel',
                       'Set-AosJunction', 'Sync-AosClaudeSkills', 'Set-AosManagedBlock', 'Sync-AosCodexAgents', 'Sync-AosClaudeSettings',
                       'Sync-AosCodexProfiles', 'Sync-AosMcp', 'Sync-AosProfile', 'Sync-AosPi', 'Sync-AosPlaces') {
            Mock $f -ModuleName aos { }
        }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'ollama' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code = 0; Text = "NAME ID SIZE`nqwen3.5:4b abc 3 GB" } } -ParameterFilter { $CommandLine -eq 'ollama list' }
        InModuleScope aos { Sync-AosBrain -DryRun }
        Should -Invoke Sync-AosPi -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
        InModuleScope aos { Install-AosLocal -DryRun }
        Should -Invoke Sync-AosPi -ModuleName aos -Times 2 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'Media layer' {
    BeforeEach {
        Mock Install-AosWingetPackage -ModuleName aos { }
        Mock Update-AosPath -ModuleName aos { }
    }

    It 'is an opt-in install layer after local' {
        InModuleScope aos {
            $script:Layers | Should -Contain 'media'
            [array]::IndexOf($script:Layers, 'media') | Should -BeGreaterThan ([array]::IndexOf($script:Layers, 'local'))
        }
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\bootstrap.ps1') -Raw) | Should -Match "ValidateSet\([^)]*'media'"
    }

    It 'installs every media package, passing DryRun and the skip-dependencies flag through' {
        Mock Get-AosPackages -ModuleName aos {
            @{ media = @(
                @{ id = 'Gyan.FFmpeg'; why = 't' },
                @{ id = 'yt-dlp.yt-dlp'; why = 't'; skipDependencies = $true }
            ) }
        }
        InModuleScope aos { Install-AosMedia -DryRun }
        Should -Invoke Install-AosWingetPackage -ModuleName aos -Times 2 -Exactly -ParameterFilter { $DryRun }
        Should -Invoke Install-AosWingetPackage -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Id -eq 'yt-dlp.yt-dlp' -and $SkipDependencies }
        Should -Invoke Install-AosWingetPackage -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Id -eq 'Gyan.FFmpeg' -and -not $SkipDependencies }
    }

    It 'is left out of aos install all, and installed when named' {
        foreach ($f in 'Install-AosBase', 'Install-AosEngines', 'Sync-AosBrain', 'Install-AosBridges', 'Sync-AosRefs', 'Install-AosLocal',
                       'Install-AosPhone', 'Install-AosMedia', 'Show-AosNextSteps') { Mock $f -ModuleName aos { } }
        InModuleScope aos { Install-AosLayer -Layer all -DryRun }
        Should -Invoke Install-AosMedia -ModuleName aos -Times 0 -Exactly
        Should -Invoke Install-AosLocal -ModuleName aos -Times 1 -Exactly
        InModuleScope aos { Install-AosLayer -Layer media -DryRun }
        Should -Invoke Install-AosMedia -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
        Should -Invoke Install-AosLocal -ModuleName aos -Times 1 -Exactly
    }

    It 'lists each package once, with an id and a reason, none already in another layer' {
        $pkgs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\packages.json') -Raw | ConvertFrom-Json
        $ids = @($pkgs.media | ForEach-Object { $_.id })
        $ids.Count | Should -BeGreaterThan 0
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        foreach ($p in $pkgs.media) { $p.why | Should -Not -BeNullOrEmpty -Because $p.id }
        $others = @($pkgs.base) + @($pkgs.local) | ForEach-Object { $_.id }
        foreach ($id in $ids) { $others | Should -Not -Contain $id }
        $ids | Should -Contain 'Gyan.FFmpeg'
    }
}

Describe 'Winget skip-dependencies' {
    It 'previews winget with --skip-dependencies when asked, and without it otherwise' {
        Mock Test-AosWinget -ModuleName aos { $false }
        Mock Write-AosDry -ModuleName aos { }
        InModuleScope aos { Install-AosWingetPackage -Id 'x.y' -Why 't' -DryRun -SkipDependencies }
        Should -Invoke Write-AosDry -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'winget install --id x\.y -e .*--skip-dependencies' }
        InModuleScope aos { Install-AosWingetPackage -Id 'x.z' -Why 't' -DryRun }
        Should -Invoke Write-AosDry -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -match 'x\.z' -and $Text -notmatch 'skip-dependencies' }
    }
}

Describe 'Places registration' {
    BeforeEach {
        Mock Get-AosStateDir -ModuleName aos { $caseRoot }
        Mock Get-AosPlaces -ModuleName aos { @([ordered]@{ name='repo'; kind='repo'; path=$caseRoot; exists=$true }) }
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'paseo' }
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=0; Text='[]' } } -ParameterFilter { $CommandLine -eq 'paseo project ls --json' }
        Mock Register-AosPaseoPlace -ModuleName aos { $true }
        Mock Write-AosWarn -ModuleName aos { }
    }
    It 'registers existing places and skips normalized known paths' {
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Register-AosPaseoPlace -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Path -eq $caseRoot }
        $knownJson = ConvertTo-Json -InputObject @(@{ path=($caseRoot.ToUpperInvariant()+'\') }) -Compress
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=0; Text=$knownJson } } -ParameterFilter { $CommandLine -eq 'paseo project ls --json' }
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Register-AosPaseoPlace -ModuleName aos -Times 1 -Exactly
    }
    It 'never registers missing folders or preview changes' {
        Mock Get-AosPlaces -ModuleName aos { @([ordered]@{ name='gone'; kind='repo'; path=(Join-Path $caseRoot 'gone'); exists=$false }) }
        InModuleScope aos { Sync-AosPlaces }
        InModuleScope aos { Sync-AosPlaces -DryRun }
        Should -Invoke Register-AosPaseoPlace -ModuleName aos -Times 0 -Exactly
    }
    It 'persists local discovery when the daemon cannot list projects' {
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=1; Text='offline' } } -ParameterFilter { $CommandLine -eq 'paseo project ls --json' }
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Register-AosPaseoPlace -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'paseo project ls' }
        Test-Path (Join-Path $caseRoot 'places.json') | Should -BeTrue
    }
    It 'refuses malformed listings and reports failed registration' {
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=0; Text='invalid json' } } -ParameterFilter { $CommandLine -eq 'paseo project ls --json' }
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Register-AosPaseoPlace -ModuleName aos -Times 0 -Exactly
        Mock Invoke-AosCapture -ModuleName aos { @{ Code=0; Text='[]' } } -ParameterFilter { $CommandLine -eq 'paseo project ls --json' }
        Mock Register-AosPaseoPlace -ModuleName aos { $false }
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'registration failed' }
    }
    It 'skips external calls without Paseo and skips absent configuration' {
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'paseo' }
        InModuleScope aos { Sync-AosPlaces }
        Should -Invoke Invoke-AosCapture -ModuleName aos -Times 0 -Exactly
        Mock Get-AosPlaces -ModuleName aos { $null }
        InModuleScope aos { Sync-AosPlaces }
    }
    It 'previews an existing unregistered folder without registering or writing it' {
        InModuleScope aos { Sync-AosPlaces -DryRun }
        Should -Invoke Register-AosPaseoPlace -ModuleName aos -Times 0 -Exactly
        Test-Path (Join-Path $caseRoot 'places.json') | Should -BeFalse
    }
    It 'runs Places sync from brain sync and passes preview through' {
        foreach ($f in 'Set-AosJunction','Sync-AosClaudeSkills','Set-AosManagedBlock','Sync-AosCodexAgents','Sync-AosClaudeSettings','Sync-AosCodexProfiles','Sync-AosLocalState','Sync-AosAgentModel','Sync-AosPi','Sync-AosMcp','Sync-AosProfile','Sync-AosPlaces') { Mock $f -ModuleName aos { } }
        InModuleScope aos { Sync-AosBrain -DryRun }
        Should -Invoke Sync-AosPlaces -ModuleName aos -Times 1 -Exactly -ParameterFilter { $DryRun }
    }
}

Describe 'Places persistence' {
    It 'creates only the Inbox and preserves an unchanged registry' {
        Mock Get-AosStateDir -ModuleName aos { $caseRoot }
        Mock Get-AosPlaces -ModuleName aos { @(
            [ordered]@{ name='missing'; kind='repo'; path=(Join-Path $caseRoot 'missing'); exists=$false },
            [ordered]@{ name='inbox'; kind='inbox'; path=(Join-Path $caseRoot 'Inbox'); exists=$false }
        ) }
        InModuleScope aos { Sync-AosPlaces }
        (Test-Path (Join-Path $caseRoot 'missing')) | Should -BeFalse
        (Test-Path (Join-Path $caseRoot 'Inbox')) | Should -BeTrue
        $registry = Join-Path $caseRoot 'places.json'
        $stamp = (Get-Item $registry).LastWriteTimeUtc
        InModuleScope aos { Sync-AosPlaces }
        (Get-Item $registry).LastWriteTimeUtc | Should -Be $stamp
    }
    It 'does not create folders or a registry during preview' {
        Mock Get-AosStateDir -ModuleName aos { $caseRoot }
        Mock Get-AosPlaces -ModuleName aos { @([ordered]@{ name='inbox'; kind='inbox'; path=(Join-Path $caseRoot 'Inbox'); exists=$false }) }
        InModuleScope aos { Sync-AosPlaces -DryRun }
        (Test-Path (Join-Path $caseRoot 'Inbox')) | Should -BeFalse
        (Test-Path (Join-Path $caseRoot 'places.json')) | Should -BeFalse
    }
}

Describe 'Places commands' {
    BeforeEach {
        $desk = Join-Path $caseRoot 'Desktop'
        $cfg = Join-Path $caseRoot 'places.json'
        Write-TestFile $cfg '{ "places": [ { "name": "in", "kind": "inbox", "path": "{{desktop}}\\Inbox" } ] }'
        foreach ($d in 'repo1\.git', 'vault1\.obsidian', 'plain') { New-Item -ItemType Directory -Force -Path (Join-Path $desk $d) | Out-Null }
        Mock Get-AosDesktopDir -ModuleName aos { $desk }
        Mock Get-AosProjectsDir -ModuleName aos { Join-Path $desk '1-Projects' }
        Mock Get-AosPlacesConfigPath -ModuleName aos { $cfg }
        Mock Sync-AosPlaces -ModuleName aos { }
        foreach ($f in 'Write-AosOk', 'Write-AosWarn', 'Write-AosInfo') { Mock $f -ModuleName aos { } }
    }

    It 'detects <Kind> for <Dir>' -TestCases @(
        @{ Dir = 'repo1'; Kind = 'repo' }, @{ Dir = 'vault1'; Kind = 'vault' }, @{ Dir = 'plain'; Kind = 'folder' }
    ) {
        param($Dir, $Kind)
        InModuleScope aos -Parameters @{ P = (Join-Path $desk $Dir) } { param($P) Get-AosPlaceKind $P } | Should -Be $Kind
    }

    It 'stores a placeholder path: <Case>' -TestCases @(
        @{ Case = 'projects before desktop'; Rel = '1-Projects\x'; Want = '{{projects}}\x' },
        @{ Case = 'desktop'; Rel = 'plain'; Want = '{{desktop}}\plain' }
    ) {
        param($Case, $Rel, $Want)
        InModuleScope aos -Parameters @{ P = (Join-Path $desk $Rel) } { param($P) ConvertTo-AosPlacePath $P } | Should -Be $Want
    }

    It 'adds a folder with its detected kind and syncs' {
        InModuleScope aos -Parameters @{ P = (Join-Path $desk 'vault1') } { param($P) Add-AosPlace -Path $P } | Should -BeTrue
        $saved = Get-Content $cfg -Raw | ConvertFrom-Json
        $new = $saved.places | Where-Object name -eq 'vault1'
        $new.kind | Should -Be 'vault'
        $new.path | Should -Be '{{desktop}}\vault1'
        Should -Invoke Sync-AosPlaces -ModuleName aos -Times 1 -Exactly
    }

    It 'refuses <Case>' -TestCases @(
        @{ Case = 'a duplicate name'; Rel = 'plain'; Name = 'in'; Kind = '' },
        @{ Case = 'a second inbox'; Rel = 'plain'; Name = ''; Kind = 'inbox' },
        @{ Case = 'a missing folder'; Rel = 'nope'; Name = ''; Kind = '' },
        @{ Case = 'an unknown kind'; Rel = 'plain'; Name = ''; Kind = 'weird' }
    ) {
        param($Case, $Rel, $Name, $Kind)
        $before = Get-Content $cfg -Raw
        InModuleScope aos -Parameters @{ P = (Join-Path $desk $Rel); N = $Name; K = $Kind } { param($P, $N, $K) Add-AosPlace -Path $P -Name $N -Kind $K } | Should -BeFalse
        Get-Content $cfg -Raw | Should -BeExactly $before
        Should -Invoke Sync-AosPlaces -ModuleName aos -Times 0 -Exactly
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1
    }

    It 'refuses a folder outside the home folder' {
        Mock ConvertTo-AosPlacePath -ModuleName aos { $null }
        InModuleScope aos -Parameters @{ P = (Join-Path $desk 'plain') } { param($P) Add-AosPlace -Path $P } | Should -BeFalse
    }

    It 'parses aos place add <folder> --name <n> --kind <k>' {
        Mock Add-AosPlace -ModuleName aos { $true }
        InModuleScope aos { Invoke-AosPlace -Arguments @('add', 'C:\x', '--name', 'n1', '--kind', 'folder') }
        Should -Invoke Add-AosPlace -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\x' -and $Name -eq 'n1' -and $Kind -eq 'folder' }
    }
    It 'rejects an unknown option without adding a place' {
        Mock Add-AosPlace -ModuleName aos { $true }
        InModuleScope aos { Invoke-AosPlace -Arguments @('add', 'x', '--typo') }
        Should -Invoke Add-AosPlace -ModuleName aos -Times 0 -Exactly
    }
    It 'leaves malformed configuration byte-identical' {
        Write-TestFile $cfg '{"places":["invalid"]}'
        $before = Get-Content $cfg -Raw
        InModuleScope aos -Parameters @{ P=(Join-Path $desk 'plain') } { param($P) Add-AosPlace -Path $P } | Should -BeFalse
        Get-Content $cfg -Raw | Should -BeExactly $before
    }
    It 'previews adding a place without writing configuration or syncing' {
        $before = Get-Content $cfg -Raw
        InModuleScope aos -Parameters @{ P=(Join-Path $desk 'plain') } { param($P) Add-AosPlace -Path $P -DryRun } | Should -BeTrue
        Get-Content $cfg -Raw | Should -BeExactly $before
        Should -Invoke Sync-AosPlaces -ModuleName aos -Times 0 -Exactly
    }
    It 'refuses a duplicate path even under another name' {
        $folder = Join-Path $desk 'plain'
        InModuleScope aos -Parameters @{ P=$folder } { param($P) Add-AosPlace -Path $P } | Should -BeTrue
        $before = Get-Content $cfg -Raw
        InModuleScope aos -Parameters @{ P=$folder } { param($P) Add-AosPlace -Path $P -Name 'second' } | Should -BeFalse
        Get-Content $cfg -Raw | Should -BeExactly $before
    }

    It 'prints JSON for aos place ls --json' {
        $out = InModuleScope aos { Invoke-AosPlace -Arguments @('ls', '--json') }
        (($out -join "`n") | ConvertFrom-Json).places[0].name | Should -Be 'in'
    }

    It 'adds a new project as a repo place' {
        Mock Add-AosPlace -ModuleName aos { $true }
        Mock Test-AosCommand -ModuleName aos { $false } -ParameterFilter { $Name -eq 'git' }
        Mock Update-AosPath -ModuleName aos { }
        Mock Write-AosStep -ModuleName aos { }
        InModuleScope aos -Parameters @{ P = (Join-Path $desk '1-Projects\newproj') } { param($P) New-AosProject -Path $P }
        Should -Invoke Add-AosPlace -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Kind -eq 'repo' -and $Path -like '*newproj' }
    }

    It 'shows each place and whether Paseo knows it in aos status' {
        Mock Test-AosCommand -ModuleName aos { $true } -ParameterFilter { $Name -eq 'paseo' }
        Mock Get-AosPaseoProjectPaths -ModuleName aos { ,@() }
        InModuleScope aos { Show-AosPlacesStatus }
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'in' -and $Text -match 'missing' }
    }
}

Describe 'Inbox skill' {
    It 'has valid frontmatter with a short description' {
        $path = Join-Path $PSScriptRoot '..\agents-home\skills\inbox\SKILL.md'
        Test-Path -LiteralPath $path | Should -BeTrue
        $text = [IO.File]::ReadAllText($path)
        $frontmatter = [regex]::Match($text, '(?s)^---\r?\nname: inbox\r?\ndescription: (?<d>[^\r\n]+)\r?\n---')
        $frontmatter.Success | Should -BeTrue
        # Pi lists every skill's description in its 16K prompt.
        $frontmatter.Groups['d'].Value.Length | Should -BeLessOrEqual 250
    }
}

Describe 'Desktop folder fallback' {
    It 'uses OneDrive Desktop when the shell folder is empty and it exists' {
        $old = $env:OneDrive
        try {
            $env:OneDrive = New-TestFolder (Join-Path $caseRoot 'OneDrive')
            $desktop = New-TestFolder (Join-Path $env:OneDrive 'Desktop')
            if (InModuleScope aos { Get-Command Get-AosShellFolder -ErrorAction SilentlyContinue }) { Mock Get-AosShellFolder -ModuleName aos { '' } }
            InModuleScope aos { Get-AosDesktopDir } | Should -BeExactly $desktop
        } finally { $env:OneDrive = $old }
    }
    It 'uses HOME Desktop when the shell folder and OneDrive Desktop are absent' {
        $old = $env:OneDrive
        try {
            $env:OneDrive = Join-Path $caseRoot 'missing'
            if (InModuleScope aos { Get-Command Get-AosShellFolder -ErrorAction SilentlyContinue }) { Mock Get-AosShellFolder -ModuleName aos { '' } }
            InModuleScope aos { Get-AosDesktopDir } | Should -BeExactly (Join-Path $HOME 'Desktop')
        } finally { $env:OneDrive = $old }
    }
    It 'builds projects from the mockable desktop unless overridden' {
        $old = $env:AOS_PROJECTS
        try {
            $env:AOS_PROJECTS = $null
            Mock Get-AosDesktopDir -ModuleName aos { 'C:\fixture desk' }
            InModuleScope aos { Get-AosProjectsDir } | Should -BeExactly 'C:\fixture desk\1-Projects'
            $env:AOS_PROJECTS = Join-Path $caseRoot 'projects'
            InModuleScope aos { Get-AosProjectsDir } | Should -BeExactly $env:AOS_PROJECTS
        } finally { $env:AOS_PROJECTS = $old }
    }
}

Describe 'cc bridge hooks' {
    BeforeEach {
        $plugins = New-TestFolder (Join-Path $caseRoot 'plugins')
        $hook = Join-Path $plugins 'sendbird\cc\1.5.0\hooks\hooks.json'
        Mock Write-AosWarn -ModuleName aos { }
        Mock Write-AosOk -ModuleName aos { }
    }
    It 'repairs every command field and preserves valid JSON and unrelated text' {
        Write-TestFile $hook '{"hooks":{"SessionStart":[{"hooks":[{"command":"node $PLUGIN_ROOT/a.js","commandWindows":"node $PLUGIN_ROOT/b.js","note":"$PLUGIN_ROOT"},{"command":"echo ${PLUGIN_ROOT} $env:PLUGIN_ROOT"}]}]},"other":1}'
        InModuleScope aos -Parameters @{ P=$plugins } { param($P) Repair-AosCcHooks -PluginsRoot $P }
        $j = Get-Content $hook -Raw | ConvertFrom-Json
        $j.hooks.SessionStart[0].hooks[0].command | Should -BeExactly 'node ${PLUGIN_ROOT}/a.js'
        $j.hooks.SessionStart[0].hooks[0].commandWindows | Should -BeExactly 'node ${PLUGIN_ROOT}/b.js'
        $j.hooks.SessionStart[0].hooks[0].note | Should -BeExactly '$PLUGIN_ROOT'
        $j.hooks.SessionStart[0].hooks[1].command | Should -BeExactly 'echo ${PLUGIN_ROOT} $env:PLUGIN_ROOT'
        $j.other | Should -Be 1
        @(Get-ChildItem $env:AOS_BACKUPS -Recurse -File).Count | Should -BeGreaterThan 0
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'cc hooks changed: trust them once in Codex' }
    }
    It 'does not rewrite fixed hooks or warn again' {
        Write-TestFile $hook '{"command":"${PLUGIN_ROOT}/run"}'
        $before = (Get-Item $hook).LastWriteTimeUtc
        InModuleScope aos -Parameters @{ P=$plugins } { param($P) Repair-AosCcHooks -PluginsRoot $P }
        (Get-Item $hook).LastWriteTimeUtc | Should -Be $before
        Should -Invoke Write-AosWarn -ModuleName aos -Times 0 -Exactly
    }
    It 'previews without writing and tolerates an absent plugin' {
        Write-TestFile $hook '{"command":"$PLUGIN_ROOT/run"}'
        $before = Get-Content $hook -Raw
        InModuleScope aos -Parameters @{ P=$plugins } { param($P) Repair-AosCcHooks -PluginsRoot $P -DryRun }
        Get-Content $hook -Raw | Should -BeExactly $before
        Should -Invoke Write-AosWarn -ModuleName aos -Times 0 -Exactly
        InModuleScope aos -Parameters @{ P=(Join-Path $caseRoot 'empty') } { param($P) Repair-AosCcHooks -PluginsRoot $P } | Out-Null
    }
}

Describe 'Coordination ledger' {
    BeforeEach { $env:AOS_COORD = Join-Path $caseRoot 'coord' }
    It 'creates the folder and appends compact ordered UTF-8 events' {
        InModuleScope aos { Add-AosLedgerEvent -Event @{ type='first'; note='caf' }; Add-AosLedgerEvent -Event @{ type='second' } }
        $lines = @(Get-Content (Join-Path $env:AOS_COORD 'ledger.jsonl'))
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '"type":"first"'
        $lines[0] | Should -Match '"ts":"[^"]+"'
        [System.IO.File]::ReadAllBytes((Join-Path $env:AOS_COORD 'ledger.jsonl'))[0] | Should -Not -Be 239
        @(InModuleScope aos { Get-AosLedger -Last 1 })[0].type | Should -Be 'second'
    }
    It 'skips malformed lines and round-trips a UTF-8 note' {
        Write-TestFile (Join-Path $env:AOS_COORD 'ledger.jsonl') "garbage`n"
        InModuleScope aos { Add-AosLedgerEvent -Event @{ type='note'; text=([char]0x00e9 + 'cole') } }
        @(InModuleScope aos { Get-AosLedger })[0].text | Should -BeExactly ([char]0x00e9 + 'cole')
    }
    It 'times out on a held lock and releases it after a throwing body' {
        New-TestFolder $env:AOS_COORD | Out-Null
        $path = Join-Path $env:AOS_COORD 'coord.lock'
        $stream = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
        try { { InModuleScope aos { Invoke-AosCoordLocked -Body { 1 } -TimeoutMs 100 } } | Should -Throw '*coordination lock busy*' }
        finally { $stream.Dispose() }
        { InModuleScope aos { Invoke-AosCoordLocked -Body { throw 'body failed' } } } | Should -Throw '*body failed*'
        InModuleScope aos { Invoke-AosCoordLocked -Body { 42 } } | Should -Be 42
    }
}

Describe 'Coordination claims' {
    BeforeEach {
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $repo = New-TestFolder (Join-Path $caseRoot 'repo space')
        & git -C $repo init -q
    }
    It 'uses a stable checkout key for a spaced accented path and resolves a file' {
        $sub = New-TestFolder (Join-Path $repo ([char]0x00e9 + 'cole'))
        $file = Join-Path $sub 'a.txt'
        Write-TestFile $file 'x'
        $checkout = InModuleScope aos -Parameters @{ P=$file } { param($P) Get-AosCheckout -Path $P }
        $checkout | Should -BeExactly $repo
        $key = InModuleScope aos -Parameters @{ P=$checkout } { param($P) Get-AosClaimKey -Checkout $P }
        $key | Should -Match '^[0-9a-f]{16}$'
    }
    It 'creates, renews and refuses another session with a holder' {
        $first = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 's1' }
        $first.Ok | Should -BeTrue
        $first.Action | Should -Be 'created'
        $first.Claim.checkout | Should -BeExactly $repo
        foreach ($field in 'agent','session','note','since','renewed','expires','host_pid') { $first.Claim.Contains($field) | Should -BeTrue }
        $again = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 's1' }
        $again.Action | Should -Be 'renewed'
        $again.Claim.since | Should -Be $first.Claim.since
        $other = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 's2' }
        $other.Action | Should -Be 'refused'
        $other.Holder.agent | Should -Be 'codex'
    }
    It 'releases only the owner and records release' {
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 's1' } | Out-Null
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosRelease -Path $P -Agent 'codex' -Session 's2' } | Out-Null
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 1
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosRelease -Path $P -Agent 'codex' -Session 's1' } | Out-Null
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 0
        @(InModuleScope aos { Get-AosLedger } | Where-Object type -eq 'release').Count | Should -Be 1
    }
    It 'rejects invalid agents and TTLs without a claim file' {
        foreach ($inputCase in @(@{ A='Bad!'; T=60 }, @{ A='codex'; T=0 }, @{ A='codex'; T=1441 })) {
            $r = InModuleScope aos -Parameters @{ P=$repo; A=$inputCase.A; T=$inputCase.T } { param($P,$A,$T) Invoke-AosClaim -Path $P -Agent $A -Session 's1' -TtlMinutes $T }
            $r.Ok | Should -BeFalse
        }
        @(Get-ChildItem $env:AOS_COORD -Filter '*.json' -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It 'refuses a young unreadable claim and takes over one older than 24 hours' {
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 'old' } | Out-Null
        $file = @(Get-ChildItem $env:AOS_COORD -Filter '*.json' -Recurse | Where-Object { $_.Name -ne 'models.json' })[0].FullName
        Write-TestFile $file ''
        $young = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'claude' -Session 'new' }
        $young.Action | Should -Be 'refused'
        $young.Message | Should -Match ([regex]::Escape($file))
        (Get-Item $file).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-25)
        $old = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'claude' -Session 'new' }
        $old.Action | Should -Be 'taken-over'
        @(InModuleScope aos { Get-AosLedger } | Where-Object type -eq 'claim-takeover').Count | Should -Be 1
    }
    It 'takes over an expired claim and records the old holder' {
        $first = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 'old' }
        $file = @(Get-ChildItem $env:AOS_COORD -Filter '*.json' -Recurse | Where-Object { $_.Name -ne 'models.json' })[0].FullName
        $claim = Get-Content $file -Raw | ConvertFrom-Json
        $claim.expires = [DateTime]::UtcNow.AddMinutes(-1).ToString('o')
        Write-TestFile $file ($claim | ConvertTo-Json -Compress)
        $next = InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'claude' -Session 'new' }
        $next.Action | Should -Be 'taken-over'
        $next.Holder.agent | Should -Be 'codex'
    }
    It 'prints live claims and notes through the CLI' {
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 's1' } | Out-Null
        $listing = InModuleScope aos { aos who --json } | Out-String | ConvertFrom-Json
        @($listing.claims).Count | Should -Be 1
        InModuleScope aos { aos note 'fixture note' --as codex } | Out-Null
        @(InModuleScope aos { Get-AosLedger } | Where-Object type -eq 'note').Count | Should -Be 1
    }
}

Describe 'Process runner' {
    It 'quotes Windows arguments including trailing slashes and quotes' {
        $cases = @(
            @{ A='a b'; W='"a b"' }, @{ A='C:\p q\'; W='"C:\p q\\"' },
            @{ A='say "hi"'; W='"say \"hi\""' }, @{ A=''; W='""' },
            @{ A=([char]0x00e9 + 'cole'); W=([char]0x00e9 + 'cole') }
        )
        foreach ($c in $cases) {
            InModuleScope aos -Parameters @{ A=$c.A } { param($A) ConvertTo-AosArgString -Arguments @($A) } | Should -BeExactly $c.W
        }
    }
    It 'returns a nonzero code for a missing where.exe target' {
        $r = InModuleScope aos -Parameters @{ P=$caseRoot } { param($P) Invoke-AosProcess -Exe 'where.exe' -Arguments @('aos-test-no-such-command-987') -WorkingDirectory $P }
        $r.Code | Should -Not -Be 0
        $r.TimedOut | Should -BeFalse
    }
    It 'honours a working directory with spaces' {
        $dir = New-TestFolder (Join-Path $caseRoot 'work space')
        $out = Join-Path $caseRoot 'cd.txt'
        $r = InModuleScope aos -Parameters @{ P=$dir; O=$out } { param($P,$O) Invoke-AosProcess -Exe 'cmd.exe' -Arguments @('/d','/c','cd') -WorkingDirectory $P -StdoutFile $O }
        $r.Code | Should -Be 0
        (Get-Content $out -Raw).Trim() | Should -BeExactly $dir
    }
    It 'times out and kills a sleeping PowerShell process' {
        $r = InModuleScope aos -Parameters @{ P=$caseRoot } { param($P) Invoke-AosProcess -Exe 'powershell.exe' -Arguments @('-NoProfile','-Command','Start-Sleep 30') -WorkingDirectory $P -TimeoutSeconds 1 }
        $r.TimedOut | Should -BeTrue
        $r.KillFailed | Should -BeFalse
    }
    It 'refuses a cmd script target' {
        $script = Join-Path $caseRoot 'a.cmd'
        Write-TestFile $script '@echo off'
        InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction Stop | Out-Null }
        { InModuleScope aos -Parameters @{ P=$script; W=$caseRoot } { param($P,$W) Invoke-AosProcess -Exe $P -WorkingDirectory $W } } | Should -Throw
    }
}

Describe 'Delegation preflight' {
    BeforeEach { $env:AOS_COORD = Join-Path $caseRoot 'coord' }
    It 'accepts Claude without probing a model' {
        $r = InModuleScope aos { Resolve-AosDelegateModel -Vendor 'claude' -Model '' }
        $r.Ok | Should -BeTrue
        $r.Model | Should -BeExactly ''
    }
    It 'uses a fresh cached Codex model without a process' {
        $cache = Join-Path $env:AOS_COORD 'models.json'
        Write-TestFile $cache ('{"codex":{"model":"fixture-model","checked":"' + [DateTime]::UtcNow.ToString('o') + '"}}')
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { throw 'unexpected probe' } }
        $r = InModuleScope aos { Resolve-AosDelegateModel -Vendor 'codex' -Model '' }
        $r.Ok | Should -BeTrue
        $r.Model | Should -Be 'fixture-model'
        Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
    }
    It 'stops after a usage limit error event and records quota' {
        if (InModuleScope aos { Get-Command Get-AosCodexModelCandidates -ErrorAction SilentlyContinue }) { Mock Get-AosCodexModelCandidates -ModuleName aos { @('first','second') } }
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile '{"type":"error","message":"You have hit your usage limit"}'
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos { Resolve-AosDelegateModel -Vendor 'codex' -Model '' }
        $r.Ok | Should -BeFalse
        $r.Category | Should -Be 'quota'
        Should -Invoke Invoke-AosProcess -ModuleName aos -Times 1 -Exactly
        Test-Path (Join-Path $env:AOS_COORD 'models.json') | Should -BeFalse
    }
    It 'does not treat normal agent text saying usage limit as an error' {
        if (InModuleScope aos { Get-Command Get-AosCodexModelCandidates -ErrorAction SilentlyContinue }) { Mock Get-AosCodexModelCandidates -ModuleName aos { @('first') } }
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile "{`"type`":`"item.completed`",`"item`":{`"type`":`"agent_message`",`"text`":`"usage limit PONG`"}}`n{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":3,`"output_tokens`":2}}"
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        (InModuleScope aos { Resolve-AosDelegateModel -Vendor 'codex' -Model '' }).Ok | Should -BeTrue
    }
    It 'tries a second visible model only after not-supported and caches success' {
        if (InModuleScope aos { Get-Command Get-AosCodexModelCandidates -ErrorAction SilentlyContinue }) { Mock Get-AosCodexModelCandidates -ModuleName aos { @('first','second') } }
        Mock Invoke-AosProcess -ModuleName aos {
            if ($Arguments -contains 'first') { Write-TestFile $StdoutFile '{"type":"error","message":"model not supported"}' }
            else { Write-TestFile $StdoutFile "{`"type`":`"item.completed`",`"item`":{`"type`":`"agent_message`",`"text`":`"PONG`"}}`n{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":2,`"output_tokens`":1}}" }
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos { Resolve-AosDelegateModel -Vendor 'codex' -Model '' }
        $r.Ok | Should -BeTrue
        $r.Model | Should -Be 'second'
        Should -Invoke Invoke-AosProcess -ModuleName aos -Times 2 -Exactly
        (Get-Content (Join-Path $env:AOS_COORD 'models.json') -Raw | ConvertFrom-Json).codex.model | Should -Be 'second'
        @(InModuleScope aos { Get-AosLedger } | Where-Object type -eq 'model-probe').Count | Should -Be 2
    }
    It 'does not switch away from a failing explicit model' {
        if (InModuleScope aos { Get-Command Get-AosCodexModelCandidates -ErrorAction SilentlyContinue }) { Mock Get-AosCodexModelCandidates -ModuleName aos { @('other') } }
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile '{"type":"error","message":"model not supported"}'
            @{ Code=1; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos { Resolve-AosDelegateModel -Vendor 'codex' -Model 'explicit' }
        $r.Ok | Should -BeFalse
        Should -Invoke Invoke-AosProcess -ModuleName aos -Times 1 -Exactly
    }
    It 'reports a missing verify executable in the Codex sandbox' {
        Mock Test-AosCommand -ModuleName aos { $true }
        if (InModuleScope aos { Get-Command Resolve-AosDelegateModel -ErrorAction SilentlyContinue }) { Mock Resolve-AosDelegateModel -ModuleName aos { @{ Ok=$true; Model='fixture-model' } } }
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { @{ Code=1; TimedOut=$false; KillFailed=$false } } }
        $r = InModuleScope aos -Parameters @{ W=$caseRoot } { param($W) Test-AosDelegatePreflight -Vendor 'codex' -Model '' -Needs @() -Verify 'missing-tool --version' -WorkDir $W }
        $r.Ok | Should -BeFalse
        ($r.Reasons -join ' ') | Should -Match 'missing-tool'
    }
    It 'reports a failing needs command and accepts passing commands' {
        Mock Test-AosCommand -ModuleName aos { $true }
        if (InModuleScope aos { Get-Command Resolve-AosDelegateModel -ErrorAction SilentlyContinue }) { Mock Resolve-AosDelegateModel -ModuleName aos { @{ Ok=$true; Model='fixture-model' } } }
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { @{ Code=1; TimedOut=$false; KillFailed=$false } } }
        $bad = InModuleScope aos -Parameters @{ W=$caseRoot } { param($W) Test-AosDelegatePreflight -Vendor 'codex' -Model '' -Needs @('tool --check') -Verify '' -WorkDir $W }
        $bad.Ok | Should -BeFalse
        ($bad.Reasons -join ' ') | Should -Match 'tool --check'
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { @{ Code=0; TimedOut=$false; KillFailed=$false } } }
        (InModuleScope aos -Parameters @{ W=$caseRoot } { param($W) Test-AosDelegatePreflight -Vendor 'codex' -Model '' -Needs @('tool --check') -Verify '' -WorkDir $W }).Ok | Should -BeTrue
    }
}

Describe 'Write guard' {
    BeforeEach {
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $repo = New-TestFolder (Join-Path $caseRoot 'repo space')
        & git -C $repo init -q
    }
    It 'claims a free checkout and renews the same session without output' {
        $inputJson = @{ cwd=$repo; session_id='s1'; tool_name='Write'; tool_input=@{ file_path=(Join-Path $repo 'a.txt') } } | ConvertTo-Json -Compress
        $r = InModuleScope aos -Parameters @{ J=$inputJson } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'pre-edit' -InputJson $J }
        $r.Exit | Should -Be 0
        $r.Stderr | Should -BeNullOrEmpty
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 1
        (InModuleScope aos -Parameters @{ J=$inputJson } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'pre-edit' -InputJson $J }).Exit | Should -Be 0
    }
    It 'blocks a different holder with the required message' {
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 'other' -Note 'working' } | Out-Null
        $j = @{ cwd=$repo; session_id='s1'; tool_name='Edit'; tool_input=@{ file_path=(Join-Path $repo 'a.txt') } } | ConvertTo-Json -Compress
        $r = InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'pre-edit' -InputJson $J }
        $r.Exit | Should -Be 2
        $r.Stderr | Should -Match 'aos: .* is held by codex \(other\).*Do not edit here; coordinate \(aos who\) or use a worktree\.'
    }
    # Written by Claude (not split authorship): found in Claude's own review of pass A while both
    # Codex slots were busy. Without it, a delegate's hook would be blocked by its own wrapper's claim.
    It 'lets a delegate edit under the claim its aos delegate wrapper took' {
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 'd-1' -Note 'aos delegate d-1' } | Out-Null
        $j = @{ cwd=$repo; session_id='codex-thread-9'; tool_name='apply_patch'; tool_input=@{ input="*** Begin Patch`n*** Add File: b.txt`n*** End Patch" } } | ConvertTo-Json -Compress
        $saved = $env:AOS_DELEGATE_ID
        try {
            $env:AOS_DELEGATE_ID = 'd-1'
            $r = InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'codex' -Event 'pre-edit' -InputJson $J }
            $r.Exit | Should -Be 0
            $env:AOS_DELEGATE_ID = $null
            # No fallback (Codex review of pass A, finding 1): another same-vendor session is blocked.
            $r = InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'codex' -Event 'pre-edit' -InputJson $J }
            $r.Exit | Should -Be 2
            $r = InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'pre-edit' -InputJson $J }
            $r.Exit | Should -Be 2
        } finally { $env:AOS_DELEGATE_ID = $saved }
        $c = @(InModuleScope aos { Get-AosClaims })
        $c.Count | Should -Be 1
        $c[0]['session'] | Should -Be 'd-1'
    }
    It 'fails open for invalid JSON and a busy lock' {
        $r = InModuleScope aos { Invoke-AosGuard -Agent 'claude' -Event 'pre-edit' -InputJson '{' }
        $r.Exit | Should -Be 0
        $r.Stderr | Should -Match 'aos guard: .* \(edit allowed\)'
        New-TestFolder $env:AOS_COORD | Out-Null
        $stream = [IO.File]::Open((Join-Path $env:AOS_COORD 'coord.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        try {
            $j = @{ cwd=$repo; session_id='s1'; tool_name='Write'; tool_input=@{ file_path=(Join-Path $repo 'a.txt') } } | ConvertTo-Json -Compress
            $r = InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'pre-edit' -InputJson $J }
            $r.Exit | Should -Be 0
            $r.Stderr | Should -Match 'edit allowed'
        } finally { $stream.Dispose() }
    }
    It 'shows another session at start and releases only its own claims at end' {
        InModuleScope aos -Parameters @{ P=$repo } { param($P) Invoke-AosClaim -Path $P -Agent 'codex' -Session 'other' } | Out-Null
        $j = @{ cwd=$repo; session_id='s1' } | ConvertTo-Json -Compress
        $start = InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'session-start' -InputJson $J }
        $start.Stdout | Should -Match '^Note: aos:'
        InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'claude' -Event 'session-end' -InputJson $J } | Out-Null
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 1
    }
    It 'claims both checkouts named by Codex apply_patch including an accented folder' {
        $other = New-TestFolder (Join-Path $caseRoot ([char]0x00e9 + 'cole repo'))
        & git -C $other init -q
        $patch = "*** Begin Patch`n*** Add File: " + (Join-Path $repo 'a.txt') + "`n*** Update File: " + (Join-Path $other 'b.txt') + "`n*** End Patch"
        $j = @{ cwd=$repo; session_id='s1'; tool_name='apply_patch'; tool_input=$patch } | ConvertTo-Json -Compress
        (InModuleScope aos -Parameters @{ J=$j } { param($J) Invoke-AosGuard -Agent 'codex' -Event 'pre-edit' -InputJson $J }).Exit | Should -Be 0
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 2
    }
}

Describe 'Presence hooks sync' {
    It 'declares both vendor hook events with the required matchers and timeouts' {
        $claude = Get-Content (Join-Path $PSScriptRoot '..\config\claude\settings.json') -Raw | ConvertFrom-Json
        $codex = Get-Content (Join-Path $PSScriptRoot '..\config\codex\hooks.json') -Raw | ConvertFrom-Json
        $claude.hooks.PreToolUse[0].matcher | Should -Be 'Edit|Write|MultiEdit|NotebookEdit'
        # ~/.codex/hooks.json wraps events in "hooks" (Codex hooks docs; the cc plugin's hooks.json).
        $codex.hooks.PreToolUse[0].matcher | Should -Be 'apply_patch|Edit|Write'
        foreach ($hooks in @($claude.hooks, $codex.hooks)) {
            foreach ($event in 'PreToolUse','SessionStart','SessionEnd') {
                @($hooks.$event).Count | Should -BeGreaterThan 0
                $entry = @($hooks.$event)[0].hooks[0]
                $entry.command | Should -Match 'aos guard'
                # commandWindows exists only in Codex hooks; Claude settings have no such field.
                if ($hooks -eq $codex.hooks) { $entry.commandWindows | Should -Match 'aos guard' }
                if ($event -eq 'SessionEnd') { $entry.timeout | Should -Be 5 }
                else { $entry.timeout | Should -Be 10 }
            }
        }
    }
    It 'merges a user hook, replaces stale owned hooks and stays byte-identical on second sync' {
        $target = Join-Path $caseRoot 'codex hooks.json'
        Write-TestFile $target '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user"}]},{"hooks":[{"type":"command","command":"old aos guard codex session-start"}]}]}}'
        if (InModuleScope aos { Get-Command Get-AosCodexHooksPath -ErrorAction SilentlyContinue }) { Mock Get-AosCodexHooksPath -ModuleName aos { $target } }
        Mock Write-AosWarn -ModuleName aos { }
        InModuleScope aos { Sync-AosCodexHooks }
        $one = Get-Content $target -Raw
        $one | Should -Match 'echo user'
        $one | Should -Not -Match 'old aos guard'
        $one | Should -Match 'Import-Module'
        $one | Should -Not -Match '\{\{aos\}\}'
        InModuleScope aos { Sync-AosCodexHooks }
        Get-Content $target -Raw | Should -BeExactly $one
        Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -ParameterFilter { $Text -match 'Codex hooks changed: trust them once' }
    }
    It 'creates Codex hooks when missing and previews without writing' {
        $target = Join-Path $caseRoot 'hooks.json'
        if (InModuleScope aos { Get-Command Get-AosCodexHooksPath -ErrorAction SilentlyContinue }) { Mock Get-AosCodexHooksPath -ModuleName aos { $target } }
        InModuleScope aos { Sync-AosCodexHooks -DryRun }
        Test-Path $target | Should -BeFalse
        InModuleScope aos { Sync-AosCodexHooks }
        Test-Path $target | Should -BeTrue
    }
}

Describe 'aos delegate' {
    BeforeEach {
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $repo = New-TestFolder (Join-Path $caseRoot 'repo space')
        & git -C $repo init -q
        & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
        $task = Join-Path $caseRoot 'task file.md'
        Write-TestFile $task 'Write a fixture file'
        if (InModuleScope aos { Get-Command Test-AosDelegatePreflight -ErrorAction SilentlyContinue }) {
            if (InModuleScope aos { Get-Command Test-AosDelegatePreflight -ErrorAction SilentlyContinue }) { Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } } }
        }
    }
    It 'publishes the exact result schema contract' {
        $schema = Get-Content (Join-Path $PSScriptRoot '..\config\delegate\result.schema.json') -Raw | ConvertFrom-Json
        $schema.type | Should -Be 'object'
        $schema.additionalProperties | Should -BeFalse
        @($schema.required) -join '|' | Should -Be 'status|summary|files_changed|tests_run|unverified'
        @($schema.properties.status.enum) -join '|' | Should -Be 'done|blocked|failed'
        $schema.properties.tests_run.items.properties.exit_code.type | Should -Be 'integer'
    }
    It 'accepts a read-only Codex result and sums measured usage' {
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile "{`"type`":`"thread.started`",`"thread_id`":`"thread-1`"}`n{`"type`":`"item.completed`",`"item`":{`"type`":`"agent_message`",`"text`":`"done`"}}`n{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":12,`"cached_input_tokens`":4,`"output_tokens`":3}}"
            $result = Join-Path (Split-Path $StdoutFile -Parent) 'result.json'
            Write-TestFile $result '{"status":"done","summary":"done","files_changed":[],"tests_run":[],"unverified":[]}'
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $receipt = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R }
        $receipt.accepted | Should -BeTrue
        $receipt.outcome | Should -Be 'accepted'
        $receipt.thread_id | Should -Be 'thread-1'
        $receipt.usage.input | Should -Be 12
        $receipt.usage.cached | Should -Be 4
        $receipt.usage.output | Should -Be 3
        $global:LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $env:AOS_COORD "delegations\$($receipt.id)\receipt.json") | Should -BeTrue
        @(InModuleScope aos { Get-AosLedger } | Where-Object type -eq 'delegate').Count | Should -Be 1
    }
    It 'fails a quota error event even with exit zero' {
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile "{`"type`":`"error`",`"message`":`"You've hit your usage limit`"}`n{`"type`":`"turn.failed`",`"error`":{`"message`":`"usage limit`"}}"
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R }
        $r.accepted | Should -BeFalse
        $r.outcome | Should -Be 'failed'
        $r.error.category | Should -Be 'quota'
        $global:LASTEXITCODE | Should -Be 1
    }
    It 'refuses write mode without verify before launching a process' {
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { throw 'unexpected process' } }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R -Write }
        $r.accepted | Should -BeFalse
        Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
    }
    It 'keeps the claim and avoids a commit if timeout killing fails' {
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { @{ Code=1; TimedOut=$true; KillFailed=$true } } }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R -Write -Verify 'cmd.exe /c exit 0' }
        $r.outcome | Should -Be 'needs-inspection'
        $r.commit | Should -BeNullOrEmpty
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 1
        $global:LASTEXITCODE | Should -Be 1
    }
    It 'fails Claude is_error even when subtype says success and exit is zero' {
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile '{"is_error":true,"subtype":"success","session_id":"claude-1","structured_output":{"status":"done","summary":"done","files_changed":[],"tests_run":[],"unverified":[]}}'
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'claude' -TaskFile $T -Repo $R }
        $r.outcome | Should -Be 'failed'
        $r.accepted | Should -BeFalse
    }
    It 'reports preflight failure without leaving a worktree branch' {
        if (InModuleScope aos { Get-Command Test-AosDelegatePreflight -ErrorAction SilentlyContinue }) { Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$false; Model=''; Reasons=@('missing CLI') } } }
        if (InModuleScope aos { Get-Command Invoke-AosProcess -ErrorAction SilentlyContinue }) { Mock Invoke-AosProcess -ModuleName aos { throw 'unexpected delegate process' } }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R -Write -Verify 'cmd.exe /c exit 0' }
        $r.outcome | Should -Be 'preflight-failed'
        @(& git -C $repo branch --list 'delegate/*').Count | Should -Be 0
        @(& git -C $repo worktree list).Count | Should -Be 1
    }
    Context 'host verification and delegate lifecycle' {
        BeforeEach {
            $savedWorktrees = $env:AOS_WORKTREES
            $env:AOS_WORKTREES = Join-Path $caseRoot 'worktrees'
            & git -C $repo config user.name Fixture
            & git -C $repo config user.email fixture@example.invalid
            Mock Invoke-AosProcess -ModuleName aos {
                if ($Exe -eq 'codex.exe') {
                    Write-TestFile (Join-Path $WorkingDirectory 'fixture.txt') 'delegate edit'
                    Write-TestFile $StdoutFile '{"type":"turn.completed"}'
                    $resultPath = $Arguments[[Array]::IndexOf($Arguments, '-o') + 1]
                    Write-TestFile $resultPath '{"status":"done","summary":"fixture change","files_changed":["fixture.txt"],"tests_run":[{"command":"fixture test","exit_code":0,"passed":true}],"unverified":[]}'
                }
                else { Write-TestFile $StdoutFile 'host verification' }
                @{ Code=0; TimedOut=$false; KillFailed=$false }
            }
        }
        AfterEach { $env:AOS_WORKTREES = $savedWorktrees }

        It 'accepts a host commit in an accented worktree and releases its live claim' {
            $accentRepo = Join-Path $caseRoot ('repo space\caf' + [char]0x00E8)
            New-TestFolder $accentRepo | Out-Null
            & git -C $accentRepo init -q
            & git -C $accentRepo config user.name Fixture
            & git -C $accentRepo config user.email fixture@example.invalid
            & git -C $accentRepo commit --allow-empty -qm initial
            Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'codex.exe' } {
                $claims = @(InModuleScope aos { Get-AosClaims })
                $claims.Count | Should -Be 1
                $claims[0].agent | Should -Be 'codex'
                $branch = & git -C $WorkingDirectory branch --show-current
                $branch | Should -Be ('delegate/' + $claims[0].session)
                $claims[0].checkout | Should -Be $WorkingDirectory
                Get-Content -LiteralPath $StdinFile -Raw -Encoding UTF8 | Should -Match ([regex]::Escape($WorkingDirectory))
                Write-TestFile (Join-Path $WorkingDirectory 'fixture.txt') 'delegate edit'
                Write-TestFile $StdoutFile '{"type":"turn.completed"}'
                Write-TestFile $Arguments[[Array]::IndexOf($Arguments, '-o') + 1] '{"status":"done","summary":"fixture change","files_changed":["fixture.txt"],"tests_run":[],"unverified":[]}'
                @{ Code=0; TimedOut=$false; KillFailed=$false }
            }
            $r = InModuleScope aos -Parameters @{ T=$task; R=$accentRepo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $global:LASTEXITCODE | Should -Be 0
            $r.outcome | Should -Be 'accepted'
            $r.accepted | Should -BeTrue
            $r.branch | Should -Be "delegate/$($r.id)"
            $r.commit | Should -Not -BeNullOrEmpty
            (& git -C $accentRepo log -1 --format=%H $r.branch) | Should -Be $r.commit
            (& git -C $accentRepo show "$($r.commit):fixture.txt") | Should -Be 'delegate edit'
            $r.verify.exit_code | Should -Be 0
            @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 0
            Should -Invoke Invoke-AosProcess -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Exe -eq 'cmd.exe' -and $WorkingDirectory -eq $r.workdir }
        }

        It 'rejects a done write delegate that changes nothing without committing' {
            Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'codex.exe' } {
                Write-TestFile $StdoutFile '{"type":"turn.completed"}'
                Write-TestFile $Arguments[[Array]::IndexOf($Arguments, '-o') + 1] '{"status":"done","summary":"nothing to change","files_changed":[],"tests_run":[],"unverified":[]}'
                @{ Code=0; TimedOut=$false; KillFailed=$false }
            }
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $r.outcome | Should -Be 'rejected'
            $r.accepted | Should -BeFalse
            $r.commit | Should -BeNullOrEmpty
            (& git -C $repo log -1 --format=%H $r.branch) | Should -Be $r.base
        }

        It 'rejects and names a change outside the allow glob' {
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' -Allow 'src/*' }
            $r.outcome | Should -Be 'rejected'
            $r.accepted | Should -BeFalse
            @($r.outside_allow) | Should -Contain 'fixture.txt'
        }

        It 'rejects failing host verification while preserving the delegate passing test claim' {
            Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'cmd.exe' } {
                Write-TestFile $StdoutFile 'host verification failed'
                @{ Code=1; TimedOut=$false; KillFailed=$false }
            }
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $r.outcome | Should -Be 'rejected'
            $r.accepted | Should -BeFalse
            $r.commit | Should -Not -BeNullOrEmpty
            $r.delegate.status | Should -Be 'done'
            @($r.delegate.tests_run).Count | Should -Be 1
            $r.delegate.tests_run[0].command | Should -Be 'fixture test'
            $r.delegate.tests_run[0].exit_code | Should -Be 0
            $r.delegate.tests_run[0].passed | Should -BeTrue
            $r.verify.exit_code | Should -Be 1
            $global:LASTEXITCODE | Should -Be 1
        }

        It 'accepts usage limit words in a normal agent message' {
            Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'codex.exe' } {
                Write-TestFile $StdoutFile "{`"type`":`"item.completed`",`"item`":{`"type`":`"agent_message`",`"text`":`"The usage limit documentation is correct.`"}}`n{`"type`":`"turn.completed`"}"
                Write-TestFile $Arguments[[Array]::IndexOf($Arguments, '-o') + 1] '{"status":"done","summary":"reviewed","files_changed":[],"tests_run":[],"unverified":[]}'
                @{ Code=0; TimedOut=$false; KillFailed=$false }
            }
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R }
            $r.outcome | Should -Be 'accepted'
            $r.accepted | Should -BeTrue
            $r.error | Should -BeNullOrEmpty
            $global:LASTEXITCODE | Should -Be 0
        }

        It 'releases the claim without committing partial edits after a clean timeout kill' {
            Mock Invoke-AosProcess -ModuleName aos -ParameterFilter { $Exe -eq 'codex.exe' } {
                Write-TestFile (Join-Path $WorkingDirectory 'partial.txt') 'unfinished edit'
                Write-TestFile $StdoutFile ''
                @{ Code=1; TimedOut=$true; KillFailed=$false }
            }
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $r.outcome | Should -Be 'timed-out'
            $r.accepted | Should -BeFalse
            @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 0
            $global:LASTEXITCODE | Should -Be 1
            Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly -ParameterFilter { $Exe -eq 'cmd.exe' }
            $r.commit | Should -BeNullOrEmpty
            (& git -C $repo log -1 --format=%H $r.branch) | Should -Be $r.base
        }

        It 'refuses write mode outside a git repository before launching a process' {
            $plain = New-TestFolder (Join-Path $caseRoot 'not a repo')
            $r = InModuleScope aos -Parameters @{ T=$task; R=$plain } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $r.outcome | Should -Be 'refused'
            $r.accepted | Should -BeFalse
            $global:LASTEXITCODE | Should -Be 1
            Should -Invoke Invoke-AosProcess -ModuleName aos -Times 0 -Exactly
        }

        It 'warns that a dirty caller tree supplies committed HEAD only and proceeds' {
            Write-TestFile (Join-Path $repo 'untracked.txt') 'caller edit'
            Mock Write-AosWarn -ModuleName aos { }
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            Should -Invoke Write-AosWarn -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Text -like '*committed HEAD only*' }
            $r.outcome | Should -Be 'accepted'
            Test-Path (Join-Path $r.workdir 'untracked.txt') | Should -BeFalse
            Get-Content (Join-Path $repo 'untracked.txt') -Raw | Should -Be 'caller edit'
        }

        It 'lists recent ledger delegates and shows the receipt JSON through the CLI' {
            InModuleScope aos {
                foreach ($id in @('older', 'recent', 'latest')) {
                    Add-AosLedgerEvent @{ type='delegate'; id=$id; vendor='codex'; model='fixture-model'; outcome='accepted'; seconds=1; input=2; output=3 }
                }
                Add-AosLedgerEvent @{ type='note'; id='not-a-delegate' }
            }
            $listing = (InModuleScope aos { aos delegate ls --last 2 } 6>&1 | Out-String)
            $listing | Should -Match 'recent'
            $listing | Should -Match 'latest'
            $listing | Should -Not -Match 'older|not-a-delegate'
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $shown = (InModuleScope aos -Parameters @{ Id=$r.id } { param($Id) aos delegate show $Id } 6>&1 | Out-String -Width 32767)
            $stored = Get-Content (Join-Path $env:AOS_COORD "delegations\$($r.id)\receipt.json") -Raw
            ($shown | ConvertFrom-Json | ConvertTo-Json -Depth 10) | Should -Be ($stored | ConvertFrom-Json | ConvertTo-Json -Depth 10)
        }

        It 'refuses to clean an unmerged branch unless force is supplied' {
            $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate codex -TaskFile $T -Repo $R -Write -Verify 'fixture-verify' }
            $r.accepted | Should -BeTrue
            InModuleScope aos -Parameters @{ Id=$r.id } { param($Id) aos delegate clean $Id }
            $global:LASTEXITCODE | Should -Be 1
            @(& git -C $repo branch --list $r.branch).Count | Should -Be 1
            Test-Path -LiteralPath $r.workdir | Should -BeTrue
            InModuleScope aos -Parameters @{ Id=$r.id } { param($Id) aos delegate clean $Id --force }
            @(& git -C $repo branch --list $r.branch).Count | Should -Be 0
            Test-Path -LiteralPath $r.workdir | Should -BeFalse
            @(& git -C $repo worktree list).Count | Should -Be 1
        }
    }
}

# Tests for Codex's review of pass A (delegation 20261001-145522). Written by Claude because Codex hit
# its usage limit before it could write them (same-vendor tests: weaker than split authorship).
Describe 'Pass A review fixes' {
    BeforeEach {
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $repo = New-TestFolder (Join-Path $caseRoot 'repo space')
        & git -C $repo init -q
        Write-TestFile (Join-Path $repo 'tracked.txt') 'base'
        & git -C $repo add tracked.txt
        & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial
        $task = Join-Path $caseRoot 'task file.md'
        Write-TestFile $task 'Write a fixture file'
    }
    It 'fails a delegate whose process exits nonzero despite a done result (finding 2)' {
        Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } }
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile "{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":1,`"cached_input_tokens`":0,`"output_tokens`":1}}"
            Write-TestFile (Join-Path (Split-Path $StdoutFile -Parent) 'result.json') '{"status":"done","summary":"done","files_changed":[],"tests_run":[],"unverified":[]}'
            @{ Code=1; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R }
        $r.accepted | Should -BeFalse
        $r.outcome | Should -Be 'failed'
        $global:LASTEXITCODE | Should -Be 1
    }
    It 'keeps the claim through verify and rejects a verify that changes the tree (finding 3)' {
        Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } }
        $global:aosTestClaimsDuringVerify = -1
        Mock Invoke-AosProcess -ModuleName aos {
            if ($Exe -eq 'cmd.exe') {
                $global:aosTestClaimsDuringVerify = @(& (Get-Module aos) { Get-AosClaims }).Count
                Write-TestFile (Join-Path $WorkingDirectory 'tracked.txt') 'rewritten by verify'
                return @{ Code=0; TimedOut=$false; KillFailed=$false }
            }
            Write-TestFile (Join-Path $WorkingDirectory 'new.txt') 'delegate edit'
            Write-TestFile $StdoutFile "{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":1,`"cached_input_tokens`":0,`"output_tokens`":1}}"
            Write-TestFile (Join-Path (Split-Path $StdoutFile -Parent) 'result.json') '{"status":"done","summary":"edit","files_changed":["new.txt"],"tests_run":[],"unverified":[]}'
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R -Write -Verify 'echo ok' }
        $global:aosTestClaimsDuringVerify | Should -Be 1
        $r['verify_changed_tree'] | Should -BeTrue
        $r.outcome | Should -Be 'rejected'
        @(InModuleScope aos { Get-AosClaims }).Count | Should -Be 0
    }
    It 'refuses to clean a worktree with uncommitted partial edits unless forced (finding 4)' {
        Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } }
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile (Join-Path $WorkingDirectory 'partial.txt') 'half done'
            @{ Code=-1; TimedOut=$true; KillFailed=$false }
        }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R -Write -Verify 'echo ok' }
        $r.outcome | Should -Be 'timed-out'
        Test-Path (Join-Path $r.workdir 'partial.txt') | Should -BeTrue
        InModuleScope aos -Parameters @{ I=$r.id } { param($I) Remove-AosDelegation -Id $I }
        $global:LASTEXITCODE | Should -Be 1
        Test-Path (Join-Path $r.workdir 'partial.txt') | Should -BeTrue
        InModuleScope aos -Parameters @{ I=$r.id } { param($I) Remove-AosDelegation -Id $I -Force }
        $global:LASTEXITCODE | Should -Be 0
        Test-Path $r.workdir | Should -BeFalse
    }
    It 'unlinks junctions inside a worktree before removing it, leaving their targets intact' {
        Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } }
        $shared = New-TestFolder (Join-Path $caseRoot 'shared deps')
        Write-TestFile (Join-Path $shared 'keep.txt') 'shared'
        Mock Invoke-AosProcess -ModuleName aos {
            if ($Exe -eq 'cmd.exe') { return @{ Code=0; TimedOut=$false; KillFailed=$false } }
            Write-TestFile (Join-Path $WorkingDirectory 'new.txt') 'x'
            Write-TestFile $StdoutFile "{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":1,`"cached_input_tokens`":0,`"output_tokens`":1}}"
            Write-TestFile (Join-Path (Split-Path $StdoutFile -Parent) 'result.json') '{"status":"done","summary":"x","files_changed":[],"tests_run":[],"unverified":[]}'
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $r = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R -Write -Verify 'echo ok' }
        New-Item -ItemType Junction -Path (Join-Path $r.workdir 'deps') -Target $shared | Out-Null
        InModuleScope aos -Parameters @{ I=$r.id } { param($I) Remove-AosDelegation -Id $I -Force }
        Test-Path $r.workdir | Should -BeFalse
        Test-Path (Join-Path $shared 'keep.txt') | Should -BeTrue
    }
    It 'gives two delegations started in the same second different folders (finding 7)' {
        Mock Test-AosDelegatePreflight -ModuleName aos { @{ Ok=$true; Model='fixture-model'; Reasons=@() } }
        Mock Get-Date -ModuleName aos { '20261001-120000' }
        Mock Invoke-AosProcess -ModuleName aos {
            Write-TestFile $StdoutFile "{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":1,`"cached_input_tokens`":0,`"output_tokens`":1}}"
            Write-TestFile (Join-Path (Split-Path $StdoutFile -Parent) 'result.json') '{"status":"done","summary":"x","files_changed":[],"tests_run":[],"unverified":[]}'
            @{ Code=0; TimedOut=$false; KillFailed=$false }
        }
        $a = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R }
        $b = InModuleScope aos -Parameters @{ T=$task; R=$repo } { param($T,$R) Invoke-AosDelegate -Vendor 'codex' -TaskFile $T -Repo $R }
        $a.id | Should -Not -Be $b.id
        Test-Path (Join-Path $env:AOS_COORD "delegations\$($a.id)\receipt.json") | Should -BeTrue
        Test-Path (Join-Path $env:AOS_COORD "delegations\$($b.id)\receipt.json") | Should -BeTrue
    }
    It 'passes an explicit model to the model check (finding 6)' {
        Mock Test-AosCommand -ModuleName aos { $true }
        Mock Resolve-AosDelegateModel -ModuleName aos { [pscustomobject]@{ Ok=$true; Model=$Model; Category='ok'; Reason='' } }
        $r = InModuleScope aos -Parameters @{ W=$repo } { param($W) Test-AosDelegatePreflight -Vendor 'codex' -Model 'explicit-m' -WorkDir $W }
        Should -Invoke Resolve-AosDelegateModel -ModuleName aos -Times 1 -Exactly -ParameterFilter { $Model -eq 'explicit-m' }
        $r.Model | Should -Be 'explicit-m'
    }
    It 'times out a child that never reads a large stdin (finding 5)' {
        $big = Join-Path $caseRoot 'big stdin.txt'
        [IO.File]::WriteAllText($big, ('x' * 2MB))
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = InModuleScope aos -Parameters @{ F=$big } { param($F) Invoke-AosProcess -Exe 'powershell.exe' -Arguments @('-NoProfile', '-Command', 'Start-Sleep 30') -StdinFile $F -TimeoutSeconds 2 }
        $sw.Stop()
        $r.TimedOut | Should -BeTrue
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 15
    }
}
}
