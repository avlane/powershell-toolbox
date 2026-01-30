function Get-PtServiceTriage {
    <#
    .SYNOPSIS
    Lists services that are set to start automatically but are not running.

    .DESCRIPTION
    Uses Win32_Service on each computer and returns the automatic services that are
    stopped, together with the account they run as and the exit code of their
    last run. A short list of well-known services that are meant to stop
    themselves after doing their work is left out unless -IncludeExpected is given.

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER OnlyFailed
    Only services that stopped with an error: an exit code other than 0 (stopped
    normally) and 1077 (not started since boot, which is what services that start on a
    trigger or after a delay show until their time comes). Cuts out most of the noise
    from automatic services that are stopped on purpose.

    .PARAMETER IncludeLastEvent
    For each service, look in the System log of the last 7 days for the newest
    Service Control Manager event that names it (terminated unexpectedly, failed to
    start, logon failure ...) and add its time, id and first line as LastEventTime,
    LastEventId and LastEventMessage. Costs one extra event log query per computer.

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

        [switch]$IncludeExpected,

        [switch]$OnlyFailed,

        [switch]$IncludeLastEvent
    )

    begin {
        # automatic services that exit after doing their work
        $expected = @('sppsvc', 'gupdate', 'gupdatem', 'RemoteRegistry', 'ClrOptimization_v4.0.30319_32', 'ClrOptimization_v4.0.30319_64', 'TrustedInstaller')
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $services = Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'" -ComputerName $computer -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not query $computer : $($_.Exception.Message)"
                continue
            }

            $events = @()
            if ($IncludeLastEvent) {
                # 7000/7001/7009/7011/7023/7024/7031/7034: failed to start, timeout, stopped or crashed
                $filter = @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7000, 7001, 7009, 7011, 7023, 7024, 7031, 7034; StartTime = (Get-Date).AddDays(-7) }
                try {
                    $events = @(Get-WinEvent -ComputerName $computer -FilterHashtable $filter -MaxEvents 500 -ErrorAction Stop)
                }
                catch {
                    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                        Write-Warning "Could not read the System log on $computer : $($_.Exception.Message)"
                    }
                }
            }

            foreach ($service in $services) {
                if (-not $IncludeExpected -and $expected -contains $service.Name) { continue }
                if ($OnlyFailed -and $service.ExitCode -in 0, 1077) { continue }

                $row = [ordered]@{
                    ComputerName = $computer
                    Name         = $service.Name
                    DisplayName  = $service.DisplayName
                    State        = $service.State
                    StartName    = $service.StartName
                    ExitCode     = $service.ExitCode
                }

                if ($IncludeLastEvent) {
                    $last = $events | Where-Object { $_.Message -like "*$($service.DisplayName)*" } | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
                    $row['LastEventTime'] = ${last}?.TimeCreated
                    $row['LastEventId'] = ${last}?.Id
                    $row['LastEventMessage'] = $last ? ($last.Message -split "`r?`n")[0] : $null
                }

                [pscustomobject]$row
            }
        }
    }
}
