# Recovered swarm and multi-provider capacity assessment

21 October 2026, Europe/Rome. The supplied external drive resolved the previously unknown
repository. The operator's system exists: **swarm v2**, with a separate optional integration in
the older **Orchestration Layer**. The current agentic-os setup does not expose that pool.

This assessment found additional usable account capacity and reproduced defects that prevent
safe wholesale reactivation. It did not install the old framework, change provider configuration,
migrate credentials or modify the external-drive backup. One explicitly zero-priced synthetic
completion verified the recovered independent OpenRouter account.

## What was found

Paths relative to the connected backup drive:

| Material | Location / status |
| --- | --- |
| Actual swarm source | `legacy/4-Media/swarm variants/swarm v2`; distribution metadata says 2.0.0, module says 2.0.0-mvp. No Git metadata, remote URL or licence file found. |
| Existing orchestration integration | `orchestration layer/src/dispatch/workers/swarm_pool.py`; registration behind `DISPATCH_SWARM_ENABLED` / `DISPATCH_SWARM_FANOUT_ENABLED`, external import via `SWARM_ROOT`. |
| Duplicate v2 copies | `legacy/6-Parked/_attic/2026-07-26/swarm-duplicates/swarm v2 - Copy` and `swarm v2 - Copy (3)`; key source-file hashes match the main copy. |
| Earlier generation | `legacy/1-Projects/comet swarm modular`, package `free-swarm` 1.0.0. |

The v2 catalogue defines fourteen enabled remote profiles: two each for Cerebras, Mistral, Cohere,
Groq, Gemini, OpenRouter and Hugging Face. Ollama is opt-in; the paid OpenAI profile is disabled by
default. The source has a SQLite usage/cooldown ledger, persistent queue, failover, parallel standalone
fanout/debate engines and local summarization support. The old dispatcher adapter's own fanout loops
over profiles **sequentially**. Profile count does not establish concurrent worker count.
The catalogue has two predefined credential slots per provider. `policy.json` only patches existing
IDs; unknown IDs are ignored (`config.py:204-220`). More providers/accounts can be added in source,
but arbitrary account onboarding is not yet a configuration-only registry.

The backup's `swarm v2/secrets.env` contains fourteen nonempty, distinct credential strings, plus
other disabled/provider/webhook entries. They are plaintext on the backup. No values, credential
digests or account IDs were written to this report or copied into the test snapshot. Neither old
OpenRouter credential matches either current encrypted OpenRouter secret. Credential presence and
uniqueness do not establish separate project/organization quotas or free billing status.

Current integration checks found no installed `orch` distribution, no `orch`/`dispatch`/`cc-fleet`
commands, no swarm route in the shared launcher/MCP/native routing, and no matching current
configuration references. The earlier adapter is real, but was not carried into the active setup.
The already working OmniRoute helper remains the current narrow free text route.

## Actual checks

A credential-free snapshot of 145 Python source/test files was copied under
`~/.aos/research/swarm-recovery-20261021`. Every copied source hash was checked against the backup.
All executable testing used that snapshot, isolated state and a fresh home-folder environment.
Socket connections and external process creation were blocked for source tests. No service was
started and no backup startup script was run.

- **57 unchanged swarm tests passed**, with zero blocked network/process attempts.
- **17 unchanged dispatcher swarm tests passed**, with zero blocked attempts.
- **Eight new regression test methods failed with fourteen failed assertions and zero errors**,
  demonstrating the defects below. They remain red; no implementation fix is claimed.
- An initial guard wrapper replaced a class with a function and prevented Windows asyncio test
  collection. A class-preserving guard corrected the harness. A combined run then had 73 passes
  and one unavailable-package fixture failure because the real swarm was deliberately importable.
  Running the suites in their intended separate environments passed all 74 without editing tests.
  Both earlier attempts are retained.
- Metadata/account endpoints were checked for all fourteen credentials, with anonymous controls,
  no model generation and no automatic retries. Follow-ups clarified Cohere's anonymous response
  and compared current versus recovered OpenRouter identities in memory only.

