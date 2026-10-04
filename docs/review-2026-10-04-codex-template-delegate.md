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

## Codex review 2 (e21cd7d + 8edcd1d, bounded): REQUEST CHANGES, 6 findings, verbatim

REQUEST CHANGES

- [config/hooks/aos-notes.mjs:18](/C:/Users/marin/.aos/worktrees/video-template-items/config/hooks/aos-notes.mjs:18) and [line 38](/C:/Users/marin/.aos/worktrees/video-template-items/config/hooks/aos-notes.mjs:38): Codex subagent hooks use the **parent’s session ID**. If a subagent makes the first matching tool call, it marks the notes seen; the parent never receives them. [Codex hook documentation](https://learn.chatgpt.com/docs/hooks).
- [config/hooks/aos-notes.mjs:32](/C:/Users/marin/.aos/worktrees/video-template-items/config/hooks/aos-notes.mjs:32): Ledger timestamps have one-second precision. A note written in the same second as the last delivered note fails `at > since` and is never shown in that session.
- [config/hooks/aos-notes.mjs:38](/C:/Users/marin/.aos/worktrees/video-template-items/config/hooks/aos-notes.mjs:38) and [line 40](/C:/Users/marin/.aos/worktrees/video-template-items/config/hooks/aos-notes.mjs:40): With 17 pending notes, the hook marks all seen but displays only five. Its “older: aos who” hint cannot recover the rest when `aos who` shows only the latest ten ledger events.
- [config/hooks/aos-notes.mjs:27](/C:/Users/marin/.aos/worktrees/video-template-items/config/hooks/aos-notes.mjs:27): Every matching tool call rereads and splits the entire append-only ledger, including when no notes are new. As it grows, this adds latency to every shell/edit call and can hit the five-second hook timeout.
- [aos.psm1:2509](/C:/Users/marin/.aos/worktrees/video-template-items/aos.psm1:2509) and [line 2527](/C:/Users/marin/.aos/worktrees/video-template-items/aos.psm1:2527): The stdout read still starts *after* waiting for stdin. A child that fills stdout before reading a large stdin can deadlock with the parent until the hard deadline; the claimed read-before-stuck-stdin fix does not prevent it.
- [aos.psm1:3187](/C:/Users/marin/.aos/worktrees/video-template-items/aos.psm1:3187): Every capacity check scans five complete rollouts. One current selected rollout is 168 MB, so each delegation pays that read cost.

The PostToolUse output shape matches the [Codex schema](https://learn.chatgpt.com/docs/hooks). Read-only `node --check` and `git show --check` passed; tests were not run in this read-only review.

Claude: all six agreed and fixed in the next commit (subagent: Claude calls with agent_id are skipped; Codex subagents carry no marker, so there the first caller of the session gets the notes, documented in the hook).
