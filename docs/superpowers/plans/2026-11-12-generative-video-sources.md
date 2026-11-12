# Generated Video Sources (first step) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a film take a generated video take into its asset ledger with its rights recorded, and give every session a skill that repeats the Flow and Kling procedures.

**Architecture:** No new command. `aos asset fetch` learns the basis `generated` and four extra fields; the template's asset gate learns the basis and two `sourcing.json` switches; a new shared skill holds the procedure and one recipe per platform. Everything else in the spec stays deferred.

**Tech Stack:** Node ESM (`node:test`), the existing asset kit (`agents-home/video/assets`), the video template's checks, Markdown skills, Pester via `aos test`.

**Spec:** `docs/superpowers/specs/2026-11-12-generative-video-sources-design.md`

## Global Constraints

- Branch `claude/generative-sources-spec`, worktree `~/.aos/worktrees/gen-sources-spec`. Do not touch the main checkout.
- No model names in the repo: recipes say "the cheapest model with frames mode" / "the flagship model".
- `aos.psm1` and `bootstrap.ps1` are not changed by this plan.
- Run `aos test` (both shells) before the final commit; `aos` may not be on PATH in agent shells, so from the worktree
  root run `pwsh -NoProfile -Command "Import-Module ./aos.psm1 -Force; aos test"`. Node suites run alone with
  `node --no-warnings --test <file>`.
- Every platform fact in a recipe is either "observed 2026-11-12" or marked "secondhand, check first-hand".
- Never remove, crop or cover a watermark; no account tracking or switching (spec, Rules).
- The skill is linked into `~/.claude` by `aos sync`: get a Codex review (`second-opinion` skill) before merging. Do not run `aos sync` in this plan.

## Review Focus

- A generated fetch missing any of the four fields must fail before any download or budget charge (test in Task 1).
- `--commercial` outside `yes|no|unknown` or `--terms-read` not a date must be refused (Task 1).
- A film whose `sourcing.json` has no `generated` block (every existing film) must refuse a generated row with a message that says how to allow it (Task 2).
- A monetized film must refuse `commercial: unknown` (Flow today), not only `no` (Task 2).
- A watermarked row must appear by id in `qa/assets.md` human checks; an unwatermarked ledger must not add the line (Task 2).

---

### Task 1: `aos asset fetch --basis generated`

**Files:**
- Modify: `agents-home/video/assets/asset.mjs` (`fetchAsset`, `main` options and `fetch` case, header usage comment)
- Test: `agents-home/video/assets/test/core.test.mjs`

**Interfaces:**
- Produces: a ledger row with `basis: 'generated'`, `licenseUrl` = the platform's terms page, `platform` = platform id (`flow`, `kling`), `acquisition: 'platform-feature'`, and
  `generated: {termsRead: 'YYYY-MM-DD', watermark: boolean, commercial: 'yes'|'no'|'unknown', prompt: string}`. Non-generated rows get no `generated` key.
- CLI flags: `--terms-read <date>`, `--watermark yes|no`, `--commercial yes|no|unknown`, `--prompt "<text>"`; the terms page is passed as the existing `--license-url`.

- [ ] **Step 1: Write the failing tests** in `core.test.mjs`, using the file's `film()` and `server()` helpers and `fetchPage: async () => 'terms page'`:
  - `test('fetchAsset: a generated take records platform, terms and the generated block')`: opts `{url, id: 'a07', basis: 'generated', licenseUrl: 'https://example.org/terms', acquisition: 'platform-feature', platform: 'flow', why: 'transition S07', kind: 'clip', measure: false, termsRead: '2026-11-12', watermark: false, commercial: 'unknown', prompt: 'Locked-off camera'}`; assert the row's `generated` deep-equals `{termsRead: '2026-11-12', watermark: false, commercial: 'unknown', prompt: 'Locked-off camera'}`, `licenseUrl === 'https://example.org/terms'`, and `research/rights/a07.json` exists.
  - `test('fetchAsset: a generated take without its fields is refused before any transfer')`: same opts without `prompt`; `assert.rejects(..., /a07: generated needs --license-url, --terms-read, --watermark, --commercial and --prompt/)`; assert `budgetFor(d).usedBytes === 0` and the ledger is empty.
  - `test('fetchAsset: a generated take with a bad commercial value or date is refused')`: `commercial: 'maybe'` rejects with `/a07: --commercial must be yes, no or unknown/`; `termsRead: 'last week'` rejects with `/a07: --terms-read must be a date \(YYYY-MM-DD\)/`.
  - `test('fetchAsset: other bases get no generated block')`: the existing cc0 opts; assert `!('generated' in row)`.

- [ ] **Step 2: Run to verify they fail**

