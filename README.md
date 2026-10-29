# docs-versioning

[![Release](https://img.shields.io/github/v/release/gsaronni/docs-versioning)](https://github.com/gsaronni/docs-versioning/releases)
[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![restic](https://img.shields.io/badge/backend-restic-3E8AFB)](https://restic.net/)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A restic-based backup and restore tool for a non-technical Windows user (originally built for my dad), with a plain point-and-click GUI on top of the same logic the command-line scripts use. It has been in daily use on the target machine since August 2026. See `CHANGELOG.md` for the full history and `ROADMAP.md` for what comes next.

## What it does

- **Back Up Now**: backs up a chosen folder to a local restic repository, applies retention (daily, weekly, monthly), and copies the repository to an external drive whenever one is connected.
- **Restore Latest Backup**: restores the most recent backup to a new, timestamped folder on the Desktop. Never touches existing files.
- **Find an Old File**: searches every backup (local and external) for files matching a name, shows the results in a sortable grid, and restores whichever ones you pick.
- **Update**: pulls the latest version from the private repository and forces the install back to it, whatever was changed or deleted locally.
- Runs unattended via Task Scheduler, or by hand via a desktop shortcut or the CLI scripts.
- The GUI speaks a deliberately archaic Italian for its real user, and English in test mode for development.

## Requirements

- Windows with **PowerShell 7** (`pwsh`), not Windows PowerShell 5.1.
- [restic](https://restic.net/) installed and on `PATH`.
- git, for the self-update.

## Folder structure

```
docs-versioning/
  VERSION                         single source of truth for the version shown in the GUI
  CHANGELOG.md
  ROADMAP.md
  bin/
    backup-documents.ps1          CLI: run a backup
    restore-latest.ps1            CLI: restore the latest backup
    fetch-file.ps1                CLI: search and restore specific files
    backup-helper-launcher.ps1    the GUI
    invoke-update.ps1             CLI: self-update
    create-shortcut.ps1           creates the desktop shortcut for the GUI
    setup-scheduled-task.ps1      registers the backup and update tasks, idempotently
    bump-version.ps1              bumps VERSION (patch, minor, major, alpha, beta)
    publish-showcase.ps1          publishes this public copy from the private repository
  etc/
    backup-config-template.psd1   start here
    backup-config.psd1            production config (example values in this copy)
    backup-config.test.psd1       development config (example values in this copy)
    restic-repo.key               repository password (never published)
  lib/
    backup-common.psm1            all real logic; CLI and GUI both call into it
    strings.psm1                  every user-visible string, English and Italian
  logs/                           the backup script's own logs, rotated after 120 days
```

## First-time setup

1. **Copy the template config:**
   ```powershell
   Copy-Item etc\backup-config-template.psd1 etc\backup-config.psd1
   ```
   Set `SourcePath` explicitly: there is no default, and a blank value stops the backup with an error rather than guessing a folder. Set `LocalRepoPath` to where the repository should live, and `ExternalDriveLabel` to the volume label of the external drive. Leave `PasswordFile` blank to use `etc\restic-repo.key`.

2. **Generate a repository password** (one-time, CLI only):
   ```powershell
   $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
   [Convert]::ToBase64String($bytes) | Set-Content -NoNewline etc\restic-repo.key
   ```

3. **Create the desktop shortcut:**
   ```powershell
   .\bin\create-shortcut.ps1
   ```
   Run it on the account that will use the GUI; the shortcut lands on that account's desktop.

4. **Register the scheduled tasks** (optional, for unattended backups and updates):
   ```powershell
   .\bin\setup-scheduled-task.ps1
   ```
   Creates the tasks under Task Scheduler's **Personal Backups** folder: backup at logon and daily at 18:00 (catching up if missed), update every four weeks. Safe to run repeatedly; it changes something only when the registered task has drifted from the desired definition.

## Using it

**GUI:** double-click the desktop shortcut, or run `.\bin\backup-helper-launcher.ps1`. Every button checks its preconditions first and says clearly what is wrong instead of failing silently.

**CLI:**
```powershell
.\bin\backup-documents.ps1              # real backup
.\bin\backup-documents.ps1 -DryRun      # show what would happen, change nothing
.\bin\restore-latest.ps1                # restore the most recent backup
.\bin\fetch-file.ps1                    # search and restore specific files
```

## Test mode

Every entry point supports `-Test`, which uses `backup-config.test.psd1` instead of the real config and switches the GUI to English, so development never touches the real setup:
```powershell
.\bin\backup-documents.ps1 -Test -DryRun
.\bin\backup-helper-launcher.ps1 -Test
.\bin\setup-scheduled-task.ps1 -Test      # registers separate "(TEST)" tasks
```

## How this copy is published

The tool lives in a private repository, which also holds the real configuration and the repository password for its one deployment. This public copy is generated from it by `bin/publish-showcase.ps1`: it exports the committed tree, removes private files, replaces private names, scans the result for anything that should not leave, and only then commits and releases here. Releases carry the same version and changelog on both sides.

## Known quirks

- **Permission warning on restore**: restic may report that it could not restore the timestamp of one folder. Setting it needs `SeRestorePrivilege`, which only a fully elevated shell has; the files themselves are always restored completely.
- **Registering the scheduled tasks the first time may need an elevated PowerShell window**, because creating a new Task Scheduler folder does. Later runs do not.
