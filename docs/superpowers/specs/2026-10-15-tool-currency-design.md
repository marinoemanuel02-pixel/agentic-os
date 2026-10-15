# Tool currency: knowing what tools exist before building (design)

Date: 2026-10-15. Status: draft written after the user approved the three-part direction in conversation;
awaiting Codex critique, then the user's review of this file.
Author: Claude (session 9884029f). Branch `tool-currency-spec` (worktree `~/.aos/worktrees/agentic-os-tool-currency`),
cut from `phone-orchestration-design` at 33ee9cb. Nothing here is implemented.

## Why

The user, 2026-10-15, verbatim: "all the tools must used for the builds must be factored in since they change
significantly the result and approach in development, there are probably tons more that can be added and new ones
get released everyday and i am not sure whether the agents working on the projects are handling this correctly, many
people have been using similar harnesses so there should be precedent to check against before." And: "THIS SPACE IS
MOVING REALLY FAST, PEOPLE ARE REVERSE ENGENIEERING MANY PAID SOFTWARES, CUSTOM MPCPs GET RELEASED and TOOLS FOR
CREATING CUSTOM ONES AND CONVERTING INTO MCPs SPECIFIC TOOLS WITHOUT ONES".

Approved in conversation the same day: all three parts below (the map, the ledger and gate, the vetting tiers), as a
written spec in a worktree. Everything in "Open questions" is a default the user has not yet confirmed.

## What the audit found (read 2026-10-15)

| Finding | Where |
|---|---|
| The tool catalog lists what is installed, by hand. Its MCP table has two servers (`context7`, `nar`); this machine also runs the Blender add-on server, a Playwright server, Chrome and computer-use tools, Google connectors and a registry-search tool. | `agents-home/skills/tool-catalog/SKILL.md`; `claude mcp list`, `codex mcp list` |
| The catalog's own rule 2 makes the agent passive: "if nothing fits, say what is missing ... adding one is the user's call". Nothing says to look for a tool that exists but is not installed. | same file |
| The catalog test only proves that every shared skill and every `config/mcp.json` server is mentioned. It cannot see anything installed outside aos. | `tests/aos.Tests.ps1` ("Shared tool awareness") |
| Discovery is passive: awesome-lists are cloned on the `catalogs` shelf, checked 2026-09-27, and no process reads them. | `refs/repos.json` |
| The runtime search-and-add idea (Docker MCP gateway) exists only as a plan: not in `config/mcp.json`, no decision entry. | `docs/superpowers/plans/2026-09-29-tool-gateway.md` |
| Facts have a currency gate (R27: dated primary sources, re-verified on export day). Tools have only R08 (one real test call when a tool is added). | `~/.agents/video/video-rules.md`, `templates/video/tools/checks/currency.mjs` |
| 2 of 9 film retros mention tools at all (both the Blender MCP films); none records what alternatives existed or why one was chosen. There is nowhere to record it, so it cannot be checked. | `~/1-Projects/videos/*/retro.md` |
| Tool discovery so far came from the user: "Blender MCP set up first"; the "add only after it recurs" rule had to be rejected by the user (2026-10-01). | memory notes `capability-tools-skip-recurrence-rule`, `video-cant-escape-ai-blender-mcp` |
| One registered server is unpinned: the Playwright plugin runs `npx @playwright/mcp@latest`. | `claude mcp list` |
| `codex mcp list --json` prints environment variable values in the clear (the table form masks them). Any inventory built on it must redact. | checked on this machine |

Not an audit finding, a limit: absent retro notes do not prove no agent ever looked. They prove it cannot be checked.

## Precedent checked

"Checked" says how: opened = the page was read; live = called from this machine; snippet = a search result only, not
relied on for a decision.

