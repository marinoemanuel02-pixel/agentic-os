# Cross-vendor verification of coordination and tools - 2026-10-22

Claude had been out of quota during the capability work, so only Codex had exercised it. After the
weekly reset the Claude lead re-ran the coordination layer and every installed tool from its own side,
with bounded read-only Codex workers for the Codex-side checks. Verified revision: `1032d3e` on
`codex/capability-watch` (the primary checkout, which was read-only for the whole run), plus the two
fixes below on `fix/fullcheck-coordination-defects`. Raw logs, fixtures and receipts are under the
home-relative `.aos/research/full-verification-20261022`; run receipts are in `.aos/coord/delegations`.

## Defects found and fixed

1. **Contracts, packets, checkpoints, procedures and swarm contracts failed in every OneDrive-hosted
   checkout**, including the primary one (`unsafe relative task path through a link`).
   `Resolve-AosTaskFile` rejected any item with the `ReparsePoint` attribute; OneDrive Files On-Demand
   sets it on every synced file (tag `0x9000A01A`, empty `LinkType`). Earlier validation ran in
   worktrees outside OneDrive. The same contract registered in one and failed in the other. The guard
   now refuses every reparse point except an exact cloud-files tag (`0x9000001A` and the `CLOUD_1..F`
   family) with no `LinkType`, and fails closed when the tag cannot be read. Real junctions, symlinks,
   mount points, ProjFS and dedup tags stay refused.
2. **`waiting_seconds` was inflated by the local UTC offset under PowerShell 7** (a 3 s wait recorded
   7204 s; a 29 s wait in a real Codex round trip recorded 7229 s). The stored stamp comes back as a
   `DateTime` and was re-parsed from text. The existing test asserted only `>= 3`, which an inflated value
   satisfies. `Get-AosElapsedSince` now normalizes the kind directly (no text, so no fraction loss and no
   calendar dependence) and both consumers use it (`Set-AosRunState`, the delegate receipt).

Tests added in `tests/aos.Tests.ps1`: four, all seen failing before the fix (2 in Windows PowerShell 5.1,
3 in PowerShell 7, the offset regression only in PowerShell 7). The cloud-placeholder case is mocked because a
cloud-tag file cannot be created without a sync provider; the real tag was verified on this machine's
OneDrive files in both shells (`README.md` reads `0x9000A01A`; 373 tracked files resolve; contract registration
and a checkpoint cold check pass). Independent review: Codex reviewed the first revision (raised that
accepting any empty-`LinkType` reparse point was broader than the evidence, that the helper still lost
fractions and depended on the culture calendar) and the revised delta (struct layout, mask arithmetic and
fail-closed behaviour confirmed; one remaining concern, a test formatting a stamp with the current culture,
was fixed and re-run but not re-reviewed). Its other pointer (`aos.psm1` rollout-log timestamp) was checked: PowerShell 7 loses only sub-second digits there,
no offset shift; left unchanged.

## Results

| Area | What ran | Result |
|---|---|---|
| Full `aos test` | both shells, parse and ASCII first | primary checkout (run started at `5445d24`, `1032d3e` landed during it): 535/535 per shell, 753 s; with the fixes: **539/539 per shell, 0 failed, 0 skipped, exit 0, 630 s** |
| Python / Node / plugin | `unittest` (all), `node --test` app-server and hook, status-pane data layer | 127 OK / 31 pass / 5 of 5 (`pane.test.ts` needs the Claude mod runtime and cannot run under Node) |
| Coordination, offline | `coordination-smoke.ps1`, six-case eval preparation, `capabilities` and `roles --dry-run`, `sync -DryRun`, `status` | smoke all true (reply while alive, cancel confirmed, third actor refused, launch failure cleaned, real profile untouched); roles unchanged; sync idempotent; status all `ok` |
| Coordination, live | five Claude-to-Codex read-only workers (wiring check, message round trip, two reviews, one contract task), Codex contract task over the **App Server transport**, Claude contract task over exec, addressed message round trip, Codex to Claude review (receipt from the Codex lead), two native Claude children with the managed `aos-verify` role, lead-to-lead notes | all accepted; host verifier exit 0 on both contract tasks; message round trip completed with the worker alive (reply read, acknowledged); first native child stopped at its 16-turn role limit and continued with a fresh budget |
| Coordination negatives | stale checkpoint, continuation check with healthy source capacity, cross-lead `send`, over-long `wait` | each refused with the expected reasons (`Valid:false`, `source quota limit is not currently confirmed`, `messages must stay within one task tree`, `wait must be between 0 and 45 seconds`) |
| Capability components | `capability-setup check` for all ten pins | all ten installed and valid |
| MCP servers | own stdio client: initialize + `tools/list` | pdfcraft 171, blender-agent-sdk 14, logisheets 73 (full), filmcraft 17, photocraft 25, blender-mcp 71: all equal the recorded counts |
| Tool operations | see below | PASS unless listed under limits |
| Stack (14 approved) | `stack verify` | 11 passed offline; composio (live discovery, 11 tools), omniroute (one free request) and voicestudio (app started for the check, stopped afterwards; Italian and English non-silent clips) passed when run |
| Swarm pool | one free packet, lead-written verifier | gemini free tier, 1.7 s, host-accepted |
| Local model / MCP | `nar_status`, embed classification (3 of 3 correct incl. Italian); `context7` and `nar` registered in both agents | pass |
| CLI and media sweep | ffmpeg, ImageMagick, pandoc, DuckDB, Inkscape, Blender, melt, yt-dlp, Playwright, Whisper CLI, node, uv, gh, rg, fd, jq, ollama, GUI apps present | pass; one `melt` render failed once while the machine was loaded and passed in 6 of 6 reruns (unexplained) |

