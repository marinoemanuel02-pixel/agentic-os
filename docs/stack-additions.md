# Optional stack additions

Installed on 19-20 October and integrated again on 21 October 2026 following the
[candidate audit](research/2026-10-19-candidate-audit.md). The approved scope is the
recommended and conditional shortlist plus OmniRoute, not every audit entry.
Use the narrow routes below on demand. Packages, source clones and environments live
under the home folder outside OneDrive; the repository contains shared procedures and launchers.

## Installed routes and actual evidence

| Addition | Delivered route | Verified here / remaining limit |
| --- | --- | --- |
| Watch | Shared `watch` skill, pinned frame extractor and owned caption adapter | Timestamped visual event inspected at five seconds. Embedded MP4 text captions, source-relative focus and quiet intervals now pass. Local engine, 30-frame cap and disabled speech fallback remain. |
| AnyDoc | Local CLI 0.2.4 | DOCX/text-PDF table markers preserved; scan exited 3 locally. Hosted OCR refused. Isolated Xberg separately passed the selected local scan trial; complex office fidelity remains unmeasured. |
| frontend-design | Official shared skill, pinned source and Apache-2.0 licence | Skill validation passed; no claim of better aesthetics without a real brief and visual comparison. |
| UI UX Pro Max | Shared skill, offline Python search and MIT licence | Local UX query and design-system generation worked. Advice and contrast claims still need checking in the actual interface. |
| Repomix | CLI 1.18.1 | Selected Python export contained the source and omitted the fixture `.env`; no global hook or remote-config trust enabled. Inspect exports before sharing them. |
| RTK OSS | Windows CLI 1.0.1 | Invalid Git option preserved exit 129 and the original diagnostic. No automatic command rewrite or measured quota-saving claim. |
| Graphify | Isolated code-only CLI | Fixture graph contained both functions and the expected caller edge, with zero reported model tokens. Global hooks/MCP and LLM backends are disabled in this route. Large-repo accuracy and freshness still need task-specific checks. |
| Serena | Isolated on-demand CLI; six-tool navigation context | Fresh-server Python/TypeScript/PowerShell lookups passed with explicit languages and cached dependencies. Allow startup time beyond the earlier short client deadline. Six navigation tools only; dashboard/log GUI disabled. |
| OpenMontage | Isolated Python environment and source | Local audio/video trim, Backlot health, a saved-key Pixabay search with source/creator metadata and a short stock export passed. CLIP models, broad provenance quality and cloud generation remain untested. |
| OpenDesign Agent Kit | CLI 0.2.0 | Two responsive fixtures exported to standalone HTML and reopened with working filters. Real product design quality remains unmeasured. No global MCP/initializer installed. |
| VoiceStudio | Native Windows app 0.5.6 with cached-backend launcher | Supertonic-3 preset voice selected on CPU; analytics off. Cold app-owned backend, health, app WebSocket connection and decoded non-silent Italian/English speech passed. Dubbing/cloning and subjective voice quality are untested. |
| CLI-Anything | Kdenlive harness 1.0.0 plus checked native render helper | Project creation/import/track/clip/XML passed. Isolated plugin rendering now exports the original project; decoding and video similarity passed. Unsupported active services are refused. Full plugin startup and opening the editor remain unverified. |
| Composio | On-demand consumer Connect MCP client; SDK environment retained | Saved consumer key authenticates with the correct header/endpoint. Tool listing/discovery and a connected GitHub read passed. Other apps/actions require their own scoped verification. |
| OmniRoute | Isolated CLI/server 3.8.51 plus one-command text task | Saved OpenRouter connection, live zero-price checks, explicit restricted route and actual fact extraction passed. Anonymous/old credential rejected with 401, disallowed inference with 403. Owned server stopped after tasks; no managed third-provider writer. |

Exact source revisions, installed versions and release hashes are in the
[installation receipt](research/2026-10-20-stack-installation.json). Original logs and fixtures
are under `~/.aos/research/stack-add-20261019`. Earlier failed smoke attempts are retained;
help/version success is not counted as an end-to-end media or provider result.

