<#
=============================================================================
 backup-documents.ps1
 Standalone backup for dad's Documents\2026 — no bash, no WSL, fully
 self-contained PowerShell. Local repo (frequent) + external drive repo
 (replicated whenever the labeled drive is connected).
=============================================================================
 Usage:
   pwsh.exe -File backup-documents.ps1              (live run — gated to once per day)
   pwsh.exe -File backup-documents.ps1 -DryRun        (dry run — reports the gate, never skips or writes)
   pwsh.exe -File backup-documents.ps1 -InitOnly      (create the local repo only, then stop)
=============================================================================
#>

param(
    [switch]$DryRun,
    [switch]$InitOnly
)

# =============================================================================
# CONFIG
# =============================================================================

$ConfigPath = Join-Path $PSScriptRoot "..\etc\backup-config.psd1"
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$cfg = Import-PowerShellDataFile $ConfigPath

$SourcePath         = $cfg.SourcePath
$LocalRepoPath      = $cfg.LocalRepoPath
$PasswordFile       = $cfg.PasswordFile
$ExternalDriveLabel = $cfg.ExternalDriveLabel
$ExternalSubpath    = $cfg.ExternalRepoSubpath
$KeepDaily          = $cfg.KeepDaily
$KeepWeekly         = $cfg.KeepWeekly
$KeepMonthly        = $cfg.KeepMonthly
$LogRetentionDays   = $cfg.LogRetentionDays

$Tag   = "docs-daily"
$Today = Get-Date -Format "yyyy-MM-dd"

# =============================================================================
# LOGGING — self-sufficient, auto-generates its own timestamped log file.
# No -LogFile parameter here at all: this machine has nothing else to
# unify logs with, so there's no reason to make it configurable.
# =============================================================================

$LogDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')-backup-documents.log"

function Write-Log {
    param($level, $color, $msg)
    $line = "[$level]  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line
}

function Log-Info  { param($msg) Write-Log "INFO " "Green"  $msg }
function Log-Warn  { param($msg) Write-Log "WARN " "Yellow" $msg }
function Log-Error { param($msg) Write-Log "ERROR" "Red"    $msg }
function Log-Fatal  { param($msg) Log-Error $msg; exit 1 }

# Runs restic, writing each line to console AND log file explicitly —
# NOT via Tee-Object passthrough (that leaked output into a function's
# return value alongside $LASTEXITCODE during BG3 testing; learned that
# lesson once, not repeating it here).
function Invoke-LoggedRestic {
    param([string[]]$ResticArgs)
    & restic @ResticArgs 2>&1 | ForEach-Object {
        Write-Host $_
        Add-Content -Path $LogFile -Value $_
    }
    return $LASTEXITCODE
}

function Remove-OldLogs {
    $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
    $old = Get-ChildItem -Path $LogDir -Filter "*-backup-documents.log" | Where-Object { $_.LastWriteTime -lt $cutoff }
    if ($old.Count -gt 0) {
        Log-Info "Removing $($old.Count) log(s) older than $LogRetentionDays days"
        $old | Remove-Item -Force
    }
}

# Day-gate driven by the repo's own history — no separate marker file.
# Same design proven on BG3: ask restic directly whether the latest
# snapshot with this tag is already dated today.
function Test-AlreadyRanToday {
    param([string]$RepoPath, [string]$PwFile)
    $env:RESTIC_REPOSITORY   = $RepoPath
    $env:RESTIC_PASSWORD_FILE = $PwFile
    $json = & restic snapshots --tag $Tag --latest 1 --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $false }
    $snaps = $json | ConvertFrom-Json
    if (-not $snaps -or $snaps.Count -eq 0) { return $false }
    $lastDate = ([datetime]$snaps[0].time).ToString("yyyy-MM-dd")
    return ($lastDate -eq $Today)
}

# Finds the external drive by volume label rather than assuming a drive
# letter — letters aren't guaranteed stable across reconnects.
function Get-ExternalDrivePath {
    $vol = Get-Volume -FileSystemLabel $ExternalDriveLabel -ErrorAction SilentlyContinue
    if ($vol -and $vol.DriveLetter) {
        return "$($vol.DriveLetter):\$ExternalSubpath"
    }
    return $null
}

Remove-OldLogs

# =============================================================================
# PREFLIGHT
# =============================================================================

if ($SourcePath -like "*REPLACE_ME*") {
    Log-Fatal "backup-config.psd1's SourcePath still has the placeholder username — edit it before running."
}

if (-not (Get-Command restic -ErrorAction SilentlyContinue)) {
    Log-Fatal "restic not found in PATH. See setup notes for install steps."
}

if (-not (Test-Path $SourcePath)) {
    Log-Fatal "Source path does not exist: $SourcePath"
}

$localDriveRoot = Split-Path -Qualifier $LocalRepoPath
if (-not (Test-Path $localDriveRoot)) {
    Log-Fatal "$localDriveRoot is not accessible (local repo path: $LocalRepoPath)"
}

if (-not (Test-Path $PasswordFile)) {
    Log-Fatal "Password file not found: $PasswordFile — this must be created once during setup and never lost."
}

$env:RESTIC_REPOSITORY    = $LocalRepoPath
$env:RESTIC_PASSWORD_FILE = $PasswordFile

