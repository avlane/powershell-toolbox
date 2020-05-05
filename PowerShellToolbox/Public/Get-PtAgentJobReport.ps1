function Get-PtAgentJobReport {
    <#
    .SYNOPSIS
    Reports the state of the SQL Server Agent jobs: last result, next run and recent failures.

    .DESCRIPTION
    Reads msdb on each instance and returns one object per job with the outcome and
    start time of its last run, how long it took, when it runs next and how many
    runs failed in the last few hours. Verdict is Failed (the last run failed),
    Flaky (the last run succeeded but there were failures in the window), Disabled
    or OK.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Hours
    The window for counting failed runs. Default 24.

    .PARAMETER OnlyProblems
    Leave out jobs whose Verdict is OK.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtAgentJobReport -ServerInstance SQLPROD01, SQLPROD02 -OnlyProblems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [switch]$OnlyProblems,

        [pscredential]$Credential
    )

    begin {
        # job outcome codes in msdb.dbo.sysjobhistory.run_status
        $statusNames = @{ 0 = 'Failed'; 1 = 'Succeeded'; 2 = 'Retry'; 3 = 'Canceled'; 4 = 'InProgress' }

        $query = @"
WITH last_run AS (
    SELECT h.job_id, h.run_status, h.run_date, h.run_time, h.run_duration, h.message,
           ROW_NUMBER() OVER (PARTITION BY h.job_id ORDER BY h.instance_id DESC) AS rn
    FROM msdb.dbo.sysjobhistory AS h
    WHERE h.step_id = 0
),
failures AS (
    SELECT h.job_id, COUNT(*) AS failed_runs
    FROM msdb.dbo.sysjobhistory AS h
    WHERE h.step_id = 0 AND h.run_status = 0
      AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(HOUR, -$Hours, GETDATE())
    GROUP BY h.job_id
),
next_run AS (
    SELECT job_id, MIN(msdb.dbo.agent_datetime(next_run_date, next_run_time)) AS next_run_time
    FROM msdb.dbo.sysjobschedules
    WHERE next_run_date > 0
    GROUP BY job_id
)
SELECT j.name AS JobName,
       j.enabled AS Enabled,
       l.run_status AS LastRunStatus,
       msdb.dbo.agent_datetime(l.run_date, l.run_time) AS LastRunTime,
       (l.run_duration / 10000) * 3600 + ((l.run_duration / 100) % 100) * 60 + (l.run_duration % 100) AS LastRunSeconds,
       l.message AS LastMessage,
       n.next_run_time AS NextRunTime,
       ISNULL(f.failed_runs, 0) AS FailedRuns
FROM msdb.dbo.sysjobs AS j
LEFT JOIN last_run AS l ON l.job_id = j.job_id AND l.rn = 1
LEFT JOIN failures AS f ON f.job_id = j.job_id
LEFT JOIN next_run AS n ON n.job_id = j.job_id
ORDER BY j.name;
"@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'msdb' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                $lastStatus = 'NeverRun'
                if ($null -ne $row.LastRunStatus) { $lastStatus = $statusNames[[int]$row.LastRunStatus] }

                if (-not $row.Enabled) { $verdict = 'Disabled' }
                elseif ($lastStatus -eq 'Failed') { $verdict = 'Failed' }
                elseif ($row.FailedRuns -gt 0) { $verdict = 'Flaky' }
                else { $verdict = 'OK' }

                if ($OnlyProblems -and $verdict -eq 'OK') { continue }

                [pscustomobject]@{
                    ServerInstance = $server
                    JobName        = $row.JobName
                    Enabled        = [bool]$row.Enabled
                    LastRunStatus  = $lastStatus
                    LastRunTime    = $row.LastRunTime
                    LastRunSeconds = $row.LastRunSeconds
                    NextRunTime    = $row.NextRunTime
                    FailedRuns     = $row.FailedRuns
                    Verdict        = $verdict
                    LastMessage    = $row.LastMessage
                }
            }
        }
    }
}
