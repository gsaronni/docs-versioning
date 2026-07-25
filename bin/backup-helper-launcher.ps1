<#
=============================================================================
 backup-helper-launcher.ps1
 Full GUI — everything happens inside this window, no console windows.
 No Application.DoEvents() anywhere. One Timer, registered once, drives
 Backup/Restore/Search progress via $script: state only.
=============================================================================
#>

param([switch]$Test)

if ($Test) { $env:BACKUP_HELPER_TEST_MODE = "1" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptRoot = $PSScriptRoot
Import-Module (Join-Path $ScriptRoot "..\lib\backup-common.psm1") -Force

# =============================================================================
# UI
# =============================================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = if ($Test) { "Backup Helper — TEST MODE" } else { "Backup Helper" }
$form.Size = New-Object System.Drawing.Size(560, 500)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = $form.Size

$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = "Back Up Now"
$btnBackup.Size = New-Object System.Drawing.Size(160, 40)
$btnBackup.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($btnBackup)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore Latest Backup"
$btnRestore.Size = New-Object System.Drawing.Size(160, 40)
$btnRestore.Location = New-Object System.Drawing.Point(190, 20)
$form.Controls.Add($btnRestore)

$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Text = "Find an Old File"
$btnFind.Size = New-Object System.Drawing.Size(160, 40)
$btnFind.Location = New-Object System.Drawing.Point(360, 20)
$form.Controls.Add($btnFind)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Size = New-Object System.Drawing.Size(100, 30)
$btnStop.Location = New-Object System.Drawing.Point(20, 65)
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "Update"
$btnUpdate.Size = New-Object System.Drawing.Size(100, 30)
$btnUpdate.Location = New-Object System.Drawing.Point(360, 65)
$form.Controls.Add($btnUpdate)

# Must join the same group Backup/Restore/Find are in, so it disables
# them during an update and vice versa.
$AllButtons = @($btnBackup, $btnRestore, $btnFind, $btnUpdate)

$btnUpdate.Add_Click({
    try {
        Start-BackgroundOperation -OperationName "Update" -Operation {
            param($ScriptRoot, $LogQueue)
            Import-Module (Join-Path $ScriptRoot "..\lib\backup-common.psm1") -Force
            $LogAction = { param($line) $LogQueue.Enqueue([string]$line) }
            Invoke-DocsUpdate -ScriptRoot $ScriptRoot -LogAction $LogAction
        }
    } catch {
        foreach ($b in $AllButtons) { $b.Enabled = $true }
        $btnStop.Enabled = $false
        $statusLabel.Text = "Ready"
        [System.Windows.Forms.MessageBox]::Show("Something went wrong:`r`n`r`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
    }
})

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready"
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(135, 73)
$form.Controls.Add($statusLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 100)
$progressBar.Size = New-Object System.Drawing.Size(440, 20)
$progressBar.Anchor = "Top,Left,Right"
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)

$percentLabel = New-Object System.Windows.Forms.Label
$percentLabel.Text = ""
$percentLabel.AutoSize = $false
$percentLabel.Size = New-Object System.Drawing.Size(60, 20)
$percentLabel.Location = New-Object System.Drawing.Point(465, 100)
$percentLabel.Anchor = "Top,Right"
$percentLabel.TextAlign = "MiddleLeft"
$form.Controls.Add($percentLabel)

$outputBox = New-Object System.Windows.Forms.RichTextBox
$outputBox.Location = New-Object System.Drawing.Point(20, 130)
$outputBox.Size = New-Object System.Drawing.Size(500, 310)
$outputBox.Anchor = "Top,Bottom,Left,Right"
$outputBox.ReadOnly = $true
$outputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$outputBox.BackColor = [System.Drawing.Color]::Black
$outputBox.ForeColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($outputBox)

$AllButtons = @($btnBackup, $btnRestore, $btnFind)

function Add-Output {
    param($text, $color = [System.Drawing.Color]::LightGreen)
    $outputBox.SelectionStart = $outputBox.TextLength
    $outputBox.SelectionColor = $color
    $outputBox.AppendText("$text`r`n")
    $outputBox.SelectionStart = $outputBox.TextLength
    $outputBox.ScrollToCaret()
}

function Show-InputDialog {
    param([string]$Prompt, [string]$Title)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(420, 150)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $dlg.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(15, 45)
    $txt.Size = New-Object System.Drawing.Size(375, 25)
    $dlg.Controls.Add($txt)
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(215, 80)
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(295, 80)
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel
    $result = $dlg.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $txt.Text }
    return $null
}

