function Remove-PtSecret {
    <#
    .SYNOPSIS
    Deletes a secret from the module's vault.

    .DESCRIPTION
    A wrapper around Remove-Secret from Microsoft.PowerShell.SecretManagement for the
    PowerShellToolbox vault. Deleting cannot be undone, so ConfirmImpact is High:
    you are asked first unless you pass -Confirm:$false. Supports -WhatIf.

    .PARAMETER Name
    The name of the secret.

    .PARAMETER Vault
    The vault. Default PowerShellToolbox.

    .EXAMPLE
    Remove-PtSecret -Name jira-api-token -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('VaultName')]
        [string]$Vault = 'PowerShellToolbox'
    )

    process {
        if (-not (Get-Command -Name Remove-Secret -ErrorAction SilentlyContinue)) {
            throw 'Remove-Secret was not found. Install the module with: Install-Module Microsoft.PowerShell.SecretManagement'
        }

        if ($PSCmdlet.ShouldProcess("$Vault/$Name", 'Delete the secret')) {
            Remove-Secret -Name $Name -Vault $Vault -ErrorAction Stop
        }
    }
}
