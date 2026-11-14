# Orchestration audit - 2026-10-28

Scope: the prior chat "Improve agent coordination", current coordination report and account
readiness, and the pool/coordination execution paths. Started at `afc3fe9` on `feat/pool-mcp`;
changes are on `codex/orchestration-audit`. This is a focused repair pass, not a claim that
every installed optional tool was revalidated.

## Repairs

| Evidence | Change |
|---|---|
| `--workers 1` precreated an allowance; following the skill attempted another reservation and hit the cap | Skill now names the precreated actor and tells agents to reuse it |
| An observed native handle could be replaced, then completed under an unrelated handle | Reject handle replacement before changing state |
| `accepted` runs could return to `running` or `waiting-input` | Terminal runs cannot return to active states; inspection can still resolve |
| Claude returned a weekly-limit error classified as `other` | Recognize weekly/daily/monthly/session limit messages as quota errors |
| Fresh zero capacity with no reset was classified as `low` | Treat it as limited, report unknown reset, retain normal staleness behavior |
| Optional pool approval configuration reads aborted otherwise valid Codex delegation | Omit the optional grant when registration cannot be read |
| Private local requests could follow redirects or use an environment proxy | Disable both routes for the local transport |
| Missing chat fields raised raw exceptions; invalid/short embeddings silently lost classifications | Normalize malformed responses and validate vector count, dimensions and finite nonzero values |
| Raw source size ignored schema/instruction/escaping overhead and cloud UTF-8 bytes | Check full prompts, local system/format text and the complete cloud packet |
| A string could become character-by-character variants; empty summaries passed | Enforce candidate list shape and require nonempty summaries |
| String feedback became truthy and unknown ids were accepted | Require a boolean and an existing result id |

The coordination skill also explains batching, result reuse, continuing with direct inspection
after a failed pool route, and closing confirmed children/lead before the final response. The
conjoined-task runbook limits mandatory cross-vendor test authorship
to risky fixes, matching the global contract. The stale AppData reference-cache comment was corrected.

## Live observations

- Private local extraction returned three correct fields from a supplied prior-run summary.
  The lead checked the source and recorded accepted feedback (`extract-5440c2d24b0e`).
- Live local embedding triage returned both synthetic items with the correct labels (spoken
  track to audio/speech; readable font to typography/fonts), no ties or omitted rows, in 5.971
  seconds. The lead checked both and accepted feedback (`triage-d17c1afe223d`).
- Public synthetic variants returned two local candidates in 8.255 seconds. All cloud attempts
  failed `not_free`; their safety admission remained enforced. The local candidates combined
  both requested categories instead of separating them. The lead recorded rejected feedback
  (`variants-621e7ff72f76`) despite the structural `pass` verdict.
- The local account listing admitted OpenRouter aliases but not recovered free-tier accounts.
  This is configuration eligibility, not proof that a live route works. No attestations were
  renewed and no paid fallback was enabled.
- The report contained 129 historical attempts, 85 accepted, and 88 with unknown usage. Task
  classes differ; these figures do not establish savings or comparative vendor quality.

## Review and verification

Claude test authorship failed at weekly quota in delegation
`20261028-203340-2524-claude-goal-independently-write-regre`. It produced no test file; host
compilation failed too. Codex authored the regressions and observed the relevant failures before
fixing production code. This does not satisfy independent cross-vendor test authorship.

A separate Codex native explorer reproduced the lifecycle defects. A subsequent native reviewer
checked the repairs and found the oversized tie-break; the lead reproduced and fixed it. This is
same-vendor scrutiny, not a second opinion. The later quota/optional-grant changes use host checks.

Verified on the repaired source:

- `aos test`: exit 0; 608 passed under Windows PowerShell 5.1 and 608 passed under PowerShell 7,
  with zero failures, skips, inconclusive or unrun tests. Parse/ASCII checks passed too. This
  includes the existing swarm, stack, media and coordination suites with their isolated fixtures.
- `python -m unittest discover -s tests -p 'test_pool*.py' -v`: 31 passed.
- `tests/Run-Focused.ps1 -Filter '*coordination identity regressions*'`: five passed per shell
  in the native review, after the lead observed three failing cases on the original code.
- `tests/Run-Focused.ps1 -Filter '*Vendor capacity*'`: nine passed per shell after quota repairs.
- `tests/Run-Focused.ps1 -Filter '*aos delegate*'`: 25 passed per shell after the optional-grant repair.
- `powershell -ExecutionPolicy Bypass -File ./bootstrap.ps1 -DryRun`: exit 0.
- `git diff --check`: passed.

Earlier full runs exposed the optional-grant regression and were not clean. Superseded initial
and diagnostic processes were cancelled; their incomplete output is not counted. The pool protocol
fixture emits an existing socket ResourceWarning. Raw final output is in the home-relative
`.aos/research/orchestration-audit-20261028/verified-suite.log`.

## Retained limits

- No independent Claude review or vendor-home/PATH configuration sync was possible this session.
- The six-day `claude-riema-sito` reservation has no process identity or completion evidence.
  Age alone does not establish safe release, so it remains reserved.
- Worktree prune dry run found stale registrations; Git also reported two permission errors
  during automatic metadata maintenance. No forced deletion or branch cleanup was performed.
- The quota-blocked Claude worktree was confirmed clean and removed with ordinary
  `aos delegate clean`; its failure receipt remains preserved.
- Existing unrelated `HANDOFF-media.md` remains untouched. The ignored root handoff will point
  to this audit and retain a backup of its superseded content outside the repository.