Run: `node --no-warnings --test agents-home/video/assets/test/core.test.mjs`
Expected: the four new tests FAIL (no `generated` key / no rejection); existing tests pass.

- [ ] **Step 3: Implement in `asset.mjs`**
  - A pure `generatedFields(opts) -> {termsRead, watermark, commercial, prompt} | null` (null when `opts.basis !== 'generated'`), throwing the three messages above; call it at the top of `fetchAsset`, before the lock and before any budget call.
  - Spread `...(gen ? {generated: gen} : {})` into the `addRow` object.
  - `main`: add the four options (`'terms-read'`, `watermark`, `commercial`, `prompt` as strings); in `case 'fetch'` pass `termsRead`, `watermark: v.watermark === undefined ? undefined : v.watermark === 'yes'`, `commercial`, `prompt`. Add one usage line to the header comment.

- [ ] **Step 4: Run to verify they pass**

Run: `node --no-warnings --test agents-home/video/assets/test/core.test.mjs`
Expected: all PASS (tests needing ffmpeg may skip).

- [ ] **Step 5: Commit**

```bash
git add agents-home/video/assets/asset.mjs agents-home/video/assets/test/core.test.mjs
git commit -m "asset kit: fetch takes a generated basis with terms, watermark, commercial and prompt"
```

### Task 2: The asset gate knows `generated`

**Files:**
- Modify: `templates/video/tools/checks/assets.mjs` (`BASES`, row loop, returned report, `reportText`)
- Modify: `templates/video/sourcing.json`, `templates/video/shots.md` (source list), `templates/video/AGENTS.md` (one line)
- Test: `templates/video/tools/checks/assets.test.mjs`, `templates/video/tools/checks/template-text.test.mjs`

**Interfaces:**
- Consumes: the row shape from Task 1.
- Produces: `sourcing.json` key `"generated": {"allowed": true, "monetized": false}`; `report.watermarked: string[]` (ids).

- [ ] **Step 1: Write the failing tests** in `assets.test.mjs`. Helper in the test file: `gen(l, d, extra)` turns fixture row `a01` into `{...a01, basis: 'generated', license: null, platform: 'flow', acquisition: 'platform-feature', credit: '', generated: {termsRead: '2026-11-12', watermark: false, commercial: 'unknown', prompt: 'p', ...extra}}` and writes `sourcing.json` with `generated: {allowed: true, monetized: false}` (use `mutate` + `write`). The fixture's `a01` keeps its derivatives, uses and rights evidence.
  - `test('a generated row passes when the film allows it')`: `checkAssets(d).errors` deep-equals `[]`, and `report.perBasis.generated === 1`.
  - `test('a generated row is refused when sourcing.json has no generated block')`: delete `generated` from sourcing; `refused(d, /^a01: generated material not allowed in sourcing\.json \(set "generated": \{"allowed": true\}\)/)`.
  - `test('a generated row without its fields is refused')`: delete `generated.prompt`; `refused(d, /^a01: generated row needs platform, licenseUrl and generated\.termsRead, watermark, commercial, prompt/)`.
  - `test('a monetized film refuses generated rows not cleared for commercial use')`: `monetized: true` with `commercial: 'unknown'` refused with `/^a01: commercial use unknown not allowed in a monetized film/`; with `commercial: 'yes'` passes.
  - `test('watermarked generated rows are listed for a human check')`: `watermark: true`; `reportText(checkAssets(d))` matches `/Watermarks stay visible, uncropped and uncovered: a01/`; the valid fixture's report does not match `/Watermarks stay visible/`.
  - Update `test('the valid fixture passes ...')` only if `perBasis` changes (it should not).
  In `template-text.test.mjs`: the shots test expects `/built, clip, photo, capture, model, lottie, generated, mixed/`; new `test('the template allows generated material, not monetized')` reads `sourcing.json` and deep-equals `generated` to `{allowed: true, monetized: false}`; the contract test also requires `generate-video` in `AGENTS.md`.

- [ ] **Step 2: Run to verify they fail**

Run: `node --no-warnings --test templates/video/tools/checks/assets.test.mjs templates/video/tools/checks/template-text.test.mjs`
Expected: the new tests FAIL; the rest pass.

