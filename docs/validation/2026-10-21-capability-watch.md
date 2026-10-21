# Capability registry implementation validation

Scope: branch `codex/capability-watch`, implementation through `1c768de`, based on `5495ae8`.
The two uploaded audits and the reconciled conversation were read; their provenance and the
recommended integration tiers are in [the guide](../capability-watch.md). This adds a watcher and
evidence workflow, not application installations or executed application benchmarks.

## Checks

| Check | Result |
|---|---|
| `python -m unittest discover -s tests -p test_capability_watch.py -v` | 22 passed. Initial 15 acceptance cases failed before implementation; added validation and review regressions failed before their fixes. |
| `python -m unittest discover -s tests -p 'test_*.py' -v` | Final run: 111 passed, 39.210 seconds. Earlier 109-case run also passed before the two review regressions were added. |
| `python tools/stack.py capabilities validate` | Passed: 36 candidates, 10 configured sources. |
| PowerShell 7 `Test-Json -Path config/capabilities.json -SchemaFile config/capabilities.schema.json` | True; independent JSON Schema implementation accepts the curated data. |
| `python -m py_compile tools/capability_watch.py tests/test_capability_watch.py` | Passed. |
| `git diff --check` | Passed; Git's platform line-ending notices are not whitespace errors. |
| `aos test`: core PowerShell parse/ASCII checks | Passed. Core module/bootstrap were not modified. |
| `aos test`: Windows PowerShell 5.1 | 534 passed, 0 failed, 0 skipped, 460.47 seconds. |
| `aos test`: PowerShell 7 | 534 passed, 0 failed, 0 skipped, 395.68 seconds. `aos test` exited 0 with all green. |
| Python lint/static types | Not run: this repository has no configured Python linter or type-check command. No new dependency was installed to introduce one. Syntax, schema and existing test checks ran instead. |

The Pester wrapper runs the capability tests in both shells. Tests use disposable files and
injected public-source responses; they do not install applications, fetch real network content,
change actual vendor settings, read credentials or exercise candidate tools.

## Live source checks

`python tools/stack.py capabilities refresh --apply` succeeded for six enabled discovery and
package sources: REA rankings, awesome-reverse-engineered, both REA case lists, npm REA and npm
LogiSheets. It established six baselines with no errors and returned 50 of 12,712 unreviewed
repository links. Those are discovery links, not 12,712 verified new applications. No links were
automatically adopted into the curated registry.

`refresh --tool pdfcraft --tool blender-agent-sdk --tool logisheets --tool agent-desktop --apply`
succeeded for twelve original-repository surfaces (metadata, README, latest release). A repeat
returned zero baselines, zero capability transitions and zero errors; two source hashes changed
without changing detected capability signals. Metadata and documentation checks are not Windows
execution or source-code conformance tests.

After the parser fixes, a further PdfCraft refresh passed and caught a real upstream `pushed_at`
advance as `repository_changed`. It did not convert that activity into a functional-commit date,
capability verification or status promotion. Eighteen source observations are retained; the curated
registry remains 31 watch, 5 ignore, 0 sandbox and 0 production, with zero verification records.

The public Glama API probe returned 401. Its source is disabled and explicit CLI selection refuses
to load credentials or invent an authenticated adapter. The guessed `blender-agent-sdk` PyPI
project returned 404 and was not configured. The optional Audacity PyPI route remains disabled
until its package-to-original-repository identity is checked. RSS/PyPI parsing was exercised
offline; those optional feeds were not counted among the six successful default live sources.

The runtime state is outside the repository under `~/.aos/capability-watch`. Registry/application
status was not promoted. No tool binaries, model files, persistent MCP servers, services, paid API
calls, PATH edits or vendor-home changes were introduced by this implementation.

## Review

- **Codex author review:** corrected a schema boolean/int mismatch, timezone-offset ordering and
  malformed saved-source handling with regressions. Curated JSON-RPC/live-attach claims that
  exceeded the supplied source were returned to unknown; original workflow labels were added.
- **Claude reviewer:** unavailable. `aos delegate claude` refused before launch because the shared
  capacity ledger had a fresh quota limit until reset. This is not a clean independent verdict;
  no bypass, repeated probe or paid fallback was attempted.
- **Separate Codex reviewer:** found two P2 defects: malformed GitHub metadata could overwrite a
  good observation or throw on a string parent; escaped JSON URLs could silently lose discoveries.
  Both were reproduced before fixing. Its bounded follow-up confirmed both fixes and 22 passing
  tests, with no residual important defect. This is a same-vendor correctness review, not an
  independent second-vendor opinion. The reviewer did not re-audit external application claims.

No Blender corpus, PdfCraft mutation, spreadsheet round trip, desktop fallback, industrial-device
operation or other candidate application trial was run. Those remain the explicit future
evaluation tier; the registry's production evidence arrays are empty.
