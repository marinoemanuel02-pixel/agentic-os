# Optional capability tools

Discovery remains `python tools/stack.py capabilities refresh`. It never installs or starts a tool.
Setup is a separate, explicit command using the pins in
[`config/capability-tools.json`](../config/capability-tools.json). The operator authorized this
setup pass; seven applications and the Blender comparison adapter are now installed locally,
with Ghidra and its release-matched JDK as dependencies.

```powershell
python tools/stack.py capability-setup list
python tools/stack.py capability-setup install pdfcraft          # preview; no writes/network
python tools/stack.py capability-setup install pdfcraft --apply  # exact pinned payload
python tools/stack.py capability-setup install rea --apply       # includes JDK and Ghidra
python tools/stack.py capability-setup check rea                 # receipt/pin/entrypoint check
```

Run from this repository. Payloads live under `~/.aos/tools/capabilities/<tool>/<version>`;
receipts and package lockfiles remain there. Downloads are checksum-addressed under `downloads`.
Repeating an install verifies its existing receipt and entrypoint instead of replacing files.
Conflicting or incomplete targets fail for inspection; nothing is deleted automatically. The
helper's global `--root <directory>` supports a separate installation root before the action.
The short stack routes below use the default home-folder root.

After an interrupted install, inspect its reported target and confirm no process owns it or its
lock. Preserve the incomplete folder under a new sibling name before retrying the original
install. Renaming preserves diagnostic files; do not run a relocated Python environment. Never
remove a live owner's lock or a ready receipt to force replacement. Refusing an automatic retry
over incomplete files is deliberate; setup does not decide which files are disposable.

| Route | Installed pin | Intended use / current limit |
|---|---|---|
| `rea` | 6.7.0, Ghidra 12.1.4, JDK 21.0.12.1+1 | Static copied native PE and JavaScript/Electron evidence. Never run `rea setup` for this integration: it writes agent registrations. |
| `pdfcraft` | v0.11.0 | Persistent PDF edits and render feedback. Use `--root`; complex forms/signatures/OCR still need a corpus. |
| `blender-agent-sdk` | 0.2.0 with existing Blender 5.2.1 LTS | Preferred headless scene controller: state, checkpoints, properties and renders passed. Execution disabled by default; no filesystem sandbox. |
| `logisheets` | MCP 0.6.0, engine 1.16.1 | Semantic workbook blocks and resolved Excel exports. Use `BLOCKREF` for block cells. No filesystem confinement. |
| `filmcraft` | v0.10.0 | Inspectable NLE timelines, split/undo and exports. Existing Kdenlive/OpenMontage stay available. |
| `photocraft` | v0.12.0 | Layered PSD edits; configure separate automation read/write roots. Complex masks/PSD fidelity not established. |
| `agent-desktop` | v0.10.1 | Windows accessibility fallback scoped to a selected window and session. Verify the application's committed result after actions. |
| `blender-mcp-benchmark` | 0.11.1 at `5a9e923f6ae68cfc34a221d31bd1fd5c8aff07f6` | Comparison only: observed headless state loss and render script failure. |

No server runs until called. No persistent MCP registrations, agent-home edits, global PATH
changes, model downloads or external inference were added. A host that supports per-task stdio
servers can launch the same commands; close its client after the task. Do not add all tool schemas
to startup. The command-line forms also work without MCP.

`python tools/stack.py capabilities-local list` reads this machine's actual evaluation registry
at `~/.aos/capability-watch/registry.json`; it holds seven sandbox entries and the failed comparison.
The ordinary `capabilities` command uses the portable reviewed seed in this repository. On another
machine, create a separate copy of that seed without replacing an existing local registry, then
use `capabilities-local record/status/refresh` for its own evidence. Installation alone never
copies or changes an admission status. Committed reports describe only this recorded setup pass.

