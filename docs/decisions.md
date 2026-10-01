# Decisions

Why agentic-os is shaped the way it is. Newest first. When a decision changes, add an entry;
don't rewrite the old one: the record of what was rejected is the part that ages best.

## 2026-10-01 - Places: one list, one inbox, filing only on confirmation

- One global Inbox, not one per vault (the user's choice). The phone captures through the aos plugin
  (no model call); photos and files go through OneDrive's share; agents file with the inbox skill.
- The repo keeps placeholders ({{desktop}}, {{projects}}, {{home}}), resolved at run time; the resolved
  list lives in ~\.aos\places.json, read by the plugin and the skill.
- aos creates only the inbox folder; a missing place is warned about, never recreated.
- The panel's file name is built on the PC; the phone never sends a path.
- The skill asks the local model (`nar_choose`) for a destination per item and always shows the whole
  proposal before moving anything. First live run (6 items, read-only): it sent every AI-video test to
  `tala/Test ai` (confidence 0.34-0.76) and kept the acceptance note in the Inbox (0.99).

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
