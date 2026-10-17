Describe 'live output append helper' {
# Add-AosLiveOutput is module-private and does not exist yet; each test asserts it is present first so an
# absent helper fails here instead of passing through an unrelated CommandNotFound error.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking

    function New-LiveFixtureFile([string]$Path, [string]$Text) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }

    function Wait-LiveFixtureFile([string]$Path, [int]$Milliseconds) {
        $until = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
        while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 20 }
        return (Test-Path -LiteralPath $Path)
    }
}

It 'appends one chunk after a prefix while another process briefly holds the log open for read' {
    $log = Join-Path $TestDrive 'l\e.jsonl'
    $marker = Join-Path $TestDrive 'l\ready.txt'
    $fixture = Join-Path $TestDrive 'l\hold.ps1'
    $prefix = '{"event":"start"}' + "`n"
    $chunk = 'caf' + [char]0x00E9 + ' chunk' + "`n"
    New-LiveFixtureFile $log $prefix
    # Fixture: opens the log with FileShare.Read (no write sharing), signals readiness, holds ~200ms, releases.
    New-LiveFixtureFile $fixture @'
param([string]$Log, [string]$Marker)
$fs = [System.IO.File]::Open($Log, 'Open', 'Read', 'Read')
try {
    [System.IO.File]::WriteAllText($Marker, 'ready')
    Start-Sleep -Milliseconds 200
} finally { $fs.Dispose() }
'@
    $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $proc = Start-Process -FilePath $exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$fixture`" `"$log`" `"$marker`"" -WindowStyle Hidden -PassThru
    try {
        (Wait-LiveFixtureFile $marker 10000) | Should -BeTrue

        InModuleScope aos -Parameters @{ Log = $log; Chunk = $chunk } {
            param($Log, $Chunk)
            Get-Command Add-AosLiveOutput -Module aos -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            Add-AosLiveOutput -Path $Log -Text $Chunk -Deadline ([DateTime]::UtcNow.AddSeconds(3))
        }

        $proc.WaitForExit(10000) | Should -BeTrue
        $proc.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($log, [System.Text.Encoding]::UTF8) | Should -Be ($prefix + $chunk)
    } finally {
        if (-not $proc.HasExited) { $proc.Kill() }
        $proc.Dispose()
    }
}

It 'throws within a bounded time and leaves the bytes unchanged when the lock outlives a short deadline' {
    $log = Join-Path $TestDrive 'b\e.jsonl'
    New-LiveFixtureFile $log ('{"event":"start"}' + "`n")
    $before = [System.IO.File]::ReadAllBytes($log)
    $handle = [System.IO.File]::Open($log, 'Open', 'Read', 'Read')
    try {
        InModuleScope aos -Parameters @{ Log = $log } {
            param($Log)
            Get-Command Add-AosLiveOutput -Module aos -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $threw = $false
            try {
                Add-AosLiveOutput -Path $Log -Text 'blocked' -Deadline ([DateTime]::UtcNow.AddMilliseconds(150))
            } catch {
                $threw = $true
            }
            $watch.Stop()
            $threw | Should -BeTrue
            $watch.ElapsedMilliseconds | Should -BeLessThan 2000
        }
        [System.IO.File]::ReadAllBytes($log) | Should -Be $before
    } finally {
        $handle.Dispose()
    }
}

It 'fails promptly on a permanent invalid target instead of retrying it as a sharing violation' {
    $dir = Join-Path $TestDrive 'd\target-dir'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    InModuleScope aos -Parameters @{ Dir = $dir } {
        param($Dir)
        Get-Command Add-AosLiveOutput -Module aos -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $threw = $false
        try {
            Add-AosLiveOutput -Path $Dir -Text 'never' -Deadline ([DateTime]::UtcNow.AddSeconds(3))
        } catch {
            $threw = $true
        }
        $watch.Stop()
        $threw | Should -BeTrue
        $watch.ElapsedMilliseconds | Should -BeLessThan 1500
    }
}
}
