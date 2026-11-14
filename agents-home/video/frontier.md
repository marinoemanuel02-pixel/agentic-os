# Video craft frontier

The best each dimension has reached so far, how it was reached, and what the next film aims past. `aos video
preflight` inserts this file. Rewrite an entry at every retro (never append history: git keeps it); a new film
starts from each `best`, compares its look-lab frames against it side by side, and passes a dimension only when
both vendors, blind, judge the new frame better. A gap is written as a target, not as a fault.

Each `best` names the film's tag or commit and what judged it. A dimension that moves (acting, motion, timing,
sound) is judged on a clip or the film, never on stills alone: the 2026-10-26 entry below came from stills, and the
operator then rejected that cast in six verdicts (v8-v16) before accepting a different one.

## Characters and acting
- best: pauseai-it tag `final-v20` (accepted by the operator on the moving film, both formats, 2026-10-29): the drawn
  cast in `src/lib/Toon.tsx`, `ToonHead.tsx`, `hands.ts` and `ToonPerson.tsx` (Codex's design B from v15, in Rational
  Animations' sober register: muted palette from the scene, thin even line, about seven heads tall, profile-line
  faces, two-segment limbs solved per joint; rig tests in `tools/checks/toon-rig.test.mjs`). Not yet in the template.
  Superseded: `Person.tsx` (2026-10-26), judged better than alignment-3's Pip from stills by both vendors, rejected
  by the operator on the film. `src/lib/Mind.tsx` (one-eyed creature with breathing lobes) was not part of that verdict.
  Superseded: the cast kit in `templates/video/src/lib/cast/` (PR #2) is the v9 redesign, which did not pass the
  operator on the v9 and v10 films (verdicts in the ledger); it stays in the template as merged work until the Toon
  cast replaces it.
- how: SVG rig as pure functions of the frame, poses as props, blinks/breathe/lag from motion.ts; the look set
  against operator-named reference frames (Rational Animations) before production.
- next: characters that change shape language with emotion (squash, stretch, overlap) and hands that grip.
- try: a pose library per character and a two-character contact helper (holding, pulling, handing over).
## Motion
- best: alignment-3 onward: every move through `src/lib/motion.ts` (soft in-out curves, minimum move length,
  settle, breathe); `tools/checks/motion.mjs` reports snaps and expo curves.
- next: camera and characters that glide and overlap: secondary motion, arcs, anticipation on soft curves, energy
  from cut rhythm and acting rather than fast easing.
- try: damped follow-through and arc helpers in motion.ts, measured by the motion check.

## Scene, texture and light
- best: alignment-3 for 2D (layered props, foliage, warm painted surfaces; preferred blind by Codex over pauseai-it's
  night cities) and cant-escape-ai-2 / alignment-now v8 for 3D.
- how: dense authored props, coloured ink lines, cel shadow, paper grain; scanned CC0 models in 3D.
- next: night scenes as dense as day scenes: textured foreground and midground layers, not silhouettes.
- try: a prop library for the 2D kit (street furniture, interiors) and a foreground layer in every Scene.
## Visual metaphor and recognition
- best: pauseai-it: one staged metaphor per line (leash, unreadable inside, race shedding safety, rulebook pages,
  pause dome, treadmills with a STOP, snapped leash, 100 researchers, imaginary flight), preferred blind by Codex;
  two independent image reviews before shipping.
- how: the metaphor is written in each shot's header before code; reviews ask what a first-time viewer misreads.
- next: metaphors that hold without any label.
- try: a storyboard round on stills only, judged blind by the other vendor before any code.
## Real material
- best: cant-escape-ai-2: commons.py with licence ledger, real detection on real footage (R52), page captures.
- next: imported material graded into the film's design system so it sits inside the illustrated world.

## Pacing and engagement
- best: alignment-now: 6.9 shots/min, 9 practices under one design system; cant-escape-ai-2: 2.5 s mean shot (short).
- next: report from `tools/checks/pacing.mjs` beats the last film's pacing.json on time-to-hook and longest hold.

## Voice
- best: cant-escape-ai-2 v5 (the user's own voice through tools/ingest-voice.py); Italian synthetic: pauseai-it, Kokoro
  if_sara at 1.05, picked among four auditions by Whisper word error rate (all 0.034), word times measured with
  AOS_VO_LANG=it.
- next: an Italian narration that sounds natural to the user at the audition gate.
- try: the user's own recorded voice for Italian films.
## Sound
- best: synthesized score and effects from tools/audio.mts, word-timed through cue-core; -14 LUFS, TP <= -1 dBTP.
- next: a score whose motifs follow the script's turns (problem, race, stakes, call).

## Text on screen and claims
- best: pauseai-it: `ClaimCard` with literal `<Who>/<Claim>/<Src>` children (the screen-text gate sees every word),
  outcome and horizon on every estimate, a share of people never drawn as a probability; preferred blind by Codex.
- how: claims.json screen entries per source, currency.json with export-day proofs.
- next: data panels in the same illustrated material as the scenes (the blind review's remaining gap).
- try: dials and counters drawn as props inside the set, not as panels over it.
## Captions
- best: huggingface-it v6 (2026-10-30), narration at about 250 words a minute: `src/lib/Captions.tsx` keyed on the
  measured words, chunks of two rows of at most 20 characters at 84 px just above the band the apps cover, the spoken
  word easing into the accent colour, one box per run of chunks fading 0.5 s at the run's ends, and inside a run the
  next chunk replacing the last on the same frame (no fade, no empty frame); nothing over a `CAPTION_OFF` card.
- how: a chunk ends at two rows or a phrase end; chunks closer than 0.9 s share a box; the swap lands 0.05 s before
  the next chunk's first word.
- next: readable time measured rather than judged from sheets: the share of narrated frames that show a whole chunk
  at full opacity, reported per film, so the next fast short beats this one's number.
- try: the template now carries this timing (`src/lib/caption-timing.ts`, drawn by `Captions.tsx`, tests in
  `tools/checks/captions.test.mts`) and `readableShare()` computes the readable time: report it per film beside
  the pacing report. A 16:9 caption layout exists but no film has been judged on it.
## Type size
- best: huggingface-it v6: every size on screen at 36 px or more at 1080p (quote-card original and source lines,
  counter source, headline tag at 36 px, the headline's Italian note at 48 px), held by `tools/checks/type-size.mjs`
  (R58) at build and QA.
- how: small type set at the rubric's floor and the card made room for it (the quote card widened to 940 px, lines
  wrap) instead of shrinking type to fit.
- next: secondary lines (sources, translations) that read at a glance on a phone without a pause on the frame.
- try: one type scale in look.ts (caption, card, note, source) that every component takes its sizes from.
## Accuracy and currency
- best: alignment-now: currency gate (R27) plus an independent blind accuracy read by the other vendor after every
  narration change; cant-escape-ai-2: accuracy read before voicing.
- next: every figure on screen traces to an opened, dated primary source, re-verified on export day.
