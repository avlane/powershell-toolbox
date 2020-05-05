function Get-PtBackupStatus {
    <#
    .SYNOPSIS
    Shows when each database was last backed up and flags the ones that are overdue.

    .DESCRIPTION
    Reads msdb.dbo.backupset on each instance and returns, per online database, the
    time of the last full, differential and log backup, how old they are, and a
    Status of OK, Stale or NoBackup. A database in the full or bulk-logged recovery
    model is also Stale when its last log backup is older than MaxLogAgeMinutes.

    Copy-only backups count as backups here. Ages are measured against the clock of
    the server, not of the machine running this command.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER MaxFullAgeHours
    A database whose newest full or differential backup is older than this is
    Stale. Default 36.

    .PARAMETER MaxLogAgeMinutes
    Same for log backups. Default 120.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtBackupStatus -ServerInstance SQLPROD01, SQLPROD02 | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 8760)]
        [int]$MaxFullAgeHours = 36,

        [ValidateRange(1, 10080)]
        [int]$MaxLogAgeMinutes = 120,

        [pscredential]$Credential
    )

    begin {
        $query = @'
SELECT d.name AS DatabaseName,
       d.recovery_model_desc AS RecoveryModel,
       GETDATE() AS ServerTime,
       MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFull,
       MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiff,
       MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLog
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b ON b.database_name = d.name
WHERE d.name <> 'tempdb' AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;
'@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                # the newest of the full and differential backups is what restores depend on
                $lastBase = $row.LastFull
                if ($row.LastDiff -is [datetime] -and ($lastBase -isnot [datetime] -or $row.LastDiff -gt $lastBase)) {
                    $lastBase = $row.LastDiff
                }

                $problems = @()
                $baseAge = $null
                if ($lastBase -is [datetime]) {
                    $baseAge = [math]::Round(($row.ServerTime - $lastBase).TotalHours, 1)
                    if ($baseAge -gt $MaxFullAgeHours) { $problems += "no full or differential backup for $baseAge hours" }
                }
                else {
                    $problems += 'never backed up'
                }

                $logAge = $null
                if ($row.LastLog -is [datetime]) {
                    $logAge = [math]::Round(($row.ServerTime - $row.LastLog).TotalMinutes, 0)
                }
                if ($row.RecoveryModel -ne 'SIMPLE' -and $row.DatabaseName -ne 'model') {
                    if ($null -eq $logAge) { $problems += 'no log backup' }
                    elseif ($logAge -gt $MaxLogAgeMinutes) { $problems += "no log backup for $logAge minutes" }
                }

                if ($lastBase -isnot [datetime]) { $status = 'NoBackup' }
                elseif ($problems.Count -gt 0) { $status = 'Stale' }
                else { $status = 'OK' }

                [pscustomobject]@{
                    ServerInstance    = $server
                    DatabaseName      = $row.DatabaseName
                    RecoveryModel     = $row.RecoveryModel
                    LastFull          = $row.LastFull
                    LastDiff          = $row.LastDiff
                    LastLog           = $row.LastLog
                    HoursSinceBase    = $baseAge
                    MinutesSinceLog   = $logAge
                    Status            = $status
                    Problems          = $problems -join '; '
                }
            }
        }
    }
}
