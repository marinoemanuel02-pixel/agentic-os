# Remaining stack trials implementation plan

**Goal:** Reconsider the unadopted candidates using shared, small tests that establish useful
differences from the installed stack, without Claude inference or additional API spending.

**Architecture:** Codex conducts bounded trials in disposable home-folder workspaces. Reuse one
input pack per workflow, compare against the working baseline, and retain outputs plus failures.
Install an optional candidate only for its assigned trial; promote it only after that trial passes.

**Tech stack:** Native Windows, existing Python/Node/PowerShell, Playwright, FFmpeg, local models,
and scoped provider access where already authorized and confirmed free.

**Sources:** [57-entry audit](../../research/2026-10-19-candidate-audit.md),
[original coverage map](../../research/2026-10-19-candidate-sources.md),
[research evaluation](../../research/2026-10-19-stack-evaluation.md),
[actual installations](../../stack-additions.md).

This is a test plan, not a report that the proposed trials passed. Reasons below reproduce the
19 October decisions; current compatibility, pricing and release claims must be rechecked before
each trial. Some entries were deferred or retained as references rather than rejected as products.
The later decision to install OmniRoute supersedes its original general-gateway deferral.

## What was not adopted, and why

### Runtime candidates and partial integrations

| Candidate | Why it was not added in full | Reconsider through |
| --- | --- | --- |
| Ponytail | Reuse-first/minimal-change guidance already exists. Another always-on policy/status layer has no measured benefit. One focused prompt remains eligible. | C |
| Ruflo (`ruvnet`) | Whole swarm/memory framework duplicates aos. Its scanner expects different schemas, and degraded output can still exit zero. | C, scanner only |
| Ruflo (`louis1969`) | Different router; licence file not established and missing providers can produce mock responses. | Hold until identity/licence and real-provider behavior are established |
| API Anything, browser-learning version | Needs a repetitive lookup that ordinary browser/API/CLI cannot already perform; expiry, automatic repair and session storage are untested. | A |
| API Anything, OpenAPI version | A different project. Need a genuinely missing CLI and checks of its licence, authentication and PowerShell output. | A |
| Perplexity MCP | Uses separately billed API capacity; existing subscriptions do not pay for it. | Hold under no-extra-spend policy |
| Playwright MCP | Built-in browser controls and Playwright CLI already cover normal automation. Persistent-session advantage is unproven. | A |
| Chrome DevTools MCP/CLI | Useful performance/network diagnostics, but no real defect was tested. Start with CLI and a disposable browser profile. | A |
| Chrome extension bridges (`mcp-chrome`, `chrome-mcp`) | Main-profile/session access and native-host permissions add cost; only useful for an authenticated workflow the native browser cannot reach. | A, disposable profile first |
| Filecrawl / Firecrawl MCP | Exact Filecrawl identity was not established. Likely Firecrawl adapter has a limited keyless route; it needs a failing extraction case. | A |
| Firecrawl service/self-hosting | Free hosted retrieval is conditional on a real gap and hard limits. Self-hosting adds another dependency/service and does not guarantee hosted parity. | A, bounded hosted/keyless route first |
| GlyphMCP, Excalidraw service | Editable diagrams could add value, but free limits, retention and export fidelity were unknown. | B |
| Glyph RAG (`terminus-labs-ai/glyph`) | Adds PostgreSQL/pgvector plus another index before a missing corpus is demonstrated. | D, only if smaller options fail |
| Glyph-language compiler MCP | Only relevant to a Glyph-language codebase, which this setup lacks. | Hold until that workload exists |
| NANYTE Glyph GDS bridge | Chip-layout/GDSII capability; no current chip-layout project. | Hold until that workload exists |
| Full OpenDesign desktop app | Agent Kit was installed instead. Full app adds workspace persistence, telemetry and another runtime; native-subscription propagation/editable exports remain untested. | B |
| Herdr | Distinct terminal persistence/activity visibility, but recurring disconnect/lost-session problems were not established. | E |
| Agent-Reach (`Panniantong`) | Many channels duplicate gh, yt-dlp and browser access. Test a missing channel rather than install every authenticated channel. Avoid the unrelated same-name PyPI package. | A |
| Agent Reach (`jgalea`) | Separate implementation; selective channels/cache overlap existing routes, and Windows was not real-machine tested upstream. | A, only its selective interface |
| Obscura | Another browser engine; normal interaction is covered and its speed/CDP compatibility claims were not reproduced. | A |
| Claude-mem / claiude mem | Historical search is distinct from HANDOFF, but continuous summaries use quota. Default AppData/PATH placement and hosted-trial onboarding conflict with current setup choices. | D; no Claude observer while limited |
| Planning-with-files | Durable plans already exist. Selective refresh may help drift; another completion-hook owner may cause unnecessary stops. | C |
| Taste-skill | Worth an alternative design trial, but its substantial context/build budget was not justified. Avoid mixing its style rules into the same run as competing design skills. | B |
| Matt Pocock skills | Select useful domain/architecture material by task; much TDD/research/handoff behavior overlaps. Avoid bulk interviews, extra agents and tracker publishing. | B/C, one exact skill |
| Wshobson agents/skills | Domain material can help, but a second orchestrator/adapters/memory configuration is unnecessary. Static/model-judge scores are not local task results. | B/C, one exact skill |
| Beads | Dependency backlog can help at larger scale; it adds a Dolt database and backup/migration obligations. JSONL is not a complete backup. | E |
| Vibe Kanban | Visual task/diff UI could help, but worktree/agent ownership overlaps aos. Former hosted services were being sunset; local community app needs its own test. | E, local only |
| Claude Code Router | Another general gateway duplicates the chosen OmniRoute route; subscriptions do not become interchangeable API credits. | Hold unless OmniRoute fails a specific required route |
| CC Switch | GUI administration remains optional; auto-sync would create a second writer of files aos owns. | E, inspect-only disposable configuration |
| Claude HUD | The installed aos-status mod covers the current need. Compare a specific missing display before adding another status layer. | E, offline fixtures first |
| Headroom compressor | Could help large structured tool outputs, but fidelity and original-retrieval overhead need measurement. Global proxy and extra model downloads were deferred. | C, local non-model library path |
| Headroom browser extension (`ZM-BAD`) | Browser context estimates are heuristic and distinct from native measured usage. No browser-chat gap established. | E, optional disposable profile |
| Headroom quota dashboard (`domanski-ai`) | Read-only history may help; account rotation has little value with one account/vendor. Windows transactional handoff is unsupported. | E, read-only fixture data |
| MemPalace | Adds embedding model/Chroma/index cost. Need exact historical evidence, deletion and rebuild tests on a small selected corpus. | D |
| Gunk Buster (Gustavo Meilus) | Promising deterministic drift scanner, but findings need source verification. File-moving/trap workflow was not approved as default. | C, read-only scan |
| Alternate `/watch` (Newuxtreme) | Chosen local Watch route already fills the gap. Alternate no-caption transcription relies on external Groq/OpenAI services. | Hold unless the chosen route misses a concrete feature |
| Native Claude session messaging | Status mod installed, messaging extension not implemented. Exact delivery/refusal/queue/ownership semantics still need a dedicated test. | E offline; live Claude check remains pending |

