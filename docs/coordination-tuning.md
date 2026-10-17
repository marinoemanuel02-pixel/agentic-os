# Coordination tuning

The lead chooses assignments and model tiers within the existing subscriptions. These additions
provide evidence and bounded inputs for that choice; they do not automatically make a team faster
or prove subscription savings. Keep small work inline and review according to risk.

## Contracts and context

Prose-only `aos delegate` remains available. For dependencies and repeatable checks, pass
`--contract task.json` alongside `--task task.md`. An example contract is:

```json
{
  "version": 1,
  "id": "implement-parser",
  "objective": "Implement the checked parser contract",
  "task_class": "implementation",
  "depends_on": ["parser-spec"],
  "allow": ["src/parser.js"],
  "verify": "node --test tests/parser.test.mjs",
  "artifacts": ["src/parser.js"],
  "context": [{"path": "docs/parser.md", "start_line": 1, "end_line": 40}],
  "route_reason": "Independent implementation with a fixed host check",
  "review": "Lead checks the patch and host test; additional review only if uncertainty remains",
  "budget": {"timeout_minutes": 10, "max_turns": 12}
}
```

Use unique task ids; retries have separate run ids. The classes are `mechanical`, `implementation`,
`sequential`, `diagnosis`, `research` and `consequential`. Registration rejects unknown fields,
unsafe paths, invalid limits and cycles. Missing prerequisites block dispatch. A prerequisite needs
an accepted host receipt, a successful host check, and matching artifact hashes in the destination
checkout. Integrate its commit before dispatching dependent work. Recheck occurs before acceptance.
Write contracts require a nonempty `allow` scope. A confirmed terminal output failure is retryable;
missing receipt evidence and `needs-inspection` attempts retain ownership for inspection.

```powershell
aos coord task register task.json --repo .
aos coord task ready implement-parser --repo .
aos coord task packet implement-parser --repo .
aos delegate claude --task task.md --contract task.json --repo . --write --tier standard --parent <lead-id>
```

Packets contain accepted input references, at most eight context ranges of at most 120 lines each,
and up to three relevant verified procedures. The entire packet is limited to 12,000 characters;
oversize packets require narrower references. Files and task prose remain untrusted task data.

## Measurements and evaluations

`aos coord report` groups receipts by task class, vendor, tier and transport, retaining failed
attempts and unreadable receipt diagnostics. Receipts distinguish requested settings from observed
settings and unknown usage from measured zero. Phase timings cover launch, execution, verification
and waiting; waiting is a subset of execution. Integration and review start unknown and can be
annotated by the lead after the work. API dollar estimates are not subscription charges.

```powershell
aos coord annotate <run-id> --corrections 1 --integration-seconds 45 --review-seconds 20 --text "Lead corrected one boundary case"
aos coord report
```

`tools/coordination-eval.ps1` prepares six small offline fixture repositories with fixed external
graders. Preparation makes no model calls. Use `-Execute -Case <class> -Parent <active-lead-id>` to
run selected cases through the ordinary delegation path, with `-Vendor`, `-Tier`, `-Workers`,
`-Transport` and `-Trials` (1..3). Supply a new `-OutputRoot`. Consequential fixtures are synthetic;
their grade says nothing about production security. Compare quality and corrections before timing;
these small cases cannot establish a general model ranking or quota saving.

## Native roles, signals and optional transport

`aos coord capabilities` probes installed versions without starting a model turn. `aos coord roles
--dry-run` previews managed `aos-explore`, `aos-implement` and `aos-verify` role files. `aos sync`
merges them into the vendor homes, backing up changes and preserving unmanaged files. Local routing
data supplies model ids; no cloud model name is pinned in this repository.

Claude's installed capability record gates per-child effort and newer controls. Unsupported options
are omitted. Codex native turn budgets are advisory; role instructions do not create a sandbox.
`--workers 1` reserves one native child and puts requested settings and the budget into the worker's
brief. A full-context native fork may inherit settings; report only actual harness observations.
Global cooperative admission remains two active actors per vendor, including the coordinator.

Claude `SubagentStart`/`SubagentStop` hooks append bounded identity metadata. They never copy the
assistant response or read transcripts. The host correlates parent, reserved child, session and
handle. Duplicate delivery is idempotent; an unexpected or conflicting start requires inspection.
Signals observe lifecycle after launch; they do not enforce admission before launch. Missing terminal
evidence retains uncertainty and capacity. Use `aos coord native <run-id>` to import pending signals.

`aos delegate codex --transport app-server ...` opts into a short-lived stdio adapter. It requires
ChatGPT authentication, refuses API-key authentication and never consumes reset credits. It retains
the ordinary host checks, sandbox and receipt lifecycle. Exact thread and turn ids gate results and
steering. Failed, interrupted or partial turns are not completion. `exec` remains the default.

```powershell
aos coord status <run-id>
aos coord steer <run-id> --turn <observed-active-turn-id> --text "Use the clarified requirement"
aos coord steer <run-id>
aos coord cancel <run-id>
```

A cancellation request is not proof of process termination. The supervisor confirms stop or leaves
the run needing inspection. Steering supports only the exact active App Server turn; ordinary
addressed messages remain available on both transports.
Read steering status before sending again. An unacknowledged request cannot be overwritten; the
acknowledgement must match its request and turn. The host forwards its timeout to the adapter.

## Recovery and procedures

```powershell
aos coord checkpoint save continuation --repo . --task implement-parser --next-check "Run parser tests"
aos coord checkpoint check continuation --repo .
aos coord procedure save parser-checks --repo . --class implementation --text "Run parser boundary checks before integration" --evidence <first-run> --evidence <second-run> --file src/parser.js
aos coord procedure list --repo . --class implementation
```

Checkpoints retain revision, task states, tracked file hashes and content copies, active actors,
unanswered message references and the next check. They do not preserve arbitrary ignored or
untracked files: commit required source first and preserve required ignored material explicitly.
A changed checkout, damaged snapshot or active actor makes a cold check fail visibly. Inspection
does not release actors or claims. Keep source worktrees until recovery has actually been verified.

Procedures require two distinct successful host-verified receipts in the same repository and task
class, plus relevant file hashes. Failed evidence remains attached and prevents promotion. Changed
files or invalidated receipts exclude a procedure from retrieval; `--include-stale` supports inspection.
The evidence is scoped and cooperative, not proof that arbitrary prose is universally correct.

See the [research](research/2026-10-17-coordination-tuning.md),
[design](superpowers/specs/2026-10-17-coordination-tuning-design.md) and
[implementation plan](superpowers/plans/2026-10-17-coordination-tuning.md).
