# Candidate capability registry

Use `python tools/stack.py capabilities` from the repository. This standard-library command
tracks upstream tools; it does not install them or alter agent settings. The existing
`watch` command remains the local video tool. The installed-tool verifier and swarm API
capability catalogue retain their existing scopes.

## Data and confidence

[`config/capabilities.json`](../config/capabilities.json) is the reviewed candidate list;
[`config/capabilities.schema.json`](../config/capabilities.schema.json) is its JSON Schema.
`validate` enforces the schema's used keywords and semantic constraints without installing a
validator. All candidates start at `watch` or `ignore`; recommended tiers are priorities for
future evaluation, not statements that the applications were installed or tested here.

Each candidate records discovery time/sources, repository creation and functional-commit dates,
release information, parent/fork provenance, license, Windows build/execution claims, interface
flags, inspect/render/mutation properties, security concerns, incremental value and existing
routes. These curated fields are **research claims**, including `true` flags. Null means unknown,
not unsupported. A source's added/pushed date never becomes repository creation or functional work.

Fresh observations are separate, under `~/.aos/capability-watch/state.json`. They contain source
URLs, fetch dates, content hashes, repository/package metadata, snippets and unverified word
signals. A Windows release filename is not a Windows execution test. A README mentioning MCP,
even in a negation or roadmap, is not proof of support. License metadata is not a license review.
`list` prints curated data; read the state file or refresh report for observations.

Both uploaded inputs were read in full. Their filenames and SHA-256 hashes are recorded under
`research_inputs`: `Pasted markdown(6).md` is the broad audit; `Pasted text (2)(2).txt` is the
emerging-project audit. The latter explicitly disclaims local Windows execution. The broad
Markdown lost its citation URLs, so unresolved facts remain unknown. Additional recommendations
come from conversation `6ad8ecad-6f4c-83eb-a574-58c427e57533`; its stable id is provenance, not
an invented export hash. Original source content is not copied into the repository.

## Refresh and review

```powershell
python tools/stack.py capabilities validate
python tools/stack.py capabilities list

# Preview enabled discovery indexes and package releases; no writes.
python tools/stack.py capabilities refresh --limit 20 --match spreadsheet

# Persist successful observations and the returned discovery identities.
python tools/stack.py capabilities refresh --limit 50 --apply

# Inspect selected original repositories: metadata, README and latest release.
python tools/stack.py capabilities refresh --tool pdfcraft --tool logisheets --apply

# Select an optional feed explicitly (or change its enabled field in the registry).
python tools/stack.py capabilities refresh --source rea-rss --apply

# Globals precede the action; overrides keep fixtures/state in a chosen folder.
python tools/stack.py capabilities --state work/capabilities/state.json refresh --source rea-daily
```

Default refresh uses discovery/release sources only. `--tool` selects original repositories
instead; combine it with explicit `--source` arguments if needed. Requests are bounded to 20
seconds per socket operation and 8 MiB per response. There is no retry loop or background service.
Each selected repository takes three GitHub requests plus any explicit `watch_paths`. Select small
batches to respect anonymous API limits; 403/429 is a failure, not an empty repository.

The first successful observation establishes a baseline. Subsequent reports include
`signal_appeared`, `signal_disappeared`, `release_changed`, `repository_changed` and changed-source
hashes. The tracked signals are Windows, CLI, MCP, stdio, JSON-RPC, headless, live GUI attach,
inspectable state, render feedback, filesystem scoping, revision guards, rollback and transactions.
Words disappearing from a document do not establish feature removal. Metadata push times do not
establish functional changes. Signals are recorded per source so disagreement remains visible.

`discoveries` contains normalized repository URLs, discovery times and all matching source ids.
It does not create candidate entries. Links can point to references, forks or unrelated code:
review the original repository before adding a row. `--match` is a case-insensitive substring in
nearby context; it is a rough discovery filter. Results are capped at 50 by default (maximum 500),
with `discovery_count` showing the uncapped number. Only emitted discoveries become seen when
applied, so another run drains the remaining results. Previously seen entries stay in the state;
curated `ignore` entries remain excluded from new-candidate output.

Use a focused repository review to fill unknown curated fields and add relevant `watch_paths`
such as an actual automation document or manifest. Paths are relative to the repository; remote
`HEAD` follows its default branch. These paths only fetch text. There is no execution, cloning,
installer download, model call or instruction-following from source content.

Exit codes: **0** successful validation/preview/update, **1** refresh has failed sources, **2**
invalid arguments/data or blocked operation. Applied partial refreshes retain successful new data
and the previous successful value for failed sources; failure is still reported. Corrupt state
fails closed for manual inspection. Writes use exclusive sidecar locks and atomic replacement.
After a crash, confirm no process owns the lock before removing it; locks never expire themselves.

## Sources

