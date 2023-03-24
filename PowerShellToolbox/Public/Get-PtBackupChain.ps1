function Get-PtBackupChain {
    <#
    .SYNOPSIS
    Checks that the log backups since the last full backup form an unbroken chain.

    .DESCRIPTION
    Get-PtBackupStatus says when the last backup ran; this checks that you could
    actually restore to a point in time. For each database in the full or
    bulk-logged recovery model it takes the newest full backup (copy-only backups
    are ignored, they do not start a chain), then walks the log backups after it in
    order and compares log sequence numbers: every log backup must start at or
    before the end of the one before it. A gap, for example after someone ran
    BACKUP LOG ... WITH NO_LOG elsewhere, a log backup taken on another server, or a
    deleted backup that msdb still remembers, means everything after the gap can
    only be restored to the time of the gap.

    The check uses msdb history only. It does not look at the backup files.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Days
    How far back to read the history. Default 14, so it needs a full backup newer than that.

    .PARAMETER OnlyProblems
    Leave out databases whose chain is intact.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtBackupChain -ServerInstance SQLPROD01 -OnlyProblems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 365)]
        [int]$Days = 14,

        [switch]$OnlyProblems,

        [pscredential]$Credential
    )

    begin {
        $query = @"
SELECT bs.database_name AS DatabaseName,
       d.recovery_model_desc AS RecoveryModel,
       bs.type AS BackupType,
       bs.is_copy_only AS IsCopyOnly,
       bs.backup_start_date AS BackupStart,
       bs.backup_finish_date AS BackupFinish,
       bs.first_lsn AS FirstLsn,
       bs.last_lsn AS LastLsn
FROM msdb.dbo.backupset AS bs
JOIN sys.databases AS d ON d.name = bs.database_name
WHERE bs.backup_finish_date >= DATEADD(DAY, -$Days, GETDATE())
  AND bs.type IN ('D', 'L')
ORDER BY bs.database_name, bs.backup_start_date;
"@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            $groups = Invoke-PtSqlQuery @parameters | Group-Object -Property DatabaseName
            foreach ($group in $groups) {
                $rows = @($group.Group)
                $recoveryModel = $rows[0].RecoveryModel
                if ($recoveryModel -eq 'SIMPLE') { continue }

                $fulls = @($rows | Where-Object { $_.BackupType -eq 'D' -and -not $_.IsCopyOnly })
                if ($fulls.Count -eq 0) {
                    $result = [pscustomobject]@{
                        ServerInstance = $server; DatabaseName = $group.Name; RecoveryModel = $recoveryModel
                        LastFull = $null; LogBackups = 0; ChainIntact = $false; GapAfter = $null
                        Detail = "No full backup in the last $Days days."
                    }
                    $result
                    continue
                }

                $full = $fulls[-1]
                $logs = @($rows | Where-Object { $_.BackupType -eq 'L' -and $_.BackupStart -ge $full.BackupStart })

                $intact = $true
                $gapAfter = $null
                $detail = ''
                $reach = [decimal]$full.LastLsn     # how far the chain reaches so far
                $first = $true
                foreach ($log in $logs) {
                    $logFirst = [decimal]$log.FirstLsn
                    $logLast = [decimal]$log.LastLsn
                    if ($first -and $logLast -lt $reach) { continue }    # entirely inside the full backup
                    if ($logFirst -gt $reach) {
                        $intact = $false
                        $gapAfter = $first ? $full.BackupFinish : $previousFinish
                        $detail = $first ? 'The first log backup after the full backup starts too late.' : "A log backup is missing before the one that finished at $($log.BackupFinish)."
                        break
                    }
                    $first = $false
                    $reach = [math]::Max($reach, $logLast)
                    $previousFinish = $log.BackupFinish
                }

                if ($logs.Count -eq 0) {
                    $intact = $false
                    $detail = 'No log backup since the last full backup.'
                }

                if ($OnlyProblems -and $intact) { continue }
                [pscustomobject]@{
                    ServerInstance = $server
                    DatabaseName   = $group.Name
                    RecoveryModel  = $recoveryModel
                    LastFull       = $full.BackupFinish
                    LogBackups     = $logs.Count
                    ChainIntact    = $intact
                    GapAfter       = $gapAfter
                    Detail         = $detail
                }
            }
        }
    }
}
