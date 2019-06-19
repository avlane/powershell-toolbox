# PowerShellToolbox - small admin helpers for Windows PowerShell 5.1

function Get-PtDiskReport {
    <#
    .SYNOPSIS
    Reports the free space on the fixed disks of one or more computers.

    .DESCRIPTION
    Queries Win32_LogicalDisk (fixed disks only, DriveType 3) with WMI and returns
    one object per disk with size, free space and a status of OK or Low.

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER WarningPercent
    A disk with less than this percentage free is reported as Low. Default 10.

    .EXAMPLE
    Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 -WarningPercent 15

    Shows the disks of both servers, flagging those under 15 percent free.

    .EXAMPLE
    Get-PtDiskReport | Where-Object Status -eq 'Low'

    Only the local disks that are running out of space.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(1, 99)]
        [int]$WarningPercent = 10
    )

    process {
        foreach ($computer in $ComputerName) {
            try {
                $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $computer -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not query $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($disk in $disks) {
                $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                if ($freePercent -lt $WarningPercent) { $status = 'Low' } else { $status = 'OK' }

                [pscustomobject]@{
                    ComputerName = $computer
                    Drive        = $disk.DeviceID
                    Label        = $disk.VolumeName
                    SizeGB       = [math]::Round($disk.Size / 1GB, 1)
                    FreeGB       = [math]::Round($disk.FreeSpace / 1GB, 1)
                    FreePercent  = $freePercent
                    Status       = $status
                }
            }
        }
    }
}

function Get-PtServiceTriage {
    <#
    .SYNOPSIS
    Lists services that are set to start automatically but are not running.

    .DESCRIPTION
    Uses Win32_Service on each computer and returns the automatic services that are
    stopped, together with the account they run as and the exit code of their
    last run. Services that start with a delayed trigger (DelayedAutoStart) and
    well-known ones that are meant to stop themselves are left out unless
    -IncludeExpected is given.

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER IncludeExpected
    Also list services that normally stop on their own, such as the Software
    Protection and Google Update services.

    .EXAMPLE
    Get-PtServiceTriage -ComputerName SQLPROD01

    .EXAMPLE
    Get-PtServiceTriage | Format-Table ComputerName, Name, StartName, ExitCode
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [switch]$IncludeExpected
    )

    begin {
        # automatic services that exit after doing their work
        $expected = @('sppsvc', 'gupdate', 'gupdatem', 'RemoteRegistry', 'ClrOptimization_v4.0.30319_32', 'ClrOptimization_v4.0.30319_64', 'TrustedInstaller')
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $services = Get-WmiObject -Class Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'" -ComputerName $computer -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not query $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($service in $services) {
                if (-not $IncludeExpected -and $expected -contains $service.Name) { continue }

                [pscustomobject]@{
                    ComputerName = $computer
                    Name         = $service.Name
                    DisplayName  = $service.DisplayName
                    State        = $service.State
                    StartName    = $service.StartName
                    ExitCode     = $service.ExitCode
                }
            }
        }
    }
}

function Get-PtEventLogSummary {
    <#
    .SYNOPSIS
    Summarises the errors and warnings in an event log by source and event id.

    .DESCRIPTION
    Reads the events of the last few hours with Get-WinEvent and groups them by
    provider and event id, so a flood of the same error shows up as one row with a
    count instead of thousands of lines. The most frequent groups come first.

    .PARAMETER ComputerName
    The computers to read. Defaults to the local computer.

    .PARAMETER LogName
    The log to read. Default System.

    .PARAMETER Hours
    How far back to look. Default 24.

    .PARAMETER Level
    Which severities to include: Critical, Error, Warning. Default Critical and Error.

    .PARAMETER Top
    How many groups to return per computer. Default 10.

    .EXAMPLE
    Get-PtEventLogSummary -ComputerName SQLPROD01 -LogName Application -Hours 6 -Level Error, Warning
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [string]$LogName = 'System',

        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [ValidateSet('Critical', 'Error', 'Warning')]
        [string[]]$Level = @('Critical', 'Error'),

        [ValidateRange(1, 1000)]
        [int]$Top = 10
    )

    begin {
        $levelNumbers = @{ Critical = 1; Error = 2; Warning = 3 }
        $levels = @($Level | ForEach-Object { $levelNumbers[$_] })
        $start = (Get-Date).AddHours(-$Hours)
    }

    process {
        foreach ($computer in $ComputerName) {
            $filter = @{ LogName = $LogName; Level = $levels; StartTime = $start }
            try {
                $events = Get-WinEvent -ComputerName $computer -FilterHashtable $filter -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not read the $LogName log on $computer : $($_.Exception.Message)"
                continue
            }

            $groups = $events | Group-Object -Property ProviderName, Id | Sort-Object -Property Count -Descending | Select-Object -First $Top
            foreach ($group in $groups) {
                $newest = $group.Group | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
                $oldest = $group.Group | Sort-Object -Property TimeCreated | Select-Object -First 1
                $firstLine = ''
                if ($newest.Message) { $firstLine = ($newest.Message -split "`r?`n")[0] }

                [pscustomobject]@{
                    ComputerName = $computer
                    Provider     = $newest.ProviderName
                    EventId      = $newest.Id
                    Level        = $newest.LevelDisplayName
                    Count        = $group.Count
                    FirstSeen    = $oldest.TimeCreated
                    LastSeen     = $newest.TimeCreated
                    Message      = $firstLine
                }
            }
        }
    }
}
