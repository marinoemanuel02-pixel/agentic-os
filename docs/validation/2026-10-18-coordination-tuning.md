# Coordination implementation and refinement validation

Checked 2026-10-18. This implements all six additions from the
[research](../research/2026-10-17-coordination-tuning.md) and
[design](../superpowers/specs/2026-10-17-coordination-tuning-design.md).
The starting agent owns integration and automatically chooses useful delegation and tiers within
the existing Claude Pro and ChatGPT Plus subscriptions. Review remains selective and risk-based.

## Implemented behavior

1. Receipts and route reports distinguish timing phases, comparable task classes, failed attempts,
   correction metadata and unavailable usage. Six offline evaluation fixtures have fixed external
   graders; preparation does not call a model. Execution requires an explicit case and active lead.
2. Optional task contracts check dependencies, attempt ownership, receipt acceptance and artifact
   hashes in the dispatch checkout. Missing, forged, partial or stale evidence cannot unlock work.
3. Task packets bound context references and reusable evidence. Stable task ids remain separate from
   retry attempt ids. Dependent changes must already be integrated before dispatch.
4. Managed explore, implement and verify roles use the local routing map and reviewed CLI capability
   gates. Requested settings remain distinct from settings actually observed by the runtime.
5. Native lifecycle signals correlate exact identities. An optional short-lived Codex App Server
   adapter requires ChatGPT authentication and validates exact turn results, steering and cancellation.
6. Checkpoints retain tracked contents and state for cold continuation. Procedures require two distinct
   host-verified successes and current hashes; stale or contradicted guidance is excluded.

These extend the existing scoped delegates, actor registry, messages and host receipts. They add no
paid API, persistent orchestration service, runtime package dependency or additional credential.
Commands and boundaries are in [coordination tuning](../coordination-tuning.md).

## Final checks

- Final complete `aos test`: 504 passed, zero failed and zero skipped in each of Windows PowerShell
  5.1 and PowerShell 7 on the final runtime. Parsing and ASCII checks passed. The complete evidence
  is `full-release-504.log`; the runtime was frozen during this run.
- Separate `node --test tools/codex-app-server.test.mjs tools/coordination-hook.test.mjs`: 31 passed,
  zero failed or skipped. The same suites also pass through Pester in each shell.
  They cover protocol identity, authentication refusal, partial completion,
  bounded timeouts, steering, cleanup and bounded lifecycle metadata.
- Bootstrap preview: `powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun`
  completed with exit zero. This is a preview, not a claim that every optional bootstrap item was installed.
- `git diff --check` passed for the combined commits and working diff. The primary checkout was
  fast-forwarded to the verified implementation; its unrelated handoff files remained byte-identical.
- `aos sync -DryRun`, then two actual `aos sync` runs completed successfully. All 37 managed-target
  records were identical after the second run, including SHA-256, modification time, existence and
  link targets. No second-run configuration rewrite occurred.

All test fixtures use isolated state, backups and temporary repositories rather than the real
profile, registry or network. Live subscription checks below are separate from the offline suite.

## Independently authored regressions and failures retained

Claude authored the initial contract and recovery safety tests and follow-up regressions. The lead
observed failures for material regressions before their fixes and checked their passes. Existing measured outcome assertions
were not weakened. Two additional defects surfaced during integration:

- Git's collapsed untracked-directory status rejected an otherwise valid scoped result. Two real
  Git regressions failed in both shells before `--untracked-files=all` and passed afterward. An extra
  file outside the declared scope remains rejected.
- A real Windows read handle briefly denied the live stdout writer. The post-upgrade full suite
  passed 499 tests in Windows PowerShell but failed one of 499 in PowerShell 7 on that sharing
  violation. Three separately authored regressions failed in both shells before the helper existed,
  then passed with the fix. The original live-process test also passed unchanged in both shells.
  Retries apply only to open-time sharing violations and stop at a short bound or process deadline;
  permanent errors fail promptly and a chunk is appended once.

Earlier combined runs passed 498 tests per shell before the later additions. They are not the final
combined result. An initial focused invocation used an unsupported alternation in the wildcard
filter and selected zero tests; it was discarded and rerun with real selections. Evaluation fixture
path lengths also needed shortening for Windows PowerShell cleanup. Neither is recorded as coverage.

Some independent authoring jobs returned rejected/blocked receipts because their sandbox could not
run Pester or their original scope arguments were malformed. Their source was read and integrated
explicitly, then tested by the lead. Those original receipts were retained, not changed to accepted.
One native worker hit a subscription limit; continuation waited for the observed reset and the
failed actor remains recorded. A tool failure is not a clean review.

## Cross-vendor findings

