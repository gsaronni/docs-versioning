<#
=============================================================================
 setup-scheduled-task.ps1
 Idempotent — safe to run repeatedly. Compares the desired configuration
 against whatever's currently registered (stored as a signature string in
 the task's own Description field) and only deletes+recreates if it's
 actually drifted. Same "apply from a file" pattern as Ansible/kubectl.

 Usage:
   pwsh.exe -File setup-scheduled-task.ps1             (real daily backup)
   pwsh.exe -File setup-scheduled-task.ps1 -Test        (separate TEST task,
                                                          points -Test at
                                                          backup-config.test.psd1,
                                                          never touches the
                                                          real task)
   pwsh.exe -File setup-scheduled-task.ps1 -Remove      (remove this task)
   pwsh.exe -File setup-scheduled-task.ps1 -Test -Remove
=============================================================================
#>

param(
    [switch]$Test,
    [switch]$Remove
)

$TaskFolder = "\Personal Backups\"
$TaskName = if ($Test) { "Daily Backup (TEST)" } else { "Daily Backup" }

$ScriptRoot = $PSScriptRoot
$BackupScript = Join-Path $ScriptRoot "backup-documents.ps1"

if (-not (Test-Path $BackupScript)) {
    Write-Host "ERROR: backup-documents.ps1 not found next to this script." -ForegroundColor Red
    exit 1
}

$PwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $PwshCommand) {
    Write-Host "ERROR: pwsh.exe not found in PATH." -ForegroundColor Red
    exit 1
}
$PwshPath = $PwshCommand.Source

$actionArgsList = @("-WindowStyle", "Hidden", "-File", "`"$BackupScript`"")
if ($Test) { $actionArgsList += "-Test" }
$actionArgs = $actionArgsList -join " "

$existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue

if ($Remove) {
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "Removed task '$TaskName' from '$TaskFolder'." -ForegroundColor Yellow
    } else {
        Write-Host "No task named '$TaskName' found under '$TaskFolder' — nothing to remove." -ForegroundColor Yellow
    }
    exit 0
}

# The desired configuration, canonicalized to a single string. If this
# doesn't match what's already registered, we know something drifted.
$DesiredSignature = (@{
    Action      = $actionArgs
    Execute     = $PwshPath
    WorkingDir  = $ScriptRoot
    Triggers    = @("AtLogOn", "Daily-18:00-StartWhenAvailable")
    Settings    = @{ AllowBattery = $true; MultipleInstances = "IgnoreNew"; ExecutionTimeLimitHours = 6 }
} | ConvertTo-Json -Compress)

if ($existing -and $existing.Description -eq $DesiredSignature) {
    Write-Host "Task '$TaskName' already matches the desired configuration — nothing to do." -ForegroundColor Green
    exit 0
}

if ($existing) {
    Write-Host "Task '$TaskName' exists but its configuration has drifted — replacing it." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
}

$Action = New-ScheduledTaskAction -Execute $PwshPath -Argument $actionArgs -WorkingDirectory $ScriptRoot

$Triggers = @(
    New-ScheduledTaskTrigger -AtLogOn
    New-ScheduledTaskTrigger -Daily -At "6:00PM"
)

# ExecutionTimeLimit set generously (6h) — the very first external-drive
# sync could genuinely take a long while over USB 2.0 on a full 120GB
# repo; incremental daily runs afterward will be far faster. Worth
# revisiting once you know real-world durations on the actual hardware.
$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
    -MultipleInstances IgnoreNew

# Interactive logon (not a stored password / S4U) — simplest, safest,
# and correctly scoped: the task runs as whoever's actually logged on,
# with exactly their own permissions to their own Documents folder.
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder `
        -Action $Action -Trigger $Triggers -Settings $Settings -Principal $Principal `
        -Description $DesiredSignature -ErrorAction Stop | Out-Null
    Write-Host "Task '$TaskName' created under '$TaskFolder'." -ForegroundColor Green
    Write-Host "Triggers: at logon, and daily at 6:00 PM (catches up if missed)." -ForegroundColor Green
} catch {
    Write-Host "ERROR: could not create the scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "If this says 'Access is denied', try running this script from an elevated (Administrator) PowerShell window. This has been observed to be needed the first time a NEW Task Scheduler folder (like 'Personal Backups') is created — later runs against an already-existing folder may not need elevation." -ForegroundColor Yellow
    exit 1
}