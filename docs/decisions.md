# Decisions

Why agentic-os is shaped the way it is. Newest first. When a decision changes, add an entry;
don't rewrite the old one: the record of what was rejected is the part that ages best.

## 2026-10-04 - Per-shot pose files, scaffold fixtures, and a no-progress limit for delegates

- alignment-now v6: every 3D shot imported one shared `joins.ts`, so any pose edit re-rendered all of them.
  The template now keeps each shot's poses in `src/shots/poses/<id>.ts`, imported only by that shot's module;
  the joins gate loads them per shot and rejects shared pose tables and stages that import poses. The cache key
  rule itself is unchanged: it already follows imports, so the coupling was the file layout, not the cache.
- `pipeline.test.mjs` copied the whole checkout, so inside a film it tested the film's plan, lines and shots
  (5 failures in alignment-now). Fixtures now overlay a scaffold snapshot; a Pester test keeps the snapshot
  equal to the template scaffold and another runs the pipeline tests inside a film-like copy.
- screen-text read a straight apostrophe in JSX text nested inside braces as a string start ("unclosed JSX tag").
  A quote right after a letter or digit is text: no JS string can start there.
- Codex delegates stuck on a dropped connection held their claim until the hard timeout. `aos delegate` now
  kills a Codex run whose `--json` event stream is silent for `--idle` minutes (default 15) and records
  `stalled`. Claude delegates get no idle limit: `claude -p --output-format json` prints only at the end, so
  silence there is not a stall. Not yet reviewed by Codex (its window was spent); review queued.

## 2026-10-04 - Bind dated source evidence and require the actual export day

- The independent alignment-now source review found that build/QA omitted `--claims`, factual coverage was
  optional, and `currency.json` was absent from the sealed input identity. A ledger could be changed after
  rendering without invalidating QA. The reviewed guard transfer passes claims at both entry points, rejects
  empty source ledgers and unmapped factual/quoted claims, and binds the ledger bytes before sealing.
- A three-day draft research window is retained for writing, but cannot certify an export-day reopening.
  Build and QA use `--export`, which requires a successful recheck dated on the actual local day. Fresh evidence
  must precede a rebuild; changing a recheck after sealing invalidates the seal. Crossing midnight requires
  rechecking and rebuilding. Browser-only confirmation remains a manual assertion, not automated source truth.
- Build now matches QA's missing-ledger rule: only an explicit `CURRENCY=none` in qa.env declares a timeless
  topic. Ambient environment variables cannot bypass it, and a present invalid ledger still fails. Entry-point
  fixtures exercise refusals before any renderer or media dependency is reached.
- New regressions failed before transfer and run through four added Pester cases using TestDrive. Existing
  measured tests and the render cache are unchanged. Film approval, playback/listening and factual interpretation
  remain independent release requirements; passing these guards does not establish them.

## 2026-10-04 - Capacity as data: `aos capacity` (R34 gets a tool)

- **Why.** R34 was a sentence; the run that wrote it then stalled twice more on a limited vendor, and the user had to
  report Codex's remaining window by hand ("codex is at 23 percent ... make sure both agents are leverageing proprely
  both quotas"). Neither vendor can read the other's usage card, so the shared ledger now carries it: `capacity`
  events from the user or an agent (`aos capacity set`), and from quota errors in delegate receipts (the reset time is
  parsed from "try again at ..."). `aos capacity` shows each vendor as ok, low (<= 30 %), limited (until the reset),
  reset (time passed: check before a big task) or stale (older than a window), with the planning hint; `aos delegate`
  warns before giving work to a limited or low vendor. It warns, it does not refuse: the human decides.
- **Also in this change.** The render cache splits segments over 150 frames into chunks rendered by separate
  processes: alignment-now v6's S36 (306 heavy 3D frames) went white for its last 11 frames in one process while the
  same frames rendered clean in halves.

## 2026-10-04 - The alignment-now run: tools behind R27/R29/R32, and a capacity rule (R34)

- **What was missing.** R27 (currency), R29 (engagement) and R32 (render only what changed) described capabilities
  no template tool had. The alignment-now film built and exercised them, so they move into templates/video:
  `tools/checks/currency.mjs` + `tools/reverify.mjs` (a ledger with source date, retrieval date, version and an
  anchor string per item; build and QA refuse a stale or one-sided item; export day re-opens every page),
  `tools/checks/pacing.mjs` (shots per minute, longest hold, practice changes, on-screen words not in the narration,
  first hook, loudness curve; it reports, reviewers judge) and `tools/render-cached.sh` + `tools/cache/`
  (cut-to-cut segments keyed on each shot's transitive src/ imports and the input manifest's environment, one shared
  bundle, lossless concat with a frame-count check). R27 and R29 become `[check: ...]` rules wired into qa.sh.
- **Why a cache and not a faster renderer.** v4 re-rendered the whole film four times for fixes touching one or two
  shots; alignment-now's builds took 16-21 min each. The key covers transitive imports because a chapter file and a
  shared library are where stale hits hide (the regression test changes a library two imports down; a mutation to
  direct imports only is caught). Decoded frames are not bit-identical to a whole-film render (lossy H.264 encodes a
  frame differently next to a different keyframe), so equivalence is checked by frame count and PSNR, not framemd5.
- **R34, capacity.** Codex hit its 5-hour limit three times in one night and Claude scheduled work for Codex's reset
  instead of taking it; the user had to step in. The split is now read from both limits and written down at every
  gate, and a limited vendor triggers a re-split, never a wait.
