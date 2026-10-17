Describe 'coordination protocol tuning' {
    It 'passes the fake App Server and native hook protocol tests without model calls' {
        $root=Split-Path -Parent $PSScriptRoot
        $output=& node --test --test-reporter=tap (Join-Path $root 'tools/codex-app-server.test.mjs') (Join-Path $root 'tools/coordination-hook.test.mjs') 2>&1
        $code=$LASTEXITCODE
        if ($code -ne 0) { Write-Host ($output -join "`n") }
        $code | Should -Be 0
        ($output -join "`n") | Should -Match '# fail 0'
    }
}
