---
name: media-tools
description: Drive the installed free media tools (ffmpeg, ImageMagick, pandoc, yt-dlp, Whisper, DuckDB, Playwright, Blender, Inkscape, Kdenlive, GIMP, OBS) from the command line. Use for cutting or converting audio/video/images, transcripts and subtitles, document conversion, vector export, headless browser capture, scripted screen recording.
---

# Media tools

Everything here is free and installed with winget unless noted. Prefer these command lines over a GUI or an MCP
server: they cost no context until used. Quote paths (spaces, Italian names) and pass each as one argument.

## Rules

- Never overwrite source media: write to a new file or folder. Heavy output (renders, downloads, caches) goes under
  `~\.aos\video\<name>`, not OneDrive.
- Downloads and installs need the user's consent with source and size. Models and browsers download on first use
  of some tools: ask before the first run.
- Secrets (the OBS WebSocket password) are read at run time with `aos secret`; never print or commit them.
- yt-dlp only for material the user may use; it needs Deno (installed) for some YouTube sites.

## On PATH

| Tool | Typical use |
|---|---|
| `ffmpeg` / `ffprobe` (full build, NVENC present) | `ffprobe -v error -show_format -show_streams -of json in.mp4`; fast cut `ffmpeg -ss 10 -to 20 -i in.mp4 -c copy out.mp4` snaps to keyframes (10 s asked, 10.07 s got); exact cut re-encodes: `ffmpeg -ss 10 -i in.mp4 -t 10 -c:v libx264 -crf 20 -c:a aac out.mp4`. YouTube loudness: `-af loudnorm=I=-14:TP=-1.5:LRA=11 -ar 48000` (one pass landed at -14.0 LUFS, -1.5 dBFS); measure with `-af ebur128=peak=true -f null -` |
| `magick` (ImageMagick 7) | `magick in.png -resize 1920x1080 out.jpg`; batch `magick mogrify -path out -format webp *.png` |
| `pandoc` | `pandoc in.md -o out.docx` (also pdf needs an engine, html, epub) |
| `yt-dlp` | `yt-dlp -o "%(title)s.%(ext)s" <url>` |
| `whisper-ctranslate2` | `whisper-ctranslate2 in.mp4 --model large-v3-turbo --language it --device cpu --compute_type int8 --output_format srt -o out/`. `--device cpu` is required: the default picks the GPU and fails on the missing `cublas64_12.dll`. About 1x real time (58 s in 57 s). Installed with `uv tool` into `~\.aos\uv\tools` (`UV_TOOL_DIR`), pinned `--with "av<19"` (PyAV 19 breaks faster-whisper 1.2.1) |
| `duckdb` | `duckdb -c "select * from 'data.csv' limit 5"` (CSV, JSON, Parquet) |
| `playwright` | `playwright screenshot <url> shot.png`; browsers (headless shell) live in `~\.aos\ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`) |

## Not on PATH (call by full path)

