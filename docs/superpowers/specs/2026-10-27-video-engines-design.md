# Video pipeline: real-time engines and procedural tools (design, as built)

Status: built on branch `feat/video-engines` (2026-10-27). Inputs: two deep-research reports the user ran (Perplexity
and ChatGPT), used as leads only; every claim the build relies on was re-checked against the machine, the repo or a
vendor page. Rules R55-R57; decision entry 2026-10-27 in `docs/decisions.md`; how-to in
`templates/video/engines/README.md`.

## Why

Picture came from Remotion, R3F inside Remotion (`@remotion/three`) and Blender (R41-R49). Nothing simulated many
interacting things in real time, and EEVEE costs 5.6-16 s per frame on this laptop (R43). The user wants more tools
available, each in its own lane, under one design system (R28).

## Baseline (measured 2026-10-27)

| Item | Value | Consequence |
|---|---|---|
| GPU | GeForce GTX 1660 Ti, 6 GB VRAM, no RT cores | No RTX-only features (Omniverse RTX, hardware Lumen); Unreal path tracing untested |
| RAM / disk | 16 GB; C: 79 GB free, D: not mounted | Unreal is the only candidate where disk decides |
| Already in stack | Remotion + R3F/three, Blender 5.2, ffmpeg 9 | "Add three.js/R3F" from both reports was already done |
| Blender pattern | `blender/shots.json` -> `tools/render-shot.py` -> `app/public/clips/<id>.mp4` + `src/data/media.json`, R50 exposure gate, render log | Engines plug into it; no second contract |

## What the research got right, wrong, or unverified

| Claim | Report | Check | Result |
|---|---|---|---|
| Godot Movie Maker: `--write-movie`, `--fixed-fps`, `--quit-after`, `--resolution`; non-real-time; PNG sequence + WAV | both | Godot 4.7 stable docs | **Verified.** No EXR writer in the docs; headless (`--headless`) not covered |
| Godot is MIT, no revenue cap | both | known, reports cite godotengine.org/license | Verified (standard) |
| Manim Community license | P: "unverified" | repo LICENSE | **MIT** (copyright 3Blue1Brown LLC) |
| Cavalry is free | P: free via Canva; G: Starter capped 1080p | CG Channel 2026-04, Cavalry CLI docs | **Full app free for individuals incl. commercial since 2026-04; Canva account required at launch; studios need paid Canva.** G's 1080p cap is outdated. **CLI render is legacy and "not available in 2.7 or above"** (and was Enterprise-only before) |
| Autograph free for commercial use with CLI + Python | P only | Maxon press release 2026-05-07, CG Channel | **Verified** (Maxon App account). Windows CLI behaviour and GPU needs untested |
| Unreal 5.8 has an official, experimental MCP | G | third-party guides, Epic forum thread on "ModelContextProtocol toolsets" | **Corroborated, not read on Epic's own page.** Local server at 127.0.0.1:8000, no auth, serial on the game thread, Experimental |
| Unreal: rendered video royalty-free, seats free under $1M revenue | both | not re-opened today; P cited a unity.com URL for it (miscitation) | Known pre-2026 terms; **re-check at install** |
| Unity Personal: $200K, and for service providers the **client's** finances count | G (P similar) | unity.com Personal/plans pages | **Verified.** Own films: fine. Client work: depends on the client |
| Omniverse free since 2026-05, ranked #4 | G | NVIDIA lists RTX GPUs | **Irrelevant here: no RTX card** |
| PlayCanvas "Editor 2.35 projects over MCP, Oct 2026" | G | search | Version/date **not found**; an official `@playcanvas/editor-mcp-server` exists (acts on the project open in a browser Editor) |
| Rive: free tier usable for video | P: unverified; G: splash | Rive blog | **Exports moved to paid plans on 2025-10-20.** Excluded |
| TouchDesigner, Houdini Apprentice, vvvv, Notch: free tiers non-commercial or trial | both agree | consistent with known terms | Excluded for monetized/client work; study only |

## Lanes (R55)

| Lane | Tool | Status |
|---|---|---|
| Master, type, captions, 2D, compositing | Remotion | in stack |
| Frame-exact GPU scenes in the cut | R3F/three inside Remotion | in stack |
| Hero sets, scanned assets, offline sims | Blender | in stack |
| Real-time procedural 3D, many interacting parts | Godot 4.7.2 | installed (173 MB, `~/.local/bin/godot`), demo rendered |
| Mathematical notation and mechanisms | Manim CE 0.22 + TinyTeX | installed (venv 372 MB, TinyTeX 386 MB), demo rendered |
| Cinematic worlds, MetaHuman people | Unreal 5.8 | adapter written; spike needs Epic account + disk decision |
| Timeline/Cinemachine shots (own films; clients only under $200K) | Unity 6 | adapter + `AosRender.cs` written, unverified; needs Unity ID |
| Finishing / compositing | Autograph via `cmd` | adapter tested with a stand-in; needs Maxon account and CLI check |
| Hand-designed vector motion | Cavalry via `import` | adapter tested; needs Canva account; GUI render only |
| Excluded | Omniverse, TouchDesigner, Houdini Apprentice, vvvv, Notch, Rive, Spline | hardware or licence |