| Claim | Source | Checked |
|---|---|---|
| Loading every tool schema up front is the problem: 5 servers / 58 tools is about 55K tokens before work starts; tool search cut that by about 85% and raised selection accuracy (Opus 4: 49% to 74%) | Anthropic, "Advanced tool use" (anthropic.com/engineering/advanced-tool-use) | opened |
| Claude Code ships tool search on by default, and tells Claude which servers failed to connect | code.claude.com/docs/en/mcp (page truncated at 100K characters; the tool-search configuration section was not read) | opened, partly |
| Docker Dynamic MCP: `mcp-find` / `mcp-add`, servers last one session only, experimental, catalog built and signed by Docker | docs.docker.com/ai/mcp-catalog-and-toolkit/dynamic-mcp/ | opened |
| The official MCP Registry is a preview with the v0.1 API frozen (README, 2025-10-24); it verifies namespace ownership (GitHub OAuth/OIDC, DNS/HTTP challenge), not code | github.com/modelcontextprotocol/registry | opened |
| `GET registry.modelcontextprotocol.io/v0.1/servers?search=<q>&limit=<n>` and the `/v0/` path both return 200 and JSON; entries carry `server.name`, `description`, `remotes` / `packages`, `repository`, and `_meta."io.modelcontextprotocol.registry/official"` with `isLatest`, `publishedAt`; old versions are returned too | the registry | live, 2026-10-15 |
| Auto-converted OpenAPI servers perform worse than curated ones; FastMCP offers `route_maps` with `EXCLUDE` to allow-list routes | gofastmcp.com/integrations/openapi | opened |
| Claude Code documents a server scaffold plugin (`/mcp-server-dev:build-mcp-server`); it is not installed here | code.claude.com/docs/en/mcp | opened |
| A fake npm package, `postmark-mcp` v1.0.16 (2025-09-17), BCC'd every email to the attacker; 1,643 downloads; the vendor said it was never theirs | The Hacker News, 2025-09-29 | opened (fetch gave 403; read in the built-in browser) |
| Codex has no documented tool-search feature | developers.openai.com/codex/mcp via search | snippet; not found, so no design here depends on one |
| Generators exist for OpenAPI, CLI help text and HAR captures (mcp-gen, mcpgen, any-cli-mcp-server, HAR-MCP, Stainless) | directory listings | snippet |
| A 2026 impersonation campaign cloned official MCP repos to deliver an infostealer; most public servers use static keys | search result | snippet; not relied on |

No published precedent was found for a per-project tool ledger. Part 2 is by analogy to the user's own R27, not copied
practice.

## Goals and non-goals

Goals: (1) an agent can see what is installed, per vendor, and look for what is not, in one command each; (2) every
build records, per need, what was searched, what was found, what was chosen and why, dated, and a gate refuses a
build that skipped it; (3) any tool that is not the vendor's own passes a vetting gate sized to its risk before it is
installed; (4) the process costs almost no always-loaded context and works the same from Claude and Codex.

Non-goals: an MCP server for tool discovery (schemas load on every request; a command line does the job, decisions
2026-10-01); the Docker gateway now (see Rejected); auto-installing anything (installs keep needing the user's yes with
source and measured size); ranking tools by stars or popularity; cracked, pirated or licence-circumventing software
(refused: "free" means free legitimately); the local Pi agent (no MCP servers by decision 2026-09-29); retrofitting
films already made.

## Design

Principles: command line first, then skill, then server (unchanged). Discovery is not installation. A ledger is a
locator, not a judge: it proves a search was recorded and a vetting was done, not that either was good; independent
review judges (same limit as the currency gate). Nothing new is written into `~/.claude` or `~/.codex`.

### 1. The map: `aos tools`

**`aos tools`** prints, per vendor, what is live: MCP servers (name, transport, enabled, command file name or url,
pin state), plugins (id, version, enabled), shared skills (from `agents-home/skills`). Sources, all read-only:
`claude mcp list` (text) and `claude plugin list --json`; `codex mcp list --json` and `codex plugin list` (text; it
lists a whole marketplace, so only rows with status "installed" count). Rules:

- **Redaction is part of the design.** Print only name, transport, enabled, and for a stdio server the command's file
  name plus the package spec when the command is `npx`, `uvx` or `pipx`. Never print `env`, headers, `cwd` or other
  arguments (an argument can carry a key). A test feeds a fixture with a fake secret in each field and fails if it
  appears in the output.