- **Independent review (Codex, 2026-10-04): REQUEST CHANGES, all five acted on.** The cache key followed the
  registry, which imports every shot, so one changed shot changed every key (the wiring is now hashed, not followed;
  a regression test and a mutation prove it); dynamic `import()` was not followed; a recent first retrieval could stand
  in for the export-day check (QA now runs the gate with `--export`); a contested item could pass with a same-side
  second source (it now needs a counter from another camp); a pacing failure did not fail QA (it does now).
- **Rejected.** Running the pacing and cache tests in CI: the runners have no ffmpeg, so those Pester cases skip with
  the reason instead of pretending to pass; they run on this machine with `aos test`.
- **Fixes found on this run, at the source.** `verify.mjs` sorted sheet frames with `Number("161.png")` (NaN, so the
  "last" column was sometimes the middle frame); `word-times.py` decodes with ffmpeg because newer PyAV breaks
  faster-whisper's decoder. Reported, not changed here: `pipeline.test.mjs` copies a project but keeps its real
  plan.ts (fails in any filled project), and `screen-text.mjs` reads a straight apostrophe in JSX text as a string
  start.

## 2026-10-03 - What the AGI/ASI run taught the pipeline (rules R26-R33, a review-sheet tool)

- **Verdict that drives it.** v4 passed every technical gate and an independent Codex re-review (SHIP WITH NOTES, after a
  REVISE on v3 and a Codex source review during the first render), and still got "too stiff and not engaging enough,
  the data and references are old". Craft checks do not measure engagement or freshness, so the
  pipeline gains a currency gate (R27), a look lab with a design system for many visualization practices (R28), and an
  engagement report (R29). R18's "one medium" is overridden only when a brief asks for variety, and then only under a
  design system, because mixed media without one read as demos (alignment v1 and v2).
- **Efficacy.** Reviews must see images early (R30): the late film review found a missing mechanism explanation and a
  source-version drift that three author passes did not. Bugs found on renders get source guards, with red-first
  tests where code can detect them (R31). Rejected alternatives: a sixth author pass instead of an independent one; waiving the dome-pop motion hit.
- **Efficiency.** Where the time went: four 12-15 minute full renders, a three-hour idle gap, and a build that died
  because a script was edited while bash ran it. R26 seals builds, R32 spends the machine (awake, parallel work,
  quarter-scale review renders, render only what changed; measured once on 180 heavy frames: render concurrency 2-4
  equal, 6-10 slower, so the lever is rendering less, not rendering wider), and `templates/video/tools/review-sheets.mts`
  replaces the frame extraction that was hand-written three times. Its sampling, out-dir refusal, partial-cut and
  path-with-spaces logic are unit-tested; end to end, its S10 50 % frame of the v4 export was byte-identical to the
  hand-extracted one (the hand sheets used 25/55/88 % early and 20/50/85 % later).
- **Not changed.** R17 stays: calm easing and 0.6 s moves. The checks that measure currency and pacing are built and
  exercised in the next film (alignment-now) first and transferred only after they pass on a real film, as the joins,
  screen-text and word-cue checks were.

## 2026-10-03 - Transfer proven film checks without transferring the film

- The AGI/ASI director source at c30a7ac exercised matched-pose dissolve holds, finite camera guards,
  screen-text coverage, shared word cues, voice hash binding, private media roots and caption fallback.
  The template carries those mechanisms, with empty authored joins/timing and an unreviewed scaffold ledger;
  a new project must author/review them before production. No film shots, camera poses, text or acronym aliases
  were copied. This tightens the earlier scaffold policy: generic ledger structure is now included.
- Plan review found that the film checked voice hashes after writing two stems and divided by zero for an
  explicit empty caption. The transfer checks hashes before any stem write and omits empty-caption cues.
  Tests cover preserved stem bytes, narration fallback, explicit captions, malformed poses, held camera ends,
  JSX child text and private verifier output roots. Word measurement takes an explicitly configured existing
  local model directory, never a model download or a repository model name.
- Sound uses BEAT/FPS, including the picture's rounded frames per beat. AOS_VIDEO_MEDIA_ROOT is honoured by
  every media writer; hero verification requires explicit compositions/frame samples and its own bundle.
  Read-only shared dependencies remain shared. Build and QA gate claims, text and joins; full-size frame and
  primary-source review remain necessary. A coverage check cannot establish factual truth or listening quality.
- Node regressions are wired into aos test under both Windows PowerShell 5.1 and PowerShell 7. The sealed-export
  review remains a separate Codex verdict, saved outside the director checkout; it does not approve the film
  by inference from template tests.
- Transfer validation found filesystem URLs left percent-encoded in paths with spaces, silently bypassed
  joins/motion entry points, frame-screen scratch outside the private media root, and a forced verifier exit
  that crashed the Node loader after successful stills. CLI/fixture regressions failed before correction;
  filesystem URLs are decoded, scratch belongs to the private runner and the verifier exits naturally.
  Renderer fixtures assert AppData rejection when TestDrive is there; a private TestDrive exercises actual
  successful output paths. Those are controlled renderer tests, not new film renders.

## 2026-10-03 - Video QA binds exports to all declared render inputs

