# Codex critique of the video asset import spec (2026-10-06, codex exec --profile review -m gpt-6-astra, 20,376 tokens)

Reviewed commit 5e2e17b. Verbatim answer below; Claude's response is the revised spec (each change cites the finding).

I’ll read only the three named files and return a bounded critique. I won’t run builds or browse.
exec
"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -Command "Get-Content -LiteralPath 'docs/superpowers/specs/2026-10-06-video-asset-import-design.md','agents-home/video/video-rules.md','templates/video/AGENTS.md'" in C:\Users\marin\OneDrive\Desktop\agentic-os
 succeeded in 876ms:
# Video asset import, reference packs and the consolidated pipeline (design)

Date: 2026-10-06. Status: approved in conversation, awaiting review of this file.
Author: Claude (session 12e91af7). Independent critique: Codex (bounded, before implementation).

## Why

The user, after six films built entirely as code: "the real limitation here in the orchestration is how in the last
runs they built everything from scratch, the pre existing online libraries of assets, examples of the same niche,
references ecc.. ... the edits and video generation must be able to import assets and images, short clips MOST
IMPORTANTLY, to have more variety and grant realism; the same with animation and different transitions."
Then: "the clip taken should be contextual too and maybe even reference other videos, media or material needed for
that specific visualization, not locked and binded to the specific platform".

Every final product must be usable and up to standard for upload: the user will open ad hoc channels for them.
Interactive co-creation with the user is a later topic and out of scope here.

## Decisions taken with the user (2026-10-06)

| Question | Answer |
|---|---|
| Copyright risk for imported clips | Licensed/public-domain material **and** short fair-use excerpts (news, other creators) |
| Free API keys (Pexels, Pixabay, Freesound) | Yes, the user creates them if free; stored with `aos secret` |
| Download approval | One budget per film, approved at the brief gate; over budget asks again |
| Niches | General: reference packs per niche, built on demand; proposed niches are inspiration, no lock-in |
| Design | Approach A (shared asset tool + ledger + gate + components), sourcing by need, not by platform |
| Cleanup | Groups A-D done 2026-10-06 (Recycle Bin, log in `~/.aos/logs/cleanup-2026-10-06.txt`) |

## Goals and non-goals

Goals: (1) any shot can use real material found for its specific idea, from any reachable source, with its rights
recorded and checked; (2) a library of transitions and animation beyond dissolves; (3) per-niche reference packs that
feed the brief and the look; (4) the lessons of six films consolidated into fewer, clearer rules and fixed template
bugs; (5) Claude/Codex work split and quota tracked at every gate, with a token budget on delegated runs.

Non-goals: generic generative imagery or video (still rejected, R03); paid sources; an MCP server for assets
(schemas load on every request; CLI instead); interactive user co-creation; uploading to YouTube.

## 1. Sourcing by need

Each shot in `shots.md` gets two new columns: **need** (what the viewer must see and why, one sentence) and
**source** (`built`, `clip`, `photo`, `capture`, `model`, `lottie`, `mixed`). The search follows the need in this
order, and the director records which step produced the asset:

1. **The subject's own primary material**: the paper's figures, the lab's launch or demo video, the product's real UI,
   the repo, the dataset, the hearing's official recording. Web pages and UIs are captured live (screenshot, scroll
   recording or screen recording with Playwright), not re-drawn.
2. **Other coverage**: news footage, other creators' videos, podcasts, as short fair-use excerpts with commentary.
3. **Open libraries for filler**: stock clips and photos, CC0 3D models, HDRIs, textures, sound effects.
4. **Build it** (the current pipeline), when nothing real shows the idea better.

Platform adapters only help step 3 search. Steps 1-2 take any URL.

## 2. The asset tool (`aos asset`)

One copy for both vendors: Node code in `agents-home/video/assets/` (synced to `~/.agents/video/assets` by
`aos sync`), called through thin `aos asset` wrappers in `aos.psm1` (ASCII, PS 5.1-safe). Commands:

