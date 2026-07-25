# bin/Invoke-Update.ps1
param([switch]$Silent)
$ScriptRoot = $PSScriptRoot
Import-Module (Join-Path $ScriptRoot "..\lib\backup-common.psm1") -Force
$LogAction = { param($line) if (-not $Silent) { Write-Host $line } }
$success = Invoke-DocsUpdate -ScriptRoot $ScriptRoot -LogAction $LogAction
if (-not $Silent) {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = if ($success) { "Updated successfully." } else { "Update failed — see console output." }
    [System.Windows.Forms.MessageBox]::Show($msg, 'Update', 'OK', $(if ($success) { 'Information' } else { 'Warning' })) | Out-Null
}