- An alignment-3 motion run rendered its proxy from edited source while examining an older export. The first
  source-only guard missed voice, music, public assets and font/config drift. The AGI/ASI run exercised a SHA256
  manifest for those inputs, dependency lockfile, voice engine and runtime metadata; added/removed files also
  invalidate it. Renderer source junctions must point at the declared checkout. It guards accidental drift,
  not malicious forgery of both the export and its manifest.
- Build checks the manifest before sealing exact MP4/SRT hashes; QA checks both inputs and those supplied files
  before costly decoding/proxy work, and inputs again before/after the proxy. Claims are recorded when present,
  so the generic scaffold does not need a film-specific claims ledger. Rule R22 calls the guard from QA.
- Eleven content/export/junction/integrity regression cases run from aos test under both shells, with fixtures
  under TestDrive. The project first failed the cases before the fix; the template integration test also failed
  before transfer. Runtime paths are resolved locally; manifests store logical labels, not machine paths.
- A private guard caller may set AOS_VIDEO_MEDIA_ROOT and AOS_REMOTION_MODULES. The existing build scripts still
  use their scaffolded default media root; the guard override alone does not move an entire production pipeline.
  Claude's independent review found mixer scratch inside the protected audio tree and an unbound dependency
  junction. Scratch now goes to renders/ and the actual app/node_modules is checked; both had failing tests
  before the fixes. Pre-proxy mismatches also write a FAIL to the report.
  No shot cache was added: the independent plan review found that invalidation complexity would cost this run
  more than it saved. Independent reusable-patch review remains a separate gate before push.

## 2026-10-02 - The video pipeline learns: rules with ids, a motion check, verdicts in the ledger

- The user judged the alignment video v1 "still very much shape-like" and, after v2, "still too shape-like and
  simple, as well as having too-snappy animations", and asked that the orchestration learn from every creation.
  Until now learning was prose appended to `video-rules.md` that nothing enforced, and nothing recorded verdicts
  or stage times.
- Rules now carry an id and a kind: `[manual]` or `[check: x]`. A check rule must have `templates/video/tools/
  checks/x.mjs` and be called from `tools/qa.sh` (a test enforces both). The first is `motion` (R17): the cause
  of "snappy" was found in code (an expo-out "house ease" over 8-16 frames in 2-4 s shots), so the check scans
  source for expo/back curves and scans a texture-free proxy render for moves that start at full speed. It is a
  locator, with labelled unit tests; on the real films it flags 19 snaps in the v2 export and none in the new hero.
- `aos video verdict` and `aos video log` record the user's words verbatim and each stage's minutes in the
  existing coordination ledger (`~\.aos\coord\ledger.jsonl`, append-safe, outside the repo), next to the delegate
  receipts. `aos video preflight` turns rules + ledger into the project's `PREFLIGHT.md` (same-family verdicts
  first, stage medians, delegate outcomes); `aos video new` writes it once. Rejected: a history file in
  `agents-home` (Codex's plan critique: every log line would dirty the config repo, and two agents could
  interleave writes).
- nar feedback is sent only when the user compares the same candidates nar scored (rule R21); a verdict on a
  finished film is not a label for an earlier choice (also from the plan critique).
- The template moved to long shots joined by dissolves (`plan.ts` overlaps, `Main.tsx` fades), soft easing
  (`src/lib/motion.ts`), a per-project `qa.env` for the length, and an audition mode that no longer overwrites
  the measured line lengths (a bug found when this video's audition clobbered `vo.json`).

## 2026-10-02 - Videos start from a template; orchestration fixes from the first accepted video

- The user accepted agi-race-2 v1 as a first result ("not that bad") and asked to improve the orchestration
  before the next video. Its pipeline was rebuilt by hand inside the project; now `templates/video` carries it
  and `aos video new <name>` scaffolds a project plus a render app in `~\.aos\video\<name>` linked to the shared
  Remotion install (about 480 MB, made once). The template's verify makes a contact sheet (the director's review
  of delegated shots was the gate that caught every visual defect), the local-model screen asks only for
  on-screen text (its slop flags were noise), and the delegate task template asks for readable code.
- The claim guard only hooks edit tools; a shell write slipped through on 2026-10-01. The contract now says to
  check `aos who` before writing with a shell. A Bash hook was rejected: it cannot tell writes from reads.
- `aos sync` now also removes MCP servers it registered earlier and the manifest dropped (built by Codex,
  reviewed by Claude; see the commit).

## 2026-10-01 - Perplexity removed: research uses the agents' free web tools

- Supersedes the Perplexity half of the entry below. In the first real use (the agi-race-2 video research) both
  `call_perplexity_computer` calls returned `insufficient_credits`. The connector exposes only "Computer" (an
  agent that spends credits on every call; `models_list` worked, so sign-in was fine). Perplexity's own credits page
  (https://www.perplexity.ai/help-center/en/articles/13838041-how-credits-work-on-perplexity; it returned 403 to
  Claude's fetcher, Codex's reviewer read it) says consumer Pro has no monthly Computer credits, only a one-time
  bonus, after which credits are bought. Bought credits are a paid dependency, which the free-stack rule excludes.
- The user asked to investigate it and remove it if it did not work. Removed from `config/mcp.json`; the
  `research` skill now describes the free method (search, then open every page a claim rests on, record opened
  vs snippet). The research for that video was done this way, and every script claim traces to an opened page.
- `aos sync` does not unregister servers dropped from the manifest, so the Claude registration is removed by
  hand (`claude mcp remove perplexity-computer --scope user`) after a Codex review. The `"agents"` field in
  `config/mcp.json` stays: it is still useful for a one-agent server.

