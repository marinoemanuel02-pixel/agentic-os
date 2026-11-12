# Generated video as a material source: design

Date: 2026-11-12. Status: draft for the operator's review; the build plan is written afterwards with Opus and Codex.
Evidence: the Flow and Kling spikes of 2026-11-12 (`1-Projects/videos/flow-spike/`, working files in
`~/.aos/video/flow-spike`).

## Intent

The video pipeline makes films from code-driven motion, imported real material and 3D. Hosted video generators now
make things code cannot make cheaply: organic motion, fluid transitions, photoreal plates. Their free tiers give a
small daily allowance at no cost. This design adds generated video as one more material source, beside imported
clips and code, so a film can use a generated transition, asset or clip where it carries the shot.

The operator's rule (2026-11-12): generated material is allowed case by case. A take that reads as generic AI output
is discarded; a take that works in an explainer, a transition, an asset or a full clip stays. The pipeline offers the
option; it never makes generation the default.

What the spikes proved:
- A code segment, a generated transition and a second code segment join without visible seams when the director
  renders both keyframes from the film's own code and hands them to the generator as first and last frame. The
  generators land the end keyframe's geometry exactly; small brightness and colour drift is hidden by a crossfade.
- The agent can drive both sites from the built-in browser after one sign-in by the operator: upload, mode, prompt,
  submit, wait, fetch the file.
- The operator judged Flow's and Kling's transitions "kinda the same", so a platform is chosen on quota, watermark and
  rights, not on look.

## Goals

1. A film can mark shots as generated (transition, asset or clip) in its shot list, with the reason.
2. The director renders keyframes from the film's code, writes the generation request, and the agent runs it on a
   free platform with the operator out of the loop except for the steps listed under Constraints.
3. Each platform's daily quota is tracked; when it runs out, that platform's queue pauses, the operator is notified,
   and the queue resumes after the reset by itself.
4. Every kept take enters the film through the existing asset ledger (rule R35) with its rights recorded: platform,
   plan, terms page, watermark, commercial permission, prompt, keyframes.
5. Every take passes the anti-slop gate (R04) on review sheets before it can reach the picture; discards are logged
   with the reason.
6. Joins between code and generated segments are trimmed and crossfaded by measurement, not by eye.

## Non-goals

- Paid plans, paid APIs or any new subscription (free-stack rule).
- A headless bot that runs without the agent. Generation runs as agent-driven procedure steps in a session.
- Replacing code-driven motion. Generation stays opt-in per shot.
- Local generation now. The local lane (open models on the planned RTX 3090) is a later adapter behind the same
  interface; this design only keeps the interface open for it.

## Anti-goals (failure even if it works)

- Generic AI look reaching a film because the take was already paid for in credits.
- Rotating several accounts to multiply a free quota, or anything that tracks or switches accounts. Declined on
  2026-11-12: it breaks every platform's terms and risks bans that link accounts.
- Removing, cropping or covering a platform watermark.
- Accepting a platform's terms or rights confirmations without the operator's OK.
- A film that is monetized carrying a take whose plan forbids commercial use.

## Constraints

