# Capability setup and local trials - 2026-10-21

Application trials started on October 21; final repository checks and the other-vendor review
continued on October 22. Filenames retain the original work date.

The operator authorized continued implementation and actual tools setup. Ten pinned runtime
components were installed under the home folder: seven application routes, one Blender comparison
adapter, Ghidra and JDK. All ten repeated installs validated receipts without downloads/replacement.
The [manifest](../../config/capability-tools.json) records original URLs and full SHA-256 pins;
the [inventory](../research/2026-10-21-capability-installation.json) records actual entrypoint,
dependency-lock/package inventory and artifact hashes. Nothing was globally registered.

## Application evidence

All inputs were owned/generated task fixtures. MCP clients initialized, listed tools, made the
operations below and shut down. Tool counts describe these exact builds, not capability quality.
Raw transcripts/artifacts remain under home-relative `.aos/research/capability-setup-20261021`;
the committed inventory supplies relative names and hashes without machine-specific paths.

| Tool / exact pin | Actual result | Limit / status |
|---|---|---|
| REA 6.7.0 + Ghidra 12.1.4 + Temurin JDK 21.0.12.1+1 | Ghidra-only doctor healthy, Windows x64 native controls available. Generated 1 KiB PE had one procedure; decompile returned `return 0x2a`. Source hash remained unchanged. A generated JavaScript export produced a sealed static application graph. | `sandbox`. No hostile/mutable/sensitive target or application execution. First cold Java probe timed out; direct Java version and subsequent selected-provider doctor passed. Broad doctor stays environment-unhealthy because unused engines/registrations are absent. |
| PdfCraft v0.11.0 | 171 tools. Text PDF -> insert second page -> rotate -> undo -> save -> PNG. Out-of-root read and write both refused. Independent pypdf asserted two pages, expected text and rotation zero; PDFium rendered independently and image was inspected. | `sandbox`. Forms, signatures, OCR, Unicode, complex PDF fidelity and adversarial Windows path corpus omitted. |
| Blender Agent SDK 0.2.0, Blender 5.2.1 LTS | 14 tools. Persistent cube, exact transform, bevel modifier, checkpoints/restore, .blend save/reopen and Cycles 320x240 PNG. A fresh process asserted saved location `[2,3,4]` and Bevel. Material node property read/change worked. Invalid property/operator and script execution were refused. | `sandbox`; preferred bounded headless adapter. Partial benchmark below. Saving/import operators still reach user files; no filesystem sandbox. |
| LogiSheets MCP 0.6.0, engine 1.16.1 | 73 full tools. Semantic orders total 30 -> edit -> 32. Mixed valid/invalid write refused atomically; prior amount stayed 12. Checkpoint restored amount 10. Resolved XLSX independently reopened with openpyxl: `=B1 + B2`, cached 30; ordinary `SUM(D1:D2)` cached 12. | `sandbox`. Block rows contain data without a physical header row. Initial ordinary range formulas into block cells returned `#REF!`; use semantic BLOCKREF/BLOCKREFS then resolve on Excel export. openpyxl warned of missing default style. No filesystem root. |
| FilmCraft v0.10.0 | 17 tools. Created 320x240/24fps two-second color-matte timeline, inserted source, split at one second, inspected two clips, undid to one, saved .fcproj and rendered PNG. H.264 export independently passed ffprobe: 48 frames, 2.000000 seconds, 320x240. | `sandbox`. New inspectable timeline abstraction demonstrated; no claim of superiority to existing Kdenlive/OpenMontage or broad media/interchange fidelity. |
| PhotoCraft v0.12.0 | 25 tools. Two layers, color fill, 0.5 opacity, PSD save/reopen and flattened PNG. Independent PSD section parser found two layers; Pillow found 320x240 and expected blended pixel `[136,102,51]`. Read/write roots configured; out-of-root save refused. | `sandbox`. Mask/vector/complex PSD corpus omitted. PSD 8-bit opacity round trip became approximately 0.502, as expected from quantization. |
| Agent Desktop v0.10.1 | Accessibility available. Only an owned offscreen WinForms fixture was observed. Window-scoped snapshot -> semantic SetValue -> Invoke button -> independent saved marker matched. Wrong-session ref refused. State root redirected to installation profile. | `sandbox`. SetValue reported delivered_verified; click delivered_unverified, so the saved marker supplied commit evidence. No global screenshot/clipboard or unrelated app actions. Protected-window/STOP/custom-rendered-control corpus omitted. |
| blender-mcp 0.11.1, commit `5a9e923f6ae68cfc34a221d31bd1fd5c8aff07f6` | 71 tools initialized. A created object disappeared between separate headless script calls (`AOS_PERSISTENT False`). Native preview generated Python `SyntaxError: 'return' outside function`. | `watch`, pinned failed artifact/execution record. Render error arrived in text with `isError:false`; callers must inspect result content. No upstream code patched to change measured outcome. |

