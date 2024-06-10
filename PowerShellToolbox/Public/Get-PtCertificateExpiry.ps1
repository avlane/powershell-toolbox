function Get-PtCertificateExpiry {
    <#
    .SYNOPSIS
    Lists certificates in a Windows certificate store with the days left until they expire.

    .DESCRIPTION
    Reads Cert:\<StoreLocation>\<StoreName> on each computer (remote computers
    are reached with one Invoke-Command call that talks to several of them at a time,
    so PowerShell remoting must be enabled) and
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

    .PARAMETER Subject
    Only certificates whose subject matches this wildcard, for example *example.com*.

    .PARAMETER ExcludeThumbprint
    Certificates to ignore, by thumbprint (for old ones that are known and kept on purpose).

    .PARAMETER OnlyProblems
    Leave out certificates whose Status is OK.

    .PARAMETER ThrottleLimit
    How many remote computers Invoke-Command talks to at the same time. Default 32.

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
        [int]$WarningDays = 30,

        [string]$Subject,

        [string[]]$ExcludeThumbprint,

        [switch]$OnlyProblems,

        [ValidateRange(1, 256)]
        [int]$ThrottleLimit = 32
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
        $requested = New-Object -TypeName 'System.Collections.Generic.List[string]'
    }

    process {
        foreach ($computer in $ComputerName) { $requested.Add($computer) }
    }

    end {
        $entries = New-Object -TypeName 'System.Collections.Generic.List[object]'

        $remote = @($requested | Where-Object { $localNames -notcontains $_ } | Select-Object -Unique)
        foreach ($computer in @($requested | Where-Object { $localNames -contains $_ } | Select-Object -Unique)) {
            try {
                foreach ($certificate in @(& $readStore $StoreLocation $StoreName)) { $entries.Add([pscustomobject]@{ Computer = $computer; Certificate = $certificate }) }
            }
            catch {
                Write-Warning "Could not read the $StoreLocation\$StoreName store on $computer : $($_.Exception.Message)"
            }
        }

        if ($remote.Count -gt 0) {
            # one call for all remote computers, run side by side; computers that fail
            # come back as errors, not as results
            $remoteErrors = @()
            $remoteResults = @(Invoke-Command -ComputerName $remote -ScriptBlock $readStore -ArgumentList $StoreLocation, $StoreName -ThrottleLimit $ThrottleLimit -ErrorAction SilentlyContinue -ErrorVariable remoteErrors)
            foreach ($certificate in $remoteResults) { $entries.Add([pscustomobject]@{ Computer = [string]$certificate.PSComputerName; Certificate = $certificate }) }
            foreach ($failure in $remoteErrors) {
                $name = $failure.TargetObject ?? $failure.OriginInfo.PSComputerName
                Write-Warning "Could not read the $StoreLocation\$StoreName store on $name : $($failure.Exception.Message)"
            }
        }

        foreach ($computer in ($entries | Select-Object -ExpandProperty Computer -Unique)) {
            foreach ($certificate in (($entries | Where-Object { $_.Computer -eq $computer }).Certificate | Sort-Object -Property NotAfter)) {
                if ($Subject -and $certificate.Subject -notlike $Subject) { continue }
                if ($ExcludeThumbprint -contains $certificate.Thumbprint) { continue }

                $daysLeft = [int][math]::Floor(($certificate.NotAfter - (Get-Date)).TotalDays)
                $status = $daysLeft -lt 0 ? 'Expired' : ($daysLeft -le $WarningDays ? 'Expiring' : 'OK')
                if ($OnlyProblems -and $status -eq 'OK') { continue }

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
