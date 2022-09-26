function Get-PtScheduledTaskReport {
    <#
    .SYNOPSIS
    Lists scheduled tasks with their last result and flags the ones that need attention.

    .DESCRIPTION
    Combines Get-ScheduledTask and Get-ScheduledTaskInfo. Status is
    Disabled, NeverRun, Failed (the last result is an error code), Overdue (the next
    run time is already well in the past, which means the scheduler missed it),
    Running or OK.
    Tasks under \Microsoft\ are left out unless -IncludeMicrosoft is given, since
    Windows ships hundreds of them.

    .PARAMETER CimSession
    Sessions to remote computers (New-CimSession). Default: the local computer.

    .PARAMETER TaskPath
    Only tasks under this path, for example \MyCompany\. Default \* (all).

    .PARAMETER IncludeMicrosoft
    Also list the tasks under \Microsoft\.

    .PARAMETER OverdueHours
    A ready task whose next run time lies more than this many hours in the past is
    Overdue. Default 1.

    .PARAMETER OnlyProblems
    Leave out tasks whose Status is OK, Running or Disabled.

    .EXAMPLE
    Get-PtScheduledTaskReport -OnlyProblems | Format-Table TaskName, LastRunTime, LastResult, RunAs
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$CimSession,

        [string]$TaskPath = '\*',

        [switch]$IncludeMicrosoft,

        [ValidateRange(0, 8760)]
        [int]$OverdueHours = 1,

        [switch]$OnlyProblems
    )

    begin {
        # results that are not failures: success, ready, running, not yet run, queued
        $okResults = @(0, 0x41300, 0x41301, 0x41303, 0x41325)
    }

    process {
        $sessions = @($CimSession)
        if ($sessions.Count -eq 0) { $sessions = @($null) }

        foreach ($session in $sessions) {
            $parameters = @{ TaskPath = $TaskPath; ErrorAction = 'Stop' }
            $computer = $env:COMPUTERNAME
            if ($session) {
                $parameters['CimSession'] = $session
                $computer = $session.ComputerName
            }

            try {
                $tasks = @(Get-ScheduledTask @parameters)
            }
            catch {
                Write-Warning "Could not list the scheduled tasks on $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($task in $tasks) {
                if (-not $IncludeMicrosoft -and $task.TaskPath -like '\Microsoft\*') { continue }

                $infoParameters = @{ TaskName = $task.TaskName; TaskPath = $task.TaskPath; ErrorAction = 'SilentlyContinue' }
                if ($session) { $infoParameters['CimSession'] = $session }
                $info = Get-ScheduledTaskInfo @infoParameters

                $result = $null
                if ($info) { $result = [int64]$info.LastTaskResult }

                if ($task.State -eq 'Disabled') { $status = 'Disabled' }
                elseif ($task.State -eq 'Running') { $status = 'Running' }
                elseif ($result -eq 0x41303) { $status = 'NeverRun' }
                elseif ($null -ne $result -and $okResults -notcontains $result) { $status = 'Failed' }
                elseif ($info.NextRunTime -and $info.NextRunTime -lt (Get-Date).AddHours(-$OverdueHours)) { $status = 'Overdue' }
                else { $status = 'OK' }

                if ($OnlyProblems -and $status -notin 'Failed', 'NeverRun', 'Overdue') { continue }

                $action = $task.Actions | Select-Object -First 1
                [pscustomobject]@{
                    ComputerName = $computer
                    TaskPath     = $task.TaskPath
                    TaskName     = $task.TaskName
                    State        = [string]$task.State
                    Status       = $status
                    LastRunTime  = ${info}?.LastRunTime
                    LastResult   = $null -ne $result ? ('0x{0:X}' -f $result) : $null
                    NextRunTime  = ${info}?.NextRunTime
                    RunAs        = $task.Principal.UserId
                    Command      = ('{0} {1}' -f $action.Execute, $action.Arguments).Trim()
                }
            }
        }
    }
}
