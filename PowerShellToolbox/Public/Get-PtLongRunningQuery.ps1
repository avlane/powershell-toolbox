function Get-PtLongRunningQuery {
    <#
    .SYNOPSIS
    Lists the requests that have been running for a while, with CPU, reads and the statement.

    .DESCRIPTION
    Reads sys.dm_exec_requests on each instance and returns the user requests that
    started at least MinimumSeconds ago, longest first. Backups, restores, DBCC,
    index maintenance and rollbacks are expected to run long and are left out unless
    -IncludeMaintenance is given. The session of this command is never listed.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER MinimumSeconds
    Only requests that have run at least this long. Default 30.

    .PARAMETER IncludeMaintenance
    Also list backups, restores, DBCC commands, index operations and rollbacks.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtLongRunningQuery -ServerInstance SQLPROD01 -MinimumSeconds 120 | Format-Table SessionId, LoginName, ElapsedSeconds, Text
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 604800)]
        [int]$MinimumSeconds = 30,

        [switch]$IncludeMaintenance,

        [pscredential]$Credential
    )

    begin {
        $query = @"
SELECT r.session_id AS SessionId,
       DB_NAME(r.database_id) AS DatabaseName,
       s.login_name AS LoginName,
       s.host_name AS HostName,
       s.program_name AS ProgramName,
       r.status AS Status,
       r.command AS Command,
       r.start_time AS StartTime,
       DATEDIFF(SECOND, r.start_time, GETDATE()) AS ElapsedSeconds,
       r.cpu_time AS CpuMs,
       r.logical_reads AS LogicalReads,
       r.wait_type AS WaitType,
       r.blocking_session_id AS BlockingSessionId,
       SUBSTRING(t.text,
                 (r.statement_start_offset / 2) + 1,
                 ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END
                   - r.statement_start_offset) / 2) + 1) AS StatementText
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID
  AND s.is_user_process = 1
  AND DATEDIFF(SECOND, r.start_time, GETDATE()) >= $MinimumSeconds
ORDER BY r.start_time;
"@
        $maintenance = '^(BACKUP|RESTORE|DBCC|ALTER INDEX|CREATE INDEX|UPDATE STATISTICS|ROLLBACK|KILLED)'
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                if (-not $IncludeMaintenance -and $row.Command -match $maintenance) { continue }

                [pscustomobject]@{
                    ServerInstance   = $server
                    SessionId        = $row.SessionId
                    DatabaseName     = $row.DatabaseName
                    LoginName        = $row.LoginName
                    HostName         = $row.HostName
                    ProgramName      = $row.ProgramName
                    Status           = $row.Status
                    Command          = $row.Command
                    StartTime        = $row.StartTime
                    ElapsedSeconds   = $row.ElapsedSeconds
                    CpuSeconds       = [math]::Round($row.CpuMs / 1000, 1)
                    LogicalReads     = $row.LogicalReads
                    WaitType         = $row.WaitType
                    BlockedBy        = $row.BlockingSessionId -gt 0 ? $row.BlockingSessionId : $null
                    Text             = $row.StatementText
                }
            }
        }
    }
}
