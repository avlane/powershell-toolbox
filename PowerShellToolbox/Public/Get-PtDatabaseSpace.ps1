function Get-PtDatabaseSpace {
    <#
    .SYNOPSIS
    Lists the data and log files of every database with their size, growth setting and the free space of their volume.

    .DESCRIPTION
    Reads sys.master_files and sys.dm_os_volume_stats on each instance. Besides the
    numbers it flags two things that cause trouble in practice: files that grow by
    a percentage (or by 1 MB steps), and volumes that are nearly full. Status is
    LowVolume, BadGrowth or OK, and a file can only have one, with LowVolume taking
    precedence.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Database
    Only these databases. Default: all.

    .PARAMETER LowVolumePercent
    A volume with less than this percentage free is LowVolume. Default 15.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtDatabaseSpace -ServerInstance SQLPROD01 | Where-Object Status -ne 'OK' | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [string[]]$Database,

        [ValidateRange(1, 99)]
        [int]$LowVolumePercent = 15,

        [pscredential]$Credential
    )

    begin {
        $query = @'
SELECT DB_NAME(f.database_id) AS DatabaseName,
       f.name AS LogicalName,
       f.type_desc AS FileType,
       f.physical_name AS PhysicalName,
       CAST(f.size AS bigint) * 8 / 1024 AS SizeMB,
       f.max_size AS MaxSizePages,
       f.growth AS Growth,
       f.is_percent_growth AS IsPercentGrowth,
       v.volume_mount_point AS Volume,
       v.available_bytes / 1048576 AS VolumeFreeMB,
       v.total_bytes / 1048576 AS VolumeTotalMB
FROM sys.master_files AS f
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) AS v
ORDER BY DB_NAME(f.database_id), f.file_id;
'@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                if ($Database -and $Database -notcontains $row.DatabaseName) { continue }

                # growth is in 8 KB pages unless it is a percentage; 0 means the file does not grow
                if ($row.Growth -eq 0) { $growthText = 'fixed size' }
                elseif ($row.IsPercentGrowth) { $growthText = "$($row.Growth) percent" }
                else { $growthText = "$([int]($row.Growth * 8 / 1024)) MB" }

                if ($row.MaxSizePages -eq -1 -or $row.MaxSizePages -eq 268435456) { $maxText = 'unlimited' }
                else { $maxText = "$([int]([int64]$row.MaxSizePages * 8 / 1024)) MB" }

                $volumeFreePercent = $null
                if ($row.VolumeTotalMB -gt 0) { $volumeFreePercent = [math]::Round(($row.VolumeFreeMB / $row.VolumeTotalMB) * 100, 1) }

                if ($null -ne $volumeFreePercent -and $volumeFreePercent -lt $LowVolumePercent) { $status = 'LowVolume' }
                elseif ($row.IsPercentGrowth -or ($row.Growth -gt 0 -and $row.Growth * 8 / 1024 -lt 64)) { $status = 'BadGrowth' }
                else { $status = 'OK' }

                [pscustomobject]@{
                    ServerInstance    = $server
                    DatabaseName      = $row.DatabaseName
                    LogicalName       = $row.LogicalName
                    FileType          = $row.FileType
                    SizeMB            = $row.SizeMB
                    Growth            = $growthText
                    MaxSize           = $maxText
                    Volume            = $row.Volume
                    VolumeFreeMB      = $row.VolumeFreeMB
                    VolumeFreePercent = $volumeFreePercent
                    Status            = $status
                    PhysicalName      = $row.PhysicalName
                }
            }
        }
    }
}