- **Pin state** is `pinned` (exact version, digest or local path), `floating` (`@latest`, no version) or `n/a` (remote
  url). `floating` is a warning line, not an error (the Playwright plugin is the first).
- **Failure is not "none".** A source that errors, times out or cannot be parsed prints `unavailable: <source>: <why>`
  and the command exits non-zero. `claude mcp list` health-checks every server (about 7 s measured) and has no
  options at all besides help (checked), so its text is parsed, as is `codex plugin list`; a line that does not parse is
  listed as `unparsed: <line>` rather than dropped.
- **Cache.** The result is written to `~/.aos/state/tools-inventory.json` (outside the repo, never committed) and reused
  for 24 hours unless `--refresh`. A snapshot in a committed skill was rejected (see Rejected).
- Inside a Claude session the live view of deferred tools is the session's own `ToolSearch`; `aos tools` is for the
  offline view, for Codex, and for anything installed outside the session.

**`aos tools find <need words>`** looks for what is not installed:

1. The official registry: `GET /v0.1/servers?search=<words>&limit=20`, newest version only (`isLatest`), each row as
   name, description, remote or package, repository, published date, and a namespace line (`io.github.<account>` =
   GitHub account ownership; a reverse-DNS domain = domain ownership; both are ownership, not safety). Follows
   `nextCursor` up to three pages. The schema is a preview: unknown shapes print `unparsed`, never a silent empty.
2. The local awesome-lists on the `catalogs` shelf (`rg -i` over `~/.aos/refs`), offline.
3. A fixed last line: registry coverage is partial; also search the web for the need (the `research` skill) and ask the
   user's installed Claude/Codex plugin search where available.

A registry or network failure prints `registry unreachable` and exits non-zero. `find` installs nothing and makes no
request carrying project content: the query is the need words only.

### 2. The ledger and the gate

Each project keeps `tools.json` (next to `currency.json`). Shape, one entry per capability the build needs:

```json
{
  "policy": {"searchWithinDays": 30},
  "needs": [{
    "id": "N01", "need": "drive Blender scenes live and read back stills", "stage": "production",
    "searches": [{"source": "registry", "query": "blender", "date": "2026-10-15", "note": "what came back"}],
    "candidates": [{"name": "...", "kind": "cli|skill|mcp|plugin|library|service|model|generated",
                    "tier": 0, "origin": "url", "publisher": "...", "licence": "...", "cost": "free",
                    "installedBy": "aos|plugin|user|agent"}],
    "chosen": "<candidate name> | none", "why": "...",
    "vetting": {"version": "exact", "pinned": true, "codeReview": "read|sandboxed|vendor",
                "secrets": "none|aos-secret:<name>", "consent": {"date": "", "size": "", "words": ""},
                "testCall": {"date": "", "what": "", "result": "ok"},
                "tools": {"count": 0, "schemaChars": 0},
                "terms": "", "approval": "", "fallback": ""}
  }]
}
```

**`aos tools check <project> [--fresh] [--today YYYY-MM-DD]`** reports every defect in one pass (like
`currency.mjs`). Errors:

- Structure: missing field, duplicate id, bad date, future date, unknown kind or tier, empty `needs` (unless
  `policy.noNewTools` holds a reason).
- A need with no search whose `source` is `registry` or `web`. `installed`, `refs` and `user` searches are allowed
  but cannot be the only ones: "I looked at what I already have" must not pass for a search.
- `--fresh` (run at the brief gate and again when production starts): the newest `registry` or `web` search is older
  than `policy.searchWithinDays` (default 30). Build and QA do not pass `--fresh`; they must not fail a long project on
  age, only on a missing vetting.
