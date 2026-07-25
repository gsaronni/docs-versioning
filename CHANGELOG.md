# Changelog

All notable changes to the docs-versioning project are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [0.1.0-alpha] - 2026-07-25

### Status

First working draft. Everything below tested on dev-machine as a standalone testbed — SourcePath in backup-config.psd1 still points at a placeholder, so nothing has run against a real target yet. Not deployed to production (dad's machine). Direct spinoff of Checkpoint's BG3/restic migration — same restic patterns, no bash/WSL dependency at all this time.

### Added

- backup-documents.ps1 — local repo (frequent) + external drive repo (replicated via `restic copy` whenever a drive labeled ExternalDisk is connected, detected by volume label rather than drive letter). Day-gate via direct query against the repo's own snapshot history (no marker file — same design proven on Checkpoint's BG3 migration). Retention: keep-daily 10, keep-weekly 4, keep-monthly 6 — monthly added here specifically because real documents warrant longer recall than game saves. Self-generating timestamped logs with rotation, no -LogFile parameter needed since there's nothing else to unify with here.
- restore-latest.ps1 — zero-argument recovery. Restores the latest backup to a new timestamped Desktop folder. Never touches existing files.
- fetch-file.ps1 — interactive search across all snapshots via `restic find --ignore-case --json`, confirmed recursive and case-insensitive (verified empirically against a real test repo, not assumed). Results shown in Out-GridView (built into PowerShell 7 on Windows Desktop, no extra module) for actual clickable selection, extracting just the one chosen file to a fresh Desktop folder.
- lib/BackupCommon.psm1 — shared config-loading + restic-availability check, factored out once duplicated identically across all three scripts. Deliberately minimal: logging, day-gating, and external-drive detection stay local to backup-documents.ps1 since only it needs them. Not yet wired into the three scripts — sitting ready for the next pass.
- bin/BackupHelper-Launcher.ps1 — WinForms front door (3 buttons: Back Up Now / Restore Latest / Find an Old File) over the same three scripts. Deliberately a thin launcher, not a rewrite — CLI usage of the underlying scripts is fully unaffected, and Task Scheduler will call backup-documents.ps1 directly, bypassing this entirely.

### Considered and rejected

- ps2exe compilation of the launcher into a standalone .exe. Built, hit a real bug ($PSScriptRoot is empty inside ps2exe-compiled executables — documented upstream limitation, confirmed via multiple independent sources), fixed it correctly using ps2exe's own documented workaround — then dropped the whole approach anyway. Reasoning: compiling a PowerShell script into a raw .exe is exactly the pattern antivirus heuristics flag as suspicious (ps2exe's own README acknowledges this), which risks a scary, unexplainable Defender popup on dad's very first double-click with no one around to reassure him it's fine. A plain .lnk shortcut targeting `pwsh.exe -File launcher.ps1` gives the same double-clickable icon experience with zero compilation, zero extra tooling, and zero AV risk. Simpler wins.

### Notes

- Password file and all scripts live under a dedicated root (originally planned as C:\Backup on the real deployment), deliberately outside Documents\2026 — that folder syncs to Nextcloud, so anything inside it risks being swept into that sync or, worse, into the backup's own source set.
- `restic copy` has no --dry-run flag (confirmed: open, unresolved upstream feature request, not something either of us is missing). backup-documents.ps1 handles this by logging the command it would run during -DryRun without executing it, rather than passing a flag that doesn't exist.

### TODO

- Edit backup-config.psd1's SourcePath to a real path before any meaningful test run
- Wire BackupCommon.psm1 into all three scripts (currently built, unused)
- Decide on and build the .lnk shortcut for dad's actual desktop
- Test the full external-drive replication path end to end (drive labeling, first-time external repo init, restic copy) — not yet exercised at all, only designed
- Eventually: deeper GUI integration (logic moved into BackupCommon.psm1 as real functions, GUI calls them directly on a background thread instead of spawning separate console windows) — explicitly deferred, real scope, not a quick patch
- Deploy to dad's actual machine once the above is solid