| Provider slots | Metadata result | What remains unknown |
| --- | --- | --- |
| Mistral, both | Authenticated catalog access; archived model still listed. | Current free mode, included remaining usage and organization independence. |
| Gemini, both | Authenticated model listing; archived model absent from the current catalog. | Current project billing/free tier, independent project quotas and a current eligible model. |
| Cohere, both | Key checker returned `valid=true`; anonymous control returned `valid=false`. Organization IDs differed in memory. | Trial versus production eligibility and current remaining trial allowance. |
| Hugging Face, both | Authenticated identity lookup; two different users. | No included free-user Inference Providers credit under current documentation; inference was not called. |
| OpenRouter, primary archived key | Account endpoint returned 401. | Stale/rejected archived credential; current working account remains available. |
| OpenRouter, second archived key | Account endpoint passed, creator differed from current account, and daily free allowance reported 50. | Immediate counter enforcement/freshness is not inferred from its display. |
| Cerebras and Groq, both each | Metadata returned 403, including anonymous controls. | Access cause and credential validity; they are **not** labelled invalid solely from these responses. |

Overall: nine archived credentials were authenticated by metadata checks; one returned 401;
four remain unverified behind 403 responses. Metadata success is not a free-generation pass.

The second OpenRouter account then completed **one actual synthetic task** using a current explicit
free route whose live prices were all zero. The request disabled fallback, set zero maximum prices,
had a bounded response/token budget and made no retry. Depot, total and unknown date were correct;
the candidate was complete and remained unaccepted. The call took 2.974 seconds and reported
316 tokens. Reported paid daily usage remained zero. The immediately polled daily counter stayed
at zero of fifty before/after; no consumed-counter delta or guaranteed future capacity is invented.
No archived credential was added to the current gateway or secret store.

## Reproduced integration defects

Source anchors below are relative to the recovered v2 package unless labelled dispatcher.

| Defect | Executed evidence / source |
| --- | --- |
| Hard exclusions are only rankings | With a profile already hard-capped, all four selectors still returned it. Permanent cooldown did the same. `swarm/router.py:60-111`. |
| No final call-boundary admission | `call_one` still invoked the fake provider after its hard cap was consumed. `swarm/engines/common.py:30-43`. |
| Retries undercount wire attempts | Three fake rate-limit attempts produced one usage row. SDK retries are also not explicitly disabled. `common.py:33-43`, `providers/openai_compat.py:43`. |
| No atomic quota reservation | Two simultaneous fake calls consumed a one-call hard limit twice. SQLite WAL alone does not reserve remaining capacity. |
| No account/project grouping or credential deduplication | Two profiles containing the same synthetic credential received separate usage counts; the second remained uncapped after the first was exhausted. `ledger.py:24-32,102-120`. |
| Adapter/pool payload mismatch | The real adapter-to-common path emitted a system message with null content. Dispatcher `workers/swarm_pool.py:202`; swarm `common.py:30-31`. |
| Free label does not enforce free requests | The OpenRouter adapter supplied no price/fallback preference despite `prefer_free` metadata. The probe captured request construction through a fake client. `providers/openai_compat.py:37-57`. |

Additional source findings, not separately live-exploited: Gemini puts the key in a query URL and
propagates raw exceptions; failed webhook logging includes a URL prefix; HTTP authentication is
optional when the token is unset and there is no explicit request-body bound. Local-day resets and
historical request-count estimates do not model provider token/audio/organization quotas. These
are reasons to restore a narrow worker core with current safeguards, rather than start the old
daemon or revive its whole browser/control plane.

## Current quota and free-tier reality

