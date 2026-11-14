# Tool currency: knowing what tools exist before building (design)

Date: 2026-10-15. Status: revised after Codex critique (13 findings, all taken; dispositions at the end); awaiting the
user's review of this file.
Author: Claude (session 9884029f). Independent critique: Codex, read-only, before any plan or code
(`2026-10-15-tool-currency-codex-critique.md`). Branch `tool-currency-spec` (worktree
`~/.aos/worktrees/agentic-os-tool-currency`), cut from `phone-orchestration-design` at 33ee9cb. Nothing is implemented.

## Why

The user, 2026-10-15, verbatim: "all the tools must used for the builds must be factored in since they change
significantly the result and approach in development, there are probably tons more that can be added and new ones
get released everyday and i am not sure whether the agents working on the projects are handling this correctly, many
people have been using similar harnesses so there should be precedent to check against before." And: "THIS SPACE IS
MOVING REALLY FAST, PEOPLE ARE REVERSE ENGENIEERING MANY PAID SOFTWARES, CUSTOM MPCPs GET RELEASED and TOOLS FOR
CREATING CUSTOM ONES AND CONVERTING INTO MCPs SPECIFIC TOOLS WITHOUT ONES".

Approved in conversation the same day: all three parts below (the map, the ledger and gate, the vetting rules), as a
written spec in a worktree. Everything in "Open questions" is a default the user has not yet confirmed.

## What the audit found (read 2026-10-15)

| Finding | Where |
|---|---|
| The tool catalog lists what is installed, by hand. Its MCP table has two servers (`context7`, `nar`); this machine also runs the Blender add-on server, a Playwright server, Chrome and computer-use tools, Google connectors and a registry-search tool. | `agents-home/skills/tool-catalog/SKILL.md`; `claude mcp list`, `codex mcp list` |
| The catalog's own rule 2 makes the agent passive: "if nothing fits, say what is missing ... adding one is the user's call". Nothing says to look for a tool that exists but is not installed. | same file |
| The catalog test only proves that every shared skill and every `config/mcp.json` server is mentioned. It cannot see anything installed outside aos. | `tests/aos.Tests.ps1` ("Shared tool awareness") |
| Discovery is passive: awesome-lists are cloned on the `catalogs` shelf, checked 2026-09-27, and no process reads them. The three lists on that shelf are about skills, Claude Code and orchestrators, not general tool lists. | `refs/repos.json` |
| The runtime search-and-add idea (Docker MCP gateway) exists only as a plan: not in `config/mcp.json`, no decision entry. | `docs/superpowers/plans/2026-09-29-tool-gateway.md` |
| Facts have a currency gate (R27: dated primary sources, re-verified on export day, bound into the input manifest). Tools have only R08 (one real test call when a tool is added). | `~/.agents/video/video-rules.md`, `templates/video/tools/checks/currency.mjs`, `input-manifest.mjs` |
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
| Loading every tool schema up front is the problem: 5 servers / 58 tools is about 55K tokens before work starts; tool search cut that by about 85% and raised selection accuracy (49% to 74% on the older of the two models they tested) | Anthropic, "Advanced tool use" (anthropic.com/engineering/advanced-tool-use) | opened |
| Claude Code ships tool search on by default, and tells Claude which servers failed to connect | code.claude.com/docs/en/mcp (page truncated at 100K characters; the tool-search configuration section was not read) | opened, partly |
| Docker Dynamic MCP: `mcp-find` / `mcp-add`, servers last one session only, experimental, catalog built and signed by Docker | docs.docker.com/ai/mcp-catalog-and-toolkit/dynamic-mcp/ | opened |
| The official MCP Registry is a preview with the v0.1 API frozen (README, 2025-10-24); it verifies namespace ownership (GitHub OAuth, DNS or HTTP challenge), not code | github.com/modelcontextprotocol/registry | opened |
| Its `search` parameter is a case-insensitive substring match on server names only ("intentionally simple"); `version=latest` and `updated_since=<date>` are supported | the registry repo's `docs/reference/api/official-registry-api.md` | opened (found by Codex, confirmed here) |
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

