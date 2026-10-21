# Approved stack integration and workflow verification

21 October 2026, Europe/Rome. Integrate the fourteen products in the approved shortlist plus
OmniRoute, using the existing installations. Later successful trials remain trials. The operator
explicitly waived external review; no Claude inference or independent other-vendor review was run.

All fourteen selected checks passed in a fresh run from the primary checkout. VoiceStudio started
its own cached backend through the shared launcher; OmniRoute made an actual restricted free-route
request. Both owned services stopped afterward. This establishes the workflows below, not every
upstream feature or an absolute quality/security guarantee.

## Actual product checks

| Product | Checked behavior | Practical limit |
| --- | --- | --- |
| Watch | Extracted four real frames and embedded text captions from generated local media; frame paths/cues checked. A frame from the preceding run was opened and its timestamp inspected. | Bitmap subtitles, ASR and arbitrary video interpretation are separate. |
| AnyDoc | Generated DOCX converted locally with expected paragraph markers. Earlier installation evidence covers a text-PDF table. | Scan OCR and complex layout fidelity are not established. |
| frontend-design | Shared canonical source, vendor links and contents matched. | A skill's aesthetic effectiveness needs a real design brief and visual evaluation. |
| UI UX Pro Max | Offline UX search returned relevant keyboard guidance. | Advice still needs validation in the actual interface. |
| Repomix | Selected Python/TypeScript/PowerShell markers preserved; synthetic `.env` canary excluded. | Inspect real exports before sharing. No global hook. |
| RTK OSS | Invalid Git option retained its diagnostic and exit 129. | No automatic rewrite or measured subscription-saving claim. |
| Graphify | Code-only Python symbols and cross-file caller found; zero reported model tokens. | TypeScript call accuracy and large-repository freshness are unmeasured. |
| Serena | Fresh scoped server returned Python, TypeScript and PowerShell symbol bodies with the six-tool allowlist. | Cached dependencies and explicit languages; not a clean-machine install benchmark or filesystem sandbox. |
| CLI-Anything/Kdenlive | New project/import/track/clip/XML, checked native subset render, duration and full decode passed. Prior-run source/render SSIM was 0.988638. | Arbitrary effects and opening the native editor were not tested. |
| OpenMontage | Local audio/video trim produced the expected duration. Prior trial evidence separately covers Pixabay search and a stock export. | Cloud generation, CLIP and broader stock provenance are untested. |
| OpenDesign Agent Kit | Registered HTML exported with expected content. The preceding export reopened and its button worked at 1280 and 390 pixel widths. | Real product design quality is unmeasured. |
| VoiceStudio | Cold app-owned backend, health 200, app WebSocket connection; generated decoded non-silent Italian 5.433 s and English 4.110 s clips. | No listening-quality verdict, cloning/dubbing or new native visual interaction test. |
| Composio | Existing consumer Connect credential authenticated and listed eleven tools. Earlier repair evidence includes a connected GitHub read. | This run made no account writes; each other app/action needs authorization and verification. |
| OmniRoute | One live zero-price restricted text route extracted the supplied depot and correct total; response complete and candidate still unaccepted. | Text-only additional capacity; quotas apply. No arbitrary third-provider native filesystem writer admission. |

Installed versions, source revisions and licences remain in the
[original installation receipt](2026-10-20-stack-installation.json). No upstream installation was
replaced. The new helpers are owned adapters, not additional adopted products. The
[machine receipt](2026-10-21-stack-integration.json) records current source hashes and check scopes.

## Operational changes

`python tools/stack.py verify --output <new-home-folder> --live` creates fresh disposable fixtures
and preserves bounded command evidence. Existing output is refused. Repeated `--tool` selects
checks. Failures, unavailable services and omitted live checks remain failed, blocked and skipped;
none silently becomes a pass. Keep VoiceStudio open for speech. Live mode allows consumer
Composio discovery and one free OmniRoute request, with no connector write action.

`python tools/stack.py omniroute-task --packet task.txt --output candidate.json` loads the encrypted
worker credential internally, checks its local restricted policy and the live OpenRouter catalog,
then performs one bounded request. It starts/stops only an owned foreground gateway and preserves
an already authenticated server. `--check` tests readiness without inference. One exclusive worker
lock prevents helper concurrency; no automatic retry or fallback is enabled. Empty/oversized input
and existing output are refused. Model names remain runtime configuration rather than repository pins.