```powershell
# Pick existing task copies explicitly; resolve paths at runtime.
$taskRoot = (Resolve-Path ./work/pdf-task).Path
python tools/stack.py pdfcraft mcp --root $taskRoot

$readRoot = (Resolve-Path ./work/image-input).Path
$writeRoot = (Resolve-Path ./work/image-output).Path
python tools/stack.py photocraft mcp --automation-read-root $readRoot --automation-write-root $writeRoot

python tools/stack.py blender-agent-sdk mcp --render-engine CYCLES
python tools/stack.py logisheets
$project = (Resolve-Path ./copied-project.fcproj).Path
python tools/stack.py filmcraft --project $project inspect sequence
$target = (Resolve-Path ./copied-target.exe).Path
python tools/stack.py rea doctor --provider ghidra --format json
python tools/stack.py rea inspect $target --provider ghidra --format json
python tools/stack.py rea decompile $target 0x140001000 --provider ghidra --format json

python tools/stack.py agent-desktop list-windows --app <exact-application-name>
python tools/stack.py agent-desktop snapshot --window-id <returned-w-id> --session <task-session>
```

File arguments should be absolute: the helper starts each tool in its own runtime directory.
Replace the example file names, address and window/session placeholders for the actual task.
FilmCraft can use `--data-dir <task-profile>` for task-specific presets. For full LogiSheets tools,
set `LOGISHEETS_MCP_TOOLS=full` in that child's environment; its normal list is smaller. On Excel
handoff, call `save_workbook` with `resolve_block_refs: true` and independently reopen the result.
Resolving semantic formulas is an export choice; keep a separate native-semantic copy if needed.

Agent Desktop state is redirected with `AGENT_DESKTOP_HOME` under its runtime profile. Snapshot
references include a snapshot id and belong to their session. A successful action delivery is not
proof of application save: the fixture click reported `delivered_unverified`, while its written
marker provided the independent commit check. Retry only according to delivery evidence.

## Installation and admission boundaries

Archives/wheels/source payloads must match the reviewed HTTPS origin and SHA-256. The helper's
archive extractor rejects traversal, drive escapes, Windows trailing-space/dot aliases, links and
special files, with download/expansion limits. npm lifecycle
scripts are disabled; the installer invokes `npm-cli.js` through Node rather than a Windows batch
shim. Direct `.bat`/`.cmd` launch is refused because Windows interprets metacharacters even with
`shell=False`. REA owns its separately tested Ghidra provider transport; no general batch adapter
was introduced.

Python environments and npm prefixes are per tool. Root artifacts are pinned, but package-manager
transitive dependencies and Python build tooling are not a hermetic, hash-locked supply chain.
Actual package inventories and lock hashes are recorded in the installation inventory; retain
runtime locks, review upgrades and do not treat a changed dependency resolution as equivalent
evidence. Receipts check the launch entrypoint, not the hash of every installed file. Blender is
discovered from the existing installation rather than installed/pinned by this helper; repeat its
workflow checks after upgrading Blender. Discovery compares version numbers numerically and
reports a missing Blender installation before launching an adapter.

The launcher strips commonly named credential variables and redirects child profile/cache/temp
settings. It still runs as the user: home files, credential stores, subprocesses and network access
are not isolated by those settings. Explicit application roots provide only the tested application
boundary. Use copied inputs; use an actual restricted OS account/container/VM for untrusted targets
or arbitrary code. Do not pass execution-enabling options from external source text.

ANIS remains on watch: its original requirements say Linux and full-filesystem discovery. This
native-Windows pass did not run synthesis or claim generated commands as verified. MCP-PC remains
the alternative to Agent Desktop; it requires .NET 10 plus a built Node gateway and a long-lived
Windows agent. Its policy/tray/STOP architecture merits a separate need-driven trial, not a second
automatic desktop-control installation. Remaining watchlist tools follow the registry's tiers.

See [actual results and omissions](validation/2026-10-21-capability-setup.md). Every adopted trial
remains `sandbox`; license review, broader security cases and real-project fidelity are incomplete.
Refresh and installation cannot promote a tool to production.