The local registry records eight versioned evaluations and pins; seven moved to `sandbox`, comparator
stayed `watch`. Source/build/execution/artifact findings do not fill unknown license or broader
security admission. No production candidate was created. The exact adapter release feed
`logisheets-mcp/latest` was added and successfully fetched separately from engine releases.
The local registry is home-relative `.aos/capability-watch/registry.json`, selected by
`capabilities-local`; the repository's seed stays portable and unverified. The first full-suite
attempt caught local records incorrectly written into that portable seed. They were preserved in
the local registry; no existing acceptance test was edited. That failed run is retained as
`aos-test.txt`; its remaining second-shell run was stopped and a fresh complete run started.

## Blender comparison coverage

This was a bounded headless comparison, not a completed ten-task parity benchmark. Both used the
same installed Blender build. The SDK was selected for the observed persistent-state/render path;
the comparator's fundamental failures stopped dependent parity work. Preserve the remaining
acceptance cases before making a broader adoption claim.

| Original benchmark row | SDK evidence | Comparator evidence / remaining work |
|---|---|---|
| 1. Persistent scene and reconnect | State persisted across MCP calls; fresh process reopened saved file. Live-session reconnect not exercised. | Separate headless calls lost the added object; no live bridge configured. |
| 2. Mesh, name, transform, numeric inspection | Cube and exact transform asserted. | Raw script created/named mesh; subsequent call lost state. |
| 3. Discover operator, invalid property | Operator discovery, invalid property/operator refusal passed. | Raw script worked; equivalent discovery/refusal corpus omitted. |
| 4. Modifier and evaluated geometry | Bevel applied and independently reopened. Evaluated mesh topology not measured. | Dependent persistent-scene check omitted. |
| 5. Material/node graph | Existing Principled node color read/changed. New graph/link construction omitted. | Omitted after persistence failure. |
| 6. Camera/lights/render | Default camera/light scene rendered Cycles PNG, image inspected. New lighting layout omitted. | Native preview failed with invalid generated Python. |
| 7. Animation | Operator discovery only; frame/keyframe/render checks not run. | Not run. |
| 8. Save/close/reopen/export | .blend reopened in fresh SDK process; state/modifier asserted. External interchange not tested. | Independent raw-script file workflow not scored as persistent server behavior. |
| 9. Recovery/stale edits | Checkpoint -> mutation -> restore asserted; bad operator left server usable. Revision/uncertain completion corpus omitted. | No comparable checkpoint trial after state failure. |
| 10. Live Windows GUI/human edit/output scope | Not run; headless-only selection, output confinement unestablished. | Not run; no live addon/bridge registration. |

## Other candidates and safety review

ANIS's original README requires Linux and describes full-filesystem discovery; no native Windows
install or synthesis is claimed. MCP-PC requires .NET 10, Node gateway and a resident Windows
agent; Agent Desktop was selected for the semantic fallback fixture, so a second control stack
was not installed. Remaining registry candidates retain their prior conditional/watch/ignore
outcomes. No additional account, paid inference, remote tunnel or model downloads were used.

