# Video asset import, reference packs and the consolidated pipeline (design)

Date: 2026-10-06. Status: approved in conversation; revised after Codex critique (REVISE, 8 findings, all taken); awaiting the user's review of this file.
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
| `aos asset fetch <url\|candidate> --film <name> --basis <basis> --acquisition <a> --why "<need>" [--source-in s --source-out s]` | Downloads (yt-dlp for video sites with `--download-sections` for the excerpt, HTTP for files), measures the real file with ffprobe, hashes it, stores it in the cache, writes the ledger row, charges the budget. |
| `aos asset capture <url> --film <name> --mode shot\|scroll\|record [--seconds n] --why "<need>"` | Playwright capture of a public page or product UI (basis `capture`). |
| `aos asset proxy --film <name>` | Derives, under `$AOS_VIDEO_MEDIA_ROOT/app/public/assets/`, one silent video proxy per asset (`<id>.mp4`, 1080p30 H.264 CRF 18, GOP 30) and, only for uses that keep sound, a separate audio derivative (`<id>.<use>.wav`) that `audio.mts` mixes. Records each derivative's hash and the exact ffmpeg settings in the ledger. |
| `aos asset registry --film <name>` | Writes `src/data/assets.ts` (asset id -> derivative path) from the ledger; components take an asset id, never a path. |
| `aos asset credits --film <name>` | Writes the credits block for `description.md` from the ledger. |
| `aos asset budget --film <name> [--approve <MB>]` | Shows used vs approved; `--approve` records the user's budget (only after the user said so). |

Cache: `~/.aos/assets/objects/<sha256>.<ext>` plus `index.json` (URL, retrieval time, license as read, sha256),
outside OneDrive, deduplicated across films.

Budget (Codex finding 5): the budget counts **network bytes received** for the film, including failed and partial
transfers and retries; a cache hit costs nothing. Fetches for one film are serialized by a lock file in its media
root. Before a transfer the remaining budget is reserved; the transfer streams with a hard byte cap (HTTP: abort at
the cap; yt-dlp: `--max-filesize` plus a watchdog on the partial file), and an unknown size is allowed only under
that cap. Retained disk (cache, captures, proxies) is reported separately by `aos asset budget`, not charged to the
download budget. Over budget: the command stops and prints what it needs; only the user can raise it.

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
  "basis": "fair-use", "license": null, "licenseUrl": null,
  "acquisition": "download-tool", "platform": "youtube",
  "rightsEvidence": "research/rights/a07.json",
  "source": { "in": 12.0, "out": 20.0 },
  "media": { "sha256": "...", "cache": "objects/<sha>.mp4", "start": 12.0, "duration": 8.03 },
  "derivatives": [{ "path": "assets/a07.mp4", "sha256": "...", "ffmpeg": "-c:v libx264 -crf 18 -g 30 -an ..." }],
  "uses": [{ "use": "u1", "shot": "S07", "shotFrom": 30, "mediaFrom": 0.5, "mediaTo": 6.0, "audio": "muted",
             "rationale": "we show the moment the agent edits its own test; the narration explains why it matters" }],
  "credit": "Source: <name>, <date>", "clearance": null }
