# Codex critique of the Paseo removal plan (2026-10-15)

Reviewer: Codex (`codex exec --profile review`, model passed per call), read-only, 86,334 tokens, exit 0, no
usage-limit error. Subject: `2026-10-15-remove-paseo.md` as committed in a6f62a6. Text below is Codex's final
answer, verbatim; the dispositions follow it. The revised plan (b96ac0e) was not re-read by Codex.

## Findings

1. **Blocker — Task 8, Steps 1 and 6:** The tombstone’s `install phone` test matches its own tracked test file, so its green run cannot pass. Build the search string in pieces, as the same block does for `paseo`, or exclude the test file from that check.

2. **Blocker — Task 3, Step 10:** `Select-String -Path <directory> -Recurse` is not a valid PowerShell 5.1 or 7 command, so the template scan fails. Pipe `Get-ChildItem -Recurse -File` into `Select-String` instead.

3. **Important — Task 9, Step 1:** `remove-paseo-plugin` still points at `HEAD` before the commit; `git diff HEAD remove-paseo-plugin` is empty regardless of staged changes. Compare the worktree and index against `HEAD`, excluding `paseo-plugin/`.

4. **Important — Task 3, Steps 8–9:** The plan renders through the changed template but only checks that each repointed film can load `OfflineTts`. This does not meet the spec’s identical-samples check for **each** repointed film. Render and compare the test line in each eligible film repo.

5. **Important — Task 3, Step 9:** The comment promises a fresh seal check, but the command checks only `git status`. A film sealed after Step 1 could be edited and have its seal broken. Recheck `exports/input-manifest.json` immediately before each edit.

6. **Important — Task 11, Steps 2–3:** If the operator chooses the junction, uninstalling the CLI first breaks the skipped films’ voice path until the next command succeeds. Make junction creation and verification an immediate, failure-handled part of that operation, with a recovery command if creation fails.

7. **Important — Task 11, Step 2 / Global Constraints:** `npm uninstall -g` permanently removes the package rather than moving it to `$bk\removed`, contrary to “An agent never permanently deletes.” Reconcile that constraint explicitly and preserve the package before uninstall if it applies.

8. **Important — Task 12, Step 1:** The spec calls for updating four memory notes; the plan changes two and leaves two as history. The planning-time amendments do not change that requirement. Add the missing updates or record an approved amendment.

9. **Minor — Task 3, Step 2 and Task 4, Step 1:** Step 2 says to record `$bk\sherpa-version.txt` but never writes it; Task 4 requires that file. Add the `Set-Content` command.

10. **Minor — Tasks 3, 6–8 / Global Constraints:** These tasks batch several repo code edits before running `aos test`, although the plan requires it after every repo code edit. State a consistent test checkpoint rule and apply it in the steps.

## Verified

- The helper smoke test’s `Replace-Once`, `Replace-Span`, and `Remove-LinesMatching` sequence produces the stated CRLF result. The named `Remove-Describe` targets have following `Describe` blocks; the inspected insertion and removal anchors match the source.
- **Voice tool sherpa path:** its red run fails for the missing loader lines; the proposed loader supports the three green cases.
- **Removed phone layer:** all three red cases fail against the present layer, dispatcher, and package list; the proposed removals support their green assertions.
- **Places sync and rewritten status case:** the outer mocks make the old external lookup observable in red runs; removal of that lookup supports green runs.
- **Tombstone:** its split `pa` + `seo` search avoids matching itself. Its `install phone` search has the blocker above.

## Could not verify

The read scope excluded film repos, live nar, installed packages, scheduled tasks, memory notes, and other machine state. No tests or write commands were run.

## Dispositions

| # | Disposition |
|---|---|
| 1 | Accepted. The search string is built as `('install ' + 'phone')` (I had noticed the hazard and failed to apply it). |
| 2 | Accepted. `Get-ChildItem -Recurse -File \| Select-String -List`. |
| 3 | Accepted. Task 9 checks `git diff --cached --stat` inside the worktree. |
| 4 | Accepted. Task 3 Step 9 renders the film's first line through the old path before the edit and the new path after, per film, and compares samples; a failed baseline leaves the film alone. |
| 5 | Accepted. The seal is rechecked immediately before each film's edit. |
| 6 | Accepted. Task 11 Step 2 is one script (move, then junction and verify), with a one-command recovery. |
| 7 | Accepted, and stronger than asked: the package and shims are moved to the holding folder instead of `npm uninstall -g` (spec amendment 6). |
| 8 | Recorded as spec amendment 7: the two notes name Paseo only as dated history that stays true; a new `paseo-removed` note is added. Needs the operator's confirmation. |
| 9 | Accepted. The command now writes `sherpa-version.txt`. |
| 10 | Accepted. One rule in Global Constraints: `aos test` after each task's edits and before its commit; filtered runs are only for red/green of one block. |