A bounded same-vendor read-only review reproduced two installer defects: Windows batch arguments
could be interpreted by a shell, and check/run/dependency receipt validation omitted current pin
checks. Fixes reject direct batch launches (including npm shims) and share complete receipt
validation with runtime/entrypoint containment. Regressions were observed failing before passing.
The follow-up review caught a receipt claiming `installed:false` that skipped dependency validation;
that condition was removed and the reviewer confirmed the regression passes. A further inline test
rejects Windows trailing-space/dot path aliases before extraction. Existing acceptance tests were
left unchanged; added setup cases were each observed failing before their fixes.
Claude was initially quota-blocked; that was an unavailable review, not a clean verdict. After
the reset, read-only review `20261022-084238-f436-claude-goal-review-agentic-os-s-expli` completed.
No vendor-home/PATH writes were made.

The review voices remain separate:

- **Codex team:** identified and fixed Windows batch interpretation and incomplete receipt checks,
  including the false-ready dependency. The follow-up reviewer confirmed those bounded fixes.
- **Only Claude:** numeric Blender version ordering and uncontrolled corrupt-archive exceptions.
  Both probes were reproduced as failing tests and fixed; the lead then ran 16 passing setup cases.
  Claude did not re-review those final fixes. Its earlier 14-case suite passed.
- **Claude design challenge, lead decision:** automatic retry/cleanup after an incomplete install
  was suggested. The lead retained fail-closed preservation and documented rename/inspect/retry
  recovery, because relocating a Python environment or deleting diagnostic files is inappropriate.
  Whole-manifest receipt binding, incomplete credential-variable filtering and reserved-device-name
  hardening remain documented review limits, not production security assurances.
- **Both vendors:** no shared unresolved concrete defect was established in the reviewed containment
  paths. This is not a claim that all security or fidelity cases have passed.

## Repository verification

- `python -m unittest discover -s tests -p test_capability_setup.py`: 16 passed. Offline fixtures;
  preview, pin mismatch, traversal/link rejection, incomplete install, repeated install, wheel cache
  naming, literal executable arguments, child profile, current receipt/containment, batch rejection,
  Node/npm transport, checked routes, false-ready dependency receipt, Windows path aliases,
  numeric Blender discovery/missing executable and controlled corrupt-archive failure.
- `python -m unittest discover -s tests -p 'test_*.py'`: final 127 passed in 28.940 seconds
  (`python-tests-final-127.txt`). Earlier 123/124/125 runs passed as cases were added.
- Fresh complete-log `aos test`: **exit 0, all green**. Windows PowerShell 5.1 passed 535/535 in
  321.43 seconds; PowerShell 7 passed 535/535 in 411.69 seconds. Both had zero failed, skipped,
  inconclusive or not-run cases. Core parse/ASCII checks passed before Pester started. After the
  last Python fixes, the targeted setup wrapper also passed under Windows PowerShell 5.1 with
  all 16 Python cases (`setup-final-ps51.txt`, 1 selected Pester case, 534 not selected).
- The earlier long-running second attempt reported Windows PowerShell 5.1 535 passed and PowerShell
  7 534 passed/1 failed, after a 31,516.83-second elapsed interval. Its bounded console capture lost
  the failing case identity; the cause is unclassified. It is retained as a failed run, not a clean
  result. The fresh repeat captures complete stdout/stderr in `aos-console-complete.txt` and
  `aos-stderr-complete.txt`.
- Registry schema/semantic validation: 36 candidates and 11 sources passed after evidence update.
- `python -m py_compile tools/capability_setup.py tools/capability_watch.py`, JSON Schema `Test-Json`
  and `git diff --check`: passed on final files. No configured root Python linter or static type
  checker exists; no additional linter/type-check run was claimed.
- Ten actual install repeats, selected launcher smoke commands and selected-provider doctor passed.
  All six MCP stack routes initialized/listed/closed through the actual nested launcher; the Windows
  CLI route and REA selected-provider doctor also passed through their short routes.
  Failed initial broad/cold probes and comparator failures are reported above, not counted as passes.

Raw test logs are retained in the same home-relative research folder. This report's results cover
generated fixtures and the stated versions, not unattended production or arbitrary project fidelity.
