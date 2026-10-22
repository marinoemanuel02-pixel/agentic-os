# First conjoined task

The lead owns the split, host checks and integration. Use the [coordination skill](../agents-home/skills/coordination/SKILL.md), [contracts](coordination-tuning.md), [routing](routing.md) and [swarm guide](swarm.md) for details. Commands below use placeholders; substitute actual ids, paths and quoted text.

## Before you start

Read actual account usage in Claude Code and Codex respectively:
```text
/usage
/status
```
Record the observed allowance, then run the read-only readiness gate:
```powershell
aos capacity set <claude|codex> <percent left> --resets <ISO> --note <text>
aos ready <repo>
```
A limited vendor, full actor cap or refused task paths fail readiness. A held checkout, stale capacity, uncommitted changes or commits only on this machine warn. Resolve failures before dispatch. The capacity ledger goes stale; a long lead context drains the 5-hour window fast. The operator can reset Codex's weekly allowance; its 5-hour window still binds.

## Reserve the lead and checkpoint

Reserve before the first managed dispatch; add the optional worker flag only when needed:
```powershell
aos coord reserve <lead-id> --as <vendor> --task <task> [--workers 1]
aos coord checkpoint save <id> --repo . --next-check <text>
aos coord checkpoint check <id> --repo .
```
The worker flag creates child actor <lead-id>-native-1. Lead plus that child fill the vendor's two slots. Two Codex delegates can run at once under a Claude lead. A reservation alone does not prove a native worker ran. Preserve required untracked/ignored material separately; checkpoints preserve tracked content. Inspect active actors before continuing.

## Split the work

Give independent files to parallel writers, each in its own worktree. Check semantic dependencies as well as file overlap. The implementing vendor does not write the tests: have the other vendor write tests first as a prerequisite task, with test files declared as artifacts. See the tests fail before implementation. Implementers depend on that task and start only after its accepted result is merged into their checkout. One writer owns each checkout, including native children; only the lead integrates.

## Write contracts

Use fields `version`, `id`, `objective`, `task_class`, `depends_on`, `allow`, `verify`, `artifacts`, `context`, `route_reason`, `review`, `budget`. Write contracts need nonempty `allow`. Every contract needs `verify`; the host runs it. For a focused suite under both Windows PowerShell 5.1 and PowerShell 7, use:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Focused.ps1 -Filter "<name filter>"
```
Keep the whole packet under 12,000 characters. Leave `context` empty and tell the worker which files to read in the task brief. A changed contract needs a new task id; an identical retry keeps its id and gets a new run id. Prerequisite artifacts must match accepted evidence; comparison tolerates CRLF/LF conversion for text files only.
```powershell
aos coord task register c.json --repo <checkout>
aos coord task ready <task-id> --repo <checkout>
aos coord task packet <task-id> --repo <checkout>
```

## Dispatch

Name the objective, dependencies, allowed files, acceptance checks and return format in task.md:
```powershell
aos delegate <codex|claude> --task task.md --contract c.json --repo <checkout> --write --tier standard --parent <lead-id>
```
Omit `--allow`; repeating it must match the contract's set, not a subset. A Claude worker may run only the verify executable unless more are declared with `--needs "<probe command>"`. The host runs the probe and requires exit 0. For example, add this to the dispatch to declare pwsh:
```text
--needs "pwsh -NoProfile -Command exit"
```
Tell Codex workers NOT to run the full suite: a delegate sandbox cannot run it meaningfully; about 54 tests fail there for environmental reasons. The lead runs it on the host at integration.

## Watch while workers run

The prompt tells a worker that asks a question to wait about 30 seconds, then return blocked. Keep a background loop on this inbox command running while workers run; exit the loop on the first message and handle it promptly:
```powershell
aos coord inbox <lead-id>
```
Reply and acknowledge explicitly; reading does not acknowledge:
```powershell
aos coord send <lead-id> --to <worker-id> --text <text> --reply-to <message-id>
aos coord ack <lead-id> --ack <message-id>
```
Restart the watcher after handling a message. Cross-lead messages are refused because they belong to separate task trees. For lead-to-lead notes use:
```powershell
aos note <text> --as <vendor>
```

## Read receipts and retry

```powershell
aos delegate ls
aos delegate show <id>
```
Accepted means the host verifier passed; the lead still reads the patch. For rejected or blocked runs, read the summary and unverified list, fix the cause and retry the same contract id. If the contract changes, use a new task id. Preflight-failed means the host declined to launch, for example because a needs probe exited nonzero. Keep missing receipt evidence or unconfirmed termination open for inspection.

## Integrate and verify

Claim the target checkout, inspect scope and merge the accepted delegate branch:
```powershell
aos claim <checkout> --as <vendor>
git merge --no-ff <accepted-delegate-branch>
```
From that checkout, run the focused tests on the host in both shells, then the full suite in both shells:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Focused.ps1 -Filter "<name filter>"
aos test
```
Dispatch dependent work only after its prerequisite is merged. A host receipt does not replace checks on the combined result.

## Record and finish

Record measured corrections and integration/review time, inspect the report, then finish actors with actual completion evidence and release claims:
```powershell
aos coord annotate <run-id> --corrections <n> --integration-seconds <s> --review-seconds <s> --text <text>
aos coord report
aos coord finish <actor-id> --evidence <text>
aos release <checkout> --as <vendor>
```
Do not finish a coordinator while a launched child remains unconfirmed. Report checks that ran, failures and skipped checks; unknown usage stays unknown.

## When a limit is near

Use the [handoff skill](../agents-home/skills/handoff/SKILL.md) to write HANDOFF.md and preserve a checked checkpoint and required untracked/ignored material. Inspect in-flight work; a quota error does not prove workers stopped. Retain the source checkout until recovery is verified. After a real limit, record only the observed limit/reset, then check continuation before reserving the receiving lead:
```powershell
aos capacity set <claude|codex> <percent left> --resets <ISO> --note <text>
aos coord continuation check <checkpoint-id> --repo . --from <vendor> --to <vendor>
```
The read-only check needs current source-limit evidence, known positive target capacity, valid checkpoint state and no unresolved active actors. The receiver reads HANDOFF.md, checks preserved material and runs the saved next check. Handoff never accepts partial work.

## Known traps

- PowerShell 7 children inherit `PSModulePath`; a Windows PowerShell 5.1 child can then lose cmdlets such as Get-FileHash. tests\Run-Focused.ps1 clears it for its 5.1 child.
- Put delegate worktrees outside OneDrive. The setup handles OneDrive-hosted repos, but heavy caches do not belong there.
- Pass Windows paths to pwsh and python. Write source with file tools, not long shell heredocs.
- The swarm drain command prints the whole queue. The [swarm pool](swarm.md), nar (`nar_choose`, `nar_classify`) and capability tools are for bounded, checkable candidates only. Never accept their results without a lead-authored verifier.
