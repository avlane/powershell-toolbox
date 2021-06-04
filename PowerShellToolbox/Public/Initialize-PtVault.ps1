function Initialize-PtVault {
    <#
    .SYNOPSIS
    Registers a SecretStore vault for this module's secrets, if it is not there yet.

    .DESCRIPTION
    Uses the Microsoft.PowerShell.SecretManagement and Microsoft.PowerShell.SecretStore
    modules (Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore).
    Creates a vault named PowerShellToolbox, backed by SecretStore, in the current
    user's profile. Does nothing if a vault of that name exists.

    The first time a SecretStore vault is used it asks for a password; to run
    unattended, configure it yourself first with Set-SecretStoreConfiguration. This
    command does not do that for you, because the choice (password, no password,
    how long to stay unlocked) is a security decision.

    .PARAMETER VaultName
    The vault name. Default PowerShellToolbox.

    .PARAMETER DefaultVault
    Make this the default vault for Get-Secret and Set-Secret.

    .EXAMPLE
    Initialize-PtVault
    Set-PtSecret -Name jira-api-token -Credential (Get-Credential)
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$VaultName = 'PowerShellToolbox',

        [switch]$DefaultVault
    )

    foreach ($module in 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore') {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "The $module module is not installed. Install it with: Install-Module $module"
        }
    }

    $existing = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
    if ($existing) { return $existing }

    if ($PSCmdlet.ShouldProcess($VaultName, 'Register a SecretStore vault')) {
        Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault:$DefaultVault
        Get-SecretVault -Name $VaultName
    }
}
