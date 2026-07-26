<#
=============================================================================
 backup-documents.ps1
 Thin CLI wrapper — all real logic lives in lib/backup-common.psm1 now.
 Behaves identically to before: same console output, same log file.
=============================================================================
 Usage:
   pwsh.exe -File backup-documents.ps1              (live run)
   pwsh.exe -File backup-documents.ps1 -DryRun        (dry run)
   pwsh.exe -File backup-documents.ps1 -InitOnly      (just create the repo)
   pwsh.exe -File backup-documents.ps1 -Test          (use backup-config.test.psd1 instead)
=============================================================================
#>

param(
    [switch]$DryRun,
    [switch]$InitOnly,
    [switch]$Test
)

if ($Test) {
    $env:BACKUP_HELPER_TEST_MODE = "1"
} else {
    Remove-Item Env:\BACKUP_HELPER_TEST_MODE -ErrorAction SilentlyContinue
}

Import-Module (Join-Path $PSScriptRoot "..\lib\backup-common.psm1") -Force

$LogDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')-backup-documents.log"

$cutoff = (Get-Date).AddDays(-120)
Get-ChildItem -Path $LogDir -Filter "*-backup-documents.log" |
    Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force

$LogAction = {
    param($line)
    Write-Host $line
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $line"
}

if ($InitOnly) {
    Import-BackupConfig -ScriptRoot $PSScriptRoot | Out-Null
    & restic init
    exit 0
}

Invoke-DocumentBackup -ScriptRoot $PSScriptRoot -LogAction $LogAction -DryRun:$DryRun | Out-Null