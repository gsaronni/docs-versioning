<#
=============================================================================
 BackupHelper-Launcher.ps1
 Thin WinForms front door over the existing scripts. Each button just runs
 the same .ps1 you already test manually via CLI — nothing here duplicates
 their logic, it only launches them. CLI usage stays completely unaffected;
 this is an additional layer, not a replacement. Task Scheduler bypasses
 this entirely and calls backup-documents.ps1 directly, as before.
=============================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$BinDir = $PSScriptRoot

function Start-BackupScript {
    param([string]$ScriptName)
    $scriptPath = Join-Path $BinDir $ScriptName
    # -NoExit keeps the window open after the script finishes so results
    # stay visible — matters here since a GUI button click has no one
    # sitting at a command line already watching. Task Scheduler's own
    # direct invocation of these scripts is untouched by this at all.
    Start-Process pwsh.exe -ArgumentList "-NoExit -File `"$scriptPath`""
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Backup Helper"
$form.Size = New-Object System.Drawing.Size(340, 260)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "What would you like to do?"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($title)

$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = "Back Up Now"
$btnBackup.Size = New-Object System.Drawing.Size(280, 40)
$btnBackup.Location = New-Object System.Drawing.Point(20, 60)
$btnBackup.Add_Click({ Start-BackupScript -ScriptName "backup-documents.ps1" })
$form.Controls.Add($btnBackup)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore Latest Backup"
$btnRestore.Size = New-Object System.Drawing.Size(280, 40)
$btnRestore.Location = New-Object System.Drawing.Point(20, 110)
$btnRestore.Add_Click({ Start-BackupScript -ScriptName "restore-latest.ps1" })
$form.Controls.Add($btnRestore)

$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Text = "Find an Old File"
$btnFind.Size = New-Object System.Drawing.Size(280, 40)
$btnFind.Location = New-Object System.Drawing.Point(20, 160)
$btnFind.Add_Click({ Start-BackupScript -ScriptName "fetch-file.ps1" })
$form.Controls.Add($btnFind)

[void]$form.ShowDialog()
