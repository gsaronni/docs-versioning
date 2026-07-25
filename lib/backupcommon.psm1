<#
=============================================================================
 BackupCommon.psm1
 Shared functions used identically across backup-documents.ps1,
 restore-latest.ps1, and fetch-file.ps1. Deliberately minimal — only what
 genuinely duplicated across all three, not a catch-all for anything
 single-script-specific (day-gating, logging, external-drive detection
 stay local to backup-documents.ps1, since only it needs them).
=============================================================================
#>

function Import-BackupConfig {
    param([string]$ScriptRoot)

    $ConfigPath = Join-Path $ScriptRoot "..\etc\backup-config.psd1"
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
        exit 1
    }

    $cfg = Import-PowerShellDataFile $ConfigPath
    $env:RESTIC_REPOSITORY    = $cfg.LocalRepoPath
    $env:RESTIC_PASSWORD_FILE = $cfg.PasswordFile

    return $cfg
}

function Test-ResticAvailable {
    if (-not (Get-Command restic -ErrorAction SilentlyContinue)) {
        Write-Host "Something is wrong — the backup tool isn't installed. Please call for help." -ForegroundColor Red
        Read-Host "Press Enter to close"
        exit 1
    }
}
