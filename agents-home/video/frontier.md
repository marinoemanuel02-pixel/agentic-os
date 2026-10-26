# Video craft frontier

The best each dimension has reached so far, how it was reached, and what the next film aims past. `aos video
preflight` inserts this file. Rewrite an entry at every retro (never append history: git keeps it); a new film
starts from each `best`, compares its look-lab frames against it side by side, and passes a dimension only when
both vendors, blind, judge the new frame better. A gap is written as a target, not as a fault.

## Characters and acting
- best: pauseai-it v10 (2026-10-26) cast, now the template kit `src/lib/cast/` (review sheets `CastSheet`,
  `CastTrio`, `CastFaces`, `CastHands`). Built in head units (about 5.5H, a neck of about 0.12H that starts inside
  the jaw and ends in the collar), one tapered torso shape per garment (t-shirt, sweater, collared shirt, suit, lab
  coat), three builds and a child body, three head shapes, eight hair styles, faces that vary per character (eye
  spacing and size, jaw, nose). Limbs are filled tapered outlines with a rounded joint and fabric creases; hands
  are an eight-pose library drawn as one silhouette each (union outline); shoes have heel, toe box and sole, the
  near foot foreshortened in 3/4; eleven mouth shapes plus `talk()`; coloured outlines lighter on internal details.
  Codex, blind against the v9 cast: "a large improvement in general quality".
- how: research first (studio styles, Disney appeal, 2D rigs: RubberHose, Duik, Spine, Rive, Character Animator),
  turned into a numbered spec in head units; then a cast sheet at film scale and at close-up, judged by both
  vendors before any shot; geometry under test (`tools/checks/cast.test.mts`).
- next: acting, not construction: poses with a line of action, weight shifts, overlapping action on hands and hair
  in motion; faces that read at a quarter-screen height.
- try: key poses per beat taken from `POSES` and blended, a dynamic line-of-action lean, blink and gaze offsets per
  character; judge in motion (a 3 s clip per character), not only on stills.
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
## Accuracy and currency
- best: alignment-now: currency gate (R27) plus an independent blind accuracy read by the other vendor after every
  narration change; cant-escape-ai-2: accuracy read before voicing.
- next: every figure on screen traces to an opened, dated primary source, re-verified on export day.
