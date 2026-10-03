# Claude bounded template re-review

Receipt: 20261003-161725-d458-claude-independent-bounded-read-only. Accepted read-only result; separate verdict.

VERDICT: REVISE. This is Claude's verdict only, and it is separate from Codex's.

REMAINING BLOCKER (introduced by the screen-text fix)
templates/video/tools/checks/screen-text.mjs:27. The new JSX-children regex `<(Tag)\b[^<>]*>([^<>{}]+)<\/\1\s*>` removed the false positives. But it now lets real screen text through unchecked. I called the real extract() read-only:
- `<div>Outer <span>inner</span> tail</div>` gives only ["inner"]. "Outer" and "tail" are dropped.
- `<p>Up to <b>40%</b> faster</p>` gives only ["40%"].
- `<div style={{opacity: f > 10 ? 1 : 0}}>Hidden words</div>` gives []. An attribute containing `>` cuts the tag short.
- `<Reveal at={() => 3}>Arrow child</Reveal>` gives [].
None of these raises an error. The old regex `>([^<>{}]+)<` caught all of these words (side-by-side probe). So the gate used to wrongly reject good shots (fail-closed) and now wrongly passes unreviewed text (fail-open). For a gate whose stated job is "nothing escapes review", that is worse. Mixed inline content like `Up to <b>40%</b> faster` is idiomatic.
Fix: take the text runs between any real tag end and the next `<`, using a tag pattern that allows `{...}` attribute expressions and quoted strings. Or, if a tag holds text the regex can't parse, raise an error instead of silently skipping it. Add fixtures for mixed content and for `>`/`=>` inside attributes.

RESOLVED (checked by reading the code and probing)
- The original false positives are gone: the arrow-paren shot form, `f > 10 ?`, `a < b && c > d` and `fontWeight: "700"` produce no extra text, and the real children are still kept. Multi-line h1 text and all-caps literals still work.
- verify-hero.mjs:152 now sorts and de-duplicates the key frames before ffmpeg extraction and renaming. I read the code but did not run ffmpeg.
- claims.mjs:9 checks kind against the fixed list. package-outputs.mts:50 raises a named error when caption/text is missing.
- I accept documenting the media-root and runner setup instead of building it, and the explicitly accepted Pester/AppData gap. Both are reasonable as written in the response.

EVIDENCE
In private scratch at ~/.aos/scratch/claude-rereview-1791037093 (outside AppData), with AOS_VIDEO_TEST_ROOT and AOS_MANIFEST_TEST_ROOT set, `node --test` passed every suite with 0 failures and 0 skips:
- input-manifest: 11/11
- joins: 6/6
- motion: 14/14
- pipeline: 14/14
- screen-text: 7/7
joins + screen-text + pipeline = 27, which matches the claimed count. The probes ran through a temp script in [temporary path redacted]. I modified no repo file.

LIMITS
- I did not run the full aos test, the bootstrap dry-run, `git diff --check`, `bash -n`, ffmpeg, Remotion or Whisper.
- I did not confirm the claimed red-before-fix runs or the preserved unsorted snapshot.
- The key-frame ordering fix is confirmed by reading only.
- I made no film or listening judgement.

