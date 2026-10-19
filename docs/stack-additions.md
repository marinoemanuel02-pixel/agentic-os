# Optional stack additions

Installed and checked on 19-20 October 2026 following the
[candidate audit](research/2026-10-19-candidate-audit.md). The approved scope is the
recommended and conditional shortlist plus OmniRoute, not every audit entry.
Use the narrow routes below on demand. Packages, source clones and environments live
under the home folder outside OneDrive; the repository contains shared procedures and launchers.

## Installed routes and actual evidence

| Addition | Delivered route | Verified here / remaining limit |
| --- | --- | --- |
| Watch | Shared `watch` skill and local frame extractor | Two frames from a two-second fixture, source timestamps 00:00 and 00:01; first frame inspected. Local engine, 30-frame cap, cloud speech fallback disabled. Real footage quality is unmeasured. |
| AnyDoc | Local CLI 0.2.4 | CSV and DOCX text converted; image-only PDF exited 3 for missing OCR. Hosted OCR is refused by the launcher. Representative complex office-file fidelity remains unmeasured. |
| frontend-design | Official shared skill, pinned source and Apache-2.0 licence | Skill validation passed; no claim of better aesthetics without a real brief and visual comparison. |
| UI UX Pro Max | Shared skill, offline Python search and MIT licence | Local UX query and design-system generation worked. Advice and contrast claims still need checking in the actual interface. |
| Repomix | CLI 1.18.1 | Selected Python export contained the source and omitted the fixture `.env`; no global hook or remote-config trust enabled. Inspect exports before sharing them. |
| RTK OSS | Windows CLI 1.0.1 | Invalid Git option preserved exit 129 and the original diagnostic. No automatic command rewrite or measured quota-saving claim. |
| Graphify | Isolated code-only CLI | Fixture graph contained both functions and the expected caller edge, with zero reported model tokens. Global hooks/MCP and LLM backends are disabled in this route. Large-repo accuracy and freshness still need task-specific checks. |
| Serena | Isolated on-demand CLI; six-tool navigation context | Real stdio MCP query found `calculate` and its expected body. The exposed set contained only the six configured navigation tools; dashboard and GUI log window disabled. Python language-server dependency installed. PowerShell and other languages remain untested. |
| OpenMontage | Isolated Python environment and source | Local FFmpeg trim and localhost Backlot health check passed. Stock-corpus retrieval, CLIP models, provenance quality and cloud generation are not established. |
| OpenDesign Agent Kit | CLI 0.2.0 | Registered fixture exported standalone HTML with its local CSS embedded. Browser exports and quality on a real design remain untested. No global MCP/initializer installed. |
| VoiceStudio | Native Windows app 0.5.6 under the home folder | Release hash and installed executable version checked; installer exited 0. Speech engine, models, dubbing and cloning are not provisioned or tested. |
| CLI-Anything | Kdenlive harness 1.0.0, isolated | Created project, imported media, added a track/clip and exported native XML. Existing MLT executable reports its version; consumer initialization and render attempts timed out, including an engine-only test. End-to-end render and opening the project in the editor are unverified. |
| Composio | Isolated Python SDK | Offline custom-tool schema and execution passed without a client/account. No app is connected; a concrete missing connector, account scope and current hard free limit must be selected before hosted use. |
| OmniRoute | Isolated CLI/server 3.8.51 plus staged text worker | Disposable server returned healthy HTTP 200 on loopback only, rejected unauthenticated `/v1/models` with 401 and created no plaintext `.env`. It was stopped after the test. No provider account is connected and no additional quota has been established. |

Exact source revisions, installed versions and release hashes are in the
[installation receipt](research/2026-10-20-stack-installation.json). Original logs and fixtures
are under `~/.aos/research/stack-add-20261019`. Earlier failed smoke attempts are retained;
help/version success is not counted as an end-to-end media or provider result.

The real home-folder router setup also passed: health 200, anonymous inference access 401,
administrator login 200 with a session cookie, loopback-only listener, no key in arguments/logs
and no plaintext `.env`. Reloading its Windows-encrypted secrets preserved both ciphertexts
and decrypted values. It has zero provider connections and was stopped after checking.

Verification: `aos test` passed **527 tests under each of Windows PowerShell 5.1 and PowerShell 7**,
with no failures or skips. After the final Python-only setup changes, all **16 launcher/router/worker
controls** passed again from both shells. The three shared skills passed the skill validator.
These controls use mocked transport and disposable files; installed-tool smoke checks are separate.

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

