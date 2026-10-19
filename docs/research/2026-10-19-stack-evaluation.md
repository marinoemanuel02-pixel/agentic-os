# Local evaluation of the research reports

Evaluated 2026-10-19 against the checkout starting at `689b490`. Inputs: the two supplied GPT
reports and the subsequently supplied Perplexity report. These reports describe candidate work;
their recommendations are not evidence that a feature is missing from the implementation.

Raw reports, input hashes, diagnostic scripts, fixture results and package metadata are retained
outside the repository under `~/.aos/research/stack-evaluation-20261019`. No credentials were copied.

## Decisions from code and local evidence

| Proposal | Evaluation | Decision |
| --- | --- | --- |
| More receipt fields for corrections/integration/review | `Set-AosReceiptAnnotation` already stores these. Of 94 local receipts, only one records corrections and none record integration/review time. 63 are host-accepted; usage is unavailable in 79. | Reuse the fields. Missing observations are not a reason to create another telemetry schema. |
| Paired routing evidence | The six-case runner exists, but its report lacks a stable fixture/task/grader identity for comparing separate runs. `Get-AosRouteReport` groups attempts, not controlled paired experiments. | Add a small offline comparison path if regression controls demonstrate the gap; no automatic routing change. |
| Complete recovery manifest/archive | Tracked checkpoints intentionally omit ignored/untracked state. A fixture demonstrates the limit and byte-preserving restoration of an explicitly selected non-secret set. | Preserve explicit required state; do not promote a general archival/extraction subsystem from this fixture alone. Real app archive recovery remains unverified. |
| Checkpoint without a task list | The public CLI accepts an optional task list, but omission reaches `Get-AosTaskRecord` with an empty identifier and fails. Existing checkpoint tests explicitly pass an empty array. | Reproduce through the public CLI, then fix the optional-argument path without weakening task-id validation. |
| SQLite lexical index | In the diagnostic corpus, lexical FTS did not improve the existing term-search baseline. | Do not add a persistent FTS index now. |
| Local dense retrieval | The installed embedding route works and improved this small cross-language diagnostic set. It does not expose sparse/multi-vector outputs in the observed response. | Retain the experiment. A persistent sidecar needs a representative labelled corpus and freshness/deletion controls first. No new model/server. |
| Earlier creative approval | Existing video rule R01 requires reviewed style and animated hero before production; R30 requires early visual evidence. | Do not add another approval stage. A future video can test adherence and whether the preview is representative. |
| Native observability / OpenTelemetry | No current outcome decision requires a new collector. Vendor observations would not establish host acceptance, integration effort or cross-vendor admission. | Do not enable/export telemetry or remove lifecycle guarantees. Reconsider only a specific missing observation. |
| GPU transcription | A working CPU path exists; this task has no active transcription job or measured transcription bottleneck. | Keep the environment and compatibility pin. No CUDA installation or ASR migration from benchmark claims. |
| Native TUI steering replacing App Server | The adapter is an optional transport in programmatic delegation. There is no human-interactive TUI branch in that path to delete. | The two surfaces serve different callers. Do not remove the automation adapter. |
| Native Codex installation | `Invoke-AosCodexInstaller` already invokes the official installer. The 18 October release adoption and rollback evidence are documented separately. | Do not build a second installer or delete compatibility handling on secondary release-tracker claims. |
| Xberg extraction | The cited release's primary licence and PyPI metadata say MIT, contradicting Perplexity's ELv2 claim. Current CLI docs describe Windows installation, but the checked Python release lists no Windows wheel. | Keep as a conditional CLI candidate. Do not install, assume a source-build fallback, or add an MCP. Actual OCR demand and a bounded Windows distribution/dependency preflight are still needed. |

## Retrieval experiment

Inputs were frozen before model queries: 15 explicitly selected stack documents, 205 heading/line
chunks, and 12 diagnostic questions with expected document sets (six English, six Italian).
Sources stayed local. The exact questions, source hashes and result spans are in the external
`retrieval/` evidence directory.

| Method | English queries | Italian queries | Total expected-document hits in top five |
| --- | --- | --- | --- |
| `rg` content matches with fixed query-term coverage ranking | 6/6 | 4/6 | 10/12 |
| Disposable SQLite FTS5 with Unicode tokenization and BM25 | 6/6 | 2/6 | 8/12 |
| Installed Ollama dense embedding route | 6/6 | 6/6 | 12/12 |

Indexing took 307 seconds under the experiment's shared machine load. Maximum measured warm query
time, including local embedding and exact similarity ranking, was 0.380 seconds. The live response
returned two 1,024-dimensional vectors in the initial API probe, with model/timing/token metadata;
it did not return sparse or multi-vector representations. Inputs used `truncate=false`.

This is a diagnostic result, not a held-out retrieval benchmark or proof of production quality.
Questions and expected documents were authored by this agent. The source corpus is English stack
documentation, not the operator's Italian archive; top-five document retrieval over 15 documents is
a forgiving metric. An agent can translate/reformulate a search, which the single-pass lexical
baselines did not do. A useful next experiment needs actual failed searches, Italian source files,
passage-level relevance and stale/deleted source controls. Nothing was indexed across the home folder.

