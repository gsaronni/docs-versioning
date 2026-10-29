# Roadmap

What the tool should do next, in planned release order. Each item ships through the normal release process and reaches the deployed install through Update. Done items move to `CHANGELOG.md`.

## 1.2.0: configurable update source and health reporting

- **Update source in config.** The update endpoint (host and port) moves from a hardcoded value in `backup-common.psm1` to config keys, with a hard failure when they are missing.
- **Health ping.** After every successful backup, an optional HTTP ping to a push monitor (`HealthPingUrl`, blank means disabled), carrying the snapshot count and whether the external drive synced. A missed ping raises the alert on the monitor side, so the user never has to report a problem.
- **Last backup and last external sync in the GUI.** "Last backup N days ago" and "External drive last synced N days ago", read from the repositories. The second is the only reminder to plug the drive in.
- **Minimum restic version.** Fail loudly below the version that supports `--skip-if-unchanged` and `copy --from-repo`.

## 1.3.0: tests and CI

- **Pester 5 unit tests** for the pure functions: path conversion, config validation, version bumping, the scheduled-task signature.
- **Mocked restic** at `Invoke-LoggedRestic` to test the day gate, the exit-code-3 warning, the benign timestamp warning, and the search result object surviving the runspace boundary.
- **Integration tests** with a real restic binary against temporary repositories: backup, retention, copy with shared chunker parameters, find, restore.
- **String lint:** every key present in both languages, matching placeholder counts, internal markers never translated.
- **PSScriptAnalyzer** and a parse-only check of the GUI script.
- **CI** running all of the above on every pull request.

## 1.4.0: maintenance and gaps

- **Monthly integrity check** with `restic check --read-data-subset`, reported like a backup.
- **Cleanup of restored folders** (`Restored-Backup-*`, `Restored-File-*`) older than a configurable age.
- **`Test-AnyRepoExists` checks the external repository too**, so Find works with only the external drive available.
- **`create-shortcut.ps1` honours test mode.**
- **Find picker**: confirm selection with Enter, and document it.

## Later

- **Offsite third copy** with `restic copy` to a self-hosted rest-server, keeping the "own disks only" rule.
- **Short git hash in the title bar** next to the version.
- **Localised CLI output.**

## Non-goals

- A web UI, multiple users, Linux or macOS support, cloud backends. Tools like Backrest already cover those; this one exists for a single non-technical Windows user.
