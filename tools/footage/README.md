# Offline existing-footage editing

This is a small local CLI, using Python's standard library, installed FFmpeg/FFprobe,
and the existing faster-whisper environment. It never downloads models or installs
anything. Source files stay read-only. Keep cache/export folders outside OneDrive
when practical and separate from each other and the source folder.

Set explicit existing source, model, and Whisper interpreter paths in your shell.
The interpreter is the `python` executable in the existing transcription environment,
not a fresh environment. The model directory must contain `model.bin`, `config.json`
and `tokenizer.json`; a model identifier is not accepted. No paths or weights are
stored in the repository.

```powershell
# Supply these existing local paths for this editing job:
$source = Read-Host 'Source directory'
$model = Read-Host 'Existing local converted model directory'
$whisperPython = Read-Host 'Existing transcription environment python executable'
$job = Join-Path $env:USERPROFILE '.aos/video/footage-job'
$cache = Join-Path $job 'cache'
$exports = Join-Path $job 'exports'
$cli = Join-Path (git rev-parse --show-toplevel) 'tools/footage/footage.py'
$roots = @('--source-root', $source, '--cache-root', $cache, '--output-root', $exports)

python $cli @roots inventory --out inventory.json
# Media and document names below are relative to the declared source/cache roots.
python $cli @roots transcribe interview.mp4 --model-dir $model --whisper-python $whisperPython --out interview.words.json
python $cli @roots search 'the phrase' interview.words.json
python $cli @roots draft interview.words.json --pad 0.2 --min-gap 0.5 --out draft.json
```

Inventory supports MP4/MOV, Matroska/WebM, WAV, MP3, FLAC, OGG, AVI, MPEG and TS.
Transcription needs audio. Search matches consecutive case-insensitive word tokens
and reports source-relative filenames, text, start, and end in seconds.
Transcripts retain every recognized word and its timestamps. Empty recognition is
valid and produces an empty draft, which cannot be rendered.

A draft keeps the padded word intervals, merges intervals separated by at most
`min-gap` seconds **after padding**, and removes the remaining gaps. These are
recognition-derived gaps, not proof that the recording is silent or unimportant.
Whisper can omit speech or misrecognize words. Review the source around every cut;
inspect timing, sentence meaning, unwanted omissions, and the ordered `cuts` array.
An agent should present the draft and a source preview to the operator when taste
or editorial intent is unresolved. Mechanical validation does not establish
editorial or aesthetic approval.

Save an inspected copy in the cache directory, edit/reorder its explicit cuts as
needed, and set its JSON `reviewed` field to the boolean `true` only after review.
Then render to a new filename:

```powershell
python $cli @roots render reviewed.json --out interview-cut.mp4
```

Each plan binds sources by relative path, size, SHA-256, and duration. Search, draft,
and render refuse stale source content. Word/cut times must be finite and within
source duration. Rendering checks identities again before publishing the export.
Keep sources stable during a job; this is content validation, not a filesystem lock
against a concurrent writer that changes and restores bytes during decoding.

Rendering re-encodes precise seeks, fits every clip into the first cut's even-sized
video frame with letterboxing, and exports constant 30 fps H.264/yuv420p with stereo
48 kHz AAC. Temporary parts use PCM audio to avoid repeated AAC encoder padding.
Cuts shorter than one export frame are rejected. Every source in an export must
have both video and audio; no-audio/audio-only exports, transitions, subtitles,
color work, source frame-rate preservation, and multitrack audio are unsupported.
Small duration differences of up to one 30 fps frame per cut are possible.
The tool checks the final streams/duration; editorial quality still needs viewing.

Input demuxers are restricted to known local single-file media formats; FFmpeg's
network protocols are disabled. Whisper uses a complete existing model directory,
`local_files_only=True`, and offline environment flags. No job queue, service,
remote provider, download fallback, or retry loop is included. A transcription or
individual render step times out after one hour; probing after two minutes.
Large jobs may require a smaller explicit plan.

All generated documents and exports publish atomically without replacing an
existing destination. This requires filesystem hard-link support (normally NTFS).
A failure removes temporary files and leaves existing destinations alone. Relative
paths must use forward slashes and stay inside their declared root; symlink/junction
escapes are rejected. Rename a new output when re-running a job.

Run the self-contained checks from the repository root:

```powershell
python -m unittest discover -s tools/footage -p 'test_*.py' -v
```

The suite uses temporary folders, generated video/audio, and a local runner fixture;
it needs no personal footage, network, or real model. FFmpeg integration checks skip
when FFmpeg/FFprobe are absent. A real cached-model transcription smoke test must be
reported separately; fixture success does not measure recognition accuracy.