Multiple providers and authorized accounts with independently allocated quotas can add capacity.
The recovered OpenRouter user is a concrete additional working route; one successful request does
not establish additive aggregate throughput. The pool must track actual quota owners, not merely
key strings: [Gemini limits are project-scoped](https://ai.google.dev/gemini-api/docs/rate-limits),
[Groq limits have an organization ceiling](https://console.groq.com/docs/rate-limits), and
[Mistral documents organization API limits and included usage](https://docs.mistral.ai/admin/billing-usage/usage-limits).
Additional keys within one shared bucket do not establish more capacity.

Historical free assumptions require revalidation:

- [Cerebras currently documents a time/credit-bounded trial](https://inference-docs.cerebras.ai/support/rate-limits),
  not an automatically renewing permanent free tier. No payment method or credit purchase was added.
- [Hugging Face's opened current pricing page](https://huggingface.co/docs/inference-providers/main/pricing)
  lists no included credits for free users. A search snippet still advertised an older allowance;
  the opened page takes precedence. Custom provider keys use that provider's billing.
- [Cohere evaluation and production keys differ](https://docs.cohere.com/v1/docs/rate-limits);
  trial use is limited. An authenticated key is not proof of trial eligibility.
- [Gemini billing follows its project](https://ai.google.dev/gemini-api/docs/billing);
  the same model call can be free in one project and paid in another. No billing setting was changed.
- [OpenRouter's limits page](https://openrouter.ai/docs/api_reference/limits) explicitly warns that
  adding accounts/keys does not raise its global rate limits. Its gateway is not a second allowance.
  The recovered account is a separate authenticated identity with a reported allowance, not proof
  that global request limits increase or that its displayed fifty requests can simply be added to
  the current account's allowance.

## Other useful surfaces and the right boundary

These are scoped recommendations from current capabilities, not additional installed features.

| Surface | Useful extension | Required acceptance / limit |
| --- | --- | --- |
| Coding and text workers | Bounded helper drafts, test drafts, issue triage, extraction and document summaries across admitted providers/accounts. | Host checks outputs; record provider/account provenance, actual attempts and cancellation. Prior live utility evidence remains in the earlier evaluation. |
| Retrieval and vault/media indexing | Public-data embeddings, passage ranking and query expansion. [Gemini's standard embedding tier includes free multimodal inputs](https://ai.google.dev/gemini-api/docs/pricing); [Cohere exposes Embed/Rerank](https://docs.cohere.com/v1/docs/rate-limits). | Validate account tier first. Keep one compatible embedding model/space per index; changing provider can require reindexing. Batch and cache before adding accounts. Private local-model work stays local. |
| Transcription and subtitle work | Optional queued cloud transcription of authorized audio when local latency is unacceptable. [Groq documents audio endpoints and timestamps](https://console.groq.com/docs/speech-to-text). | Separate audio-second quota buckets, file bounds, language/timestamp checks and explicit cloud data permission. Keep existing local Whisper route. |
| OCR and visual checking | A bounded vision candidate for scanned pages, diagrams or selected video frames. [Gemini pricing describes multimodal eligible tiers](https://ai.google.dev/gemini-api/docs/pricing); [Groq vision documents image input](https://console.groq.com/docs/vision). | Model/account-specific free admission and factual spot checks. A chat key does not prove OCR quality. This does not enable AnyDoc's disabled hosted OCR path. |
| Research preparation | Parallel source extraction, grounded summaries and claim/source tables from already retrieved pages. | Use the existing web tools for retrieval. Text inference capacity alone does not grant live search or justify invented citations. |
| Native subscription clients and media generation | Keep existing native clients and local rendering/generation. | Subscription logins are not generic API keys. No verified free video/music generation pool was established; avoid routing these through assumed free chat profiles. |

The common improvement is a capability-aware queue over admitted provider/account resources, with
separate units for requests, tokens, audio seconds and monthly credits. Distribute independent
tasks; do not spend many model calls on generic councils by default. Cache completed work, use
bounded packets, honor retry/reset headers, and preserve the existing vendor actor limits and
single-writer contract. More account allowance and more simultaneous workers are separate controls.

## Concrete recovery sequence

1. Preserve the known source hashes and add the eight already failing probes to a maintained
   worker-core test suite. Repair hard exclusion, final admission, per-attempt accounting,
   atomic quota reservations, shared bucket identity, payload shape and free-price enforcement.
2. Restore only that worker core into a home-folder installation. Generalize the fixed catalogue
   into validated provider/account records if more than its predefined slots are needed. Replace plaintext loading with
   Windows-encrypted secret references and redact all error paths. Leave backup copies untouched.
   The existing adapter is a reference; no need to revive Nexus or the earlier control plane.
3. Start with the working current OpenRouter account and the independently tested recovered account.
   Add Gemini/Mistral/Cohere only after current free/trial and billing-disabled eligibility is checked;
   refresh model catalogs. Leave Cerebras/Hugging Face out of assumed recurring-free capacity and
   resolve Groq access before calling generation. Do not ask the operator to rotate valid keys just
   because an endpoint/access test is inconclusive.
4. Expose the same packet/candidate operation to a single agent and orchestration, with managed
   identity, dependency acceptance, explicit queue/concurrency limits, receipts and cancellation.
   The current native vendor enum alone is not a complete integration.
5. Compare real workflows against the existing route: correctness, total lead effort, elapsed time,
   retry count and actual paid usage. Then extend one eligible non-text surface at a time.

No production reactivation is claimed. The operator requested discovery and an assessment of reuse;
the checks above establish what exists, what still works and the concrete repair boundary.
No repository name/URL is needed now. Account eligibility/access is the remaining activation
information gap, alongside the reproduced engineering defects.

Detailed evidence and hashes are in the accompanying
[sanitized recovery receipt](2026-10-21-swarm-recovery.json). The full setup suite was not rerun:
only evidence documents changed in agentic-os. Source tests, expected regressions, metadata checks
and the additional zero-price completion were run separately and retain all non-green attempts.
