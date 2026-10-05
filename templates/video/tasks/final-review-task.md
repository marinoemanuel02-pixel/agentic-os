Independently review the exact final export of {{name}} (read-only)

The director fills the values below before `aos delegate <other-vendor> --task <file>`.
Keep this review blind: do not read the director's findings, verdict or response first.

- Export: <relative MP4 path>; expected SHA256: <hash>.
- Prior export and SHA256: <paths/hashes, or none>.
- Final input manifest: <relative path>; expected digest/file count: <values>.
- Frame provenance and sheets: <relative paths>; shot count: <count>.
- Changed shots: <ids>; full-size before/after crops: <paths>.
- Narration, claims and currency: <paths>; export date/timezone: <date/zone>.
- Technical QA, white scan and mix transcription: <paths, or pending>.
- Time budget: <minutes>; no edits, software/asset installs or downloads, or reset credits. Read-only source-page
  browsing is permitted; it does not require an install or an asset download.

Verify the media hash, input-manifest digest/file count and frame provenance yourself. Open the prior version's
sheets as well as each final sheet covering every shot's middle and settled end frame, to check regressions.
Inspect changed or suspicious details at 100%. Record the shot/frame ids visually opened. Numeric
image comparison is useful but does not count as looking at a frame. For animated text, check typing completion,
caret overlap and readable hold before the cut. Check label association, closing/terminal frames and narration-to-
picture coherence. Distinguish a partial middle state from an incomplete end state.

Read narration blind for naturalness and accuracy against the ledgers. If a short evidence excerpt omits a
detail, mark it unresolved and identify the original source/anchor needed; do not automatically weaken a true
claim. Motion hit waivers require real frames around each new hit. Stills and ASR do not establish playback or
perceptual listening. Check available QA receipts; call pending checks pending, never passed.

Return a receipt with:

- Verdict and numbered defects: severity, shot/line, observed behavior, cause if known, checkable correction.
- Exact hash/provenance checks and frame ids visually reviewed; list any omitted frames.
- Narration lines read, source pages opened, commands run and their exit results.
- Separate status for stills, motion/playback, perceptual listening, claims and technical QA.
- Explicit limitations, including pending receipts; proposals separate from release blockers.

The director reads this receipt, confirms each finding in the source and full-size evidence, and records a
response separately: both flagged / only director flagged / only reviewer flagged. Agreement requires the same
location and defect. Preserve superseded reviews and exports; a fix requires new evidence from the rebuilt export.
