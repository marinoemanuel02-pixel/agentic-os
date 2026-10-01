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
| `ffmpeg` / `ffprobe` (full build, NVENC present) | `ffprobe -v error -show_format -show_streams -of json in.mp4`; cut `ffmpeg -ss 10 -to 20 -i in.mp4 -c copy out.mp4`; loudness `-af loudnorm=I=-14:TP=-1:print_format=json` |
| `magick` (ImageMagick 7) | `magick in.png -resize 1920x1080 out.jpg`; batch `magick mogrify -path out -format webp *.png` |
| `pandoc` | `pandoc in.md -o out.docx` (also pdf needs an engine, html, epub) |
| `yt-dlp` | `yt-dlp -o "%(title)s.%(ext)s" <url>` |
| `whisper-ctranslate2` | `whisper-ctranslate2 in.mp4 --model large-v3-turbo --language it --output_format srt -o out/` (CPU; `--device cuda` needs extra CUDA libs, not installed) |
| `duckdb` | `duckdb -c "select * from 'data.csv' limit 5"` (CSV, JSON, Parquet) |
| `playwright` | `playwright screenshot <url> shot.png`; browsers (headless shell) live in `~\.aos\ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`) |

## Not on PATH (call by full path)

| App | Path | Headless |
|---|---|---|
| Blender | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` | `blender.exe -b scene.blend --python script.py -o //out_ -F PNG -a` |
| Inkscape | `C:\Program Files\Inkscape\bin\inkscape.com` | `inkscape.com in.svg --export-type=png --export-width=1920 -o out.png` |
| Audacity 4 | `C:\Program Files\Audacity 4\` | GUI only; use ffmpeg for scripted audio |
| OBS Studio | `C:\Program Files\obs-studio\bin\64bit\obs64.exe` | WebSocket on port 4455, password in `aos secret obs-websocket` |
| Kdenlive | `%LOCALAPPDATA%\Programs\Kdenlive\bin\kdenlive.exe`; renderer `melt.exe` in the same folder | Projects are text (MLT XML): edit the file, render with `melt project.kdenlive -consumer avformat:out.mp4` |
| GIMP 3 | `%LOCALAPPDATA%\Programs\GIMP 3\bin\gimp-console-3.2.exe` | Batch mode (`-i --batch-interpreter python-fu-eval -b ...`) is untested here: the first run did not finish in 60 s. Try it once, with a timeout |
| Krita | `C:\Program Files\Krita (x64)\bin\krita.exe` | GUI painting; its command line is untested (`krita --help` opens the GUI) |
| LMMS 1.2.2 | `C:\Program Files\LMMS\lmms.exe` | Projects are XML; `lmms render project.mmp -f wav -o out.wav` (checked in `--help`) |

## When the tool is missing or fails

Report the exact command and its error; do not install anything to fix it without asking. A tool that cannot be
reached from this shell (PATH not refreshed after an install) needs the app restarted, not a reinstall.

Reference clones (read-only, outside OneDrive): `~\.aos\repos\remotion-dev__skills`, `ahujasid__blender-mcp`,
`anthropics__skills`. Nothing from them is wired into config yet.
