# docs-versioning

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![restic](https://img.shields.io/badge/backend-restic-3E8AFB)](https://restic.net/)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Status](https://img.shields.io/badge/status-1.0.0--beta-yellow)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A simple, restic-based backup and restore tool for a non-technical user (originally built for my dad), with a plain point-and-click GUI on top of the same logic the command-line scripts use. Status: **1.0.0-beta** — see `CHANGELOG.md` for details.

## What it does

- **Back Up Now** — backs up a chosen folder to a local restic repository, applies retention (daily/weekly/monthly), and copies to an external drive if one's connected.
- **Restore Latest Backup** — restores the most recent backup to a new, timestamped folder on the Desktop. Never touches existing files.
- **Find an Old File** — searches every backup (local and external) for files matching a name, shows results in a sortable/filterable grid, and restores whichever one(s) you pick.
- Runs unattended via Task Scheduler, or by hand via a desktop shortcut or the CLI scripts directly.

## Requirements

- Windows with **PowerShell 7** (`pwsh`) — not Windows PowerShell 5.1.
- [restic](https://restic.net/) installed and on `PATH`.

## Folder structure

```
docs-versioning/
  bin/
    backup-documents.ps1        — CLI: run a backup
    restore-latest.ps1          — CLI: restore the latest backup
    fetch-file.ps1              — CLI: search and restore a specific file
    backup-helper-launcher.ps1  — the GUI
    create-shortcut.ps1         — creates a desktop shortcut for the GUI
    setup-scheduled-task.ps1    — registers/updates the Task Scheduler entry
  etc/
    backup-config.template.psd1 — copy this, don't edit it directly
    backup-config.psd1          — your real config (gitignored)
    backup-config.test.psd1     — your local test config (gitignored)
    restic-repo.key             — repository password (gitignored)
  lib/
    backup-common.psm1          — all real logic lives here; CLI and GUI both call into it
  logs/                          — backup-documents.ps1's own logs, auto-rotated after 120 days
```

## First-time setup

1. **Copy the template config:**
   ```powershell
   Copy-Item etc\backup-config.template.psd1 etc\backup-config.psd1
   ```
   Leave `SourcePath` and `PasswordFile` blank to use sensible defaults (`<Documents>\2026` for whoever's account runs it, and a key file living next to this project) — no need to hardcode a username anywhere. Set `LocalRepoPath` to wherever the backup repository should live, and `ExternalDriveLabel` to whatever you've labeled your external backup drive in Explorer.

2. **Generate a repository password** (one-time, CLI only — this isn't something end users ever need to touch):
   ```powershell
   $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
   [Convert]::ToBase64String($bytes) | Set-Content -NoNewline etc\restic-repo.key
   ```

3. **Create the desktop shortcut:**
   ```powershell
   .\bin\create-shortcut.ps1
   ```
   Run this on whichever machine/account will actually use the GUI — it places the shortcut on *that* account's own desktop.

4. **Register the scheduled task** (optional, for unattended daily backups):
   ```powershell
   .\bin\setup-scheduled-task.ps1
   ```
   Creates a task under Task Scheduler's **Personal Backups** folder — logon + daily (6pm, catches up if missed). Safe to run repeatedly; only changes anything if the desired configuration has actually drifted from what's registered.

## Using it

**GUI:** double-click the desktop shortcut, or run `.\bin\backup-helper-launcher.ps1` directly. Every button checks preconditions first and tells you clearly if something's wrong, rather than failing silently.

**CLI**, if you prefer:
```powershell
.\bin\backup-documents.ps1              # real backup
.\bin\backup-documents.ps1 -DryRun      # see what would happen, change nothing
.\bin\restore-latest.ps1                # restore the most recent backup
.\bin\fetch-file.ps1                    # search and restore a specific file
```

## Test mode

Everything above supports a `-Test` switch, which points at `backup-config.test.psd1` instead of the real config — completely isolated, safe to break repeatedly during development without ever touching the real setup:
```powershell
.\bin\backup-documents.ps1 -Test -DryRun
.\bin\backup-helper-launcher.ps1 -Test    # GUI title bar shows "TEST MODE"
.\bin\setup-scheduled-task.ps1 -Test      # registers a separate "Daily Backup (TEST)" task
```

## Known quirks

- **Windows permission warning on restore**: you may see a message about a timestamp not being restorable on one folder. This is a real but harmless `SeRestorePrivilege` limitation (requires a fully elevated shell to fix) — your files are always restored completely and correctly regardless; this is not a real error.
- **Registering a scheduled task the first time may need an elevated PowerShell window** — appears specific to creating a brand-new Task Scheduler folder; not needed for a machine where the "Personal Backups" folder already exists.

## Status / what's not done yet

See `CHANGELOG.md` for the full history. As of 1.0.0-beta:
- Not yet deployed to the real target machine — `SourcePath` still points at test data.
- External-drive redundancy tested only with two folders on the same physical disk, not yet against a genuinely separate drive.
- No automatic cleanup yet for old `Restored-Backup-*` / `Restored-File-*` folders accumulating on the Desktop.