function Show-SearchResultsAndContinue {
    param($Results)

    if ($null -eq $Results) {
        [System.Windows.Forms.MessageBox]::Show("No backups are set up yet — nothing to search.", "Nothing to Search", "OK", "Warning") | Out-Null
        return
    }
    if ($Results.Count -eq 0) {
        $again = [System.Windows.Forms.MessageBox]::Show("No files found. Search again?", "No Matches", "YesNo", "Information")
        if ($again -eq [System.Windows.Forms.DialogResult]::Yes) {
            $term = Show-InputDialog -Prompt "Type part of a file name (e.g. 'invoice' or 'march'):" -Title "Find an Old File"
            if (-not [string]::IsNullOrWhiteSpace($term)) { Start-SearchOperation -Term $term }
        }
        return
    }

    $selected = $Results | Sort-Object "Backup Date" -Descending |
        Out-GridView -Title "Found $($Results.Count) match(es) — select one or more (Ctrl/Shift-click) to restore" -OutputMode Multiple

    if ($selected) {
        foreach ($item in $selected) {
            $LogAction = { param($line) Add-Output $line }
            $result = Invoke-FileRestore -Selected $item -LogAction $LogAction
            if ($result) { Invoke-Item $result }
        }
    }
}

# =============================================================================
# BACKGROUND OPERATION STATE
# =============================================================================

