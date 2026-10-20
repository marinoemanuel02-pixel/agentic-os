# Remaining-stack trials, 20 October 2026

Executed the [six-batch plan](../superpowers/plans/2026-10-20-remaining-stack-trials.md)
with Codex, deterministic checks and local tools. No Claude inference or external review ran.
Two successful OpenRouter requests used an explicitly free route; no paid fallback was selected.
This is a bounded screening run, not a claim that every deferred candidate passed a full workload.

## Results that change the setup decision

| Candidate | Actual result | Decision / limit |
| --- | --- | --- |
| OmniRoute + OpenRouter | Saved account authenticated; provider connected; restricted worker key stored with `aos secret`. A gateway completion and the actual text-worker helper succeeded. Anonymous models access returned 401; a disallowed model returned 403. | Operational for the tested text route when its foreground server runs. No further account step for this connection. It remains an unaccepted text candidate route, not an AOS managed writer or independent reviewer. |
| Composio | Saved key returned HTTP 401 on both current and legacy connected-account inventory endpoints. | Blocked before connector selection. Replace/re-save a valid key for the intended project; a successful account inventory and narrowly scoped read still remain. No tokens were exported. |
| Pixabay / OpenMontage | One search returned creator, source page, duration and licence label; downloaded one selected clip and rendered a three-second export. | Working stock route. Pexels is optional and remains unavailable without a key. Individual content rights still depend on the selected asset. |
| Xberg 1.3.10 | Official Windows CLI extracted the known cells and depot from both text and scanned PDFs. Scanned-page extraction took about four seconds. | Strongest newly demonstrated gap-filler: local OCR beyond AnyDoc. Retained as an isolated trial binary; no global installer, PATH or MCP change. |
| API Anything, browser-learning variant | Built pinned source; learned from alpha/beta examples, returned the unseen gamma value, and reported a changed response schema as a nonzero failure. Repeated HTTP call took about 0.3 seconds. | Promising on-demand reuse of a known endpoint. Authentication expiry, repair across real sites and a real-workload comparison remain untested. No global registration. |
| Headroom 0.41.0 local log compressor | Reduced a frozen log from 14,357 to 466 bytes; retained file/line, error identifier, diagnostic and exit code. Original remained available. | Useful narrow compression trial. No model, proxy, automatic wrapping or subscription-token savings claim. Package version is captured in the machine receipt. |
| Gunk Buster 0.5.0 | Found a known package-manager mismatch at `AGENTS.md:1`, citing the conflicting package field. Reported no finding for the generic obsolete-command fixture. | Keep as a selective drift scanner, not a general truth checker. Radar writes its own index; no repairs, traps or production hooks were enabled. |
| ECC AgentShield 1.6.0 | Found all three planted categories: broad Bash permission, remote shell hook, and unpinned executable. Findings cite settings/MCP files; exit 2 reflects findings. | Useful read-only configuration check. Its general recommendations are advisory, not proof that the production permissions need replacing. No model/deep/sandbox analysis ran. |
| Beads 1.3.1 | Embedded database initialized without agent integration; dependency blocked the dependent task. Issue export/import into a second repo preserved ready-task behavior. | Conditional for a real dependency backlog. JSONL round-trip is not full Dolt backup/recovery or concurrent-writer proof. No production repo integration. |
| Herdr 0.9.5 | Named isolated server and workspace worked. A PowerShell counter advanced from 1 to 5 across separate CLI connections. | Conditional terminal supervisor. TUI close/reopen, server-restart restoration and original-process survival after restart were not established. No agents launched. |
| MemPalace pinned SQLite exact backend | Retrieved expected sources in the top five for 10/10 small bilingual questions, preserved exact spans, removed deleted/old records from later retrieval, and exported/rebuilt 11 remaining records. | Technically viable backend with existing local embeddings. Existing dense retrieval also scored 10/10; no demonstrated improvement justifies a second persistent memory system yet. Default Chroma embedding flow, capture and generated-answer quality were not tested. |
| Chrome DevTools 1.11.0 official CLI | Isolated session found the planted console error and the slow script, measured around 714 ms. Daemon stopped afterward. | Useful diagnostic route. Filesystem scope was bounded and usage statistics disabled. No global MCP installation or personal browser connection. |
| Playwright MCP 0.0.83 | Five local routes passed: text/table, dynamic values, pagination, disposable login page and explicit unauthorized response. | Available on demand. Existing Playwright baseline also passed; no reason for another always-loaded browser server. Login interaction/session expiry was not fully exercised. |
| Firecrawl keyless hosted MCP | One scrape of the selected public Python documentation returned all required terms. Direct public source snapshot retained. | Working bounded public fallback without another key. No crawling, account, tunnel, private-document upload or paid request. |
| Obscura | Native Windows executable started and retrieved the static local facts. | Narrow success only. Dynamic JS, authenticated sessions, rendering and broad CDP compatibility remain untested; no replacement of the existing browser route. |
| Ruflo security package 3.0.5 | Import/export surface worked; its configuration-value audit identified short synthetic signing material and low hashing rounds. | This library is not a repository scanner. No whole framework, agent swarm, policy replacement or production authentication change was adopted. |

