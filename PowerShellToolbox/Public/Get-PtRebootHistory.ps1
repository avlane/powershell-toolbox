function Get-PtRebootHistory {
    <#
    .SYNOPSIS
    Lists the restarts and unexpected shutdowns of a Windows computer from the System log.

    .DESCRIPTION
    Reads these events and labels them:

      1074  Planned     a process or user restarted or shut down the computer, with
                        the reason, the program and the user
      6008  Unexpected  the previous shutdown was unexpected
      41    Crash       Kernel-Power: the system rebooted without cleanly shutting
                        down first (power loss, hang, blue screen); the bugcheck
                        code is shown if there was one
      6005  Boot        the event log service started, which is when the system came up

    Newest first. Use it to answer "why did SQLPROD01 restart at 3 in the morning?"
    (usually Windows Update, and event 1074 says so).

    .PARAMETER ComputerName
    The computers to read. Defaults to the local computer.

    .PARAMETER Days
    How far back to look. Default 30.

    .PARAMETER OnlyUnexpected
    Only the Unexpected and Crash events.

    .EXAMPLE
    Get-PtRebootHistory -ComputerName SQLPROD01 -Days 14 | Format-Table Time, Kind, User, Reason
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(1, 3650)]
        [int]$Days = 30,

        [switch]$OnlyUnexpected
    )

    begin {
        $kinds = @{ 1074 = 'Planned'; 6008 = 'Unexpected'; 41 = 'Crash'; 6005 = 'Boot' }
        $ids = $OnlyUnexpected ? @(6008, 41) : @(1074, 6008, 41, 6005)
    }

    process {
        foreach ($computer in $ComputerName) {
            $filter = @{ LogName = 'System'; Id = $ids; StartTime = (Get-Date).AddDays(-$Days) }
            try {
                $events = @(Get-WinEvent -ComputerName $computer -FilterHashtable $filter -ErrorAction Stop)
            }
            catch {
                if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                    Write-Warning "Could not read the System log on $computer : $($_.Exception.Message)"
                }
                continue
            }

            foreach ($logEvent in ($events | Sort-Object -Property TimeCreated -Descending)) {
                $properties = @($logEvent.Properties | ForEach-Object { $_.Value })
                $reason = ''
                $user = ''
                $process = ''
                $detail = ''

                if ($logEvent.Id -eq 1074 -and $properties.Count -ge 7) {
                    $process = [string]$properties[0]
                    $reason = [string]$properties[2]
                    $user = [string]$properties[6]
                    $detail = [string]$properties[5]
                }
                elseif ($logEvent.Id -eq 41 -and $properties.Count -ge 1 -and [int64]$properties[0] -ne 0) {
                    $detail = 'Bugcheck code 0x{0:X}' -f [int64]$properties[0]
                }

                [pscustomobject]@{
                    ComputerName = $computer
                    Time         = $logEvent.TimeCreated
                    Kind         = $kinds[[int]$logEvent.Id]
                    EventId      = $logEvent.Id
                    Process      = $process
                    Reason       = $reason
                    User         = $user
                    Detail       = $detail
                }
            }
        }
    }
}
