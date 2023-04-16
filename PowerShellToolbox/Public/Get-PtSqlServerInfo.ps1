function Get-PtSqlServerInfo {
    <#
    .SYNOPSIS
    Gives a one-row overview of each SQL Server instance: version, uptime, memory, parallelism and tempdb.

    .DESCRIPTION
    Reads SERVERPROPERTY, sys.dm_os_sys_info and sys.configurations and returns the
    product version with its marketing name, edition, start time and uptime, CPU
    count, physical and maximum memory, MAXDOP, the cost threshold for parallelism and
    the number of tempdb data files. Flags lists the settings that are usually left
    at their installation defaults by mistake:

      MaxMemoryNotSet        max server memory is the 2 PB default
      MaxdopZeroOnManyCores  MAXDOP 0 on a server with more than 8 cores
      CostThresholdDefault   cost threshold for parallelism is still 5
      FewTempdbFiles         fewer tempdb data files than the lower of 8 and the cores

    These are conventions, not rules; read them as questions to ask.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtSqlServerInfo -ServerInstance SQLPROD01, SQLPROD02 | Format-Table ServerInstance, Version, Edition, UptimeDays, Flags
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [pscredential]$Credential
    )

    begin {
        $query = @'
SELECT CAST(SERVERPROPERTY('MachineName') AS nvarchar(128)) AS MachineName,
       CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(50)) AS ProductVersion,
       CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(50)) AS ProductLevel,
       CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(50)) AS ProductUpdateLevel,
       CAST(SERVERPROPERTY('Edition') AS nvarchar(100)) AS Edition,
       CAST(SERVERPROPERTY('IsClustered') AS int) AS IsClustered,
       CAST(SERVERPROPERTY('IsHadrEnabled') AS int) AS IsHadrEnabled,
       si.sqlserver_start_time AS StartTime,
       GETDATE() AS ServerTime,
       si.cpu_count AS CpuCount,
       si.physical_memory_kb / 1024 AS PhysicalMemoryMB,
       (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'max server memory (MB)') AS MaxServerMemoryMB,
       (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'max degree of parallelism') AS Maxdop,
       (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'cost threshold for parallelism') AS CostThreshold,
       (SELECT COUNT(*) FROM sys.master_files WHERE database_id = 2 AND type = 0) AS TempdbFiles
FROM sys.dm_os_sys_info AS si;
'@
        $marketingNames = @{ 10 = '2008'; 11 = '2012'; 12 = '2014'; 13 = '2016'; 14 = '2017'; 15 = '2019'; 16 = '2022' }
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                $major = [int]($row.ProductVersion -split '\.')[0]
                $name = $marketingNames[$major] ?? "version $major"

                $flags = @()
                if ($row.MaxServerMemoryMB -ge 2147483647) { $flags += 'MaxMemoryNotSet' }
                if ($row.Maxdop -eq 0 -and $row.CpuCount -gt 8) { $flags += 'MaxdopZeroOnManyCores' }
                if ($row.CostThreshold -eq 5) { $flags += 'CostThresholdDefault' }
                if ($row.TempdbFiles -lt [math]::Min(8, $row.CpuCount)) { $flags += 'FewTempdbFiles' }

                [pscustomobject]@{
                    ServerInstance   = $server
                    MachineName      = $row.MachineName
                    Version          = "SQL Server $name ($($row.ProductVersion))"
                    Level            = ($row.ProductUpdateLevel ?? $row.ProductLevel)
                    Edition          = $row.Edition
                    Clustered        = [bool]$row.IsClustered
                    AvailabilityGroups = [bool]$row.IsHadrEnabled
                    StartTime        = $row.StartTime
                    UptimeDays       = [math]::Round(($row.ServerTime - $row.StartTime).TotalDays, 1)
                    CpuCount         = $row.CpuCount
                    PhysicalMemoryMB = $row.PhysicalMemoryMB
                    MaxServerMemoryMB = $row.MaxServerMemoryMB
                    Maxdop           = $row.Maxdop
                    CostThreshold    = $row.CostThreshold
                    TempdbFiles      = $row.TempdbFiles
                    Flags            = $flags -join ', '
                }
            }
        }
    }
}
