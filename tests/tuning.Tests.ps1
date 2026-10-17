BeforeDiscovery { Import-Module (Join-Path $PSScriptRoot '../aos.psm1') -Force -DisableNameChecking }
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../aos.psm1') -Force -DisableNameChecking
}
Describe 'coordination tuning learning' {
    InModuleScope aos {
        BeforeEach {
            $env:AOS_COORD=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $env:AOS_LEARNING_REPO=Join-Path $TestDrive 'repo'
            New-Item -ItemType Directory -Path $env:AOS_LEARNING_REPO -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $env:AOS_LEARNING_REPO 'input.txt'),'stable')
            git -C $env:AOS_LEARNING_REPO init -q
            git -C $env:AOS_LEARNING_REPO -c user.name=fixture -c user.email=fixture@example.invalid add .
            git -C $env:AOS_LEARNING_REPO -c user.name=fixture -c user.email=fixture@example.invalid commit -qm base
            function script:Write-LearningReceipt([string]$Id,[bool]$Accepted=$true,[string]$Class='implementation') {
            $receipt=[ordered]@{id=$Id;repo=$env:AOS_LEARNING_REPO;workdir=$env:AOS_LEARNING_REPO;task_class=$Class;vendor='codex';tier='light';transport='exec';accepted=$Accepted;outcome='failed';seconds=12;verify=@{command='fixture';exit_code=1};usage=@{input=0;output=0;cached=0};usage_observed=$false;phase_seconds=@{launch=2;execution=7;verification=3};corrections=$null}
            if ($Accepted) { $receipt.outcome='accepted';$receipt.verify.exit_code=0 }
            Write-AosCoordJson -Path (Join-Path (Get-AosCoordDir) "delegations/$Id/receipt.json") -Value $receipt
        }
        }
        It 'reports observed zero separately from unavailable usage and counts failed attempts' {
            Write-LearningReceipt one $true
            Write-LearningReceipt two $false
            $path=Join-Path (Get-AosCoordDir) 'delegations/two/receipt.json'
            $r=Read-AosCoordJsonFile $path;$r.usage_observed=$true;Write-AosCoordJson $path $r
            $report=Get-AosRouteReport
            $report.attempts | Should -Be 2
            $report.accepted | Should -Be 1
            $report.usage_unknown | Should -Be 1
            $report.groups[0].observed_input | Should -Be 0
            $report.subscription_savings | Should -BeNullOrEmpty
        }
        It 'keeps unlike task classes in separate comparison groups' {
            Write-LearningReceipt one $true implementation
            Write-LearningReceipt two $true research
            @( (Get-AosRouteReport).groups ).Count | Should -Be 2
        }
        It 'retains corrupt receipt failures as report diagnostics' {
            Write-AosText (Join-Path (Get-AosCoordDir) 'delegations/bad/receipt.json') '{broken'
            @((Get-AosRouteReport).unreadable).Count | Should -Be 1
        }
        It 'promotes only two distinct host-verified same-repository receipts' {
            Write-LearningReceipt one $true
            { Save-AosProcedure -Id proc -Repo $env:AOS_LEARNING_REPO -TaskClass implementation -Text 'Use checked input' -EvidenceIds @('one','one') -Files @('input.txt') } | Should -Throw '*distinct*'
            Write-LearningReceipt two $true
            $p=Save-AosProcedure -Id proc -Repo $env:AOS_LEARNING_REPO -TaskClass implementation -Text 'Use checked input' -EvidenceIds @('one','two') -Files @('input.txt')
            $p.state | Should -Be verified
            @((Get-AosProcedures -Repo $env:AOS_LEARNING_REPO -TaskClass implementation)).Count | Should -Be 1
        }
        It 'retains failed evidence and excludes contradicted procedures' {
            Write-LearningReceipt one $true
            Write-LearningReceipt two $false
            $p=Save-AosProcedure -Id proc -Repo $env:AOS_LEARNING_REPO -TaskClass implementation -Text 'Use checked input' -EvidenceIds @('one','two') -Files @('input.txt')
            $p.state | Should -Be contradicted
            @($p.evidence).Count | Should -Be 2
            @(Get-AosProcedures -Repo $env:AOS_LEARNING_REPO -TaskClass implementation).Count | Should -Be 0
        }
        It 'excludes procedure on input drift and reports it with IncludeStale' {
            Write-LearningReceipt one $true;Write-LearningReceipt two $true
            Save-AosProcedure -Id proc -Repo $env:AOS_LEARNING_REPO -TaskClass implementation -Text 'Use checked input' -EvidenceIds @('one','two') -Files @('input.txt') | Out-Null
            [IO.File]::WriteAllText((Join-Path $env:AOS_LEARNING_REPO 'input.txt'),'changed')
            @(Get-AosProcedures -Repo $env:AOS_LEARNING_REPO -TaskClass implementation).Count | Should -Be 0
            (Get-AosProcedures -Repo $env:AOS_LEARNING_REPO -TaskClass implementation -IncludeStale).state | Should -Be stale
        }
        It 'refuses unverified external evidence or path traversal' {
            { Save-AosProcedure -Id proc -Repo $env:AOS_LEARNING_REPO -TaskClass implementation -Text 'x' -EvidenceIds @('missing','missing2') -Files @('../input.txt') } | Should -Throw '*relative*'
        }
        It 'round-trips a cold checkpoint and detects changed tracked input bytes' {
            Save-AosCheckpoint -Id cold -Repo $env:AOS_LEARNING_REPO -TaskIds @() -NextCheck 'Run fixed checks' | Out-Null
            (Test-AosCheckpoint -Id cold -Repo $env:AOS_LEARNING_REPO).Valid | Should -BeTrue
            [IO.File]::WriteAllText((Join-Path $env:AOS_LEARNING_REPO 'input.txt'),'changed')
            $r=Test-AosCheckpoint -Id cold -Repo $env:AOS_LEARNING_REPO
            $r.Valid | Should -BeFalse
            @($r.Reasons).Count | Should -BeGreaterThan 0
        }
        It 'preserves suspect actors on checkpoint reads' {
            $r=Reserve-AosActor -Id lead -Vendor codex -Task task; if (-not $r.Ok) { throw $r.Reason }
            Set-AosActorState -Id lead -State suspect -Text unknown | Out-Null
            Save-AosCheckpoint -Id cold -Repo $env:AOS_LEARNING_REPO -TaskIds @() -NextCheck 'Inspect worker' | Out-Null
            $r=Test-AosCheckpoint -Id cold -Repo $env:AOS_LEARNING_REPO
            $r.Valid | Should -BeFalse
            (Get-AosActors | Where-Object id -eq lead).state | Should -Be suspect
        }
    }
}