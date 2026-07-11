function Get-PtBlockingSession {
    <#
    .SYNOPSIS
    Shows the sessions that are blocked right now and who is at the head of each blocking chain.

    .DESCRIPTION
    Reads sys.dm_exec_requests on each instance. For every blocked request it
    returns the wait, the statement and the session blocking it, and follows the
    chain to the head blocker: the session that blocks others but is not waiting
    itself. With -IncludeHeadBlocker it adds one row per head blocker with its
    login, host, program and last input buffer, which is usually what you need to
    know before deciding whether to kill it.

    Nothing is returned when nothing is blocked.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER MinimumWaitSeconds
    Ignore requests that have waited less than this long. Default 5.

    .PARAMETER IncludeHeadBlocker
    Also return a row of Kind HeadBlocker for each head of a chain.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtBlockingSession -ServerInstance SQLPROD01 -IncludeHeadBlocker | Format-List
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(0, 86400)]
        [int]$MinimumWaitSeconds = 5,

        [switch]$IncludeHeadBlocker,

        [pscredential]$Credential
    )

    begin {
        $blockedQuery = @'
SELECT r.session_id AS SessionId,
       r.blocking_session_id AS BlockingSessionId,
       r.wait_type AS WaitType,
       r.wait_time AS WaitTimeMs,
       DB_NAME(r.database_id) AS DatabaseName,
       s.login_name AS LoginName,
       s.host_name AS HostName,
       s.program_name AS ProgramName,
       SUBSTRING(t.text,
                 (r.statement_start_offset / 2) + 1,
                 ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END
                   - r.statement_start_offset) / 2) + 1) AS StatementText
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;
'@
    }

    process {
        foreach ($server in $ServerInstance) {
            $common = @{ ServerInstance = $server; Database = 'master' }
            if ($Credential) { $common['Credential'] = $Credential }

            $allBlocked = @(Invoke-PtSqlQuery @common -Query $blockedQuery)
            $blocked = @($allBlocked | Where-Object { $_.WaitTimeMs -ge ($MinimumWaitSeconds * 1000) })
            if ($blocked.Count -eq 0) { continue }

            # session id -> the session it waits for, to walk each chain to its head. This
            # uses every blocked request, also the ones that have waited less than the
            # minimum: a session in the middle of a chain that has only just started to
            # wait must not be mistaken for the head.
            $waitsFor = @{}
            foreach ($row in $allBlocked) { $waitsFor[[int]$row.SessionId] = [int]$row.BlockingSessionId }

            $heads = New-Object -TypeName 'System.Collections.Generic.List[int]'
            foreach ($row in $blocked) {
                $head = [int]$row.BlockingSessionId
                $seen = @{}
                while ($waitsFor.ContainsKey($head) -and -not $seen.ContainsKey($head)) {
                    $seen[$head] = $true
                    $head = $waitsFor[$head]
                }
                if (-not $heads.Contains($head)) { $heads.Add($head) }

                [pscustomobject]@{
                    ServerInstance   = $server
                    Kind             = 'Blocked'
                    SessionId        = $row.SessionId
                    BlockedBy        = $row.BlockingSessionId
                    HeadBlocker      = $head
                    WaitSeconds      = [math]::Round($row.WaitTimeMs / 1000, 1)
                    WaitType         = $row.WaitType
                    DatabaseName     = $row.DatabaseName
                    LoginName        = $row.LoginName
                    HostName         = $row.HostName
                    ProgramName      = $row.ProgramName
                    Text             = $row.StatementText
                }
            }

            if ($IncludeHeadBlocker) {
                # the ids come from the query above, so they are integers and safe to put in the text
                $idList = ($heads | ForEach-Object { [int]$_ }) -join ', '
                $headQuery = @"
SELECT s.session_id AS SessionId,
       s.login_name AS LoginName,
       s.host_name AS HostName,
       s.program_name AS ProgramName,
       s.status AS Status,
       s.last_request_start_time AS LastRequestStart,
       s.open_transaction_count AS OpenTransactions,
       ib.event_info AS InputBuffer
FROM sys.dm_exec_sessions AS s
OUTER APPLY sys.dm_exec_input_buffer(s.session_id, NULL) AS ib
WHERE s.session_id IN ($idList);
"@
                foreach ($row in (Invoke-PtSqlQuery @common -Query $headQuery)) {
                    [pscustomobject]@{
                        ServerInstance   = $server
                        Kind             = 'HeadBlocker'
                        SessionId        = $row.SessionId
                        BlockedBy        = $null
                        HeadBlocker      = $row.SessionId
                        WaitSeconds      = $null
                        WaitType         = $row.Status
                        DatabaseName     = $null
                        LoginName        = $row.LoginName
                        HostName         = $row.HostName
                        ProgramName      = $row.ProgramName
                        Text             = $row.InputBuffer
                    }
                }
            }
        }
    }
}
