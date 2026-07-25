<#
=============================================================================
 restore-latest.ps1
 Thin CLI wrapper — logic lives in lib/backup-common.psm1.
=============================================================================
#>

param([switch]$Test)

if ($Test) { $env:BACKUP_HELPER_TEST_MODE = "1" }

Import-Module (Join-Path $PSScriptRoot "..\lib\backup-common.psm1") -Force

$LogAction = {
    param($line)
    Write-Host $line -ForegroundColor Cyan
}

Write-Host ""
Write-Host "This will create a new folder on your Desktop — it will NOT touch your existing files." -ForegroundColor Cyan
Write-Host ""

$result = Invoke-LatestRestore -ScriptRoot $PSScriptRoot -LogAction $LogAction

if ($result) {
    Invoke-Item $result
}

Read-Host "Press Enter to close"