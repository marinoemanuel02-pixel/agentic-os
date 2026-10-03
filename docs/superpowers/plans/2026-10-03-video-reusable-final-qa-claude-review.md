# Claude reusable-template review

Receipt: 20261003-160720-6538-claude-independent-read-only-review-o. Accepted read-only result; separate from the Codex verdict.

VERDICT: REVISE. This is Claude's verdict alone. Codex's review in the *-review.md file stays separate.

BLOCKER
1. HIGH, templates/video/tools/checks/screen-text.mjs:27 (JSX-children regex `>([^<>{}]+)<`). The regex treats ordinary TSX code as on-screen text. I ran extract() read-only:
   - `export const S = () => (\n <Stage ...>` produces "(".
   - `const o = f > 10 ? 1 : 0; return (<Stage` produces "10 ? 1 : 0; return (".
   - `a < b && c > d` produces "); const ok = a".
   - Line 38 (the label regex) turns `fontWeight: "700"` into the screen string "700".
   It fails closed, not open. But build.sh and qa.sh gate on it, so an idiomatic, correctly written shot can only pass if someone adds junk like "(" to claims.json as a "reviewed" screen entry. That undermines the ledger. Action:
   - Only take children between a real JSX open tag and its close tag (e.g. `<(Reveal|Label|div|span|p|h[1-6])\b[^>]*>([^<{]+)</`), or strip JS expressions first.
   - Leave pure numbers or style values out of the label regex.
   - Add fixtures for the arrow-paren shot form, comparison operators and fontWeight.

SHOULD-FIX
2. MEDIUM, tools/verify-hero.mjs:152-156. Key-frame PNGs get the wrong frame number when the requested frames are out of order or repeated. ffmpeg's `select` writes frames in stream order, but the rename follows the order frames were requested in. So `Comp:90,30` saves frame 30 as key-090.png. A duplicate (`Comp:30,30`) fails the rename and is reported as an extraction failure. Action: sort and de-duplicate `keyAt` before extracting, and add a fixture.
3. MEDIUM, private media root: tools/sync-app.sh, render.sh, still.sh, frames.sh, and the qa.sh proxy render. These scripts resolve AOS_VIDEO_MEDIA_ROOT, but nothing creates `$H/app` or its src and node_modules junctions under a new private root (only `aos video new` does that, under the default root). So `cp ... "$H/app/"` fails. build.sh would write the audio stems, then fail at render. The template AGENTS.md says "every media tool honours it" for isolated production; that is true for paths but the scripts can't run there end to end. Action: document the runner setup it needs, or have sync-app create a private app with junctions.
4. LOW-MEDIUM, tests/aos.Tests.ps1 plus pipeline.test.mjs:200. Under aos test, TestDrive is inside AppData, so the controlled verifier test only checks the refusal. On Windows runners (local and CI) the successful-output path of both verifiers is never run. That path is proven only by private runs like mine. The plan review admits this. Action: have the Pester case point AOS_VIDEO_TEST_ROOT at a non-AppData temp path for that one case, or record it as an accepted gap.

MINOR
- claims.mjs: `kind` is free text, so a typo like `"fct"` skips the rule that facts need sources. Validate kind against a fixed list.
- word-times.py:34: with VO_DIR set, it hashes a WAV other than the `public/` file that audio.mts hashes. This fails closed, but it contradicts the AGENTS.md claim that both use the "same vo.json WAV paths".
- package-outputs.mts: a row with neither text nor caption crashes with a TypeError on `.trim()` rather than a clear message.
- verify-hero.mjs:31: needs a git checkout. Without one (`aos video new` only warns if git is missing), it throws uncaught. The test mocks git, so this is never exercised.
- joins.mts: JOINS keys for shots that no longer exist are not reported.
- screen-text: props other than `text` (e.g. `title="..."`) are not scanned. R24 relies on authors following the convention.

CHECKED, NO ISSUE FOUND
- shotCamera keeps both ends of a dissolve: it holds the start pose for the first xin frames, and buildShots' tail puts the outgoing overlap at f >= frames, which returns the end pose.
- audio.mts checks every voice hash before writing any stem.
- The beat grid is BEAT/FPS.
- An empty caption is skipped.
- The template ships no film shots, poses, aliases or prose.
- Empty JOINS and words.json, and the scaffold ledger marked unreviewed, block a fresh scaffold as intended.
- fileURLToPath fixes the silent CLI bypass for joins and motion.
- Both verifiers refuse AppData and the checkout before writing.
- screen.mjs scratch now goes under the media root.
- Wording on truth and listening stays inside the evidence: the docs, R24 and the gates say coverage is not truth, legibility or listening, and they claim no playback or listening result.

CHECKS I RAN
- Read the plan, the *-review.md, `git diff c4f2fde` and every untracked file.
- Probed screen-text extract() with inline samples (no writes).
- Ran all five template Node suites in private scratch with AOS_VIDEO_TEST_ROOT and AOS_MANIFEST_TEST_ROOT under ~/.aos/scratch/claude-review-finalqa-*. All exited 0.
- A TAP run of joins + screen-text + pipeline: 25 tests, 25 passed, 0 failed, 0 skipped, outside AppData, so the verifier success path did run.

LIMITS
- I did not run the full aos test (in progress elsewhere), the bootstrap dry-run, any bash tool, a real Remotion bundle or render, ffmpeg, word-times.py or Whisper.
- I did not test the key-frame mislabel or the private-root sync failure by running them. Both come from reading the code. The ffmpeg output-order point is from known `select` behaviour.
- I did not confirm the claimed "red before fix" runs.
- I did not modify any repo file (git status is unchanged). My scratch output is under ~/.aos/scratch/claude-review-finalqa-1791036535 and -2.