- [ ] **Step 3: Implement**
  - `BASES` gains `'generated'`. In the row loop, for `r.basis === 'generated'`: field check (`platform`, `licenseUrl`, `generated.termsRead`, `generated.watermark` boolean, `generated.commercial` in `yes|no|unknown`, non-empty `generated.prompt`) with the message above; `sourcing.generated?.allowed !== true` gives the not-allowed message; `sourcing.generated?.monetized === true && commercial !== 'yes'` gives the monetized message; collect `watermark === true` ids into `watermarked`. Generated rows keep the existing acquisition and rights-evidence checks (the evidence is the terms page).
  - Return `report.watermarked`; `reportText` adds `- Watermarks stay visible, uncropped and uncovered: <ids>.` under Human checks only when the list is non-empty.
  - `sourcing.json`: add the `generated` block. `shots.md`: insert `generated` before `mixed` in the source list and one sentence: a generated shot names its reason and follows the `generate-video` skill. `AGENTS.md`: one line under the asset commands: generated takes enter through `aos asset fetch --basis generated` (skill `generate-video`, rule R55).

- [ ] **Step 4: Run to verify they pass**

Run: `node --no-warnings --test templates/video/tools/checks/assets.test.mjs templates/video/tools/checks/template-text.test.mjs`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add templates/video
git commit -m "video template: asset gate admits generated rows with rights, monetized switch and watermark check"
```

### Task 3: The `generate-video` skill, rule and decision

**Files:**
- Create: `agents-home/skills/generate-video/SKILL.md`, `agents-home/skills/generate-video/flow.md`, `agents-home/skills/generate-video/kling.md`
- Modify: `agents-home/skills/tool-catalog/SKILL.md` (one table row next to `video-references`), `agents-home/video/video-rules.md` (append R55), `docs/decisions.md` (entry on top)
- Modify: `docs/superpowers/specs/2026-11-12-generative-video-sources-design.md` (Rights section: `fetch --basis generated` replaces `gen-ingest`; `--file` deferred)

**Interfaces:**
- Consumes: the CLI flags from Task 1, the `sourcing.json` block from Task 2.

- [ ] **Step 1: Write `SKILL.md`**: frontmatter `name: generate-video`, description under 250 characters (when to use: a shot marked `generated` in `shots.md`, or the operator asks for a generated transition, asset or clip). Body = the spec's six procedure steps, with the exact fetch command:
  `aos asset fetch --film <dir> --id <aNN> --url <file link> --kind clip --basis generated --acquisition platform-feature --platform <flow|kling> --license-url <terms page> --terms-read <date> --watermark yes|no --commercial yes|no|unknown --prompt "<prompt>" --why "<need>"`,
  the operator touchpoints, the quota rule (stop the platform, report when it resets, never touch accounts), and the ffmpeg commands from the spike: motion measure `ffmpeg -i take.mp4 -vf "scale=320:-1,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=motion.txt" -f null -`, and the `xfade` join (4 frames in, 10-12 out).
- [ ] **Step 2: Write `flow.md` and `kling.md`** from the spec's observed table, one section each: reach frames mode, put keyframes in, cost and credits, confirmation, wait, get the file link, output, behaviour; then "Secondhand, check first-hand" (terms on automated use and commercial use) and "Last verified 2026-11-12". Describe controls by visible label or role, never by coordinates. Include the in-page methods that worked (Flow: drop event on the media area; Kling: slot file input, and the Upload item's file input) and the local-file note (try Claude in Chrome's file upload first, then in-page bytes).
- [ ] **Step 3: Append R55** to `video-rules.md`: `- R55 [manual] Generated material is opt-in per shot and enters only through aos asset fetch --basis generated with its terms, watermark and commercial fields; it passes R04 on review sheets like any shot, watermarks stay visible, and no account is tracked or switched to stretch a free quota (skill generate-video).  (from the Flow and Kling spikes 2026-11-12)`
- [ ] **Step 4: Add the catalog row and the decisions entry** (`## 2026-11-12 - Generated video is a case-by-case material source`: Why, Decision, What was rejected: account rotation, a queue/quota system before more platforms are tested).
- [ ] **Step 5: Verify the catalog and skill tests**

Run: `aos test`
Expected: all suites pass under PowerShell 7 and Windows PowerShell 5.1, including "lists every shared skill ... in the catalog".

- [ ] **Step 6: Commit**

```bash
git add agents-home/skills/generate-video agents-home/skills/tool-catalog/SKILL.md agents-home/video/video-rules.md docs/decisions.md docs/superpowers/specs/2026-11-12-generative-video-sources-design.md
git commit -m "skill generate-video (Flow, Kling recipes), rule R55, decision entry"
```

### Task 4: Second opinion and hand-back

- [ ] **Step 1:** Run the `second-opinion` skill: `codex exec --profile review "<review the branch diff against main for correctness of the gate and fetch changes, and for any recipe line stated as fact that is not marked observed>" </dev/null`. Record Codex's findings separately from Claude's.
- [ ] **Step 2:** Fix confirmed findings with a test each; rerun `aos test`.
- [ ] **Step 3:** Report to the operator: commits, test results, Codex's verdict. Do not merge, push or run `aos sync` without the operator's go-ahead.
