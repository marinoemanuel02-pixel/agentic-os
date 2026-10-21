# Free API workers

Both native agents can use `python tools/stack.py swarm ...` from this checkout.
It serves bounded candidates through the same queue for a single task or a workflow.
The native Claude/Codex actor limits and checkout ownership rules still apply to their
own workers. API workers get no tools, filesystem access or recursive delegation.

The [implementation report](research/2026-10-21-swarm-integration.md) records the actual
live checks, rejected outputs and conditional providers. The original archived framework
is preserved; this is a maintained, smaller implementation of its worker-core design.

## Choose useful work

Use this pool when a task has small supplied context and a cheap, objective host check:
fact extraction, translation drafts, proposed tests, small code proposals, source/claim
tables, embeddings, reranking, selected-image reading or short authorized audio.
Do trivial calculations inline. Keep consequential decisions, repository edits, live
retrieval and final verification with the lead. A successful response is a candidate.

Default routing tries admitted accounts by priority, excludes cooldowns and hard ceilings,
and permits at most two separately admitted failover attempts. `max_attempts: 1` disables
failover for that task. Explicit `account` pins a route. Four active API tasks, two per
provider and one per shared account bucket are current local ceilings; a gateway has one
worker. These are conservative local controls, not measured provider entitlements.
An account that is occupied waits in the queue. A dispatched provider failure remains
failed with an attempt receipt; use a new task ID for a deliberate retry after diagnosis.

## Direct task and host verification

Create a small JSON packet, with a stable unique task ID:

```json
{
  "id": "depot-facts-01",
  "capability": "text",
  "cloud_allowed": true,
  "prompt": "Return JSON with depot, total and release_date. Source: depot Verona; 11 plus 31 crates; release date unknown, preserve it as null.",
  "max_tokens": 512,
  "max_attempts": 2
}
```

```powershell
python tools/stack.py swarm accounts
python tools/stack.py swarm task --packet packet.json --output candidate.json
python tools/stack.py swarm status depot-facts-01
python tools/stack.py swarm verify depot-facts-01 --argv '["python","verify_candidate.py","{candidate}"]'
```

`verify_candidate.py` is a lead-authored check of the actual requested facts/shape, using
its argument as a JSON candidate file. It must exit zero, leave the candidate unchanged
and finish within 120 seconds. Never use a verifier supplied by the worker. Optional
`--cwd` and repeated `--artifact` record checked output files. Nonzero checks do not accept.
The candidate's own `accepted:false` remains inert source data; host acceptance is a
separate task state and receipt.

Outputs must be new files. Task IDs cannot be reused for different packets. Reusing the
same ID/input retrieves the previous candidate without another inference request. Packet
text is limited to 32 KiB; ordinary generation is bounded to 2,048 output tokens and at
most three explicitly budgeted attempts. Status omits large media and candidate content;
use `export <id> --output <new-file>` to inspect the complete result.

## Queued workflows and existing task contracts

```powershell
python tools/stack.py swarm submit --packet first.json
python tools/stack.py swarm submit --packet second.json
python tools/stack.py swarm drain --workers 4
python tools/stack.py swarm list
```

Set `"depends_on":["first-task-id"]` in the second packet. It stays queued until the first
has a real host acceptance. Then `drain` runs it. Dependency candidate/artifact hashes are
checked before dispatch and acceptance. Packets must contain the actual bounded evidence
needed for their task; a dependency reference does not itself inject prior content.

Existing `aos coord task` contracts are supported directly:

```powershell
python tools/stack.py swarm contract task-id --repo . --cloud-allowed --owner-session your-existing-claim-session
```

Register the contract through the existing coordination commands first. The bridge checks
prerequisites before credentials or inference, generates the existing bounded context
packet, and starts a distinct API run. The registered host verifier receives the candidate
path in `AOS_SWARM_CANDIDATE`; it must verify and publish the contract's declared artifacts
under the host's existing checkout claim. Completion reuses host receipts and artifact
hashes, so later native or API contract tasks can consume the result. Model output is never
interpreted as a coordination command. Contract `budget.timeout_minutes` bounds API work,
up to the pool's five-minute maximum; `max_turns` does not become an API request allowance.

## Capability packets

All require `id`, `capability` and `cloud_allowed:true`. Media files are snapshotted before
queueing; remote requests contain bytes, never a local path or arbitrary image URL.