## What was built

- `tools/engines.py`: engine table (`engines/shots.json` joins `blender/shots.json`, one id per table), adapters
  (godot, manim, unreal, unity, cmd, import), frame-complete runs (fewer frames than preroll + n fails; known
  failure lines such as Godot's `SCRIPT ERROR` fail even on exit 0), encode to H.264 like the asset proxies (EXR gets
  one sRGB conversion), Manim's transparent mov expanded over the look background, `--repeat` determinism.
- `tools/render-shot.py`: dispatch per engine. The Blender path, key and command are unchanged, so existing films do
  not re-render. Engine shots get the same clip, render log (now with `engine`), media row, state and exposure gate;
  a shot may move the gate only with `luma_why`, recorded in media.json. Shots without `edit.json` take `frames`
  from their entry. `--force` no longer leaks into the shot list.
- `tools/cache/keys.mjs` + `plan.mts`: a clip owned by a media.json row keys only its shot's segment instead of the
  global environment digest; segments without clips keep their old keys.
- `tools/export-look.mts`: `engines/look.json` (fps, calm-curve points, fonts, looks) from `look.ts`; `--check`
  refuses a stale one and render-shot runs it before engine shots.
- Kits: `engines/godot` (project, `lib/aos_shot.gd` base with the calm curve, demo `s_tokens`), `engines/manim`
  (`aos.py`, demo `s_attention`), `engines/unity/Editor/AosRender.cs`, `engines/README.md`.
- Tests: `tools/checks/engines_test.py` (17, a stand-in engine writes frames; render cases skip without ffmpeg) and
  two cache tests; Pester runs both and the look check. Guards were mutation-checked (frame-count and preroll).
- Rules R55-R57, template AGENTS.md line, tool-catalog entry, decision entry.

## Found while building (each now guarded)

| Finding | Guard |
|---|---|
| Godot exits 0 and renders an empty scene when a shot script fails to parse | `FAIL_ON` + test |
| Manim 0.22 `--format png` saves one frame; `png-sequence` skips held frames (3 s scene -> 61 PNGs) | transparent mov (qtrle, lossless, every frame) + expand test |
| Manim's partial-movie paths pass Windows MAX_PATH under deep media roots | short `m` media folder |
| A wide, sparse graph shot fails R50 (luma 26) | reframed the shot; gate moved only with a written reason |
| Every re-rendered clip would have re-rendered the whole film (public/ in the global digest) | per-segment clip keys + test |

## Measured (1920x1080, 30 fps, this laptop)

| Shot | Frames | Time | Rerun of 30 frames |
|---|---|---|---|
| Godot `s_tokens` (48 nodes, 320 tokens, glow, fog, MSAA 4x) | 186 | 100-139 s incl. startup (0.5-0.75 s/frame) | pixel-identical |
| Manim `s_attention` (MathTex, 36 cells) | 426 | 60 s (0.14 s/frame) | pixel-identical |

## Open (needs the user)

1. Accounts: Epic (Unreal), Unity ID, Maxon (Autograph), Canva (Cavalry). Agents never create them.
2. Unreal disk: C: has 79 GB free and D: is not mounted.
3. Unity licence stance for client work.
4. Each spike's gate: one finished shot from a real script line, rendered unattended twice, contact sheet reviewed by
   the other vendor, determinism recorded, seconds per frame logged.

## Sources (opened or searched 2026-10-27)

- Godot Movie Maker (4.7): https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html
- Manim licence: https://github.com/ManimCommunity/manim/blob/main/LICENSE
- Cavalry free: https://www.cgchannel.com/2026/04/canva-makes-motion-graphics-and-animation-app-cavalry-free/
- Cavalry CLI (legacy, not in 2.7+): https://cavalry.studio/docs/applications/cavalry-cli/
- Autograph free + CLI/Python: https://www.maxon.net/en/article/maxon-makes-autograph-free-for-teams
- Unity Personal / service providers: https://unity.com/pages/license-compliance , https://unity.com/products
- Unreal 5.8 MCP (third-party + Epic forum): https://dev.to/gamedevtoollab/using-unreal-mcp-in-ue-58-from-codex-setup-toolsets-and-safe-editor-automation-4pon ,
  https://forums.unrealengine.com/t/feedback-after-using-modelcontextprotocol-toolsets-agentically/2731505
- Unreal ray/path tracing requirements: https://dev.epicgames.com/documentation/en-us/unreal-engine/ray-tracing-and-path-tracing-features-in-unreal-engine
- Rive exports paid: https://rive.app/blog/new-pricing
- PlayCanvas Editor MCP: https://developer.playcanvas.com/user-manual/editor/mcp-server/
