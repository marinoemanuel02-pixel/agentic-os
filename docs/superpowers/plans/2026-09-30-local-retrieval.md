# Local retrieval implementation plan

Goal: let Pi find files and read bounded text through checked native operations without shell syntax.

Architecture: one Pi extension exposes file_search and text_read, using Node filesystem APIs. Explicit paths are resolved by the host; results include actual absolute paths and counts. Search is bounded by depth, entries, result count and cancellation. Symlink directories are skipped. Existing permission gate applies to both operations. No write operation is added.

User authorization: continue implementation autonomously; keep the local model useful independently and as a tool for cloud providers.

Tasks:
- [ ] Add failing fixture tests for outside-project reads, Unicode, invalid bounds, missing paths, search result limits, symlink skipping and cancellation.
- [ ] Implement config/pi/extensions/aos-file-tools.ts and its tests with exported functions and thin Pi registration.
- [ ] Install through Sync-AosPi with backup/idempotence/DryRun tests; run aos test in both shells.
- [ ] Discover installed tools in coordinator host and include their evidence in runtime reminders.
- [ ] Run live local acceptance: find a fixture, read exact content; verify permission denial and actual output.
- [ ] Record tested capabilities and limitations; commit on existing feature branches.

Follow-on increments: Places registration and task retrieval; document extraction; predefined maintenance checks; shared gateway. Each requires its own verified acceptance before advertising availability.
