function Test-PtCommandParameter {
    <#
    .SYNOPSIS
    Tells whether a command has a parameter of the given name.

    .DESCRIPTION
    Used to give a clear message when a newer version of another module is needed
    (for example an Invoke-Sqlcmd without -TrustServerCertificate), instead of the
    generic 'parameter cannot be found' error. Returns $false if the command does
    not exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Parameter
    )

    $found = Get-Command -Name $Command -ErrorAction SilentlyContinue
    if (-not $found) { return $false }
    return $found.Parameters.ContainsKey($Parameter)
}
