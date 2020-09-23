function Get-PtJiraIssue {
    <#
    .SYNOPSIS
    Gets one Jira issue as a flat object, with its description as plain text.

    .DESCRIPTION
    Needs Connect-PtJira first. Returns the same properties as Search-PtJiraIssue
    plus Description, Labels and, with -IncludeComments, the comments (author,
    account id, created, text).

    .PARAMETER Key
    The issue key, for example OPS-123.

    .PARAMETER IncludeComments
    Also fetch the comments.

    .EXAMPLE
    Get-PtJiraIssue OPS-123 -IncludeComments | Select-Object -ExpandProperty Comments
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key,

        [switch]$IncludeComments
    )

    process {
        $fields = @('summary', 'issuetype', 'status', 'priority', 'assignee', 'reporter', 'created', 'updated', 'description', 'labels')
        if ($IncludeComments) { $fields += 'comment' }

        $issue = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key" -Query @{ fields = ($fields -join ',') }
        $flat = ConvertFrom-PtJiraIssue -Issue $issue -BaseUri $script:PtJira.BaseUri

        $flat | Add-Member -NotePropertyName Description -NotePropertyValue ((ConvertFrom-PtAdf -Node $issue.fields.description).TrimEnd()) -PassThru |
            Add-Member -NotePropertyName Labels -NotePropertyValue @($issue.fields.labels) -PassThru |
            ForEach-Object {
                if ($IncludeComments) {
                    $comments = foreach ($comment in @($issue.fields.comment.comments)) {
                        [pscustomobject]@{
                            Author          = $comment.author.displayName
                            AuthorAccountId = $comment.author.accountId
                            Created         = ConvertFrom-PtJiraDate -Text $comment.created
                            Text            = (ConvertFrom-PtAdf -Node $comment.body).TrimEnd()
                        }
                    }
                    $_ | Add-Member -NotePropertyName Comments -NotePropertyValue @($comments) -PassThru
                }
                else {
                    $_
                }
            }
    }
}
