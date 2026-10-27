# {{name}} (video)

Instructions for Claude Code and Codex; `CLAUDE.md` imports this file. Made with `aos video new {{name}}`.
Read `PREFLIGHT.md` first (the invariant rules with their ids, the craft frontier with the best exemplar per
dimension to start from and beat, how long each stage took before); refresh it with `aos video preflight {{name}}`. Read `~/.agents/video/video-rules.md` before
every stage.

## What this is

A video made as code: Remotion (React) for picture, three.js / react-three-fiber or SVG for the scenes, a Node
synthesizer for music and effects (`tools/audio.mts`), local Kokoro v1.0 for the voice. Stages and files:
`brief.md` + `rubric.md` (definition of good) -> `style.md` + `style/` (look) -> `script.md` + `shots.md` +
`src/data/plan.ts` (structure) -> `src/shots/` (production) -> `qa/` -> `exports/` -> `retro.md`.

## Layout

- Code and text here (OneDrive). Rendering runs from `~/.aos/video/{{name}}/app`: a junction `node_modules` to the
  shared Remotion install and a junction `src` to this project's `src/`; `tools/sync-app.sh` copies the configs.
- Heavy output (renders, frames, stems, voice WAVs in `app/public/vo`) stays in `~/.aos/video/{{name}}`.

## Commands (Git Bash, from this folder)

