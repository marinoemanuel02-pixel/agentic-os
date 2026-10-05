# Independent capacity review and response

The first production review, receipt20261005-211532-7f00-claude-read-only-independent-review-o,
reported no blocker but found additional date/exhaustion issues. Codex inspected its receipt and production diff,
added five regressions, and observed all five fail before fixing the code. No existing test was removed or weakened.

- Only Claude: an exhausted unexpired weekly limit became merely stale. Accepted: exhaustion binds until reset.
- Only Claude: offsetless ISO CLI dates were ambiguous; unspecified DateTime and quota-error formatting differed
  across shells/cultures. Accepted: explicit CLI offset, UTC normalization, invariant formatting and ledger reset
  normalization at the same boundary as timestamps.
- Only Claude: a healthy observed week hid the need to refresh an expired session. Accepted: keep the week visible
  and ask to refresh the reset window.

Codex ran all25 capacity tests under Windows PowerShell5.1 and PowerShell7:25pass/0fail in each. The five review
regressions followed the12 independently authored Claude regressions, which Codex also saw fail before the fix.
The original weekly-binding test remains intact. Full443-test verification is recorded separately once complete.

The final blind review, receipt20261005-213651-59a2-claude-read-only-final-independent-re, accepted the branch with
no shipping blockers. It independently passed all25 filtered capacity checks under both shells. Its first attempts
omitted the runner's isolation environment and failed25checks per shell; it corrected the setup, checked that the
real ledger was untouched, and reported those failures. Neither reviewer receipt proves the full suite passed.

Remaining proposals are deferred: a future log line can keep advice unknown until its timestamp catches up;
all-malformed newer telemetry can replace a ledger limit with unknown; localized decimal display is cosmetic;
unparseable quota errors still have no known reset/window. These fail safely or predate this branch and do not
justify speculative changes during a release. A future adapter should preserve native source/observation time
and both windows, rather than automatically inventing availability. No credentials, profiles or paid settings changed.

Both vendors flagged the original expired/stale quota defects. Claude alone found the additional review defects.
Review verdicts remain separate from this director response; receipt files retain commands and limitations.

The final-review task template is a documentation improvement, not new runtime behavior. Its final independent
review is recorded with the film's closing review. Do not claim that the earlier capacity review covered it.
