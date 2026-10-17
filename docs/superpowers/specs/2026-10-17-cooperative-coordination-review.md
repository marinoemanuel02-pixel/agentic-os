# Coordination design: separate reviews and dispositions

Date: 2026-10-17. Scope: the design in
[`2026-10-17-cooperative-coordination-design.md`](2026-10-17-cooperative-coordination-design.md).
This records design review, not implementation validation. Findings below refer to the initial
committed draft `b1df3b0`; subsequent edits address them as described. The revised draft has not had
a second independent review and is awaiting user review before implementation planning.

## Codex self-review

The first two findings were recorded and corrected before the independent critique was requested.
The third was recorded before reading Claude's result.

- **P1, draft lines 117-127:** session registration could double-count an admitted delegate, and idle
  presence could be mistaken for admission. The draft now distinguishes presence from reservations
  and attaches a delegate session to its already reserved actor.
- **P2, draft lines 156-163:** a read-only assignment could prohibit the coordination updates needed
  for acknowledgements and clarification. The draft now permits scoped runtime-state commands while
  preserving read-only project access.
- **P1, draft lines 69-77:** native implementation output had no defined path into the coordinator's
  assigned worktree, where the existing host commit and verify operate. The revision defines an
  exclusive native writer with a read-only coordinator, or scoped patch integration from separate
  worktrees after native writers terminate. CLI delegates still do not commit.

## Claude independent critique

Reviewer status: **completed**, through `aos delegate claude`, receipt id
`20261017-151039-8586-claude-goal-improve-agentic-os-so-eit`, 38 seconds. The reviewer read the full
spec and spot-checked `docs/routing.md:22`. It did not re-check the other code citations or run tests.
The receipt's accepted state means the review was returned successfully, not that the design passed.
The author's findings above were not supplied to Claude.

Claude's overall recommendation was to tighten the design before planning: the direction was sound,
but the first increment was too broad and several demonstrations could pass without real cooperation.

| Claude finding, location in initial draft | Author's disposition after checking the spec and request |
|---|---|
| HIGH, 108-147 and 211-217: increment 1 mixes routing fixes with substantial admission/lifecycle machinery | Accepted the delivery concern. Routing/policy/receipts are now a separate first increment, followed by minimal actor admission. Did not defer admission until an overbooking incident: the existing budget already requires accounting for read-only and native workers. |
| HIGH, 129-134 and 241-245: self-authored registry records cannot prove native workers | Accepted. Require observed harness handles/status or transcript evidence, with native-route eligibility established before the live fixture. |
| MEDIUM, 110-113: a cap of two permits only one child per coordinator; remove foreign coordinators | Accepted the arithmetic and made it explicit. Did not remove the pattern: assigning a bounded unit to the other vendor's native team is part of the operator's request. One child can still use a different model, tool set and isolated context. No larger team is enabled silently. |
| MEDIUM, 117-127: unspecified queue owner, idle-session admission and orphaned children | Accepted. Busy admission returns to the lead; there is no durable queue. Idle presence alone consumes no slot. Reconciliation checks each child's own termination evidence; unresolved children stay visible and have an explicit operator reconciliation path. |
| MEDIUM, 156-180: live messages are a large surface; use blocked receipt and re-dispatch instead | Accepted as the interim baseline. Did not remove live clarification from completion criteria: one-shot delegation alone leaves the identified cooperation gap. Hook identity is now explicit; ambiguous hooks must leave addressed messages unread. |
| MEDIUM, 80-96: tier policy is not evidence of cheaper execution | Accepted. Routing and honest fallback tests prove behavior only. Saving claims require observed model and measured comparisons. |
| MEDIUM, 14-16 and 241-243: vague usefulness/quality criteria | Accepted. Fixed checks require distinct contributions; removing either vendor's artifact must fail a check or omit a deliverable. The same fixture/base/checks run with one agent, with both elapsed times reported. A defect found by the other vendor is not the only valid execution contribution. |
| LOW, 237-238: semantic dependency detection has no automatic mechanism | Accepted. Declare it a lead judgment and work-breakdown rule. Automated tests check declared dependencies; live evidence checks actual routing. |
| LOW, 203-205: policy precedence needs runtime evidence | Accepted. The small-task demonstration must show that imported process-skill defaults do not trigger a redundant reviewer. Vendor plugin caches remain untouched. |
| LOW, 103-106: supported auth-mode metadata is not established for both clients | Accepted. Capability discovery is a gate; an unverified CLI route is not used for unattended subscription-only work or advertised as verified. |

Claude explicitly did not count version-dependent native effort, optional session resume or
experimental teams as defects because the spec already schedules capability checks for them.

## Agreement and disagreement

- **Both flagged:** no identical same-location defect was independently reported by both reviews.
- **Only Codex:** the three self-review findings above.
- **Only Claude:** the ten critique findings above. The author accepted or narrowed the concrete
  issues; several architectural simplifications remain disagreements, recorded in the table.

Codex's recommendation is to review this revised spec, then write a task-level implementation plan.
Do not describe the whole change as complete after only the routing/policy increment. Admission,
native output integration and live exchange must have evidence before claiming the requested team
cooperation works.

## Checks performed in this design stage

- Initial committed draft: `git diff --check HEAD^ HEAD` passed.
- A document check found no unresolved TODO/TBD/FIXME/PLACEHOLDER tokens, machine-specific absolute
  user paths, or pinned cloud model ids. The confirmed automatic-routing decision was present.
- Previous audit: `node --test config/hooks/aos-notes.test.mjs` passed 11/11; resolver and parser checks
  reproduced the ignored Claude model and unsupported effort option. No production fix is claimed.
- No source, tests, vendor configuration or synced rules were changed in this stage. The full
  PowerShell suite, live cooperation fixtures and bootstrap preview were skipped because implementation
  and rollout have not started. They remain requirements in the spec.
