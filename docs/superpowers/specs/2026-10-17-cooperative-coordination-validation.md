# Cooperative coordination: validation report

Date: 2026-10-17. Status: **implemented, verified and synced.**
Evidence lives in `.superpowers/sdd/2026-10-17-cooperative-coordination/` and the local delegation
receipts. Failed attempts and capability limits are recorded separately below.

## Source revision

Task base: `c945cf93d85f5dd296bbe393199f7ebaf1edd3cb`. Runtime fixes through `dd59007` on
`codex/cooperative-runtime`; policy, plan and this report are versioned with the final delivery.
The earlier `main..HEAD` review range included unrelated history and was corrected to this base.

## Checks that passed

- Final `aos test`: 435 passed under Windows PowerShell 5.1 and 435 under PowerShell 7, with
  no failures or skips. The preceding full revision passed 432 tests under each shell.
- Updated cooperation selection: 51 passed under each shell, including all three review regressions.
  Other focused runs: 11 older process tests, four catalog tests and the local smoke fixture passed
  under both shells. New tests were observed failing before the corresponding production fixes.
- `node --no-warnings --test config/hooks/aos-notes.test.mjs`: 11 passed.
- Final `bootstrap.ps1 -DryRun`: exit 0.
  `git diff --check`: clean. Source parse and ASCII checks passed.
- Skill validation of `agents-home/skills/coordination/SKILL.md`: valid.

## Live cooperation evidence

- Claude CLI delegate (receipt `20261017-163821-0ce6`): accepted, host component check exit 0, only the
  assigned file changed. Requested model default; observed model taken from the receipt.
- Necessary clarification: a worker asked a question while its process was alive and the lead replied;
  worker state showed waiting-input.
- Read-only Codex transport check (receipt `20261017-164857-8b6d`): accepted. The worker asked a live
  question and received the genuine value `readonly-codex-verified`. No sandbox was widened.
- A lighter native Codex worker wrote one fixture file in a separate worktree. The lead collected
  its scoped patch after harness completion. Actual spawn/follow-up call ids and the completed handle
  were read from the host transcript and native tools, separately from the actor registry.
- The combined fixed acceptance passed. Removing either vendor's contributed file made it fail.
- A one-worker baseline passed the same fixed check. End-to-end wall time: cooperation 98.25 s,
  baseline 69.23 s, including host delays and integration. This small task favors inline execution;
  these timings do not establish a general speed or quota benefit.
- Reverse direction passed: the actual Claude lead assigned the normalizer to Codex, wrote its own
  envelope, received the stopped executor's patch, applied it and ran a combined check. The host then
  passed the same fixed acceptance on the collected worktree. Claude lead process: 96.68 s; host
  verification was outside that timer. Codex executed directly because another native child would
  have exceeded the actor allowance.
- Claude native team passed too: receipt `20261017-203927-8b12` accepted with fixed host verification
  and only the two assigned files in its final diff. The host correlated the actual native tool call,
  `task_started` and `task_notification` with status `completed` for handle `a5faa25571af49672`, then
  finished the reserved native actor and acknowledged the coordinator before its completion.
  The coordinator remained read-only while the native writer worked, then wrote its own file.
- Local, untracked routing maps resolve task tiers to current account-supported options. Both CLI
  light routes were exercised successfully. Priority labels and list-price usage estimates were not
  treated as evidence of subscription savings.
- A fresh native Codex session loaded the synced contract and coordination skill, chose light inline
  execution for a small label edit, and used no extra workers or reviewers. Its first shell command
  failed quoting before any write; the corrected command and independent host JSON check passed.

## Reviews (verdicts kept separate)

- Author findings: recorded first in `author-review.md` (ledger).
- Independent Claude plan critique (receipt `20261017-155446-8112`): findings fixed before code.
- Independent Claude safety tests (receipt `20261017-155944-ec9d`): receipt REJECTED (its sandbox
  could not run Pester); the lead read the additive tests and ran RED/GREEN itself.
- The first final review (`20261017-164135-806c`) timed out without a verdict. A corrected source
  snapshot review also reached its process deadline during reasoning. Neither is a clean review.
- The corrected review resumed with a bounded conclusion and returned findings. Only Claude
  initially flagged two reproduced defects: question delivery before waiting-state publication,
  and reconciliation releasing an exited model actor before host verification finished.
- Claude authored three new regression tests. The host added module-scope harness wrappers without
  changing their assertions, saw all three fail under both shells, then implemented the fixes.
  Questions now publish after both waiting writes and restore prior state on a failed transition;
  an ended model with unconfirmed host completion stays suspect and retains its slot.
- Scoped Claude fix review considered both original defects addressed. Its lock-reentrancy concern
  was resolved by reading `Invoke-AosCoordLocked`'s explicit reentrant branch and by the passing
  nested-question tests. Whole-registry rollback runs under that same lock.
- Other review notes described intentional refused-admission audit records, forbidden id reuse,
  conservative I/O failure, or explicitly checked correct behavior. No speculative retry mechanism
  was added. The reviewer ran no tests; host verification is reported separately above.

## Rollout checks

- Fast-forwarded the primary `codex/cooperative-coordination` branch through `c381b58`, preserving
  implementation history. Git-normalized source blobs match the tested implementation worktree;
  checkout line-ending conversion follows `.gitattributes`. The primary local smoke check passed.
- Backed up managed targets to `~/.aos-backups/cooperative-coordination-20261017-204719/`, then ran
  `aos sync` successfully. A second sync left compared contents, timestamps and link targets unchanged.
  The Claude coordination link resolves to the primary shared skill; the generated Codex contract
  contains automatic routing and the imported-process-default override.
- The actual PowerShell profile retained its pre-sync hash and timestamp. The classic Windows
  PowerShell profile remained absent, as both sync logs reported. The fresh policy check above passed.
- Preserved ignored validation evidence in the primary checkout and archived both managed development
  worktrees through the app. Source branches remain available. A subsequent app restore attempt for
  archived-claim cleanup reported a missing snapshot; archive recovery is therefore unverified.
  Automatic approval review blocked direct claim-file cleanup with "blocked by policy". The supported
  release command cleared the existing checkouts' claims; the archived-path claim is left to expire.
- The earlier continuation failed on noninteractive tool permissions and then a subscription limit.
  It did not perform rollout; the resumed host completed the remaining work without weakening a
  sandbox or consuming reset credits.
- Unrelated `HANDOFF-media.md` and the original checkout's existing handoff are preserved.

## Limitations

- Native model and effort are recorded from the request; the observed native model is not exposed.
- Claude per-worker effort is unavailable in the installed Claude Code version and is not advertised.
- Subscription savings are unmeasured. Native accounting stays cooperative for unmanaged sessions.
- Inbox reads and bounded waits occur at tool boundaries; they do not wake arbitrary idle models.
- A model that has ended while host completion is unknown retains its slot until confirmed. Metadata
  I/O failures are failures, rather than clean completion; no crash-atomic multi-file store is claimed.
