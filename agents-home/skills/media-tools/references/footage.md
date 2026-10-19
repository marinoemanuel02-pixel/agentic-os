# Edit existing footage locally

Use installed Python, FFmpeg/FFprobe and the existing faster-whisper environment. No API account,
new model or download is needed. Resolve the setup repository from `(Get-Command aos).Module.ModuleBase`
in PowerShell; the CLI is `tools/footage/footage.py` under it. Read that directory's `README.md` for
the complete command interface and supported export formats.

1. Identify the source folder. Select new, separate cache/export folders under `~/.aos/video/<job>`;
   all three roots are explicit. Do not put generated data inside the source tree.
2. Inventory sources. Resolve an already installed Whisper interpreter and complete cached model
   directory; do not pass a model tag that could download. Transcribe the chosen media locally.
3. Use `search` to retrieve source-relative filenames and exact recognized intervals. Recognition
   can be wrong; verify the source around important quotations and cut boundaries.
4. Use `draft` to create an inspectable cut list. Its gaps come from recognized word intervals,
   not an independent silence detector. Review the source around proposed omissions, sentence
   meaning, pauses, pacing and clip order. Present the draft/preview when editorial intent needs
   the operator's judgment. Do not treat `reviewed: true` as evidence of who reviewed it.
5. Save the inspected plan as a new cache file, adjust cuts if needed, then set its boolean
   `reviewed` field to true. Render to a new MP4. Never overwrite source media or an existing export.
6. Inspect the exported video and its sound. Mechanical stream/duration checks do not establish
   editorial quality. Preserve the plan, transcript and source identities for later revision.

The tool refuses changed source hashes, invalid intervals, escaped paths and existing destinations.
It exports 30 fps H.264 with stereo 48 kHz AAC, letterboxed to the first clip's frame dimensions.
Audio-only/no-audio exports, captions, transitions and multitrack sound are outside this helper.
Use existing media tools for those needs. Keep retries bounded and inspect the actual error.
