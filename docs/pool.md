# Free-resource layer (`aos-pool`)

One MCP server, registered for Claude and Codex by `aos sync`, that makes the local model and the free
API pool a default worker in every run. It is a thin task-shaped front over what already exists: Ollama
(`config/local.json`) and the managed free API pool (`docs/swarm.md`). No new router, no new accounts.

## Why it exists

The swarm and the local model were callable but unused: the swarm needs a JSON packet and a
lead-written verifier per task, the local model was reachable only for scoring and sorting, and the
contract only said "consider" them. Other setups solve this either with task-shaped MCP tools (used
rarely unless a rule says so) or with hooks that silently swap the agent's model (automatic, but quality
drops unseen). This layer takes the first and adds the two missing pieces: a default-use rule in the
shared contract and checks built into every tool, so no per-task verifier is needed.

## Tools

| Tool | Route | Built-in checks |
|---|---|---|
| `pool_extract(source, fields \| schema)` | local; free API fallback when public and the local answer fails a check | JSON parses, schema subset holds, every value occurs in the source (`grounded`) |
| `pool_triage(items, labels)` | local embeddings (`bge-m3`), local model breaks near-ties; never leaves the machine | low-margin items listed |
| `pool_variants(brief, n)` | local, plus the free API pool when public | non-empty, deduplicated across routes, count |
| `pool_crosscheck(claims, sources)` | local, plus an independent free API vote when public | quote must occur in the cited source or the verdict drops to `not_found`; local/cloud disagreement is `disputed` |
| `pool_summarize(text, focus, max_words)` | local | length bound; numbers not in the source are flagged |
| `pool_feedback(id, accepted)` | ledger | per tool and route: calls, pass rate, acceptance, median time |

Every result has `id`, `routes`, `checks`, `ms` and `verdict` (`pass` when every check held, else
`review`). `pass` is not acceptance: the lead spot-checks and reports with `pool_feedback`.

## Privacy

`privacy` is `private` by default: the local model only. `public` is for material that is already public
or meant for release (published sources, a script for a public video); it lets the free API pool see the
prompt, and some free tiers may train on prompts. Never pass secrets either way.

## State and limits

- Ledger: `~/.aos/pool/ledger.jsonl` (override with `AOS_POOL_DIR`). It records tool, routes, verdict,
  time and input size, never the texts.
- Input: the complete local prompt, including schema, labels, claims and instructions, is capped at
  40,000 characters. This is a coarse bound, not a tokenizer guarantee for the 16K context. Cloud
  prompts also have a 30,000-character bound and must fit the swarm's 32 KiB UTF-8 packet limit.
  An oversized public prompt stays local; unavailable cloud admission returns a route error and
  preserves any usable local candidate.
- Private local HTTP requests bypass environment proxies and refuse redirects. Chat responses
  need string content; embeddings need one finite, nonzero vector of equal width per input.
- Empty summaries and malformed candidate lists cannot pass. Feedback accepts a real boolean
  and a known result id, preventing accidental truthiness from inflating acceptance statistics.
- The 6 GB GPU holds one model at a time: switching between the embedding model and the text model
  costs about a minute the first time (measured 65 s), then calls are fast (warm triage 0.1 s, warm
  extraction a few seconds). Models stay loaded for 30 minutes after use.
- `AOS_OLLAMA_URL` and `AOS_LOCAL_JSON` override the local endpoint and config for tests.

Batch related work and reuse checked results. On a route failure, continue with direct inspection
or an eligible route instead of repeating an unchanged call. Check `swarm accounts` before counting
API capacity: expired free-tier attestations stay ineligible until the operator supplies new evidence.

## Measured on 2026-10-26 (qwen3.5:4b, bge-m3, one run each)

Extraction of four fields from an Italian paragraph: correct, absent field returned as null, 13 s cold.
Cross-check of a true and a false claim: supported / contradicted, 4 s. Summary: flagged as over length.
Variants, public: three local and three from the free API pool, 5 s. These are single samples, not rates;
`pool_feedback` statistics are the measure going forward.
