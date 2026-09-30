# Phone coordination v1 implementation plan

Spec: docs/superpowers/specs/2026-09-30-phone-orchestration-design.md (user approved 2026-09-30).

## Execution and constraints

Use the existing nar-tools Paseo plugin, pinned to the installed 0.10.1 SDK. Build on branch phone-coordinator in an isolated worktree outside OneDrive. Keep the local 16K agent's tool catalog small. Reuse the installed native provider sessions, permission handling and quota service. Do not edit credentials or replace vendor agent loops. No model names in source; catalogs supply IDs. No automatic replay after partial execution. Finish with a fresh-context review and live local acceptance; cloud and phone acceptance remain explicitly pending until run.

The requested full harness spans several independently testable systems. This plan delivers the persistent conversation and controls first. Places automation, computer-use bridging and the existing video/Inbox plans remain separate builds with their requirements retained in the approved spec.

## Task 1: routing and durable session state

Create server/coordinator/policy.ts and store.ts, with matching Vitest tests. A route encodes auto/local/pinned provider plus live model ID. Normalize native usage windows without estimating unavailable quota. Treat scoped exhaustion only as applicable to that provider/model. Explicit model selections never silently change. State schema version 1 stores session mappings, transcript/handoff, last turn status and pending message IDs under ~/.aos/coordinator. Atomic replace on save; process-local per-session serialization; reject incompatible schema and prevent state-path traversal. Test red before implementation: pinned quota failure, auto fallback, unknown quota, per-model scope, interrupted/unfinished turn, state corruption and duplicate client message IDs.

## Task 2: forwarding provider and native adapter

Create server/coordinator/provider.ts and native.ts. Register coordinator as a plugin provider using public ProviderConnection protocol. Obtain PaseoApi through plugin lifecycle/handler context; expose catalog Auto, Local and discovered provider/model choices with relevant reasoning settings. Native API creates parented underlying sessions in the selected directory, observes snapshots/timelines before sending, returns permission requests unchanged, translates turn and timeline events, and retains session IDs. Use fixed argv paseo stop for cancellation (no phone-supplied shell text). Do not access SDK internal transport or vendor token files. Model/provider changes are between turns and resume a compatible prior native session or create a new one with explicit handoff. Refuse incompatible attachments instead of dropping them. Restore durable mapping after reload and reconcile unfinished turns; never auto-send an unfinished prompt. Test with fake native agents: response, failed/canceled turn, permission roundtrip, steering, reload, quota exhaustion with no side effect, partial execution failure, and duplicate delivery.

## Task 3: phone controls and host operations

Add shared/coordinator-rpc.ts, server/coordinator/controls.ts and client/coordinator.tsx. Controls expose health, quota with observation age, coordinator creation/opening, recorded task listing, selected project, retry and stop for recorded IDs. Client selects registered projects and model routes from host catalogs, opens the coordinator via supported client navigation, and exposes Local independently of cloud usage. Operations use strict inputs and fixed host commands; service recovery invokes a named task and waits for readiness. Honor explicit Stop; no automatic watchdog installed in this task. UI gives specific unavailable/service-loading/permission/quota states. Test validation, unknown agent IDs, cancellation failures and unhealthy Ollama. Typecheck React Native panel.

## Task 4: integration and validation

Wire provider/RPC registration into index.server.ts and coordinator panel into existing panel. Keep old nar behavior working. Add a focused README with upgrade boundary and recovery behavior. Run all plugin Vitest tests and tsc. Review complete branch against spec; record findings and fixes. Install/reload from worktree only after required review, with old plugin path backed up for restoration. Live acceptance: catalog discovery, create coordinator in a scratch workspace, Local reply, local file read, permission deny/allow, stop, model change and plugin reload preserving conversation. Simulate quota in tests; no unnecessary live cloud inference. Phone acceptance must be confirmed by user.

## Upgrade and review gates

Public plugin/client contracts are the compatibility boundary. Tests compile against exact SDK version; upgrading means rerun protocol/permission/cancel/recovery cases before reloading live plugin. Do not advertise capability until verified in actual agent environment. Future computer-use bridge must prove screenshot/input/cancellation from Paseo; desktop-only skills are not assumed portable. Service sign-in automation and global config edits belong to agentic-os, require aos test in both shells and cross-vendor review before application.

Before substantial implementation, request independent Claude critique of this plan; report failed critique honestly. Before live registration/global configuration, obtain cross-vendor review of those changes. A same-vendor review is additional evidence, not the required independent review.