# =============================================================================
# LOCAL REPO INIT (idempotent)
# =============================================================================

Log-Info "Checking local repo at $LocalRepoPath"
& restic snapshots --json 2>&1 | Out-Null
$repoExists = $LASTEXITCODE -eq 0

if (-not $repoExists) {
    Log-Info "Local repo not found — initializing"
    if ($DryRun) {
        Log-Info "[DRY-RUN] Would run: restic init"
    } else {
        & restic init
        if ($LASTEXITCODE -ne 0) { Log-Fatal "restic init failed" }
        Log-Info "Local repo initialized"
    }
} else {
    Log-Info "Local repo already exists"
}

if ($InitOnly) {
    Log-Info "InitOnly flag set — stopping here"
    exit 0
}

# =============================================================================
# DAY-GATE
# =============================================================================

$alreadyRanToday = Test-AlreadyRanToday -RepoPath $LocalRepoPath -PwFile $PasswordFile

if ($alreadyRanToday) {
    if ($DryRun) {
        Log-Info "[DRY-RUN] Latest snapshot already dated today ($Today) — a live run would stop here; continuing anyway for inspection"
    } else {
        Log-Info "Latest snapshot already dated today ($Today) — skipping backup and retention"
        # Still worth checking the external drive even on a skipped day —
        # dad might connect it any time, independent of the backup schedule.
        $extPath = Get-ExternalDrivePath
        if ($extPath) {
            Log-Info "External drive detected ($ExternalDriveLabel) — checking for anything to copy"
            Invoke-LoggedRestic -ResticArgs @(
                "copy", "--repo", $LocalRepoPath, "--password-file", $PasswordFile,
                "--repo2", $extPath, "--password-file2", $PasswordFile,
                "--tag", $Tag
            ) | Out-Null
        }
        exit 0
    }
}

# =============================================================================
# LOCAL BACKUP
# =============================================================================

Log-Info "Starting backup of $SourcePath"

$backupArgs = @("backup", $SourcePath, "--tag", $Tag, "--skip-if-unchanged")

if ($DryRun) {
    $backupArgs += "--dry-run"
    Log-Info "[DRY-RUN] restic $($backupArgs -join ' ')"
}

$backupExit = Invoke-LoggedRestic -ResticArgs $backupArgs

if ($backupExit -eq 0) {
    Log-Info "Backup completed successfully"
} else {
    Log-Warn "Backup exited with code $backupExit — check output above"
}

# =============================================================================
# LOCAL RETENTION
# =============================================================================

Log-Info "Applying retention: keep-daily=$KeepDaily keep-weekly=$KeepWeekly keep-monthly=$KeepMonthly"

$forgetArgs = @(
    "forget", "--tag", $Tag,
    "--keep-daily", $KeepDaily,
    "--keep-weekly", $KeepWeekly,
    "--keep-monthly", $KeepMonthly,
    "--prune"
)

if ($DryRun) {
    $forgetArgs += "--dry-run"
    Log-Info "[DRY-RUN] restic $($forgetArgs -join ' ')"
}

$forgetExit = Invoke-LoggedRestic -ResticArgs $forgetArgs

if ($forgetExit -eq 0) {
    Log-Info "Retention applied successfully"
} else {
    Log-Warn "Retention exited with code $forgetExit — check output above"
}

# =============================================================================
# EXTERNAL DRIVE REPLICATION (only if connected — never fatal if absent)
# =============================================================================

$extPath = Get-ExternalDrivePath

if (-not $extPath) {
    Log-Info "External drive ($ExternalDriveLabel) not connected — skipping replication, will retry next run"
} else {
    Log-Info "External drive detected at $extPath"

    # Init the external repo if this is its first time seeing this drive.
    & restic -r $extPath --password-file $PasswordFile snapshots --json 2>&1 | Out-Null
    $extRepoExists = $LASTEXITCODE -eq 0

    if (-not $extRepoExists) {
        Log-Info "External repo not found — initializing"
        if ($DryRun) {
            Log-Info "[DRY-RUN] Would run: restic init on external drive"
        } else {
            & restic -r $extPath --password-file $PasswordFile init
            if ($LASTEXITCODE -ne 0) { Log-Fatal "External repo init failed" }
            Log-Info "External repo initialized"
        }
    }

    $copyArgs = @(
        "copy", "--repo", $LocalRepoPath, "--password-file", $PasswordFile,
        "--repo2", $extPath, "--password-file2", $PasswordFile,
        "--tag", $Tag
    )

    if ($DryRun) {
        Log-Info "[DRY-RUN] restic $($copyArgs -join ' ') (copy has no --dry-run flag; showing command only, not executing)"
    } else {
        $copyExit = Invoke-LoggedRestic -ResticArgs $copyArgs
        if ($copyExit -eq 0) {
            Log-Info "External replication completed successfully"
        } else {
            Log-Warn "External replication exited with code $copyExit — check output above"
        }
    }
}

# =============================================================================
# SUMMARY
# =============================================================================

Log-Info "Current local snapshots:"
$env:RESTIC_REPOSITORY = $LocalRepoPath
Invoke-LoggedRestic -ResticArgs @("snapshots", "--tag", $Tag, "--compact") | Out-Null

Log-Info "Done"
