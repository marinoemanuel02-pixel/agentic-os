# Phone orchestration: one conversation, three providers

Date: 2026-09-30. Status: user approved the design and implementation in this session. The phone coordinator increment is installed; subsequent tool, Places and computer-use systems remain work to do.

## User intent

The user wants one conversation in Paseo that coordinates Claude, Codex and the local model on this Windows PC. The local model must remain accessible when subscription quota is exhausted. The user can select models, access additional repositories and tools on the PC, request computer use, and launch subagents when requested or useful. Claude Pro and ChatGPT Plus are the cloud execution routes; this design introduces no paid API route.

Success means the phone can submit, steer, inspect and stop work without requiring a visit to the desktop to choose another provider or restart a missing service. The PC must be awake, online and signed in; UI automation additionally requires an available interactive desktop.

## Measured starting point

- Paseo 0.10.1 is installed. Its daemon and relay were restored during this session. Ollama was subsequently opened by the user; the local agent model was observed running with a 16K context and entirely on the GPU.
- The registered projects now include agentic-os, nar-tools, tala, duda15, meta-cognizione and Inbox, as well as the old agent-gate test project. This was manual registration; the approved Places design is not implemented.
- Paseo detects Claude, Codex and Pi. Detection and a model catalog do not prove available quota or access to a specific model. The only registered agent at the initial audit was the Pi gate session.
- The local model's explanation of the setup included invented details. Routing decisions, health, quota and operation status must come from code and provider evidence rather than a model's description of itself.
- The existing aos plugin provides status and nar feedback. It is not a coordinator.
- Native Paseo orchestration is documented in the local reference clone, including parented agents, model settings, workspaces, cancellation and completion notifications. Installed-version checks are required before using any reference-clone capability.
- The installed plugin SDK exposes registerProvider and a provider protocol with persistence, steering, configuration and permissions. The newer reference clone also describes usage-source registration, which is absent from the installed plugin contract; do not depend on it.
- Installed Paseo exposes native provider usage reporting with a five-minute cache. Its high-level plugin PaseoApi can create/observe sessions, send prompts and respond to permissions, but has no cancel or model-change operation. Native CLI stop and low-level daemon controls exist; a forwarding provider needs an explicit tested bridge for these operations.

## Approaches considered

1. A native Codex or Claude lead with a separate local conversation. This is the smallest usable first milestone and preserves native subagent visibility. It does not satisfy a single persistent conversation across provider changes.
2. A thin Paseo plugin provider forwarding to native sessions, with a persistent conversation and deterministic routing state. Recommended target: it preserves vendor agent loops and adds the missing identity, quota and handoff behavior.
3. A separate agent framework with direct model calls and a replacement tool loop. Rejected for this increment: it duplicates the installed vendor agents, their history, tools, permissions and subscription integrations.

Do not fork Paseo to start this work. Use its plugin/provider and client APIs. If the installed API cannot forward permissions, steering or cancellation correctly, report that specific incompatibility before treating the persistent conversation as deliverable.

## First sub-project: phone coordination v1

This spec covers dependable services, native coordination and the persistent routing conversation. Existing Places work is a prerequisite for automatic folder discovery. Tool expansion and Windows computer control are subsequent independently tested sub-projects; their requirements are preserved below.

### 1. Service availability and recovery

- Start Paseo and Ollama outside the desktop apps' MSIX environment at sign-in. Reuse existing installations and the existing Paseo task. Back up configuration before changing it.
- Check the daemon, relay and Ollama endpoint independently. The UI must distinguish PC unreachable, Paseo unavailable, Ollama unavailable, model missing/loading, and provider quota exhausted.
- A stopped local runtime can be restarted through a fixed host operation from the phone. Verify readiness before dispatch. A watchdog uses bounded backoff and reports repeated failure; it must honor an explicit user stop instead of restarting forever.
- Always accessible does not mean permanently resident on the GPU. Idle models can unload. Long GPU-exclusive work must be visible, cancellable and bounded; local chat requests can interrupt or defer such work according to the user's choice. A render queue must not silently starve local access.

### 2. One conversation and honest handoffs

- Register a plugin provider for the coordinator conversation. The displayed conversation has one durable ID, an append-only user-visible transcript and references to underlying Paseo sessions.
- Run execution in native Claude, Codex or Pi sessions. Preserve their instructions, project context, tools, permissions and vendor session IDs. No copied login tokens or custom inference calls.
- Forward responses and activity with provider/model attribution. Preserve actual terminal states: completed, failed, interrupted, waiting for permission and quota exhausted are different outcomes.
- A provider change occurs at a turn boundary. An active turn must finish or be explicitly interrupted first. Retain the previous provider session for reuse.
- Model changes also occur at a turn boundary. If the installed plugin API cannot configure an underlying session, create a new native session with the chosen model and an explicit handoff. Cancellation uses a fixed-argument native CLI control adapter, scoped to recorded child IDs, until a supported low-level plugin control API is verified. Never accept shell text from the phone as a control command.
- Handoff context includes the user's objective, constraints, selected places, latest verified results, pending tasks and unresolved permissions. Keep source history available and label summaries as summaries; a different provider cannot inherit the original vendor's hidden state.
- Never replay a partly executed task automatically. Record tool/task identifiers and verify the working tree and resulting files before another provider continues. File changes already made survive a quota failure.
- If permission forwarding cannot preserve the original request and response, expose the underlying native agent's permission UI with a clear link and waiting status. Never translate a generic message into an approval.

### 3. Quota and model selection

