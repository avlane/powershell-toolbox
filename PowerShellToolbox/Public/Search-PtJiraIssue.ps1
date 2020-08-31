function Search-PtJiraIssue {
    <#
    .SYNOPSIS
    Finds Jira issues with a JQL query and returns them as flat objects.

    .DESCRIPTION
    Pages through /rest/api/3/search (startAt / maxResults) until all matches are
    read or -First is reached. Needs Connect-PtJira first. Without -Raw each issue
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

    $startAt = 0
    $returned = 0
    $baseUri = $script:PtJira.BaseUri

    do {
        $query = @{ jql = $Jql; startAt = $startAt; maxResults = $PageSize; fields = ($Fields -join ',') }
        $page = Invoke-PtJiraRequest -Path '/rest/api/3/search' -Query $query

        $issues = @()
        if ($page.issues) { $issues = @($page.issues) }

        foreach ($issue in $issues) {
            if ($returned -ge $First) { return }
            $returned++
            if ($Raw) { $issue } else { ConvertFrom-PtJiraIssue -Issue $issue -BaseUri $baseUri }
        }

        $startAt += $issues.Count
    } while ($issues.Count -gt 0 -and $startAt -lt $page.total)
}
