# Free-worker usefulness and delegation coverage

**Later same-day update:** the supplied external drive identified the user's actual `swarm v2`
and its earlier orchestration adapter. The [recovery assessment](2026-10-21-swarm-recovery.md)
supersedes the repository-identity unknown below and records fourteen archived credential slots,
current authentication, an independent live free-account check and reproduced defects. The original
evaluation below remains the earlier current-machine evidence.

21 October 2026, Europe/Rome. Check the existing OpenRouter/OmniRoute route and identify the
operator's separately mentioned swarm with rotating free LLM keys. No production behavior was
changed, Claude inference used, paid trial invoked, or new provider connected.

The installed free worker is useful for bounded text and code candidates. A single agent can use
it directly. A lead can build a checked multi-step workflow around it. Native managed delegation
and automatic routing to this provider are **not integrated** into aos: those schemas currently
admit only Claude and Codex. The helper also serializes tasks rather than running a parallel swarm.

## Which routes actually exist

| Route | Observed state | Delegation coverage |
| --- | --- | --- |
| OpenRouter through OmniRoute | One active OpenRouter API-key provider connection in the local gateway; one saved explicit allowed free route. Six new actual requests completed. | Callable from any authorized agent with a shell through the shared launcher. Text-only candidates with no filesystem tools; host verification remains necessary. |
| Direct OpenRouter video-project trial | Existing `tools/or/or.ps1` and `or.mjs` in the `where-you-end` video project. Project instructions document coding/video caps and one saved key. | A separate **paid capped trial**, outside the native harness. It was inspected, not called. It does not establish an additional free-worker pool or key-rotation implementation. |
| Separate free-key swarm repository | Not identified from eleven supplied text attachments, setup research, clone metadata and relevant chat history. The feature inventory describes an unnamed queen/worker orchestrator. | Unknown installation, credentials, quota semantics and callable route. A repository name/URL is still required. Ruflo and Headroom are distinct audited projects; neither was assumed to be the intended repository. |

OpenRouter is the upstream provider and OmniRoute the local gateway for the tested connection;
these are not two independent quota pools. The installed policy helper rotates the local worker
access credential for secure storage. That operation is not upstream free-account/key rotation.
[OpenRouter documents](https://openrouter.ai/docs/api_reference/limits) that adding accounts or API
keys does not enlarge its globally enforced capacity. Provider/model-specific limits still apply.

## Live usefulness checks

Only synthetic task data was sent. The existing helper checked current zero pricing, used the
restricted route and sent no-fallback/zero-price preferences. No model name was added to the repo.

| Task | Result | Full helper time / inference time |
| --- | --- | --- |
| Classify twelve issue tickets into media/auth/docs/UI | All twelve labels correct; actual shared CLI from the lead agent. | 98.893 s cold / 2.663 s |
| Summarize changing evidence | Four final states and decisive source IDs correct; unknown preserved; instruction embedded in source text ignored in this fixture. | 5.909 s / 4.561 s |
| Write a pure task-readiness helper | Host inspected the code; nine independent behavioral tests passed. Empty stub baseline failed eight of nine, so the checks detect missing behavior. | 23.314 s / 21.985 s |
| Extract corrected Italian facts | All facts correct, including a withdrawn date preserved as null. Original exact-string assertion failed because the voice description included additional faithful source wording. Host factual review passed without another model request; original failure retained. | 4.789 s / 3.124 s |
| Extract eight workflow jobs | All IDs, durations and dependency lists matched the source. Host verified this output before the next request. | 3.089 s / 1.827 s |
| Schedule the verified predecessor output | Eight jobs, two resource lanes, valid dependencies, no overlapping lane work and optimal eleven-minute makespan. The two resource lanes are schedule data, not two simultaneously running inference workers. | 10.805 s / 9.485 s |

There were four strict structured-output passes, one code candidate subsequently passing nine tests,
and one factual pass after host inspection of an overly strict wording assertion. This small sample
does not establish a general success rate or robust prompt-injection resistance. All original worker
receipts retain `accepted=false`; the assessment is evidence of these tasks, not general code admission.
Generated code was a synthetic fixture and was not installed into the production stack.

The free-model counter changed from 0 to 6 of the account's reported daily 1000-request ceiling;
reported `usage_daily` remained zero. These are point-in-time account measurements, not guaranteed
future capacity. Null credit limits were not interpreted as zero credit. Total provider-reported
tokens were 6289. The gateway owned for evaluation stopped after the batch.

## Efficiency and orchestration

The first cold CLI call spent about 96 seconds outside inference. This includes route setup,
authentication, metadata and startup work; it is not an isolated server-start measurement.
The next owned batch gateway took 9.096 seconds to become ready. Once ready, full helper requests
took 3.089-23.314 seconds, median 5.909 seconds, with about 1.3-1.7 seconds beyond inference each.
Batching related useful tasks through one deliberately reused foreground gateway therefore avoids
repeating setup. One tiny task can cost more wall time to delegate than to finish inline.

Useful candidates demonstrated here are issue triage, evidence extraction, compact grounded
summaries, pure helper drafts with behavioral tests, and dependent planning from verified inputs.
Keep consequential decisions, unrestricted repository changes, complex debugging and final acceptance
with the lead. Neither lead review time nor a comparable native-model baseline was measured; no
quantitative Claude/Codex quota or end-to-end speed saving is claimed.

The live dependent workflow worked through explicit packet handoff and a host correctness gate.
Admission probes separately confirmed that `Resolve-AosTaskRoute` and `Invoke-AosDelegate` reject
both `openrouter` and `omniroute` as native vendors, before inference. The coordination guide has no
automatic free-worker routing branch. The exclusive helper lock refuses a second task while held;
it is single-worker serialization, not an implemented parallel provider pool. There is no native
third-provider completion, task-acceptance or cancellation lifecycle to claim.

Single-agent use today, from the setup repo:

```powershell
python tools/stack.py omniroute-task --packet task.txt --output new-candidate.json
```

The shared tool catalog and README expose that route to both agents. Only the current Codex lead
invocation was live-tested here; no live Claude execution was used. A coordinator can call the same
helper sequentially, validate the returned facts/code and pass only checked output downstream.
Reusing an existing authenticated foreground gateway preserves it; the helper stops only its own
server. Current policy remains one task at a time with explicit free admission and no paid fallback.

To make free workers native orchestration targets would require a separate checked implementation:
provider identity/admission, task/result receipts, input and output gates, queue/concurrency limits,
quota-aware failure handling, lifecycle/cancellation and a comparison on representative real tasks.
Adding an unidentified rotating-key framework or merely changing a vendor enum would not establish
those behaviors. This evaluation does not silently implement that architectural change.

## Evidence and scope

Evidence: `~/.aos/research/free-worker-utility-20261021`.
`results.json` preserves original outcomes, candidates preserve actual outputs, and
`host-assessment.json` adds the explicit code/factual checks. `orchestration-admission.json` records
native rejection. Account metadata contains only selected non-secret fields. The accompanying
[sanitized receipt](2026-10-21-free-worker-evaluation.json) records code/evidence identities.

Executed: six actual free calls, nine generated-helper tests plus their failing stub baseline,
two-provider native route/delegate refusal probes, an exclusive-lock control, and source/receipt
consistency checks. The full `aos test` suite was not repeated: this commit adds evidence documents
only and changes no production source or measured tests. Earlier 531-per-shell integration results
remain historical evidence in the [integration report](2026-10-21-stack-integration.md).
The unrelated media handoff and previous failures were preserved. No account/operator change is
needed for the tested route; the separate swarm's name or URL is the remaining information gap.
