# Coordination tuning follow-up review (2026-10-18)

Scope: the spec and `docs/coordination-tuning.md`, plus the four previously unreviewed evaluation
files: `tools/coordination-eval.ps1`, `tools/coordination-eval-grade.mjs`, `tests/eval-tuning.Tests.ps1`
and `config/delegate/eval-cases.json` (manifest read only through its tests and loader).
Test-authoring pass only; no runtime change. Regressions are in `tests/tuning-regressions.Tests.ps1`
and the end of `tools/codex-app-server.test.mjs`.

## Documented limits, not defects

- Prerequisite commits must be integrated into the dispatch checkout before dependent work.
- Checkpoints cover tracked files only; active actors are inspected conservatively.

## Defects covered by regressions (expected RED before the fixes)

1. **Task acceptance leaves a dead attempt owning the task.** `Complete-AosTaskAttempt`
   (`config/task-contracts.ps1`) throws from `Get-AosArtifactManifest` when a declared artifact is missing,
   after a genuine accepted receipt with a passing host check. `active_run` stays set and the state stays
   `running`, so the task can never be retried. Required: throw visibly, record `failed`, clear
   `active_run`. A missing or forged receipt must still keep unknown ownership (the evidence is uncertain,
   so the attempt is not freed). The delegate must also not report `accepted` when this fails.
2. **Native conflict is not sticky.** `Import-AosNativeSignals` sets `needs-inspection`, but the next
   ordinary `Set-AosRunState ... running` overwrites it, and `Invoke-AosDelegate` only checks the
   transient state for `native_unconfirmed`. Required: a persistent `native_inspection_required` flag that
   survives status updates and reimport, and which the delegate honours.
3. **Steering can silently overwrite an unacknowledged request.** `Send-AosTurnSteering` always rewrites
   `steering.json`. Required: refuse while the previous request has no matching ack (an ack with an unknown
   id counts as pending), and add `Get-AosTurnSteering -RunId` returning `{request, ack, pending}`.
4. **Unknown Codex version hides active stale managed roles.** `Sync-AosNativeRoles` reports plain
   `unsupported` even when managed role files from an earlier supported version still exist. Required:
   `unsupported-existing-managed`; unowned files stay untouched.
5. **Adapter deadline ignores `options.timeoutMs`.** `runAdapter` uses only `dependencies.maxRunMs ?? 1h`,
   so the host-requested timeout cannot bound the App Server run. Required: `options.timeoutMs` governs
   when `maxRunMs` is absent (the optional CLI `--timeout-seconds` is the parent's to implement).

## Evaluation files

No consequential defect found. The grader runs outside each fixture, rejects initial fixtures, and fails on
missing or corrupted outputs; execution requires an explicit case and an active lead; the report never
claims savings. Two notes, neither a defect: the grader catches every exception into one generic failure
line (intended: avoids leaking worker content), and fixtures are synthetic.

## Binding `receipt.verify.command` to `contract.verify`

Not needed for the stated cooperative model. The delegate writes `verify.command` from its own `-Verify`
argument, which the evaluation runner and contract path both fill from the contract, and
`Test-AosHostReceipt` already requires the exit code, repo and task id. Binding the command text would
only catch a host caller passing a different `-Verify` than the contract, which is host metadata and not
a hostile boundary. Optional hardening: record a mismatch as a receipt warning. No test added.

## Not exercised

Delegate-level acceptance of a sticky native conflict (needs a Claude launch fixture whose mock writes a
signal for the generated run id) is covered only at run-state level.