| Source | Configured surface | Use and limit |
|---|---|---|
| [REA Case Rankings](https://github.com/miles990/rea-case-rankings) | [records JSON](https://miles990.github.io/rea-case-rankings/api/records.json), optional [daily JSON](https://miles990.github.io/rea-case-rankings/api/daily.json) and [RSS](https://miles990.github.io/rea-case-rankings/feed.xml) | Case discovery; scores are not conformance evidence. |
| [awesome-reverse-engineered](https://github.com/alexgaoth/awesome-reverse-engineered) | `data/entries.json` | Broad repo links; retrieved here despite the broad report's earlier failure. |
| [REA list](https://github.com/AIshihzong/awesome-reverse-engineer-anything) | README | Focused discovery; authorship/provenance needs original-source review. |
| [REA cases](https://github.com/songshikang0111/awesome-REA-cases) | `INDEX.en.md` | Full case list, rather than counting maintenance commits. |
| [Glama](https://glama.ai/mcp/reference/list-mcp-servers) | `https://glama.ai/api/mcp/v1/servers` | Recorded but disabled/blocked: API needs authentication; anonymous probe returned 401. No secret loading adapter is included. Use manual directory review. |
| npm | `rea-agents/latest`, `logisheets/latest` | Package version separate from source release. |
| PyPI | `audacity-mcp-server/json` | Optional, disabled until publishing identity/repo mapping is checked. Guessed `blender-agent-sdk` package returned 404 and was not configured. |
| Original GitHub repositories | API metadata, raw README, latest release, explicit extra paths | Final source-review leads. No published release (404 on latest-release endpoint) is recorded as null; other fetch errors remain failures. |

HTTPS is restricted to the explicit hosts in `tools/capability_watch.py`, including redirect
targets. No credentials are sent. Adding another origin requires a reviewed code change. No exact
canonical `awesome-ai-rewrite`/`awesome-ai-craft` source was established by the report; none is guessed.

## Evidence and status changes

Statuses mean: `ignore` has insufficient incremental value or a current blocker; `watch` follows
changes; `sandbox` has been selected for isolated evaluation; `production` has passed the pinned
version's adoption checks. Changing a status does not install or launch anything.

After doing the actual checks, save an evaluator-authored record. The following example is an
**unverified template**, so its checks deliberately remain `unknown`:

```json
{
  "checked_at": "2026-10-21T20:00:00Z",
  "version": "replace-with-exact-tested-version-or-commit",
  "checks": {
    "source": "unknown", "license": "unknown", "windows_build": "unknown",
    "windows_execution": "unknown", "security": "unknown", "artifact": "unknown"
  },
  "references": ["replace-with-corpus-report-path-or-URL"],
  "notes": "Describe actual results, versions, failures and independent artifact inspection."
}
```

```powershell
python tools/stack.py capabilities status pdfcraft sandbox --reason "Selected copied-PDF corpus" --apply
python tools/stack.py capabilities record pdfcraft --evidence work/pdfcraft-evidence.json --pin
python tools/stack.py capabilities record pdfcraft --evidence work/pdfcraft-evidence.json --pin --apply
python tools/stack.py capabilities status pdfcraft production --reason "Pinned corpus and boundaries passed"
```

All mutations preview unless `--apply` is present. Registry writes save a content-named previous
JSON copy under the state directory's `registry-backups`. Evidence records are append-only through
the command and require a version, dated result for all six checks, references and explanatory notes.
Each check is `pass`, `fail` or `unknown`; importing a report never runs it.

For production, the latest record for `pinned_version` must pass all six checks. Source/license
review, Windows build and actual Windows execution, exercised security boundaries, and independently
reopened/rendered artifacts are separate requirements. The command validates the record's structure;
the evaluator is responsible for the truth of its contents. Demote a production candidate before
recording a failed current-version reevaluation. Revisit evidence explicitly when upgrading the pin.

For every application trial: copy inputs, inspect state, make a bounded edit, render/export,
independently reopen/validate, then consider promotion. Exercise denied writes, stale revisions,
rollback and uncertain completion. Root scoping and localhost tokens need actual tests; arbitrary
execution or native plugins can exceed an application's apparent filesystem boundaries.

## Recommended evaluation tiers

These are reconciled research priorities, not additional installed software. Use the registry's
per-candidate source and limitations before planning a trial.

| Tier | Candidate | Acceptance / existing-route comparison |
|---|---|---|
| First | [REA](https://github.com/morluto/rea) + [Ghidra](https://github.com/NationalSecurityAgency/ghidra) | New binary/Electron/runtime evidence. Begin with static analysis in copied, separate target workspaces. Provider setup is part of the test, not another default MCP. |
| First | [PdfCraft](https://github.com/storytold/pdfcraft) | Semantic edits and persistent renders. Test `--root`, page/form/bookmark edits, denial outside root, save/reopen and independent PDF renders against existing PDF scripts. |
| First | [Blender Agent SDK](https://github.com/yazzang-homelab/blender-agent-sdk) **versus** [sandraschi/blender-mcp](https://github.com/sandraschi/blender-mcp) | Run the same ten tasks below on both; choose one. Blender CLI already exists. Reported Windows transport/CI is not GUI execution proof. |
| First | [LogiSheets](https://github.com/logisky/LogiSheets) | Prefer semantic Blocks and policy-aware headless engine over experimental desktop. Compare formulas, invalid writes, structural edits and Excel round trips with existing spreadsheet routes. GridCraft is the alternative. |
| Next | [FilmCraft](https://github.com/storytold/filmcraft) | Timeline state beyond FFmpeg, but Kdenlive CLI-Anything/OpenMontage already exist. Require a measured workflow benefit, scoped media copies, interchange and ffprobe/render checks. Reported MCP confinement gap remains a test target. |
| Next | [PhotoCraft](https://github.com/storytold/photocraft) | Layered PSD state beyond ImageMagick/GIMP/Krita/imagegen. Test separate read/write roots, layers/masks, PSD save/reopen and independent render fidelity. |
| Next | [Agent Desktop](https://github.com/lahfir/agent-desktop) **versus** [MCP-PC](https://github.com/lightnew10/MCP-pc) | Choose one semantic Windows fallback. Test stable element references, policy/audit modes, retry/stop behavior and custom-rendered controls. Prefer native API/MCP, then CLI, before generic desktop control. |
| Experimental | [ANIS](https://github.com/co-evolve-lab/ANIS) | Interface synthesis is promising; native Windows readiness and generated-command correctness remain unestablished. Compare existing CLI-Anything before adding another generator. |
| Demand-driven | SoundCraft **or** Audacity4MCP; DeckCraft; FigCraft; ComfyUI MCP | DAW projects, visual slides, persistent design or local workflow graphs must be a repeated need. Existing artifact/media/design routes already cover common outputs. |
| Watch | SolidCraft, GridCraft, EffectCraft, DesignCraft, WordCraft, VectorCraft, CADCraft | Interface maturity is ahead of app fidelity. SolidCraft needs kernel/rollback/GPU corpus evidence; retain scripted CAD/FreeCAD as a correctness comparison. |
| Watch | Inkscape Live MCP, paper-rs/Sketch, zee-rp, kordoc, Ananasar, ReaCut, video-agent-runtime, muCrab | Track Windows/interface changes and native-file value. Inkscape is an architectural reference for revision guards and uncertain completion; report says macOS-only. |
| Ignore by default | Suite launchers, ArtCraft/LightCraft without a new need, new orchestrators, Open Science Desktop, REA Studio Lab, open-obsidian, DiskLens, Ledger Reborn | Convenience, redundant control planes or no verified agent surface do not expand this harness. Proprietary DAW bridges are conditional on already using that DAW. |

Audacity integrations are different: `jhonsu01/audacity-mcp-server` is principally bounded audio
file processing; `xDarkzx/Audacity4-MCP` needs its companion modified Audacity application for deep
live-project control. Choose SoundCraft or the latter first for a DAW need; test the former against
FFmpeg before calling it new capability. Do not use branded download repositories as verified builds.

ComfyUI MCP and video-agent-runtime names in the conversation lacked recoverable canonical URLs.
Their registry URLs remain null; a similarly named repository is not silently substituted. Several
unconfirmed licenses also remain null. The broad audit's Playwright, Docling and OBS suggestions
are baseline infrastructure comparisons for this work, not fresh adoption requirements. Adobe's
own proprietary suite being open-sourced was not established by these reports; the Craft projects
are independent implementations with separate provenance and licensing questions.

### Shared Blender ten-task benchmark

Run against the same pinned Blender version, source scene and time budget in separate copied
workspaces. Record elapsed time, operation failures, final structured state, exported artifacts,
independent render inspection and permissions. Do not rank adapters by advertised tool count.

1. Start and inspect a persistent scene; reconnect without losing session state.
2. Create, name, transform and inspect a mesh with exact numeric assertions.
3. Discover and execute a supported operator; reject invalid properties explicitly.
4. Apply a modifier and inspect its evaluated geometry.
5. Create a material/node graph and inspect links/properties.
6. Set camera and lights; render and inspect the saved image.
7. Add animation keyframes and verify frame-specific transforms/render output.
8. Save, close, reopen and independently inspect/export the scene.
9. Checkpoint, make a failed or stale edit, and verify rollback/uncertain completion behavior.
10. Attach to a live Windows GUI, observe a human edit and enforce allowed output paths.

No Blender benchmark or candidate application execution is claimed by implementing this registry.

## Verification

The offline acceptance suite is `python -m unittest discover -s tests -p test_capability_watch.py -v`.
It is also wrapped by Pester, so `aos test` runs it under both Windows shells along with the existing
repository checks. See [the validation report](validation/2026-10-21-capability-watch.md) for actual
run counts, live feed results and limits.