### Existing capabilities, references and collections

| Entry | Why no additional installation was made |
| --- | --- |
| Remotion, FFmpeg, yt-dlp | Already installed and in use. The `sd` suffix remains unidentified; Stable Diffusion would be a separate model/hardware task. |
| Context7 | Existing MCP was configured and queried successfully; a second installer adds no capability. |
| GitHub MCP | gh works and a GitHub connector is available. Add a server only for an uncovered client workflow. |
| Agent Skills format and general skill packs | Shared SKILL.md sources already exist. Choose individual React/accessibility/domain skills when relevant. |
| Karpathy skills | Core principles already folded into AGENTS. Alternative audit/refactor/wiki workflows need a specific gap; no official Karpathy authorship was established. |
| Everything Claude Code / ECC whole bundle | Already retained as a reference. Bulk hooks/memory/process installation would duplicate existing guards; a standalone scanner can enter C. |
| Gustavo Franco engineering rules | Selective doc-sync/render ideas may help; whole configuration duplicates guards and Bash hooks do not prove PowerShell coverage. |
| Gustavo Fior Craft | Design-engineering reference, not an agent runtime. Font terms remain separate from code terms. |
| Awesome Claude Skills / Awesome Agent Skills | Discovery collections with separately licensed, separately authenticated entries; not one vetted installation. |
| Awesome Claude Code | Already a reference catalogue; linked tools need individual review. |
| Claude Plugins directories | Native plugin support and bridges already exist; choose one missing plugin rather than import the directory. |
| Awesome MCP Servers | Discovery index; index popularity/licence does not establish server permissions, compatibility or free service access. |
| System prompt collections | Research references, not authoritative descriptions of this running harness or installable upgrades. |
| Find Skills | Skill-installer/plugin discovery already cover much of this. Optional search convenience, not automatic installation into separate vendor copies. |
| Official Claude Code Setup recommender | A read-only gap recommender, not an installer. Its suggestions must be compared with this mature baseline. |
| Archived `b33eep/claude-code-setup` | Archived setup bundle was not adopted. |
| `gtbauke/skills`, guessed `gufranco/claude-code` | Repository identities were not established (404). Actual Gustavo alternatives were evaluated separately; unknown contents were not invented. |

