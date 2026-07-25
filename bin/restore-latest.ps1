<#
=============================================================================
 restore-latest.ps1
 Double-click recovery. No arguments, no snapshot IDs to remember.
 Restores the latest local backup to a new folder on the Desktop.
=============================================================================
#>

$ConfigPath = Join-Path $PSScriptRoot "..\etc\backup-config.psd1"
$cfg = Import-PowerShellDataFile $ConfigPath

$env:RESTIC_REPOSITORY    = $cfg.LocalRepoPath
$env:RESTIC_PASSWORD_FILE = $cfg.PasswordFile

$RestoreTarget = Join-Path ([Environment]::GetFolderPath("Desktop")) "Restored-Backup-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"

Write-Host ""
Write-Host "Restoring your most recent backup..." -ForegroundColor Cyan
Write-Host "This will create a new folder on your Desktop — it will NOT touch your existing files." -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command restic -ErrorAction SilentlyContinue)) {
    Write-Host "Something is wrong — the backup tool isn't installed. Please call for help." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

restic restore latest --tag docs-daily --target $RestoreTarget

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Done! Your files are here:" -ForegroundColor Green
    Write-Host $RestoreTarget -ForegroundColor Green
    Write-Host ""
    Invoke-Item $RestoreTarget
} else {
    Write-Host ""
    Write-Host "Something went wrong. Please call for help rather than trying more things." -ForegroundColor Red
}

Read-Host "Press Enter to close"
