function Get-PtDatabaseGrowth {
    <#
    .SYNOPSIS
    Estimates how fast each database is growing from the sizes recorded by full backups.

    .DESCRIPTION
    msdb remembers the data size of every backup. For each database this takes the
    largest full backup of each day over the last Days days and fits a straight line
    through them, which gives the growth in MB per day and, relative to today's size,
    in percent per 30 days. It is a rough trend, not a forecast: one big load or a
    purge in the period moves it, and a database with fewer than three days of full
    backups is reported as NotEnoughData.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Days
    How far back to look. Default 90.

    .PARAMETER Database
    Only these databases. Default: all.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtDatabaseGrowth -ServerInstance SQLPROD01 | Sort-Object GrowthMBPerDay -Descending | Select-Object -First 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(7, 3650)]
        [int]$Days = 90,

        [string[]]$Database,

        [pscredential]$Credential
    )

    begin {
        $query = @"
SELECT bs.database_name AS DatabaseName,
       CAST(bs.backup_finish_date AS date) AS BackupDate,
       MAX(bs.backup_size) / 1048576.0 AS SizeMB
FROM msdb.dbo.backupset AS bs
WHERE bs.type = 'D'
  AND bs.backup_finish_date >= DATEADD(DAY, -$Days, GETDATE())
GROUP BY bs.database_name, CAST(bs.backup_finish_date AS date)
ORDER BY bs.database_name, CAST(bs.backup_finish_date AS date);
"@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'msdb' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            $groups = Invoke-PtSqlQuery @parameters | Group-Object -Property DatabaseName
            foreach ($group in $groups) {
                if ($Database -and $Database -notcontains $group.Name) { continue }

                $points = @($group.Group | Sort-Object -Property BackupDate)
                $first = $points[0]
                $last = $points[-1]

                $slope = $null
                if ($points.Count -ge 3) {
                    $x = @($points | ForEach-Object { ([datetime]$_.BackupDate - [datetime]$first.BackupDate).TotalDays })
                    $y = @($points | ForEach-Object { [double]$_.SizeMB })
                    $slope = Get-PtLinearSlope -X $x -Y $y
                }

                $perDay = $null
                $percentPerMonth = $null
                if ($null -ne $slope) {
                    $perDay = [math]::Round($slope, 2)
                    if ([double]$last.SizeMB -gt 0) { $percentPerMonth = [math]::Round($slope * 30 / [double]$last.SizeMB * 100, 1) }
                }

                [pscustomobject]@{
                    ServerInstance         = $server
                    DatabaseName           = $group.Name
                    Samples                = $points.Count
                    FirstDate              = $first.BackupDate
                    LastDate               = $last.BackupDate
                    FirstSizeMB            = [math]::Round([double]$first.SizeMB, 1)
                    LastSizeMB             = [math]::Round([double]$last.SizeMB, 1)
                    GrowthMBPerDay         = $perDay
                    GrowthPercentPer30Days = $percentPerMonth
                    Status                 = $null -eq $slope ? 'NotEnoughData' : 'OK'
                }
            }
        }
    }
}
