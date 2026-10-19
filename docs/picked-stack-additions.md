# Selected stack additions

The operator approved three refinements from the ten-item inventory: local existing-footage editing,
a read-only native Claude status pane, and checked continuation after quota failures. These reuse
the installed tools and existing subscriptions.

## Existing-footage editing

`tools/footage/footage.py` inventories local sources, transcribes with an explicitly installed local
Whisper model/interpreter, searches timestamped words, drafts speech-based cuts and exports an
inspected plan through FFmpeg. Read [the CLI guide](../tools/footage/README.md) and the `media-tools`
skill's footage reference. Set source, cache and output roots explicitly; put generated data under
the home folder outside OneDrive. Source identity, times, paths and destination collisions are checked.

The draft is an editorial starting point. A recognizer's omitted words do not establish silence;
inspect the source around every proposed omission. The plan's `reviewed` boolean records a caller
assertion, not proof of a human review. Mechanical validation does not establish good editing.

A real offline smoke used a locally generated spoken fixture, the existing cached model and existing
Whisper environment. It recognized 20 words, returned 2.70-3.52 seconds for the queried phrase,
drafted three cuts and produced a checked export while the source hash remained equal. This proves
the local integration, not recognition accuracy on real footage. Synthetic unittests separately
cover rejection, source drift, no-overwrite and path controls.

## Native Claude status pane

The [native mod](../plugins/aos-status/README.md) adds immediate `/aos-status`. It reads bounded actor,
claim and capacity records, shows observation times and measured session context, and refreshes on
request. It does not start work, change permissions, make a model request or alter coordination state.

CLI-native validation and test-kit rendering for terminal/Desktop surfaces passed. Native marketplace
installation also passed with `CLAUDE_CONFIG_DIR` redirected to an isolated fixture. That installation
does not enable the mod in the normal Claude configuration. Live Desktop rendering remains
unverified; the app's embedded version is independent of the CLI.

The project normally requires an independent other-vendor review before writes to Claude user
configuration. On 20 October the operator explicitly instructed work without any external review.
Under that exception, the local marketplace and `aos-status@aos-local` version 0.1.0 were installed
from the stable primary checkout. Claude's native listing reports user scope and enabled. Existing
settings/marketplace/plugin records were backed up first. No model request or permission change
was needed; the live Desktop surface remains unverified.

The selected pilot is delivered as a local plugin directory. From the setup repository, start a
session with `claude --plugin-dir ./plugins/aos-status`, then enter `/aos-status`. The persistent
installation now loads from its cache; use `/reload-plugins` in a supported open session or start
a new one. The operator's explicit exception, rather than the earlier pilot approval, authorized it.

## Continuation after a quota failure

1. Preserve the failed receipt and observed limit/reset. Inspect partial changes and in-flight
   actors. Establish termination before marking work terminal; a quota error alone releases no slot.
2. Preserve required ignored/untracked material separately. Save `HANDOFF.md` and a coordination
   checkpoint. Retain the source checkout.
3. Before registering the receiving lead, run:

   ```powershell
   aos coord continuation check <checkpoint-id> --repo . --from claude --to codex
   ```

4. Resolve blocking reasons. The source limit must remain confirmed; target capacity must have a
   known positive allowance; snapshots, task state and revision must match; active actors block
   the check. Unknown capacity is not assumed available.
5. The receiver reads the handoff, verifies separately preserved material and runs returned
   `NextCheck` before further edits. The check itself never dispatches or replays work.

Isolated regressions cover readiness, damaged/stale input, active actors, unknown/limited/stale/reset
capacity, expired source limits, low positive allowance and public CLI exit behavior. A real paired
vendor continuation was not run while Claude remains quota-limited.

Logs and generated fixtures are retained under `~/.aos/research/picked-stack-20261019`. The
implementation plan records ownership, acceptance checks and deployment boundaries.

## Verification and limits

- Complete `aos test`: 526 passed, zero failures/skips under Windows PowerShell 5.1 (447.9 seconds)
  and PowerShell 7 (508.37 seconds), overall exit 0. Static parsing and ASCII checks passed.
  Runtime/test/plugin files matched `4eadb08` throughout; later changes are documentation only.
- New continuation controls were observed failing first; all 11 then passed. Two Pester integration
  checks also execute the five status-parser controls and 16 offline footage unittests. The native
  mod kit separately passed four UI/command tests; strict plugin/marketplace validation passed.
- Four edited skill frontmatter validators and `git diff --check` passed. No existing measured
  assertion was changed or removed.
- Full bootstrap previews in both shells stalled at the pre-existing local agent-model check and
  were interrupted. Native output capture reproduced it. They are incomplete, not successful
  previews. Ollama's API and direct list/show commands answered bounded probes; the cause remains
  unresolved. No unrelated bootstrap/model code was changed. The narrower native plugin installation
  preflight passed in its isolated configuration fixture.
- The worker's duplicate baseline test run was stopped to avoid concurrent full suites; its partial
  output is not credited. Only the combined complete run above establishes full-suite coverage.
- Live Desktop rendering, normal-profile mod installation and live cross-vendor quota continuation
  remain unverified. The code does not claim those outcomes from fixtures or version support.