The real home-folder router setup also passed: health 200, anonymous inference access 401,
administrator login 200 with a session cookie, loopback-only listener, no key in arguments/logs
and no plaintext `.env`. Reloading its Windows-encrypted secrets preserved both ciphertexts
and decrypted values. That initial test had zero provider connections. The later
[trial run](research/2026-10-20-stack-trial-results.md) connected the saved OpenRouter account,
verified a restricted free route and the actual worker helper, then stopped the server.

Verification: `aos test` passed **527 tests under each of Windows PowerShell 5.1 and PowerShell 7**,
with no failures or skips. After the final Python-only setup changes, all **16 launcher/router/worker
controls** passed again from both shells. The three shared skills passed the skill validator.
These controls use mocked transport and disposable files; installed-tool smoke checks are separate.
Those figures describe the earlier installation. The later [repair report](research/2026-10-20-stack-repairs.md)
records the corrected routes and adds ten offline regression controls.
After the repairs, `aos test` passed **528 tests per shell**, with zero failures or skips.
The ten repair controls and sixteen existing launcher controls passed separately as well.
The [21 October integration report](research/2026-10-21-stack-integration.md) records the latest
fourteen-product run, cold speech startup, worker-policy hardening and final regression results.

## Use the tools

Resolve the setup repo from the loaded `aos` module when working elsewhere. From that repo:

```powershell
python tools/stack.py list
python tools/stack.py anydoc report.docx
python tools/stack.py repomix . --include "src/**/*.py,README.md" --output selected.xml
python tools/stack.py rtk git status
python tools/stack.py watch recording.mp4 --start 10 --end 20 --detail efficient --out-dir output
python tools/stack.py ui-ux "accessible dashboard" --domain ux -n 3
python tools/stack.py graphify update path/to/project --no-cluster
```

Repeat actual workflow checks into a **new** home-folder evidence directory:

```powershell
python tools/stack.py voicestudio
# Keep the app open; in another terminal from this repo:
python tools/stack.py verify --output "$HOME/.aos/research/stack-check-new" --live
```

The runner creates its own disposable documents, code and media. `--live` permits consumer Composio
tool discovery and one fact-checkable free-route OmniRoute inference. It makes no connector writes.
Omit `--live` for local checks; those two checks are then explicitly skipped and the overall result
is non-green. Repeat `--tool <name>` to select checks; use `--help` for the accepted names.
A missing speech backend is blocked, not passed. Existing output directories are refused. Receipts
record command results, scope and current launcher/manifest hashes; this is not a full install attestation.

The launcher passes literal arguments, child-only environment variables and the child's exit code.
It does not set user PATH, register MCP servers, install hooks, start a permanent daemon, or
provide a sandbox for arbitrary upstream commands. Watch's cloud engine/Whisper overrides and
AnyDoc's hosted OCR are refused. Use existing offline transcription through `media-tools` when needed.

For Serena, start one selected project with this context; an MCP client can launch the same command
over stdio without global registration:

```powershell
python tools/stack.py serena start-mcp-server --project path/to/project --context config/serena-readonly.yml --agent-interface tools --transport stdio --enable-web-dashboard false --enable-gui-log-window false --open-web-dashboard false --tool-timeout 120
```

Its context exposes symbol overview, symbol lookup, references, pattern search, file read and directory
listing. Index/cache writes by the language server can still occur; this is a navigation-only tool set,
not a filesystem sandbox. Check that a language is supported before promising semantic results.
For a mixed-language project, explicitly configure its actual languages in `.serena/project.yml`
instead of assuming detection includes all of them. The checked fixture used:

```yaml
language_servers:
  - python
  - typescript
  - powershell
```

Merge this into an existing project config; keep its other fields. A fresh server with cached
dependencies took 21.77 seconds for its first Python lookup. The test client allowed 150 seconds;
a 40-second whole startup budget is not a reliable readiness check. The installed tool's default
timeout is 240 seconds; the example's explicit 120-second setting is the bounded tested profile.

For the conditional media/design tools:

```powershell
python tools/stack.py kdenlive --help
python tools/stack.py kdenlive-render path/to/exported-project.kdenlive --output path/to/new-render.mp4
python tools/stack.py openmontage serve --port 7800
python tools/stack.py open-design export path/to/artifact.html --format standalone --workspace path/to/workspace
python tools/stack.py composio tools
python tools/stack.py voicestudio
```

OpenMontage's foreground server binds localhost; stop it when done. Its cloud-provider SDK dependencies
are installed, but no credentials were configured or generation requested. OpenDesign expects a registered
`.artifact.json` sidecar; use absolute entry paths or run from the workspace, because relative entries are
resolved from the current directory. Do not run its initializer against real vendor configuration blindly.

The Kdenlive project harness still edits/exports the project; `kdenlive-render` is its separate
checked H.264/AAC MP4 renderer. It copies six existing plugins into a hash-keyed home-folder cache
and passes `-repository` explicitly, before initialization. It refuses unsupported active services
and existing output files, preserves the original project and selects the harness's exported
timeline instead of its media bin. Other effects/formats require their own verification.

Composio uses the **consumer** key already saved as `composio-api-key`. Its Connect endpoint is
`https://connect.composio.dev/mcp`, with the `x-consumer-api-key` header. The developer SDK's
`x-api-key` route is a separate interface: its rejection of this consumer key was not an invalid-key
diagnosis. No developer project or further key rotation is needed for the checked route.
`composio tools` returns live tool schemas. To make an authorized call, put its non-secret JSON
arguments in a UTF-8 file, then run:

```powershell
python tools/stack.py composio call COMPOSIO_SEARCH_TOOLS --input path/to/search.json
```

Example search input:

```json
{"queries":[{"use_case":"Read the currently authenticated GitHub user's own profile"}],"session":{"generate_id":true},"search_strategy":"tool_search"}
```

Inspect the returned connection status and complete tool schema before any later call; reuse the
returned session ID. App connections and action permissions remain task-specific. No remote shell,
workbench, message or write action was used in verification. This local route needs no manual
custom-MCP registration. Making Composio appear as a native app connector is a separate optional
client connection; the launcher does not claim to have installed it into ChatGPT or Claude.

VoiceStudio's launcher now passes an explicit `--user-data-dir` under
`~/.aos/tools/stack/voicestudio/profile`; its managed runtime consequently lives there too.
Changing APPDATA alone did not change Electron's profile path and was not retained as the solution.
Data/model locations are explicit and the selected external engine path is saved in app preferences.
On 20 October the operator delegated
the remaining choices: Supertonic-3 bundled preset voice, Italian and English, local CPU speech,
and analytics disabled. This is a preset-voice setup; a personal clone still needs an authorized
reference and a cloning-capable engine when that job is requested.

The engine's actual import probe passed and its pinned Hugging Face snapshot downloaded.
Its MIT SDK and OpenRAIL-M model terms are separate; preserve the model licence and identify
generated output as synthetic. The installed app's base-runtime setup selected CUDA dependencies
despite the requested CPU variant. Do not claim the smaller CPU runtime from the request alone.
The speech engine itself is CPU-only. The managed runtime subsequently passed its import check;
localhost health returned 200, while engine selection reported `cpu_only`/`cpu`. The app generated
Italian and English WAVs at 44,100 Hz, and decoding/duration/non-silence checks passed. Generation
ran with `HF_HUB_OFFLINE=1`; complete network isolation was not tested. The first clip took 40.13 s
including cold model/watermark work; the following English clip took 6.91 s. These two different
texts/languages are not a controlled performance comparison or a listening-quality verdict.

Cold installation/startup exceeded the first bounded wait and a 30-second engine-inventory call
timed out. After startup the service answered normally. A relocation initially moved only the model
repository, leaving Hugging Face's shared blob directory at the former cache root; synthesis failed.
Moving that public shared blob store to the checked destination repaired all model links (zero broken,
398,075,273 bytes across the four ONNX files). Both actual speech requests then completed.

