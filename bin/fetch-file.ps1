<#
=============================================================================
 fetch-file.ps1
 Thin CLI wrapper — logic lives in lib/backup-common.psm1.
=============================================================================
#>

param([switch]$Test)

if ($Test) { $env:BACKUP_HELPER_TEST_MODE = "1" }

Import-Module (Join-Path $PSScriptRoot "..\lib\backup-common.psm1") -Force

if (-not (Test-ResticAvailable)) {
    Write-Host "Something is wrong — the backup tool isn't installed. Please call for help." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

if (-not (Test-AnyRepoExists -ScriptRoot $PSScriptRoot)) {
    Write-Host "ERROR: no backups exist yet — nothing to search." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

$LogAction = { param($line) Write-Host $line -ForegroundColor Cyan }

Write-Host ""
Write-Host "=== Find an old version of a file ===" -ForegroundColor Cyan
Write-Host "Type part of a file name (e.g. 'invoice' or 'march') to search all backups." -ForegroundColor Cyan
Write-Host ""

$keepGoing = $true
while ($keepGoing) {
    $term = Read-Host "Search for"
    if ([string]::IsNullOrWhiteSpace($term)) { break }

    Write-Host "Searching..." -ForegroundColor Yellow
    $results = Search-BackupFiles -ScriptRoot $PSScriptRoot -Term $term -LogAction $LogAction

    if ($null -eq $results) {
        Write-Host "No backups are set up yet — nothing to search." -ForegroundColor Yellow
        continue
    }
    if ($results.Count -eq 0) {
        Write-Host "No files found matching '$term'. Try a different search." -ForegroundColor Yellow
        continue
    }

    $selected = $results | Sort-Object "Backup Date" -Descending |
        Out-GridView -Title "Found $($results.Count) match(es) for '$term' — select one or more (Ctrl/Shift-click) to restore" -OutputMode Multiple

    if ($selected) {
        foreach ($item in $selected) {
            $result = Invoke-FileRestore -Selected $item -LogAction $LogAction
            if ($result) { Invoke-Item $result }
        }
    }

    Write-Host ""
    $again = Read-Host "Search for another file? (Enter to search again, type 'n' to quit)"
    if ($again -eq "n") { $keepGoing = $false }
}

Write-Host "Done."
Read-Host "Press Enter to close"