function New-PtJiraIssue {
    <#
    .SYNOPSIS
    Creates a Jira issue.

    .DESCRIPTION
    Needs Connect-PtJira first. The description is sent as an Atlassian Document
    Format document with one paragraph per line. People are given as account ids
    (see Find-PtJiraUser); labels may not contain spaces. Supports -WhatIf and
    -Confirm, which show the request body instead of sending it.

    Required fields that a project's screens add on top of these (custom fields)
    are not covered; Jira answers with an error that names them.

    .PARAMETER ProjectKey
    The project, for example OPS.

    .PARAMETER Summary
    The title of the issue.

    .PARAMETER IssueType
    The issue type name. Default Task.

    .PARAMETER Description
    The description text.

    .PARAMETER AssigneeAccountId
    The accountId of the assignee.

    .PARAMETER Label
    Labels to set.

    .PARAMETER Priority
    A priority name such as High.

    .PARAMETER ParentKey
    The key of a parent issue (for a sub-task, or an epic's child in a team-managed project).

    .EXAMPLE
    New-PtJiraIssue -ProjectKey OPS -Summary 'Disk F: on SQLPROD01 at 92 percent' -Description "Found by Get-PtDiskReport.`nPlease extend the volume." -Label disk, sql -Priority High
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+$')]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [ValidateLength(1, 255)]
        [string]$Summary,

        [string]$IssueType = 'Task',

        [string]$Description,

        [string]$AssigneeAccountId,

        [ValidatePattern('^\S+$')]
        [string[]]$Label,

        [string]$Priority,

        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$ParentKey
    )

    $fields = [ordered]@{
        project   = @{ key = $ProjectKey }
        summary   = $Summary
        issuetype = @{ name = $IssueType }
    }
    if ($Description) { $fields['description'] = ConvertTo-PtAdf -Text $Description }
    if ($AssigneeAccountId) { $fields['assignee'] = @{ accountId = $AssigneeAccountId } }
    if ($Label) { $fields['labels'] = @($Label) }
    if ($Priority) { $fields['priority'] = @{ name = $Priority } }
    if ($ParentKey) { $fields['parent'] = @{ key = $ParentKey } }

    if ($PSCmdlet.ShouldProcess("$ProjectKey ($IssueType)", "Create the issue '$Summary'")) {
        $created = Invoke-PtJiraRequest -Path '/rest/api/3/issue' -Method Post -Body @{ fields = $fields }
        [pscustomobject]@{
            Key = $created.key
            Id  = $created.id
            Url = "$($script:PtJira.BaseUri)/browse/$($created.key)"
        }
    }
}
