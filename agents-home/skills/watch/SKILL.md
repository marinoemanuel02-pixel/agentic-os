---
name: watch
description: Use when a local video or permitted public video needs timestamped visual inspection, screen-text review, or focused frame evidence alongside its transcript.
---

# Video evidence

Locate the agentic-os repo from the loaded `aos` module directory. Run its `tools/stack.py watch`
with a source file or permitted URL and, preferably, a short `--start` / `--end` interval.
This route forces the local engine, disables cloud/transcription fallbacks and caps regular frames
at 30. `--detail efficient` is a useful first pass; use explicit `--timestamps` for a known moment.

Read the returned report and open the relevant frame files before making visual claims. Sampling
can miss short events; inspect a tighter interval when that matters. Timestamps remain source-relative.
Do not report frames or captions as a complete viewing or proof of inaudible/unsampled content.

For local files without captions, use the existing `media-tools` footage workflow with an already
installed local model. Combine that source-relative transcript with Watch's frames. Do not provision
another speech environment, export browser cookies or enable a cloud engine just to complete a run.

The installed upstream runtime is under `~/.aos/tools/stack/watch/source/skills/watch`; its scripts
are kept together. Local integration is deliberately a small shared entrypoint instead of a second
vendor-specific installation. Source: bradautomates/claude-video, revision
`03ceb42f7fa2c4439aca01752118044baabffb8f`, MIT; upstream LICENSE is retained with the source.
