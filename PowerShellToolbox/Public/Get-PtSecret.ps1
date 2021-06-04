function Get-PtSecret {
    <#
    .SYNOPSIS
    Reads a secret from the module's vault.

    .DESCRIPTION
    A small wrapper around Get-Secret from Microsoft.PowerShell.SecretManagement that
    defaults to the PowerShellToolbox vault. A stored credential comes back as a
    PSCredential and a stored string as a SecureString, so passwords do not
    sit around as plain text. -AsPlainText returns a string secret as text; use it
    only where an API insists.

    .PARAMETER Name
    The name of the secret.

    .PARAMETER Vault
    The vault. Default PowerShellToolbox.

    .PARAMETER AsPlainText
    Return a string secret as plain text.

    .EXAMPLE
    $credential = Get-PtSecret -Name jira-api-token
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$Vault = 'PowerShellToolbox',

        [switch]$AsPlainText
    )

    if (-not (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue)) {
        throw 'Get-Secret was not found. Install the module with: Install-Module Microsoft.PowerShell.SecretManagement'
    }

    $parameters = @{ Name = $Name; Vault = $Vault; ErrorAction = 'Stop' }
    if ($AsPlainText) { $parameters['AsPlainText'] = $true }
    Get-Secret @parameters
}
