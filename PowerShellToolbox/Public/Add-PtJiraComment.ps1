function Add-PtJiraComment {
    <#
    .SYNOPSIS
    Adds a comment to a Jira issue.

    .DESCRIPTION
    Needs Connect-PtJira first. The text is sent as an Atlassian Document Format
    document with one paragraph per line; no markup is interpreted. Supports
    -WhatIf and -Confirm.

    .PARAMETER Key
    The issue key, for example OPS-123.

    .PARAMETER Body
    The comment text.

    .EXAMPLE
    Add-PtJiraComment -Key OPS-123 -Body 'Restarted the agent job, backlog is draining.'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Body
    )

    process {
        if ($PSCmdlet.ShouldProcess($Key, 'Add a comment')) {
            $response = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key/comment" -Method Post -Body @{ body = (ConvertTo-PtAdf -Text $Body) }
            [pscustomobject]@{
                Key       = $Key
                CommentId = $response.id
                Created   = ConvertFrom-PtJiraDate -Text $response.created
            }
        }
    }
}
