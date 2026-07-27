<#
=============================================================================
 backup-common.psm1
 Real shared logic — backup, restore, search — used by BOTH the CLI
 scripts and the GUI, via a -LogAction callback each caller supplies.
=============================================================================
#>

# PowerShell 7.3+ can convert a native command's nonzero exit code into an
# actual PowerShell error (per $ErrorActionPreference) — restic routinely
# returns nonzero for benign warnings, and that conversion was crashing the
# GUI when triggered from inside a WinForms event-callback context.
$global:PSNativeCommandUseErrorActionPreference = $false

Import-Module (Join-Path $PSScriptRoot "strings.psm1") -Force

function Import-BackupConfig {
    param([string]$ScriptRoot)
    $ConfigName = if ($env:BACKUP_HELPER_TEST_MODE -eq "1") { "backup-config.test.psd1" } else { "backup-config.psd1" }
    $ConfigPath = Join-Path $ScriptRoot "..\etc\$ConfigName"
    if (-not (Test-Path $ConfigPath)) {
        throw (Get-Str 'ConfigNotFound' -FormatArgs @($ConfigPath, $ConfigName))
    }
    $cfg = Import-PowerShellDataFile $ConfigPath

    if ([string]::IsNullOrWhiteSpace($cfg.SourcePath)) {
        throw (Get-Str 'SourcePathNotSet')
    }
    if ([string]::IsNullOrWhiteSpace($cfg.PasswordFile)) {
        $cfg.PasswordFile = Join-Path $ScriptRoot "..\etc\restic-repo.key"
    }

    $env:RESTIC_REPOSITORY    = $cfg.LocalRepoPath
    $env:RESTIC_PASSWORD_FILE = $cfg.PasswordFile
    return $cfg
}

function Test-ResticAvailable {
    return [bool](Get-Command restic -ErrorAction SilentlyContinue)
}

function Get-ExternalDrivePath {
    param([string]$Label, [string]$Subpath)
    $vol = Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue
    if ($vol -and $vol.DriveLetter) {
        return "$($vol.DriveLetter):\$Subpath"
    }
    return $null
}

function ConvertTo-ResticInternalPath {
    param([string]$WindowsPath)
    if ($WindowsPath -match '^([A-Za-z]):\\(.*)$') {
        return "/$($Matches[1].ToUpper())/$($Matches[2] -replace '\\','/')"
    }
    return $WindowsPath -replace '\\', '/'
}

function Sync-ExternalRepo {
    param($cfg, [string]$Tag, [scriptblock]$LogAction, [switch]$DryRun)

    $extPath = Get-ExternalDrivePath -Label $cfg.ExternalDriveLabel -Subpath $cfg.ExternalRepoSubpath
    if (-not $extPath) {
        & $LogAction (Get-Str 'ExtDriveSkip' -FormatArgs @($cfg.ExternalDriveLabel))
        return $true
    }

    & $LogAction (Get-Str 'ExtDriveFound' -FormatArgs @($extPath))
    & restic -r $extPath --password-file $cfg.PasswordFile snapshots --json 2>&1 | Out-Null
    $extRepoExists = $LASTEXITCODE -eq 0

    if (-not $extRepoExists) {
        & $LogAction (Get-Str 'ExtRepoInit')
        if (-not $DryRun) {
            $initArgs = @(
                "-r", $extPath, "--password-file", $cfg.PasswordFile, "init",
                "--from-repo", $cfg.LocalRepoPath, "--from-password-file", $cfg.PasswordFile,
                "--copy-chunker-params"
            )
            $initExit = Invoke-LoggedRestic -ResticArgs $initArgs -LogAction $LogAction
            if ($initExit -ne 0) { & $LogAction (Get-Str 'ExtRepoInitFailed'); return $false }
            & $LogAction (Get-Str 'ExtRepoInitOk')
        }
    }

    if (-not $DryRun) {
        $copyArgs = @(
            "copy", "-r", $extPath, "--password-file", $cfg.PasswordFile,
            "--from-repo", $cfg.LocalRepoPath, "--from-password-file", $cfg.PasswordFile,
            "--tag", $Tag
        )
        Invoke-LoggedRestic -ResticArgs $copyArgs -LogAction $LogAction | Out-Null
    }
    return $true
}