- A chosen candidate that is not `free`, has no licence, no exact version, no `testCall` with result `ok` (R08), or, when
  `installedBy` is `agent`, no `consent` (the existing install rule: source and measured size, the user's yes).
- Tier rules from section 3 (enforced from rollout slice 3; slices 1-2 check only the rows above).
- `chosen: none` without `why`.

**Wiring.** Exactly one implementation, a dependency-free Node module with `node --test` tests, so it runs inside the
isolated video render roots and from Codex; `aos tools check` calls it. The video template gets: `tools.json`
scaffolded by `aos video new`, a `## Tools` pointer in `brief.md`, the check called from `build.sh` and `qa.sh` beside
the currency check, a `## Tools` section in `retro.md` ("new since the last film"; "used but not in the ledger"), a line
in `PREFLIGHT.md` ("tool search last run N days ago"), and one new rule in `video-rules.md`. The rule's id is taken at
merge as the next free one: the unmerged branch `video-blender-shorts` already uses R41-R52, so a number chosen now
would collide. Other projects: `templates/project/AGENTS.md` gets a two-line pointer; the check is advisory there.

**Where the work goes when nothing is found.** In order: a script or command-line wrapper written for the project (no
context cost); a generated MCP server only when the tool must hold state across calls in a session (the Blender case);
never a hand-written server for something a command line reaches.

### 3. Vetting tiers

| Tier | What it is | Extra requirements (on top of: free, licence recorded, exact version, one real test call, install consent with measured size) |
|---|---|---|
| 0 | The software vendor's own tool, or one aos or a plugin marketplace already installs. The vendor identity is confirmed from the vendor's own page, not a search result. | none |
| 1 | Community open source: a server, skill, CLI or library by someone else | version or commit pinned (no `@latest`, no auto-update; an upgrade is a new vetting); code read or run sandboxed first; secrets stated and passed only through `aos secret`; tool count and schema size recorded |
| 2 | Generated by us from an OpenAPI spec, CLI help text or a HAR capture | all of tier 1, plus: the generated source lives in the project repo and is reviewed as our code; routes allow-listed (read-only first; a catch-all exclude); a fixture test per exposed tool; regenerated, not patched, when the spec changes; HAR files redacted of cookies and tokens before they are kept |
| 3 | Unofficial or reverse-engineered access to a paid or private service | all of tier 2, plus: the licence or terms clause checked and written down; the user's approval in his own words, per tool per project; a recorded fallback, because the film or build must not depend only on something a site change can break; never the user's account credentials in an unofficial tool |

Why these gates: the registry confirms who owns a name, not what the code does; the postmark-mcp backdoor was one line
added in v1.0.16 to a copy of a legitimate library, which is why pinning and a re-vetting on upgrade matter more than a
first read; clones of official repos are the known impersonation route, which is why the publisher is checked
against the vendor's own page. Tier 3 is allowed to exist because the user named this space on purpose; it stops at the
user because it can touch a third party's terms and the free-stack rule.

### 4. What changes in always-loaded text

`agents-home/AGENTS.md` (loaded on every request by both agents): one sentence changes, no net new line. Today: "Before
saying a capability is missing, or choosing among tools, read the `tool-catalog` skill: it lists every skill, MCP
server, CLI, media app and agent here, and which one to try first." It gains: "then `aos tools find <need>` before
concluding nothing exists." The `tool-catalog` skill: rule 2 becomes "If nothing fits, run `aos tools find <need>`, then
say what is missing; installing needs the user's yes"; a row for `aos tools`; the MCP table gains a note that
`aos tools` shows what aos does not own (plugins, connectors, app-owned servers). Its existing test stays and gains a
check that `aos tools` is named. No server, no skill is added: the cost is the one command line.

## Failure handling

- Registry down or reshaped: `find` says so and exits non-zero; the agent falls back to web search and records
  `source: web`. Never "no candidates found" from a failed call (global contract, rule 5).
- Inventory source missing (vendor CLI not installed): `unavailable`, not an empty list.
- A ledger entry that cites a tool the inventory does not show: the check warns (it may be a different machine).
- A tool that changes after pinning: not detected by design; pinning makes an upgrade a deliberate act that goes
  through vetting again.

## Testing and success criteria

Each criterion is checkable and each new test must be seen failing before the code (contract, rule 3). Tests follow the
repo's: Pester for `aos` (both shells; `$TestDrive`; no real profile or network, the vendor CLIs and the registry
mocked through `Invoke-AosCapture` and a fixture), `node --test` for the ledger module. Tests are best written by
Codex (project rule); Codex's sandbox has no Pester 5, so the host runs them.

