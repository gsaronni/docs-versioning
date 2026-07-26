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
$UpdateTaskName = if ($Test) { "Docs Update (TEST)" } else { "Docs Update" }

$ScriptRoot = $PSScriptRoot
$BackupScript = Join-Path $ScriptRoot "backup-documents.ps1"
$UpdateScript = Join-Path $ScriptRoot "invoke-update.ps1"

# --- Removal handles BOTH tasks together, then exits. Must come before any
# registration logic below, so -Remove never gets short-circuited by an
# early exit that only knew about one of the two tasks. ---
if ($Remove) {
    $existingBackup = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue
    if ($existingBackup) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "Removed task '$TaskName' from '$TaskFolder'." -ForegroundColor Yellow
    } else {
        Write-Host "No task named '$TaskName' found under '$TaskFolder' — nothing to remove." -ForegroundColor Yellow
    }

    $existingUpdate = Get-ScheduledTask -TaskName $UpdateTaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue
    if ($existingUpdate) {
        Unregister-ScheduledTask -TaskName $UpdateTaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "Removed task '$UpdateTaskName' from '$TaskFolder'." -ForegroundColor Yellow
    } else {
        Write-Host "No task named '$UpdateTaskName' found under '$TaskFolder' — nothing to remove." -ForegroundColor Yellow
    }
    exit 0
}

# --- From here down: registration only, -Remove already handled above. ---

if (-not (Test-Path $BackupScript)) {
    Write-Host "ERROR: backup-documents.ps1 not found next to this script." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $UpdateScript)) {
    Write-Host "ERROR: invoke-update.ps1 not found next to this script." -ForegroundColor Red
    exit 1
}

$PwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $PwshCommand) {
    Write-Host "ERROR: pwsh.exe not found in PATH." -ForegroundColor Red
    exit 1
}
$PwshPath = $PwshCommand.Source

# ---- Daily Backup task ----

$actionArgsList = @("-WindowStyle", "Hidden", "-File", "`"$BackupScript`"")
if ($Test) { $actionArgsList += "-Test" }
$actionArgs = $actionArgsList -join " "

$existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue

$DesiredSignature = (@{
    Action      = $actionArgs
    Execute     = $PwshPath
    WorkingDir  = $ScriptRoot
    Triggers    = @("AtLogOn", "Daily-18:00-StartWhenAvailable")
    Settings    = @{ AllowBattery = $true; MultipleInstances = "IgnoreNew"; ExecutionTimeLimitHours = 6 }
} | ConvertTo-Json -Compress)

if ($existing -and $existing.Description -eq $DesiredSignature) {
    Write-Host "Task '$TaskName' already matches the desired configuration — nothing to do." -ForegroundColor Green
} else {
    if ($existing) {
        Write-Host "Task '$TaskName' exists but its configuration has drifted — replacing it." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
    }

    $Action = New-ScheduledTaskAction -Execute $PwshPath -Argument $actionArgs -WorkingDirectory $ScriptRoot
    $Triggers = @(
        New-ScheduledTaskTrigger -AtLogOn
        New-ScheduledTaskTrigger -Daily -At "6:00PM"
    )
    $Settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
        -MultipleInstances IgnoreNew
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    try {
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder `
            -Action $Action -Trigger $Triggers -Settings $Settings -Principal $Principal `
            -Description $DesiredSignature -ErrorAction Stop | Out-Null
        Write-Host "Task '$TaskName' created under '$TaskFolder'." -ForegroundColor Green
        Write-Host "Triggers: at logon, and daily at 6:00 PM (catches up if missed)." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: could not create '$TaskName': $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "If this says 'Access is denied', try running this script from an elevated (Administrator) PowerShell window. This has been observed to be needed the first time a NEW Task Scheduler folder (like 'Personal Backups') is created — later runs against an already-existing folder may not need elevation." -ForegroundColor Yellow
        exit 1
    }
}

# ---- Docs Update task ----

$updateArgsList = @("-WindowStyle", "Hidden", "-File", "`"$UpdateScript`"", "-Silent")
$updateArgs = $updateArgsList -join " "

$existingUpdate = Get-ScheduledTask -TaskName $UpdateTaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue

$UpdateDesiredSignature = (@{
    Action      = $updateArgs
    Execute     = $PwshPath
    WorkingDir  = $ScriptRoot
    Triggers    = @("Weekly-4-Sunday-09:00")
    Settings    = @{ AllowBattery = $true; MultipleInstances = "IgnoreNew" }
} | ConvertTo-Json -Compress)

if ($existingUpdate -and $existingUpdate.Description -eq $UpdateDesiredSignature) {
    Write-Host "Task '$UpdateTaskName' already matches the desired configuration — nothing to do." -ForegroundColor Green
} else {
    if ($existingUpdate) {
        Write-Host "Task '$UpdateTaskName' exists but its configuration has drifted — replacing it." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $UpdateTaskName -TaskPath $TaskFolder -Confirm:$false
    }

    $UpdateAction = New-ScheduledTaskAction -Execute $PwshPath -Argument $updateArgs -WorkingDirectory $ScriptRoot
    $UpdateTrigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At "9:00AM"
    $UpdateSettings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew
    $UpdatePrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    try {
        Register-ScheduledTask -TaskName $UpdateTaskName -TaskPath $TaskFolder `
            -Action $UpdateAction -Trigger $UpdateTrigger -Settings $UpdateSettings -Principal $UpdatePrincipal `
            -Description $UpdateDesiredSignature -ErrorAction Stop | Out-Null
        Write-Host "Task '$UpdateTaskName' created under '$TaskFolder'." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: could not create '$UpdateTaskName': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}