# Read-only agent status

This native Claude mod adds `/aos-status`, an immediate command that opens a pane without a model
request. It displays active actor identities, live checkout-claim count, recorded vendor capacity,
observation times and the current session's measured context percentage. Refresh is explicit.
Missing, oversized, stale or malformed records remain visibly unknown. Capacity is an observation,
not a guarantee that a future model request will be admitted.

The mod reads only bounded coordination metadata and session usage. It does not read transcripts
or authentication, alter permissions, start processes, call models, access the network, write files,
send messages or create a timer. It never releases actors or claims. Registry history is capped at
512 KiB per file; if it grows past that, the affected observation becomes unavailable. The existing
`aos capacity` command can inspect newer account-log evidence that is absent from the ledger.

## Use

From the repository root, load it for one session with:

```powershell
claude --plugin-dir ./plugins/aos-status
```

At the Claude prompt enter `/aos-status`. A wide terminal shows a side pane; narrower surfaces use
the host's own pane placement. The mod leaves unrelated panes and tool calls alone.

For persistent installation after the project's required independent review:

```powershell
claude plugin marketplace add ./plugins
claude plugin install aos-status@aos-local
```

Use the stable primary checkout for the marketplace, not an expendable worktree. Claude caches
installed plugins by version; source edits need a version increase and update/reinstall. Run
`/reload-plugins` in an already-open supported session. `claude plugin disable aos-status@aos-local`
turns the installed mod off. Installation writes Claude user configuration and is separate from
the tests below.

Installed on this machine on 20 October 2026 under the operator's explicit instruction to proceed
without external review. Native listing reports `aos-status@aos-local` 0.1.0, user scope, enabled.
The existing configuration records were backed up first. This does not establish rendering in a
live Desktop session; the fixture checks below remain separate.

## Verification

```powershell
node --test plugins/aos-status/tests/summary.test.mjs
$env:CLAUDE_CONFIG_DIR = Join-Path $env:TEMP ('aos-mod-test-' + [guid]::NewGuid())
claude plugin validate plugins/aos-status --strict
claude plugin test plugins/aos-status
```

Native tests use the host's mod kit without sign-in, network or model requests. They exercise the
terminal and Desktop render surfaces as test fixtures; they do not establish rendering in a live
Desktop session. Tested with the installed CLI; minimum documented native-mod support is 2.1.287.
Do not infer the Desktop app's embedded version from the CLI.

Sources: [native mods](https://code.claude.com/docs/en/plugins/mods/overview),
[interface](https://code.claude.com/docs/en/plugins/mods/interface),
[test kit](https://code.claude.com/docs/en/plugins/mods/test).
