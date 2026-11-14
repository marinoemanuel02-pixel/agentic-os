# Codex critique of the tool-currency spec (2026-10-15)

Reviewer: Codex (`codex exec --profile review`, model flag as the account accepts it), read-only, 94,890 tokens, exit 0, no usage-limit
error. Subject: `2026-10-15-tool-currency-design.md` as committed in 04fa69d (the `spec:NNN` line numbers below refer
to that version). Text below is Codex's final answer, verbatim except that absolute worktree paths are made
repo-relative; dispositions are in the spec's "Codex review" section.

## Findings

1. **Blocker — discovery, [spec:100](docs/superpowers/specs/2026-10-15-tool-currency-design.md:100).** The proposed registry search is too narrow for the stated goal: the [official API searches server names only](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/official-registry-api.md), while the three `catalogs` repos are about skills, Claude Code and orchestrators ([refs/repos.json:19](refs/repos.json:19)). Web research is only a printed reminder, yet a ledger can pass with a registry search alone. Agents can satisfy the gate while silently missing generators, CLI wrappers and unofficial tools.

2. **Blocker — freshness gate, [spec:143](docs/superpowers/specs/2026-10-15-tool-currency-design.md:143).** `--fresh` is promised at brief and production start, but the specified wiring adds checks only to build and QA, without `--fresh` ([spec:151](docs/superpowers/specs/2026-10-15-tool-currency-design.md:151)). The existing pipeline has no enforced brief or production-start command ([build.sh:9](templates/video/tools/build.sh:9)). A stale search can therefore pass the only hard gates.

3. **Important — export evidence, [spec:151](docs/superpowers/specs/2026-10-15-tool-currency-design.md:151).** The wiring omits `tools.json` from the input manifest, which currently binds `currency.json` but not a tool ledger ([input-manifest.mjs:77](templates/video/tools/checks/input-manifest.mjs:77)). The ledger could be changed after rendering and QA could pass against a different tool decision from the one used to make the export.

4. **Important — redaction, [spec:85](docs/superpowers/specs/2026-10-15-tool-currency-design.md:85).** The rule prints package specs, remote URLs, raw `unparsed` lines and source failure reasons ([spec:91](docs/superpowers/specs/2026-10-15-tool-currency-design.md:91)). Any of those can contain a token even if `env`, headers and other arguments are suppressed; the stated fixture test does not cover those output paths. Inventory output or its cache can disclose a secret.

5. **Important — inventory meaning, [spec:80](docs/superpowers/specs/2026-10-15-tool-currency-design.md:80).** Calling the result “what is live” is too strong. A registration or installed plugin does not prove that a tool is available in the current agent session, and a 24-hour cache ([spec:95](docs/superpowers/specs/2026-10-15-tool-currency-design.md:95)) can conceal an install, removal or connection change made minutes earlier. An agent could plan around an unavailable tool or miss a newly available one.

6. **Important — ledger gate, [spec:115](docs/superpowers/specs/2026-10-15-tool-currency-design.md:115).** The schema contains self-reported search notes but no result links or evidence, and `policy.noNewTools` can excuse an empty needs list with a reason ([spec:139](docs/superpowers/specs/2026-10-15-tool-currency-design.md:139)). The spec acknowledges that review must judge search quality, but the hard gate can also be passed without recording a capability search at all. That weakens its claim that a build cannot skip tool consideration.

7. **Important — tier 0, [spec:165](docs/superpowers/specs/2026-10-15-tool-currency-design.md:165).** Tier 0 includes anything “a plugin marketplace already installs,” even when a third party publishes it. Such a tool bypasses the community-tool review in tier 1 solely because of its distribution channel; this conflicts with the goal of vetting non-vendor tools.

8. **Important — tier 3, [spec:169](docs/superpowers/specs/2026-10-15-tool-currency-design.md:169).** Requiring every unofficial or reverse-engineered tool to meet *all* tier 2 requirements assumes it has generated source, a source spec and regenerable routes. An existing unofficial server may have none of these. The rule would either exclude tools the design means to assess or encourage a paper claim that cannot be fulfilled; a terms field and self-entered approval text also cannot prove permission.

9. **Important — pinning and identity, [spec:89](docs/superpowers/specs/2026-10-15-tool-currency-design.md:89).** A local path is classified as `pinned` although its contents can change. In the ledger, `chosen` is only a candidate name, and the proposed check does not compare the recorded version with the installed executable or package ([spec:123](docs/superpowers/specs/2026-10-15-tool-currency-design.md:123)). The gate can approve one version on paper while another runs.

10. **Important — second-opinion rule, [spec:76](docs/superpowers/specs/2026-10-15-tool-currency-design.md:76).** The claim that this design writes nothing under `~/.claude` or `~/.codex` is **wrong** for rollout slice 1: its global-contract edit is copied into `~/.codex/AGENTS.md` by `aos sync` ([aos.psm1:495](aos.psm1:495)). The root rule requires the other vendor’s second opinion before that write ([AGENTS.md:17](AGENTS.md:17)); the rollout should retain that gate.

11. **Important — rollout, [spec:220](docs/superpowers/specs/2026-10-15-tool-currency-design.md:220).** Slice 2 introduces a hard video gate while expressly deferring tier enforcement to slice 3 ([spec:148](docs/superpowers/specs/2026-10-15-tool-currency-design.md:148)). It is independently mergeable as code, but not as the promised vetting gate: risky tools can pass during the interval.

12. **Minor — preflight and success criteria, [spec:155](docs/superpowers/specs/2026-10-15-tool-currency-design.md:155).** `PREFLIGHT.md` is generated by `Write-AosVideoPreflight`; it is not a file in `templates/video` ([aos.psm1:1924](aos.psm1:1924)). Slice 2 must change that generator to make the promised line appear. Also, “useful” in the backtest and “cost is not small” after three films have no stated decision threshold ([spec:214](docs/superpowers/specs/2026-10-15-tool-currency-design.md:214)); those success criteria are observable, but not yet checkable as pass or fail.

13. **Minor — project rules and context cost, [spec:44](docs/superpowers/specs/2026-10-15-tool-currency-design.md:44).** The draft itself names “Opus 4” despite the root rule of no model names in the repo ([AGENTS.md:15](AGENTS.md:15)). Its “cost is the one command line” claim is also inaccurate: the proposed change adds always-loaded contract text, whose per-request token cost the contract explicitly calls out ([agents-home/AGENTS.md:3](agents-home/AGENTS.md:3)).

The repo-checkable audit claims about the current catalog, its test, `config/mcp.json`, the reference shelf, and the existing currency gate had **no finding**. The draft states the ASCII, PowerShell 5.1/7, `$TestDrive`, idempotence and append-only decision constraints; there is no implementation yet to check against them.

### Not checked

- Live Claude/Codex registrations, plugin lists, secret-bearing CLI output, and the external film retros.
- The draft’s third-party precedent measurements or a live registry response; I checked the registry’s official API documentation.
- Tests or builds; this was a read-only design review, and `git status --short` was clean.
