function Get-PtSqlErrorLog {
    <#
    .SYNOPSIS
    Reads the SQL Server error log (or the SQL Server Agent log) with search and time filters.

    .DESCRIPTION
    Wraps sys.sp_readerrorlog. The server does the text search (up to two search
    strings, both of which must occur), PowerShell does the time filtering and
    removes routine messages that bury the interesting ones: successful backups,
    "I/O is frozen/resumed" pairs from snapshot backups, trace flag echoes, and
    successful logins. -IncludeRoutine turns that filter off.

    sp_readerrorlog returns an error such as 18456 as two rows, the line "Error: 18456,
    Severity: 14, State: 8." and the message after it. The first one is parsed into
    ErrorNumber, Severity and State so you can filter on them; the message is the next row.

    Reading the log needs the securityadmin or sysadmin role (or VIEW SERVER STATE
    plus access to sp_readerrorlog, depending on the version).

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Search
    Up to two strings; rows must contain all of them.

    .PARAMETER LogNumber
    0 is the current log, 1 the previous one, and so on up to 99. Default 0.

    .PARAMETER Agent
    Read the SQL Server Agent log instead of the SQL Server log.

    .PARAMETER Since
    Only entries after this time.

    .PARAMETER Until
    Only entries before this time.

    .PARAMETER First
    The most entries to return per instance, newest first. Default 500.

    .PARAMETER IncludeRoutine
    Keep the routine messages.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtSqlErrorLog -ServerInstance SQLPROD01 -Search 'Login failed' -Since (Get-Date).AddHours(-6)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateCount(0, 2)]
        [ValidateLength(1, 255)]
        [string[]]$Search,

        [ValidateRange(0, 99)]
        [int]$LogNumber = 0,

        [switch]$Agent,

        [datetime]$Since,

        [datetime]$Until,

        [ValidateRange(1, 100000)]
        [int]$First = 500,

        [switch]$IncludeRoutine,

        [pscredential]$Credential
    )

    begin {
        $quote = { param($text) "N'" + ($text.Replace("'", "''")) + "'" }
        $arguments = @("@p1 = $LogNumber", "@p2 = $($Agent ? 2 : 1)")
        foreach ($term in @($Search)) { if ($term) { $arguments += "@p$($arguments.Count + 1) = $(& $quote $term)" } }
        $query = 'EXEC sys.sp_readerrorlog ' + ($arguments -join ', ') + ';'

        $routine = '^(Database backed up\.|BACKUP DATABASE successfully processed|BACKUP LOG successfully processed|Log was backed up\.|I/O was resumed|I/O is frozen|DBCC TRACEON|DBCC TRACEOFF|Login succeeded for user|Setting database option|Starting up database|Recovery of database .* is \d+% complete|Recovery completed for database|Clearing tempdb database|Parallel redo is)'
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            $rows = @(Invoke-PtSqlQuery @parameters | Where-Object {
                    ($PSBoundParameters.ContainsKey('Since') -eq $false -or $_.LogDate -gt $Since) -and
                    ($PSBoundParameters.ContainsKey('Until') -eq $false -or $_.LogDate -lt $Until) -and
                    ($IncludeRoutine -or $_.Text -notmatch $routine)
                } | Sort-Object -Property LogDate -Descending | Select-Object -First $First)

            foreach ($row in $rows) {
                $errorNumber = $null
                $severity = $null
                $state = $null
                if ($row.Text -match '^Error: (\d+), Severity: (\d+), State: (\d+)\.') {
                    $errorNumber = [int]$Matches[1]
                    $severity = [int]$Matches[2]
                    $state = [int]$Matches[3]
                }

                [pscustomobject]@{
                    ServerInstance = $server
                    LogDate        = $row.LogDate
                    ProcessInfo    = $row.ProcessInfo
                    ErrorNumber    = $errorNumber
                    Severity       = $severity
                    State          = $state
                    Text           = $row.Text
                }
            }
        }
    }
}