## Installed routes checked more deeply

| Route | Evidence / limit |
| --- | --- |
| AnyDoc | DOCX and text PDF preserved all seven expected text/table markers. Image-only PDF explicitly exited 3 locally; hosted OCR stayed refused. Complex merged tables and reading-order fidelity beyond this fixture remain unmeasured. |
| Watch | Extracted bounded timestamped frames. The frame at five seconds was opened and showed the planted visual-only text. Embedded MP4 `mov_text` captions were **not** extracted; Watch reported no captions. Separate Whisper transcription supplied the known speech. |
| Whisper / FFmpeg / footage | Existing cached English CPU ASR recognized all four expected words; transcript intervals stayed within the source. OpenMontage produced a two-second audio/video cut with correct duration. Existing footage regression tests ran separately. This does not judge every word or editorial quality. |
| VoiceStudio | Cold reopen reached health 200, then fresh Italian and English clips decoded as non-silent audio using the cached selected engine. Health reports a CUDA-capable service; the selected Supertonic speech engine runs on CPU. Full network isolation, listening preference, dictation and cloning remain unverified. |
| CLI-Anything / Kdenlive | Prior native project export remains valid. A fresh minimal native render again timed out at 35 seconds and its owned process tree was stopped. Direct FFmpeg export worked. Native render remains failed. |
| Repomix | All six multilingual source markers were present in the selected export; synthetic `.env` canary absent. |
| RTK | Preserved the invalid Git command's diagnostic and exit 129. No automatic command rewriting or measured general savings. |
| Graphify | Code-only updates reflected rename and deletion with zero reported model tokens; Python caller and PowerShell call evidence retained. A TypeScript import was represented, but a TypeScript call edge was not established. Presentation labels include `()`, which the verifier normalizes. |
| Serena | Automatic language discovery chose TypeScript only. Explicit Python/TypeScript/PowerShell configuration enabled TS and PS symbol queries; first Python query timed out at 40 seconds, while subsequent Python edit/freshness checks passed. Keep explicit language configuration and startup limits; do not call this a clean cold-start pass. |
| frontend-design / UI UX Pro Max | Two same-agent interpretations of one frozen task brief passed desktop/390px checks: no horizontal overflow, labelled controls, keyboard skip link, working blocked-task filter, measured text contrast at least 8.89:1 for the checked elements. Screenshots were opened. This is not an independent skill-effectiveness or aesthetic benchmark, nor a complete accessibility audit. |
| OpenDesign Kit | Exported both fixtures to standalone HTML; reopened exports and checked their interactive filter. Local five-node SVG preserved labels/edges after geometry revision and reopening. Full OpenDesign was unnecessary for this export. |
| Claude HUD 0.12.0 | Native offline fixture selection: 48/49 passed, with a failure in the Git files ordering/width render test at `tests/render.test.js:233`. No live Claude session or production statusline change. |
| aos-status / native messaging | Existing status and coordination controls ran within the repository suite. Offline fixtures do not prove live Claude Desktop rendering or cross-session message delivery. |

## Candidates screened but not advanced

These are **not run** outcomes for the stated runtime feature, not failed benchmarks.

