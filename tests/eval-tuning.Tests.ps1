Describe 'coordination evaluation isolated suite' {
    BeforeAll {
        $evalRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $evalRoot 'aos.psm1') -Force -DisableNameChecking
        $savedEvalCoord = $env:AOS_COORD
        function Read-EvalJson([string]$Path) { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
        function Invoke-EvalGrader([string]$Grader,[string]$Id,[string]$Repo) {
            # Expected native stderr must not become a terminating PS 5.1 RemoteException.
            $previousPreference=$ErrorActionPreference
            try {
                $ErrorActionPreference='Continue'
                $text=& node $Grader $Id $Repo 2>&1 | Out-String
                return @{Code=$LASTEXITCODE;Text=$text}
            }
            finally { $ErrorActionPreference=$previousPreference }
        }
        function Set-EvalSolution([string]$CaseId, [string]$Repo) {
            $solutions = @{
                mechanical = @{ 'labels.txt' = "status=ready`nowner=team`n" }
                implementation = @{ 'slug.mjs' = 'export function slug(text) { return text.trim().toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,""); }' }
                sequential = @{
                    'amount.mjs' = 'export function formatAmount(cents) { return {currency:"EUR",amount:(cents/100).toFixed(2)}; }'
                    'invoice.mjs' = 'import {formatAmount} from "./amount.mjs"; export function invoice(cents) { const result=formatAmount(cents); return result.currency+" "+result.amount; }'
                }
                diagnosis = @{ 'range.mjs' = 'export function inclusiveSum(start,end) { let sum=0;for(let i=start;i<=end;i++)sum+=i;return sum; }' }
                research = @{ 'synthesis.json' = '{"claims":[{"text":"The Harbor library opens Monday through Friday.","sources":["source-a.txt"]},{"text":"The Harbor library closes at 18:00 on weekdays.","sources":["source-b.txt"]}]}' }
                consequential = @{ 'policy.json' = '{"default":"deny","rules":[{"role":"reader","resource":"report","actions":["read"]},{"role":"editor","resource":"report","actions":["read","write"]}]}' }
            }
            foreach ($file in $solutions[$CaseId].Keys) {
                [IO.File]::WriteAllText((Join-Path $Repo $file), $solutions[$CaseId][$file], (New-Object Text.UTF8Encoding($false)))
            }
        }
    }
    BeforeEach {
        # Nested fixture repos include 40-character git objects; PS 5.1 cleanup has a path limit.
        $caseRoot = Join-Path $TestDrive ('e' + [guid]::NewGuid().ToString('N').Substring(0,10))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $env:AOS_COORD = Join-Path $caseRoot 'coord'
        $runner = Join-Path $evalRoot 'tools\coordination-eval.ps1'
        if (Test-Path -LiteralPath $runner) { . $runner -OutputRoot $caseRoot }
        Mock Invoke-AosProcess -ModuleName aos { throw 'no model or CLI process is allowed in evaluation preparation' }
    }
    AfterAll { $env:AOS_COORD = $savedEvalCoord }

    It 'manifest has exactly six explicit offline classes with bounded fixtures and fixed checker identities' {
        $manifest = Read-AosEvalManifest
        @($manifest.cases).Count | Should -Be 6
        (@($manifest.cases.task_class | Sort-Object) -join ',') | Should -Be 'consequential,diagnosis,implementation,mechanical,research,sequential'
        foreach ($case in $manifest.cases) {
            $case.checker | Should -Be $case.id
            $case.task | Should -Not -BeNullOrEmpty
            @($case.allow).Count | Should -BeGreaterThan 0
            @($case.files.Keys).Count | Should -BeGreaterThan 0
        }
        $bad = Read-EvalJson (Join-Path $evalRoot 'config\delegate\eval-cases.json')
        $bad.cases[0].allow = @('../escape')
        $path = Join-Path $caseRoot 'bad.json'
        [IO.File]::WriteAllText($path, (ConvertTo-Json $bad -Depth 12))
        { Read-AosEvalManifest -Path $path } | Should -Throw
        $bad.cases[0].allow = @('labels.txt'); $bad.cases[0].checker = 'unknown-checker'
        [IO.File]::WriteAllText($path, (ConvertTo-Json $bad -Depth 12))
        { Read-AosEvalManifest -Path $path } | Should -Throw
        $bad.cases[0].checker = 'mechanical'; $bad.cases[0].objective = 42
        [IO.File]::WriteAllText($path, (ConvertTo-Json $bad -Depth 12))
        { Read-AosEvalManifest -Path $path } | Should -Throw
    }
    It 'defaults to preparation only with clean committed independent fixtures and external contracts and grader' {
        $report = Invoke-AosCoordinationEval -OutputRoot (Join-Path $caseRoot 'out') -Trials 1
        $report.mode | Should -Be 'prepare-only'
        @($report.trials).Count | Should -Be 6
        foreach ($trial in $report.trials) {
            $trial.accepted | Should -BeNullOrEmpty
            $trial.receipt_ref | Should -BeNullOrEmpty
            $trial.measurements.observed_model | Should -BeNullOrEmpty
            $contract = Read-EvalJson $trial.contract
            $contract.version | Should -Be 1
            $contract.id | Should -Be $trial.id
            $contract.budget.timeout_minutes | Should -Be 3
            $contract.budget.max_turns | Should -Be 12
            $contract.verify | Should -Match 'coordination-eval-grade.mjs'
            $contract.verify | Should -Match (' ' + $trial.case_id + ' "\."$')
            $trial.contract.StartsWith($trial.repo + '\', [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $trial.repo 'coordination-eval-grade.mjs') | Should -BeFalse
            (& git -C $trial.repo status --porcelain) | Should -BeNullOrEmpty
            (& git -C $trial.repo rev-list --count HEAD) | Should -Be '1'
        }
        Test-Path -LiteralPath (Join-Path $env:AOS_COORD 'actors.json') | Should -BeFalse
        InModuleScope aos { Should -Invoke Invoke-AosProcess -Times 0 }
        $report.subscription_savings | Should -BeNullOrEmpty
    }
    It 'six fixed graders reject initial fixtures, accept contributions and reject each missing or corrupted contribution' {
        $report = Invoke-AosCoordinationEval -OutputRoot (Join-Path $caseRoot 'out')
        $grader = Join-Path $evalRoot 'tools\coordination-eval-grade.mjs'
        foreach ($trial in $report.trials) {
            (Invoke-EvalGrader $grader $trial.case_id $trial.repo).Code | Should -Be 1
            Set-EvalSolution $trial.case_id $trial.repo
            $good = Invoke-EvalGrader $grader $trial.case_id $trial.repo
            $good.Code | Should -Be 0 -Because ($trial.case_id + ': ' + $good.Text)
            if ($trial.case_id -eq 'mechanical') {
                (Invoke-EvalGrader $grader $trial.case_id ($trial.repo.ToLowerInvariant())).Code | Should -Be 0 -Because 'Windows fixture paths may differ only in letter case'
            }
            $contract = Read-EvalJson $trial.contract
            foreach ($file in $contract.artifacts) {
                $path = Join-Path $trial.repo $file
                $before = [IO.File]::ReadAllText($path)
                Remove-Item -LiteralPath $path
                (Invoke-EvalGrader $grader $trial.case_id $trial.repo).Code | Should -Be 1 -Because ('missing ' + $trial.case_id + '/' + $file)
                [IO.File]::WriteAllText($path, 'corrupted contribution')
                (Invoke-EvalGrader $grader $trial.case_id $trial.repo).Code | Should -Be 1 -Because ('corrupt ' + $trial.case_id + '/' + $file)
                [IO.File]::WriteAllText($path, $before)
            }
        }
    }
    It 'repeated preparation uses unique clean trials without deleting or reusing existing user content' {
        $out = Join-Path $caseRoot 'out'
        $first = Invoke-AosCoordinationEval -OutputRoot $out -Case mechanical -Trials 2
        [IO.File]::WriteAllText((Join-Path $first.trials[0].repo 'personal.txt'), 'keep this dirty fixture')
        $second = Invoke-AosCoordinationEval -OutputRoot $out -Case mechanical -Trials 2
        $first.root | Should -Not -Be $second.root
        @($first.trials.id + $second.trials.id | Select-Object -Unique).Count | Should -Be 4
        [IO.File]::ReadAllText((Join-Path $first.trials[0].repo 'personal.txt')) | Should -Be 'keep this dirty fixture'
        foreach ($trial in $second.trials) { (& git -C $trial.repo status --porcelain) | Should -BeNullOrEmpty }
    }
    It 'execution needs explicit cases and an active lead and rejects incompatible transports before fixture creation' {
        $out = Join-Path $caseRoot 'out'
        { Invoke-AosCoordinationEval -OutputRoot $out -Execute } | Should -Throw
        { Invoke-AosCoordinationEval -OutputRoot $out -Execute -Case mechanical -Parent missing } | Should -Throw
        { Invoke-AosCoordinationEval -OutputRoot $out -Case unknown } | Should -Throw
        { Invoke-AosCoordinationEval -OutputRoot $out -Vendor claude -Transport app-server } | Should -Throw
        { Invoke-AosCoordinationEval -OutputRoot $out -Trials 4 } | Should -Throw
        Test-Path -LiteralPath $out | Should -BeFalse
    }
    It 'execution forwards the exact bounded route to a fake delegate and reports only its observed measurements' {
        InModuleScope aos {
            (Reserve-AosActor -Id eval-lead -Vendor codex -Task eval-task).Ok | Should -BeTrue
            $null = Set-AosActorState -Id eval-lead -State running
        }
        Mock Invoke-AosEvalDelegate {
            param($Module, $Parameters)
            $Parameters.Vendor | Should -Be 'claude'
            $Parameters.Tier | Should -Be 'light'
            $Parameters.Workers | Should -Be 1
            $Parameters.Parent | Should -Be 'eval-lead'
            $Parameters.Transport | Should -Be 'exec'
            $Parameters.Write | Should -BeTrue
            $Parameters.TimeoutMinutes | Should -Be 3
            Test-Path -LiteralPath $Parameters.ContractFile | Should -BeTrue
            return [pscustomobject]@{ id='fake-observation'; accepted=$true; outcome='accepted'; seconds=9;
                observed_model=$null; observed_effort=$null; usage_observed=$false; usage=@{input=0;output=0;cached=0}; phase_seconds=$null }
        }
        $report = Invoke-AosCoordinationEval -OutputRoot (Join-Path $caseRoot 'out') -Execute -Case mechanical `
            -Parent eval-lead -Vendor claude -Tier light -Workers 1 -Transport exec
        Should -Invoke Invoke-AosEvalDelegate -Times 1
        $report.mode | Should -Be 'execute'
        $report.trials[0].accepted | Should -BeTrue
        $report.trials[0].receipt_ref | Should -Match 'fake-observation[\\/]receipt.json$'
        $report.trials[0].measurements.elapsed_seconds | Should -Be 9
        $report.trials[0].measurements.input_tokens | Should -BeNullOrEmpty
        $report.trials[0].measurements.observed_model | Should -BeNullOrEmpty
        $report.subscription_savings | Should -BeNullOrEmpty
    }
}
