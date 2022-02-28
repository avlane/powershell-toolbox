function Restart-PtFailedService {
    <#
    .SYNOPSIS
    Starts services that should be running but are not, and waits until they are.

    .DESCRIPTION
    Takes the output of Get-PtServiceTriage (or a name and computer) and starts each
    service through CIM, which also works for remote computers and in PowerShell 7,
    where Get-Service has no -ComputerName. After starting it waits up to
    TimeoutSeconds for the state Running. The result per service is Started,
    AlreadyRunning, NotFound or Failed.

    Starting services is a change to a production machine, so ConfirmImpact is High:
    you are asked for each service unless you pass -Confirm:$false, and -WhatIf
    shows what would be started. Wildcards in names are not accepted on purpose.

    .PARAMETER Name
    The service name (not the display name).

    .PARAMETER ComputerName
    The computer. Default: the local computer.

    .PARAMETER TimeoutSeconds
    How long to wait for the service to reach Running. Default 60.

    .EXAMPLE
    Get-PtServiceTriage -ComputerName SQLPROD01 | Restart-PtFailedService -WhatIf

    .EXAMPLE
    Restart-PtFailedService -Name MSSQLSERVER -ComputerName SQLPROD01 -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[^*?\[\]]+$')]
        [string]$Name,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 60
    )

    process {
        $filter = "Name = '" + ($Name -replace "'", "''") + "'"

        try {
            $service = Get-CimInstance -ClassName Win32_Service -Filter $filter -ComputerName $ComputerName -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not query $ComputerName : $($_.Exception.Message)"
            return
        }

        $result = 'Failed'
        $detail = ''
        if (-not $service) {
            $result = 'NotFound'
            $detail = "There is no service called $Name on $ComputerName."
        }
        elseif ($service.State -eq 'Running') {
            $result = 'AlreadyRunning'
        }
        elseif ($PSCmdlet.ShouldProcess("$Name on $ComputerName", 'Start the service')) {
            try {
                $call = Invoke-CimMethod -InputObject $service -MethodName StartService -ErrorAction Stop
                if ($call.ReturnValue -ne 0 -and $call.ReturnValue -ne 10) {
                    $detail = "StartService returned code $($call.ReturnValue)."
                }
                else {
                    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
                    do {
                        Start-Sleep -Seconds 2
                        $service = Get-CimInstance -ClassName Win32_Service -Filter $filter -ComputerName $ComputerName -ErrorAction Stop
                    } while ($service.State -ne 'Running' -and (Get-Date) -lt $deadline)

                    if ($service.State -eq 'Running') { $result = 'Started' }
                    else { $detail = "The service is still $($service.State) after $TimeoutSeconds seconds." }
                }
            }
            catch {
                $detail = $_.Exception.Message
            }
        }
        else {
            return
        }

        [pscustomobject]@{
            ComputerName = $ComputerName
            Name         = $Name
            Result       = $result
            State        = ${service}?.State
            Detail       = $detail
        }
    }
}
