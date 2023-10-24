function Test-PtTlsCertificate {
    <#
    .SYNOPSIS
    Connects to a TLS endpoint and reports the certificate it presents.

    .DESCRIPTION
    Opens a TCP connection, does the TLS handshake with SslStream and reads the server
    certificate: subject, issuer, validity, thumbprint, the DNS names it covers, the
    protocol that was negotiated, and whether the platform trusts it for the host name
    used. This is what a browser or a client library would see, so it also covers
    certificates that are not in a Windows store, such as those of a load balancer, a
    SQL Server (port 1433) or an LDAPS endpoint.

    The handshake accepts any certificate on purpose, so that a bad one can be
    described instead of failing the connection; nothing is sent over it. The
    result's Status is Expired, NameMismatch, Untrusted, Expiring or OK.

    .PARAMETER HostName
    The host to connect to.

    .PARAMETER Port
    The TCP port. Default 443.

    .PARAMETER ServerName
    The name to ask for (SNI) and to check the certificate against, when it differs
    from HostName, for example when connecting to an IP address.

    .PARAMETER WarningDays
    A certificate that expires within this many days is Expiring. Default 30.

    .PARAMETER TimeoutSeconds
    Connect and handshake timeout. Default 10.

    .EXAMPLE
    'www.example.com', 'api.example.com' | Test-PtTlsCertificate | Format-Table HostName, Status, DaysLeft, NotAfter

    .EXAMPLE
    Test-PtTlsCertificate -HostName sqlprod01.corp.example.com -Port 1433
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$HostName,

        [ValidateRange(1, 65535)]
        [int]$Port = 443,

        [string]$ServerName,

        [ValidateRange(1, 3650)]
        [int]$WarningDays = 30,

        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 10
    )

    process {
        foreach ($target in $HostName) {
            $sni = $ServerName ? $ServerName : $target
            $timeoutMs = $TimeoutSeconds * 1000
            $captured = @{ Errors = [System.Net.Security.SslPolicyErrors]::None }
            $callback = [System.Net.Security.RemoteCertificateValidationCallback]({
                    param($sender, $certificate, $chain, $sslPolicyErrors)
                    $captured.Errors = $sslPolicyErrors
                    $true
                }.GetNewClosure())

            $client = New-Object -TypeName System.Net.Sockets.TcpClient
            $stream = $null
            $ssl = $null
            try {
                if (-not $client.ConnectAsync($target, $Port).Wait($timeoutMs)) {
                    throw "no connection within $TimeoutSeconds seconds"
                }
                $stream = $client.GetStream()
                $stream.ReadTimeout = $timeoutMs
                $stream.WriteTimeout = $timeoutMs
                $ssl = New-Object -TypeName System.Net.Security.SslStream -ArgumentList $stream, $false, $callback
                $ssl.AuthenticateAsClient($sni)

                $certificate = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $ssl.RemoteCertificate
                $san = $certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } | ForEach-Object { $_.Format($false) }
                $names = [regex]::Matches([string]$san, 'DNS Name=([^,\s]+)') | ForEach-Object { $_.Groups[1].Value }

                [pscustomobject]@{
                    HostName      = $target
                    Port          = $Port
                    Status        = Get-PtTlsStatus -NotAfter $certificate.NotAfter -PolicyErrors $captured.Errors -WarningDays $WarningDays
                    DaysLeft      = [int][math]::Floor(($certificate.NotAfter - (Get-Date)).TotalDays)
                    NotAfter      = $certificate.NotAfter
                    Subject       = $certificate.Subject
                    Issuer        = $certificate.Issuer
                    DnsNames      = @($names) -join ', '
                    Thumbprint    = $certificate.Thumbprint
                    Protocol      = [string]$ssl.SslProtocol
                    PolicyErrors  = [string]$captured.Errors
                    Error         = $null
                }
            }
            catch {
                [pscustomobject]@{
                    HostName      = $target
                    Port          = $Port
                    Status        = 'Failed'
                    DaysLeft      = $null
                    NotAfter      = $null
                    Subject       = $null
                    Issuer        = $null
                    DnsNames      = $null
                    Thumbprint    = $null
                    Protocol      = $null
                    PolicyErrors  = $null
                    Error         = $_.Exception.Message
                }
            }
            finally {
                if ($ssl) { $ssl.Dispose() }
                if ($stream) { $stream.Dispose() }
                $client.Dispose()
            }
        }
    }
}
