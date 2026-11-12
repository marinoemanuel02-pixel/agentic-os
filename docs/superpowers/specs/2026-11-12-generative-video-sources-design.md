# Generated video as a material source: design

2026-11-12. Draft. First step only: more platforms will be tested before anything larger is built.
Evidence: Flow and Kling spikes, `1-Projects/videos/flow-spike/` (working files `~/.aos/video/flow-spike`).

## Why

Hosted video generators make what code makes poorly (fluid, organic motion) and their free tiers cost nothing.
The operator's rule (2026-11-12): generated material is allowed case by case; a take that reads as generic AI output
is discarded. The spikes showed a code segment, a generated transition and a code segment join without a visible
seam when both keyframes are rendered from the film's code and given to the generator as first and last frame.
Flow and Kling were judged equal in look, so platforms are chosen on quota, watermark and rights.

## Scope of this step

1. **A skill** `agents-home/skills/generate-video/` that records how to drive each tested platform, so any session can
   repeat it: `SKILL.md` (the procedure) plus one recipe per platform (`flow.md`, `kling.md`).
2. **Rights in the existing ledger**: a `generated` basis in the asset gate and an ingest path, so a kept take enters a
   film like any import (rule R35).
3. **A rule line** in `video-rules.md` and a `docs/decisions.md` entry.

Deferred until testing settles which platforms stay: a queue file, a quota ledger with automatic resume, trim and
seam tools, porting `src/lib/media` into the template, a local-model lane. The spike did trimming and seam checks by
hand with ffmpeg; the recipe records those commands.

## Rules

- Generation is opt-in per shot; the shot list names the reason.
- The operator does: one sign-in per platform in the built-in browser, CAPTCHAs, platform rights/terms dialogs, the
  download approval (the film's existing budget, `aos asset budget --approve`), and the keep verdict.
- No account tracking or switching. At quota the agent stops that platform and says when it resets.
- Never remove, crop or cover a watermark.
- Before a platform is driven, its terms are read first-hand. If they forbid automated access, the agent writes a
  prompt sheet (keyframes, prompt, length, aspect) and the operator runs it.
- No model names in the repo (repo rule): recipes say "the cheapest model with frames mode", the page lists the rest.

## The skill

`SKILL.md`, the procedure:
1. Render the keyframes from the film's code (`tools/still.sh`), 1280x720 PNG (720x1280 vertical).
2. Open the platform in the built-in browser; check credits; follow the platform recipe.
3. Write the prompt from the film's style lock. Ask for the motion to resolve into the last frame.
4. Fetch each take through `aos asset gen-ingest --url` (below).
5. Make review sheets; judge against R04 and the style lock; log keep or discard with one reason.
6. Join: trim the still tail (measure motion with ffmpeg `tblend` difference), crossfade about 4 frames in and
   10-12 out, then check the seams for jump frames.

Recipes hold only what was observed, each with its date; a step that no longer matches the page stops the run.

Observed 2026-11-12:

| | Flow | Kling |
|---|---|---|
| Free credits | 50/day (Google's help page; not read on the page) | 66 (shown on the page) |
| Frames mode | prompt bar: Video, then Frames (Start/End slots; UI follows the account language) | Generate, reference dropdown: Keyframes (First/Last) |
| Cost seen | 20 for 2 takes (cheapest model) | 50 per take (flagship), 30 (fast) |
| Upload that worked | drop event with the files on the media area | first frame: the slot's file input; last frame: its Upload item opens a file input |
| Dialog | image-rights confirmation on upload (operator) | none |
| Wait | about 1.5 min | about 4 min |
| File link | take page, `video.currentSrc` (signed) | `projects-assets/batch-status` response, `works[].resource.resource` |
| Output | 1280x720, 24 fps, 7.9 s, audio | 1280x720, 24 fps, 5 s, audio, visible watermark |
| Behaviour | end frame held still about 2.5 s; target fades in | particles move into the target; burst starts abruptly |

Open in the recipes, to check first-hand before relying on them: each platform's terms on automated use and on
commercial use of free output (secondary sources say Kling's free output is non-commercial; Flow's is unconfirmed).

Getting a local file into the page: the built-in browser cannot (no file picker, no local fetch, no synthetic paste).
The spike redrew simple keyframes on a canvas in the page, which only works for simple geometry. Try first, with one
real call each (R08): Claude in Chrome's file upload tool, then passing the PNG's bytes into the page.

## Rights

`aos asset gen-ingest --film <dir> --id <aNN> (--url <link> | --file <path>) --platform <p> --terms-url <url>
--terms-read <date> --watermark yes|no --commercial yes|no|unknown --why "<need>"` fetches through the kit's own
fetch path (so the budget cap holds), measures, proxies, and writes an `assets.json` row with basis `generated` plus
those fields and the prompt. `--file` is for takes the operator ran from a prompt sheet.

The gate (`templates/video/tools/checks/assets.mjs`): `generated` is a known basis and needs those fields;
`sourcing.json` gets `"generated": {"allowed": true, "monetized": false}`; a `generated` row fails when `allowed` is not
true, or when `monetized` is true and `commercial` is not `yes`. Watermarked rows go to `qa/assets.md` for a human check.

## Files

- `agents-home/skills/generate-video/` (new); listed in `tool-catalog`.
- `agents-home/video/assets/asset.mjs` (gen-ingest) and its tests.
- `templates/video/tools/checks/assets.mjs` and its test; `templates/video/sourcing.json`.
- `agents-home/video/video-rules.md` (one appended rule), `docs/decisions.md` (entry on top).

The skill is linked into `~/.claude` by `aos sync`, so the change gets a Codex review first (repo rule).

## Open question

Which films count as monetized? It decides whether Kling's free output is usable and whether `commercial: unknown`
(Flow today) blocks. Until answered, `monetized` defaults to false per film and is set when the film is briefed.
