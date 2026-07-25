<#
=============================================================================
 create-shortcut.ps1
 Run this ONCE to create a real double-clickable desktop shortcut for
 Backup Helper. No compilation, no ps2exe, no console window for the
 person using it — just a plain .lnk pointing at pwsh.exe with the
 console hidden.
=============================================================================
#>

param(
    # Confirmed working icon, read directly from a shortcut where it was
    # applied via Windows' own Change Icon picker — not a guess.
    [string]$IconPath = "$env:SystemRoot\System32\imageres.dll,270"
)

$LauncherPath = Join-Path $PSScriptRoot "backup-helper-launcher.ps1"
$ShortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Backup Helper.lnk"

if (-not (Test-Path $LauncherPath)) {
    Write-Host "ERROR: backup-helper-launcher.ps1 not found next to this script." -ForegroundColor Red
    exit 1
}

# Handles both plain "file.ico" and "file.dll,77" (index) forms — only
# the part before a trailing ",<number>" is an actual file to check.
function Test-IconPath {
    param([string]$Path)
    if ($Path -match '^(.+),(-?\d+)$') {
        return Test-Path $Matches[1]
    }
    return Test-Path $Path
}

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "pwsh.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -File `"$LauncherPath`""
$Shortcut.WorkingDirectory = $PSScriptRoot
$Shortcut.Description = "Backup Helper"

if (Test-IconPath $IconPath) {
    $Shortcut.IconLocation = $IconPath
} else {
    Write-Host "WARNING: icon not found ($IconPath) — using the default icon instead." -ForegroundColor Yellow
}

$Shortcut.Save()

Write-Host "Shortcut created: $ShortcutPath" -ForegroundColor Green
Write-Host "Double-click it to test — should open the Backup Helper window with no console visible." -ForegroundColor Green