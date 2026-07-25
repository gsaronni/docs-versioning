<#
=============================================================================
 fetch-file.ps1
 Search across all backups for a file by name (or partial name), pick the
 version you want in a clickable table, and restore just that one file to
 a new folder on the Desktop. Never touches your existing files.
=============================================================================
#>

$ConfigPath = Join-Path $PSScriptRoot "..\etc\backup-config.psd1"
$cfg = Import-PowerShellDataFile $ConfigPath

$env:RESTIC_REPOSITORY    = $cfg.LocalRepoPath
$env:RESTIC_PASSWORD_FILE = $cfg.PasswordFile

if (-not (Get-Command restic -ErrorAction SilentlyContinue)) {
    Write-Host "Something is wrong — the backup tool isn't installed. Please call for help." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

function Get-SnapshotDates {
    # Builds an ID -> date lookup, since `restic find` returns the snapshot
    # ID but not its date. Without this, results would show a meaningless
    # hash instead of "this version is from July 20th."
    $json = & restic snapshots --tag docs-daily --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return @{} }
    $snaps = $json | ConvertFrom-Json
    $lookup = @{}
    foreach ($s in $snaps) {
        $lookup[$s.id] = ([datetime]$s.time).ToString("yyyy-MM-dd HH:mm")
    }
    return $lookup
}

function Search-Files {
    param([string]$Term)
    $pattern = "*$Term*"
    $json = & restic find --ignore-case --json $pattern 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
    $groups = $json | ConvertFrom-Json
    if (-not $groups) { return @() }

    $dates = Get-SnapshotDates
    $rows = foreach ($group in $groups) {
        $snapDate = if ($dates.ContainsKey($group.snapshot)) { $dates[$group.snapshot] } else { "unknown date" }
        foreach ($m in $group.matches) {
            if ($m.type -eq "file") {
                [PSCustomObject]@{
                    "Backup Date"  = $snapDate
                    "File"         = Split-Path $m.path -Leaf
                    "Folder"       = Split-Path $m.path -Parent
                    "Size (KB)"    = [math]::Round($m.size / 1KB, 1)
                    FullPath       = $m.path
                    SnapshotId     = $group.snapshot
                }
            }
        }
    }
    return $rows
}

function Restore-SelectedFile {
    param($Selected)
    $RestoreTarget = Join-Path ([Environment]::GetFolderPath("Desktop")) "Restored-File-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"

    Write-Host ""
    Write-Host "Restoring '$($Selected.File)' from $($Selected.'Backup Date')..." -ForegroundColor Cyan

    restic restore $Selected.SnapshotId --target $RestoreTarget --include $Selected.FullPath

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Done! Your file is here:" -ForegroundColor Green
        Write-Host $RestoreTarget -ForegroundColor Green
        Invoke-Item $RestoreTarget
    } else {
        Write-Host "Something went wrong restoring that file. Please call for help." -ForegroundColor Red
    }
}

# =============================================================================
# MAIN LOOP
# =============================================================================

Write-Host ""
Write-Host "=== Find an old version of a file ===" -ForegroundColor Cyan
Write-Host "Type part of a file name (e.g. 'invoice' or 'march') to search all backups." -ForegroundColor Cyan
Write-Host ""

$keepGoing = $true

while ($keepGoing) {
    $term = Read-Host "Search for"

    if ([string]::IsNullOrWhiteSpace($term)) {
        $keepGoing = $false
        break
    }

    Write-Host "Searching..." -ForegroundColor Yellow
    $results = Search-Files -Term $term

    if ($results.Count -eq 0) {
        Write-Host "No files found matching '$term'. Try a different search." -ForegroundColor Yellow
        continue
    }

    $selected = $results | Sort-Object "Backup Date" -Descending |
        Out-GridView -Title "Found $($results.Count) match(es) for '$term' — select one to restore, or close this window to search again" -OutputMode Single

    if (-not $selected) {
        Write-Host "No selection made." -ForegroundColor Yellow
    } else {
        Restore-SelectedFile -Selected $selected
    }

    Write-Host ""
    $again = Read-Host "Search for another file? (Enter to search again, type 'n' to quit)"
    if ($again -eq "n") { $keepGoing = $false }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Read-Host "Press Enter to close"
