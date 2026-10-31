# Session audit: orchestrations, subagents and video productions (2026-10-31)

The operator asked for a check, with Codex, of all previous orchestrations and video productions, to learn from them
and upgrade the stack, noting that many sessions were stopped by him or by the PC shutting down. Two passes over one
evidence package: Claude measured; Codex checked the measurements and the stack independently (read-only). Their
findings are kept apart below. Evidence and scripts: `~/.aos/research/session-audit-20261031`.

## Sources and limits

- 190 Claude transcript files (156 sessions after folding forks and side sessions into the largest copy), 35 subagent
  transcripts (24 after folding), 178 Codex rollouts (on disk from 10-25 only), 135 delegation receipts, 1,464 ledger
  events (claims, video stages, verdicts), 13 film retros. Window 2026-09-27 to 10-31.
- Limits (Codex's metric check, all accepted): folding by first message drops divergent continuations (one Riema fork
  held 35 messages the kept copy lacks), so totals slightly undercount; Claude "turns" (assistant messages) and Codex
  turns (task starts) are not comparable; "clean" means the transcript ended on a reply, not that work was accepted
  (85 of 135 receipts were accepted, a different population); active and polling minutes are gap heuristics;
  window percentages are account-wide, so one session's quota cost cannot be isolated; error examples were sampled
  (12 per session), so counts drawn from them are lower bounds; category labels are keyword guesses.
- Sessions ending mid-work (58 of 156 Claude sessions) were mostly the operator's stops or PC shutdowns and are not
  read as stack failures. Their lesson is the same as for quota stops: commit and save outputs as you go.

## Dynamics

- Volume: Claude main sessions about 119 active hours (video 48, stack 34, Riema 23, quiz 10), Codex about 38
  (Riema 29), subagents the rest of about 165 in all. Claude
  read about 7.0 billion cached input tokens; Codex's 77 Riema rollouts read 434 M input tokens, 425 M of them cached.
- Context: 35 Claude sessions peaked above 400K tokens and 19 above 700K; the longest video and Riema sessions ran to
  about 965K. Every turn re-reads that context. 31 compactions in 20 sessions.
- Limits: 27 Claude sessions hit a plan limit at least once (39 events); sessions ending on 10-28 and 10-30 had the most.
  Delegations failed on quota 8 times (Codex) and on lost streams or DNS 6 times.
- Concurrency (10-minute buckets): two or more sessions active in 46 % of active time; 3+ Claude sessions, all on one
  5-hour window, for about 14 hours; Claude and Codex both active for about 34 hours.

## Orchestration and the guard

- Delegations: Claude 44 accepted of 58 receipts, Codex 37 of 73 (17 rejected, 14 failed, 4 preflight-failed).
- Codex write stages on the Riema site: 12-21 M input tokens each, 40-100 minutes; read-only Codex runs were
  cheap (median 45K input on gpt-6.1-sol, 64K on gpt-6-luna; 106 runs).