The launcher passes literal arguments, child-only environment variables and the child's exit code.
It does not set user PATH, register MCP servers, install hooks, start a permanent daemon, or
provide a sandbox for arbitrary upstream commands. Watch's cloud engine/Whisper overrides and
AnyDoc's hosted OCR are refused. Use existing offline transcription through `media-tools` when needed.

For Serena, start one selected project with this context; an MCP client can launch the same command
over stdio without global registration:

```powershell
python tools/stack.py serena start-mcp-server --project path/to/project --context config/serena-readonly.yml --agent-interface tools --transport stdio --enable-web-dashboard false --enable-gui-log-window false --open-web-dashboard false
```

Its context exposes symbol overview, symbol lookup, references, pattern search, file read and directory
listing. Index/cache writes by the language server can still occur; this is a navigation-only tool set,
not a filesystem sandbox. Check that a language is supported before promising semantic results.

For the conditional media/design tools:

```powershell
python tools/stack.py kdenlive --help
python tools/stack.py openmontage serve --port 7800
python tools/stack.py open-design export path/to/artifact.html --format standalone --workspace path/to/workspace
python tools/stack.py composio -c "import composio; print('SDK available')"
python tools/stack.py voicestudio
```

OpenMontage's foreground server binds localhost; stop it when done. Its cloud-provider SDK dependencies
are installed, but no credentials were configured or generation requested. OpenDesign expects a registered
`.artifact.json` sidecar; use absolute entry paths or run from the workspace, because relative entries are
resolved from the current directory. Do not run its initializer against real vendor configuration blindly.

VoiceStudio needs an engine/model choice on first use. Select a runtime location under
`~/.aos/tools/stack/voicestudio` before installing its managed runtime; its default runtime is under
application data. The launcher directs its model/project data with `OMNIVOICE_DATA_DIR`, which is
separate from the runtime-location setting. No engine/model has been chosen or downloaded.
Existing Whisper and FFmpeg remain usable now.

## OmniRoute as additional capacity

Keep native Claude/Codex subscription clients as the normal routes. A separate OmniRoute provider
can supply additional text workers once an eligible account is deliberately connected. Routing the
same exhausted account through a gateway does not increase its allowance. Choose one explicit route,
verify its authentication terms and hard free allowance, and disable paid/unknown fallbacks.

`tools/omniroute_worker.py` prepares the narrow integration: one explicit route, one text packet
(at most 32 KiB), one non-streaming request, bounded response, no filesystem tools, no redirects,
no automatic retries and no accepted result by default. It uses an explicit loopback endpoint and
a scoped router key injected into that process from `aos secret`. The result records hashes,
reported usage/model and completeness; it is a candidate for the lead to verify, not a native AOS
delegate receipt or an independent other-vendor review. A partial answer remains incomplete.
Before activation, assign the route to its actual provider and apply the existing actor/capacity
rules. A gateway must not bypass a known vendor limit or the two-active-actors-per-vendor cap.
The current managed AOS actor schema does not admit an arbitrary third provider; that integration
remains a separate checked change. This helper provides a text candidate, not a managed code writer.

After provider/account setup and creation of a scoped key, its invocation is:

```powershell
python tools/stack.py omniroute-worker --endpoint http://127.0.0.1:20128/v1 --model <explicit-route-from-live-catalog> --packet task.txt --output candidate.json
```

Do not pass keys as command arguments, put them in `.env`, export native subscription credentials,
or use OmniRoute's credential-export command. Store generated router encryption/signing keys with
`aos secret`, inject them into the server process and require API keys. Configure the home-folder
`DATA_DIR` and `OMNIROUTE_SERVER_HOST=127.0.0.1` explicitly; the upstream default binds all interfaces.
The foreground launcher loads or creates its encryption/signing keys and administrator password
through the existing Windows-encrypted `aos secret` store. It does not print them or put them in
command arguments. Informational help/version calls do not open that store. Run
`python tools/stack.py omniroute serve` when ready to connect a provider, then open the localhost
dashboard. The administrator password is stored as `omniroute-admin-password`; retrieve it locally
from the secret store when the dashboard requests it, and never paste it into chat.
Background/tray startup and the credential-export command are refused by this route.

The passing disposable startup used known public fixture values, no connected accounts, no browser,
no daemon/tray, no-recovery mode, cleared proxy variables and a longer cold-start health timeout.
Initial health probes timed out. This establishes a working isolated Windows server and rejection of
anonymous requests; it does not establish provider login, usable quota or production authentication.

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
