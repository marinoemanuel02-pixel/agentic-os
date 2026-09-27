# Decisions

Why agentic-os is shaped the way it is. Newest first. When a decision changes, add an entry;
don't rewrite the old one: the record of what was rejected is the part that ages best.

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