Goals: (1) an agent can see what is registered, per vendor, and look for what is not, in one command each; (2) every
build records, per need, what was searched (with evidence), what was found, what was chosen and why, dated, and a gate
refuses a build that skipped it or let the search go stale; (3) any tool that is not the vendor's own passes a vetting
gate sized to its risk before it is installed; (4) the process costs almost no always-loaded context and works the
same from Claude and Codex.

Non-goals: an MCP server for tool discovery (schemas load on every request; a command line does the job, decisions
2026-10-01); the Docker gateway now (see Rejected); auto-installing anything (installs keep needing the user's yes with
source and measured size); ranking tools by stars or popularity; cracked, pirated or licence-circumventing software
(refused: "free" means free legitimately); the local Pi agent (no MCP servers by decision 2026-09-29); retrofitting
films already made.

## Design

Principles: command line first, then skill, then server (unchanged). Discovery is not installation. A ledger is a
locator, not a judge: it proves a search was recorded and a vetting was done, not that either was good; independent
review judges (same limit as the currency gate), and this spec makes that review an explicit step. The commands write
only under `~/.aos`; the one edit that reaches `~/.codex` is the contract sentence in section 4, and it is gated there.

### 1. The map: `aos tools`

**`aos tools`** prints, per vendor, what is registered: MCP servers (name, transport, enabled, pin state), plugins
(id, version, enabled), shared skills (from `agents-home/skills`). Sources, all read-only: `claude mcp list` (text) and
`claude plugin list --json`; `codex mcp list --json` and `codex plugin list --json` (its `installed` array; the text
form lists the whole marketplace, 6,000+ not-installed rows). `--json` emits the same redacted data for other tools.
Rules:

- **Registered is not available.** A registration does not prove the tool is usable in the current session, and
  a plugin may be installed but not loaded. The output says "registered" and, where the source reports it, the
  connection status. Inside a Claude session the live view of deferred tools is the session's own `ToolSearch`; this
  command is for the offline view, for Codex, and for anything installed outside the session.
- **No cache.** Every run reads the sources (about 8 s, dominated by `claude mcp list` health-checking every server). A
  stale answer about what is installed is worse than a slow one, and nothing is stored, so nothing can leak from a store.
- **Redaction is an allow-list, applied to every output path.** Printed fields: name, transport, enabled, version, pin
  state, connection status, and nothing else, except:
  - stdio: the command's file name, plus the package spec only when the command is `npx`, `uvx` or `pipx` and the spec
    matches a strict package pattern (`name`, `@scope/name`, optionally `@version`); anything else prints `<redacted>`.
  - remote: scheme, host and path with userinfo, query and fragment removed (and any path segment that looks like a
    token, long and mixed, replaced).
  - never: `env`, headers, `cwd`, other arguments, raw `unparsed` lines (printed as a count per source), and raw
    stderr (failures print a fixed reason: `not installed`, `exit <n>`, `not parseable`).
  A test feeds fixtures with a fake secret in every field and in every output path above (env, header, argument, url
  query and userinfo, package spec, unparsed line, stderr) and fails if it appears in stdout, stderr or `--json`.
- **Pin state** is `pinned` (exact version or digest), `floating` (`@latest`, no version), `local` (a path: its contents
  are not verified) or `n/a` (remote url). `floating` and `local` are warning lines, not errors (the Playwright plugin
  is the first `floating`).
- **Failure is not "none".** A source that is missing, errors or cannot be parsed prints `unavailable: <source>: <fixed
  reason>` and the command exits non-zero (the local CLIs run without a timeout wrapper). `claude mcp list` has no
  options besides help (checked), so its text is parsed; a line that does not parse is counted as `unparsed`, never
  dropped.

**`aos tools find <need words> [--since YYYY-MM-DD]`** looks for what is not installed. It is honest about its reach: it
sees MCP servers published to the registry, and nothing else.

