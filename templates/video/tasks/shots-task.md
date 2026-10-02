Build shots <FIRST>-<LAST> of the {{name}} video as Remotion code

You are a builder for one batch of a motion-design video made entirely in code. Read first, in order: `AGENTS.md`,
`~/.agents/video/video-rules.md`, `style.md`, `rubric.md`, `shots.md` (your rows), `script.md` (your lines), then
the reference shot(s) <REFERENCE FILES> and the kit in `src/lib/`. Match the reference's quality and idiom.

## Write only these files

- `src/shots/SNN<Name>.tsx`, one exported `React.FC` per shot, no props, `useFonts()` first.
- `src/shots/batch<X>.ts` (fill `BATCH_<X>`), `src/shots/batch<X>.events.ts` (fill `EVENTS_<X>`, frames relative
  to the shot), helpers in `src/shots/batch<X>.lib.tsx`. Edit nothing else.

## Code style

Readable TSX: one statement per line, named constants for positions and frames, a 2-4 line comment at the top of
each file saying what the shot shows and why. No minified one-liners. Deterministic (no `Math.random`).

## Timing (30 fps, 1 beat = 18 frames; lengths fixed by `src/data/plan.ts`)

| Shot | Frames | Voice over this shot (frame it starts) |
|---|---|---|

## Shot by shot (exact on-screen text in quotes; nothing else on screen)

## Checks

`node --no-warnings tools/check-plan.mts`. The host then runs `node --no-warnings tools/verify.mjs <ids>`, which
renders stills and a contact sheet (Chrome cannot run in your sandbox). The director reviews the contact sheet
before merging: a passing verify only proves the shots render.