## 2026-10-01 - Perplexity for research, Claude only; one tool catalog for every agent

- The user connected Perplexity (`perplexity-computer`, a remote HTTP MCP) and wants it available as a tool
  wherever it helps. It needs a paid Perplexity plan and "Computer" tasks spend credits, so it is the one
  deliberate exception to the free-stack rule: optional, used only where it beats `context7` and plain web
  fetches, and ask-first for long or account-touching calls (the `research` skill). Its tool names were not
  inspected when this was written; the skill tells agents to list them at first use.
- Claude only for now: Codex's quota is the scarce one and Codex already has direct web access. Codex and Pi
  hand research to Claude through `aos delegate claude` or `$cc:rescue`. A server entry in `config/mcp.json`
  may now carry `"agents": ["claude"]`; without it a server goes to both agents as before.
- Awareness is a skill, not more prompt: `tool-catalog` lists every shared skill, MCP server, CLI, media app and
  agent with the first one to try, and the global contract points to it in two lines. A test fails when a skill
  or server exists that the catalog does not mention, so the list cannot drift.
- Capability MCP servers may be added on first need (the old "only after it recurs" rule now applies to
  convenience tools only).

## 2026-10-01 - Media layer: a free stack, command lines before MCP servers

- The user wants a free stack: any paid dependency is out (DaVinci Resolve Studio, Figma, Adobe, paid image
  APIs, Ableton/REAPER) except the Claude and Codex subscriptions. Replacements: Kdenlive (projects are
  MLT text, render with `melt`), Blender, Remotion (free for individuals and up to 3 employees, a licence
  condition to revisit), Penpot, GIMP/Krita/Inkscape, LMMS/Audacity, local ComfyUI.
- Ways to drive a program, best first: a command line, a scripting API, an MCP server, computer use. The
  first two cost no context until used and work the same from Claude and Codex, so the layer installs
  programs and one shared skill (`media-tools`) documents the commands; no new MCP server was added.
- `media` is an opt-in layer: `aos install media` installs it, `aos install` / `all` does not (about
  1.3 GB). `yt-dlp` installs with `--skip-dependencies` because winget would add a second ffmpeg; Deno,
  its other dependency, is listed on its own.
- Left out on purpose: Playwright browsers, Whisper models and ComfyUI (measured, large, chosen one by
  one). Resolve's MCP servers need the paid Studio edition, so none is installed.
- FFmpeg lives here, not in `local`, for now. The video-process plan wanted it in `local`; whoever builds
  video-kit moves it and changes the test that keeps the two lists disjoint.

## 2026-10-01 - Coordination: aos-native claims, guard hooks and delegation receipts

- Research by both vendors in parallel (`docs/superpowers/research/2026-10-01-coordination-*.md`).
  Beads (27.6k stars) was not adopted: a 54 MB download, an embedded Dolt database that admits one
  writer at a time, and `bd init` rewrites AGENTS.md. MCP Agent Mail neither: Python 3.14 via uv, a
  curl|bash installer, advisory leases. A2A, swarm frameworks and Docker sandboxes: no benefit shown
  for three agents and one user. The user chose a small aos-native layer with the same semantics.
- Claims are enforced at write time by PreToolUse hooks in Claude and Codex (Codex runs hooks on the
  host, so sandboxed sessions claim too), renewed on every edit, released at session end. The guard
  fails open: a broken guard must never block all edits. A file lock, not a mutex: Local\ mutexes
  are per logon session, and the Paseo daemon and scheduled tasks may run in another.
- Delegates never commit: Codex's workspace-write sandbox keeps `.git` read-only (measured), so the
  host commits on `delegate/<id>` and runs the verify command itself; the delegate's own test claims
  stay labelled as claims in the receipt.
- The plan was attacked by Codex before any code (16 findings, 10 high; `...-plan-critique-codex.md`),
  which replaced the session mutex, the notice-only hook and in-sandbox commits.
- The cc plugin's hooks failed on every Codex run (`$PLUGIN_ROOT` is empty in PowerShell); aos now
  rewrites them to `${PLUGIN_ROOT}`, which Codex substitutes itself, and the user re-trusts them.

## 2026-10-01 - One fresh vault replaces tala, duda15 and meta-cognizione

- The user said the tala and duda15 vaults are not theirs and were mixed in by mistake. Both folders went
  to the Windows Recycle Bin (recoverable; OneDrive also keeps deleted files online for a while).
  meta-cognizione moved to `Desktop\legacy\meta-cognizione` (D:, where legacy archives normally go, was
  not connected). All three left `config/places.json` and Paseo's project list.
- The only vault is now `Desktop\vault`: created empty, with nothing copied from the old vaults. Notes
  above that name tala describe the old setup.

## 2026-10-01 - Places: one list, one inbox, filing only on confirmation

