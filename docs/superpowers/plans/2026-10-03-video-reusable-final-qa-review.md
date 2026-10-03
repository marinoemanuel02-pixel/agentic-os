# Reusable video checks: Codex review

Scope: transfer from the interrupted reusable-final-qa candidate based on c4f2fde, with the original worktree
preserved. Production remains with the separate director. This review does not approve any film export.

## Findings and resolution

- Paths with spaces left filesystem URLs encoded in audio, captions and verifiers. Joins and motion silently
  returned success because their CLI entry comparison failed. Persistent spaced fixtures failed five cases
  before correction. fileURLToPath/pathToFileURL now resolve these paths and execute the gates.
- The standard verifier allowed AppData output, unlike hero verification. Its rejection test failed before
  the guard was added. Tests deliberately check refusal when Pester TestDrive is under AppData; private-root
  fixtures separately exercise successful outputs from both verifiers.
- Frame screening wrote JPEG scratch to the system temp directory. A controlled screen fixture failed before
  scratch moved beneath the configured media root. This fixture supplies a fake local response, without network.
- The standard verifier produced all stills, then crashed during forced process.exit on this Node runtime.
  The same controlled fixture reproduced it twice. Setting exitCode allows the loader to drain and it passes.

## Evidence

The three new Node suites failed against an unchanged private template copy. The initial full aos test returned
393 passed / 1 failed in both shells: its renderer fixture collided with the AppData output guard. That failure
was retained as a policy check rather than bypassing the production guard. After the additional path/scratch/exit
repairs, all 25 Node cases passed with no skips in a private root, including successful controlled verifier output.
The revised full suite and independent review remain gates before pushing. Claims/text checks establish coverage;
they cannot establish factual truth, pixel legibility, playback or listening quality.

Codex verdict: the concrete findings above are resolved in the inspected code and Node fixtures. Approval to land
remains conditional on the revised full suite, preview and the other vendor's separate review.

## Response to the independent implementation review

Receipt 20261003-160720-6538 returned REVISE. That verdict remains in the adjacent Claude review, separately.

- Reproduced the blocking TSX false positives: arrow-function parentheses, comparisons and numeric font weights
  were mistaken for screen words. A new fixture failed before extraction was limited to real matching JSX tags
  and numeric style literals were excluded. Literal text props/children remain the authored convention.
- Corrected unsorted/repeated hero key frames: extraction is in stream order, so requests are now sorted and
  deduplicated before naming evidence files. A controlled ffmpeg-order fixture verifies frame 30 is key-030 and
  frame 90 is key-090. The initially written fixture used an invalid in-checkout media root; after correcting that
  fixture, a private copy with the original unsorted implementation failed extraction as expected.
- Documented runner preconditions rather than introducing another setup mechanism: shell production overrides
  select a pre-provisioned app with source/dependency junctions and measured public voice assets. The two verifiers
  provision their private apps themselves. Merely choosing a new media root is not an end-to-end setup.
- Accepted the Pester location gap explicitly: when TestDrive is AppData, the fixture verifies refusal, while
  private Node runs exercise the successful path. No guard bypass or skipped test. The independent reviewer also
  ran the success path privately. A mocked renderer is not real Remotion/ffmpeg execution.
- Added fixed claim kinds and a named missing-caption error, with failing CLI cases first. Documented VO_DIR copy
  requirements and unscanned alternate text props. Git is required for hero verification. Extra inactive joins
  are a minor retained limitation; they do not alter the active shot list or authorize any export.

All 27 Node cases pass privately after these repairs. The prior revised full suite passed394 in both shells;
the final suite is running again for the review repairs. Bootstrap dry-run and Bash syntax succeeded. A bounded
independent re-review is required before landing. This report continues to make no film or listening verdict.

The first bounded re-review (161725-d458) remained REVISE: the matching-tag regex omitted mixed inline children
and attributes containing comparison/arrow operators. All four supplied examples failed a new fixture. Extraction
now tracks tag nesting and balanced quoted/braced attributes, collecting prefix and tail text around nested tags.
A further failed fixture led to rejection of computed inline HTML words while keeping conditional geometry and
literal fragments usable. The three suites now pass29 cases privately, without skips. This remains a convention
checker, not a general TypeScript parser or a replacement for rendered pixel review. Final bounded review and the
full suite remain required before push; previous REVISE verdicts are preserved.

Receipt 163227-350d confirmed the mixed-child repairs but found an ungrouped string-literal alternation. Ternary
and concatenated children produced junk strings instead of computed-text errors. Its three examples failed a
new fixture before the expression was grouped and anchored as a whole. All30 Node cases now pass privately.
The remaining scanner limitations (regex literals, custom dynamic text and mapped children directly inside HTML
text elements) are documented, with mandatory explicit pixel/ledger review rather than a completeness claim.

Final verification: receipt164419-6706 APPROVES the bounded repair and independently ran all30 cases. The exact
final-code aos test run passed394 in each shell, with zero skips; its private TEMP/TestDrive also exercised both
successful verifier paths. Bash syntax, diff whitespace and the bootstrap preview passed. Codex approves landing
the transfer with the documented scanner/setup limits. Claude's approval remains its own adjacent report, and
earlier REVISE reports remain intact. No actual template Remotion render, Whisper measurement, or listening is
inferred from these controlled fixtures; the separate film used its real sealed export and independent reviews.