### Earlier research proposals left unadopted

These precede the 57-name audit and are included so "initial setup" also covers the research reports.

| Proposal | Recorded reason |
| --- | --- |
| Another correction/integration/review telemetry schema | Existing receipt fields already store them; the gap is recording observations. |
| General recovery/archive subsystem | A synthetic declared-preservation test passed, but real app archive recovery, ignored state and DPAPI portability were not established. |
| Persistent SQLite FTS index | Small diagnostic: 8/12 expected-document hits versus existing term search 10/12. No improvement shown. |
| New persistent dense/sparse retrieval sidecar | Existing dense route scored 12/12 on a small diagnostic, but no held-out Italian-source/freshness/deletion evidence; sparse/multi-vector responses were not observed. |
| Extra early video approval stage | Existing style/hero and visual-evidence gates already require it. |
| New OpenTelemetry collector/export | No current outcome decision needs another collector; vendor metrics cannot substitute for host acceptance. |
| Context pruning / disabling skills | No source-attributed measurement from the actual running harness; tiny input totals do not identify skill overhead. |
| GPU ASR migration | CPU transcription works; no measured workload bottleneck justified CUDA changes. |
| Removing App Server in favor of native TUI steering | Programmatic delegation and a human TUI serve different callers. |
| Another native Codex installer | Existing implementation already invokes the official installer and preserves compatibility/rollback. |
| Xberg | Licence corrected to MIT; proposed Python release lacked a Windows wheel. A separate Windows CLI asset exists but OCR dependencies/fidelity remain untested. |
| Marker / Docling | Not benchmarked; isolated upstream issues do not prove they cannot run here. Need an uncovered document case. |
| MCP-login changes / more read batching | No actual OAuth defect; independent read batching already available. |
| Whole swarm replacement, disk-streamed CPU LLM, unspecified hosted long-task model | The inventory supplied capabilities rather than an exact validated replacement/model. aos/local Ollama already cover parts; model identity, throughput, licence and any API budget need evidence. |
| Second full video/content orchestrator, generated-footage providers | Existing project-folder/FFmpeg/Whisper/Remotion pipeline already covers much. OpenMontage/Kdenlive are narrow trials; paid generation and new orchestration were not justified. |
| Another native browser layer | Existing browser/Playwright access is present; only a demonstrated diagnostic or site-access gap warrants another layer. |

The last three rows describe why no additional wholesale subsystem followed the earlier feature
inventory. They do not claim a named implementation was benchmarked or found defective.

## A simple way to test many candidates

Use six short batches. Each candidate gets the same input and a separate output folder. A batch
can stop once the existing route already solves the task with fewer dependencies/corrections.
Budget the first screen at 15 minutes per candidate and at most two attempts; slow downloads,
unknown terms or paid requirements become explicit blockers, not prolonged installation projects.
Only promising candidates advance to one real-workload trial and a second repeat run.

### Shared preparation