1. `aos tools` against fixtures for both vendors lists every server and plugin, marks `floating` for `@latest`, prints
   `unavailable` for a failing source, and never prints a planted secret from `env`, headers or args.
2. `aos tools find` against a recorded registry response returns only `isLatest` rows, one per name, with the namespace
   line, and prints `registry unreachable` (exit non-zero) on a failed call.
3. `aos tools check` fails on each defect class above with a fixture per class and passes a complete ledger,
   including: `--fresh` fails on a 31-day-old search and not on a 29-day-old one; a ledger whose only searches are
   `installed` fails.
4. The video template's build and QA refuse a new project without a valid `tools.json`; a project made before this
   change is unaffected.
5. `aos test` passes in both shells; ASCII and parse checks pass; a second `aos sync` still changes nothing.
6. **Backtest, the evidence it is worth having:** run `aos tools find` for the capability needs of one finished film
   (`cant-escape-ai`) and list which candidates it surfaces that the film did not use or know about. Reported
   honestly: if it surfaces nothing useful, the gate is overhead and this spec is revisited before merge.
7. **Sunset check after three films:** the ledger's candidates adopted, against the minutes the `brief` stage spent on
   it (`aos video log`). If nothing was adopted and the cost is not small, the gate is loosened to advisory.

## Rollout (each slice merges on its own)

1. `aos tools` and `aos tools find`, the catalog and global-contract edit, tests, README, decision entry. Useful alone.
2. The ledger module, `aos tools check`, the video template wiring and rule, the retro and PREFLIGHT lines.
3. The vetting tiers as ledger rules (tier fields enforced) and the `templates/project` pointer.

## Rejected

- **Docker MCP gateway now.** Catalog is Docker's own curated set, so it misses the long tail and anything
  community-made or reverse-engineered; added servers last one session; experimental; Docker Desktop required; Codex
  support unknown. Revisit if the registry search misses things the user wants after three films.
- **A generated inventory block committed in the skill.** Connectors connect and disconnect, so the file would change
  without anyone editing it; decisions 2026-10-02 already rejected a history file in `agents-home` for the same reason
  (it dirties the config repo and two agents can interleave writes). The cache lives in `~/.aos/state`.
- **An MCP server for discovery.** Its schemas would load on every request for something a command line does.
- **Ranking by stars.** Impersonation clones copy stars and metadata; the check is the publisher against the vendor's
  own page.
- **A hard gate for every project.** Most projects are not builds with a pipeline; advisory until it earns more.
- **Letting agents install what `find` returns.** Discovery and installation stay separate steps; the second needs the
  user's yes with source and size.

## Open questions (defaults apply until the user answers)

1. Search freshness window: 30 days. The field moves daily; films are weeks apart. Shorter means more re-searching.
2. Non-video projects: advisory. Make it a hard gate only for projects that opt in.
3. Tier 3 approval: per tool per project. The alternative, once per tool, is looser.
4. Where the shared Node module lives in the repo: left to the implementation plan; the constraint is one
   implementation, no dependencies, runnable without `aos`.

## Constraints from `AGENTS.md` that bind the plan

`aos.psm1` and `bootstrap.ps1` stay ASCII-only and run under Windows PowerShell 5.1 and PowerShell 7 (no `??`, no
ternary, no `&&`). `docs/decisions.md` is append-only: a new dated entry on top. No model names in the repo. Every step
idempotent. This design writes nothing under `~/.claude` or `~/.codex`; if the plan changes that, the other vendor's
second opinion comes first. The contract asks the other vendor to critique a plan over about an hour before code
exists; that critique of this spec is the next step.
