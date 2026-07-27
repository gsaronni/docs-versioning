# Changelog

All notable changes to the docs-versioning project are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com).

## 1.0.5-beta 2026-07-27 (hotfix — found during deployment testing)

### Changed
- `SourcePath` in `backup-config.psd1` set to the real, deliberate value for deployment: `C:\Users\user\Documents` (whole Documents folder, not a yearly subfolder — confirmed intentional).
- `ExternalDriveLabel` set to `Disk`, matching the actual factory label on the connected external drive (confirmed via `Get-Volume`).

### Fixed
- `Import-BackupConfig` no longer silently defaults `SourcePath` to `<Documents>\2026` when the config leaves it blank — that default risked backing up the wrong folder without anyone noticing. A missing `SourcePath` now throws an explicit, visible error instead.

### Known gaps / next steps
- `ExternalDriveLabel` is currently the drive's factory label, not a deliberately chosen one — if the drive is ever reformatted, relabeled, or replaced, this will need updating (fails silently/skips external sync if it doesn't match, no error).
- First real Backup/external-sync/Restore/Find runs against production are the next step, not yet done.

## 1.0.4-beta 2026-07-26 (hotfix — found during deployment testing)

### Fixed
- Clicking "Find an Old File" / "Cerca Documento Perduto" with no repo at all silently did nothing — no dialog, no message, just a completed search that led nowhere. Root cause: `Search-BackupFiles` returned a bare `$null` to signal "no repo exists," but a plain `$null` doesn't reliably survive the trip back across the background runspace boundary, so neither the null-check nor the empty-results-check in the GUI ever matched. Fixed by having the function return an explicit `[PSCustomObject]@{ RepoFound; Matches }` instead of relying on `$null` vs. empty-array ambiguity.
- "Find an Old File" now checks `Test-AnyRepoExists` upfront, before prompting for a search term or spinning up a background search — matching the pattern `$btnRestore` already used. Previously it would ask for a term, run the whole search, and only discover there was nothing to search *after* all that work; now it stops immediately with the same "Nothing to Search" message, no wasted round-trip.

### Verified
- Both Italian and English "no matches for this term" and "no repo exists yet" dialogs confirmed correct — the no-matches path via a temporary `LocalRepoPath` swap to the existing test repo (reverted via `git checkout --`), and the no-repo-yet path via a throwaway empty `restic init` at the production path, deleted afterward — production `C:\Backup\repo-local` remains genuinely uninitialized ahead of real deployment.

## 1.0.3-beta 2026-07-26

### Added
- Full Italian (Dantesco) localization of the GUI, driven by the existing `-Test` switch: standard mode now shows Italian, `-Test` mode stays English for dev/debugging. All button text, dialog prompts, status labels, and log-box narration route through a new `lib/strings.psm1` (`Get-Str 'Key' [-FormatArgs @(...)]`). Deliberately out of scope: raw `restic`/`git` output passed straight through, the `PROGRESS:`/`RESTORE_TARGET:`/`ERROR:` internal markers (translating those would silently break the progress bar and error-coloring logic), and Windows' own OS-locale `MessageBox` button captions.

### Fixed
- `backup-helper-launcher.ps1` never actually reset `$env:BACKUP_HELPER_TEST_MODE` when run without `-Test` — a prior `-Test` run in the same PowerShell session left the variable set, so the GUI kept rendering in English even on a "real" run. The other three CLI wrappers already handled this correctly; the launcher was the one file missed. Fixed with the same `if/else` + `Remove-Item Env:\...` pattern used elsewhere.

### Considered and rejected
- A `git status --porcelain` dirty-check before Update's `reset --hard`/`clean -fd`, meant to stop the button from discarding uncommitted work on a dev machine mid-edit (cost three real losses on dev-machine during this session). Rejected: it would have equally blocked the reset on dad's machine any time he deleted or altered a tracked file — exactly the "no matter what he does to it, Update fixes it" guarantee the feature exists for. Dad's machine is deliberately meant to have its state forced back to whatever's pushed, full stop, deletions and edits included. Resolution: be more careful testing Update on dev-machine instead of softening what it does on dad's install.

### Known gaps / next steps
- Still not deployed to dad's real machine (unchanged from prior versions).

## 1.0.2-beta 2026-07-26

### Fixed
- Update button could silently collide with Backup/Restore/Find: a duplicate `$AllButtons` array declaration in `backup-helper-launcher.ps1` was overwriting the one that included `$btnUpdate`, so it never got disabled/re-enabled alongside the other three. Since all operations share a single background runspace, clicking Update mid-Backup (or vice versa) would have silently orphaned whichever ran first.
- `setup-scheduled-task.ps1 -Remove` only removed the "Daily Backup" task and exited before ever reaching the "Docs Update" task — running `-Remove` couldn't fully clean up both tasks in one call. Restructured so both removals happen together up front, and registration for each task is now independent (one task's drift/failure no longer blocks the other).
- Update task's stored drift-detection signature said `"Monthly-Day1-09:00"` while the actual registered trigger was weekly-every-4-Sunday — cosmetic only (never affected behavior), but corrected to `"Weekly-4-Sunday-09:00"` so it doesn't mislead future debugging.

