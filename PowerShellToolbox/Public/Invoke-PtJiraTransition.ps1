function Invoke-PtJiraTransition {
    <#
    .SYNOPSIS
    Moves a Jira issue through its workflow, by transition name or id.

    .DESCRIPTION
    Looks up the transitions that are available for the issue (see
    Get-PtJiraTransition), picks the one whose name or id matches and performs it,
    optionally adding a comment in the same request. Fails with the list of
    available transitions if there is no match. Supports -WhatIf and -Confirm.

    .PARAMETER Key
    The issue key, for example OPS-123.

    .PARAMETER Transition
    The name (case-insensitive) or the numeric id of the transition.

    .PARAMETER Comment
    A comment to add together with the transition.

    .EXAMPLE
    Invoke-PtJiraTransition -Key OPS-123 -Transition 'Done' -Comment 'Fixed in the 2020-09 patch run.'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Transition,

        [string]$Comment
    )

    process {
        $available = @(Get-PtJiraTransition -Key $Key)
        $match = @($available | Where-Object { $_.Id -eq $Transition -or $_.Name -eq $Transition }) | Select-Object -First 1
        if (-not $match) {
            $names = ($available | ForEach-Object { "$($_.Name) ($($_.Id))" }) -join ', '
            throw "$Key has no transition called '$Transition'. Available now: $names"
        }

        if ($PSCmdlet.ShouldProcess($Key, "Transition to $($match.ToStatus) ($($match.Name))")) {
            $body = @{ transition = @{ id = $match.Id } }
            if ($Comment) {
                $body['update'] = @{ comment = @(@{ add = @{ body = (ConvertTo-PtAdf -Text $Comment) } }) }
            }
            Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key/transitions" -Method Post -Body $body | Out-Null
            [pscustomobject]@{ Key = $Key; Transition = $match.Name; ToStatus = $match.ToStatus }
        }
    }
}
