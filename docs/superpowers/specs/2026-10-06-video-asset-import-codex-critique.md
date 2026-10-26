# Codex critique of the video asset import spec (2026-10-06, codex exec --profile review -m gpt-6-astra, 20,376 tokens)

Reviewed commit 5e2e17b. Verbatim answer below; Claude's response is the revised spec (each change cites the finding).

A. Findings

1. **§3; Open items — rights/terms risk.** Duration caps, muted audio and overlapping narration cannot establish fair use; `capture` does not establish permission either. A channel preference cannot resolve the spec’s acknowledged download-terms restriction. Require per-use rationale, rights evidence and a separate acquisition-permission decision. Label automated results “policy checks passed”; replace “ledger is the dispute proof” with “supporting evidence.” Terms were not independently verified in this review.

2. **§3 — unenforceable gate.** `uses[].in/out` has no film placement; `commentaryLine` cannot prove overlap, substantive commentary or visible attribution. Literal `staticFile` coverage misses dynamic paths, remote URLs and nested model/Lottie dependencies. Require a resolved render-use manifest with timeline frames, dependency hashes, narration intervals and attribution configuration. Keep commentary relevance and credit legibility as explicit human checks.

3. **§§2–4, 6 — provenance contradiction.** Fetch hashes original bytes, proxy changes those bytes, and the gate checks an unspecified file against the hash. The spec also omits explicit integration with R22’s sealed inputs. Record separate source/proxy hashes and conversion settings; seal the ledger, rights evidence, derivatives and resolved dependencies. Resolve writable paths through `AOS_VIDEO_MEDIA_ROOT`, consistent with R10/R25 and the template.

4. **§§2–4 — excerpt/audio ambiguity.** Fetching source seconds 12–17.5 produces an excerpt whose local start may be zero; `Clip` then applying 12–17.5 can trim twice. One proxy per asset also cannot represent conflicting per-use audio choices safely. Define source, downloaded-media and film time coordinates separately; verify actual excerpt boundaries and specify how audio variants are derived.

5. **§2 — unenforceable download budget.** “Stops before exceeding” lacks behavior for unknown sizes, retries, partial downloads, concurrent fetches and cache hits. Define whether the budget measures network bytes or retained bytes; reserve capacity atomically, enforce streaming limits and account for failed transfers. State how capture output and proxy expansion affect storage separately.

6. **§§4, 6 — contract conflicts.** Only R03/R04 change, while R17 and the template prescribe long shots with dissolves/match cuts; R18/R28 condition mixed media on the brief and a demonstrated hero. Explicitly reconcile these with wipes, whip blur and imported media. Define how generated source tags satisfy R24’s literal-text claims contract, including independent frame review.

7. **§8 — unreliable quota control.** Log polling cannot promise a hard input ceiling; accounting semantics, child runs, missing events and cancellation behavior are unspecified. Define cumulative versus cached input, bind events to the exact delegate, budget descendants, record overshoot and terminate the process tree with a receipt. Describe this as a best-effort limit and test delayed/missing events and cancellation.

8. **Testing — underspecified acceptance case.** In a 10-second film, fair-use plus capture permits only one second total. The proposed four-basis test supplies no durations and omits public-domain/own. Specify valid timeline fixtures and separate refusal fixtures; mutate each protected field against production gate code so passing tests establish that the guard actually detects violations.

B. Proposed ownership after reset

Planning estimates, **total processed tokens including iterations**, pending code inspection:

- Adapters: **60–100k**; shared interface, then incremental sources.
- Ledger gate: **40–70k**, against Claude’s failing fixtures.
- `delegate --max-input`: **20–35k**.

C. Capacity

Live five-hour usage, weekly usage and next reset are **not visible to me**. The spec reports **19% remaining at 19:05**, with an approximate **20:31 Europe/Rome reset on 2026-10-06**; that is historical, unverified information.

Read exactly the three requested files. No builds, tests, web access or edits.

**REVISE**

## Codex review of the asset gate, tool, adapters and media components (2026-10-06, codex exec --profile review -m gpt-6-astra, 68,160 tokens)

Reviewed at commit c3f2693 (read-only, two in-memory probes). Verbatim below; Claude agreed with all eight and fixed them test-first (see the commits after a229184).

1. **P1 — Media bypasses the gate.** [assets.mjs:76](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/templates/video/tools/checks/assets.mjs:76) skips both registry files; the scanner checks only selected call syntax, and inventory covers only `public/assets`. **Input:** an empty ledger, `public/untracked.mp4`, and `<video src="/untracked.mp4"/>` pass. An unchecked registry entry also passes. **Fix:** verify generated registries against the ledger; inspect media sinks and resolved imports with an AST, including aliases, relative URLs, CSS, and encoded paths.