- Claims: 85 refusals in the ledger. 62 were Codex blocked by Codex, all between 10-02 and 10-20 (holders named by
  process id, by a run name, or a coordinator's native child); none since. The live problem was non-git claims: the shared Claude memory
  folder was claimed 81 times and refused other sessions' memory writes 10 times (10-12 to 10-30); no other non-git
  claim was ever contended, and those claims were per subfolder anyway.
- `aos` from agent shells: only the interactive pwsh profile defines it, so Claude's Bash/PowerShell tools and Codex
  exec failed with "aos not recognized" and fell back to long `Import-Module` one-liners. The shims that fix this
  were built and tested on 10-08 on `audit/no-brainers` and never merged.

## Subagents

- 25 Agent calls in 11 of 156 sessions: 18 `general-purpose`, 3 `aos-verify`, 2 `aos-explore`, 2 `Explore`; 10 named
  no model and inherited the lead's. 20 ran in the background.
- 6 children ended at the Claude plan limit (5 in the 10-09 research run, 1 branch reviewer) and returned nothing to
  the lead, but at least one had saved its work: a literature child wrote two ledger files over 278 calls.

## Spinning

- Small in time (heuristic: about 1.8 hours of consecutive polling calls in 165 active hours) but recurring in kind:
  244 Codex `wait` calls on running commands in 39 rollouts; 47 Claude reads of background `.output` files in 13
  sessions instead of waiting for the notification; 11 identical browser JavaScript calls in a row; blocked
  `sleep`-then-`tail` polls; PowerShell tool validator rejections resent unchanged; one Pester invocation failing
  10 times in a row in a delegated test-writing session.
- Friction: PowerShell tool calls failed 13.7 % of the time (Bash 3.1 %); 89 Edit/Write precondition failures
  ("file has not been read", "modified since read"); 91 command timeouts.

## Productions

Ledger stage minutes: pauseai-it 1,525 (revision 675), cant-escape-ai 930, alignment-now 613, alignment-3 377,
cant-escape-ai-2 350, huggingface-it 320, agi-asi-alignment 229 (stage minutes mix machine and human time).
Recurring classes across 13 films with retros (dossier, from retro text): motion and timing defects missed by
stills-only review (7 films); flat or unrecognisable props and characters (7); voice or mix not checked by ear or by a
number (8); dark or blown-out shots (6); delegated Codex output that could not be run or seen in its sandbox (6);
Windows and OneDrive tooling traps (6); template tools failing on shorts, Italian or word-cut films (5). pauseai-it
reached v20, about 12 of the versions on the cast; acceptance followed an operator-named reference.

## Findings, by vendor

Both flagged: the memory-folder claims; `aos` unreachable from agent shells; very large contexts; Codex write stages
re-reading 12-21 M tokens; review gaps on motion and sound; quota-stopped children.

Only Codex flagged:
- The shorts route had no enforced QA: `finish.sh` printed stream and loudness numbers and the template said to check
  by hand, while the last three films were shorts (verified: `qa.sh` hardcodes 1920x1080 and needs build.sh outputs).
- The frontier named a stills-judged cast as `best` that the operator then rejected six times.
- Operational notes contradict current code (the full-path verify note; R50's mean-luma text vs the YHIGH gate).
- A quota-stopped child's saved files should be read before re-running it.
- The metric caveats listed under "Sources and limits".

Only Claude flagged:
- The aos shims had been finished and tested three weeks earlier and stranded on an unmerged branch; about 30 local
  branches are unmerged into the working line.
- The 62 Codex-on-Codex refusals are historical (none since 10-22), not a live defect.

Disagreement: for non-git paths Codex proposed file-level claims; Claude kept "no auto-claim outside git, explicit
claims honoured", because every memory write touches `MEMORY.md` and a one-hour claim on it would recreate the block.

## What changed (branch `claude/stack-upgrade-1031`)

1. Guard: auto-claims only git work trees; explicit claims on other folders still hold (2 tests, first one red first).
2. `aos` shims for agent shells, ported from `audit/no-brainers` (13 tests, all red first).
3. Shorts QA: `finish.sh` runs the static gates and `tools/checks/delivery.mjs` and exits 1 on failure (14 tests,
   including a synthetic-clip integration test; checked on huggingface-it v6 and v7: pass at 1080x1920, fail at
   1920x1080).
4. Guidance: AGENTS.md (landing, repetition, context), coordination (long work, partial results, refreshed subagent
   figures), handoff (context trigger, Branches section), frontier (pinned `best`, clip evidence for moving
   dimensions), R50 text.

## Not done here

- `qa.sh` still carries its own copy of the delivery limits; moving it onto `delivery.mjs` is a separate change.
- Caption visibility on the real timeline (Codex's proposed check) is not built.
- The accepted Toon cast is not in the template yet.
- The unmerged branches (fixes on `fix/ingest-voice-*`, `frontier-characters-v9`, `feat/video-engines`, others) need
  a triage pass: land, or record why not.
- The audit scripts carry the limits above; fix them before using the numbers for routing policy.
