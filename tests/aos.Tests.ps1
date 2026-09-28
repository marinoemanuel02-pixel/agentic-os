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

}
