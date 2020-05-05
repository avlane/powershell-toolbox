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
                $services = Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'" -ComputerName $computer -ErrorAction Stop
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