$script:ActivePS = $null
$script:ActiveRunspace = $null
$script:ActiveAsyncResult = $null
$script:ActiveLogQueue = $null
$script:ActiveOperationName = $null
$script:ActiveBaseStatus = $null
$script:ActiveRestoreTarget = $null
$script:SpinnerChars = @('|', '/', '-', '\')
$script:SpinnerIndex = 0

# Handles one drained log line: intercepts internal PROGRESS:/RESTORE_TARGET:
# markers (updates the bar / remembers the path, never printed to the box)
# and prints everything else normally.
function Receive-LogLine {
    param([string]$Line)

    if ($Line -like "PROGRESS:*") {
        $pct = 0
        if ([int]::TryParse($Line.Substring(9), [ref]$pct)) {
            $pct = [Math]::Max(0, [Math]::Min(100, $pct))
            $progressBar.Value = $pct
            $percentLabel.Text = "$pct%"
        }
        return
    }
    if ($Line -like "RESTORE_TARGET:*") {
        $script:ActiveRestoreTarget = $Line.Substring(15)
        return
    }

    $color = $(if ($Line -like "ERROR:*") { [System.Drawing.Color]::Red } else { [System.Drawing.Color]::LightGreen })
    Add-Output $Line $color
}

function Start-BackgroundOperation {
    param([string]$OperationName, [scriptblock]$Operation, [string]$ExtraArg)

    foreach ($b in $AllButtons) { $b.Enabled = $false }
    if ($OperationName -ne "Search") { $btnStop.Enabled = $true }
    $script:ActiveBaseStatus = if ($OperationName -eq "Search") { "Searching" } else { "Working" }
    $statusLabel.Text = "$($script:ActiveBaseStatus)... $($script:SpinnerChars[0])"
    $script:ActiveRestoreTarget = $null

    if ($OperationName -eq "Search") {
        # restic find/snapshots return one complete document, not a
        # streaming progress feed — there's no percent_done to show
        # honestly, so use an indeterminate marquee instead of a fake number.
        $progressBar.Style = "Marquee"
        $progressBar.MarqueeAnimationSpeed = 30
        $percentLabel.Text = ""
    } else {
        $progressBar.Style = "Blocks"
        $progressBar.Value = 0
        $percentLabel.Text = "0%"
    }

    Add-Output "--- $OperationName started ---" ([System.Drawing.Color]::White)

    $script:ActiveLogQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $script:ActiveOperationName = $OperationName
    $script:ActiveRunspace = [runspacefactory]::CreateRunspace()
    $script:ActiveRunspace.Open()
    $script:ActivePS = [powershell]::Create()
    $script:ActivePS.Runspace = $script:ActiveRunspace

    $ps = $script:ActivePS.AddScript($Operation).AddArgument($ScriptRoot).AddArgument($script:ActiveLogQueue)
    if ($ExtraArg) { [void]$ps.AddArgument($ExtraArg) }

    $script:ActiveAsyncResult = $script:ActivePS.BeginInvoke()
    $pollTimer.Start()
}

function Start-SearchOperation {
    param([string]$Term)
    Start-BackgroundOperation -OperationName "Search" -ExtraArg $Term -Operation {
        param($ScriptRoot, $LogQueue, $Term)
        Import-Module (Join-Path $ScriptRoot "..\lib\backup-common.psm1") -Force
        $LogAction = { param($line) $LogQueue.Enqueue([string]$line) }
        Search-BackupFiles -ScriptRoot $ScriptRoot -Term $Term -LogAction $LogAction
    }
}

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 200
$pollTimer.Add_Tick({
    if (-not $script:ActivePS) { return }
    try {
        $script:SpinnerIndex = ($script:SpinnerIndex + 1) % $script:SpinnerChars.Count
        $statusLabel.Text = "$($script:ActiveBaseStatus)... $($script:SpinnerChars[$script:SpinnerIndex])"

        while ($script:ActiveLogQueue.Count -gt 0) {
            Receive-LogLine -Line $script:ActiveLogQueue.Dequeue()
        }

        if ($script:ActiveAsyncResult.IsCompleted) {
            $pollTimer.Stop()

            while ($script:ActiveLogQueue.Count -gt 0) {
                Receive-LogLine -Line $script:ActiveLogQueue.Dequeue()
            }

            $wasStopped = $script:ActivePS.InvocationStateInfo.State -eq 'Stopped'
            $rawResults = $null
            if (-not $wasStopped) {
                try { $rawResults = $script:ActivePS.EndInvoke($script:ActiveAsyncResult) } catch { $rawResults = $null }
            }
            $script:ActivePS.Dispose()
            $script:ActiveRunspace.Close()

            $opName = $script:ActiveOperationName
            $restoreTarget = $script:ActiveRestoreTarget
            $script:ActivePS = $null
            $script:ActiveRunspace = $null
            $script:ActiveAsyncResult = $null
            $script:ActiveLogQueue = $null
            $script:ActiveOperationName = $null
            $script:ActiveRestoreTarget = $null

            $btnStop.Enabled = $false
            foreach ($b in $AllButtons) { $b.Enabled = $true }

            if ($opName -eq "Search") {
                $statusLabel.Text = "Ready"
                $progressBar.Style = "Blocks"
                $progressBar.Value = 0
                $percentLabel.Text = ""
                Add-Output "--- Search completed ---" ([System.Drawing.Color]::White)
                Show-SearchResultsAndContinue -Results $rawResults
                return
            }

            if ($wasStopped) {
                $statusLabel.Text = "Stopped"
                $progressBar.Value = 0
                $percentLabel.Text = ""
                Add-Output "--- $opName stopped by user ---" ([System.Drawing.Color]::Yellow)

                # Clean up whatever a stopped restore had partially written —
                # never leave dirty/incomplete files sitting on the Desktop.
                if ($opName -eq "Restore" -and $restoreTarget -and (Test-Path $restoreTarget)) {
                    Remove-Item -Path $restoreTarget -Recurse -Force -ErrorAction SilentlyContinue
                    Add-Output "Cleaned up partial restore files." ([System.Drawing.Color]::Yellow)
                }
                return
            }

            $lastResult = $rawResults | Select-Object -Last 1
            $success = [bool]$lastResult

            if ($success) {
                $statusLabel.Text = "Ready"
                $progressBar.Value = 100
                $percentLabel.Text = "100%"
                Add-Output "--- $opName completed ---" ([System.Drawing.Color]::White)
                if ($opName -eq "Restore" -and ($lastResult -is [string])) { Invoke-Item $lastResult }
            } else {
                $statusLabel.Text = "Failed — see messages above"
                Add-Output "--- $opName FAILED — see errors above ---" ([System.Drawing.Color]::Red)
            }
        }
    } catch {
        $pollTimer.Stop()
        try { $script:ActivePS.Dispose(); $script:ActiveRunspace.Close() } catch {}
        $script:ActivePS = $null
        $script:ActiveRunspace = $null
        $script:ActiveAsyncResult = $null
        $script:ActiveLogQueue = $null
        $btnStop.Enabled = $false
        foreach ($b in $AllButtons) { $b.Enabled = $true }
        $statusLabel.Text = "Ready"
        [System.Windows.Forms.MessageBox]::Show("Something went wrong:`r`n`r`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
    }
})

$btnBackup.Add_Click({
    try {
        $problem = Test-BackupConfigReady -ScriptRoot $ScriptRoot
        if ($problem) {
            [System.Windows.Forms.MessageBox]::Show($problem, "Can't Back Up Yet", "OK", "Warning") | Out-Null
            return
        }
        Start-BackgroundOperation -OperationName "Backup" -Operation {
            param($ScriptRoot, $LogQueue)
            Import-Module (Join-Path $ScriptRoot "..\lib\backup-common.psm1") -Force
            $LogAction = { param($line) $LogQueue.Enqueue([string]$line) }
            Invoke-DocumentBackup -ScriptRoot $ScriptRoot -LogAction $LogAction
        }
    } catch {
        foreach ($b in $AllButtons) { $b.Enabled = $true }
        $btnStop.Enabled = $false
        $statusLabel.Text = "Ready"
        [System.Windows.Forms.MessageBox]::Show("Something went wrong:`r`n`r`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
    }
})

$btnRestore.Add_Click({
    try {
        if (-not (Test-ResticAvailable)) {
            [System.Windows.Forms.MessageBox]::Show("The backup tool isn't installed. Please call for help.", "Can't Restore Yet", "OK", "Warning") | Out-Null
            return
        }
        if (-not (Test-AnyRepoExists -ScriptRoot $ScriptRoot)) {
            [System.Windows.Forms.MessageBox]::Show("No backups exist yet — nothing to restore.", "Can't Restore Yet", "OK", "Warning") | Out-Null
            return
        }

        $spaceCheck = Test-EnoughRestoreSpace -ScriptRoot $ScriptRoot
        if ($spaceCheck -and -not $spaceCheck.Enough) {
            $neededGB = [math]::Round($spaceCheck.NeededBytes / 1GB, 1)
            $freeGB = [math]::Round($spaceCheck.FreeBytes / 1GB, 1)
            [System.Windows.Forms.MessageBox]::Show(
                "Not enough disk space to restore.`r`n`r`nNeeded (approx): $neededGB GB`r`nAvailable: $freeGB GB`r`n`r`nFree up space and try again.",
                "Not Enough Space", "OK", "Warning") | Out-Null
            return
        }

        Start-BackgroundOperation -OperationName "Restore" -Operation {
            param($ScriptRoot, $LogQueue)
            Import-Module (Join-Path $ScriptRoot "..\lib\backup-common.psm1") -Force
            $LogAction = { param($line) $LogQueue.Enqueue([string]$line) }
            Invoke-LatestRestore -ScriptRoot $ScriptRoot -LogAction $LogAction
        }
    } catch {
        foreach ($b in $AllButtons) { $b.Enabled = $true }
        $btnStop.Enabled = $false
        $statusLabel.Text = "Ready"
        [System.Windows.Forms.MessageBox]::Show("Something went wrong:`r`n`r`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
    }
})

$btnStop.Add_Click({
    if ($script:ActivePS) {
        try { $script:ActivePS.Stop() } catch {}
        Add-Output "--- Stop requested — finishing current step... ---" ([System.Drawing.Color]::Yellow)
        $btnStop.Enabled = $false
    }
})

$btnFind.Add_Click({
    try {
        if (-not (Test-ResticAvailable)) {
            [System.Windows.Forms.MessageBox]::Show("The backup tool isn't installed. Please call for help.", "Error", "OK", "Error") | Out-Null
            return
        }
        $term = Show-InputDialog -Prompt "Type part of a file name (e.g. 'invoice' or 'march'):" -Title "Find an Old File"
        if ([string]::IsNullOrWhiteSpace($term)) { return }
        Start-SearchOperation -Term $term
    } catch {
        $statusLabel.Text = "Ready"
        [System.Windows.Forms.MessageBox]::Show("Something went wrong:`r`n`r`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
    }
})

[void]$form.ShowDialog()