### Verified
- `.\setup-scheduled-task.ps1 -Test` registers both "Daily Backup (TEST)" and "Docs Update (TEST)"; `-Test -Remove` now removes both in one call — confirmed via live Task Scheduler runs on dev-machine, not just code review.

## 1.0.1-beta 2026-07-26

### Added
- Update button in the GUI (`Invoke-DocsUpdate` in `lib/backup-common.psm1`), sharing the same background-runspace/progress-bar/Stop machinery as Backup/Restore/Find. Checks reachability to zblade's Gitea over Netbird first (clear message if unreachable, no silent hang), then forces the local repo to match `origin/main` (`fetch` + `reset --hard` + `clean -fd`), deliberate one-way sync, not a merge: whoever clicks Update gets exactly what's pushed, no local-drift handling needed since this repo has exactly one committer.
- Shortcut regeneration on update, but only if the desktop `.lnk` is actually missing not run unconditionally, since the shortcut's target/icon don't change on their own between pulls.
- Scheduled task re-registration folded into the same flow, calls the existing idempotent `setup-scheduled-task.ps1`, respecting `-Test` via `BACKUP_HELPER_TEST_MODE` so a test-mode Update never touches the real "Daily Backup" task.

### Known gaps / next steps
- Update itself isn't yet on a schedule, currently only runs when the button is clicked. A monthly (or longer) scheduled task calling `Invoke-DocsUpdate -Silent` would close the loop for a machine that might otherwise go a long time between manual "hey, click Update" nudges.
- Still not deployed to dad's actual machine (unchanged from 1.0.0-beta).

## 1.0.0-beta 2026-07-26

First complete, end-to-end working version, CLI and GUI both fully functional and tested. Still "beta" because: `SourcePath` isn't pointed at dad's real Documents\2026 yet, the external-drive test setup deliberately uses two folders on the same physical disk (not real redundancy), and none of this has been deployed to dad's actual machine yet.

### Added
- Full WinForms GUI (`backup-helper-launcher.ps1`): Back Up Now / Restore Latest Backup / Find an Old File / Stop, all sharing logic with the CLI scripts via `lib/backup-common.psm1`.
- Real progress bars for Backup and Restore, parsed from restic's own `--json` `percent_done` stream, not simulated. Find gets an honest indeterminate marquee bar instead of a fake percentage, since `restic find` doesn't stream progress the way `backup`/`restore` do.
- Search now logs real checkpoints (`Checking Local repo...`, `Searching External for 'x'...`, `Found N match(es)`) instead of running silently.
- Multi-file select-and-restore via `Out-GridView -OutputMode Multiple`, in both CLI and GUI.
- Stop button: cooperative stop via `[powershell].Stop()`; automatically cleans up partial restore files rather than leaving them on the Desktop.
- Disk-space check before a full restore (`restic stats --mode restore-size` vs. free space, 10% safety margin), warns and aborts if there isn't enough room.
- `-Test` switch across every script + `BACKUP_HELPER_TEST_MODE` env var: a separate `backup-config.test.psd1` for local dev, completely isolated from the real `backup-config.psd1`. GUI title bar shows "TEST MODE" when active.
- `create-shortcut.ps1`: generates a real desktop `.lnk`, hidden console (`pwsh -WindowStyle Hidden`), configurable icon.
- `setup-scheduled-task.ps1`: idempotent Task Scheduler registration under a custom "Personal Backups" folder, `AtLogOn` + `Daily` (6pm) with `StartWhenAvailable` to catch missed runs; `-Test`/`-Remove` switches; drift-detection via a signature stored in the task's own Description field.

### Fixed
- Restore paths no longer mirror the full absolute source chain (`C:\Users\...`), full restore is rooted at the actual backed-up folder via restic's `snapshot:subfolder` syntax; single-file restore uses `restic dump` for a flat, simple result.
- The Windows `SeRestorePrivilege` timestamp warning (benign, data always intact) is no longer misreported as a failed restore.
- `restic copy`/`init`'s deprecated `--repo2` flag replaced with the current `--from-repo`/`--from-password-file` scheme (deprecated since restic 0.14), was also masking a real bug: the "already backed up today" shortcut path was skipping external-repo initialization entirely.
- `$PSNativeCommandUseErrorActionPreference` (a PowerShell 7.3+ behavior, on by default in 7.4+) was converting restic's routine nonzero exit codes into GUI-crashing PowerShell errors, disabled explicitly.
- The actual GUI crash cause: `Application.DoEvents()` inside a click handler was processing other button clicks **reentrantly**, nesting one PowerShell scriptblock's execution inside another's, something PowerShell's error-handling internals aren't built to expect when scriptblocks run as raw WinForms delegates. Replaced with a single top-level `Timer` and `$script:`-scope state; no `DoEvents()` anywhere anymore.
- `restic` exit code `3` (some source files unreadable, backup otherwise fine) is now handled as a warning, not a hard failure.
- Config no longer needs a hardcoded username anywhere: `SourcePath` defaults to `<Documents>\2026` for whoever's account is running it; `PasswordFile` defaults to a path relative to the script's own location.

