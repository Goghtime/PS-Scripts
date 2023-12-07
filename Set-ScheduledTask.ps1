$ScriptContent = @'
...
'@

#############

$ScriptPath = "C:\Windows\Admin\Scripts"
$ScriptName = "SCRIPT NAME HERE"
$TaskName = "TAKE NAME HERE"
$ScriptFullPath = Join-Path -Path $ScriptPath -ChildPath $ScriptName

# Ensure the script directory exists
if (-not (Test-Path -Path $ScriptPath -PathType Container)) {
    $null = New-Item -Path $ScriptPath -ItemType Directory -Force
}

if (-not (Test-Path -Path $ScriptFullPath)) {
    $ScriptContent | Out-File -FilePath $ScriptFullPath -Encoding UTF8
} else {
    Write-Host "Script file already exists."
}

# PowerShell executable path
$PowerShellPath = (Get-Command PowerShell.exe).Source

$taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (-null -eq $taskExists) {
    # PowerShell executable path
    $PowerShellPath = (Get-Command PowerShell.exe).Source

    # Create a new scheduled task action to run the new script
    $action = New-ScheduledTaskAction -Execute $PowerShellPath -Argument "-ExecutionPolicy Bypass -File `"$ScriptFullPath`""

    $trigger = New-ScheduledTaskTrigger -Daily -At 12pm

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunElevated

    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description "Runs script daily at 12 PM" -Settings $settings -User "SYSTEM"
} else {
    Write-Host "Scheduled task already exists."
}