2. **P1 — Rendered uses need not match counted uses.** [GlTransition.tsx:55](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/templates/video/src/lib/media/GlTransition.tsx:55) accepts asset IDs without use IDs; [assets.mjs:149](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/templates/video/tools/checks/assets.mjs:149) counts only declared uses. **Input:** render a capture through `GlTransition` with `uses: []`: it passes with zero counted seconds and no tag. Repeated `Clip` instances likewise need no additional ledger use. **Fix:** derive or reconcile actual placements, including transitions; require unique use IDs and nonempty tags. An empty credit with `texts:[""]` currently passes too.

3. **P1 — Credential-bearing URLs persist unredacted.** [asset.mjs:60](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/asset.mjs:60), [asset.mjs:73](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/asset.mjs:73), and [fetch.mjs:10](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/lib/fetch.mjs:10). **Input:** `--url https://host/file.mp4?token=SECRET` writes the token into budget logs, cache keys, ledger, and rights evidence; HTTP failures print it. **Fix:** keep request credentials transient; sanitize persisted URLs and errors, use opaque cache keys, and redact evidence excerpts.

4. **P1 — Excerpt downloads have no effective runtime byte watchdog.** [fetch.mjs:38](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/lib/fetch.mjs:38) runs synchronous yt-dlp and charges only the final destination size. **Input:** a failed excerpt leaves downloaded `.part`/separate-stream files but no destination: charged bytes are zero. Retries and intermediate traffic are also absent. **Fix:** monitor the child and actual received bytes, enforce the remaining cap during transfer, charge failures, and clean temporary files in `finally`.

5. **P1 — HTTP and ancillary traffic escape accounting.** [fetch.mjs:16](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/lib/fetch.mjs:16). **Input:** two 60-byte chunks under a 100-byte cap return `bytes:60` despite receiving 120; a reset after 60 bytes throws before charging. Rights-page fetches ([asset.mjs:29](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/asset.mjs:29)) and browser captures bypass the budget entirely. **Fix:** count every received chunk, persist accounting on failure, and budget all film-associated network traffic.

6. **P1 — External dependencies evade inspection.** [assets.mjs:145](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/templates/video/tools/checks/assets.mjs:145). **Input:** a correctly hashed `assets/a.GLTF` containing an external buffer URI passes because extension matching is case-sensitive. GLB dependency inspection is absent too. **Fix:** normalize extensions, inspect GLB JSON chunks, and reject external resources regardless of casing or URI encoding.

7. **P2 — Corrupted or partial cache objects are trusted.** [cache.mjs:15](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/lib/cache.mjs:15), [cache.mjs:26](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/agents-home/video/assets/lib/cache.mjs:26). **Input:** replace cached media with another valid file; lookup checks existence only, and proxy regeneration records fresh derivative hashes without checking the original hash. An interrupted copy can similarly leave the final object path occupied. **Fix:** hash-check reads, publish objects atomically, and lock shared index updates across films.

8. **P2 — Rights evidence requires only an existing path.** [assets.mjs:132](C:/Users/marin/.aos/worktrees/agentic-os-video-assets/templates/video/tools/checks/assets.mjs:132). **Input:** `rightsEvidence:"sourcing.json"` passes for a CC0 declaration. **Fix:** require a contained evidence file with validated URL, retrieval time, digest, excerpt, and asset/license binding.

Ran PowerShell reads and two lightweight `node --input-type=module` in-memory probe commands; no files changed. Six gate bypass probes and both HTTP-accounting probes reproduced. Standard NC/SA/ND URLs were rejected. No inherently unfailable assertion was found; integration tests check source strings, not execution.

Could not establish actual export/sealing enforcement, lock behavior, or frame-rounding effects because their implementations were outside scope. No suite, render, browser, or live download was run.

**REVISE**

## Codex review of the regrouped video rules (2026-10-06, 17,595 tokens; Claude applied all five points in eb178cc)

- **Contract consistency:** R35/R39 and the template’s “Imported material” section agree on sourcing order, asset records, component-only access, and policy checks. R39 places policy and budget in the brief; the template names `sourcing.json`. Clarify that the brief establishes these and `sourcing.json` records them, avoiding competing authorities.

- **Unresolved permission boundary:** R03 permits imported material when it carries the line and matches the design system, but R18/R28 still require a brief-level exception for mixed media. The template does not mention that condition. Add a cross-reference so permission to import is not mistaken for permission to mix media freely.

- **Meaning lost in R04:** Previously, “generic stock look” and “visuals that do not carry their line” were independent rejection criteria. Now, “generic generated or generic stock visuals that do not carry their line” narrows both: generic-looking visuals may pass when relevant, while bespoke visuals that fail their line are no longer explicitly rejected. Restore the independent criteria. R03’s opt-in requirement remains intact; allowing imported material does not require weakening R04.

