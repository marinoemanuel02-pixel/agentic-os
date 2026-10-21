# Approved stack integration implementation plan

**Goal:** Finish the fourteen approved additions as usable, discoverable on-demand routes and
verify OmniRoute as additional free text-worker capacity. Preserve previous trial/adoption boundaries.

**Architecture:** Extend the existing shared launcher and isolated home-folder installs. Use checked
task inputs and outputs, encrypted credentials and live route validation. Keep native subscription
clients, existing writer ownership and current primary workflows. The user already authorized
implementation, delegated routine choices and waived external review; no additional approval gate.

**Tech stack:** Python standard library, installed CLIs/SDKs, PowerShell secret store and existing tests.

## Constraints and acceptance

- The original receipt's fourteen products define adopted scope. Helpers are not extra products.
- Positive later trials remain conditional unless an actual uncovered task justifies a narrow route.
- No paid inference/fallback, credential export, model-name pin in the repository, global proxy,
  automatic memory capture, bulk hooks or native-config replacement.
- Heavy installs, caches and evidence stay under the home folder outside OneDrive/AppData.
- No Claude inference or external review. Read-only native inventory has one bounded worker;
  the lead is the sole writer. The unrelated HANDOFF-media.md stays untouched.
- Every adopted product has provenance, a callable route/procedure, a useful real check and an
  explicit limit. A help/version call alone is not workflow verification.

## Task 1: Inventory and repeatable verification

Files: `config/stack-tools.json`, a small `tools/stack_verify.py`, scoped Python regression tests,
and `docs/stack-additions.md`. Read-only native inventory supplies paths/decisions; lead integrates.

- [x] Compare the approved receipt, current routes, shared skills and retained source pins.
- [x] Define a repeatable verification runner: explicit selected tools, fresh exclusive output folder,
  bounded owned processes, redacted receipts and separate local/live/operator-needed outcomes.
- [x] Write failing controls for selection, output preservation, timeout/failure reporting and
  refusal to silently turn a skipped/unavailable check into a pass; implement the narrow runner.
- [x] Execute real fixture checks for all fourteen products, reusing original expected facts where
  useful; inspect selected visual/audio artifacts before claims. Fix observed integration defects.
- [x] Preserve sources/failed attempts and commit the independently useful result.

## Task 2: One-command OmniRoute worker operation

Files: `tools/omniroute_worker.py`, a focused `tools/omniroute_run.py` if lifecycle needs separation,
`config/stack-tools.json`, scoped Python regression tests and the shared tool guide.

- [x] Inspect the installed gateway schema, scoped saved key, active provider and current official
  free-route pricing/limits. Do not print secrets or persist model names in the repository.
- [x] Write failing tests for encrypted-key loading, only allowed verified-free routes, no paid
  fallback, response completeness, exclusive candidate output and owned-service lifecycle.
- [x] Provide a single callable route that loads credentials internally, validates one explicit
  allowed route and makes one bounded request. Reuse an already healthy loopback server, or start
  and stop an owned foreground instance without touching unrelated processes.
- [x] Verify a real task with checkable facts, anonymous/disallowed rejection, no plaintext key in
  args/logs, stopped owned server, and a second clean run. Keep the result a lead-verified text
  candidate; do not claim it is a native filesystem writer or independent reviewer.
- [x] Commit the operational route and usage instructions.

## Task 3: Integrate, verify and close

- [x] Refresh source-of-truth discovery docs, current status and machine receipt. Recheck installed
  links/launchers rather than add a second installation per vendor.
- [x] Run relevant Python controls, bootstrap dry-run if applying configuration, and full `aos test`
  under PowerShell 5.1 and 7. Preserve non-green results and resolve actual regressions.
- [x] Record exact scope, dates, operator prerequisites and remaining unverified features; no
  absolute perfection claim. Commit, preserve handoff state and release observed actors/claims.

Review focus: moved/missing installs; stale successful receipts; credential/redirect leaks; cold
startup and occupied ports; free-route metadata changes; partial outputs; runtime writes outside
the intended folder; third-provider actor identity and candidate acceptance remain distinct.

Completion evidence: `docs/research/2026-10-21-stack-integration.md` and its JSON receipt.
The primary final run passed fourteen scopes; `aos test` passed 531 tests per shell with no failures
or skips. No configuration apply occurred, so bootstrap preview was conditional and not repeated.
Source-supported speech cold-start repair and worker hash-only policy hardening were added after
actual failures. Logs retain the initial blockers and two corrected harness assumptions.