- [ ] Create a disposable `remaining-stack-trials` folder under the home-folder aos research area;
  never index the whole home folder, copy real account tokens, or use the live vendor settings as fixtures.
- [ ] Freeze source hashes and expected facts before candidate runs. Keep the verifier and input
  identities unchanged across comparisons; record tool version, arguments, elapsed time, peak memory,
  download/storage footprint, exit code and raw output. Unknown quota usage stays unknown.
- [ ] Use only Codex/local deterministic tools. No Claude model/reviewer/observer request, and no
  paid API fallback. A validated explicit OpenRouter free route may supply a text candidate later;
  the lead verifies it and does not call it an independent vendor review.
- [ ] Record each result as passed, failed, blocked or not run, with a reproducible command and
  evidence path. Help/version/import/mock success counts only for that narrow property.

### A. One website and one public source: retrieval, browser and API tools

**Candidates:** API Anything (both variants), Playwright MCP, Chrome DevTools CLI, Chrome
bridges, Firecrawl adapter/service, Agent-Reach variants and Obscura.

- [ ] Create five local pages: ordinary text/table, JavaScript-rendered facts, pagination, a
  disposable login with fake credentials, and a route returning 401/changed schema. Freeze 12 facts.
  Baseline: available browser plus existing Playwright CLI, with the same expected fields.
- [ ] Test a recorded action across unseen parameters; change an endpoint or expire the fake
  session. Require correct fields and an explicit failure on missing/auth-invalid data, with no
  made-up records. Measure cold and repeated runs separately.
- [ ] Hosted tools cannot fetch loopback fixtures: use one explicitly selected public documentation
  site for the same extraction checks, freeze its source snapshot, and obey robots/service limits.
  Do not expose the local server through a tunnel. Test DevTools against an intentionally seeded
  slow asset and console error; require correct location/evidence, not just a trace file.
- [ ] Agent-Reach gets one actually missing public channel (e.g. RSS); if none exists, mark it
  not needed. Authenticated bridge tests use the disposable account/profile first.

### B. One interface brief and one diagram: design and skill alternatives

**Candidates:** installed frontend-design/UI UX/OpenDesign Kit, Taste, selected Vercel,
Matt Pocock/Wshobson material, GlyphMCP; full OpenDesign only if the kit lacks a required export.

- [ ] Freeze one small desktop/mobile interface brief, content and assets. Build separate outputs
  with equal task scope and a maximum of one correction round each; avoid combining competing
  art-direction skills in a single output. Record actual available usage, not estimated savings.
- [ ] Check desktop/phone screenshots, keyboard path, labels, overflow and measured contrast.
  Use known checks plus the operator's visual preference; Codex's aesthetic opinion is not an
  independent quality benchmark. No publishing or deployment is necessary.
- [ ] Export/reopen an editable five-node diagram with exact labels/edges. Test layout modification
  and export fidelity. A hosted diagram tool advances only after its free limits/retention are known.

### C. One small repo and noisy output pack: code navigation, prompts and scanners

**Candidates:** installed Graphify/Serena/Repomix/RTK; Headroom library; Gunk Buster,
ECC/Ruflo scanner components; Ponytail, Planning-with-files and exact engineering skills.

- [ ] Freeze a three-language fixture (Python, TypeScript, PowerShell) with cross-file calls, one
  deliberately broken configuration, stale instruction text and a synthetic `.env` canary.
  Freeze six symbol/caller answers and expected scan locations. Baseline: rg, gh and direct reads.
- [ ] Require correct locations and source evidence. Change/delete a symbol then re-query: an index
  must refresh or report stale state. No compressed result may omit the seeded failure, diagnostic
  or exit code. Ensure selected exports omit the fake secret file. Retain access to originals.
- [ ] Test prompt/reinjection alternatives on one interrupted multi-step fix with frozen acceptance
  checks. Score missed requirements and corrections, plus injected context; do not claim measured
  subscription savings. Stop if they merely restate existing rules or create redundant gates.
- [ ] Run scanners read-only, verify each finding against seeded and real source facts, and treat
  degraded coverage as incomplete even if the command exits zero. No automatic repairs/traps/hooks.