| Command | Does |
|---|---|
| `aos asset search <query> --kind clip\|photo\|model\|hdri\|texture\|sfx [--source s] [--json]` | Candidates from the adapters (id, preview URL, page URL, license, author, duration/size). No download. |
| `aos asset fetch <url\|candidate> --film <name> --basis <basis> --why "<need>" [--in s --out s] [--shot SNN]` | Downloads (yt-dlp for video sites with `--download-sections` for the excerpt, HTTP for files), hashes, stores in the cache, writes the ledger row, counts the budget. |
| `aos asset capture <url> --film <name> --mode shot\|scroll\|record [--seconds n] --why "<need>"` | Playwright capture of a public page or product UI (basis `capture`). |
| `aos asset proxy --film <name>` | Transcodes every used clip once into the film's media root (`public/assets/<id>.mp4`, 1080p30 H.264 CRF 18, GOP 30, audio stripped unless the row keeps it). |
| `aos asset credits --film <name>` | Writes the credits block for `description.md` from the ledger. |
| `aos asset budget --film <name> [--approve <MB>]` | Shows used vs approved; `--approve` records the user's budget (only after the user said so). |

Cache: `~/.aos/assets/objects/<sha256>.<ext>` plus `index.json` (URL, retrieval time, license as read, sha256),
outside OneDrive, deduplicated across films. A fetch that would exceed the film's approved budget stops and asks.

Adapters (search helpers, each tested against recorded responses, one real call when added per R08):

| Adapter | Key | Notes from the 2026-10-06 terms check |
|---|---|---|
| pexels | free key | 200 req/h; no attribution required (credit anyway); no unaltered resale |
| pixabay | free key | 100 req/60 s; cache responses 24 h; no hotlinking; bulk/automated collection prohibited: fetch only chosen items |
| openverse | none | anonymous 20/min, 200/day; `license_type=commercial,modification`; ready attribution string |
| wikimedia | none | identifying User-Agent required; filter out CC-BY-SA and anything not CC0/PD/CC-BY |
| nasa | none | commercial OK without implied endorsement; logos and identifiable people need clearance |
| internet-archive | none | Prelinger is NOT blanket PD: rights read per item |
| polyhaven | none | CC0; unique User-Agent; credit "Powered by Poly Haven" in the credits block |
| ambientcg | none | CC0 textures/HDRIs |
| freesound | free token | search and HQ previews with the token; originals need OAuth2 (deferred); CC0/CC-BY only; SFX can still draw Content ID claims |
| generic | none | any URL: yt-dlp (about 1,800 sites) or HTTP; rights basis declared by the director |

Kenney and Quaternius (CC0 models) and LottieFiles (Lottie Simple License, commercial use) are fetched as generic
URLs with the basis recorded by hand. Secrets are read from the Windows store at call time, never written to files.

## 3. The ledger (`assets.json`) and the gate (`tools/checks/assets.mjs`)

One row per asset used in the film:

```json
{ "id": "a07", "kind": "clip", "need": "the demo the lab showed on launch day", "searchStep": 1,
  "url": "https://...", "page": "https://...", "author": "...", "retrieved": "2026-10-07T10:12:00+02:00",
  "basis": "fair-use", "license": null, "licenseUrl": null, "sha256": "...", "cache": "objects/<sha>.mp4",
  "uses": [{ "shot": "S07", "in": 12.0, "out": 17.5, "audio": "muted", "commentaryLine": "L14" }],
  "credit": "Source: <name>, <date>", "clearance": null, "platformTerms": "youtube-download" }
```

Rights basis, one of: `license` (license id from the allowlist), `public-domain`, `cc0`, `fair-use`, `capture`
(a capture of a public page or product, treated as fair use with commentary), `own` (made by us).

The gate refuses the build and QA when:

- a file under `public/assets/` or a `staticFile("assets/...")` reference in `src/` has no ledger row, or a row's
  file hash does not match;
- a `license` row has a license outside the allowlist: CC0, PD, CC-BY 3.0/4.0, Pexels, Pixabay, MIT, BSD-3,
  Lottie Simple License, Poly Haven/ambientCG/Kenney/Quaternius CC0. Denied: any NC or ND, CC-BY-SA (share-alike
  may reach the whole film), unknown or missing;
