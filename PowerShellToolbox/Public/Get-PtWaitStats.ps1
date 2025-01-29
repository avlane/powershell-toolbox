function Get-PtWaitStats {
    <#
    .SYNOPSIS
    Shows what SQL Server has mostly been waiting for, with the usual idle waits left out.

    .DESCRIPTION
    Reads sys.dm_os_wait_stats, which counts waits since the instance started (or the
    counters were cleared), removes the waits that are just idle threads and
    background housekeeping, and returns the Top ones with their share of the rest
    plus a one-line reminder of what a common wait means. With -SampleSeconds the
    counters are read twice and only the waits in between are shown, which answers
    "what is it waiting for right now" instead of "what has it waited for since the
    last restart".

    The share is relative to the waits that are left, not to the elapsed time, and wait
    time of parallel queries is summed over threads, so the seconds can exceed the
    clock time.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Top
    How many wait types to return per instance. Default 10.

    .PARAMETER SampleSeconds
    Take two readings this many seconds apart and report the difference. Default 0
    (cumulative since the start).

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtWaitStats -ServerInstance SQLPROD01 -SampleSeconds 60 | Format-Table WaitType, WaitSeconds, Percent, Description
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 500)]
        [int]$Top = 10,

        [ValidateRange(0, 3600)]
        [int]$SampleSeconds = 0,

        [pscredential]$Credential
    )

    begin {
        $query = @'
SELECT wait_type AS WaitType,
       waiting_tasks_count AS WaitingTasks,
       wait_time_ms AS WaitTimeMs,
       signal_wait_time_ms AS SignalWaitTimeMs
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0;
'@
        # waits of idle or background threads: they say nothing about performance
        $idle = '^(BROKER_|CHECKPOINT_QUEUE|CLR_|DBMIRROR_|DIRTY_PAGE_POLL|DISPATCHER_QUEUE_SEMAPHORE|FT_IFTS|HADR_(CLUSAPI_CALL|FILESTREAM_IOMGR_IOCOMPLETION|LOGCAPTURE_WAIT|NOTIFICATION_DEQUEUE|TIMER_TASK|WORK_QUEUE)|LAZYWRITER_SLEEP|LOGMGR_QUEUE|MEMORY_ALLOCATION_EXT|ONDEMAND_TASK_QUEUE|PARALLEL_REDO_|PREEMPTIVE_|PWAIT_ALL_COMPONENTS_INITIALIZED|QDS_|REQUEST_FOR_DEADLOCK_SEARCH|RESOURCE_QUEUE|SERVER_IDLE_CHECK|SLEEP_|SOS_WORK_DISPATCHER|SP_SERVER_DIAGNOSTICS_SLEEP|SQLTRACE_|UCS_|WAIT_XTP_|WAITFOR|XE_|XTP_PREEMPTIVE_TASK)'
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            $first = @(Invoke-PtSqlQuery @parameters)
            $rows = $first
            if ($SampleSeconds -gt 0) {
                Start-Sleep -Seconds $SampleSeconds
                $before = @{}
                foreach ($row in $first) { $before[[string]$row.WaitType] = $row }
                $rows = foreach ($row in @(Invoke-PtSqlQuery @parameters)) {
                    $old = $before[[string]$row.WaitType]
                    [pscustomobject]@{
                        WaitType         = $row.WaitType
                        WaitingTasks     = $row.WaitingTasks - ($old ? $old.WaitingTasks : 0)
                        WaitTimeMs       = $row.WaitTimeMs - ($old ? $old.WaitTimeMs : 0)
                        SignalWaitTimeMs = $row.SignalWaitTimeMs - ($old ? $old.SignalWaitTimeMs : 0)
                    }
                }
            }

            $relevant = @($rows | Where-Object { $_.WaitType -notmatch $idle -and $_.WaitTimeMs -gt 0 })
            $total = ($relevant | Measure-Object -Property WaitTimeMs -Sum).Sum

            foreach ($wait in ($relevant | Sort-Object -Property WaitTimeMs -Descending | Select-Object -First $Top)) {
                [pscustomobject]@{
                    ServerInstance = $server
                    WaitType       = $wait.WaitType
                    WaitSeconds    = [math]::Round($wait.WaitTimeMs / 1000, 1)
                    SignalSeconds  = [math]::Round($wait.SignalWaitTimeMs / 1000, 1)
                    ResourceSeconds = [math]::Round(($wait.WaitTimeMs - $wait.SignalWaitTimeMs) / 1000, 1)
                    Percent        = [math]::Round($wait.WaitTimeMs / $total * 100, 1)
                    WaitingTasks   = $wait.WaitingTasks
                    AvgMsPerWait   = $wait.WaitingTasks -gt 0 ? [math]::Round($wait.WaitTimeMs / $wait.WaitingTasks, 1) : $null
                    Description    = Get-PtWaitDescription -WaitType $wait.WaitType
                }
            }
        }
    }
}