function Test-BackupConfigReady {
    param([string]$ScriptRoot)
    $cfg = Import-BackupConfig -ScriptRoot $ScriptRoot
    if (-not (Test-ResticAvailable)) { return (Get-Str 'ResticMissing') }
    if (-not (Test-Path $cfg.SourcePath)) { return (Get-Str 'SourceMissing' -FormatArgs @($cfg.SourcePath)) }
    $localDriveRoot = Split-Path -Qualifier $cfg.LocalRepoPath
    if (-not (Test-Path $localDriveRoot)) { return (Get-Str 'DriveMissing' -FormatArgs @($localDriveRoot)) }
    if (-not (Test-Path $cfg.PasswordFile)) { return (Get-Str 'PasswordMissing' -FormatArgs @($cfg.PasswordFile)) }
    return $null
}

function Test-AnyRepoExists {
    param([string]$ScriptRoot)
    Import-BackupConfig -ScriptRoot $ScriptRoot | Out-Null
    & restic snapshots --tag docs-daily --json 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-AlreadyRanToday {
    param([string]$Tag)
    $Today = Get-Date -Format "yyyy-MM-dd"
    $json = & restic snapshots --tag $Tag --latest 1 --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $false }
    $snaps = $json | ConvertFrom-Json
    if (-not $snaps -or $snaps.Count -eq 0) { return $false }
    $lastDate = ([datetime]$snaps[0].time).ToString("yyyy-MM-dd")
    return ($lastDate -eq $Today)
}

# Checks the LATEST snapshot's restore size against free space at the
# restore destination. Returns $null if it couldn't be determined (fails
# open — never blocks a restore over an inconclusive check).
function Test-EnoughRestoreSpace {
    param([string]$ScriptRoot)
    Import-BackupConfig -ScriptRoot $ScriptRoot | Out-Null

    $statsJson = & restic stats latest --tag docs-daily --mode restore-size --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $statsJson) { return $null }
    $stats = $statsJson | ConvertFrom-Json
    $neededBytes = $stats.total_size

    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $driveLetter = (Get-Item $desktopPath).PSDrive.Name
    $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if (-not $drive) { return $null }
    $freeBytes = $drive.Free

    [PSCustomObject]@{
        NeededBytes = $neededBytes
        FreeBytes   = $freeBytes
        Enough      = ($freeBytes -gt ($neededBytes * 1.1))  # 10% safety margin
    }
}

function Invoke-LoggedRestic {
    param([string[]]$ResticArgs, [scriptblock]$LogAction)
    & restic @ResticArgs 2>&1 | ForEach-Object { & $LogAction $_ }
    return $LASTEXITCODE
}

# =============================================================================
# BACKUP — uses --json so we get real percent_done progress; --json replaces
# restic's normal human text entirely, so we reconstruct a readable summary
# line ourselves from the structured "summary" message once it arrives.
# =============================================================================

