Describe 'task artifact manifests across line endings' {
# Regression: a dependent task could never start in this repository. The prerequisite worker wrote LF text, the receipt
# recorded the hash of those bytes, and the integrated checkout then held CRLF (.gitattributes: *.ps1 text eol=crlf), so
# the byte-level hash comparison reported 'receipt or input artifacts changed' for identical content. Text artifacts must
# survive line-ending conversion; binary artifacts and real content changes must still be refused.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\aos.psm1') -Force -DisableNameChecking
    if ([string]::IsNullOrWhiteSpace($env:AOS_BACKUPS) -or
        -not [System.IO.Path]::IsPathRooted($env:AOS_BACKUPS)) {
        throw 'Run tests/Run-Tests.ps1: AOS_BACKUPS must point to a temporary folder.'
    }
    function New-EolFolder([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return $Path
    }
    function Write-EolBytes([string]$Path, [byte[]]$Bytes) { [System.IO.File]::WriteAllBytes($Path, $Bytes) }
    function ConvertTo-EolBytes([string]$Text, [string]$Eol) {
        return [System.Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n", "`n").Replace("`n", $Eol))
    }
    # SHA-256 of a file's bytes in the manifest's own form (upper-case hex), without Get-FileHash, which is not
    # resolvable in a Windows PowerShell child of PowerShell 7 that inherited its module path.
    function Get-EolRawHash([string]$Path) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))) -replace '-', '') }
        finally { $sha.Dispose() }
    }
    # Manifest of one file, then the verdict for the repository as it is on disk now.
    function Get-EolManifest([string]$Repo, [string[]]$Files) {
        InModuleScope aos -Parameters @{ R = $Repo; F = $Files } { param($R, $F) @(Get-AosArtifactManifest $R $F) }
    }
    function Test-EolManifest([string]$Repo, $Rows) {
        InModuleScope aos -Parameters @{ R = $Repo; A = $Rows } { param($R, $A) Test-AosArtifactManifest $R $A }
    }
}

BeforeEach {
    # Short component names keep PS 5.1 TestDrive cleanup within path limits.
    $caseRoot = New-EolFolder (Join-Path $TestDrive ('e' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
    $repo = New-EolFolder (Join-Path $caseRoot 'r')
    $text = "first line`nsecond line`nthird line`n"
}

It 'verifies an LF-recorded text artifact after the checkout converted it to CRLF' {
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`n")
    $rows = Get-EolManifest $repo @('a.txt')
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`r`n")
    Test-EolManifest $repo $rows | Should -BeTrue
}

It 'verifies a CRLF-recorded text artifact against LF content' {
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`r`n")
    $rows = Get-EolManifest $repo @('a.txt')
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`n")
    Test-EolManifest $repo $rows | Should -BeTrue
}

It 'still refuses a text artifact whose words changed, whatever its line endings' {
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`n")
    $rows = Get-EolManifest $repo @('a.txt')
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes ($text.Replace('second', 'SECOND')) "`r`n")
    Test-EolManifest $repo $rows | Should -BeFalse
}

It 'compares a binary artifact byte for byte, so converted line endings inside it are a change' {
    $lf = [byte[]](0, 1, 2, 10, 3, 10, 4)
    $crlf = [byte[]](0, 1, 2, 13, 10, 3, 13, 10, 4)
    Write-EolBytes (Join-Path $repo 'b.bin') $lf
    $rows = Get-EolManifest $repo @('b.bin')
    Write-EolBytes (Join-Path $repo 'b.bin') $crlf
    Test-EolManifest $repo $rows | Should -BeFalse
    Write-EolBytes (Join-Path $repo 'b.bin') $lf
    Test-EolManifest $repo $rows | Should -BeTrue
}

It 'keeps the raw sha256 field unchanged and adds a text hash only for text files' {
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`r`n")
    Write-EolBytes (Join-Path $repo 'b.bin') ([byte[]](0, 1, 2, 13, 10))
    $rows = Get-EolManifest $repo @('a.txt', 'b.bin')
    $rows[0]['sha256'] | Should -BeExactly (Get-EolRawHash (Join-Path $repo 'a.txt'))
    $rows[1]['sha256'] | Should -BeExactly (Get-EolRawHash (Join-Path $repo 'b.bin'))
    [string]$rows[0]['sha256_text'] | Should -Not -BeNullOrEmpty
    [string]$rows[0]['sha256_text'] | Should -Not -BeExactly $rows[0]['sha256']
    [string]$rows[1]['sha256_text'] | Should -BeNullOrEmpty
}

It 'verifies a legacy row that holds only the raw hash of the LF bytes against a CRLF checkout' {
    $lfBytes = ConvertTo-EolBytes $text "`n"
    Write-EolBytes (Join-Path $repo 'a.txt') $lfBytes
    $legacy = @([ordered]@{ path = 'a.txt'; sha256 = (Get-EolRawHash (Join-Path $repo 'a.txt')) })
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`r`n")
    Test-EolManifest $repo $legacy | Should -BeTrue
}

It 'still refuses a missing artifact and unchanged bytes keep verifying' {
    Write-EolBytes (Join-Path $repo 'a.txt') (ConvertTo-EolBytes $text "`n")
    $rows = Get-EolManifest $repo @('a.txt')
    Test-EolManifest $repo $rows | Should -BeTrue
    Remove-Item -LiteralPath (Join-Path $repo 'a.txt') -Force
    Test-EolManifest $repo $rows | Should -BeFalse
}
}