### D. One selected bilingual history: memory and retrieval

**Candidates:** MemPalace, Claude-mem's reusable non-Claude/manual-ingest path if supported,
existing local dense retrieval, and optional Glyph RAG only after a simpler candidate fails.

- [ ] Start with 12 synthetic English/Italian notes, ten questions and exact expected source spans.
  Include a superseded fact, edit, deletion and one irrelevant near-match. Baseline: direct file
  search plus the already installed embedding route.
- [ ] Require exact quotations/locations, correct current fact and deletion from subsequent answers.
  Export/rebuild into a new folder and re-run the same checks. Record index/model memory and disk.
- [ ] Claude-mem's live Claude capture and observer-quality behavior remain blocked by quota;
  manual ingestion cannot establish those features. Do not enable continuous capture of real chats.

### E. One fake long-running task: terminal, task-board and status tooling

**Candidates:** Herdr, Beads, local Vibe Kanban, CC Switch, Claude HUD, three Headroom variants,
and the existing aos-status/native-messaging surface.

- [ ] Use a harmless PowerShell counter plus a tiny disposable repo with one dependent task,
  one blocked task and a diff. Close/reopen the terminal UI; distinguish reattachment, restart and
  process survival. No real agent or second writer needs to launch.
- [ ] Test task dependency blocking, stop/cancel, diff navigation and export/restore. Feed saved
  fake usage records to dashboards; unknown/stale usage must remain labelled. CC Switch operates
  only on a disposable config directory and must not modify aos-owned production settings.
- [ ] Validate Claude mod/HUD parsing/rendering with native fixtures without model requests. Actual
  cross-session Claude delivery and embedded Desktop compatibility remain unverified until a live
  compatible session is available. A mocked queued message is not proof of delivery or completion.

### F. One document/media pack: finish the installed tools' real checks

**Candidates:** AnyDoc (then Xberg/Marker/Docling only for uncovered failures), Watch,
OpenMontage, VoiceStudio, CLI-Anything Kdenlive, and the existing FFmpeg/Whisper/Remotion routes.

- [ ] Make one DOCX/text PDF with known headings/table/reading order and one scanned page. Verify
  exact cells and omissions; only install another extractor if the current route fails useful content.
  Confirm scans stop locally rather than silently upload. PDF visual QA remains a separate check.
- [ ] Make one short captioned video with known spoken phrases and a brief on-screen-only event.
  Check Watch timestamps/event detection and known transcript/cut boundaries. Compare export
  duration/audio/video and preserve source hashes; missing ASR words are not proof of silence.
- [ ] Generate short Italian and English clips from the chosen bundled local VoiceStudio voice.
  Verify health, installed model, actual engine/device, audio decoding/non-silence and offline repeat.
  Preserve synthetic marking; the operator can judge voice appeal from the sample.
- [ ] Open a Kdenlive project and render a minimal timeline with a strict timeout, comparing it with
  direct FFmpeg. Existing consumer-init timeouts are failures to diagnose, not passed renders.
- [ ] Use the saved Pixabay key for one bounded stock search through OpenMontage. Check original
  source URL/creator/licence metadata and duration, then assemble a short local export. Pexels remains
  unavailable because the operator has no key; it is not a required dependency. No paid generation.

## Recommended order and acceptance

First finish **F** and the saved-key integration checks (one free OpenRouter request, one narrowly
scoped Composio read, one Pixabay lookup). Then run **C**, **A**, **B**, **D**, **E**. This validates
already-installed capabilities before adding more dependencies and gives reusable fixtures to later
tools. Composio service/account identity and scope must come from the existing connection; no
external send/write operation is part of this test plan.

Keep a candidate only when it completes a missing task or measurably improves the baseline while
retaining all required facts/failures and acceptable setup cost. Otherwise record the precise reason
and leave it unintegrated. No single composite score hides a failed correctness check.

**Review/limits:** Codex owns the trials and checks; no independent other-vendor review is claimed.
Some native Claude, personal-account consent and subjective voice/design checks cannot be replaced
by mocks. The user already waived external review for this setup. This planning task does not
authorize purchasing API credit, importing every collection, or publishing artifacts.
