# Phone coordination v1 implementation plan

> Superseded 2026-10-15: Paseo was removed from this PC and repo (`2026-10-15-remove-paseo-design.md`). Kept as history.

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

## Critique resolutions (Claude task-muob32t5-npb50z, completed)

1. Deduplicate before every native send. Installed send accepts activeTurnBehavior at runtime despite omitted SDK typing; isolate that 0.10.1 compatibility shim, validate its daemon request, and reject steering until a protocol test proves it. Do not use default send on an active child.
2. Persist dispatching state and deterministic child/create/message IDs before any external call. Recovery refetches native history; an unknown unfinished turn becomes needs-reconciliation, never an automatic resend. Automatic fallback requires a complete refetch proving no tool calls or partial outputs; otherwise save a handoff and stop.
3. Capture the shared plugin PaseoApi in before(agent.session_open), which precedes provider open, and in RPC hooks. Catalog discovery can offer Auto/Local without API; cloud catalog refresh occurs after bootstrap. Use the config environment's PASEO_AGENT_ID for the parent, never provider sessionId. Fail with a specific error if bootstrap/parent is absent.
4. Stop uses process.execPath plus resolved @getpaseo/cli/dist/index.js, full recorded UUIDs and --json. Installed cli.js only defines commands; index.js executes them, confirmed during live acceptance. Parse reported IDs and refresh snapshots. Traverse recorded descendant relationships, never use --all/--cwd. Handle initializing/permission status explicitly and never claim cancellation from command exit alone.
5. Translate permission shapes and namespace IDs with child agent IDs. Preserve action selection and explicit one-time updated inputs needed by Pi's question gate; do not forward persistent grants without an explicitly selected persistent action. Refresh pending requests before accepting an answer. Use provider-native asking modes; never choose bypass/unattended modes automatically.
6. Quota schemas do not expose structured model scope. Route on verified unscoped session/weekly windows; scoped windows are displayed but not used to block all models. Unknown failure text remains generic failure. A failed native route gets five minutes of Auto backoff on the next explicit request, separately from quota classification. Observation time remains unknown when the native report omits it. Concurrency accounting covers harness-owned sessions, not unrelated desktop sessions.
7. Validate protocol version 1 and outgoing events, pin manifest support to the tested Paseo release, and compare runtime/catalog versions before activation. A new SDK/daemon release requires compatibility checks before widening the supported range.
8. Provider persistence holds the durable coordinator UUID; the locked state file is authoritative for dispatch mappings. Use an exclusive lock across plugin processes, release only owned locks, fail closed on unknown owner state, and retry transient Windows rename failures. No secrets stored in state.
9. Parent linkage and reload bootstrap are explicit integration tests. If they fail, do not deploy a detached or nonpersistent substitute as the coordinator.

## Installed result, 2026-09-30

nar-tools branch phone-coordinator at 9aec647 is installed through its existing checkout on phone-coordinator-live. The aos plugin reports running on Paseo 0.10.1. Model discovery exposes 25 choices including Auto and Local; no model names are baked into routing. The agentic-os project has an idle Coordinator conversation ready in Auto mode.

Final verification: npm test reports 199 passed in 14 files; npm run typecheck and git diff --check pass. Live scratch acceptance passed Local reply, file read, namespaced permission Deny/Allow, Stop while permission waits, Stop linked tasks after a reload, explicit reconciliation without replay, retained native child identity and a later Local file read. Local health and idempotent Start report the configured model ready. Offline service launch is tested with fakes; an actual cold launch was not forced.

Claude completed the plan critique and independently wrote native permission/stop tests. Its final branch review failed with its weekly limit. A fresh Codex review found integration defects that were fixed and covered by regression/live tests; it is not an independent-vendor review. No cloud execution or physical-phone acceptance was claimed.

The live dependency junction still targets the earlier nar-tools-plugin worktree. A matching stable cache was installed under ~/.aos/deps/paseo-plugin-0.10.1, but automatic approval review rejected replacing the junction without supplying a reason. Preserve that worktree until the link is moved. Backups retain the previous plugin path and checkout branch. No aos.psm1 code changed, so aos test was not rerun for documentation-only agentic-os edits.

Remaining: physical-phone acceptance, live cloud and native subagent acceptance, direct-CLI admission enforcement (currently instructions), Places automation, broader tool access, computer-use bridge, video plans, and final cross-vendor code review when quota resets. The coordinator itself guards its native sends at two per cloud vendor and one local; it does not police unrelated desktop sessions.
