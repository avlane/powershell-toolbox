function Get-PtJiraWorklog {
    <#
    .SYNOPSIS
    Lists the time one person logged in Jira between two dates, one row per worklog.

    .DESCRIPTION
    Needs Connect-PtJira first. Finds the issues with worklogs by that person in the
    period (JQL worklogAuthor and worklogDate), then reads each issue's worklogs and
    keeps those that were started in the period by that person. That second step is
    needed because the JQL matches issues, and an issue can also hold other people's
    worklogs and worklogs from other dates.

    The hours come from timeSpentSeconds, so they are exact; a Jira "day" does not
    enter into it. The comment is returned as plain text.

    .PARAMETER AccountId
    The person's account id (see Find-PtJiraUser). Default: the user you are connected as.

    .PARAMETER From
    The first day, inclusive. Default: the first day of the current month.

    .PARAMETER To
    The last day, inclusive. Default: today.

    .PARAMETER ProjectKey
    Only worklogs on issues of these projects.

    .EXAMPLE
    Get-PtJiraWorklog -From 2026-03-01 -To 2026-03-31 | Group-Object Key | ForEach-Object { [pscustomobject]@{ Key = $_.Name; Hours = ($_.Group | Measure-Object Hours -Sum).Sum } }
    #>
    [CmdletBinding()]
    param(
        [string]$AccountId,

        [datetime]$From = (Get-Date -Day 1).Date,

        [datetime]$To = (Get-Date).Date,

        [string[]]$ProjectKey
    )

    if (-not $AccountId) {
        $AccountId = (Invoke-PtJiraRequest -Path '/rest/api/3/myself').accountId
    }
    if ($To -lt $From) { throw 'The end date is before the start date.' }

    $start = [datetimeoffset]::new($From.Date, [datetimeoffset]::Now.Offset)
    $end = [datetimeoffset]::new($To.Date.AddDays(1), [datetimeoffset]::Now.Offset)

    $account = ConvertTo-PtJqlString -Value $AccountId
    $jql = New-PtJql -Project $ProjectKey -Clause "worklogAuthor = $account AND worklogDate >= $(ConvertTo-PtJqlString -Value $From.ToString('yyyy-MM-dd')) AND worklogDate <= $(ConvertTo-PtJqlString -Value $To.ToString('yyyy-MM-dd'))"

    foreach ($issue in @(Search-PtJiraIssue -Jql $jql -Fields 'summary')) {
        $startAt = 0
        do {
            $page = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$($issue.Key)/worklog" -Query @{ startAt = $startAt; maxResults = 100 }
            $worklogs = @($page.worklogs)
            foreach ($worklog in $worklogs) {
                if (-not $worklog -or $worklog.author.accountId -ne $AccountId) { continue }
                $started = ConvertFrom-PtJiraDate -Text $worklog.started
                if ($null -eq $started -or $started -lt $start -or $started -ge $end) { continue }

                [pscustomobject]@{
                    Key        = $issue.Key
                    Summary    = $issue.Summary
                    Started    = $started
                    Author     = $worklog.author.displayName
                    AccountId  = $worklog.author.accountId
                    Hours      = [math]::Round($worklog.timeSpentSeconds / 3600, 2)
                    TimeSpent  = $worklog.timeSpent
                    Comment    = (ConvertFrom-PtAdf -Node $worklog.comment).TrimEnd()
                }
            }
            $startAt += $worklogs.Count
        } while ($worklogs.Count -gt 0 -and $startAt -lt $page.total)
    }
}
