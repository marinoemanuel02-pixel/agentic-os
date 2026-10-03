# Reusable film checks implementation plan

> Execute inline using the executing-plans and test-driven-development skills. Claude reviews read-only before push.

**Goal:** Transfer proven checks from the sealed director commit c30a7ac into the general video template.

**Architecture:** Keep timeline and camera validation pure and dependency-free. Tools resolve a private media root at runtime. A claims ledger covers authored words; word timing is bound to the exact voice WAVs.

**Tech stack:** Existing Node, Python, Bash, Pester, Windows PowerShell 5.1 and PowerShell 7. No downloads or installations.

**Spec:** The user's TASK B request; source is the director worktree at c30a7ac, read-only throughout.

## Constraints and review focus

- No film shots, authored camera poses, prose, or claims enter the template.
- Dissolves hold matching camera poses; malformed or non-finite keys fail before rendering.
- Screen extraction covers template text conventions and rejects unreviewed/computed words.
- Voice drift must fail before any stems are overwritten; valid word cues use the picture beat grid.
- Every writable media tool, including both verifiers, respects AOS_VIDEO_MEDIA_ROOT. No shared live bundles.
- Caption fallback preserves explicit captions, including an empty string.

## Tasks

1. Tests first: copy and generalize joins/screen coverage tests, add camera hold/finite/order tests, cue and voice-drift tests, media override and caption packaging fixtures. Run them against the unchanged template and record failures.
2. Add generic pose/join types and empty authored JOINS, shotCamera helper with hold/finite guards, joins checker. Carry over screen-text and claims validation with general paths and a scaffold ledger; add CLI fixtures for missing and reviewed entries.
3. Carry over cue-core, a picture cue wrapper, local-only word-times.py and voice hash validation in audio.mts. Keep empty word data as a scaffold requiring measurement before a real build. Derive seconds per beat from BEAT/FPS.
4. Apply media override to all existing media writers. Add generic verify-hero taking requested compositions/key frames instead of film-specific defaults. Carry over caption fallback; run claims, screen-text, check-plan and joins before build/render. Wire tests into aos test and rules into QA.
5. Run Node fixtures, bootstrap dry-run, aos test (both shells), inspect diff; document the dated decision and new video rules. Commit. Save Codex's own review, request read-only Claude review with aos delegate claude, resolve concrete findings with regression proof, push only after review and both shells pass, then check CI.

TASK A runs separately against sealed exports, writes only scratch evidence/report, and preserves the Codex verdict independently of Claude.

## Claude plan review adopted

Voice hash validation precedes all stem writes. Empty captions omit a cue. Screen extraction includes Reveal/Label JSX children and single-quoted literals; no film acronym aliases or fixed shot ids. The frame-keyed camera uses the Stage default fov of 30 and validates vectors at check time. Empty JOINS/word timing and an unreviewed scaffold ledger intentionally block production until authored. Word timing requires an explicitly configured existing local model directory, and hashes the vo.json file paths used by audio. Shared dependencies stay read-only; every bundle belongs to its own private runner. Joins is a manual rule with an executable build/QA gate, retaining the existing rule-format test unchanged.
