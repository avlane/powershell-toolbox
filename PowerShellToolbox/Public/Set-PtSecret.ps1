function Set-PtSecret {
    <#
    .SYNOPSIS
    Stores a secret (a credential or a secure string) in the module's vault.

    .DESCRIPTION
    A small wrapper around Set-Secret from Microsoft.PowerShell.SecretManagement that
    defaults to the PowerShellToolbox vault (see Initialize-PtVault). Pass a
    PSCredential for things that have a user name and a password or token, such as a
    Jira account (e-mail address plus API token); pass a SecureString for a single
    value. An existing secret of the same name is replaced. Supports -WhatIf.

    .PARAMETER Name
    The name of the secret, for example jira-api-token.

    .PARAMETER Credential
    A credential to store.

    .PARAMETER SecureString
    A secure string to store.

    .PARAMETER Vault
    The vault. Default PowerShellToolbox.

    .EXAMPLE
    Set-PtSecret -Name jira-api-token -Credential (Get-Credential -Message 'E-mail and API token')
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Credential')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'Credential')]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true, ParameterSetName = 'SecureString')]
        [securestring]$SecureString,

        [string]$Vault = 'PowerShellToolbox'
    )

    if (-not (Get-Command -Name Set-Secret -ErrorAction SilentlyContinue)) {
        throw 'Set-Secret was not found. Install the module with: Install-Module Microsoft.PowerShell.SecretManagement'
    }

    if ($PSCmdlet.ShouldProcess("$Vault/$Name", 'Store the secret')) {
        if ($PSCmdlet.ParameterSetName -eq 'Credential') { $value = $Credential } else { $value = $SecureString }
        Set-Secret -Name $Name -Secret $value -Vault $Vault -ErrorAction Stop
    }
}
