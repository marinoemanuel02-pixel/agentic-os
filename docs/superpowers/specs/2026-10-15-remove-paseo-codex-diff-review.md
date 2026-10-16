# Codex review of the Stage 2 diff (2026-10-16)

Reviewer: Codex (`codex exec --profile review`, model passed per call), read-only, exit 0, no usage-limit error.
Subject: `git diff 0639347..7244c5c` of the agentic-os repo (19 files) against the removal spec and plan. Text below
is Codex's final answer, verbatim except that its file links are reduced to `file:line`; dispositions follow.

## Findings, ranked by severity

1. **Moderate — removed panel still documented.** README.md:116 tells users that “the panel” keeps a draft and to refresh its recent list, immediately after replacing the panel instructions with the Inbox skill. After removal, a user following that recovery advice has no panel to open. The tombstone at tests/aos.Tests.ps1:2879 misses this because the sentence contains neither the tool’s name nor `install phone`.

2. **Low — Places tests leave two regressions undetected.** tests/aos.Tests.ps1:2710 mocks `Test-AosCommand` but never asserts it was not called. A future `Sync-AosPlaces` or `Show-AosPlacesStatus` could probe for the removed command and these tests would pass. The rewritten status case at tests/aos.Tests.ps1:2859 checks the missing-folder warning but never checks that an existing Place is displayed; dropping that output would also pass.

3. **Low — decision entry states uncertain activity as settled.** docs/decisions.md:10 classifies the records as setup and smoke tests plus the Riema session, then says the outage went “without being missed.” The spec’s evidence (2026-10-15-remove-paseo-design.md:22) also records a 2026-10-08 Coordinator conversation whose initiator cannot be attributed. If that was operator activity, the decision record gives a misleading account of usage. The outage evidence establishes downtime, not whether anyone noticed it.

## Checks with no finding

- **1. Kept behavior broken by the diff:** nothing found.
- **2. Deleted tests covering kept behavior outside the allowed list:** nothing found.
- **4. Non-ASCII bytes or the named PowerShell 7 operators in the three specified scripts:** nothing found.
- **5. New tests unable to fail at all:** nothing found. The Places and tombstone coverage holes are above.

**Could not verify:** test execution, Windows PowerShell 5.1 parsing, live voice output, Pi, delegate, machine state, or separate repos. Per the read-only instruction, I used only `git diff`, `git show`, and `git grep`; no tests were run.

## Dispositions

| # | Re-graded | Disposition |
|---|---|---|
| 1 | Important (a dead instruction in live docs) | Fixed. The line is removed. A tombstone case ('documents no panel of the removed phone app') was seen failing first, then failed again by matching itself (the sentence sat in the test file), so the phrase is built in two pieces; green in both shells. |
| 2 | Minor | Deferred: the tombstone already catches any future probe that names the tool, so the cost is a missed regression only for a rename. Not part of this fix pass. |
| 3 | Important (a claim the evidence does not support, in a decision record) | Fixed. The entry now lists the unattributed 2026-10-08 Coordinator conversation and says the daemon was down until a 5-minute restart repeat was added (a09ec89), instead of "without being missed". |