- Plan check: `node --no-warnings tools/check-plan.mts`
- Voice: `node tools/make-voice.cjs 3 1.0 [lineId]` (3 = af_heart; audition others with `VO_OUT=<dir>`)
- Review sheet of chosen frames (the director's main loop): `bash tools/frames.sh <sheet> S01:20 S02:140 ...`
- Stills: `bash tools/still.sh <frame> <CompositionId>...`; verify a checkout: `node --no-warnings tools/verify.mjs S01 S02 ...`
  (bundles, renders first/middle/last frame per shot, writes a contact sheet)
- People in 2D films: `src/lib/cast/` (`Person`, `POSES`, `walk`, `talk`, `handPos`; colours in `palette.ts`). Review
  the cast before it goes into shots and after any kit change: `bash tools/still.sh 0 CastSheet CastTrio CastFaces
  CastHands`; geometry tests `node --no-warnings --test tools/checks/cast.test.mts`
- Soundtrack stems: `node --no-warnings tools/audio.mts`; full build: `bash tools/build.sh v1`
- QA: `bash tools/qa.sh exports/{{name}}.mp4 exports/{{name}}.srt` (length from `qa.env`; includes the motion
  check on a texture-free proxy, report `qa/motion.md`), then `node tools/screen.mjs` (on-screen text)
- Currency gate (R27): `node tools/checks/currency.mjs currency.json --claims claims.json`; export day: `node tools/reverify.mjs currency.json --browser-ok <ids> --evidence research/reverify-<date> --write` (each source gets a proof file: URL, time, SHA-256 of the page, anchor excerpt; a browser row needs one saved from the browser), then rebuild and QA on that local day. Build and QA pass `--export`; the dated ledger is part of the input manifest.
- Blender sets (R41-R43): look-dev live through the Blender MCP with `BLENDER_LIB = r"<this folder>/blender/lib.py"; SHOT = "<variant>"; exec(open(r"<this folder>/blender/s_<set>.py").read())`, one still per change; finals headless: `python tools/render-shot.py S02 S11 ...` (table in `blender/shots.json`: script, SHOT variant, offset, preroll) -> `app/public/clips/<id>.mp4` and `src/data/media.json`; seconds per frame in `renders/render-log.jsonl`
- Engine shots (R55-R57, `engines/README.md`): Godot (`engines/godot`, shots extend `lib/aos_shot.gd`), Manim (`engines/manim`, scenes import `aos`), Unreal/Unity after their spike, `cmd` (Autograph) and `import` (Cavalry or any hand render) in `engines/shots.json`; `node --no-warnings tools/export-look.mts` after a look change; finals `python tools/render-shot.py S04 --repeat 30` (same clips, log, media.json and exposure gate as Blender); tests `python tools/checks/engines_test.py`
- CC0 assets: `python tools/polyhaven.py model|hdri|tex <id> [1k|2k]` (budget `BUDGET_MB` in qa.env, ledger `research/assets.md`); `python tools/polyhaven.py budget`
- Shorts edit (R44): `python tools/edit.py` cuts on the words named in `src/data/cuts.json` -> `src/data/edit.json`
- Page captures (R45): `node tools/capture.mjs [name...]` from `research/capture-pages.json` -> `app/public/captures/`, ledger `research/captures.json`
- Real material (R42, R52): `python tools/commons.py search|info|fetch|ia-search|ia-fetch ...` (Wikimedia Commons / Internet Archive, licence and author into `research/assets.md`, counted against `BUDGET_MB`); real face detection on footage: `~/.aos/venvs/cv/Scripts/python.exe tools/detect.py <video> <start> <dur> <crop x> <shot id> [--pan x2]`
- Review sheet of the assembled composition: `bash tools/stills.sh <name> S05:0.9 S11:0.5 ...` (one bundle, one still per shot)
- Human voiceover (R53): `python tools/ingest-voice.py take1.m4a take2.m4a ... [--dry] [--verify]` (takes in script order; needs `AOS_WHISPER_MODEL`, and `AOS_VO_LANG=it` or the narration's language when it is not English) -> `app/public/vo/<id>.wav`, `src/data/vo.json`, `words.json`, `words.sha256.json`; report in `<media>/voice/ingest-report.md`. A loop (R54) is set in `src/data/cuts.json`: `"head"`, `"gap"`, `"outro_frames"`.
- Pacing report (R29): `node tools/checks/pacing.mjs <film.mp4> --shots src/data/shots.json --claims claims.json --lines src/data/lines.json --out qa/pacing`
- Render cache (R32, default in build.sh): `bash tools/render-cached.sh`; `AOS_RENDER_CACHE=0` renders Main whole; tests `node --test tools/cache/cache.test.mjs`
- Motion check alone: `node --no-warnings tools/checks/motion.mjs <proxy.mp4>`; its tests: `node --test tools/checks/`
- Input provenance (R22): build snapshots inputs before rendering, checks them again afterward and seals the exact
  MP4/SRT hashes. QA rejects changed inputs or artifacts before decoding/proxy work. Rebuild after a mismatch.
  `node --test tools/checks/input-manifest.test.mjs` exercises the guard. An isolated caller may select its private
  runner for this check with `AOS_VIDEO_MEDIA_ROOT`; this does not relocate the other build scripts automatically.

## Imported material (rules R35, R39)

Films use real material found for each shot's need, from any source: first the subject's own (its paper, launch or
demo video, live page capture), then coverage excerpts, then open libraries, then built. `shots.md` records each
shot's need and source; the brief's Sourcing section establishes the channel's policy and the download budget the user
approved, and `sourcing.json` records them for the tools. Permission to import is not permission to mix media: R28
decides how practices mix, and imported material appears in the hero next to a built practice.

- Search: `aos asset search "<words>" --kind clip|photo|model|hdri|texture|sfx [--source <id>]` (Pexels, Pixabay,
  Openverse, Wikimedia, NASA, Internet Archive, Poly Haven, ambientCG, Freesound; keys via `aos secret set`).
- Fetch any URL: `aos asset fetch --film . --id a07 --url <url> --kind clip --basis <license|cc0|public-domain|fair-use|capture|own>
  --acquisition <api|direct-file|platform-feature|download-tool> --platform <p> --why "<need>" [--source-in s --source-out s]`;
  live pages: `aos asset capture --film . --id a08 --url <url> --mode shot|scroll|record`.
- Then add each row's `uses` (shot, shotFrom, mediaFrom, mediaTo, audio, rationale) to `assets.json`, and run
  `aos asset proxy --film .`, `aos asset registry --film .` and `aos asset credits --film .` (paste into description.md).
- Shots use media only through `src/lib/media/` components and an asset id (`<Clip asset="a07" use="u1" look={look} />`,
  `Photo`, `Capture`, `Model`, `Environment`, `GlTransition`); never a path. Transitions: `src/lib/transitions`.
- `aos asset budget --film .` shows the budget; `--approve <MB> --by-user` only after the user approved the amount.
- The gate (`tools/checks/assets.mjs`, run by build and QA) checks policy, not law; `qa/assets.md` lists the human
  checks: the narration comments on each excerpt, every source tag is legible, no excerpt takes more than it needs.

## The learning loop (rule R20)

- After each stage: `aos video log {{name}} <brief|look|structure|production|qa|delivery|retro|revision> <minutes> [note]`.
- Every verdict the user gives, verbatim: `aos video verdict {{name}} <their words>`. It goes to the ledger for
  audit only (`aos video preflight {{name}} --verdicts` shows it); no agent works from raw verdicts.
- Motion: every move goes through `src/lib/motion.ts`; the motion check reports snaps and expo curves.
- nar (rule R21): when choosing among style frames, `nar_choose` is a second signal; keep its call_id and the
  candidates in `retro.md`, and send `nar_feedback` only if the user compares those same candidates.
- The retrospective converts, it does not accumulate. For each verdict: (1) close the gap in the kit (template,
  `src/lib`, an asset or rig library, a tool or a check) with a test or a rendered exemplar; (2) rewrite that
  dimension's entry in `~/.agents/video/frontier.md` (new `best`, `how`, `next`, `try`; a gap is written as a
  target). A new rule in `~/.agents/video/video-rules.md` only for a technical or process guard, as `[check: x]`
  with a script in `tools/checks/x.mjs` called from `tools/qa.sh` whenever a script can catch it; taste never
  becomes a rule.
- Look gate: the look lab renders the frontier's `best` frames next to the new ones on the same beats; a dimension
  passes when both vendors, blind, judge the new frame better.

## Done means

`tools/check-plan.mts` passes; every shot renders; `tools/qa.sh` passes (1080p30 yuv420p, -14 LUFS +-1, TP <= -1 dBTP,
no black/frozen segments, captions inside the duration); the rubric scores no 0 on the contact sheet; the user has
heard the voice.

## Conventions

- One file per shot `src/shots/SNN<Name>.tsx`, readable code (one statement per line, named constants, a 2-4 line
  header comment); pure timing data that the audio tool needs goes in `.data.ts` or the batch's `.events.ts`.
- Parallel builders each own a batch file (`batchX.ts`, `batchX.events.ts`, `batchX.lib.tsx`), spread into
  `registry.ts` and `events.ts` by the director. Everything is a pure function of the frame (no `Math.random`).
- Every number and quote on screen matches `script.md` and a row in `sources.md`.
## Production checks

Author `src/shots/poses/<id>.ts` (`export const poses = {start, end}`) for every shot, imported only by that shot's
module and passed to its stage, so a pose edit re-renders one shot; the joins gate rejects shared pose tables. Use
`src/lib/shot-camera.ts` for frame-keyed cameras that hold
through dissolves. The empty scaffold intentionally fails the joins gate until these poses exist.
Review narration and every authored on-screen string in `claims.json`. Write screen words as literal `text`
properties/attributes or JSX children in shot/library consumers; stock forwarding helpers contain no authored
words. Run claims, screen-text, check-plan and joins before rendering. QA repeats coverage and joins; independent
source and full-size frame review establishes truth and legibility.

After generating voice, set `AOS_WHISPER_MODEL` to an existing local model directory and run `tools/word-times.py`
with the installed Whisper Python. No downloads are attempted. It writes words.json and words.sha256.json from
the same `vo.json` WAV paths as audio.mts. Picture and sound share cue-core; a changed voice refuses the mix before
any stem overwrite. Empty word timing also blocks production until measured. `caption` falls back to `text`;
an explicit empty caption omits that line's cues.

Set `AOS_VIDEO_MEDIA_ROOT` to a private directory for isolated production; every media tool honours it.
Before shell build/render/still/frames/QA, provision that root's `app/src` junction to this checkout's `src`,
`app/node_modules` junction to the existing read-only dependency installation, and `app/public/vo` with the
measured WAVs; create its renders/frames directories. The override selects an existing runner; sync-app.sh
copies config files and does not create junctions. Both verifier tools provision their own private runners.
Use claim kinds fact, definition, quote, inference, illustration, hypothetical, label or title. Extra detail
belongs in the evidence anchor, rather than changing the kind. Screen words use the literal conventions above;
other props such as title are not scanned, so independent pixel review remains required.
The lightweight JSX scanner is not a TypeScript parser: regex literals and custom dynamic text can escape its
conventions. For files using those constructs, review their rendered words explicitly against the ledger;
never treat a passing gate as complete screen coverage.
If VO_DIR overrides the files measured by word-times.py, copy those exact WAV bytes to the runner paths in
vo.json before audio.mts. The default measurement uses those runner paths directly.
`node tools/verify-hero.mjs Composition:30,90,150` checks explicit clips; `--stills Composition:30,Other:60` checks
only frames. Hero verification owns a bundle under `hero-verify/<branch>` within that media root; never share
that bundle with a running verifier. Both verifiers use read-only shared dependencies and private apps.

Reviews and speed (rules R26, R30, R32). `node --no-warnings tools/review-sheets.mts <export.mp4>` writes the shot
sheets (every shot at 20, 50 and 85 %) and the dissolve sheet under the media root; give them to the other vendor as
images (`codex exec -i`) at the look gate, the hero, the animatic and the final cut, not only at the end. Render review
cuts at `--scale=0.5` or quarter scale. Do not edit hashed inputs, build scripts or this checkout while `build.sh` or
QA runs; reviews, docs and the next brief can run beside a render, edits to the tree cannot. Keep the computer awake
for long jobs, and log each stage's minutes with `aos video log`. Use `-nostdin` for ffmpeg inside shell loops.
