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