The Balanced pack is incompatible with the selected alternate engine, and this release's setup
wizard still treats the default OmniVoice weights as required. After the custom engine's real checks,
the intro-completion preference was saved and the main studio visually inspected. No model-installed
flags or permissions were changed. The unused default pack remains uninstalled; a personal cloning
or dictation workflow still requires its own engine/reference/model selection. The interactive app
was left open for the operator; its temporary verification-controller timer was stopped.
The [activation receipt](research/2026-10-20-voice-activation.json) preserves that earlier evidence.

The 21 October cold check found that the packaged supervisor did not recognize the cached runtime.
`tools/voicestudio_run.py` now checks that interpreter's real imports and uses the app's supported
`OMNIVOICE_BACKEND_CMD` override, with an absolute backend directory. Electron owns the backend;
no install/model flags or preferences are fabricated. The existing Desktop shortcut already routes
through `stack.py voicestudio`, so it receives this fix. A fresh app-owned process tree reached health
200, connected its WebSocket and generated bilingual non-silent audio; stopping that tree closed
port 3900. Native visual interaction was not repeated in this check. Packaged stdout lacked a literal
readiness marker; the retained harness mismatch is separate from the passing behavioral checks.
Use `python tools/stack.py voicestudio --check` for an import-only check without opening the app.

## OmniRoute as additional capacity

Keep native Claude/Codex subscription clients as the normal routes. The saved OpenRouter account
is now connected to OmniRoute and the actual text-worker route passed. Routing the
same exhausted account through a gateway does not increase its allowance. Choose one explicit route,
verify its authentication terms and hard free allowance, and disable paid/unknown fallbacks.

`tools/omniroute_run.py` provides the narrow integration around `omniroute_worker.py`: one explicit route, one text packet
(at most 32 KiB), one non-streaming request, bounded response, no filesystem tools, no redirects,
no automatic retries and no accepted result by default. It uses an explicit loopback endpoint and
a scoped router key loaded internally from `aos secret`. The result records hashes,
reported usage/model and completeness; it is a candidate for the lead to verify, not a native AOS
delegate receipt or an independent other-vendor review. A partial answer remains incomplete.
Before activation, assign the route to its actual provider and apply the existing actor/capacity
rules. A gateway must not bypass a known vendor limit or the two-active-actors-per-vendor cap.
The current managed AOS actor schema does not admit an arbitrary third provider; that integration
remains a separate checked change. This helper provides a text candidate, not a managed code writer.

The restricted worker key is stored as `omniroute-worker-key`. No additional account action is
needed for the tested connection. The task command checks its local restricted policy and current
OpenRouter pricing, starts a foreground gateway if needed, makes one request, and stops only the
gateway it started. An existing authenticated server is reused and left running. Invocation:

```powershell
python tools/stack.py omniroute-task --check
python tools/stack.py omniroute-task --packet task.txt --output candidate.json
python tools/stack.py omniroute-policy check
```

The saved policy currently has one explicit free route; its changing model name is not pinned in
this repo. Multiple allowed routes require an explicit `--model`. Unknown/nonzero pricing, wildcard
or combo routing, automatic resolution, enabled prompt logging and a plaintext legacy key are
refused. Requests send `allow_fallbacks=false` and zero maximum prompt/completion/request prices.
One worker lock prevents concurrent tasks through this helper. Existing candidate files are refused.

The initial gateway database duplicated the worker credential as plaintext. It was rotated into
hash-only authentication: the legacy `key` field is empty and `key_hash` holds SHA-256; the actual
random credential stays in the Windows-encrypted store. A digest string in the legacy field would
still be an alternate accepted credential, so that arrangement is also refused. Automatic combos,
auto-resolution and prompt logging are disabled for this key. `omniroute-policy harden` is an
idempotent offline repair; it refuses a running gateway and saves an encrypted database snapshot
under `~/.aos-backups/omniroute` before changing anything. Recovery is for this Windows account;
never write a decrypted recovery database or paste credentials into a report.