The gateway database originally duplicated the worker key in plaintext. Offline hardening saved a
Windows-encrypted database snapshot, rotated the key, cleared the legacy plaintext column and retained
only its hash for authentication. Actual credentials stay in the encrypted store; the prefix is only
an identifier. Automatic combos, auto-resolution and prompt logging are disabled for this key.
Inspection caught that putting a digest string in the legacy column would create an alternate
accepted credential. A failing regression reproduced this; the final implementation requires an
empty legacy field and nonempty encrypted credential. Old credentials returned 401, current hash
authentication returned 200, anonymous access returned 401 and forbidden inference returned 403.
Encrypted recovery was successfully decrypted and inspected in memory without a plaintext file.

Every task requires an explicit allowed free route and known finite zero pricing. Requests also send
`allow_fallbacks=false` and zero maximum prompt/completion/request prices. This follows the current
[OpenRouter provider-routing interface](https://openrouter.ai/docs/guides/routing/provider-selection).
[Provider limits](https://openrouter.ai/docs/api_reference/limits) still apply; routing an exhausted
account through a gateway does not replenish it. This is a lead-verified candidate workflow and does
not bypass the existing vendor actor/capacity rules.

VoiceStudio's packaged supervisor did not recognize its cached runtime on a fresh launch.
`tools/voicestudio_run.py` checks actual imports and uses the source-supported
`OMNIVOICE_BACKEND_CMD` override with an absolute backend directory. Electron owns the child service.
The existing Desktop shortcut calls this shared route. No install/model flags, new preferences,
default weight downloads or account choices were needed. Offline cache settings are set in the child
environment; complete network isolation is not claimed. The packaged runtime still contains the
previously installed CUDA dependencies although the selected speech engine runs on CPU.

## Evidence and failed attempts

Detailed evidence stays under `~/.aos/research/stack-integration-20261021`, outside OneDrive:

- `verify-runner-01`: initial twelve passes and two genuine blockers before lifecycle integration.
- `verify-all-01/receipt.json`: fourteen passes with the temporary checked speech backend.
- `voice-cold-behavior-summary.json` and `verify-voice-cold-05/receipt.json`: fresh Electron-owned
  backend and bilingual audio; all owned PIDs stopped and port 3900 closed.
- `verify-final-01/receipt.json`: fourteen passes through the final primary launcher/policy, after
  credential hardening. Primary cold launch and owned-tree shutdown also passed.
- `export-reopen.json`, inspected Watch frame and `new-render-ssim.*`: additional content checks.
- `results.jsonl`: original failures and follow-ups. The initial console-marker harness failed
  because packaged stdout was empty; health, process ownership, app WebSocket and audio passed.
  A lead probe initially used the wrong health URL and was stopped; the corrected `/health` probe
  passed. Neither harness failure is presented as a successful initial test.
- `router-security-check.py` and encrypted recovery checks: live negative auth/policy evidence.
  The first in-memory SQLite snapshot probe encountered its WAL header. The corrected probe followed
  [SQLite's documented in-memory deserialize handling](https://www.sqlite.org/c3ref/deserialize.html),
  changed only the in-memory header copy, and passed. The encrypted snapshot was unchanged.

`aos test` passed **531 tests under Windows PowerShell 5.1 and 531 under PowerShell 7**, with
zero failures or skips. Static parse/ASCII checks passed. The suite includes 48 optional-stack
Python controls: 16 launcher, 10 repairs, 7 verification-runner, 12 worker policy/lifecycle and
3 cached-speech-launcher controls. The final direct controls, Python compilation and
`git diff --check` also passed. Detailed native Pester output was observed in the completed Codex
execution; the saved tee log preserves both shell success markers and the overall green result
(the runner's `Out-Host` does not put native Pester detail into that tee file).

The offline controls cover selections/output preservation, honest outcomes/timeouts, credential
boundaries, hash-only policy, known zero pricing, refusal of fallback, and owned/reused service
lifecycle. Full setup tests use disposable profile/registry/network substitutes; installed-tool
checks above are separate evidence. No bootstrap apply or vendor/PATH configuration change occurred,
so another configuration dry-run was not needed. Existing shared links were checked directly.

## Operator state and remaining limits

No operator action is required for the verified routes. Pexels remains optional and unconfigured.
The saved Pixabay, consumer Composio and OpenRouter connections retain their earlier successful
checks. Additional connectors and provider/model changes need their own scoped verification.
No permanent service was added; both verification-owned ports 3900 and 20128 were closed at completion.
The unrelated media handoff and existing trial evidence were preserved. No tool/account was removed.

Use the [tool guide](../stack-additions.md) for commands and the
[trial report](2026-10-20-stack-trial-results.md) for candidates that were not promoted to adoption.
