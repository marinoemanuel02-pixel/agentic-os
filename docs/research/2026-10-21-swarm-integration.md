# Swarm implementation and live integration

**Implementation and checks: 21 October 2026.** Both authorized recovery passes are
implemented in the shared stack. This report distinguishes working routes from conditional
capacity. [Usage and account maintenance](../swarm.md) cover both agents and the operator.

## What is operational

- A maintained API worker core with validated account records, Windows-encrypted secret
  references, transactional quota admission, charged attempts, cooldowns, bounded failover,
  queue concurrency, cancellation, host verification and crashed-owner reconciliation.
- One shared command for direct tasks and workflows: `python tools/stack.py swarm`.
  Existing registered coordination contracts use their normal context/dependency checks,
  verifier, host receipts and artifact hashes through a separate API bridge. API accounts
  do not become Claude/Codex native actors or repository writers.
- Text preparation, supplied-source claim/quote tables, embedding batches, reranking,
  PNG/JPEG questions and short authorized PCM16 WAV transcription. Media is snapshotted;
  embedding routes stay in one provider/model space. Candidates cannot execute tools.
- The existing plain-text OmniRoute task command now uses the same admission ledger after
  pool activation. Its restricted free gateway policy and owned lifecycle remain in force.
- Both shared skills now describe when and how to use these routes. Existing canonical
  skill paths/junctions expose the instructions to both vendors; no duplicate skill,
  global MCP registration, PATH change or native authentication export was added.

The original recovered source was read-only during this work; its credential-free snapshot
is retained. This
implementation carries forward the useful worker-core design and defect requirements;
it does not claim the old framework's 145 source files were repaired or deployed wholesale.
The original drive was unavailable at the final recheck, so fresh backup hash comparison
is unknown. The saved 145-file source snapshot was checked independently; the implementation
does not write to the archived source.

## Accounts and actual availability

Seven recovered keys were moved directly from the operator's backup into DPAPI, without
plaintext exports, environment files, logs or chat. The registry has **nine route records
over eight credential references**: current/recovered OpenRouter, the current OmniRoute
alias, two Gemini, two Mistral and two Cohere records. Records are not independent quota
claims. The current OpenRouter and OmniRoute records share one bucket. Gemini and Mistral
key pairs conservatively share buckets because independent projects/organizations were not
established. The two Cohere organization identities were previously established as distinct.

| Route | Actual result | Current role |
|---|---|---|
| Current OpenRouter | Correct complete text; reported request cost zero; accepted live contract task | Active free text worker |
| Recovered OpenRouter account | Correct complete text and accepted parallel task; reported cost zero | Active free text/failover worker, under shared global ceilings |
| OmniRoute | Correct text through the pool and through the existing plain-text compatibility CLI | Active optional gateway route; same upstream allowance |
| Gemini | Current-model text, embeddings, image reading and timestamped synthetic-audio transcript; accepted dependent contract and parallel tasks | Active admitted capabilities |
| Cohere | Correct text, embedding batch, relevant reranking and grounded quote extraction; accepted parallel task | Active admitted capabilities |
| Mistral | Authenticated model discovery, but three bounded generation attempts returned 429 | Conditional; moved behind live-verified providers and honors cooldown |
| Groq | Earlier authenticated and anonymous access checks both returned 403 | Adapter available; no active account, no invalid-key inference |
| Cerebras / Hugging Face | Recurring included free capacity was not established by the primary-source audit | Excluded from assumed recurring-free workers |

The operator explicitly confirmed Gemini, Mistral and Cohere as free/evaluation with paid
usage disabled. Their seven-day eligibility records are **operator attestations**, not live
billing API proofs. OpenRouter uses a fresh zero-price catalog and zero-price/no-fallback
request guards. Provider-reported cost is unknown where the response does not supply it;
no aggregate paid-usage claim is inferred from those responses.