### Known gaps / next steps
- Not yet deployed to dad's real machine, `SourcePath` still points at test data (BG3 savegames).
- External-drive redundancy still untested against a genuinely separate physical disk.
- No cleanup yet for old `Restored-Backup-*`/`Restored-File-*` folders accumulating on the Desktop over time.
- Real-world duration for the first full external sync over USB 2.0 is unknown, `setup-scheduled-task.ps1`'s 6-hour execution limit is a placeholder pending real data.

## [0.1.0-alpha] - 2026-07-25

### Status

First working draft. Everything below tested on dev-machine as a standalone testbed, SourcePath in backup-config.psd1 still points at a placeholder, so nothing has run against a real target yet. Not deployed to production (dad's machine). Direct spinoff of Checkpoint's BG3/restic migration, same restic patterns, no bash/WSL dependency at all this time.

### Added

- backup-documents.ps1, local repo (frequent) + external drive repo (replicated via `restic copy` whenever a drive labeled ExternalDisk is connected, detected by volume label rather than drive letter). Day-gate via direct query against the repo's own snapshot history (no marker file, same design proven on Checkpoint's BG3 migration). Retention: keep-daily 10, keep-weekly 4, keep-monthly 6, monthly added here specifically because real documents warrant longer recall than game saves. Self-generating timestamped logs with rotation, no -LogFile parameter needed since there's nothing else to unify with here.
- restore-latest.ps1, zero-argument recovery. Restores the latest backup to a new timestamped Desktop folder. Never touches existing files.
- fetch-file.ps1, interactive search across all snapshots via `restic find --ignore-case --json`, confirmed recursive and case-insensitive (verified empirically against a real test repo, not assumed). Results shown in Out-GridView (built into PowerShell 7 on Windows Desktop, no extra module) for actual clickable selection, extracting just the one chosen file to a fresh Desktop folder.
- lib/BackupCommon.psm1, shared config-loading + restic-availability check, factored out once duplicated identically across all three scripts. Deliberately minimal: logging, day-gating, and external-drive detection stay local to backup-documents.ps1 since only it needs them. Not yet wired into the three scripts, sitting ready for the next pass.
- bin/BackupHelper-Launcher.ps1, WinForms front door (3 buttons: Back Up Now / Restore Latest / Find an Old File) over the same three scripts. Deliberately a thin launcher, not a rewrite, CLI usage of the underlying scripts is fully unaffected, and Task Scheduler will call backup-documents.ps1 directly, bypassing this entirely.

### Considered and rejected

- ps2exe compilation of the launcher into a standalone .exe. Built, hit a real bug ($PSScriptRoot is empty inside ps2exe-compiled executables, documented upstream limitation, confirmed via multiple independent sources), fixed it correctly using ps2exe's own documented workaround, then dropped the whole approach anyway. Reasoning: compiling a PowerShell script into a raw .exe is exactly the pattern antivirus heuristics flag as suspicious (ps2exe's own README acknowledges this), which risks a scary, unexplainable Defender popup on dad's very first double-click with no one around to reassure him it's fine. A plain .lnk shortcut targeting `pwsh.exe -File launcher.ps1` gives the same double-clickable icon experience with zero compilation, zero extra tooling, and zero AV risk. Simpler wins.

### Notes

- Password file and all scripts live under a dedicated root (originally planned as C:\Backup on the real deployment), deliberately outside Documents\2026, that folder syncs to Nextcloud, so anything inside it risks being swept into that sync or, worse, into the backup's own source set.
- `restic copy` has no --dry-run flag (confirmed: open, unresolved upstream feature request, not something either of us is missing). backup-documents.ps1 handles this by logging the command it would run during -DryRun without executing it, rather than passing a flag that doesn't exist.

### TODO

- Edit backup-config.psd1's SourcePath to a real path before any meaningful test run
- Wire BackupCommon.psm1 into all three scripts (currently built, unused)
- Decide on and build the .lnk shortcut for dad's actual desktop
- Test the full external-drive replication path end to end (drive labeling, first-time external repo init, restic copy), not yet exercised at all, only designed
- Eventually: deeper GUI integration (logic moved into BackupCommon.psm1 as real functions, GUI calls them directly on a background thread instead of spawning separate console windows), explicitly deferred, real scope, not a quick patch
- Deploy to dad's actual machine once the above is solid
