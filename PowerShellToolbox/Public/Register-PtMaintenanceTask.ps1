function Register-PtMaintenanceTask {
    <#
    .SYNOPSIS
    Creates a scheduled task that runs a PowerShell script every day or on chosen weekdays.

    .DESCRIPTION
    A convenience wrapper around Register-ScheduledTask for the usual maintenance
    job: run a .ps1 file at a fixed time, without a profile, with a time limit, and
    not twice at once. By default the task runs as SYSTEM; give -Credential to run
    it as a service account (the password is stored by Windows for the task).

    The task is created in \PowerShellToolbox\ unless -TaskPath says otherwise. An
    existing task with the same name is only replaced with -Force. Supports
    -WhatIf and -Confirm.

    .PARAMETER TaskName
    The name of the task.

    .PARAMETER ScriptPath
    The .ps1 file to run. It must exist.

    .PARAMETER Arguments
    Arguments appended to the script's command line.

    .PARAMETER At
    The time of day to start. Only the time part is used.

    .PARAMETER Frequency
    Daily (default) or Weekly.

    .PARAMETER DaysOfWeek
    With -Frequency Weekly, the days to run. Default Monday.

    .PARAMETER Credential
    The account to run as. Default: SYSTEM.

    .PARAMETER TaskPath
    The folder of the task in Task Scheduler. Default \PowerShellToolbox\.

    .PARAMETER TimeLimitHours
    The task is stopped after this many hours. Default 2.

    .PARAMETER PowerShellPath
    The program that runs the script. Default pwsh.exe (PowerShell 7, which must be
    installed for the account the task runs as).

    .PARAMETER Force
    Replace an existing task of the same name.

    .EXAMPLE
    Register-PtMaintenanceTask -TaskName 'Clean backups' -ScriptPath D:\Scripts\Clean-Backups.ps1 -At 02:30 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^[^\\/:*?"<>|]+$')]
        [string]$TaskName,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$ScriptPath,

        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [datetime]$At,

        [ValidateSet('Daily', 'Weekly')]
        [string]$Frequency = 'Daily',

        [System.DayOfWeek[]]$DaysOfWeek = @([System.DayOfWeek]::Monday),

        [pscredential]$Credential,

        [string]$TaskPath = '\PowerShellToolbox\',

        [ValidateRange(1, 72)]
        [int]$TimeLimitHours = 2,

        [string]$PowerShellPath = 'pwsh.exe',

        [switch]$Force
    )

    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        throw "The task $TaskPath$TaskName already exists. Use -Force to replace it."
    }

    $fullScriptPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
    $commandLine = "-NoProfile -ExecutionPolicy Bypass -File `"$fullScriptPath`""
    if ($Arguments) { $commandLine = "$commandLine $Arguments" }

    $action = New-ScheduledTaskAction -Execute $PowerShellPath -Argument $commandLine
    if ($Frequency -eq 'Weekly') {
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DaysOfWeek -At $At
    }
    else {
        $trigger = New-ScheduledTaskTrigger -Daily -At $At
    }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours $TimeLimitHours)

    $registration = @{
        TaskName = $TaskName
        TaskPath = $TaskPath
        Action   = $action
        Trigger  = $trigger
        Settings = $settings
        Force    = $true
    }
    if ($Credential) {
        $registration['User'] = $Credential.UserName
        $registration['Password'] = $Credential.GetNetworkCredential().Password
        $registration['RunLevel'] = 'Highest'
    }
    else {
        $registration['Principal'] = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    }

    if ($PSCmdlet.ShouldProcess("$TaskPath$TaskName", "Register a $Frequency task running $fullScriptPath at $($At.ToString('HH:mm'))")) {
        Register-ScheduledTask @registration
    }
}