The [earlier recovery report](2026-10-21-swarm-recovery.md) contains opened primary sources
for account/project/global limits and free eligibility. In particular,
[OpenRouter documents global restrictions](https://openrouter.ai/docs/api_reference/limits)
and [Gemini documents project-scoped limits](https://ai.google.dev/gemini-api/docs/rate-limits).
The local pool adds conservative account ceilings plus shared OpenRouter/OmniRoute ceilings
of ten attempts per rolling minute and thirty per rolling day. Account rotation cannot
raise those limits. More providers and verified independent allocations can increase useful
capacity; more key strings alone cannot.

## Measured workflows

- Six initial text route checks covered Mistral, Gemini, Cohere, current/recovered OpenRouter
  and OmniRoute. Cohere and both OpenRouter routes returned the requested city, arithmetic
  and missing-date null correctly. OmniRoute also returned the correct result.
- Three independent tasks on Cohere, Gemini and recovered OpenRouter completed in **3.199 s
  for the batch**, using three workers. All three passed a lead-authored JSON/fact verifier
  and became host accepted. Provider-call times were 0.9512, 0.9626 and 1.1193 s; secret,
  metadata and scheduling overhead is included in the batch time. No matched sequential
  benchmark or subscription-quota saving was measured.
- Two registered contract tasks passed real host verification. OpenRouter produced the
  declared facts artifact; Gemini received that verified artifact through an explicit
  context range, doubled its total and preserved its unknown date. Both ordinary host
  receipts were accepted, and the final artifact was correct. No native actor was fabricated.
- Cohere embedded two multilingual texts and ranked the actual relevant document first.
  Its supplied-source research response passed exact source-ID and verbatim-quote checks.
  Gemini's embedding batch had valid, equally sized finite vectors.
- Gemini read the synthetic image's depot text and count correctly. The initial strict
  fixture expected a normalized city name, while the candidate preserved the full visible
  label; this failed that exact-string fixture and remains recorded. Source inspection
  confirms the visible label and count agree. It is not a universal OCR quality evaluation.
- Gemini's first synthetic-audio response had invalid timestamps and was rejected. A later
  bounded attempt passed the timestamp checks and contained the expected synthetic speech,
  depot and city words. No validator was weakened. This is not an accuracy benchmark over
  arbitrary speech or permission to use unchecked subtitles.
- OmniRoute's first pool task took 113.197 s including cold owned startup; the compatibility
  workflow later passed in 20.915 s. Direct provider routes are preferred for short tasks.
  The gateway's presence alone does not establish additional quota or efficiency.

## Reproduced defects and verification

The archived source's eight expected-failing probes remain unchanged in the recovery
evidence. The maintained suite covers their requirements: no hard-cap/degraded fallback,
permanent cooldown exclusion, final-call admission, accounting per actual attempt, shared
credential identity, valid system text, explicit zero-price/no-fallback requests and atomic
reservation of the last slot. Additional red/green checks cover a larger-limit duplicate
alias, queue contention, shared daily ceilings, optional contract budgets and host-only
supervision metadata.

`aos test` passed **533 Pester tests in Windows PowerShell 5.1 and 533 in PowerShell 7**,
with zero failures or skips. Final targeted checks also run the current **35 worker tests,
6 host-contract tests and 12 existing OmniRoute integration tests**. Host tests use disposable
repositories and redirected coordination state. A real bridge round trip additionally
executes under Windows PowerShell 5.1, rather than relying only on its parser. Python
compilation, PowerShell parsing/ASCII and diff checks are separate checks.

Some final safety cases were added after the full-suite run; their current targeted reruns
are recorded separately. Initial failures are retained, including deprecated-model selection,
missing optional budget handling, Windows PowerShell's script execution policy, one queue
contention bug, inherited PowerShell module paths, the larger-limit alias and cross-account
daily-cap regressions. The failover
test was corrected to use a different provider: an organization/provider-wide 429 must not
be bypassed by trying another key at that provider. Original archived measured tests were
not edited. No Claude session, external review or autonomous vendor-routing quality benchmark
was run under the operator's explicit exception.

The [sanitized receipt](2026-10-21-swarm-integration.json) records source hashes, exact live
outcomes and limits. Larger receipts and synthetic fixtures remain under the home evidence
folder. Unrelated media handoff material is unchanged. No provider account was created,
upgraded or connected to paid billing.

## Remaining operator choices

No action is required to use the working routes. For more capacity, add an independently
eligible account using `aos secret set` and `swarm-accounts --add-account`, with its actual
shared quota identity; the old fixed two-slot catalogue is no longer the integration limit.
Renew free/evaluation attestations after checking billing, using the command in the usage
guide. Mistral availability and Groq access remain conditional external limitations. Neither
requires rotating keys merely because discovery succeeded but generation/access failed.
