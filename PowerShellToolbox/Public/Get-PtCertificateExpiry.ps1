function Get-PtCertificateExpiry {
    <#
    .SYNOPSIS
    Lists certificates in a Windows certificate store with the days left until they expire.

    .DESCRIPTION
    Reads Cert:\<StoreLocation>\<StoreName> on each computer (remote computers
    are reached with Invoke-Command, so PowerShell remoting must be enabled) and
    returns one object per certificate, oldest expiry first. Status is Expired,
    Expiring (within WarningDays) or OK.

    .PARAMETER ComputerName
    The computers to check. Defaults to the local computer.

    .PARAMETER StoreName
    The store, for example My (personal), WebHosting or Root. Default My.

    .PARAMETER StoreLocation
    LocalMachine (default) or CurrentUser.

    .PARAMETER WarningDays
    Certificates that expire within this many days are Expiring. Default 30.

    .EXAMPLE
    Get-PtCertificateExpiry -ComputerName WEB01, WEB02 | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [string]$StoreName = 'My',

        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation = 'LocalMachine',

        [ValidateRange(1, 3650)]
        [int]$WarningDays = 30
    )

    begin {
        $readStore = {
            param($Location, $Store)
            Get-ChildItem -Path "Cert:\$Location\$Store" | ForEach-Object {
                [pscustomobject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    Thumbprint    = $_.Thumbprint
                    NotAfter      = $_.NotAfter
                    HasPrivateKey = $_.HasPrivateKey
                    DnsNames      = (@($_.DnsNameList | ForEach-Object { $_.Unicode }) -join ', ')
                }
            }
        }
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                if ($localNames -contains $computer) {
                    $certificates = @(& $readStore $StoreLocation $StoreName)
                }
                else {
                    $certificates = @(Invoke-Command -ComputerName $computer -ScriptBlock $readStore -ArgumentList $StoreLocation, $StoreName -ErrorAction Stop)
                }
            }
            catch {
                Write-Warning "Could not read the $StoreLocation\$StoreName store on $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($certificate in ($certificates | Sort-Object -Property NotAfter)) {
                $daysLeft = [int][math]::Floor(($certificate.NotAfter - (Get-Date)).TotalDays)
                if ($daysLeft -lt 0) { $status = 'Expired' }
                elseif ($daysLeft -le $WarningDays) { $status = 'Expiring' }
                else { $status = 'OK' }

                [pscustomobject]@{
                    ComputerName  = $computer
                    Subject       = $certificate.Subject
                    DnsNames      = $certificate.DnsNames
                    Thumbprint    = $certificate.Thumbprint
                    NotAfter      = $certificate.NotAfter
                    DaysLeft      = $daysLeft
                    Status        = $status
                    HasPrivateKey = $certificate.HasPrivateKey
                    Issuer        = $certificate.Issuer
                }
            }
        }
    }
}