- a CC-BY row has no credit text, or the credits block in `description.md` is missing a required credit;
- a `fair-use` or `capture` use is longer than 8 s, the sum of all fair-use/capture time exceeds 10 % of the film,
  original audio is not muted (exception: the audio itself is the subject, at most 5 s, flagged `audioSubject`),
  no narration line (`commentaryLine`) overlaps it, or the shot shows no on-screen source credit;
- a NASA row shows a logo or an identifiable person without `clearance` filled;
- a row's `platformTerms` names a platform the film's brief excludes (e.g. a channel that bans YouTube downloads).

The gate also writes `qa/assets.md` (counts per basis, fair-use seconds and share, sources per search step) and a
**Content ID note** for the delivery: stock and SFX are sometimes wrongly claimed; the ledger is the dispute proof.

## 4. Components and transitions (template `src/lib/media/`, `src/lib/transitions/`)

- `Clip.tsx`: `OffthreadVideo` of a proxy with trim (`uses[].in/out`), the film's grade, optional slow push/pan
  through `motion.ts` (R17 calm curves), and an automatic source tag for fair-use/capture rows.
- `Photo.tsx`: stills with calm pan/zoom and the same grade; `Capture.tsx`: framed browser/UI captures.
- `Model.tsx` / `Environment.tsx`: GLB models and HDRI lighting in react-three-fiber (scanned CC0 props to answer the
  v9 verdict "miniatures", "not recognizable object").
- `Lottie.tsx`: needs `@remotion/lottie` (install with consent and size, same version as `remotion` 4.0.529).
- Transitions: our own implementations of dissolve, push, wipe, zoom-through, whip blur and match cut, plus
  vendored gl-transitions shaders (MIT; one BSD-3 file keeps its notice; one file without a license line is covered
  by the repo MIT) rendered with three.js on the two shot frames. `@remotion/transitions` is not used until its npm
  `UNLICENSED` field is clarified. Remotion is pinned at 4.x: its license changes in 5.0.
- The grade (one LUT-like look per film) applies to every imported pixel so stock matches the design system.

## 5. Reference packs (skill `video-references`)