Tool operations verified independently (two Claude native children ran the MCP checks and left raw outputs on
disk; the lead re-ran the FilmCraft replay and export, the Blender render and Agent Desktop itself): PDF (open, text, render, out-of-root and `..` refused, **AcroForm field
fill, save, reopen**), Blender SDK (cube, exact transform, save and fresh-process reopen, bad operator, parameter
and property refused, checkpoint restore, a real Cycles render, **animation midpoint, modifier**), LogiSheets
(formula `SUM` = 12, refused bad sheet, saved XLSX contains the formula and cached value), FilmCraft (sequence,
matte, split, undo, save, H.264 export: 320x240, 48 frames, 2.000000 s by `ffprobe`), PhotoCraft (two layers,
**layer mask**, PSD, out-of-root save refused), Agent Desktop on an owned offscreen window (snapshot, set-value,
invoke, wrong-session ref refused, marker file as commit evidence), REA/Ghidra doctor healthy.

## Tool behaviour worth knowing (not repository defects)

- Blender SDK: `anim.keyframe_insert` stored a stale value for the second key (edit the key afterwards); changing
  `frame_current` alone does not re-evaluate animation (call `screen.frame_offset` with delta 0); nodes cannot be
  added or linked headless (no node-editor area); `object_info` reports base-mesh counts, not evaluated ones.
  `--render-engine` applies only inside screenshots and the route already defaults it to Cycles.
- PhotoCraft: a file saved in the write root must be copied to the read root to reopen. FilmCraft starts with no
  sequence. `coord wait` is capped at 45 s. `aos coord native` imports signals only for supervised delegate runs.
- Agent Desktop: one `set-value` produced `A AGENT-DESKTOP-42`; not reproduced in 9 later attempts, one of them in a fresh window.

## Cross-vendor verdicts (kept separate)

- Both vendors confirmed that a failed npm or wheel install cannot be retried until its runtime folder is moved
  (`docs/capability-setup.md` records this as deliberate). Claude's earlier review also reported numeric Blender
  discovery and archive errors (that review was requested by the Codex lead); the Codex worker did not confirm them
  against current code (already fixed in `5445d24`).
- The two defects above were flagged only by Claude; Codex's earlier validation did not see them. Codex reviewed
  the fixes in two rounds; the concerns it raised are resolved as described above.
- Codex-side wiring (Claude hooks and roles, Codex roles, versions `codex-cli 0.163.0` and Claude Code `2.1.302`,
  App Server login gating at `tools/codex-app-server.mjs`) was confirmed by a read-only Codex worker.

## Not covered

License and full security admission; OS-level isolation; hostile or mutable targets for REA; PDF signatures, OCR and
complex fidelity; Blender live GUI, node graphs and evaluated geometry counts; Excel interchange with a second
library (none installed); FilmCraft real-media corpus; PhotoCraft mask and opacity after a PSD round trip and complex
PSDs; Agent Desktop protected windows, custom controls and the STOP policy; swarm failover, embedding, image and audio
capabilities and the live contract bridge; `coordination-compare`, `coord steer` and the positive continuation path
(they need a real active turn or quota limit; covered by the 31 Node and the Pester tests only); the status pane's
live rendering; ANIS and MCP-PC, which are not installed.