- **Operator touchpoints, and only these:** one sign-in per platform in the built-in browser (it persists); a CAPTCHA
  if one appears; a platform's rights or terms confirmation (Flow shows one on the first upload of a session); one
  download approval per batch (a film's whole generation plan can be one batch); the case-by-case keep verdict on
  takes the director proposes for the cut.
- **Quota end:** the queue pauses the platform and notifies. What the operator does about accounts is the operator's
  business; the pipeline never asks for, stores or switches accounts.
- **Terms per platform:** before a platform joins the pool, its terms are read for automated use and for commercial
  use of free-plan output, and the finding is recorded with the date. A platform that forbids automated use is not
  driven; it may still be used through the operator-run fallback (below).
- **Repo rules (agentic-os AGENTS.md):** `aos.psm1` and `bootstrap.ps1` stay ASCII and PS 5.1-compatible; no model names
  in the repo (platform names are fine; which model a platform runs is picked at run time from the page's own list or
  kept in a local, untracked config); `aos test` after every edit; tests use `$TestDrive`; every step idempotent.
- **Second opinion:** the new skill lands in `agents-home/skills` and `aos sync` links it into `~/.claude`, so the
  change gets a Codex review before it merges (repo rule).
- **Heavy files stay out of OneDrive:** takes download into the film's media root under `~/.aos/video/<film>`, like
  every other imported clip.

## Decided by the operator

- Generated material is allowed case by case (2026-11-12).
- Harvest free tiers with the operator's help, as automated as possible; the operator steps in only where a step needs
  them.
- No account rotation; pause and notify at quota.
- One platform at a time when adding platforms; Flow first, Kling second (both spiked).
- Platform choice by quota, watermark and rights, since the look was judged equivalent.

## Design

### 1. Shot list and request

`shots.md` gets a `Source` column. Values: `code`, `import`, `3d`, `gen:transition`, `gen:asset`, `gen:clip`. A `gen:`
shot names its reason in the existing "Recognisable as" column. The other vendor's blind board review (R48) also
judges whether each `gen:` shot is worth a generation.

Each film gets `gen.json`, the generation plan, next to `assets.json`:

```json
{
  "schema": 1,
  "requests": [
    {
      "id": "g01",
      "shot": "S07",
      "kind": "transition",
      "first": "keyframes/S06-end.png",
      "last": "keyframes/S08-start.png",
      "prompt": "Locked-off camera ...",
      "seconds": 5,
      "aspect": "16:9",
      "takes": 2,
      "platforms": ["flow", "kling"],
      "status": "planned",
      "results": []
    }
  ]
}
```

`first` and `last` are optional (a clip may use one reference frame, or none). Statuses: `planned`, `queued`,
`generating`, `fetched`, `kept`, `discarded`, `paused-quota`. `results` lists each take: platform, local path, fetch
time, frame count, and the review outcome.

### 2. Keyframes from the film's code

A new tool `tools/keyframes.mts` renders the requested frames as PNG stills from the film's own compositions: the last
frame of the segment before a transition, the first frame of the segment after it. It uses the existing Remotion still
renderer and writes to `keyframes/` with each frame's SHA-256 in `gen.json`. Keyframes are 1280x720 (or 720x1280) PNG,
the platforms' native size, downscaled from the film's frame.

The spike drew keyframes inside the page with a canvas because the built-in browser could not hand a local file to
the page. That is a fallback, not the route: the route must upload the real rendered PNG, so the join matches the
code exactly (see section 4).

### 3. Platform recipes (the skill)

A shared skill `generate-video` in `agents-home/skills/generate-video/SKILL.md` holds the procedure and one recipe file
per platform (`flow.md`, `kling.md`, later others). The agent follows it with the browser tools. A recipe says, for
its platform:

- where the generator is and how to reach frames mode;
- how to put each keyframe into its slot;
- how to write the prompt and pick duration, aspect, take count and the cheapest model that supports frames;
- what it costs and how the page shows remaining credits and the quota-reached state;
- how long a take usually takes and how to tell finished from failed;
- how to get the file: Flow exposes a signed file link on the take's page (`video.currentSrc`); Kling's tiles play
  `blob:` links, and the real file link is in the page's own `projects-assets/batch-status` response
  (`works[].resource.resource`). The agent passes that link to `gen-ingest --url` (section 6), which fetches it.
- the confirmations the operator must click, and the terms finding with its date.

Recipes describe the page by visible labels and roles, not by pixel positions, because both sites change layout with
the pane width. Each recipe carries a "last verified" date; a step that no longer matches the page stops the run and
reports, rather than guessing.

Findings from the spikes to put in the recipes:

| | Flow | Kling |
|---|---|---|
| Free allowance seen | 50 credits/day | 66 credits/day |
| Frames-mode take | 10 credits (cheapest model), 2 takes per request for 20 | 50 (flagship) or 30 (fast) per take |
| Upload that worked | drop event with the files on the media area | first frame: set the slot's file input; last frame: open "Upload" on the last-frame tile and fill the file input it opens |
| Confirmation | image-rights dialog on first upload: operator OK | none seen |
| Wait | about 1.5 min | about 4 min in the free queue |
| Output | 1280x720, 24 fps, 7.9 s, audio track | 1280x720, 24 fps, 5 s, audio track, burned-in watermark |
| Free-plan rights | Google claims no ownership; commercial use on free credits unconfirmed | non-commercial (terms section 4.6, per secondary sources; to be read first-hand) |

### 4. Getting local files into the page

The built-in browser could not reach a local file: no picker access, the page cannot fetch from a local server, and a
synthetic paste does not reach the page. Three routes, in order of preference:

1. **Claude in Chrome's file upload tool** (`mcp__claude-in-chrome__file_upload`), which hands a real local file to a
   page's file input. This needs the platforms signed in in the operator's Chrome instead of the built-in browser.
2. **In-page transfer:** the agent passes the PNG's bytes into the page in chunks and builds the file there. The spike
   measured a 1280x720 keyframe at 9-90 KB as WebP; base64 adds a third. Workable for small keyframes, costly for
   detailed ones.
3. **In-page redraw** (what the spike did): only when the keyframe is simple geometry the agent can redraw exactly.

The builder picks between 1 and 2 after a one-call test of each (rule R08); see Open questions.

### 5. Quota, queue and resume

A local ledger `~/.aos/gen/quota.json` (outside the repo) holds, per platform: credits last seen, cost per take, the
reset rule (daily at a time the page shows, or monthly), and the last quota-reached time. The agent updates it from
what the page shows at each run.

The queue is `gen.json` itself. A run takes `planned` requests in order, tries their platforms in the listed order,
and skips a platform that lacks credits for the request. When every platform a request allows is out of credits, the
request goes `paused-quota`, the agent sends one notification ("flow and kling out of credits; 3 requests waiting;
next reset ..."), and schedules a wake-up for the earliest reset. At the wake-up it reads the pages again before
spending anything.

### 6. Ingest and rights

`aos asset` gets a subcommand:

```
aos asset gen-ingest --film <dir> --id <aNN> (--url <signed file link> | --file <inbox take>) --request <gNN> --platform <p>
                     --plan free --terms-url <url> --terms-read <date> --watermark yes|no --commercial yes|no|unknown
```

It copies the take into the film's media root, measures it, makes the proxy, and writes an `assets.json` row with a
new basis `generated`, plus: platform, plan, terms URL and the date they were read, watermark, commercial permission,
the prompt, the keyframe hashes, and the request id. It charges the take's size to the film's download budget like any
fetch.

The asset gate (`tools/checks/assets.mjs` in the template) learns the new basis:
- `generated` is a known basis; it needs `platform`, `termsUrl`, `termsRead`, `watermark` and `commercial`.
- `sourcing.json` gets `"generated": {"allowed": true, "monetized": false}`. A `generated` row fails the gate when
  `allowed` is not true, or when `monetized` is true and the row's `commercial` is not `yes`.
- A row with `watermark: yes` passes, and `qa/assets.md` lists it for a human check so a watermark is never cropped or
  covered.
- Generated media reach the picture only through `src/lib/media` components by asset id, like every import.

Credits: the film's description lists generated material by platform ("Transition S07 generated with Google Flow").

### 7. Review and the keep decision

Each fetched take gets review sheets (`tools/review-sheets.mts`: frames at 20/50/85 %, plus a strip of the whole
take). The director checks it against R04 (generic look, artifacts, style drift, motion that goes nowhere) and the
film's style lock, and either proposes it for the cut or discards it with a one-line reason in `gen.json`.

Proposed takes go into the next review cut. The operator's verdict on a generated shot is recorded like any verdict
(`aos video verdict`); a rejected take is marked `discarded` with the verdict as the reason, and its request can be
re-queued with a changed prompt.

### 8. Joins

A new tool `tools/gen-trim.mts` measures motion in a take (mean frame-to-frame difference, as done by hand in the
spike) and proposes the trim: drop the still tail after motion falls below a threshold, keep a short hold. The joins
check for seams is a new QA tool (`tools/checks/seams.mjs`, see call 6): no jump frame at either seam of a cut that
touches a generated asset, crossfade lengths recorded. Spike defaults: 4 frames into the take, 10-12 frames out of it; the tool measures, the defaults are a start.

Known generator behaviour to design around: Veo held the end frame still for about 2.5 s and faded the target in
instead of moving into it; Kling moved particles into the target but started its burst abruptly. Prompts should ask
for the motion to resolve into the last frame; the tool trims what remains.

### 9. Operator-run fallback

When a platform cannot be driven (terms forbid it, the page changed, a CAPTCHA loop), the director writes a prompt
sheet instead: per request, the keyframes, the prompt, duration and aspect, and the platform. The operator runs it on
any device and drops the files in the film's `gen-inbox/`; `gen-ingest` takes them from there with the same rights
fields.

### 10. Local lane (later)

A local adapter for open video models on the planned RTX 3090 implements the same request: keyframes in, take out,
ledger row with basis `generated` and `platform: local-<model family>`, no quota, no watermark, license from the model's
own terms. Not built now.

## Files touched

- `agents-home/skills/generate-video/` (new): SKILL.md, `flow.md`, `kling.md`.
- `agents-home/video/assets/asset.mjs` and `lib/` (gen-ingest subcommand, ledger fields) plus tests in
  `agents-home/video/assets/test/`.
- `templates/video/`: `tools/checks/assets.mjs` (+ its test), `tools/keyframes.mts`, `tools/gen-trim.mts`,
  `tools/checks/seams.mjs` (new), `src/lib/media/` (ported from the recent films), `sourcing.json` (generated block), `shots.md` (Source column), `gen.json` (empty plan),
  `AGENTS.md` (the generation stage).
- `agents-home/video/video-rules.md`: a rule for generated material (a new R-number, appended), pointing at this
  design; R03 and R35 cross-reference it.
- `docs/decisions.md`: a dated entry on top.
- `agents-home/skills/tool-catalog`: list the new skill.

## Left to the builder

- Module layout inside `asset.mjs` and the exact field names, as long as the gate rules above hold.
- The motion threshold and hold length in `gen-trim`, from measurement on the two spike takes.
- How the notification and the wake-up are sent (the session's notification and scheduling tools).
- Whether `keyframes.mts` reuses `review-sheets.mts` internals.

## Calls made by the designer (check these)

Settled after the builder check; each can be overridden.

1. **Terms first, before any build step.** Step 0 of the plan reads Flow's and Kling's terms first-hand. The test: if
   the terms forbid automated access, bots or scripts in plain words, that platform is fallback-only (section 9) and
   its recipe is not built; an agent acting in the operator's own signed-in session still counts as automated use for
   this test. If both platforms fail, the build shrinks to keyframes, prompt sheets, ingest, gate and joins.
2. **Resume means the next run picks up the queue, not an unattended run that clicks through.** A scheduled wake-up
   reads the pages and generates only if no dialog, CAPTCHA or new approval stands in the way; otherwise it stops and
   notifies. The download approval is given once per film when the operator approves `gen.json` (it covers every take
   the plan asks for), so a resume run never needs a new download approval.
3. **One budget.** The batch approval is the film's existing download budget (`aos asset budget --approve <MB>
   --by-user`), sized to the plan's takes. Takes are fetched through the asset kit's own fetch path (`fetchHttp`, so the
   cap holds during the transfer), not by a bare curl: `gen-ingest` takes a `--url` as well as a `--file`, and `--file`
   is only for the operator-run fallback inbox.
4. **Flow and Kling both in this build.** Both were spiked and judged equivalent in look; the queue's platform order
   is Flow, then Kling. A third platform is a later, separate addition.
5. **Media components exist.** `src/lib/media` (Clip, Capture, Photo, Model, Environment, GlTransition, SourceTag)
   lives in the recent films (`pauseai-it-spina`, `huggingface-it`) but not in the template. The build ports it into
   `templates/video/src/lib/media` and adds a crossfade-to-neighbour option to Clip if GlTransition does not already
   cover it.
6. **A separate seam check.** `joins.mts` compares camera poses before rendering; seams need pixels after rendering.
   The build adds `tools/checks/seams.mjs` to QA (jump-frame measure at every cut that touches a generated asset)
   and leaves `joins.mts` as it is. Section 8's mention of extending `joins.mts` is replaced by this.
7. **Clips and assets without keyframes are in scope.** The operator asked for assets, scenes and clips, not only
   transitions. Recipes cover text-only and single-reference-frame modes besides frames mode. Because those takes have
   no code anchor, their R04 review is stricter: the other vendor reviews their sheets blind before they are proposed.

## Open questions for the operator

1. Which films count as monetized (channel ads, sponsorship, client work)? This decides whether Kling's free output
   (non-commercial) can be used at all, and whether a row with `commercial: unknown`, Flow's current state, blocks by
   default.