A shared skill in `agents-home/skills/video-references/`: given a niche or a film's topic, find 3-5 strong channels
(by recent views and craft), watch 2 videos each in the built-in browser without downloading (frame sheets sampled from
the page's video element, the method of `alignment-now/docs/reference-study.md`), and write per beat: cut rate,
b-roll share, kinds of imported material, overlays, transitions, sound. Output: `agents-home/video/refs/<niche>.md`
(grows across films, dated) and the film's `refs.md` choosing what to borrow and what not to copy. Frame sheets stay
in `~/.aos/refs-cache/`, never in a repo. No niche is built in; the brief picks.

## 6. Pipeline changes

- `brief.md` gains **Sourcing**: the channel's policy (fair use allowed? YouTube downloads allowed?), the reference
  pack, the planned sources and the download budget the user approves (`aos asset budget --approve`).
- `shots.md` gains **need** and **source**; `rubric.md` gains "imported material shows this line's specific idea
  (a generic clip fails)" and "a first-time viewer recognises every object and term" (retro 45).
- R03/R04 are rewritten: generic *generated* imagery stays rejected; imported real material is allowed when it carries
  its line and is graded into the design system. Recorded as a new dated entry in `docs/decisions.md`.
- `build.sh` and `qa.sh` call the asset gate; `package-outputs.mts` adds the credits and the Content ID note.

## 7. Consolidation

- Rules: regroup R01-R34 by stage (brief, look, structure, production, QA, delivery, orchestration) with ids kept;
  merge duplicates in text only, never renumber; add rules from retro 39-46 (three adjacent frames where two boxes
  meet; audience-level reviewer questions; `git archive` instead of `git stash -u` on OneDrive; sealed-input lock).
- Template bugs found today: copied projects keep a hard-coded media-root fallback to the old film
  (`alignment-now-it/tools/*.sh` default to `~/.aos/video/alignment-now`); a literal `~/.aos/video/{{name}}` folder
  was created by an unsubstituted placeholder. Both get a failing test first, then a fix (fallback derived from the
  project folder name; placeholder substitution checked).
- Memory: one consolidation pass (merge the four video-orchestration notes, drop superseded facts).
- Remaining cleanup: `~/.aos/video/alignment-now/renders` (16 GB) after the Italian session ends; the 24 kept
  worktrees (plus the Italian session's two) listed in the cleanup log for the user to decide.

## 8. Coordination and quota

- `aos delegate --max-input <tokens>`: reads Codex's own `token_count` events from its rollout log while it runs and
  stops a run over budget (today a delegate burned 3.9 M input tokens in 29 min and failed). Default budget per task
  kind, written in the receipt.
- Every delegate task file must list the exact files to read and the one command that proves done; the delegate
  refuses a task file without them.
- At every gate (brief, look, hero, production batch, final): both vendors' windows (`aos capacity`), the split
  (who builds what until when) and the next reset written in an `aos note` and the film's `HANDOFF.md`;
  `aos video preflight` prints this as a checklist step.

## Work split for building this (both windows read 2026-10-06 19:05)

| Phase | Claude | Codex |
|---|---|---|
| Now (Codex 19 % until about 20:31) | spec, consolidation, template bug tests | one bounded critique of this spec |
| After Codex's reset | Remotion components, transitions, reference-pack skill, rules text | ledger gate and adapters test-first (Claude writes the failing fair-use/license tests, Codex the code, per split authorship), `--max-input` |
| Each merge | review Codex's diff and tests | review Claude's diff (bounded) |

## Testing

- Adapters: recorded HTTP fixtures, never the network in tests (`tests/` and `node --test`); one real call per source
  when added, recorded in the plan.
- Gate: every refusal above has a test seen failing first; fixtures under `templates/video/tools/checks/fixtures/`.
- `aos asset` wrappers: Pester tests in `tests/aos.Tests.ps1` with `$TestDrive`, both shells; `aos test` green.
- End to end: one scaffolded film fetches one clip per basis (license, cc0, fair-use excerpt, capture), proxies,
  renders a 10 s test composition with two transitions, and passes the gate; QA writes `qa/assets.md`.

## Open items

- Freesound originals (OAuth2) deferred; previews are the default.
- Whether a CC-BY-SA still forces the whole film to CC-BY-SA is a legal question; denied by default.
- YouTube's terms forbid downloading outside its features even for fair use: the brief decides per channel.
# Video rules (read at every stage; `aos video preflight` lists them; retrospectives add new ids at the end)
- R01 [manual] Never start production before the definition of good, a style frame and an animated hero shot exist and have been reviewed (by the user when they gate, by the director at playback speed when they do not).  (from agi-race 2026-09-29)
- R02 [manual] No slideshow pacing: every shot has motion inside it and a purpose; cuts land on the beat.  (from agi-race 2026-09-29)
- R03 [manual] No generic generated imagery as the default: generative engines are opt-in and must pass the anti-slop gate.  (from agi-race 2026-09-29)
- R04 [manual] Anti-slop gate: reject generic stock look, visuals that do not carry their line, AI artifacts, style drift, motion that goes nowhere.  (from agi-race 2026-09-29)
- R05 [manual] The voice is part of the style lock: send a short audition of 3-4 voices with the style frame, because no agent can judge a voice by ear; never ship a voice the user has not heard without saying so.  (from agi-race-2 2026-10-01)
- R06 [manual] Freeze line slots in beats once picture work starts; a new voice must fit the slots, not move the cuts.  (from agi-race-2 2026-10-01)
- R07 [manual] Review every delegated shot on a contact sheet (first, middle, last frame) before merging its look into the film; a passing verify only proves it renders.  (from agi-race-2 2026-10-01)
- R08 [manual] A tool or service is tested with one real call when it is added; a connector that needs credits is a paid dependency.  (from agi-race-2 2026-10-01)
- R09 [manual] Research: open the page for every claim in the script; search-result summaries are leads, not sources.  (from agi-race-2 2026-10-01)
- R10 [manual] Validate media roots before any write and keep each version's rendered public assets separate; sharing a source or module junction must not share writable output.  (from alignment v2 2026-10-02)
- R11 [manual] Run frozen-frame checks on the assembled timeline as well as suspect clips: a transition's held destination plus the following shot's quiet opening can fail across the cut. Never waive the detector for an unintended hold.  (from alignment v2 2026-10-02)
- R12 [manual] Transition source scenes must omit captions that would shrink or be wiped into fragments; inspect first, middle and last transition frames at full resolution.  (from alignment v2 2026-10-02)
- R13 [manual] Authored asset files are only a starting point for craft. Check silhouette, surface, articulated contact, readable framing and visual meaning in the rendered result.  (from alignment v2 2026-10-02)
- R14 [manual] Distinguish reviewer evidence: a midpoint cannot establish that an answer never appears, a contact sheet cannot establish playback or sound, and unread sources cannot establish traceability. Preserve each independent verdict and its unknowns.  (from alignment v2 2026-10-02)
- R15 [manual] Set PYTHONUTF8=1 and PYTHONIOENCODING=utf-8 for media CLIs on Windows. Treat a transcript sentence over a verified silent voice tail as a recognizer error, not additional narration.  (from alignment v2 2026-10-02)
- R16 [manual] Serialize verification runs that share a bundle folder. Parallel inspection is safe; rebundling while another render reads that folder is not.  (from alignment v2 2026-10-02)
- R17 [check: motion] Motion is calm: soft in-and-out curves (no expo-out or back-out), travelling moves of at least 0.6 s, shots of 5-10 s joined by dissolves or match cuts; the motion check flags snaps in the export and expo curves in the source.  (from the alignment v1 and v2 verdicts, "too-snappy animations", 2026-10-02)
- R18 [manual] Not shapes: one medium per film unless the brief argues otherwise (mixed media read as demos); characters large in frame and acting (eyes, lids, hands, follow-through); sets dense with props, light and texture (coloured ink lines, cel shadow, grain).  (from the alignment v1 and v2 verdicts, "still too shape-like and simple", 2026-10-02)
- R19 [manual] Easy to follow: one idea per line in everyday words, cases counted aloud, the picture shows the idea before the words name it, few words on screen.  (from the alignment-3 brief 2026-10-02)
- R20 [manual] Close the loop: read PREFLIGHT.md before the brief; record each stage's minutes with `aos video log` and every user verdict verbatim with `aos video verdict`; the retrospective adds new rules here, as check rules with a script in tools/checks when a script can catch it.  (from alignment-3 2026-10-02)
- R21 [manual] nar picks are hints: keep the call_id and the candidates, and send nar_feedback only when the user actually compares those candidates; a verdict on the finished film is not a label for an earlier choice.  (from the alignment-3 plan critique by Codex 2026-10-02)
- R22 [check: input-manifest] QA must bind the exact MP4 and captions to unchanged picture, public/audio assets, resolved fonts, config and runtime inputs, and reject mismatches before decoding or proxy rendering. The renderer src junction must resolve to the declared checkout.  (from the mixed alignment-3 export/proxy run and AGI/ASI guard regressions 2026-10-03)
- R23 [manual] Dissolves join identical camera poses held throughout the overlap; cuts are exact match cuts or clear reframes. Run tools/checks/joins.mts before rendering and QA; shotCamera rejects non-finite, malformed or unordered keys. Camera drift and lighting use the film frame across a dissolve.  (from the AGI/ASI camera join and black-frame fixes 2026-10-03)
- R24 [check: screen-text] Every authored on-screen string has a reviewed claims.json screen entry; use literal text properties/attributes or JSX children in authored shot/library files. Keep forwarding helpers free of authored words. Coverage is mechanical; truth, clipping and overlapping text require independent source/frame review.  (from the AGI/ASI screen ledger 2026-10-03)
- R25 [manual] Word-timed picture and effects share cue-core; measure the existing local voice WAVs and record words.sha256.json. Refuse a changed voice before overwriting any stems. Use BEAT/FPS for the soundtrack grid and AOS_VIDEO_MEDIA_ROOT for every writable media tool, with private verifier bundles.  (from the AGI/ASI timing/private-root fixes 2026-10-03)
- R26 [manual] A build is sealed: never edit a hashed input, a script it runs (bash reads scripts while it runs) or the checkout during tools/build.sh and the QA that follows. Work that must continue (reviews, docs, the next brief) happens outside the hashed tree, or waits.  (from the AGI/ASI v1 build that died on an edited build.sh, 2026-10-03)
- R27 [check: currency] Fast-moving topics need a currency gate before the script: a dated research brief from primary pages (source date, retrieval date and version such as arXiv vN), items tagged fact, measurement, opinion, forecast or contested, "as of" on screen, and every item re-verified on export day. A source's version is part of the citation: the same URL gave a different level name two years apart.  (from the v4 "old data" verdict and the Morris et al. 2023/2025 finding, 2026-10-03) Gate (build and QA refuse a film without currency.json unless qa.env declares CURRENCY=none for a timeless topic): tools/checks/currency.mjs refuses an empty ledger, a missing field, a stale retrieval, a too-old source, an unmapped factual/quoted claim or a contested item without a counter-voice from another camp; on export day tools/reverify.mjs re-opens every page and checks its anchor (browser-only pages are confirmed by hand), and both build and QA pass --claims and --export, which requires a successful re-verification dated on the actual local export day. The input manifest binds currency.json before rendering; changing it after sealing requires a rebuild.
- R28 [manual] Many visualization practices in one film are allowed only under a design system (palette, type, grid, recurring motif, transition and sound language) proven by a hero that holds two practices. Choose a practice per idea type from a look lab: the same 4-5 beats rendered in 3 practices each at quarter scale, scored blind on frames by both vendors. This overrides R18's "one medium" only when the brief asks for variety.  (from the v4 "stiff, not engaging" verdict, 2026-10-03)
- R29 [check: pacing] Engagement is measured, not assumed: report shots per minute, the longest hold with no visual change, practice changes, the share of on-screen words not in the narration and time to the first hook, and compare with the last film. Dynamism comes from cut rhythm, variety, acting and sound; R17's calm easing stays.  (from the v4 verdict, 2026-10-03) Report: tools/checks/pacing.mjs (QA fails if it cannot write qa/pacing.md; set PACING_BASELINE to the last film's pacing.json for the comparison; the numbers are reported, reviewers judge). alignment-now vs v4: 6.9 vs 2.3 shots/min, 9 practices.
- R30 [manual] Independent reviews get images, early and at every gate: tools/review-sheets.mts makes the shot sheets (20/50/85 % of each shot) and the dissolve sheet; hand them to the other vendor with codex exec -i or an equivalent. A late review found what three own passes missed (source version drift, an unexplained mechanism). State what frames cannot establish (R14).  (from the AGI/ASI v3 REVISE review, 2026-10-03)
- R31 [manual] Every bug found on a render gets a guard at its source and, where code can detect it, a test that failed first. In the AGI/ASI run: a missing re-export became a NaN camera and a black frame (now a throw on non-finite or unordered camera keys), overlapping headlines (a throw), a stale voice hash (a build refusal, mutation-tested), an object popping into frame (found by the motion check, fixed in the object, no code guard). Fix the cause, not the frame; waive a motion hit only after full-size crops of its tile.  (from the AGI/ASI renders, 2026-10-03)
- R32 [manual] Spend the machine, not the clock: keep the computer awake for long jobs, run reviews and docs (outside the hashed tree, R26) while a render runs, render review cuts at quarter scale, render only what changed, and log each stage's minutes. Measured once on this laptop, 180 heavy 3D frames (S12 of the AGI/ASI film) took 24-27 s at render concurrency 2, 3 and 4 and 29-59 s at 6-10 on an idle machine: wider did not help there, so keep the default 4 unless a re-measure on the new film says otherwise. A three-hour idle gap and four 15-minute full renders were the largest avoidable costs of the AGI/ASI run.  (from the AGI/ASI stage minutes and render timings, 2026-10-03) Render only what changed: tools/render-cached.sh (default in build.sh) keys each cut-to-cut segment on its transitive src/ imports plus the input manifest environment.
- R33 [manual] Shell hygiene on this machine: ffmpeg in a while-read loop needs -nostdin; run every media tool and the manifest verifier with the same AOS_VIDEO_MEDIA_ROOT; commit the config/places.json entry that aos video new writes (it dirties the shared checkout and blocks other sessions); never share one checkout between a builder and a reviewer session.  (from the AGI/ASI run, 2026-10-03)
- R34 [manual] Capacity is planned, not hoped for (`aos capacity` holds each vendor's last known window; `aos capacity set <vendor> <pct>` records what the usage card shows, a quota error in a delegate receipt records the reset time, and `aos delegate` warns before handing work to a limited or low vendor): at the start and at every gate read both vendors' limits (Claude usage, Codex's reset time from its last error or receipt), write the split (who builds what until when) in HANDOFF.md and an aos note, and when one vendor is limited the other takes the next batch at once in its own worktree, new files only. Never idle waiting for a reset; keep delegated runs lean (quarter-size stills, no repeated full renders) and give a detached delegate a wrapper limit above its own timeout.  (from alignment-now 2026-10-04: Codex hit its limit three times, Claude waited for it, and the user had to step in: "they didnt communicatre and decided their usage allocation")
# {{name}} (video)

Instructions for Claude Code and Codex; `CLAUDE.md` imports this file. Made with `aos video new {{name}}`.
Read `PREFLIGHT.md` first (the rules with their ids, the user's past verdicts on this kind of video, how long each
stage took before); refresh it with `aos video preflight {{name}}`. Read `~/.agents/video/video-rules.md` before
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
- Soundtrack stems: `node --no-warnings tools/audio.mts`; full build: `bash tools/build.sh v1`
- QA: `bash tools/qa.sh exports/{{name}}.mp4 exports/{{name}}.srt` (length from `qa.env`; includes the motion
  check on a texture-free proxy, report `qa/motion.md`), then `node tools/screen.mjs` (on-screen text)
- Currency gate (R27): `node tools/checks/currency.mjs currency.json --claims claims.json`; export day: `node tools/reverify.mjs currency.json --browser-ok <ids> --evidence research/reverify-<date> --write` (each source gets a proof file: URL, time, SHA-256 of the page, anchor excerpt; a browser row needs one saved from the browser), then rebuild and QA on that local day. Build and QA pass `--export`; the dated ledger is part of the input manifest.
- Pacing report (R29): `node tools/checks/pacing.mjs <film.mp4> --shots src/data/shots.json --claims claims.json --lines src/data/lines.json --out qa/pacing`
- Render cache (R32, default in build.sh): `bash tools/render-cached.sh`; `AOS_RENDER_CACHE=0` renders Main whole; tests `node --test tools/cache/cache.test.mjs`
- Motion check alone: `node --no-warnings tools/checks/motion.mjs <proxy.mp4>`; its tests: `node --test tools/checks/`
- Input provenance (R22): build snapshots inputs before rendering, checks them again afterward and seals the exact
  MP4/SRT hashes. QA rejects changed inputs or artifacts before decoding/proxy work. Rebuild after a mismatch.
  `node --test tools/checks/input-manifest.test.mjs` exercises the guard. An isolated caller may select its private
  runner for this check with `AOS_VIDEO_MEDIA_ROOT`; this does not relocate the other build scripts automatically.

## The learning loop (rule R20)

- After each stage: `aos video log {{name}} <brief|look|structure|production|qa|delivery|retro|revision> <minutes> [note]`.
- Every verdict the user gives, verbatim: `aos video verdict {{name}} <their words>`.
- Motion: every move goes through `src/lib/motion.ts` (soft in-out curves, moves >= MIN_MOVE_FRAMES, `settle`,
  `breathe`); expo-out and back-out curves fail the motion check. Shots are long and dissolve (`plan.ts`).
- nar (rule R21): when choosing among style frames, `nar_choose` is a second signal; keep its call_id and the
  candidates in `retro.md`, and send `nar_feedback` only if the user compares those same candidates.
- The retrospective adds rules to `~/.agents/video/video-rules.md` with the next free id, as `[check: x]` with a
  script in `tools/checks/x.mjs` called from `tools/qa.sh` whenever a script can catch the failure.

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

hook: PostToolUse
hook: PostToolUse Completed
