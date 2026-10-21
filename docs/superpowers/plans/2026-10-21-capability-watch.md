# Capability registry and watch workflow

## Intent and design

Implement the operator's supplied harness-expansion requirements using both uploaded research
reports and the reconciled Research harness additions conversation. Keep discovery, documented
claims and local execution evidence separate. Extend the existing `tools/stack.py` launcher;
do not install candidate applications, register MCP servers, change PATH or start a service.

The curated registry and its JSON Schema live in `config/capabilities*.json`. Unknown facts are
null. Candidate status is `ignore`, `watch`, `sandbox` or `production`; a recommended integration
tier is a separate decision. The initial applications are watch/ignore, since no local corpus
has been run. Each candidate records discovery provenance, release/activity, platform/interface,
security, incremental value and verification evidence. Ghidra is a companion to REA.

Runtime observations live under `~/.aos/capability-watch`, outside OneDrive. A refresh reads
bounded public discovery feeds or explicitly selected original repositories and package feeds.
It reports new repository links, release/metadata changes and documentation signal transitions.
First observation is a baseline. Missing words are signals, never proof a feature was removed.
Errors retain the last successful observation and return a nonzero exit code. No discovery
automatically adds a candidate, installs anything, verifies a capability or changes a status.

Registry updates use an explicit evidence-import/status workflow; preview is the default.
Applied writes are locked and atomic, preserving the previous registry in the state directory.
Production needs a pinned version and passing source, license, Windows build/execution,
security-boundary and independent artifact checks at that version. Evidence is evaluator-authored;
the watcher never executes commands from feeds or evidence files.

Use standard-library Python only. Fetch HTTPS from an explicit host allowlist, validate redirects,
cap response size and time, and do not load credentials. Glama is configured but disabled because
its API requires authentication. Public index failure remains a failure, not an empty result.

## Files and tasks

1. Add `tests/test_capability_watch.py` with offline feeds, original-repo documents, package
   metadata and disposable state. Observe failure before implementing. Cover baseline/idempotence,
   signal gain/loss, failed refresh preservation, provenance/deduplication, invalid schema/status,
   production gates, locks, preview/apply, release changes, bounds and untrusted URLs.
2. Add `config/capabilities.schema.json` and `config/capabilities.json`. Seed named recommendations
   and watchlist from both reports; preserve unknowns and report disagreements. Sources include
   REA rankings JSON/RSS, awesome-reverse-engineered JSON, REA lists, Glama, npm/PyPI and original
   repositories. Track claims separately from evidence and observations.
3. Implement `tools/capability_watch.py`: `validate`, `list`, `refresh`, `record`, `status`.
   Functions: `validate_registry(data)`, `refresh(registry, previous, fetch, tool_ids, source_ids,
   checked_at, limit, match)`, `record_evidence(candidate, evidence)`, `set_status(candidate,
   status, reason)`, and a CLI with explicit registry/state overrides. No external subprocesses.
4. Add one `capabilities` launcher entry and one Pester wrapper. Document refresh/review workflow,
   evidence format, tiers, comparisons and the shared Blender ten-task benchmark. Update README,
   source tool catalog and append-only decisions; leave installed-tool verification unchanged.
5. Run focused Python tests, all root Python tests, `aos test` under both shells, syntax/static
   checks and `git diff --check`. Exercise bounded real feeds and selected original repos. Record
   failures and verification limits. Review the final diff, then commit this branch.

## Review focus

- Negated/roadmap mentions cannot become verified support.
- Failed or malformed feeds cannot erase prior observations or simulate capability loss.
- New source/repository URLs cannot become executable instructions or unbounded network targets.
- Multiple feeds and repository URL variants cannot create duplicate candidate identities.
- Old-version or failed evidence cannot permit production promotion.

## Execution record

- Read-only architecture exploration found no overlapping candidate watcher; reuse the launcher.
- Both uploaded reports and the reconciled recommendations were read in full. See the guide for
  input names/hashes and distinctions between reported claims and this run's observations.
- Live source probe: REA records and both REA lists work; awesome-reverse-engineered JSON works
  (the broad report could not retrieve it); Glama API returns 401; the guessed Blender SDK PyPI
  package returns 404. Do not configure that guessed package.
- The repository contract permits risk-based inline execution without imported approval pauses.
  Implement here on `codex/capability-watch`; an explorer was read-only and has completed.
- Implementation and schema/data are committed. Twenty-two focused cases and 111 root Python
  tests pass; original-repository and enabled discovery refreshes pass. Separate Codex review
  findings were reproduced and corrected. Claude review was refused by the fresh quota guard.
- All five tasks are complete. Both Windows shells passed 534 Pester tests with no failures or
  skips, including the final 22-case capability suite. Schema, syntax and whitespace checks pass.
  Exact outcomes and review limits are recorded in `docs/validation/2026-10-21-capability-watch.md`.
