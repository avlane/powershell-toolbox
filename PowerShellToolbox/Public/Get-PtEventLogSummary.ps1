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
                # Get-WinEvent reports "no matching events" as an error, but for a
                # health check that is the good news, not a failure
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                    Write-Verbose "No matching events in the $LogName log on $computer."
                    continue
                }
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