SQLite's own documentation describes Unicode tokenization and BM25, not cross-language semantic
matching. Its default lexical index therefore does not solve the same problem as dense retrieval.
Source opened: [SQLite FTS5](https://www.sqlite.org/fts5.html).
The observed embedding response matches the documented vector endpoint; full upstream model
features must not be inferred from that endpoint. Source opened:
[Ollama embedding API](https://docs.ollama.com/api/embed).

## Preservation experiment

A disposable repository contains tracked verification code plus an explicitly required ignored
input and an untracked note. The source checker first passes. An actual existing checkpoint includes
only the two tracked paths. Restoring tracked contents alone fails the same checker. A hash-verified
copy of the declared two-file preservation set then passes under fresh Windows PowerShell 5.1 and
PowerShell 7 processes. The excluded rebuildable cache remains absent and the original source remains
intact. A deliberately changed preservation byte is detected by its hash.

The first fixture setup was corrected to write explicit LF bytes rather than Windows-translated
newlines; that setup failure is not evidence of a recovery defect. A separate probe then exposed the
optional-task-list checkpoint bug. The successful preservation run explicitly passed an empty task
array so the preservation question could be tested independently of that bug.

This proves only this synthetic preservation set on the same account/toolchain. It does not prove
app-managed archive recovery, clean-machine reconstruction, preservation of ACLs/alternate streams,
arbitrary ignored dependencies, or decryption of DPAPI blobs after a reset/new account. No source
worktree or backup was deleted, and no general archive extractor was implemented.

## Source checks and limits

- The Perplexity report links some Codex assertions to Anthropic releases or a third-party tracker.
  Those links do not establish the claimed Codex behavior. Local call sites settle the proposed
  adapter/installer deletion question without adopting those release claims.
- The second pasted GPT report does not retain URLs for its source ledger. Its detailed native
  telemetry and recent-commit claims were not used as grounds for changing configuration.
- The primary licence for the extraction release is MIT:
  [release licence](https://raw.githubusercontent.com/xberg-io/xberg/v1.3.9/LICENSE).
  [Official installation documentation](https://docs.xberg.io/getting-started/installation/) and
  [CLI documentation](https://docs.xberg.io/cli/usage/) describe Windows support. The package metadata
  checked on this date lists six non-Windows wheels and no source distribution for that release:
  [PyPI release metadata](https://pypi.org/pypi/xberg/1.3.9/json). This does not disprove a separate
  Windows CLI binary; it blocks assuming the proposed Python installation path works. The
  [official release assets](https://api.github.com/repos/xberg-io/xberg/releases/tags/v1.3.9)
  actually list a Windows x86-64 CLI ZIP of 50,534,472 bytes with a published SHA-256 digest.
  It was not downloaded; OCR language data, extracted footprint and end-to-end suitability remain
  unmeasured.

## Implementation and verification

Implemented on the isolated evaluation branch:

- Existing evaluation rows now include initial Git tree, task and external-grader hashes, plus
  requested route metadata. The fixture graders were not changed.
- `tools/coordination-compare.mjs` reads executed reports and current host receipts without modifying
  either. It distinguishes input mismatch, missing evidence, stale outcome snapshots, accepted versus
  rejected attempts, and unknown versus measured effort. It includes later receipt annotations,
  avoids double-counting waiting, and makes no automatic routing or savings decision.
- Checkpoint save now supports omission of the optional task list through both the helper and public
  CLI. An explicitly invalid task identifier is still rejected; preservation scope is unchanged.

These changes reuse existing mechanisms rather than introducing another receipt schema or service.
No report claim was used to enable telemetry, change authentication, upgrade a vendor, add an MCP,
change routing defaults or add another creative approval stage.

### Live routing trial and its limits

Only the implementation fixture pair was attempted; the planned second case was stopped after the
observed Claude capacity failure. Raw reports and the offline comparison are under external `paired/`.

| Actual route | Host result | Delegate seconds | Integrated original grader |
| --- | --- | --- | --- |
| Codex CLI | accepted | 172 | passed after fast-forward integration into the disposable fixture |
| Claude CLI | needs-inspection | 62 | not attempted; CLI returned a weekly-limit error |

The Claude CLI explicitly reported a weekly limit resetting 22 October at 06:00 Europe/Rome.
A later coordination-lock error obscured that cause in the host receipt. Inspection confirmed that
the recorded main process had exited and the response contained zero model tool calls. The actor/run
was marked failed with that evidence; the original needs-inspection receipt was retained unchanged.
The observed limit was added to existing capacity tracking, and no further Claude trial was launched.

An initial experiment-wrapper variable collision also needs recording: dot-sourcing the evaluator's
default parameters rebound the requested vendor. The first run actually used Codex, and both its
host receipt and evaluation report correctly identify Codex. The wrapper was corrected before the
Claude attempt; no vendor identity was relabelled to fit the intended ordering.

The Codex contribution needed no corrections and passed the original host grader again after
integration. Integration took 0.753 seconds. Its review interval overlapped unrelated diagnostics,
so review effort remains null rather than an invented zero. Both reports have matching recorded
input fingerprints; the comparison correctly reports incomplete effort. Their actual model/effort
remain unobserved in these receipts. This is functioning provenance and failure capture, not a
representative paired benchmark, an engine ranking or a reason to tune routing.

### Test evidence

- The unchanged initial `aos test` passed 504 tests under each required shell, with no failures or
  skips; parsing and ASCII checks passed.
- New regressions first failed before implementation. A separate negative control removed just
  the checkpoint fix: both shells then passed seven new tests and failed the two omitted-task
  regressions. Restoring the fix passed all nine focused regressions in each shell.
- The Python capture launcher's original PowerShell 5.1 runs inherited PowerShell 7 module paths
  and loaded the wrong utility module. Those failures were not treated as production failures or
  valid coverage. The launcher now starts the older shell through PowerShell's native compatibility
  path. Temporary test scaffolding was removed; no existing measured assertion was weakened.
- Final combined-suite output is retained in `full-final-pwsh.log`; final counts are recorded after
  that frozen-runtime run completes.