| App | Path | Headless |
|---|---|---|
| Blender | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` | `blender.exe -b scene.blend --python script.py -o //out_ -F PNG -a` |
| Inkscape | `C:\Program Files\Inkscape\bin\inkscape.com` | `inkscape.com in.svg --export-type=png --export-width=1920 -o out.png` |
| Audacity 4 | `C:\Program Files\Audacity 4\` | GUI only; use ffmpeg for scripted audio |
| OBS Studio | `C:\Program Files\obs-studio\bin\64bit\obs64.exe` | WebSocket on port 4455, password in `aos secret obs-websocket` |
| Kdenlive | `%LOCALAPPDATA%\Programs\Kdenlive\bin\kdenlive.exe`; renderer `melt.exe` in the same folder | Projects are text (MLT XML): edit the file, render with `melt -quiet project.mlt -consumer avformat:out.mp4 vcodec=libx264 acodec=aac`. Verified: two clips on two tracks with a `luma` + `mix` transition gave the right length (9.0 s); slow (about 4 min for 9 s at 1080p with Whisper running alongside), so render once, not per tweak |
| GIMP 3 | `%LOCALAPPDATA%\Programs\GIMP 3\bin\gimp-console-3.2.exe` | Batch mode (`-i --batch-interpreter python-fu-eval -b ...`) is untested here: the first run did not finish in 60 s. Try it once, with a timeout |
| Krita | `C:\Program Files\Krita (x64)\bin\krita.exe` | GUI painting; its command line is untested (`krita --help` opens the GUI) |
| LMMS 1.2.2 | `C:\Program Files\LMMS\lmms.exe` | Projects are XML; `lmms render project.mmp -f wav -o out.wav` (checked in `--help`) |

## Subtitles

- For YouTube ship the `.srt` as a separate upload; burn in only for vertical shorts or social clips.
- Never burn subtitles onto a render that already shows its own captions: they stack (seen in the first test).
- Burn-in: `-vf "subtitles=subs.srt:force_style='FontName=Inter,FontSize=11,Outline=1,MarginV=40'"` (run from the
  folder holding the `.srt`: the filter's Windows path escaping is fragile). libass sizes fonts against a 288-line
  canvas, so `FontSize=22` is about 8% of a 1080p frame: too big; 11 reads well at 1080p. Inter is not installed:
  libass falls back to Arial silently. Check one extracted frame before the full render.

## Code-driven motion design (Remotion + three.js), from the agi-race-2 video

Read `~\.agents\video\video-rules.md` first. Start a video with `aos video new <name>`: the template carries the
tools below (its `AGENTS.md` lists the commands). The first finished video is `Desktop\1-Projects\videos\agi-race-2`.

- **Layout:** code in the OneDrive project; render from `~\.aos\video\<name>\app`, which holds junctions
  `node_modules` -> the shared install `~\.aos\scratch\video-agi-race\node_modules` (Remotion 4, three r186, r3f 9;
  no npm install needed) and `src` -> the project's `src`. `remotion.config.ts` adds the app's absolute
  `node_modules` to webpack `resolve.modules`, so files reached through the junction still resolve.
- **Speed (this PC, `--gl=angle`, concurrency 4):** a 3D shot with shadows, bloom and grain renders about 4 frames
  a second at 1080p (198 frames in 48 s); a still with a cached bundle about 8 s.
- **Gotchas:** a thin flat emissive strip turns dashed at grazing camera angles (use a thin tube); `<Freeze>` does
  not reach inside `@remotion/three`'s canvas (pass the frame in as a prop); full `transmission` glass over a
  near-black scene renders as one smeared highlight (use low opacity, clear coat, lit edges); Remotion's h264 is
  full range `yuvj420p` (JPEG frames): convert with `scale=in_range=pc:out_range=tv,format=yuv420p` on the final
  encode; the system fonts Sitka and Bahnschrift work by family name after `document.fonts.load` in a `delayRender`.
- **Voice:** Kokoro v1.0 (`~\.aos\models\kokoro-multi-lang-v1_0`, sherpa-onnx from Paseo's install; `lexicon`,
  `dictDir` and `lang: "en-us"` in the config); speaker 3 is `af_heart`, the voice its authors grade highest. The
  v0.19 model in `~\.paseo\models` (bm_george) was rejected as "terrible". It also has Italian voices (`if_sara`,
  `im_nicola`). Audition voices as a short MP3 for the user at the style-frame gate; an agent cannot judge a voice.
- **Music and effects without downloads:** synthesise in Node (oscillators, a state-variable filter, a Schroeder
  reverb; the project's `tools/audio.mts`), then duck the music under the voice with `sidechaincompress` and run
  `loudnorm` twice (measure, then `linear=true`): a 6.6 s clip landed at -14.1 LUFS, -1.4 dBTP.
- **Delegating shots to Codex:** its sandbox cannot start Chrome, so `--verify` must be a host command that bundles
  and renders stills from the worktree (`tools/verify.mjs`). Give each builder its own registry and events files so
  parallel batches never touch the same file, and ask for readable code (batch A came back minified).

## When the tool is missing or fails

Report the exact command and its error; do not install anything to fix it without asking. A tool that cannot be
reached from this shell (PATH not refreshed after an install) needs the app restarted, not a reinstall.

Reference clones (read-only, outside OneDrive): `~\.aos\repos\remotion-dev__skills`, `ahujasid__blender-mcp`,
`anthropics__skills`. Nothing from them is wired into config yet.
