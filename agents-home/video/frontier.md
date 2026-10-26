# Video craft frontier

The best each dimension has reached so far, how it was reached, and what the next film aims past. `aos video
preflight` inserts this file. Rewrite an entry at every retro (never append history: git keeps it); a new film
starts from each `best`, compares its look-lab frames against it side by side, and passes a dimension only when
both vendors, blind, judge the new frame better. A gap is written as a target, not as a fault.

## Characters and acting
- best: alignment-now v8+ host (lit 3D, mouth set in the face, GTAO, no chromatic aberration).
- how: three.js/r3f character in a dressed set; acting through eyes, lids and hands; 100 % crop checks.
- next: a 2D cast in the Rational Animations language: round, readable silhouettes, large in frame, acting with
  eyes, brows, hands and follow-through, consistent across every shot.
- try: a rigged SVG character kit in Remotion (part hierarchy, pose library, blink/breath/overlap built in) and
  Blender Grease Pencil, compared in the look lab against each other and a reference frame.

## Motion
- best: alignment-3 onward: every move through `src/lib/motion.ts` (soft in-out curves, minimum move length,
  settle, breathe); `tools/checks/motion.mjs` reports snaps and expo curves.
- next: camera and characters that glide and overlap: secondary motion, arcs, anticipation on soft curves, energy
  from cut rhythm and acting rather than fast easing.
- try: damped follow-through and arc helpers in motion.ts, measured by the motion check.

## Scene, texture and light
- best: cant-escape-ai-2 (scanned CC0 models and PBR textures in Blender, p90 exposure gate) and alignment-now v8
  (GTAO, no halo, no CA).
- next: illustrated 2D sets with depth: layered painted backgrounds, soft gradients, rim light, grain, props that
  carry meaning.
- try: a background layer kit (parallax planes, gradient light, grain shader) shared by every shot of a film.

## Visual metaphor and recognition
- best: cant-escape-ai-2: storyboard recognition gate (R48) judged by the other vendor before any render.
- next: one staged metaphor per idea that a first-time viewer reads without the narration.
- try: generate 3+ metaphor candidates per beat (pool_variants), the other vendor judges the boards blind.

## Real material
- best: cant-escape-ai-2: commons.py with licence ledger, real detection on real footage (R52), page captures.
- next: imported material graded into the film's design system so it sits inside the illustrated world.

## Pacing and engagement
- best: alignment-now: 6.9 shots/min, 9 practices under one design system; cant-escape-ai-2: 2.5 s mean shot (short).
- next: report from `tools/checks/pacing.mjs` beats the last film's pacing.json on time-to-hook and longest hold.

## Voice
- best: cant-escape-ai-2 v5: the user's own recorded voice through tools/ingest-voice.py; Italian synthetic:
  alignment-now-it, Kokoro if_sara at 1.25x with a cue map from English cues to Italian words.
- next: an Italian narration that sounds natural to the user at the audition gate.
- try: audition if_sara and im_nicola at 2-3 speeds plus the user's own voice option.

## Sound
- best: synthesized score and effects from tools/audio.mts, word-timed through cue-core; -14 LUFS, TP <= -1 dBTP.
- next: a score whose motifs follow the script's turns (problem, race, stakes, call).

## Text on screen and claims
- best: alignment-now v8: QuoteCard/LogCard grammar; every string in claims.json (screen-text check).
- next: claim cards in the film's illustrated language, sourced on screen in one short line.

## Accuracy and currency
- best: alignment-now: currency gate (R27) plus an independent blind accuracy read by the other vendor after every
  narration change; cant-escape-ai-2: accuracy read before voicing.
- next: every figure on screen traces to an opened, dated primary source, re-verified on export day.
