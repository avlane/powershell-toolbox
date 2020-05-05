function Get-PtRestoreStatus {
    <#
    .SYNOPSIS
    Shows restores that are running now and the restore history of the last days.

    .DESCRIPTION
    Combines two sources on each instance. Running restores come from
    sys.dm_exec_requests, with the percentage done and the estimated finish time.
    History comes from msdb.dbo.restorehistory: which backup was restored into which
    database, when, and by whom. Each output object has a Kind of Running or
    History.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Days
    How far back the history goes. Default 7.

    .PARAMETER RunningOnly
    Skip the history.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtRestoreStatus -ServerInstance SQLDR02 -RunningOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 3650)]
        [int]$Days = 7,

        [switch]$RunningOnly,

        [pscredential]$Credential
    )

    begin {
        $restoreTypes = @{ D = 'Database'; F = 'File'; G = 'Filegroup'; I = 'Differential'; L = 'Log'; V = 'Verify only' }

        $runningQuery = @'
SELECT r.session_id AS SessionId,
       DB_NAME(r.database_id) AS DatabaseName,
       r.command AS Command,
       r.percent_complete AS PercentComplete,
       r.start_time AS StartTime,
       DATEADD(SECOND, r.estimated_completion_time / 1000, GETDATE()) AS EstimatedFinish,
       s.login_name AS LoginName
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.command LIKE 'RESTORE%'
ORDER BY r.start_time;
'@

        $historyQuery = @"
SELECT rh.destination_database_name AS DatabaseName,
       rh.restore_date AS RestoreDate,
       rh.restore_type AS RestoreType,
       rh.user_name AS RestoredBy,
       bs.server_name AS SourceServer,
       bs.database_name AS SourceDatabase,
       bs.backup_finish_date AS BackupFinished,
       bmf.physical_device_name AS BackupFile
FROM msdb.dbo.restorehistory AS rh
JOIN msdb.dbo.backupset AS bs ON bs.backup_set_id = rh.backup_set_id
LEFT JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE rh.restore_date >= DATEADD(DAY, -$Days, GETDATE())
ORDER BY rh.restore_date DESC;
"@
    }

    process {
        foreach ($server in $ServerInstance) {
            $common = @{ ServerInstance = $server; Database = 'master' }
            if ($Credential) { $common['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @common -Query $runningQuery)) {
                [pscustomobject]@{
                    ServerInstance  = $server
                    Kind            = 'Running'
                    DatabaseName    = $row.DatabaseName
                    Detail          = "$($row.Command) on session $($row.SessionId) by $($row.LoginName)"
                    PercentComplete = [math]::Round([double]$row.PercentComplete, 1)
                    Started         = $row.StartTime
                    Finished        = $row.EstimatedFinish
                }
            }

            if ($RunningOnly) { continue }

            foreach ($row in (Invoke-PtSqlQuery @common -Query $historyQuery)) {
                $type = $restoreTypes["$($row.RestoreType)"]
                if (-not $type) { $type = "$($row.RestoreType)" }
                [pscustomobject]@{
                    ServerInstance  = $server
                    Kind            = 'History'
                    DatabaseName    = $row.DatabaseName
                    Detail          = "$type restore of $($row.SourceDatabase) from $($row.SourceServer) (backup finished $($row.BackupFinished)) by $($row.RestoredBy): $($row.BackupFile)"
                    PercentComplete = 100
                    Started         = $row.RestoreDate
                    Finished        = $row.RestoreDate
                }
            }
        }
    }
}