- **Decision wording:** The October 6 entry says generic generated imagery “stays rejected,” whereas R03 prohibits it *as the default* and permits opt-in subject to the gate. Align that wording.

- **Stage placement:** R20 under Delivery contains obligations beginning before the brief and continuing throughout production; Orchestration fits better. R07’s review explicitly occurs before merging delegated shots, so it belongs under Production or needs an explicit pre-merge cross-reference. R35’s QA placement should likewise cross-reference acquisition and production, where its ledger and component restrictions first apply.

APPROVE WITH CHANGES

## Codex final whole-branch review (2026-10-06, 56,303 tokens; Claude fixed findings 1-5 and 8 test-first and deferred 6 and 7 with rulings, see the commit after eb178cc)

Earlier findings **#1, #2, #3, #4, #5, #7 and #8 remain partially unresolved**. **#6 is fixed**: in-memory probes rejected external dependencies in uppercase GLTF and GLB files.

1. **P1 — Credentials still reach errors and evidence (earlier #3).** `agents-home/video/assets/lib/fetch.mjs:34` appends unsanitized `e.message`. **Input:** a URL containing username/password; a no-network probe confirmed the synthetic password survives in the error. `asset.mjs:90` also persists raw evidence excerpts. **Fix:** sanitize nested error messages and evidence text; apply the same protection to capture errors.

2. **P1 — Media still bypasses registry enforcement (earlier #1).** `templates/video/tools/checks/assets.mjs:106` skips registries; line 236 recognizes only narrowly formatted entries. **Input:** an unquoted TypeScript registry entry pointing remotely, or `<video src={path}/>` referencing `public/vo/untracked.mp4`. Both escaped validation in probes. **Fix:** structurally validate the complete generated registry and resolve media sinks, including variables and the VO exception.

3. **P1 — Rendered uses and attribution remain disconnected (earlier #2).** `templates/video/tools/checks/assets.mjs:106` ignores `asset-uses.ts`; `templates/video/src/lib/media/GlTransition.tsx:65` discards both use IDs and renders no source tags. **Input:** ledger declares one second; generated use declares sixty seconds and empty credit. The gate still reports one second. **Fix:** compare generated uses with ledger values, reconcile actual placement durations, and render transition attribution from both uses.

4. **P1 — Network budgets remain bypassable (earlier #4/#5).** `agents-home/video/assets/asset.mjs:82` fetches rights pages without remaining-budget enforcement or failure charging; `lib/capture.mjs:71` checks only whether approval exists. `lib/fetch.mjs:87` measures peak disk occupancy, not cumulative excerpt traffic. **Input:** exhausted budget followed by capture, failed rights download, or excerpt retries overwriting partial files. **Fix:** enforce remaining capacity across these transfers, charge failures, and replace disk occupancy with cumulative transfer accounting.

5. **P2 — Worktrees resolve different narration directories.** `templates/video/tools/word-times.py:41` uses the worktree basename without inspecting `.git`. **Input:** worktree `review` of film `My Film`: JS resolves `~/.aos/video/My Film`; Python resolves `~/.aos/video/review`. **Fix:** implement the same main-checkout resolution in Python. Otherwise word timing cannot find the film’s existing narration.

6. **P2 — Missing/late rollout leaves budget reporting incorrect.** `aos.psm1:3545` enforces only observed rollout events; line 3564 records final usage without reconciling the budget. **Input:** rollout absent through the final poll, but terminal usage exceeds `--max-input`. Overshoot remains zero. **Fix:** reconcile terminal usage, explicitly report unavailable monitoring, and define a bounded policy for missing telemetry.

7. **P2 — Shared cache index updates still race (earlier #7).** `agents-home/video/assets/lib/cache.mjs:26` performs an unlocked read-modify-replace. **Input:** two films read the same index and publish different entries; the last writer loses the other entry. **Fix:** lock shared index updates. Hash verification now addresses corrupted objects.

8. **P2 — Evidence remains unbound (earlier #8).** `templates/video/tools/checks/assets.mjs:169` validates superficial fields only. **Input:** correctly named evidence containing an unrelated URL, `"not-a-date"`, arbitrary digest and unrelated excerpt passes. **Fix:** validate retrieval time and bind evidence to the row’s asset and license.

Validation: PowerShell reads and two in-memory Node probe commands; no writes, suite, build, render or live downloads. PowerShell AST extraction was blocked; Python was unavailable. Native argument quoting and process-tree cancellation depend on helpers outside scope and remain unverified.

**REVISE**