1. The official registry: `GET /v0.1/servers?search=<words>&version=latest&limit=20`, each row as name, description,
   remote or package, repository, published date, and a namespace line (`io.github.<account>` = GitHub account
   ownership; a reverse-DNS domain = domain ownership; both are ownership, not safety). `--since` adds
   `updated_since`, so "what appeared since the last film" is one flag (the ledger's last search date feeds it). The
   search is a substring match on server names only: a server whose name lacks the word is not found.
   One page by default; `--pages <n>` (at most 3) follows `nextCursor`, because the registry is slow (1 s to 85 s
   measured on 2026-10-15; the call waits up to 100 s and makes one attempt). The schema is a preview: unknown shapes
   print `unparsed`, never a silent empty. Descriptions are third-party text printed to an agent: they are cut to one
   line of 160 characters, stripped of control characters, and printed under a line saying they are data, not
   instructions. The need words are limited to letters, digits, spaces and `. + # -` and are URL-encoded; they never
   reach a shell.
2. The local awesome-lists on the `catalogs` shelf (`rg -i` over `~/.aos/refs/catalogs`), offline. They are about
   skills, Claude Code and orchestrators: a minor source, stated as such.
3. The part the registry cannot do, printed as a fixed block of web queries to run (the `research` skill): `<software>
   MCP server`, `<software> API OpenAPI spec`, `<software> CLI`, `<software> unofficial API reverse engineered`,
   `<software> open source alternative`, `<capability> MCP generator`. These are what reach generators, CLI wrappers,
   HAR-based and unofficial tools.

A registry or network failure prints `registry unreachable` and exits non-zero. `find` installs nothing and makes no
request carrying project content: the query is the need words only.

### 2. The ledger and the gate

Each project keeps `tools.json` (next to `currency.json`). Shape, one entry per capability the build needs:

```json
{
  "policy": {"searchWithinDays": 30},
  "needs": [{
    "id": "N01", "need": "drive Blender scenes live and read back stills", "stage": "production",
    "searches": [{"source": "registry|web|refs|installed|user", "query": "blender", "date": "2026-10-15",
                  "evidence": ["url opened", "..."], "note": "what came back"}],
    "candidates": [{"id": "C1", "name": "...", "kind": "cli|skill|mcp|plugin|library|service|model",
                    "risk": ["community", "generated", "unofficial"], "origin": "url", "publisher": "...",
                    "licence": "...", "cost": "free", "installedBy": "aos|plugin|user|agent", "local": false}],
    "chosen": "C1 | none", "why": "...",
    "vetting": {"version": "exact, or commit/sha256 for a local path", "codeReview": "read|sandboxed|vendor",
                "secrets": "none|aos-secret:<name>", "consent": {"date": "", "size": "", "words": ""},
                "testCall": {"date": "", "what": "", "result": "ok"},
                "tools": {"count": 0, "schemaChars": 0},
                "generatedFrom": "openapi|cli|har", "source": "", "routes": "", "fixtureTests": "", "harRedacted": true,
                "terms": "", "approval": {"date": "", "words": ""}, "fallback": "", "accountCredentials": "none"}
  }]
}
```

`risk` is empty for the software vendor's own tool. A candidate can carry several flags.

**`aos tools check <project> [--today YYYY-MM-DD] [--inventory <file>]`** reports every defect in one pass (like
`currency.mjs`). Errors:

- Structure: missing field, duplicate id, bad or future date, unknown kind or risk flag, `chosen` that names no
  candidate, empty `needs` (a film always needs tools; there is no exemption field).
- **Evidence.** Every search carries at least one opened URL in `evidence`, or the literal `"none"` with the queries
  listed in `note`. A search with neither is an error.
- **Two searches, not one.** Each need must have a `registry` search and a `web` search, both within
  `policy.searchWithinDays` (default 30) of `--today`. `installed`, `refs` and `user` searches are allowed but cannot
  stand in for either: the registry sees only names, the web is where generators and unofficial tools show up, and
  "I looked at what I already have" must not pass.
- **Freshness is checked every time**, including by build and QA: a stale search fails the build, as a stale source
  fails the currency gate. Rebuilding an old film means one re-search (minutes), by design: the space moves daily.
- A chosen candidate that is not `free`, has no licence, no `vetting.version`, no `testCall` with result `ok` (R08),
  or, when `installedBy` is `agent`, no `consent` (the existing install rule: source and measured size, the user's yes).
  A `local`-path tool's version must be a commit hash or a sha256, never "latest" or a bare path.
- The risk-flag requirements of section 3.
- `chosen: none` without `why`.
- With `--inventory` (the redacted `aos tools --json` output; `aos tools check` supplies it), a chosen candidate that
  matches a registered tool and whose installed version is visible (an `npx` spec, a plugin version) must equal the
  ledger's `vetting.version`: a mismatch is an error. When the version is not visible it is a warning. The video
  template's own build runs the Node module without `aos`, so there the check is skipped with a printed notice and runs
  when someone calls `aos tools check`. What the check cannot do: hash the executable that actually runs.

**Wiring.** Exactly one implementation, a dependency-free Node module with `node --test` tests, so it runs inside the
isolated video render roots and from Codex; `aos tools check` calls it. The video template gets:

- `tools.json` scaffolded by `aos video new`, and a `## Tools` pointer in `brief.md`.
- The check called from `build.sh` and `qa.sh` beside the currency check; `tools.json` added to the input manifest next
  to `claims.json` and `currency.json` (`input-manifest.mjs`), so a ledger edited after sealing forces a rebuild.
- `Write-AosVideoPreflight` (the generator of `PREFLIGHT.md`; the file is not in the template) gains a line: "tool search
  last run N days ago, M needs, K candidates adopted".
- A `## Tools` section in `retro.md`: "new since the last film (`aos tools find --since <last film date>`)" and "used but
  not in the ledger".
- One new rule in `video-rules.md`: the other vendor reads `tools.json` against the brief at the brief gate and says
  what need or candidate is missing (the completeness the check cannot judge). Its id is taken at merge as the next
  free one: the unmerged branch `video-blender-shorts` already uses up to R54 (checked 2026-10-15), so the plan uses
  R55 and re-checks at merge.

Other projects: `templates/project/AGENTS.md` gets a two-line pointer; the check is advisory there.

**Where the work goes when nothing is found.** In order: a script or command-line wrapper written for the project (no
context cost); a generated MCP server only when the tool must hold state across calls in a session (the Blender case);
never a hand-written server for something a command line reaches.

### 3. Vetting by risk flag

Not a ladder: a candidate carries every flag that applies, and meets every flag's requirements.

| Flag | Applies when | Requirements, on top of the base |
|---|---|---|
| (base) | every chosen candidate | free; licence recorded; exact version; one real test call (R08); install consent with measured size when an agent installs it |
| community | not published by the software's own vendor. The vendor identity is confirmed from the vendor's own page, not a search result. A third-party plugin from a marketplace is community, however it was installed. | version pinned (no `@latest`, no auto-update; an upgrade is a new vetting); code read or run sandboxed first; secrets stated and passed only through `aos secret`; tool count and schema size recorded |
| generated | built by us from an OpenAPI spec, CLI help text or a HAR capture | the generated source lives in the project repo and is reviewed as our code; routes allow-listed (read-only first, a catch-all exclude); a fixture test per exposed tool; regenerated, not patched, when the spec changes; HAR files redacted of cookies and tokens before they are kept |
| unofficial | unofficial or reverse-engineered access to a paid or private service, whoever wrote it | the licence or terms clause checked and written down; the user's approval in his own words with the date, per tool per project; a recorded fallback, because the build must not depend only on something a site change can break; never the user's account credentials in an unofficial tool |

The ledger records the approval; it cannot prove it. The user's words are what the director reads back to him, and the
plan may tie `approval` to an `aos video verdict` ledger entry. A tool that is both generated and unofficial meets both
rows; an existing unofficial server nobody here generated meets community plus unofficial.

Why these gates: the registry confirms who owns a name, not what the code does; the postmark-mcp backdoor was one line
added in v1.0.16 to a copy of a legitimate library, which is why pinning and a re-vetting on upgrade matter more than a
first read; clones of official repos are the known impersonation route, which is why the publisher is checked against
the vendor's own page. `unofficial` is allowed to exist because the user named this space on purpose; it stops at the
user because it can touch a third party's terms and the free-stack rule.

### 4. What changes in always-loaded text, and the gate on it

`agents-home/AGENTS.md` is loaded on every request by both agents, so this has a measurable cost: one sentence gains
about a dozen words (roughly 20 tokens per request, both vendors), no new line. Today: "Before saying a capability is
missing, or choosing among tools, read the `tool-catalog` skill: it lists every skill, MCP server, CLI, media app and
agent here, and which one to try first." It gains: "then `aos tools find <need>` before concluding nothing exists."
The `tool-catalog` skill (loaded on demand, not per request): rule 2 becomes "If nothing fits, run `aos tools find
<need>`, then say what is missing; installing needs the user's yes"; a row for `aos tools`; the MCP table gains a
note that `aos tools` shows what aos does not own (plugins, connectors, other registered servers; not the servers a desktop app hosts itself, such as the Blender one, which `claude mcp list` does not show: measured 2026-10-15). Its existing test stays and
gains a check that `aos tools` is named. No server and no skill is added.

`aos sync` copies the contract to `~/.codex/AGENTS.md` (`Sync-AosCodexAgents`), so this sentence is a write under
`~/.codex`. Per the project rule, the other vendor's second opinion on that exact diff comes before the sync runs in
rollout slice 1. This spec's critique covers the design, not the final wording.

## Failure handling

- Registry down or reshaped: `find` says so and exits non-zero; the agent falls back to web search and records
  `source: web`. Never "no candidates found" from a failed call (global contract, rule 5).
- Inventory source missing (vendor CLI not installed): `unavailable`, not an empty list.
- A ledger entry that cites a tool the inventory does not show: the check warns (it may be a different machine).
- A tool that changes after pinning: detected only when the inventory exposes its version (an `npx` spec, a plugin
  version); otherwise pinning makes an upgrade a deliberate act that goes through vetting again, and a swap of the
  files behind a pinned local path is not detected.

## Testing and success criteria

Each criterion is checkable and each new test must be seen failing before the code (contract, rule 3). Tests follow the
repo's: Pester for `aos` (both shells; `$TestDrive`; no real profile or network, the vendor CLIs and the registry
mocked through `Invoke-AosCapture` and a fixture), `node --test` for the ledger module. Tests are best written by
Codex (project rule); Codex's sandbox has no Pester 5, so the host runs them.

1. `aos tools` against fixtures for both vendors lists every server and plugin, marks `floating` and `local`, prints
   `unavailable` for a failing source, and leaks no planted secret through any path listed in section 1 (stdout,
   stderr, `--json`).
2. `aos tools find` against a recorded registry response returns one row per name with the namespace line, passes
   `version=latest` and, with `--since`, `updated_since`, prints the web-query block, and prints `registry unreachable`
   (exit non-zero) on a failed call.
3. `aos tools check` fails on each defect class above with a fixture per class and passes a complete ledger,
   including: a 31-day-old search fails and a 29-day-old one passes; a ledger with only a `registry` search fails; a
   search with no evidence fails; each risk flag's missing requirement fails; a version mismatch against `--inventory`
   fails.
4. The video template's build and QA refuse a new project without a valid, fresh `tools.json`; editing `tools.json`
   after the input manifest is sealed fails the manifest check; a project made before this change is unaffected.
5. `aos test` passes in both shells; ASCII and parse checks pass; a second `aos sync` still changes nothing.
6. **Backtest:** run `aos tools find` plus the printed web queries for the capability needs of one finished film
   (`cant-escape-ai`) and list the candidates not used or known then. Pass = the user marks at least one as worth
   considering for that film's shots; fail = none, and this spec is revisited before merge. The judgement is the
   user's, recorded in the decision entry.
7. **Sunset check after three films:** read the three ledgers. Pass = at least one candidate adopted that the previous
   film did not use, or a defect found by the brief-gate review. Fail (both absent) with more than 20 minutes of
   `brief`-stage time per film attributed to the ledger in `aos video log` notes = loosen the gate to advisory.

## Rollout (each slice merges on its own)

1. **The map.** `aos tools` and `aos tools find`, the catalog edit, the contract sentence (after the other vendor's second
   opinion on its diff), tests, README, the decision entry. Useful alone; changes no build.
2. **The ledger and the vetting rules, together.** The Node module with the risk-flag requirements already in it,
   `aos tools check`, the video template wiring (scaffold, build/QA, input manifest, PREFLIGHT line, retro section),
   the new video rule. One slice, because a hard gate that enforces structure but not vetting would let risky tools
   pass in the interval.
3. **Reach.** The `templates/project` pointer; the backtest and the sunset review are decisions, not code.

## Rejected

- **Docker MCP gateway now.** Catalog is Docker's own curated set, so it misses the long tail and anything
  community-made or reverse-engineered; added servers last one session; experimental; Docker Desktop required; Codex
  support unknown. Revisit if the registry plus web search misses things the user wants after three films.
- **A generated inventory block committed in the skill, or a cache of the inventory.** Connectors connect and
  disconnect, so a committed file would change without anyone editing it; decisions 2026-10-02 already rejected a history
  file in `agents-home` for the same reason (it dirties the config repo and two agents can interleave writes). A cache
  goes stale and is one more place for a secret to land; the read costs about 8 s.
- **An MCP server for discovery.** Its schemas would load on every request for something a command line does.
- **Ranking by stars.** Impersonation clones copy stars and metadata; the check is the publisher against the vendor's
  own page.
- **A hard gate for every project.** Most projects are not builds with a pipeline; advisory until it earns more.
- **A registry search alone as the discovery step.** Names only; it cannot see generators, wrappers or unofficial tools.
- **Letting agents install what `find` returns.** Discovery and installation stay separate steps; the second needs the
  user's yes with source and size.
- **An exemption field for "no new tools".** A film always needs tools; an empty ledger is a skipped step.

## Open questions (defaults apply until the user answers)

1. Search freshness window: 30 days. The field moves daily; films are weeks apart. Shorter means more re-searching.
2. Non-video projects: advisory. Make it a hard gate only for projects that opt in.
3. `unofficial` approval: per tool per project. The alternative, once per tool, is looser.
4. The sunset thresholds in criterion 7 (one adopted candidate or a review defect; 20 minutes per film) are my numbers.
5. Where the shared Node module lives in the repo: left to the implementation plan; the constraint is one
   implementation, no dependencies, runnable without `aos`.

## Constraints from `AGENTS.md` that bind the plan

`aos.psm1` and `bootstrap.ps1` stay ASCII-only and run under Windows PowerShell 5.1 and PowerShell 7 (no `??`, no
ternary, no `&&`). `docs/decisions.md` is append-only: a new dated entry on top. No model names in the repo. Every step
idempotent. The one write under `~/.codex` is the contract sentence (section 4), gated by the other vendor's second
opinion. The contract asks the other vendor to critique a plan over about an hour before code exists: this spec's
critique is done; the plan gets its own.

## Codex review (2026-10-15)

Reviewer: Codex (`codex exec --profile review`, model flag as the account accepts it), read-only, 94,890 tokens, exit 0. The full text is in
`2026-10-15-tool-currency-codex-critique.md`. Verified here against sources before acting: the registry `search`
scope, the input-manifest binding and the contract-sync path (findings 1, 3, 10, all confirmed). Codex's own "no
finding" areas: the repo-checkable audit claims. Nothing rejected.

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | Blocker | The registry searches names only; a registry search alone could pass the gate while missing generators, wrappers and unofficial tools | Taken. Confirmed in the registry docs. Both a registry and a web search are required; `find` prints the web queries and states its reach; refs shelf described as minor |
| 2 | Blocker | `--fresh` was promised at brief and production start but only build and QA are enforced, without it | Taken. Freshness is checked on every run, including build and QA; the earlier "must not fail a long project on age" is dropped |
| 3 | Important | `tools.json` not in the input manifest | Taken. Confirmed (`input-manifest.mjs` binds `claims.json` and `currency.json`). Added |
| 4 | Important | Redaction missed package specs, urls, `unparsed` lines and failure reasons | Taken. Allow-list on every output path; fixtures for each path |
| 5 | Important | "Live" overstated; a 24 h cache hides changes | Taken. Worded "registered"; the cache is removed |
| 6 | Important | Search notes are self-reported; `noNewTools` exempts a capability search | Taken. Evidence URLs required per search; the exemption is removed; the other vendor reviews `tools.json` at the brief gate. The check still cannot judge search quality: stated |
| 7 | Important | A third-party marketplace plugin was tier 0 | Taken. Marketplace third-party is `community` |
| 8 | Important | Tier 3 required all of tier 2, which an existing unofficial server cannot meet | Taken. Tiers replaced by independent risk flags |
| 9 | Important | A local path counted as pinned; `chosen` is a name; no recorded-vs-installed comparison | Taken in part. `local` is not pinned and needs a commit or sha256; `chosen` is a candidate id; a version cross-check against the inventory where the version is visible. Hashing the running executable is not attempted: stated |
| 10 | Important | "Writes nothing under `~/.codex`" is wrong: `aos sync` copies the contract | Taken. My claim was wrong; the second opinion on that diff is now a step in slice 1 |
| 11 | Important | Slice 2 gate enforces structure while vetting waits for slice 3 | Taken. Vetting rules move into slice 2 |
| 12 | Minor | `PREFLIGHT.md` is generated by `Write-AosVideoPreflight`; success criteria "useful" and "not small" have no threshold | Taken. Generator named; thresholds defined and listed as open question 4 |
| 13 | Minor | A model name in the spec; "cost is the one command line" is inaccurate | Taken. Model name removed; the contract sentence's cost stated (about 12 words, 20 tokens per request) |

## Amendments found while planning (2026-10-15)

Found by running prototypes of the parsers, the registry call and the ledger module against this machine's real
output while writing `docs/superpowers/plans/2026-10-15-tool-currency.md`; none changes a decision, each corrects a
fact or fills a gap the plan needed.

- `codex plugin list --json` exists (`--available` too) and returns `{installed, available}`; the text form was 1.1 MB
  of mostly not-installed rows. The inventory uses `--json`; the text parser in section 1 is dropped.
- Local CLIs run without a timeout wrapper, so the "times out" failure reason is removed; the fixed reasons are
  `not installed`, `exit <n>`, `not parseable`.
- The registry is slow: the same `search=blender` call took 1 s, 9.9 s, 15 s, 40 s (timed out) and 84.6 s (with
  `updated_since`). `find` waits up to 100 s, makes one attempt, and fetches one page unless `--pages` asks for more.
  `updated_since` works (verified: it returned a server published the day before).
- Registry descriptions are third-party text shown to an agent, so they are bounded, stripped and labelled as data.
  The need words never reach a shell (charset limit, URL encoding).
- The ledger schema gains the fields its tier rules need: `candidates[].local`; `vetting.generatedFrom`, `source`,
  `routes`, `fixtureTests`, `harRedacted`; `vetting.accountCredentials`.
- The next free video rule id is R55 (R54 is the highest on any branch).
- Three portability bugs the prototypes caught, now stated in the plan so they are not rediscovered: a parameter named
  `$Args` silently shadows PowerShell's automatic variable; `@(ConvertFrom-Json ...)` wraps a whole array as one item in
  Windows PowerShell 5.1 (assign first, then `@($x)`); PowerShell 7 turns ISO timestamps in JSON into `[datetime]`.
- Found by running the commands for real: a token in a url path can hold `=`, `.` or `%`, so segments are redacted by length-and-mix or by those characters, not by a fixed character class; the Blender server this session uses is hosted by the desktop app and is absent from `claude mcp list`.