| Candidate | Why the runtime comparison remains open |
| --- | --- |
| API Anything OpenAPI-generation skill | Exact skill was read. It generates a new CLI under a substantial contract; the fixture already has a working learned endpoint. No production OpenAPI CLI gap justified generating another wrapper in this screen. |
| Chrome extension bridges (`hangwin`, `IngvarKofoed`) | Existing Playwright/MCP/DevTools routes covered the frozen fixture. Extension/native-host and personal-profile setup were not advanced without an uncovered account workflow. |
| Agent-Reach variants | No missing public channel was established. The plan explicitly allows stopping here; no cookie imports or broad channel installers ran. |
| GlyphMCP diagrams | Public page advertises a free tier and requires a token, but quantitative free limits and retention were not established. No token was present in this setup. Local editable SVG/export already worked. |
| Glyph RAG | The simpler existing embedding baseline retrieved 10/10 expected sources, so the plan's escalation condition was not met. |
| Full OpenDesign | Agent Kit standalone export/reopen passed; no missing full-app export was identified. |
| Taste | Exact current skill was read. Its advertised full build is 30-45 minutes, beyond the 15-minute initial screen. No shortened imitation is presented as a Taste trial. |
| Vercel / Wshobson design material | Exact guideline/accessibility skills were inspected. The mechanical fixture covers a subset of their concerns, not a controlled comparison or full WCAG assessment. No bulk skill pack installed. |
| Ponytail / Planning-with-files / Matt Pocock engineering skill | Exact skill sources were inspected. They add instruction/reinjection or architecture-review workflows; a deterministic fixture cannot establish their context/correction benefit. No automatic hooks or extra orchestration were enabled. |
| Claude-mem | Current source describes a Bun worker and native hooks; Windows setup writes AppData/PATH by default. No supported isolated manual path was validated in the time box, and live Claude observer evaluation remains blocked by quota. |
| Vibe Kanban local app | Current README announces sunset. Beads already exercised task dependencies/interchange and existing review tooling covers diffs; no distinct visual-board workload justified another runtime in this screen. Local startup/UI/restore remain untested. |
| CC Switch | Source was inspected; production configuration switching would introduce another writer of aos-owned files. Disposable GUI/config-isolation behavior remains untested. |
| Headroom browser extension | No browser-chat context gap was established for the native desktop workflow. Browser permission/profile installation was not advanced. |
| Headroom quota dashboard | Read-only/history features are distinct from its unsupported Windows transactional handoff. No isolated saved-usage parser/UI trial ran; native subscription data was not lent to it. |
| Marker / Docling | Xberg filled the selected scan failure locally. The plan only advances more extractors for an uncovered document case. |
| Alternate Watch, general Claude router, catalogues and prompt archives | Existing selected routes or references cover these. No new missing task justified another runtime or bulk import. |

## Evidence, reproducibility and limits

Raw evidence lives outside OneDrive at `~/.aos/research/remaining-stack-trials-20261020`.
The machine receipt is [stack-trials.json](2026-10-20-stack-trials.json). It references relative
artifact names and records fixture/source identities. External scripts contain the actual argument
arrays; run them from the setup checkout, using a fresh output directory when repeating because
several exports deliberately refuse overwrite. No credentials are in commands or receipts.

| Batch | Main evidence scripts / artifacts |
| --- | --- |
| F / accounts | `media.py`, `voice-render-checks.py`, `pixabay.py`, `session-trials.py`, `connections.py`, `router-test.py`, `router-worker-check.py`, `worker-candidate.json` |
| C | `code.py`, `serena.py`, `compression.py`, `local-diagnostics.py`, `scanner.py`, `ruflo-audit.mjs` |
| A | `browser.py`, `browser-fixture.cjs`, `devtools.py`, `firecrawl.py`, `browser-baseline.json` |
| B | `design.py`, `design-check.cjs`, `export-check.cjs`, `design-checks.json`, `standalone-reopen.json` |
| D | `memory.py`, `memory-post.py`, `memory-questions.json`, `memory-export.json`, `mempalace-post-edit.json` |
| E | `session-trials.py`, `herdr-test.py`, `beads-restore.py`, `hud-fixtures.stdout.txt` |

The first attempts exposed harness mistakes as well as candidate limits: the installed browser is
the headless-shell binary rather than Playwright's default Chrome path; DevTools creates page 2
while page 1 stays blank; the installed MCP SDK returns two HTTP transport streams and uses the
snake-case client name; MemPalace returns dataclasses, not plain dictionaries. These were corrected
without changing expected facts. First-attempt rows are retained, not counted as product defects.
A duplicate worker invocation refused an existing destination before a network call; the original
successful candidate and its hash are retained. Separate cold router starts also required bounded
startup retries; those timeouts remain evidence, not clean successes.

Peak process memory and provider-wide quota savings were not measured. Download sizes, pinned
source revisions, package locks, command exit codes and elapsed times are retained where observed;
unknown values remain null. No composite score hides failed correctness checks.

Repository verification: **527 passed, zero failed/skipped under each of PowerShell 5.1 and 7**
via `aos test`; the 16 launcher/router/worker controls also passed. No core implementation or
production test expectation was changed for these trials. New candidates remain isolated until a
real workload justifies integration; the existing OpenRouter connection was activated within the
operator's prior authorization.

Primary upstream material was fetched on 20 October: pinned GitHub source snapshots and official
release assets are identified in `candidate-sources.json` and `release-preflights.json`.
Hosted route behavior was checked against the official
[Firecrawl MCP documentation](https://github.com/firecrawl/firecrawl-mcp-server),
[DevTools CLI documentation](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/cli.md),
[GlyphMCP setup page](https://glyphmcp.dev/),
[OpenRouter limits](https://openrouter.ai/docs/api_reference/limits) and
[Pixabay API documentation](https://pixabay.com/api/docs/).
