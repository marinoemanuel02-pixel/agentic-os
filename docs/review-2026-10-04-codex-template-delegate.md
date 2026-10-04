# Codex review of the template and delegate diffs (2026-10-04)

Read-only, on worktree video-template-items (commit b4bc475 plus the uncommitted --idle change). Verbatim:

I found six defects in the two diffs:

- [aos.psm1:2527](C:/Users/marin/.aos/worktrees/video-template-items/aos.psm1:2527): Each completed stdout read immediately starts another and skips the deadline check. A child that writes at least once every 500 ms can run past `--timeout` indefinitely.
- [aos.psm1:2529](C:/Users/marin/.aos/worktrees/video-template-items/aos.psm1:2529): EOF exits the idle loop. If Codex closes stdout but remains hung, the runner waits until the hard timeout instead of killing it after `--idle`.
- [aos.psm1:2522](C:/Users/marin/.aos/worktrees/video-template-items/aos.psm1:2522): With idle mode enabled, a stuck stdin write leaves both `$read` and `$outTask` null. If the child wrote stdout before blocking, the timeout receipt loses that output.
- [joins.mts:44](C:/Users/marin/.aos/worktrees/video-template-items/templates/video/tools/checks/joins.mts:44): The gate skips the poses directory and recognizes only direct `SNN` imports. A `poses/index.ts` barrel re-exporting all poses can be imported by every shot; the gate passes while one pose edit invalidates every shot’s cache.
- [screen-text.mjs:33](C:/Users/marin/.aos/worktrees/video-template-items/templates/video/tools/checks/screen-text.mjs:33): Valid JavaScript such as `return'}'` has a quote immediately after a letter. The parser treats the `}` inside that string as a closing brace. I reproduced an “unclosed JSX tag” error for a valid JSX attribute containing it.
- [aos.Tests.ps1:1007](C:/Users/marin/.aos/worktrees/video-template-items/tests/aos.Tests.ps1:1007): The snapshot test checks only files present in the snapshot. Removing, for example, `music.ts` from it still passes this test, allowing film-specific music to leak into pipeline fixtures.

I ran the read-only screen-text reproduction and confirmed `aos.psm1` contains no non-ASCII bytes. Full tests and PowerShell parser checks were unavailable in this read-only, constrained-language session.

## Claude's response

All six agreed and fixed, each with a test seen failing first:

| Finding | Fix | Test (red before the fix) |
|---|---|---|
| hard timeout skipped while output flows | deadline checked on every loop pass | 'still enforces the hard timeout while output keeps flowing' (63 s before, ~3 s after) |
| EOF leaves the idle loop while the process hangs | after EOF the loop waits for exit with the idle clock running | 'kills a process that closed stdout but keeps running' (python child, os.close(1); 51 s, not stalled, before) |
| stuck stdin in idle mode loses stdout | the chunked read starts before the stdin check; the drain keeps it | 'keeps output written before a stuck stdin write' |
| pose barrels pass the joins gate | imports of poses/ other than poses/SNN fail; pose files may not import poses | joins.test 'a pose barrel ... fail' |
| `return'}'` after a word | keywords (return, typeof, case, ...) still start strings | screen-text.test 'a string right after a keyword' |
| snapshot test one-directional | every scaffold src/data, src/shots, claims.json and script.md file must be in the snapshot (found timeline.ts missing) | removing music.ts from the snapshot fails it |