function Invoke-DocumentBackup {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][scriptblock]$LogAction,
        [switch]$DryRun
    )

    $cfg = Import-BackupConfig -ScriptRoot $ScriptRoot
    $Tag = "docs-daily"

    if (-not (Test-ResticAvailable)) {
        & $LogAction (Get-Str 'ResticNotFound')
        return $false
    }
    if (-not (Test-Path $cfg.SourcePath)) {
        & $LogAction (Get-Str 'SourceMissingErr' -FormatArgs @($cfg.SourcePath))
        return $false
    }
    $localDriveRoot = Split-Path -Qualifier $cfg.LocalRepoPath
    if (-not (Test-Path $localDriveRoot)) {
        & $LogAction (Get-Str 'DriveMissingErr' -FormatArgs @($localDriveRoot))
        return $false
    }
    if (-not (Test-Path $cfg.PasswordFile)) {
        & $LogAction (Get-Str 'PasswordMissingErr' -FormatArgs @($cfg.PasswordFile))
        return $false
    }

    & $LogAction (Get-Str 'CheckingLocalRepo' -FormatArgs @($cfg.LocalRepoPath))
    & restic snapshots --json 2>&1 | Out-Null
    $repoExists = $LASTEXITCODE -eq 0

    if (-not $repoExists) {
        & $LogAction (Get-Str 'LocalRepoNotFound')
        if (-not $DryRun) {
            & restic init
            if ($LASTEXITCODE -ne 0) { & $LogAction (Get-Str 'RepoInitFailed'); return $false }
            & $LogAction (Get-Str 'LocalRepoInitOk')
        }
    } else {
        & $LogAction (Get-Str 'LocalRepoExists')
    }

    $alreadyRanToday = Test-AlreadyRanToday -Tag $Tag
    if ($alreadyRanToday -and -not $DryRun) {
        & $LogAction (Get-Str 'AlreadyRanToday')
        Sync-ExternalRepo -cfg $cfg -Tag $Tag -LogAction $LogAction -DryRun:$DryRun | Out-Null
        return $true
    }

    & $LogAction (Get-Str 'StartingBackup' -FormatArgs @($cfg.SourcePath))
    $backupArgs = @("backup", $cfg.SourcePath, "--tag", $Tag, "--skip-if-unchanged", "--json")
    if ($DryRun) { $backupArgs += "--dry-run" }

    & restic @backupArgs 2>&1 | ForEach-Object {
        $line = [string]$_
        $obj = $null
        try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }

        if ($obj -and $obj.message_type -eq "status") {
            & $LogAction "PROGRESS:$([math]::Round($obj.percent_done * 100))"
        } elseif ($obj -and $obj.message_type -eq "summary") {
            $addedGB = [math]::Round($obj.data_added / 1GB, 3)
            & $LogAction (Get-Str 'FilesAdded' -FormatArgs @($obj.files_new, $obj.files_changed, $addedGB))
            if ($obj.snapshot_id) { & $LogAction (Get-Str 'SnapshotSaved' -FormatArgs @($obj.snapshot_id)) }
        } elseif ($obj -and $obj.message_type -eq "error") {
            & $LogAction "ERROR: $($obj.error.message)"
        } elseif ($line) {
            & $LogAction $line
        }
    }
    $backupExit = $LASTEXITCODE

    if ($backupExit -eq 3) {
        # Exit code 3 = some source files couldn't be read, but the backup
        # otherwise completed and a snapshot was created — not a real failure.
        & $LogAction (Get-Str 'BackupPartialWarn')
    } elseif ($backupExit -ne 0) {
        & $LogAction (Get-Str 'BackupExitError' -FormatArgs @($backupExit))
        return $false
    }
    & $LogAction (Get-Str 'BackupOk')

    & $LogAction (Get-Str 'ApplyingRetention' -FormatArgs @($cfg.KeepDaily, $cfg.KeepWeekly, $cfg.KeepMonthly))
    $forgetArgs = @("forget", "--tag", $Tag, "--keep-daily", $cfg.KeepDaily, "--keep-weekly", $cfg.KeepWeekly, "--keep-monthly", $cfg.KeepMonthly, "--prune")
    if ($DryRun) { $forgetArgs += "--dry-run" }
    Invoke-LoggedRestic -ResticArgs $forgetArgs -LogAction $LogAction | Out-Null

    Sync-ExternalRepo -cfg $cfg -Tag $Tag -LogAction $LogAction -DryRun:$DryRun | Out-Null

    return $true
}

# =============================================================================
# RESTORE LATEST — same --json progress approach. Emits a RESTORE_TARGET:
# marker line FIRST, before any actual restore work, specifically so the
# GUI can clean up partial files if the operation is stopped mid-way.
# =============================================================================