```

Three time coordinates, never mixed (Codex finding 4): `source.in/out` are seconds in the original work;
`media.start/duration` describe the downloaded file as measured by ffprobe (local 0 = `media.start` in source time);
`uses[].mediaFrom/mediaTo` are seconds inside the downloaded file, and `shot` + `shotFrom` (frames) place the use in
the film. `Clip` trims in media coordinates only, so an excerpt is never trimmed twice. The film placement in seconds
is computed by the gate from `src/data/plan.ts` (shot start + `shotFrom`).

Rights basis, one of: `license` (license id from the allowlist), `public-domain`, `cc0`, `fair-use`, `capture`
(a capture of a public page or product: it does not establish permission and follows the fair-use rules), `own`.
**Acquisition** is a separate decision (Codex finding 1): `api`, `direct-file`, `platform-feature` or
`download-tool`, plus the `platform`. The brief's Sourcing section lists the acquisitions the channel accepts per
platform (default: `download-tool` refused for YouTube, because its terms forbid it); the gate refuses any row
outside that list. `rightsEvidence` points to a file with the license page URL, retrieval time, a hash of the page
text and the license excerpt (the reverify proof format of R27).

Coverage (Codex finding 2): components accept only an asset id from `src/data/assets.ts`; the gate refuses any
`staticFile(`, `http(s)://` media URL, `useGLTF(` path or Lottie `src` literal outside that registry, any dynamic
path expression in those calls, a `.gltf` with external resources (models must be self-contained `.glb`) and a
Lottie file with external image assets.

The gate refuses the build and QA when:

- a file under `public/assets/` has no ledger row, or the cached media or a derivative does not match its hash;
- a `license` row has a license outside the allowlist: CC0, PD, CC-BY 3.0/4.0, Pexels, Pixabay, MIT, BSD-3,
  Lottie Simple License, Poly Haven/ambientCG/Kenney/Quaternius CC0. Denied: any NC or ND, CC-BY-SA (share-alike
  may reach the whole film), unknown or missing;
- a CC-BY row has no credit text, or the credits block in `description.md` is missing a required credit;
- a `fair-use` or `capture` use is longer than 8 s, the sum of all fair-use/capture time exceeds 10 % of the film,
  sound is kept (exception: the audio itself is the subject, at most 5 s, `audio: "subject"`, listed for the user),
  no narration word interval (from `words.json`) overlaps at least half of its film placement, the `rationale` is
  empty, or the use has no generated source tag;
- a NASA row shows a logo or an identifiable person without `clearance` filled;
- a row's acquisition/platform pair is not accepted by the brief, or `rightsEvidence` is missing.

The gate checks policy, not law: its report says "asset policy checks passed", never "fair use". What stays a human
check, listed in the review sheet for both vendors and the user: whether the narration actually comments on the
excerpt, whether the credit is legible, whether the excerpt takes more than it needs.

The gate also writes `qa/assets.md` (counts per basis, fair-use seconds and share, sources per search step) and a
**Content ID note** for the delivery: stock and SFX are sometimes wrongly claimed; the ledger and rights evidence are
supporting evidence for a dispute, not proof.

Sealing (Codex finding 3, R22/R26): `assets.json`, every `rightsEvidence` file, `src/data/assets.ts` and every
derivative hash enter the input manifest; build and QA refuse a change after sealing. All writable paths resolve
through `AOS_VIDEO_MEDIA_ROOT` (R10, R25); the cache is read-only to builds.

## 4. Components and transitions (template `src/lib/media/`, `src/lib/transitions/`)

- `Clip.tsx`: `<Clip asset="a07" use="u1">`, an `OffthreadVideo` of the silent proxy trimmed in media coordinates,
  the film's grade, optional slow push/pan through `motion.ts` (R17 calm curves), and an automatic source tag for
  fair-use/capture rows. The tag text comes from the ledger `credit`; `aos asset registry` also writes those strings
  as generated `screen` entries in `claims.json` (kind `label`, source the ledger row), so R24 coverage stays
  mechanical while legibility stays a frame review.
- `Photo.tsx`: stills with calm pan/zoom and the same grade; `Capture.tsx`: framed browser/UI captures.
- `Model.tsx` / `Environment.tsx`: GLB models and HDRI lighting in react-three-fiber (scanned CC0 props to answer the
  v9 verdict "miniatures", "not recognizable object").
- `Lottie.tsx`: needs `@remotion/lottie` (install with consent and size, same version as `remotion` 4.0.529).
- Transitions: our own implementations of dissolve, push, wipe, zoom-through, whip blur and match cut, plus
  vendored gl-transitions shaders (MIT; one BSD-3 file keeps its notice; one file without a license line is covered
  by the repo MIT) rendered with three.js on the two shot frames. `@remotion/transitions` is not used until its npm
  `UNLICENSED` field is clarified. Remotion is pinned at 4.x: its license changes in 5.0.
- The grade (one LUT-like look per film) applies to every imported pixel so stock matches the design system.

Reconciling the rules (Codex finding 6): R17 still governs motion inside a shot and the calm curves of every move.
Dissolves and match cuts stay the default join; push, wipe, zoom-through and whip blur are allowed only as the film's
declared transition language in `style.md` (part of the R28 design system) and must appear in the hero. Imported
real material counts as one visualization practice under R28: a film that uses it shows it in the hero next to a
built practice, and R18's "one medium" applies unless the brief argues for that mix.

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

- `aos delegate --max-input <tokens>`, a **best-effort** limit, not a hard ceiling (Codex finding 7). The delegate
  binds to the one Codex rollout file created after its start whose `cwd` is its worktree, reads the cumulative
  `input_tokens` of its `token_count` events (cached input included; revised 2026-10-06 after measuring a run of 3.5 M input, 3.4 M cached, that took 35 % of Codex's 5 h window: a non-cached budget would not have stopped it; cached tokens are still recorded separately), and when the count
  passes the budget kills the whole process tree (`taskkill /T /F`) and writes a receipt with the last count, the
  overshoot and outcome `over-budget`. Missing or delayed events: after `--idle` minutes without an event the
  existing no-progress kill applies; the receipt says the budget was unobserved. Descendant runs started by the
  delegate are not visible in that file and are named as a limit in the receipt. Today's failed delegate (3.9 M
  input tokens in 29 min) is the calibration case; default budgets per task kind come from Codex's own estimates.
- Every delegate task file must list the exact files to read and the one command that proves done; the delegate
  refuses a task file without them.
- At every gate (brief, look, hero, production batch, final): both vendors' windows (`aos capacity`), the split
  (who builds what until when) and the next reset written in an `aos note` and the film's `HANDOFF.md`;
  `aos video preflight` prints this as a checklist step.

## Work split for building this (windows read 2026-10-06 19:05; Codex critique done 19:50 with 20 K tokens)

| Phase | Claude (5 h 94 % left, week 51 % left) | Codex (5 h ~19 % until ~20:31, week 72 % left) |
|---|---|---|
| Now | spec revision, implementation plan, failing gate fixtures, template bug tests | idle (window kept for one bounded plan check) |
| After Codex's reset | Remotion components, transitions, reference-pack skill, rules consolidation | ledger gate against Claude's failing fixtures (est. 40-70 K), adapters behind one interface (60-100 K), `--max-input` (20-35 K) |
| Each merge | reads Codex's diff and runs the tests on the host | bounded review of Claude's diff |

Codex's estimates sum to 120-205 K tokens, inside one 5-hour window by its own estimate; each task goes through
`aos delegate` in its own worktree with `--idle` and (once built) `--max-input`, and the split is re-read at each merge.

## Testing

- Adapters: recorded HTTP fixtures, never the network in tests (`tests/` and `node --test`); one real call per source
  when added, recorded in the plan.
- Gate (Codex finding 8): fixtures on a 60 s film timeline (`plan.ts`, `words.json`, `assets.json`). One valid
  fixture holds every basis: `license` (Pexels row), `cc0`, `public-domain`, `own`, a 5 s `fair-use` excerpt under a
  narration interval and a 1 s `capture` (6 s = 10 % of 60 s, at the cap). Refusal fixtures each mutate one protected
  field of the valid one (license id, hash, credit, excerpt 8.1 s, total 6.1 s, sound kept, no overlapping words,
  empty rationale, missing evidence, refused acquisition, dynamic `staticFile` path, external `.gltf` resource) and
  must fail against the production gate code; each is seen failing before the gate code that catches it exists.
- `aos asset` wrappers: Pester tests in `tests/aos.Tests.ps1` with `$TestDrive`, both shells; `aos test` green.
- `--max-input`: tests with a fake rollout file for over budget, delayed events, missing events, a rollout from
  another worktree (ignored) and cancellation (process tree gone, receipt written).
- End to end: one scaffolded 60 s test film fetches one real asset per basis within the caps above, proxies, renders
  with two transitions and passes the gate; QA writes `qa/assets.md`.

## Open items

- Freesound originals (OAuth2) deferred; previews are the default.
- Whether a CC-BY-SA still forces the whole film to CC-BY-SA is a legal question; denied by default.
- YouTube's terms forbid downloading outside its features even for fair use: the brief decides per channel.
