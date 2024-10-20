function Search-PtJiraIssue {
    <#
    .SYNOPSIS
    Finds Jira issues with a JQL query and returns them as flat objects.

    .DESCRIPTION
    Uses the enhanced search endpoint, /rest/api/3/search/jql, which pages with a
    token (nextPageToken) instead of startAt and does not report a total. All pages
    are read until the last one or until -First is reached. Needs Connect-PtJira
    first. The query must be bounded by at least one search restriction, for example
    a project: the new endpoint rejects a bare 'ORDER BY created'. Without -Raw each issue
    is flattened to Key, Summary, Type, Status, Priority, Assignee (display name
    and accountId), Reporter, Created, Updated and Url.

    .PARAMETER Jql
    The query, for example: project = OPS AND status = "In Progress" ORDER BY updated DESC

    .PARAMETER Fields
    The fields to ask Jira for. Default: the ones used by the flat output. Only
    relevant together with -Raw if you need others.

    .PARAMETER PageSize
    Issues per request, 1 to 100. Jira may return fewer. Default 100.

    .PARAMETER First
    Stop after this many issues.

    .PARAMETER Raw
    Return the issues exactly as the API sends them.

    .EXAMPLE
    Search-PtJiraIssue 'project = OPS AND resolution = Unresolved' | Sort-Object Updated | Select-Object -First 10 Key, Summary, Assignee
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Jql,

        [string[]]$Fields = @('summary', 'issuetype', 'status', 'priority', 'assignee', 'reporter', 'created', 'updated'),

        [ValidateRange(1, 100)]
        [int]$PageSize = 100,

        [ValidateRange(1, 1000000)]
        [int]$First = 1000000,

        [switch]$Raw
    )

    $pageToken = $null
    $returned = 0
    $baseUri = $script:PtJira.BaseUri

    do {
        $query = @{ jql = $Jql; maxResults = $PageSize; fields = ($Fields -join ',') }
        if ($pageToken) { $query['nextPageToken'] = $pageToken }
        $page = Invoke-PtJiraRequest -Path '/rest/api/3/search/jql' -Query $query

        $issues = @()
        if ($page.issues) { $issues = @($page.issues) }

        foreach ($issue in $issues) {
            if ($returned -ge $First) { return }
            $returned++
            if ($Raw) { $issue } else { ConvertFrom-PtJiraIssue -Issue $issue -BaseUri $baseUri }
        }

        # the last page has no token
        $pageToken = $page.isLast ? $null : $page.nextPageToken
    } while ($pageToken)
}