Do not pass keys as command arguments, put them in `.env`, export native subscription credentials,
or use OmniRoute's credential-export command. Store generated router encryption/signing keys with
`aos secret`, inject them into the server process and require API keys. Configure the home-folder
`DATA_DIR` and `OMNIROUTE_SERVER_HOST=127.0.0.1` explicitly; the upstream default binds all interfaces.
The foreground launcher loads or creates its encryption/signing keys and administrator password
through the existing Windows-encrypted `aos secret` store. It does not print them or put them in
command arguments. Informational help/version calls do not open that store. Run
`python tools/stack.py omniroute serve` when needed, then open the localhost
dashboard. The administrator password is stored as `omniroute-admin-password`; retrieve it locally
from the secret store when the dashboard requests it, and never paste it into chat.
Background/tray startup and the credential-export command are refused by this route.

The passing disposable startup used known public fixture values, no connected accounts, no browser,
no daemon/tray, no-recovery mode, cleared proxy variables and a longer cold-start health timeout.
Initial health probes timed out. The later account trial established provider authentication,
actual free-route responses, rejection of anonymous access and rejection of a disallowed model.
Cold startup timeouts remain recorded. No automatic daemon startup or managed third-provider
writer integration was added. On-demand owned startup/shutdown is now integrated and the server
is stopped after tests. Provider quotas still apply; additional free capacity comes from the
connected provider, not from bypassing an exhausted subscription.

## Activation and maintenance

The integration is in the primary checkout. Shared skill sources are visible to Codex through its
existing `~/.agents` junction. Claude's three new per-skill junctions (`watch`, `frontend-design`,
`ui-ux-pro-max`) were applied after a dry-run showed exactly those additions. A second targeted
sync left their targets and creation times unchanged. No global MCP, native login, automatic hook
or user PATH change was made. Restart a session if its skill list was already cached.

The earlier selected `aos-status` native mod was also installed from the primary checkout's local
marketplace under the same explicit exception. Claude lists version 0.1.0, user scope, enabled.
Existing settings/marketplace/plugin records were backed up first. Use `/reload-plugins` in a
supported open Claude session or start a new session, then `/aos-status`. Live Desktop rendering
is still unverified; the completed native fixture tests are separate evidence.

The project's `AGENTS.md` normally requires the other vendor's review before writing Claude/Codex
configuration or user PATH. On 20 October the operator explicitly instructed **"work all on your own,
without any external review"** for this installation and said provider/account setup will happen
later. That exception authorizes the three links and the secure router setup here; no independent
review is claimed and the normal policy is unchanged. No further account question is pending.

The attempted GIMP fallback harness was removed again: its upstream backend targets GIMP 2.x
Script-Fu procedures and executable names, while the installed application is GIMP 3. It was not
registered as a working substitute or used to manufacture a successful render result.

Packages are pinned by the retained external lockfiles/source revisions. There is no automatic updater
for this optional set. Recheck release notes and compatibility before updating; do not use a generic
global initializer or duplicate a second vendor installation. Rollback the source integration with Git;
retain external installs/evidence until they are no longer needed. No existing tool or account was removed.

## Remaining candidates and operator setup

The [remaining-trials plan](superpowers/plans/2026-10-20-remaining-stack-trials.md) lists every
unadopted runtime/reference decision and groups proposed checks into six reusable fixture batches.
It includes the earlier research proposals and distinguishes untested candidates from tools
already covered by the baseline. Claude inference/review is excluded while its quota is exhausted.
The [executed trial report](research/2026-10-20-stack-trial-results.md) separates real workflow
checks, failures, blockers and candidates that did not advance beyond screening.

On 20 October the encrypted store listed `openrouter-api-key`, `composio-api-key` and
`pixabay-api-key`; values were not displayed. Key presence does not prove authentication or a working
connector. Live OpenRouter and Pixabay checks subsequently passed. Composio's saved key returned
HTTP 401 on the developer inventory endpoints because it is a consumer key. After the operator's
screenshot clarified the interface, Connect authentication and a connected GitHub read passed.
Keep the existing saved consumer key; there is no pending key replacement.
The operator has no Pexels key,
so Pexels is optional and unconfigured; no replacement account/signup is required for the local setup.
