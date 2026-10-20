# Repair failed stack checks

Authorized on 20 October: fix non-working routes, request operator action only where needed,
and identify non-fixable additions for removal. Prior no-external-review instruction persists.

1. Reproduce and diagnose Composio authentication, Kdenlive native rendering, Watch embedded
   captions, Serena cold startup and the Claude HUD failure. Preserve original fixtures/tests.
2. Ask for Composio key replacement only if secure format/header checks confirm rejection.
   Continue local work while waiting; never request the key in chat.
3. Write a failing regression before each owned code fix. Keep upstream source pins intact;
   prefer narrow local adapters or supported configuration over vendor-source patches.
4. Verify each changed route end to end against the original fixture, then run relevant regression
   controls. Full aos tests are required if core PowerShell changes; otherwise avoid redundant runs.
5. Record fixes, remaining blockers and a concrete removal recommendation. Do not uninstall a
   useful application because one optional integration is unsupported. No paid fallback or Claude.

Done means every reported failure has a verified fix, a clearly identified operator prerequisite,
or an evidence-based retain/disable/remove decision. Heavy evidence stays under
`~/.aos/research/stack-repairs-20261020`.
