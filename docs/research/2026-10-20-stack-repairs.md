# Repair the failed optional-stack checks

20 October 2026. Scope: fix the reported failures without Claude or external review, ask for
operator action only where needed, and remove additions only when evidence warrants it.
This supersedes the affected current-status conclusions in the earlier
[trial report](2026-10-20-stack-trial-results.md); the original failures remain historical evidence.

| Route | Cause and repair | Actual verification / limit |
| --- | --- | --- |
| Composio | The saved credential belongs to the consumer Connect interface. Testing it against the developer Platform API with `x-api-key` was the wrong authentication test. Use `https://connect.composio.dev/mcp` and `x-consumer-api-key`, loaded from `aos secret` only into memory. | HTTP initialization, live tool listing, scoped GitHub tool discovery and an actual authenticated GitHub profile read passed. Eleven meta-tools were returned. This verifies one connector; it does not verify every connected app or write action. No replacement key or developer project is required. |
| Watch | Pinned upstream fetches captions only for URL sources. An owned adapter extracts embedded text subtitles from local media and merges them into the original frame report. | Original MP4 captions now appear; a focused cue retains `[00:05]`, and a quiet interval reports an existing track without cues. Frame paths and original errors are preserved. Bitmap subtitles and offline ASR remain separate workflows. |
| Kdenlive/MLT | Full plugin initialization hangs. Windows ignores the environment-only repository override; `-repository` must precede initialization. The new render helper uses six copied plugins and checks required services before rendering. | The original exported Kdenlive project rendered in 2.005 seconds of media, with video/audio streams. Full decoding passed; source-versus-render video SSIM was 0.989062. The project was unchanged. H.264/AAC MP4 is the checked export route; arbitrary plugin effects and opening the editor remain unverified. |
| Serena | Automatic mixed-language selection and short client deadlines made earlier startup checks unreliable. Use explicit supported project languages and a realistic startup deadline. | A fresh server/project with cached language-server dependencies returned Python, TypeScript and PowerShell symbols in 21.77, 0.52 and 0.21 seconds. Tool timeout was 120 seconds; the installed template defaults to 240. This is not a fresh dependency-install benchmark. |
| Claude HUD | The failing upstream assertion constructs a Unix-style URL from a Windows path. The unmodified product uses Node's `pathToFileURL`. | A separate Windows-path check passed, including a space in the path and rejection of a JavaScript URL. The original 48/49 test result remains recorded; its measured test was not edited. No product repair or replacement of the existing status mod is justified. |

## Delivered changes

- `tools/composio_connect.py`: bounded on-demand MCP tool listing/calls. Consumer key stays out of
  command arguments, files and logs. Redirects and proxy inheritance are disabled; requests are not
  retried. Input is an explicit JSON file without credentials. Authorize each action's effects;
  installing this route does not authorize messages, account changes or remote workbench execution.
- `tools/watch_local.py`: local text-caption adapter around the pinned upstream extractor. Local
  engine, no transcription fallback and the 30-frame cap remain enforced. Exact subtitle language
  tags are honored. Source timestamps are retained and unknown report layouts fail explicitly.
- `tools/kdenlive_render.py`: on-demand renderer for local exported MLT timelines. Plugin copies
  live under the home folder, keyed by source hashes. The installed app and plugins are unchanged.
  Unsupported active services are refused; disabled filters are ignored. CLI-Anything's exported
  `tractor_project` is selected instead of its `main_bin`. Temporary XML retains the source root.
  Output is probed before publication and an existing destination is never replaced.
- `config/stack-tools.json`: route Watch and Composio through the owned adapters and add the
  explicit `kdenlive-render` command. The existing Kdenlive project-editing harness remains.
- Ten offline regression controls cover the authentication boundary, redaction/redirect refusal,
  caption selection/report preservation, relative media roots and renderer input/output safeguards. The Pester suite
  invokes these controls without credentials, installed services or network access.

The retained Composio Python environment remains usable directly for developer-SDK work if that
is later required. Its developer credentials are separate; do not put the consumer key in
`COMPOSIO_API_KEY`. No global MCP or vendor configuration was changed for these repairs.

## Evidence and qualifications

Logs, scripts, original responses and disposable outputs are retained outside OneDrive under
`~/.aos/research/stack-repairs-20261020`. The machine receipt contains hashes and summarized
verdicts, without connected-account contents or credentials. Original media/project hashes were
retained; the frozen media identities matched their earlier baseline. Raw connector responses remain
local and are not committed.

The new controls were run failing before their implementations existed, then passed. The original
Watch executable was also run directly: it exited zero while omitting the expected embedded text;
the adapter recovered that same text. One earlier regression harness attempt accidentally named
an unknown launcher route and exited 2; that was an invalid probe, not evidence of the caption bug.
Early MLT environment-only isolation probes were invalid on Windows and were replaced by explicit
repository-argument probes. A separate SDK-based MCP probe failed in the installed client stack;
the shipped route uses the successfully tested HTTP/SSE path without that dependency.
An initial media-identity probe read the non-media manifest and selected zero files; the corrected
check used `frozen-media.json` and compared the actual media hashes.

Serena and HUD required corrected configuration/testing conclusions, not edits to their pinned
product source. No tool is recommended for removal based on these five checks. The full Kdenlive
plugin path remains unsuitable for the automation route; keep it for the interactive application
and use the checked subset for supported renders.

## Primary references opened

- [Composio consumer/developer authentication boundaries](https://docs.composio.dev/kb/guide/consumer-project-boundaries-and-auth-selection)
  — distinguishes consumer keys/headers from developer project credentials.
- [Composio Connect](https://docs.composio.dev/docs/composio-connect)
  — official shared MCP endpoint. The live tool schemas took precedence over the page's older
  seven-tool list; the tested account returned eleven tools.
- [MLT factory implementation](https://github.com/mltframework/mlt/blob/master/src/framework/mlt_factory.c)
  and [melt initialization](https://github.com/mltframework/mlt/blob/master/src/melt/melt.c)
  — Windows directory selection and argument order, corroborated against the installed executable.

## Final verification

`aos test` exited 0: **528 passed, zero failed/skipped** under each of Windows PowerShell 5.1
and PowerShell 7. This includes the new ten-control Python repair suite. The sixteen existing
launcher/router/worker controls also passed separately. Python compilation and `git diff --check`
passed. No Claude inference or external review ran. Live native editor/HUD activation and broader
connector/effect coverage were skipped because they are outside the bounded routes repaired here.

The [machine receipt](2026-10-20-stack-repairs.json) records source hashes and exact verification scope.
Implementation: `4a6a91d` on `codex/stack-repairs`; no push or merge was requested.

Read the [setup guide](../stack-additions.md) for current commands. No operator action is pending
for the local routes verified here. Broader connector permissions, new apps, cloning/dictation and
native UI integrations remain task-specific choices.
