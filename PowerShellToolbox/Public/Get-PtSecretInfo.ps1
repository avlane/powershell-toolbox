function Get-PtSecretInfo {
    <#
    .SYNOPSIS
    Lists the secrets in the module's vault by name and type, without their values.

    .DESCRIPTION
    A wrapper around Get-SecretInfo from Microsoft.PowerShell.SecretManagement for the
    PowerShellToolbox vault. Useful to see what is stored (and to find a name you
    forgot) without putting any secret on screen.

    .PARAMETER Name
    A name or wildcard. Default *.

    .PARAMETER Vault
    The vault. Default PowerShellToolbox.

    .EXAMPLE
    Get-PtSecretInfo -Name 'jira*'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name = '*',

        [string]$Vault = 'PowerShellToolbox'
    )

    if (-not (Get-Command -Name Get-SecretInfo -ErrorAction SilentlyContinue)) {
        throw 'Get-SecretInfo was not found. Install the module with: Install-Module Microsoft.PowerShell.SecretManagement'
    }

    Get-SecretInfo -Name $Name -Vault $Vault -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name      = $_.Name
            Type      = [string]$_.Type
            VaultName = $_.VaultName
        }
    }
}
