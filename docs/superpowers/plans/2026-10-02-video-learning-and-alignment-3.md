# Plan: a video pipeline that learns, and the third alignment video

Date: 2026-10-02. Approved in conversation ("yes, go ahead"); the user's goal: stop only when the video is
packaged, these orchestration changes are in place, and everything is pushed. No gate stops: style frame and hero
shot are sent to the user as they are made, not waited on.

## Why

The user's verdicts on the alignment video: v1 "still very much shape-like"; after v2, "still too shape-like and
simple, as well as having too-snappy animations". Root causes found by reading the v2 code and frames:

- **Snappy**: the kit's house ease is `Easing.bezier(0.16, 1, 0.3, 1)` (expo-out: full speed at frame 0) over 8-16
  frames, in 2-4 s shots with hard cuts and cards. Nothing in QA measures motion quality.
- **Shapes**: dark dusk palette, flat fills, small characters in wide shots, four media (vector, pixel, Blender,
  three.js) that read as four demos; 36 shots and five dense cases in 2:00.
- **Not learning**: lessons are prose lines appended to `video-rules.md`; nothing enforces them, nothing records
  stage times, delegate outcomes or the user's verbatim verdicts, and nar picks are never scored against verdicts.

Reference (Rational Animations, frames looked at 2026-10-02): coloured (not black) ink outlines of varying weight,
cel shading (base + one hard shadow tone + highlight), warm saturated palette, dense lived-in sets full of props,
characters large in frame (close-ups, over-the-shoulder, hands drawing diagrams in-scene), slow camera, long shots.

## Part A: orchestration that learns (agentic-os)

1. **Rules with ids and kinds.** `agents-home/video/video-rules.md` lines become `- Rnn [manual] ...` or
   `- Rnn [check: <name>] ...`. A `[check: x]` rule must have `templates/video/tools/checks/x.*` (test enforces).
2. **History ledger.** `agents-home/video/history.jsonl` (synced to `~/.agents/video/`), one JSON object per line:
   `{ts, video, kind: verdict|stage|delegate, ...}`.
   - `aos video verdict <name> <text...>` appends `{kind:"verdict", text}` (the user's words verbatim) and the same
     line to the project's `verdicts.md`.
   - `aos video log <name> <stage> <minutes> [note...]` appends `{kind:"stage", stage, minutes, note}`.
3. **Preflight.** `aos video preflight [<name>]` prints the rules (id, kind, text), the last 10 verdicts across
   videos, and the median minutes per stage; `aos video new` writes the same into the project's `PREFLIGHT.md`.
4. **Motion check** (template `tools/checks/motion.mjs`, run by `tools/qa.sh`): static scan of `src/` for
   expo/back-out curves and moves shorter than `MIN_MOVE_FRAMES`; dynamic scan of the export (ffmpeg frame
   differences) for snaps: a frame-difference jump inside a shot (cuts from `plan.ts` excluded) that rises from
   rest to peak in <= 2 frames.
5. **Template kit.** `src/lib/motion.ts`: soft in-out curves, `settle`, `drift`, `boil` (8 fps line wobble seed),
   `MIN_MOVE_FRAMES`. Shot guidance 5-8 s; dissolves and match cuts; rubric gains "easy to follow" and "calm motion".
6. **nar calibration.** The style-frame pick uses `nar_choose` (task_type `video-style-frame`); the user's
   verdict is reported with `nar_feedback`. Written into the template AGENTS.md.
7. Tests in `tests/aos.Tests.ps1` (written first by Codex from a spec, seen failing, then implemented); `aos test`
   in both shells; a dated `docs/decisions.md` entry; second opinion from Codex on the diff.

## Part B: the video `alignment-3` (`aos video new alignment-3`)

- ~3:00, English, YouTube 1080p30, -14 LUFS. One medium: illustrated 2D with depth (multiplane parallax), cel
  shading with coloured variable-weight ink lines, line boil at 8 fps under smooth motion, paper grain, warm
  saturated palette, dense sets. Pip redesigned for expression (eyes with lids, brows on the visor, hands). No
  human faces (v2's human was called uncanny): humans appear as hands and arms only.
- Story, plain words, one idea per line: what we say vs what we mean (boat race, S1); what it really learned
  (CoinRun, S2); what we cannot see inside (features, S5); close. Sources reused from the alignment project and
  re-opened. ~330 words of narration at a calm pace.
- Shots 5-8 s, continuous camera drift, soft in-out moves >= 18 frames, overlapping action, dissolves/match cuts.
- Kokoro af_heart (approved), LMMS/Node score; both flagged unheard.
- Production: the director (Claude) builds the kit, style frames and hero shot; Codex builds well-specified shot
  batches with `aos delegate codex --write --verify`; every batch reviewed on a contact sheet.
- QA: `tools/qa.sh` including the motion check, Whisper, OCR screen, local-model screen; craft review; independent
  review by Codex. Package to `exports/` and the Inbox; `retro.md`; rules, verdict and timings into the ledger.
- Push: agentic-os branch `phone-orchestration-design`; the video project to a new private GitHub repo.

## Risks

- Codex Plus window already used by v2 today: check every run for "usage limit"; Claude builds if Codex is out.
- Render time: SVG filters per frame are slow on CPU; textures are pre-rendered PNGs, boil is a cheap displacement.
- Illustration craft from code: the hero shot is the calibration; it is reviewed at full resolution before batches.
