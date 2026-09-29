# The video process: a general pipeline that learns

Date: 2026-09-29. Status: shape approved in conversation; this spec awaits the user's review.

## Why this exists

The user wants a general video pipeline for many kinds of material, run by the harness (Claude, Codex,
the local model and their tools), producing "an articulated video up to upload standards, leveraging
latest practices"; "it's more important to refine the process itself". Free only: no paid generation
services. Three attempts on 2026-09-29 (an AGI-race / AI-safety test) failed, and each failure was a
process failure, not a tool failure:

| Attempt | What it was | The user's verdict | What the process lacked |
|---|---|---|---|
| 1 | Remotion shapes and captions, local voice | "basic infographics" | a definition of good; craft standards |
| 2 | SDXL key frames with depth-parallax camera moves | "a carousel of images" | structure from a shot list; motion inside shots |
| 3 | LTX-Video image-to-video clips (~110 s per 4 s clip on the GTX 1660 Ti) | "clearly AI slop and useless general AI generation" | a cheap look check before production; an anti-slop gate |

The common cause: production started on guesses, with no agreed target, no cheap preview and no gate
that could catch "basic", "carousel" or "slop"; and nothing turned a rejection into a rule.

## Success criteria

1. Every video goes through the stages below; production never starts before the user has approved the
   definition of good, a style frame and a rough cut.
2. The process routes material to the right engine: a motion-design explainer and an edit of the user's
   own footage both run through it end to end.
3. Every render passes automated technical checks and a craft review against the video's checklist and
   the anti-slop list before the user sees it.
4. After every video, a retrospective adds at least one rule, check or skill update when something was
   rejected; the rules are applied automatically to the next video.
5. The user can approve every gate from the phone (Paseo).

## The stages

1. **Brief and definition of good.** Purpose, audience, platform (sets the upload profile), length, type
   of material. Two or three references: the user's, or ones the director finds and proposes. From them a
   short scoring checklist (`rubric.md`: what "good" means for this video, 5-8 items). *Gate: the user
   approves the checklist.*
2. **Look development.** Two or three still style frames rendered by the engine that will produce the
   video (not by a different tool), with type, colour, composition and one representative element each.
   *Gate: the user picks one; it becomes the style lock (`style.md` + the frame).*
3. **Structure.** Script, beat sheet, and a shot list written visual-first: every shot has a purpose, a
   motion (subject and/or camera), a duration (typically 2-4 s) and a transition; cuts land on the beat.
   Then an **animatic**: the timed rough cut with placeholder visuals, a scratch voice and the chosen music.
   *Gate: the user approves the rough cut.*
4. **Production**, routed by material (below). Shots are independent tasks and can be built in parallel.
5. **Quality gates** on every render (below). A failed gate goes back to production with the reason.
6. **Revision loop.** The user's notes become revision tasks; each version keeps a before/after.
7. **Retrospective.** What failed and which gate should have caught it; the answer becomes a rule in
   `video-rules.md` (shared, applied to every future video), a new automated check, or a skill update.
   The first three rules come from the attempts above.

## Routing by material

| Material | Engine | Notes |
|---|---|---|
| Explainers, motion graphics, product and data videos | Code: Remotion (React), three.js / react-three-fiber for 3D with real lighting and materials, shaders, Manim for math | The main path for "made from these models alone"; the models write the animation code |
| The user's footage, talks, interviews, screen recordings | Edit pipeline: FFmpeg, silence removal, local Whisper subtitles, OpenTimelineIO or editor project handoff | Rough cut automated; fine edit optional in Kdenlive / DaVinci Resolve |
| 3D worlds and objects | Blender through an MCP server, or three.js | Free asset libraries (CC0) |
| Real-motion B-roll | Free footage from the sources in "Footage sources" below, graded to the style lock | Never ungraded, never generic filler; every clip logged in `credits.md` |
| Generative images or video | ComfyUI (installed, ~17 GB of models) | Opt-in per video only, and it must pass the anti-slop gate like everything else |

Voice: local TTS (Kokoro, English; an Italian-capable local voice to be chosen), or the user's own
recording. Music and effects: free licensed libraries; loudness mixed to the platform profile.

## Footage sources