- One global Inbox, not one per vault (the user's choice). The phone captures through the aos plugin
  (no model call); photos and files go through OneDrive's share; agents file with the inbox skill.
- The repo keeps placeholders ({{desktop}}, {{projects}}, {{home}}), resolved at run time; the resolved
  list lives in ~\.aos\places.json, read by the plugin and the skill.
- aos creates only the inbox folder; a missing place is warned about, never recreated.
- The panel's file name is built on the PC; the phone never sends a path.
- The skill asks the local model (`nar_choose`) for a destination per item and always shows the whole
  proposal before moving anything. First live run (6 items, read-only): it sent five AI-video test files
  to `tala/Test ai` (confidence 0.34-0.76), which the user rejected as unrelated, and kept the acceptance
  note in the Inbox (0.99). Cause: the model sees only folder names and matched the word "ai". Adding a
  `none: ask the user` option did not help (a re-run picked `Test ai` at 0.94), so a confidence threshold
  was rejected. The skill now treats the pick as a hint: the agent checks the folder's files first, and
  a file with no text to read stays in the Inbox ("ask") unless its name clearly fits.

## 2026-09-30 - Make the local filesystem boundary explicit

- The coordinator tells local Pi that its project directory is a starting location, not a repository
  sandbox. Native tools run on the PC under the Paseo daemon's Windows account and may target any path
  that account can access; Windows ACLs and phone approval remain the boundaries.
- The coordinator repeats this verified scope on every dispatch, including turns sent to an existing
  persisted child whose original system prompt may be stale. The model must verify paths outside the
  project before changing them.

## 2026-09-30 - A bounded web search tool for Pi

- The local Pi agent now receives a small `web_search` extension through `aos sync`. It queries a
  public search endpoint and returns a bounded set of titles, snippets and source URLs.
- The existing permission gate asks before each search because network access is an external
  operation. The extension does not expose arbitrary page navigation, browser control or desktop
  input. Those remain separate Paseo capabilities that must be proven in their actual runtime.
- The coordinator discovers the extension at runtime before describing local tools to a native child,
  so it does not claim web search when the extension is absent.

## 2026-09-29 - Phone access through Paseo; Pi as the local agent

- **Paseo for the phone** (spec step 5; replaces "not installed yet" in the README): its daemon runs
  Claude Code, Codex and Pi on this PC and pairs with the Paseo Android app over an end-to-end encrypted
  relay. Installed from npm (`aos install phone`), 538 MB, of which 253 MB is the Claude Agent SDK's
  bundled Windows binary. It runs on Node 24 although Paseo pins 22.20. Its voice features download
  about 1 GB of local speech models at daemon start; they are off until the user decides (the default
  dictation model is English-only; `parakeet-tdt-0.6b-v3-int8` covers Italian).
- **Pi, not OpenCode, is the harness on the local model** (the spec named OpenCode). Pi's whole first
  request, including Paseo's added system prompt and four tools, is 2,011 tokens. OpenCode would have
  cost ~360 MB (npm installs two 180 MB Windows binaries) for a larger prompt; it stays the fallback,
  behind its own reviewed plan. Pi installs 414 MB (284 MB of it esbuild for all 26 platforms).
- **The gate Pi passed** (a Paseo session in a scratch repo, every request captured by a logging proxy
  and replayed against a 32K copy of the model, so a request the 16K model truncated would show):
  largest request 11,769 tokens against a limit of 12,288 (16K minus a 4K reply); replayed sizes equal
  the live ones for all 23 requests, so nothing was truncated; Pi compacted at 13,024 tokens down to
  6,020; `aos-agent` stayed 100% on the GPU; read, bash and write tool calls, steering mid-turn and the
  permission prompts worked; all answers were correct. Ollama's `prompt_tokens` includes the cached
  prefix (checked by replaying one request twice), and Pi records `input` = prompt minus cache, so the
  size of a request is Pi's `input + cacheRead`.
- **What aos sets for Pi** (`Sync-AosPi`, owned keys only): the `aos` provider with `aos-agent` (16K
  window, 4K output, `compat.maxTokensField: max_tokens` because Ollama 0.34 ignores
  `max_completion_tokens`, no `developer` role); compaction on, with reserve and kept-recent tokens of
  4096 for that model (Pi's defaults, 16384 and 20000, exceed the window); install telemetry off.
- **Permission gate**: Pi has no permission prompts and Paseo adds none for it, so an aos extension asks
  before every tool that is not read-only; Paseo shows the question on the phone. It blocks on Deny, on
  a dismissed question and without a UI. The block message says "NOT RUN" plainly: the 4B model read
  "Denied by the user" as the command's output and claimed success. Every bash call asks, which is safe
  but tedious from a phone (six questions for one grep-heavy answer). Paseo's CLI approves a Pi question
  only with an answer: `paseo permit allow <agent> <id> --input '{"answers":{"q":"Allow"}}'`.
- **No MCP servers for the local agent** in this version: every tool schema costs prompt in a 16K window.
- **aos-agent** (the default with `num_ctx 16384`): its state is read from Ollama, comparing the whole
  normalized modelfile with the default's, not kept as bookkeeping; `aos local adopt` and `aos sync`
  rebuild it. The 2026-09-28 line "a 32K context fits the 6 GB GPU fully" was measured on MiniCPM5-2B;
  for qwen3.5:4b, 16K runs 100% on the GPU (3.3-3.5 GB) and 32K 77%.
- **Reviews**: the plan went through two cross-vendor rounds (Claude first, then Codex blind: 12 and 9
  findings); all accepted after checking each against the code, except one correction: Codex's reading
  that Ollama reports cached tokens outside `prompt_tokens` did not hold when measured.

## 2026-09-28 - Local model and the nar tools

- **Bake-off on this laptop** (`aos nar eval`: 17 tool-call cases, 30 single-pass choices, temperature 0;
  gated on tool success, choice accuracy and calibration error, hard limits 100% GPU and 15 tokens/s):

  | Model | Tool calls | Choice accuracy | ECE | Tokens/s | GPU |
  |---|---|---|---|---|---|
  | openbmb/minicpm5-2b:q8_0 | 65% | 93% | 0.110 | 61 | 100% |
  | qwen3.5:4b | 100% | 97% | 0.035 | 44-45 | 100% |
  | granite4.2:3b | 94% | 83% | 0.082 | 62 | 100% |

- **Default: qwen3.5:4b** (`aos local adopt`), better than MiniCPM5-2B on all three gated metrics;
  granite4.2:3b was refused against it. MiniCPM5-2B's published function-calling lead did not hold
  here: its Ollama package shows no tool-calling template. Qwen3.5-4B also reads images.
- **nar**: one forward pass per choice (Ollama logprobs); temperature calibration per model and task
  type; a refit is promoted only if Brier score and ECE on held-out calls are both no worse; OS file
  locks; data in ~\.aos\nar. Registered in Claude Code and Codex; `aos status` checks it.
- **No Codex profile for the local model.** Codex's own prompt is ~45K tokens; Ollama's default context
  is 4K, a 32K context fits the 6 GB GPU fully and 64K spills 27% to the CPU, and a small model cannot
  drive Codex's agent loop well anyway. An agent harness on the local model is chosen by prompt size in
  the OpenCode/Paseo plan.
- **Codex reviewed the plan (14 findings) and the code (2 new Important findings plus 5 it had flagged
  while transcribing); all fixed test-first.** Two were left as minor: model tags that differ only in
  `/`, `:` or `_` would share a calibrator, and `nar eval` with a bare tag (`foo` for `foo:latest`)
  reports it off the GPU.
- **This connection stalls Ollama's downloads** (TLS handshake timeouts to its storage host): a hung
  `ollama pull` shows 0 bytes for minutes; stopping and re-running it resumes the partial download.

## 2026-09-28 - Shared state lives under the home folder; phone access

- **The Claude desktop app redirects new AppData files into its own package.** It is an MSIX
  package, and a new file or folder that it or anything it launches creates under `AppData` lands
  in `AppData\Local\Packages\Claude_...\LocalCache`, visible only to that app's processes. Found
  there after a setup run from Claude shells: the Codex installer's PATH folder, the npm globals
  (`ccusage`), the reference clones and a Codex worktree. In a process started outside the package
  (through WMI), `codex` and `ccusage` were not found while `aos status` inside the app was all
  green. Existing AppData files, the home folder, Documents, Temp, the registry PATH and winget
  installs were not affected here (it depends on each package's declarations; the Codex app is MSIX too).
- **Correction to 2026-09-27 ("PowerShell 7 is the MSI edition").** The Store pwsh did not fail to
  see those folders because it is MSIX: they only ever existed in the Claude app's private view.
  The MSI pin stays for the same mechanism: whatever the Store pwsh installs under AppData would
  stay private to it.
- **So shared state moved to the home folder.** The user PATH also names
  `~\.codex\packages\standalone\current\bin` (the Codex installer's own junction target; `aos
  status` warns if that layout disappears), npm globals use the prefix `~\.npm-global`, reference
  clones live in `~\.aos\refs`, and the agents' contract says never to put tools, clones or
  worktrees under AppData. `aos install engines` now checks for the standalone Codex CLI itself:
  the Codex app's bundled `codex.exe` on its own PATH used to count as installed.
- **`aos secret` uses DPAPI files instead of SecretStore.** SecretManagement and SecretStore keep
  their vault registry and data under `%LOCALAPPDATA%`, so each app would have had its own, empty
  vault. Now each key is a DPAPI blob (encrypted to your Windows login) in `~\.aos\secrets`: the
  same store from every app and terminal and both PowerShell versions, with no Gallery modules.
  Commands inside Codex's sandbox run as separate Windows users and cannot decrypt them, which is
  intended: a command that needs a key runs as you. Credential Manager was the alternative
  (OS-managed, visible in Control Panel), not taken because it needs P/Invoke that Pester can't
  exercise. Astra's plan review preferred DPAPI files and added: reject Windows device names (CON,
  NUL, COM1, ...) as key names, and replace files atomically.
- **Phone access.** Claude: the Claude app connects new sessions to Remote Control, so they show up
  in the Claude mobile app, and `aos remote` runs `claude remote-control --capacity 2` so the phone
  can also start sessions on this PC (2, not the default 32: same-dir sessions share files, and the
  plans allow 2 agents per vendor; Astra's finding). Codex: the Codex app's Settings > Connections >
  Control this PC, paired with the ChatGPT Android app (the PC must stay awake, online and
  unlocked). Astra caught that the first plan offered only Codex cloud, which cannot see this PC,
  its unpushed work or its keys. `codex remote-control` (a CLI daemon) is experimental and unused.
  Cloud sessions stay for when the PC is off; they see only what was pushed.
- **`claude remote-control --help` never exits** (2.1.283): it prints the help and keeps running.
  Don't call it from scripts; it stalled Astra's review until it was stopped.
- **Codex's Windows sandbox runs commands as two local users** (`CodexSandboxOffline`,
  `CodexSandboxOnline`), gave them read access to `OneDrive`, `~\.codex` and `~\.claude` and write
  access to this repo, and denies them `.git`. That is its design; nothing to undo.

## 2026-09-27 - Finishing the setup together with GPT-6-Astra

- **Bridges proven both ways.** Claude -> Codex: `codex:setup` reports ready (codex-cli 0.157.1,
  ChatGPT login verified). Codex -> Claude: the cc plugin's companion got an answer from Claude.
  Inside a Codex session the `$cc:` commands ask once for network access (a sandbox escalation);
  `codex exec` with approvals set to "never" can't grant that, so a scripted test of `$cc:rescue`
  from inside Codex fails by design, not because the bridge is broken.
- **`$cc:setup` trusted the cc plugin's 4 Codex hooks.** That is its documented job; revoke under
  `/hooks` in Codex if ever wanted.
- **Superpowers in Codex comes from the CLI** (`codex plugin add superpowers@openai-curated-remote`,
  in the bridges layer), so the app's Plugins screen isn't needed.
- **Windows PowerShell 5.1 gets no profile while its policy blocks scripts.** The effective policy
  here is Restricted, so the profile only printed an error at every start. aos lives in pwsh;
  changing the 5.1 policy is the user's decision, not the setup's.
- **`codex exec` from Git Bash needs `</dev/null`.** With stdin left open it waits for "additional
  input" forever; the Bash form of the review command now closes stdin.
- **Astra's second review: two medium findings, both fixed and sandbox-tested.** An MSIX copy of a
  package pinned to MSI reported ok (now a migration warning, also in `aos update`); the skills
  migration read `synced\` from the current repo instead of the old link's real target (now staged
  from the real target first, stopping on failure). Claude's own pre-review added two: a link of
  the user's own is left alone, and links to skills that left the repo are removed.
- **GitHub login uses the device-code flow.** This connection has short outage windows (9 of 20
  requests failed in one minute, 0 of 20 in the next), and `gh` aborts on its first failed poll.
- **Codex plugins are detected with `codex plugin list`.** Plugins from OpenAI's remote catalog
  (superpowers) never appear in `config.toml`, so `aos status` reported Superpowers missing while
  Codex had it enabled and loaded (confirmed by asking GPT-6-Astra after the app restart).

## 2026-09-27 - Fixes found while installing

- **PowerShell 7 is the MSI edition.** winget's default for `Microsoft.PowerShell` is now the
  MSIX package, and that packaged edition could not see folders under AppData that other
  installers created (`codex`, the npm globals, VS Code data): `Test-Path` returned False for
  folders that exist. `packages.json` pins `installerType: wix`, and `aos status` warns if
  `pwsh` ever resolves to the packaged edition again.
- **`~/.claude/skills` is Claude's folder, not a link.** The Claude desktop app syncs account
  skills (docx, pdf, ...) into `~/.claude/skills/synced`; with the whole folder linked into the
  repo, 208 app files landed in git and OneDrive. Now only our skills are linked, one junction
  per skill (Claude discovers them; verified), and the app's folder stays outside the repo.
  `~/.agents` is still one junction for Codex.
- **Reference clones use `<shelf>\<owner>\<name>`**: `anthropics/skills` and `openai/skills`
  collided on `official\skills`, and the second was silently "pulled" instead of cloned.
- **Every entry point refreshes PATH from the registry** (`aos refs` and `aos new` did not, so a
  terminal opened before the Git install reported git as missing).

## 2026-09-27 - Verified from inside both agents after install

Each agent was asked what it had actually loaded (not what files exist):
- Codex (`gpt-6-astra --profile review`): heading "Global agent contract", `handoff` and
  `second-opinion` skills, `cc:review`, read-only sandbox, high effort. All as designed.
- Claude Code (Pro): same heading, both skills, superpowers. But `/codex:review` was **not**
  visible to the model: the plugin marks `review`, `adversarial-review` and `transfer` with
  `disable-model-invocation: true`. They are commands for the user to type. The contract, the
  skills and CLAUDE.md now send the agent to `codex exec --profile review` for its own reviews
  and `/codex:rescue` / the `codex-rescue` subagent for delegation, and only suggest the rest.

**Restart apps that predate the install.** The codex plugin's hooks run `node`; a process
started before Node.js was installed (the Claude Desktop app, open terminals, the Codex app)
keeps the old PATH, and the hooks fail with "node: command not found" until it restarts.

## 2026-09-27 - GPT-6-Astra reviewed the setup before it was applied

Codex (`gpt-6-astra`, read-only sandbox) reviewed the repo before it touched any config: the
setup's own second-opinion pattern, used on itself. Four findings, each checked, all accepted:

1. **High.** `[profiles.*]` tables in `config.toml` are ignored since Codex 0.134; `--profile NAME`
   layers `~/.codex/NAME.config.toml`. Confirmed by `codex --help` (0.157.1) and OpenAI's config
   docs. Profiles are now three files, and aos no longer writes to `config.toml` at all. This
   supersedes the Codex half of "Merge, never overwrite" below.
2. **Medium.** Plugin detection matched text, so a disabled or merely cached plugin read as
   installed. It now requires `enabled = true` in the plugin's own `[plugins."id"]` table.
3. **Medium.** MCP sync checked names only, so an edited URL stayed stale while reporting ok. It
   now re-adds a server whose registration doesn't match `config/mcp.json`.
4. **Medium.** The `second-opinion` shell fallback reviewed only uncommitted work and omitted the
   goal. It now carries the goal and an explicit scope (commit range, working tree or plan file).

Claude had flagged only #2 beforehand, and only as unverified. #1 is exactly the kind of
vendor-internal fact a second vendor is for.

## 2026-09-27 - Home base is the Desktop; Codex via OpenAI's installer

**The Desktop is the hub** (your call). The repo lives at `Desktop\agentic-os`, new projects in
`Desktop\1-Projects` (the numbering of your pre-reset Desktop, kept in `D:\legacy`). The Desktop
is redirected to OneDrive, which is what makes it survive a reset. The cost: OneDrive uploads
everything in it, including `.git` internals, `node_modules` and `.venv`. So re-creatable bulk
stays out: reference clones go to `%LOCALAPPDATA%\agentic-os\refs`. A private GitHub remote
remains the real backup for code; OneDrive is not version control.

**Codex CLI comes from OpenAI's own installer, not winget.** `winget install OpenAI.Codex`
worked but left no `codex` command: without Developer Mode, winget cannot create the
symlinked alias, and the executable is named `codex-x86_64-pc-windows-msvc.exe`. The official
`install.ps1` (releases.openai.com) installs `codex.exe` with its helper binaries in the layout
it expects, puts it on the user PATH and updates itself. The winget copy was removed, and so
was the PATH entry it left behind.

**Claude Code's folder added to the user PATH by aos.** The native installer put `claude.exe` in
`~\.local\bin` but reported that folder was not on PATH and asked for a manual fix. `aos`
adds it (user scope only) and notifies Windows so new terminals see it.

## 2026-09-27 - Initial build (machine freshly reset)

**Execution stays inside the vendors' own agents.** The knowledge base recorded on 2026-07-26
that the old orchestration layer lost to the harness: a CLI subprocess gets a prompt, while a
session inside Claude Code or Codex gets about 37.5k tokens of assembled context. So this setup
builds no control plane. It shares configuration and wires the two agents to each other.
Source: `D:\knowledge-base\notes\decision-orchestration-parked.md`.

**Official bridges replace `rig`.** OpenAI's `codex-plugin-cc` (Claude Code -> Codex: review,
adversarial review, rescue, transfer, review gate) and `sendbird/cc-plugin-codex` (Codex ->
Claude, via the official `claude` binary) cover rig's review, test and cold-read modules, and
they are maintained by others. What rig got right survives as rules in `AGENTS.md` and in the
`second-opinion` skill: the reviewer must be a different vendor; verdicts are never blended;
a dead reviewer is not a clean result; the other vendor writes the test.
Sources: https://github.com/openai/codex-plugin-cc, https://github.com/sendbird/cc-plugin-codex,
`D:\legacy\1-Projects\rig\`.

**The Claude subscription is used only by Anthropic's own software.** Since the January to April
2026 enforcement, Claude Pro/Max logins are allowed only in Claude Code, Claude Desktop and
claude.ai. Tools that call the official `claude` binary are fine; tools that reuse the login
token (OpenClaw, OpenCode, Hermes's proxy mode) are not. OpenAI explicitly allows the ChatGPT
login in third-party tools. So anything always-on runs on ChatGPT or API keys, and reaches
Claude only through the `claude` CLI.
Sources: https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/,
https://docs.openclaw.ai/providers/openai.

**One AGENTS.md, imported by Claude.** Claude Code reads `AGENTS.md` natively since v2.1.277
(2026-09-18), but only for a project with no `CLAUDE.md`, and on some versions only with
telemetry on. The global contract is therefore imported explicitly (`@~/.agents/AGENTS.md` in
`~/.claude/CLAUDE.md`), which works regardless of version or setting. Codex has no import
mechanism for its global file, so `aos sync` keeps a generated copy in `~/.codex/AGENTS.md`
and `aos status` flags drift.
Sources: https://code.claude.com/docs/en/memory, https://korben.info/en/claude-code-privacy-agents-md.html.

**One skills folder, two links.** Codex reads user skills from `~/.agents/skills`; Claude Code
from `~/.claude/skills`. Both are directory junctions to `agents-home/skills` (junctions need no
admin rights or Developer Mode and work from C: to D:). Your KB found that a hand-kept mirror
copy for the second vendor goes stale; a link can't.
Source: https://learn.chatgpt.com/docs/build-skills, `D:\knowledge-base\notes\skills-convention.md`.

**MCP: one server to start.** Context7 (remote, no local process) for current library docs in
both agents. GitHub goes through `gh`; browsers through each agent's built-in browser tools. Per
the KB ruling of 2026-07-19: a server earns its place by removing a real cost, one at a time.

**Merge, never overwrite.** The Codex desktop app owns `~/.codex/config.toml` (plugins,
marketplaces, its own MCP runtime). aos writes only a marked block of whole tables at the end:
a top-level key appended there would silently land inside the preceding table. Claude settings
are deep-merged (arrays unioned) with a backup first.

**Secrets in the Windows secret store.** The z.ai key sat in plaintext in the PowerShell profile
(and `APIS storage.*` files existed on D:). SecretManagement + SecretStore (Microsoft modules),
set up only on first `aos secret set`, keep keys encrypted per user without a password
prompt. That protects against the failure that actually happened (keys in plaintext files and
backups), not against malware running as you.

**Left out, on purpose:** GLM and OpenRouter (you chose to focus on Claude + GPT); Hermes and
other always-on agents; Paseo; ruflo and BMAD (they compete to own the workflow and conflict
with superpowers); bulk installs of everything-claude-code or subagent packs (they cost
always-loaded context). Revisit each one only against a need that has repeated.
