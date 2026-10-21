# Swarm integration: both recovery passes

The operator authorized full implementation of both passes and waived external review.
Gemini, Mistral and Cohere were confirmed free/evaluation with paid usage disabled on
21 October. This is an operator attestation, not a provider billing API result.

## Design and acceptance

Maintain the small worker core in agentic-os, derived from the recovered design and
its eight reproduced defects. Preserve the original credential-free snapshot and backup;
do not revive its HTTP server, UI, services, alerts or orchestration framework.
Production state, account/model records, credentials and large inputs stay under the home
folder. A validated registry supports arbitrary accounts and capability routes, without
model IDs or installation paths in tracked configuration.

One SQLite admission transaction reserves every attempted request, estimated tokens and
audio seconds across account, credential, provider and explicitly shared quota buckets.
Hard limits and cooldowns exclude routes even when no healthy route remains. Conservative
rolling local limits supplement provider limits; they are not claims about available quota.
An interrupted reservation remains charged and active until explicitly reconciled. Retries
are bounded failover attempts with independent admission and accounting; SDK retries are absent.

Both native agents use `stack.py swarm`. A direct task and a queued workflow use the same
packet/candidate operation. Workers receive bounded supplied material and no filesystem or
tool access. Candidates remain unaccepted until a host-supplied verifier actually passes.
Dependency acceptance binds candidate and artifact hashes. Queue concurrency, task identity,
attempt receipts and cancellation are explicit. Existing native two-vendor actors are unchanged.
An optional contract bridge reuses existing registered task packets, dependency readiness and
host receipt completion, rather than pretending an API account is a native actor.

Pass two adds grounded preparation over supplied sources, single-space embedding batches,
reranking, bounded image questions/OCR and authorized audio transcription. Every route uses
the same admission, secret, timeout and receipt controls. Unknown/free-ineligible accounts
remain disabled. No new live search entitlement or media-generation entitlement is inferred.

## Execution

1. Add meaningful failing tests for the eight audit defects, registry/secret boundaries,
   multi-process admission, task acceptance/cancellation and capability payload validation.
2. Implement registry/DPAPI access, transactional admission and durable queue.
3. Implement fixed-host providers with current catalogs, zero-price OpenRouter enforcement,
   bounded responses, safe errors, and capability-specific response checks.
4. Add shared launcher, host verification, native contract bridge, and shared routing guidance.
5. Migrate required recovered keys directly to DPAPI without plaintext exports; activate current
   and recovered OpenRouter, Gemini, Mistral and Cohere routes after metadata/free admission.
   Keep Groq access failure and Cerebras/Hugging Face eligibility limitations explicit.
6. Run bounded synthetic live tasks and real dependent workflows; record latency, attempts,
   completion, correctness and reported cost. Exercise OmniRoute through the same scheduler.
7. Run complete `aos test` in both shells, relevant existing optional-tool tests, static checks,
   inspect the final diff, document actual remaining operator work, and commit the result.

## Verification boundaries

Mock wire tests establish payload and failure handling, not provider availability or quality.
Operator billing attestations expire and cannot substitute for a free-price guard where the
provider exposes one. OpenRouter global restrictions still apply across accounts. Free workers
do bounded extraction, proposals and preparation; leads own edits and consequential decisions.