Decided 2026-09-29: Pexels' API key issuance is paused ("New API key issuance is currently paused" at
pexels.com/api), so the first two sources need no key at all. Checked live the same day:

| Source | Key | Use it for | Licence handling |
|---|---|---|---|
| NASA Image and Video Library (`images-api.nasa.gov/search?media_type=video`) | none | space, Earth, science, engineering | Generally not copyrighted in the US. Never imply NASA endorses the video or a product; no NASA logo or insignia in commercial use; identifiable current NASA employees or astronauts need permission for commercial use; third-party material embedded in NASA content stays restricted; credit NASA when practicable |
| Internet Archive (`archive.org/advancedsearch.php`, item metadata at `archive.org/metadata/<id>`) | none | historic and public-domain footage (for example the Prelinger collection) | Per item: use a clip only when its `licenseurl` says public domain or CC0, or a Creative Commons licence whose terms the video meets and the credit is given; no licence field means do not use it |
| Pixabay video API (`pixabay.com/api/videos/`) | free, after registration; not yet registered | general stock B-roll | Content License; no mass downloading (100 requests per 60 s), attribution requested, keep the key in `aos secret` |
| Pexels | paused | (later, if it reopens) | free licence, credit optional |

Every footage clip used is logged in the project's `credits.md`: source, URL, licence, author or agency,
date fetched. The fetch step refuses a clip it cannot log a licence for.

- **Technical checks (scripts, Codex-built):** resolution and frame rate of the platform profile; audio
  loudness (YouTube: -14 LUFS integrated, true peak <= -1 dBTP); captions present and in sync; text inside
  safe areas and above a minimum size; no black, frozen or duplicated frames; file encodes and plays.
- **Craft review (director model with vision, on contact sheets):** each checklist item scored; compared
  with the references and the style lock; the **anti-slop list**: generic stock look, visuals that do not
  carry the point of the line they illustrate, AI artifacts (melting, extra limbs, garbled text), style
  drift between shots, slideshow pacing (static shots, one visual per sentence), motion that goes nowhere.
- **Frame screening at volume (local model, qwen3.5 reads images):** flags frames for artifacts and
  drift so the director reviews only candidates; runs free and private; results scored with nar.

## Roles

| Who | Does |
|---|---|
| Claude (director and producer) | brief, references, checklist, structure and shot list, craft review, retrospective |
| Codex (builder) | engines and scene code, edit assembly, technical-check scripts, shots in parallel |
| Local model | frame screening and tagging, transcript triage, cheap private checks |
| The user | the three gates and the final review, from the PC or the phone |

## Tooling and layout

- One shared skill per stage in `agents-home/skills` (all three models read it): `video-brief`,
  `video-look`, `video-structure`, `video-produce-code`, `video-produce-edit`, `video-qa`, `video-retro`.
- `aos video new <name>` creates a project (a place, see the Places spec) with: `brief.md`, `rubric.md`,
  `refs/`, `style.md` + `style/`, `script.md`, `shots.yaml`, `animatic/`, `src/` (engine code),
  `renders/`, `qa/`, `retro.md`. Heavy media (footage, renders, caches, node_modules) lives outside
  OneDrive under `~\.aos\video\<name>`; final exports go to the project's `exports/` and to the Inbox.
- A render queue: the GPU is shared with Ollama and ComfyUI, so GPU jobs run one at a time and pause the
  local chat model; CPU renders (Remotion) can run alongside.
- Upload package: final file (1080p or higher, H.264/HEVC), captions (SRT), chapters, thumbnail.

## Measured on this PC (2026-09-29)

Remotion renders 1080p at about 3.4-3.7x real time on the CPU (Edge as the browser; `--gl=angle` for
WebGL); local Kokoro voice 30 s for 50 s of speech; SDXL Lightning ~50 s per 1344x768 image; LTX-Video
2B distilled ~110 s per 4 s clip at 768x512; Windows memory commit near its limit (18.2/18.8 GB) during
model loads.

## Out of scope here

Building the orchestration layer in general (its own spec; this process is its first workload), paid
services, and publishing to platforms (the process produces the upload package; the user uploads).

## To verify when planning

The current state of Remotion's own agent skills, a Blender MCP server and an OpenTimelineIO path on
Windows; the best free local voice for Italian; the free music and effects sources and their licences.
