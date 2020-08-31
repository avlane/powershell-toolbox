function ConvertFrom-PtJiraIssue {
    <#
    .SYNOPSIS
    Flattens a Jira issue from the REST API into one object with simple properties.

    .DESCRIPTION
    The API nests everything (fields.status.name, fields.assignee.displayName ...).
    This picks out the common fields; fields that were not requested come out as
    $null. Assignees are identified by accountId, as Jira Cloud has no user names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Issue,

        [string]$BaseUri
    )

    process {
        $fields = $Issue.fields
        [pscustomobject]@{
            Key               = $Issue.key
            Summary           = $fields.summary
            Type              = $fields.issuetype.name
            Status            = $fields.status.name
            StatusCategory    = $fields.status.statusCategory.name
            Priority          = $fields.priority.name
            Assignee          = $fields.assignee.displayName
            AssigneeAccountId = $fields.assignee.accountId
            Reporter          = $fields.reporter.displayName
            Created           = ConvertFrom-PtJiraDate -Text $fields.created
            Updated           = ConvertFrom-PtJiraDate -Text $fields.updated
            Url               = if ($BaseUri) { "$BaseUri/browse/$($Issue.key)" } else { $null }
        }
    }
}
