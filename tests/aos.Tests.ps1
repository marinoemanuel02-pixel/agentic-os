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
    BeforeEach {
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
    AfterEach { $env:AOS_PROJECTS = $savedProjects }

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
                       'Sync-AosClaudeSettings', 'Sync-AosCodexProfiles', 'Sync-AosMcp', 'Sync-AosProfile', 'Sync-AosLocalState') {
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

}
