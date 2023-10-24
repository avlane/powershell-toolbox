function Get-PtTlsStatus {
    <#
    .SYNOPSIS
    Decides the status word for a TLS certificate seen on an endpoint.

    .DESCRIPTION
    Expired wins over everything, then NameMismatch (the certificate is not valid for
    the host name that was asked for), then Untrusted (the chain does not lead to a
    trusted root), then Expiring (within WarningDays), otherwise OK. PolicyErrors is
    the SslPolicyErrors value from the validation callback, as text or number.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$NotAfter,

        [System.Net.Security.SslPolicyErrors]$PolicyErrors = [System.Net.Security.SslPolicyErrors]::None,

        [ValidateRange(1, 3650)]
        [int]$WarningDays = 30,

        [datetime]$Now = (Get-Date)
    )

    if ($NotAfter -lt $Now) { return 'Expired' }
    if ($PolicyErrors.HasFlag([System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch)) { return 'NameMismatch' }
    if ($PolicyErrors.HasFlag([System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors)) { return 'Untrusted' }
    if ($NotAfter -lt $Now.AddDays($WarningDays)) { return 'Expiring' }
    return 'OK'
}