function Invoke-LatestRestore {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][scriptblock]$LogAction
    )

    $cfg = Import-BackupConfig -ScriptRoot $ScriptRoot

    if (-not (Test-ResticAvailable)) {
        & $LogAction (Get-Str 'ResticMissingCall')
        return $null
    }

    if (-not (Test-AnyRepoExists -ScriptRoot $ScriptRoot)) {
        & $LogAction (Get-Str 'NoReposYet')
        return $null
    }

    $RestoreTarget = Join-Path ([Environment]::GetFolderPath("Desktop")) "Restored-Backup-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
    & $LogAction "RESTORE_TARGET:$RestoreTarget"
    & $LogAction (Get-Str 'RestoringLatest')

    $internalRoot = ConvertTo-ResticInternalPath $cfg.SourcePath
    $restoreArgs = @("restore", "latest:$internalRoot", "--tag", "docs-daily", "--target", $RestoreTarget, "--json")

    $sawAnyProblem = $false
    $benignOnly = $true

    & restic @restoreArgs 2>&1 | ForEach-Object {
        $line = [string]$_
        $obj = $null
        try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }

        if ($obj -and $obj.message_type -eq "status") {
            & $LogAction "PROGRESS:$([math]::Round($obj.percent_done * 100))"
        } elseif ($obj -and $obj.message_type -eq "summary") {
            $restoredGB = [math]::Round($obj.bytes_restored / 1GB, 3)
            & $LogAction (Get-Str 'FilesRestored' -FormatArgs @($obj.files_restored, $restoredGB))
        } elseif ($obj -and $obj.message_type -eq "error") {
            $sawAnyProblem = $true
            $msg = [string]$obj.error.message
            # Known benign: Windows SeRestorePrivilege limitation setting a
            # timestamp on the synthetic path-mirroring root — data is fine.
            if ($msg -notmatch "failed to restore timestamp") { $benignOnly = $false }
            & $LogAction "ERROR: $msg"
        } elseif ($line) {
            & $LogAction $line
        }
    }
    $exitCode = $LASTEXITCODE

    $success = $false
    if ($exitCode -eq 0) {
        $success = $true
    } elseif ($sawAnyProblem -and $benignOnly) {
        & $LogAction (Get-Str 'TimestampQuirk')
        $success = $true
    }

    if ($success) {
        & $LogAction (Get-Str 'RestoreDoneAt' -FormatArgs @($RestoreTarget))
        return $RestoreTarget
    } else {
        & $LogAction (Get-Str 'CallForHelp')
        return $null
    }
}

# =============================================================================
# SEARCH
# =============================================================================

function Search-BackupFiles {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][string]$Term,
        [scriptblock]$LogAction = { param($line) }
    )

    $cfg = Import-BackupConfig -ScriptRoot $ScriptRoot
    $Tag = "docs-daily"
    $pattern = "*$Term*"

    $repos = @(@{ Label = "Local"; Path = $cfg.LocalRepoPath; PasswordFile = $cfg.PasswordFile })
    $extPath = Get-ExternalDrivePath -Label $cfg.ExternalDriveLabel -Subpath $cfg.ExternalRepoSubpath
    if ($extPath) {
        $repos += @{ Label = "External"; Path = $extPath; PasswordFile = $cfg.PasswordFile }
    }

    $anyRepoExists = $false
    $allResults = @()

    foreach ($repo in $repos) {
        & $LogAction (Get-Str 'CheckingRepo' -FormatArgs @($repo.Label))
        & restic -r $repo.Path --password-file $repo.PasswordFile snapshots --json 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $LogAction (Get-Str 'RepoNotFoundSkip' -FormatArgs @($repo.Label))
            continue
        }
        $anyRepoExists = $true

        & $LogAction (Get-Str 'SearchingRepo' -FormatArgs @($repo.Label, $Term))
        $json = & restic -r $repo.Path --password-file $repo.PasswordFile find --ignore-case --json $pattern 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) {
            & $LogAction (Get-Str 'NoMatchesInRepo' -FormatArgs @($repo.Label))
            continue
        }
        $groups = $json | ConvertFrom-Json
        if (-not $groups) {
            & $LogAction (Get-Str 'NoMatchesInRepo' -FormatArgs @($repo.Label))
            continue
        }

        $snapJson = & restic -r $repo.Path --password-file $repo.PasswordFile snapshots --tag $Tag --json 2>$null
        $dates = @{}
        if ($LASTEXITCODE -eq 0 -and $snapJson) {
            foreach ($s in ($snapJson | ConvertFrom-Json)) {
                $dates[$s.id] = ([datetime]$s.time).ToString("yyyy-MM-dd HH:mm")
            }
        }

        $repoMatchCount = 0
        foreach ($group in $groups) {
            $snapDate = if ($dates.ContainsKey($group.snapshot)) { $dates[$group.snapshot] } else { "unknown date" }
            foreach ($m in $group.matches) {
                if ($m.type -eq "file") {
                    $repoMatchCount++
                    $allResults += [PSCustomObject]@{
                        "Backup Date" = $snapDate
                        "Location"    = $repo.Label
                        "File"        = Split-Path $m.path -Leaf
                        "Folder"      = Split-Path $m.path -Parent
                        "Size (KB)"   = [math]::Round($m.size / 1KB, 1)
                        FullPath      = $m.path
                        SnapshotId    = $group.snapshot
                        RepoPath      = $repo.Path
                        RepoPassword  = $repo.PasswordFile
                    }
                }
            }
        }
        & $LogAction (Get-Str 'FoundInRepo' -FormatArgs @($repoMatchCount, $repo.Label))
    }

    if (-not $anyRepoExists) {
        return [PSCustomObject]@{ RepoFound = $false; Matches = @() }
    }
    return [PSCustomObject]@{ RepoFound = $true; Matches = $allResults }
}