- Provide Auto, Local, Codex and Claude choices, with per-provider model and reasoning settings fetched from the host catalog. Validate selections at dispatch; unsupported selections report an error rather than silently choosing a different model.
- Default cloud preference is Codex, then Claude, then Local, reflecting this session's need to continue while Claude is exhausted. The user can change the order and pin a provider/model.
- Auto uses confirmed quota exhaustion, provider failures and fresh usage reports to route. Unknown quota remains unknown. Installation, token activity estimates and an old reset date are not available-quota evidence.
- Read native Paseo provider usage where supported by the installed client. Codex app-server also documents account/rateLimits/read and account/rateLimits/updated. Keep the multi-bucket view, used percentages, reset times, observation timestamp and source when available.
- Installed public Paseo usage reporting can return a five-minute cached observation. Show that age; do not claim a forced refresh. A runtime quota error takes precedence over an older usage snapshot. Direct Codex rate-limit reads are an optional adapter only if native reports cannot support the required routing behavior.
- Recheck a blocked provider at its reported reset or after explicit Retry. Do not poll an exhausted provider with repeated paid turns. Non-quota failures must not be classified as quota exhaustion.
- Explicit provider/model selection remains pinned unless the user also enabled fallback. Auto announces each fallback in the transcript. Complex implementation or review stops with a saved handoff when only the small local model remains; bounded local tasks and local chat stay usable.
- Preserve subscription authentication through the installed agents. No automatic paid API fallback or credit consumption.

### 4. Native orchestration and subagents

- Use Paseo's parented agent/workspace controls. Show each task's provider, model, working directory, parent, purpose, state and latest result in a compact phone panel; open the native conversation for details.
- The coordinator can create useful independent tasks within the user's authorized objective, and honor explicit requests for subagents. Give each child a bounded task and enough source context. Workers cannot recursively expand the task tree by default.
- At most two concurrent agents per cloud vendor, counting the coordinator and native nested workers. A local worker defaults to one active inference stream on this GPU. Queue additional work and show it.
- Give concurrent writers separate worktrees or non-overlapping files. Read-only research may share a checkout. The lead verifies diffs and checks before reporting completion.
- Stop one task and Stop all must reach running child work, including provider-native descendants when exposed. Show partial failures in cancellation. Closing the phone app must not imply cancellation.
- Independent review means the other vendor. If unavailable, record review pending; a local or same-vendor reviewer does not satisfy the existing cross-vendor rule.

### 5. Places and existing tools

- Implement the already approved Places design instead of a second registry. Resolve portable paths at runtime; the phone chooses a place ID, and the host verifies the folder.
- Each task has an explicit execution directory and a list of additional authorized places. Never run against an unrelated default folder merely because a requested folder is missing.
- The coordinator sees a small capability summary. Load or delegate detailed tool catalogs only when needed, especially for the 16K local model. Reuse native shells, installed CLI tools, skills and provider MCP integrations.
- Separate tool detection, connectivity, authorization and tested availability. Desktop-only plugins must not be advertised as available to a Paseo CLI agent without a verified bridge.

## Later sub-projects retained in the roadmap

1. Shared tools: finish the existing tool-gateway work, add a capability inventory and task-specific discovery, and verify each tool from all intended agent environments. Preserve existing approvals and secrets storage.
2. Computer use: evaluate a supported Windows/browser automation backend callable from the actual Paseo agent environment. The Codex desktop computer-use skill is session/runtime-specific and is not evidence of CLI availability. Add a host adapter only after proving capture, input, permissions, cancellation and visible phone feedback. One UI worker owns the interactive desktop at a time. No unattended claim for a locked desktop.
3. Inbox and video: complete the previously approved artifacts through their own plans. Coordinate their workloads through the same task registry; video rendering must respect local availability.

## Acceptance and failure tests

Before code changes, write tests that demonstrate the missing behavior. Use fake providers for exhaustion and disconnections so acceptance does not burn subscription quota.

1. Start after a real Windows sign-in. Reach Paseo and send a local message from the phone without opening Ollama manually.
2. Local-only mode succeeds when both cloud providers are unavailable. A missing local runtime reports its cause, recovers through the phone operation, and succeeds on retry.
3. Pin a provider/model and verify the actual runtime choice. Test model denied/removed and unknown quota without invented availability.
4. In Auto, simulate cloud quota exhaustion and continue a bounded task through the same conversation. Assert provider attribution, retained history and no repeated side effect. Complex tasks remain saved and pending.
5. From the same conversation, select another registered repository, launch a read-only child, steer it, receive its completion and inspect its result on the phone.
6. Launch two independent tasks and verify concurrency limits, worktree separation, permission handling and Stop all. A failed child never becomes a successful result.
7. Restart the daemon mid-task. Restore conversation/session references; reconcile unfinished work and permissions without blindly replaying it.
8. Reapply configuration and registration; the second run changes nothing. Run aos checks under both PowerShell versions and plugin unit/type checks for changed components.

## Evidence and validation gates

- Local reference sources: docs/superpowers/research/2026-09-29-paseo.md; the Paseo reference clone's public-docs/orchestration.md and public-docs/mcp.md; installed @getpaseo/plugin/dist/server/contracts.d.ts and provider.d.ts. Resolve their locations at runtime; never embed this PC's absolute paths in configuration.
- Official Codex rate-limit reference: https://learn.chatgpt.com/docs/app-server (account/rateLimits/read, account/rateLimits/updated and the multi-bucket response).
- Before implementation planning, review this written spec with the user. Then write a plan for phone coordination v1, with installed-version capability tests before the forwarding provider implementation.
- The existing global contract requires the other vendor to critique plans for work exceeding about an hour. Claude is currently reported out of quota: review remains pending, not clean. Obtain that critique when available or an explicit user override before a large build.
- No feature is complete until the phone acceptance steps pass. A design document, provider installation or CLI success alone is insufficient.
