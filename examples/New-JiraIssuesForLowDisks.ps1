<#
.SYNOPSIS
Example: opens one Jira issue for every disk that is running low, unless one is already open.

.DESCRIPTION
Shows how the commands of the module fit together: Get-PtDiskReport finds the
disks, New-PtJql and Search-PtJiraIssue look for an open issue about the same disk
(each issue gets a label made from the computer and the drive, so the search does
not depend on the wording of the summary), and New-PtJiraIssue creates the missing
ones. Run it with -WhatIf first to see which issues it would create.

The Jira credential is read from the module's vault (Set-PtSecret -Name jira-api-token
-Credential (Get-Credential), the user name being the account's e-mail address).

.PARAMETER ComputerName
The computers to check.

.PARAMETER BaseUri
The Jira Cloud site, for example https://example.atlassian.net

.PARAMETER ProjectKey
The project to create the issues in.

.PARAMETER SecretName
The vault secret holding the e-mail address and API token. Default jira-api-token.

.PARAMETER WarningPercent
Disks with less free space than this are reported. Default 10.

.EXAMPLE
./examples/New-JiraIssuesForLowDisks.ps1 -ComputerName SQLPROD01, SQLPROD02 -BaseUri https://example.atlassian.net -ProjectKey OPS -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $true)]
    [string]$BaseUri,

    [Parameter(Mandatory = $true)]
    [string]$ProjectKey,

    [string]$SecretName = 'jira-api-token',

    [ValidateRange(1, 99)]
    [int]$WarningPercent = 10
)

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Join-Path $root 'PowerShellToolbox') 'PowerShellToolbox.psd1') -Force -ErrorAction Stop

Connect-PtJira -BaseUri $BaseUri -SecretName $SecretName | Out-Null

$lowDisks = Get-PtDiskReport -ComputerName $ComputerName -WarningPercent $WarningPercent -IncludeMountPoints | Where-Object Status -eq 'Low'
foreach ($disk in $lowDisks) {
    # a label can only hold letters, digits and a few punctuation marks, so reduce the
    # computer and drive (E:\SQLData\) to letters and digits
    $key = ("$($disk.ComputerName)$($disk.Drive)" -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    $label = "disk-$key"

    $existing = @(Search-PtJiraIssue (New-PtJql -Project $ProjectKey -Label $label -NotStatusCategory Done) -First 1)
    if ($existing.Count -gt 0) {
        [pscustomobject]@{ Computer = $disk.ComputerName; Drive = $disk.Drive; Action = "already open: $($existing[0].Key)" }
        continue
    }

    $summary = "Low disk space on $($disk.ComputerName) $($disk.Drive): $($disk.FreePercent) percent free"
    $description = "Found by Get-PtDiskReport on $(Get-Date -Format 'yyyy-MM-dd HH:mm').`n$($disk.FreeGB) GB free of $($disk.SizeGB) GB. Volume label: $($disk.Label)."
    $created = New-PtJiraIssue -ProjectKey $ProjectKey -Summary $summary -Description $description -Label 'disk-space-auto', $label -WhatIf:$WhatIfPreference -Confirm:$false
    [pscustomobject]@{ Computer = $disk.ComputerName; Drive = $disk.Drive; Action = $created ? "created $($created.Key)" : 'would create (WhatIf)' }
}
