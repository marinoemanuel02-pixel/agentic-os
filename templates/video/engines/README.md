# Engine shots

Shots that Remotion, R3F and Blender do not cover well are rendered by an engine and enter the film as a clip, the
same way Blender sets do (rules R55-R57). The lanes:

| Engine | Use it for | Status here |
|---|---|---|
| Godot 4.7 (`godot/`) | Real-time procedural 3D with many interacting parts: agents, crowds, token flows, graphs, stylised worlds; cheap iteration where EEVEE costs 5-16 s/frame | installed, demo `s_tokens` rendered |
| Manim CE (`manim/`) | Mathematical notation and mechanisms: equations that become geometry, matrices, algorithms | installed with TinyTeX, demo `s_attention` rendered |
| Unreal 5.8 | Large cinematic environments, Niagara, PCG, MetaHuman people | adapter written, not run: needs an Epic account and a disk decision (tens of GB) |
| Unity 6 | Timeline + Cinemachine shots, VFX Graph; the user's own films unless a client is under Unity Personal's $200K limit (the client's finances count) | adapter and `unity/Editor/AosRender.cs` written, not run: needs a Unity ID |
| cmd | Any program that writes numbered frames: Autograph (free, CLI + Python) for finishing, scripts | adapter tested |
| import | A clip or frame folder rendered by hand: Cavalry (free for individuals, GUI render only), any GUI tool | adapter tested |

Text, titles and captions stay in Remotion; Manim keeps only mathematical notation.

## Table and render

`engines/shots.json` lists the shots (Blender sets stay in `blender/shots.json`; an id may be in only one):

```json
{
  "S04": {"engine": "godot", "scene": "res://shots/s_tokens.tscn", "shot": "wide", "seed": 7},
  "S09": {"engine": "manim", "script": "s_attention.py", "scene": "Attention", "seed": 3,
          "luma": [25, 225], "luma_why": "thin notation on the near-black look"},
  "S12": {"engine": "unreal", "uproject": "../unreal/Film.uproject", "map": "/Game/Shots/S12",
          "sequence": "/Game/Shots/S12_Seq.S12_Seq", "config": "/Game/Render/MRQ_PNG_30.MRQ_PNG_30",
          "output": "../unreal/Saved/MovieRenders/S12", "inputs": ["../unreal/rev.txt"]},
  "S15": {"engine": "unity", "project": "../unity", "scene": "Assets/Shots/S15.unity", "shot": "close",
          "inputs": ["../unity/rev.txt"]},
  "S20": {"engine": "cmd", "cmd": ["autograph-cli", "...", "{frames}"], "inputs": ["comp/s20.agp"]},
  "S22": {"engine": "import", "source": "renders-in/cavalry/S22.mp4"}
}
```

Common fields: `frames` (only when there is no `src/data/edit.json`), `preroll` (rendered, then dropped), `seed`,
`shot` (variant), `color` (`"linear"` for scene-linear EXR, the default; `"display"` for EXR that is already
display-referred), `fail_on` (extra log lines that mean failure), `luma` + `luma_why` (move the exposure gate for a
deliberately dark or bright shot; the reason is recorded in `src/data/media.json`).

- `node --no-warnings tools/export-look.mts` writes `engines/look.json` from `src/lib/look.ts`; render-shot refuses to
  render an engine shot while it is stale.
- `python tools/render-shot.py S04 S09 [--scale 50] [--repeat 30] [--force]` renders frames, encodes
  `<media>/app/public/clips/<id>.mp4`, logs seconds per frame, writes the `media.json` row (with `engine`) and runs the
  exposure gate. `--repeat 30` renders the first 30 frames twice and records `determinism` (pixel-identical or differs: decoded frames compared).
- A re-rendered clip re-renders only the Remotion segments of the shot that plays it (`tools/cache/keys.mjs`).
- Binary projects (Unreal, Unity) cannot be hashed cheaply: list a `rev.txt` (or any file you bump) in `inputs`.

## Godot (`godot/`)

Shots extend `res://lib/aos_shot.gd`: build the world in `build()`, set everything from the frame number in
`pose(f)` (no accumulated state, seeded randomness), move with `tween`/`move` (the template's calm curve). Look-dev:
open `engines/godot` in the Godot editor, or run a shot windowed with
`godot --path engines/godot res://shots/s_tokens.tscn -- --shot=wide`. Godot's `.godot/` cache is not committed.
Godot exits 0 when a shot script fails to parse and renders an empty scene; render-shot fails on `SCRIPT ERROR`.

## Manim (`manim/`)

Scenes import `aos` (look colours, `soft` rate function, `finish(self)` at the end so the shot reaches its length).
Render by hand: `~/.aos/venvs/manim/Scripts/manim render engines/manim/s_attention.py Attention -ql`. Manim's
png-sequence skips held frames, so render-shot asks for a transparent mov (lossless) and composites it over the look.
TinyTeX lives in `~/.aos/tinytex`; render-shot puts it on the render's PATH only.

## Unreal, Unity, Autograph, Cavalry (first spike)

- Unreal: make a Movie Render Queue preset per output (PNG or EXR, fixed spatial/temporal samples, warm-up frames,
  output folder = the shot's `output`), render the whole shot in one process. Epic's MCP (5.8, experimental) is for
  look-dev only.
- Unity: copy `unity/Editor/AosRender.cs` into the project's `Assets/Editor/`, install Recorder; the script is
  unverified until the spike runs it.
- Autograph: use a `cmd` shot once its CLI is confirmed on Windows; frames go to `{frames}`.
- Cavalry: render from the app (its CLI renderer is not available in 2.7+), then `import` the clip or frames.