function Invoke-FileRestore {
    param(
        [Parameter(Mandatory)]$Selected,
        [Parameter(Mandatory)][scriptblock]$LogAction
    )

    $RestoreDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Restored-File-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
    New-Item -ItemType Directory -Force -Path $RestoreDir | Out-Null
    $RestoreFile = Join-Path $RestoreDir $Selected.File

    & $LogAction (Get-Str 'RestoringFile' -FormatArgs @($Selected.File, $Selected.'Backup Date', $Selected.Location))

    $stderrFile = [System.IO.Path]::GetTempFileName()
    & restic -r $Selected.RepoPath --password-file $Selected.RepoPassword dump $Selected.SnapshotId $Selected.FullPath > $RestoreFile 2>$stderrFile
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Get-Content $stderrFile -ErrorAction SilentlyContinue | ForEach-Object { & $LogAction $_ }
    }
    Remove-Item $stderrFile -ErrorAction SilentlyContinue

    if ($exitCode -eq 0 -and (Test-Path $RestoreFile) -and (Get-Item $RestoreFile).Length -gt 0) {
        & $LogAction (Get-Str 'FileDoneAt' -FormatArgs @($RestoreFile))
        return $RestoreDir
    } else {
        & $LogAction (Get-Str 'FileRestoreErr')
        Remove-Item $RestoreFile -ErrorAction SilentlyContinue
        return $null
    }
}

function Invoke-DocsUpdate {
    param(
        [string]$ScriptRoot,
        [scriptblock]$LogAction
    )

    function Send-Log { param($Line, [switch]$IsWarning)
        $prefix = if ($IsWarning) { "WARNING: " } else { "" }
        & $LogAction "$prefix$Line"
    }
    function Send-Progress { param([int]$Pct) & $LogAction "PROGRESS:$Pct" }

    $RepoRoot  = Split-Path $ScriptRoot -Parent
    $GiteaHost = '192.0.2.10'   
    $GiteaPort = 222             

    Send-Progress 0
    $reachable = Test-NetConnection -ComputerName $GiteaHost -Port $GiteaPort `
                    -WarningAction SilentlyContinue -InformationLevel Quiet
    if (-not $reachable) {
        Send-Log (Get-Str 'UpdateUnreachable') -IsWarning
        return $false
    }

    Send-Progress 25
    Send-Log (Get-Str 'UpdateForcing') -IsWarning

    Push-Location $RepoRoot
    try {
        $oldHash = (git rev-parse HEAD).Trim()

        git fetch origin 2>&1 | ForEach-Object { Send-Log $_ }
        if ($LASTEXITCODE -ne 0) { Send-Log (Get-Str 'UpdateFetchFailed' -FormatArgs @($LASTEXITCODE)) -IsWarning; return $false }

        Send-Progress 50
        git reset --hard origin/main 2>&1 | ForEach-Object { Send-Log $_ }
        if ($LASTEXITCODE -ne 0) { Send-Log (Get-Str 'UpdateResetFailed' -FormatArgs @($LASTEXITCODE)) -IsWarning; return $false }

        git clean -fd 2>&1 | ForEach-Object { Send-Log $_ }

        $newHash = (git rev-parse HEAD).Trim()
        if ($oldHash -ne $newHash) {
            $changedFiles = git diff --name-only $oldHash $newHash
            if ($changedFiles -contains "bin/backup-helper-launcher.ps1") {
                & $LogAction "LAUNCHER_CHANGED:1"
            }
        }
    } finally {
        Pop-Location
    }

    Send-Progress 75
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Backup Helper.lnk'
    if (-not (Test-Path $shortcutPath)) {
        Send-Log (Get-Str 'ShortcutMissing')
        & (Join-Path $ScriptRoot 'create-shortcut.ps1')
    }

    $testArgs = if ($env:BACKUP_HELPER_TEST_MODE -eq "1") { @("-Test") } else { @() }
    & (Join-Path $ScriptRoot 'setup-scheduled-task.ps1') @testArgs 2>&1 | ForEach-Object { Send-Log $_ }

    Send-Progress 100
    return $true
}

Export-ModuleMember -Function *