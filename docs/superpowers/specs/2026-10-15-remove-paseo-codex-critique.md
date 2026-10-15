# Codex critique of the Paseo removal spec (2026-10-15)

Reviewer: Codex (`codex exec --profile review`, model passed per call), read-only, 74,894 tokens, exit 0, no usage-limit
error. Subject: `2026-10-15-remove-paseo-design.md` as committed in 8d33b38. Text below is Codex's final answer,
verbatim; dispositions are in the spec's "Codex review" section.

## Findings

1. **Blocker — spec, Decisions 1 / Stage 3:** The recommended plan leaves eight film projects’ voice tools pointing at the package Stage 3 uninstalls. Reopening any of those films to regenerate voice will fail at `require(...)`; repoint all nine projects and the audition tool before uninstalling.

2. **Important — tests/aos.Tests.ps1:2640 and tests/aos.Tests.ps1:3282:** The deletion list omits `Logon task state`, which calls the helper being removed, and a status test that mocks the removed Paseo lookup. Stage 2 can therefore leave `aos test` failing. Within `Places registration`, preserve the local persistence and brain-sync cases at lines 3123 and 3151 when removing Paseo cases.

3. **Important — spec, Stage 1:** Stopping the daemon before unregistering its task leaves a five-minute restart window. If the task fires between those commands, the daemon can remain live throughout the soak; unregister first, then stop and verify.

4. **Important — spec, Stage 1 rollback:** `aos install phone` reinstalls the daemon but does not restore the 18 moved skill directories; Install-AosPhone (aos.psm1:1176) contains no skill restoration. The rollback needs an explicit restore procedure and a check that `aos sync` has not replaced those paths.

5. **Important — spec, Stage 3:** `npm uninstall -g @getpaseo/cli` does not specify the intended prefix, although installation explicitly does at aos.psm1:439 to withstand prefix overrides. With `NPM_CONFIG_PREFIX` set elsewhere, uninstall can leave the live `paseo` command in `~/.npm-global`.

6. **Important — spec, Tests 3:** `aos place ls` calls `Show-AosPlaces`, which already has no Paseo call; the remaining lookup is in `aos status` at aos.psm1:2304. That proposed assertion can pass while status still invokes Paseo.

7. **Minor — spec, Stage 2 / Tests 1:** The named README edits omit its Paseo prose at lines 98–108 and 119–121; the media-tools note also retains a `~/.paseo` reference at line 72. The tombstone check *can* catch these tracked occurrences, but it cannot establish machine-wide absence: it excludes untracked skills and retained worktrees. `git ls-files` also continues to list deleted files until the index is updated.

Scoped hook, MCP, and Pi searches: **nothing found** beyond the Pi comment already named in the spec.

## Verified claims

- **(a) Confirmed.** `main...phone-coordinator-live` is 0 behind and 27 ahead. Only `90f0614` and `f0895d1` touch paths outside `paseo-plugin/`; their file lists contain no plugin paths.
- **(b) Wrong as worded.** The helpers serve only the Paseo feature, but `Start-AosLogonTask` is called by `Start-AosPaseoDaemon` at aos.psm1:1237, and `ConvertTo-AosLogonTaskState` is called by `Get-AosLogonTaskState` at line 1252.
- **(c) Confirmed.** The exact require path occurs in nine film `make-voice.cjs` files and the template (templates/video/tools/make-voice.cjs:7); `cant-escape-ai/tools/audition.cjs` is an additional caller.

## Could not verify

Actual scheduled-task state, PATH resolution, skill-directory link types, and runtime behavior of the copied native packages were outside the permitted file and read-only Git checks. No tests or mutating commands were run.