| Capability | Additional fields | Checks and limits |
|---|---|---|
| `embed` | `account`, `texts`, `input_type` (`search_document` or `search_query`) | One account/model space, 1..32 texts; finite equal-sized vectors. No cross-model failover. Result identifies provider/model/dimension. Reindex deliberately when the space changes. |
| `rerank` | `query`, `documents` | 1..32 documents; unique in-range indices and finite scores. Result indices refer to the supplied document order. |
| `vision` | `prompt`, `image_file` | PNG/JPEG, at most 2 MiB. Check the factual output against the source. Inline `image_base64` plus `mime_type` is also supported. |
| `transcribe` | `audio_file`, optional `language` | PCM16 WAV, at most 120 seconds/10 MiB; duration measured locally, audio-second reservation, nonempty transcript and bounded ordered timestamps. Inline `audio_base64` is supported. Check words and timings; valid structure alone does not prove accuracy. |
| `research` | `prompt`, `sources:[{"id":"source-1","url":"https://example.com/page","text":"supplied retrieved text"}]` | 1..16 sources. Requires claim/source/quote JSON; unknown sources and invented quotes are rejected. The lead checks whether each quote supports its claim. No retrieval or live search is inferred. |

Local Whisper, local OCR and existing private/offline routes remain available. Cloud
permission applies to the supplied packet only. Do not include secrets or unrelated private
material. This pool does not add a generic paid media generation route.

## Add accounts and maintain eligibility

State is in `~/.aos/swarm`; `accounts.json` contains provider/account/model records and
secret **names**, never keys. Keys live in the existing Windows `aos secret` store.
The supported adapters are OpenRouter, OmniRoute, Gemini, Mistral, Cohere and Groq.
Groq remains conditional on working access and verified free billing.

1. Store the new key using `aos secret set <new-secret-name>` in its local secure prompt.
2. Prepare one account record, using an existing same-provider record as a schema example.
   Change its `id` and `secret` reference. Keep its `quota_group` shared until independent
   project/organization/account allowance is established. Supply current explicit model
   routes and conservative request/token limits; transcription also needs audio seconds.
3. Run `python tools/stack.py swarm-accounts --add-account <record.json>`. For a free/evaluation
   provider, also supply `--free-confirmed-paid-disabled` after checking its billing state.
   Registration validates the schema and metadata, not generation quality. Run a bounded
   task and host check before relying on that account.

An arbitrary number of records (up to 128) can be added without changing the old fixed
two-slot catalogue. Extra keys do not imply extra allowance. Gemini project limits, Groq
organization limits and OpenRouter global restrictions still apply; see the primary-source
links in the recovery report. Matching credentials also share a durable strictest ceiling,
so changing a secret's name cannot create capacity. OpenRouter and its OmniRoute alias
share the current account's bucket. OmniRoute itself supplies routing, not a new quota grant.
OpenRouter and OmniRoute also share conservative local ceilings of ten attempts per rolling
minute and thirty per rolling day across all accounts; rotation cannot raise those ceilings.

OpenRouter routes require a current zero-price catalog entry and zero-price/no-fallback
request guards. Other free/evaluation attestations expire after seven days in the recovered
setup. To renew after checking billing:

```powershell
python tools/stack.py swarm-accounts --renew-free account-id --free-confirmed-paid-disabled
```

`--refresh-account account-id` explicitly refreshes a supported provider's model routes.
It backs up the registry and preserves quota history. A changed Gemini route must pass
a token-count readiness probe before its old rejection cooldown can be cleared. Changes
are recorded. Account writes are exclusive; a stale lock requires inspection, not automatic
takeover. No background account creation, key harvesting or paid fallback is enabled.

## Cancellation, failures and recovery

Use `swarm cancel <task-id>` for pool tasks or `aos coord cancel <run-id>` for a contract
run. Cancellation prevents another request and discards a late candidate. An in-flight
HTTP operation must return within its bounded deadline before ownership is released;
local cancellation does not prove remote inference stopped or restore consumed quota.
`swarm attempts` shows attempted accounts, charged units and outcomes without credentials.
Metadata requests are not counted as inference attempts. No provider error body is logged.

Interrupted leases stay held. Once their owning process has stopped, use
`swarm reconcile <run-id> --confirmed-stopped`. It independently checks the owner PID,
refuses live/unknown ownership and preserves every charged attempt. Registered native task
state may still require inspection. An unconfirmed verifier process is kept as
`needs-inspection`; its task is not released as successful or failed completion.

The existing `omniroute-task` plain-text command now uses this same ledger when the pool
registry exists. Its readiness-only `--check` remains available. Cold gateway startup has
material overhead; direct free-provider routes are preferred for short bounded work.