The lead's own findings were recorded before the blind Claude review. Codex flagged loss of a durable
native-inspection warning, which is now preserved. Claude independently flagged terminal task retry
handling after missing artifacts, missing adapter deadline forwarding, steering overwrite/acknowledgement
and stale managed-role warnings. Each material issue was checked and corrected with regression coverage.
These are separate findings; agreement was not inferred from reviewing the same file.

Claude read core dispatch, authentication, settings and adapter code. Further passes checked evaluation
files, supplied regressions and assessed the concrete CLI activation plan. Some passes explicitly did
not read the design or test files; their coverage is partial. A concern about an unhandled contract
error was resolved by reading the public dispatcher's catch and nonzero exit behavior. No claim of a
complete independent audit follows from these bounded passes.

The upgrade review required backups, copied-release checks and an atomic selection without a rename
gap. Those checks passed. The official helper's activation and rollback were exercised in a separate
fixture before actual selection. Source and release details are in the
[recent-release assessment](../research/2026-10-18-coordination-refinement.md).

## Live checks and evidence

Evidence is retained outside the repository under the user's `.aos/research/coordination-tuning-implementation`
directory. Actual host receipts remain in `.aos/coord/delegations/<run-id>/receipt.json`.

| Check | Host result and receipt |
| --- | --- |
| App Server, pre-upgrade selected CLI | Accepted, unchanged artifact, 33 s; `20261018-010800-3b4d-codex-read-input-txt-and-report-its` |
| Dependent task through ordinary exec | Accepted after checked prerequisite, 36 s; `20261018-010908-4f08-codex-read-input-txt-and-report-its` |
| Mechanical evaluation through a write delegate | Accepted, fixed external grader passed, 53 s; `20261018-011443-e8e3-codex-change-one-status-label-while` |
| Staged recent Codex CLI | Accepted, App Server artifact check, 35 s; `20261018-012721-74d3-codex-read-input-txt-and-report-its` |
| Activated recent Codex CLI | Accepted through default selection, 39 s; `20261018-014351-7c65-codex-read-input-txt-and-report-its` |
| Activated recent Claude CLI | Accepted through Pro subscription, 18 s; `20261018-014433-5091-claude-read-input-txt-and-report-its` |

The mechanical case needed no lead correction. These examples prove functioning routes, not a paired
quality, speed or quota comparison. No broad savings claim or routing retune follows from one case.

A separate native Codex worker cold-loaded a checkpoint and genuine copied receipt/task evidence in
a fresh PowerShell process. Revision, snapshot and live hashes matched, the external verifier exited
zero and the dependent task was ready. Its isolated registry had no active actors; the real global
registry still contained the lead. That distinction was recorded. Two successful host receipts also
promoted one scoped procedure, whose current artifact hash was checked.

## Rollout, recovery and limits

The recent CLIs were activated after exact package-integrity, version, schema and subscription checks.
The previous Codex release and independently hashed copy remain available; a checked atomic rollback
script is retained with the evidence. Claude's prior binary and settings were backed up before its
official installer ran. No unrelated session was interrupted.

Before applying the sync, 18 existing managed files had hash-verified backups. They were checked again
immediately before application; none required refreshing. The first sync updated Claude settings and
the generated quick profile and created six roles plus two capability records. App-owned Codex
`config.toml`, existing MCP registrations and user links were unchanged. The second sync changed no
snapshot record. Evidence includes `sync-preview.log`, both sync logs, `sync-ready.json`,
`sync-first.json` and `sync-second.json`.

The post-rollout checker confirmed existing vendor settings, permission entries and hook commands
were preserved; each lifecycle event has exactly one owned hook pointing to the primary checkout.
All six managed roles and both reviewed version records were present. App Server initialization and
ChatGPT authentication passed again after rollout without starting a model turn. Both unrelated
primary handoff files retained their original hashes. The temporary overnight continuation is being
closed after the completed rollout and bounded audit.

Source worktrees are retained:
external archive recovery is unverified, so an archive is not treated as a replacement source.

- The shared actor limit is cooperative across clients. Hooks observe after launch and cannot
  enforce machine-wide pre-launch admission. Unconfirmed child termination retains its allowance.
- The real Claude native-child lifecycle route was not exercised: another live Claude session plus
  this task's coordinator and a child would exceed the two-actor allowance. Protocol fixtures pass;
  existing user work was left alone. Native Codex continuation was exercised.
- CLI probes do not establish an already-running desktop harness's version or model. Unknown native
  settings and unavailable usage stay unknown. Role instructions alone do not create a sandbox.
- Checkpoints preserve tracked material, not arbitrary ignored or untracked files. Uncertain state
  requires inspection and does not automatically release claims or restart a worker.
- More representative paired evaluations are needed before claiming an optimal route or quota gain.
