function Find-PtJiraUser {
    <#
    .SYNOPSIS
    Looks up Jira Cloud users by name or e-mail address and returns their account ids.

    .DESCRIPTION
    Jira Cloud identifies people by accountId; there are no user names. This calls
    /rest/api/3/user/search, which matches on display name and e-mail address
    (the e-mail address is only returned for people who allow it to be visible, so
    EmailAddress is often empty). Use the AccountId in JQL (assignee = "<id>"), in
    New-PtJiraIssue -AssigneeAccountId and wherever else the API wants a person.

    Needs Connect-PtJira first. Answers are remembered for ten minutes (per query and
    options), because a script that assigns many issues to the same few people would
    otherwise ask Jira for the same person over and over; connecting again clears the
    memory. -NoCache asks Jira every time.

    .PARAMETER Query
    Part of a name or an e-mail address.

    .PARAMETER IncludeInactive
    Also return deactivated accounts and apps. By default only active people.

    .PARAMETER Exact
    Only keep results whose display name or e-mail address equals the query
    (case-insensitive) instead of merely containing it.

    .PARAMETER First
    The most results to return. Default 50.

    .PARAMETER NoCache
    Do not use, and do not update, the remembered answers.

    .EXAMPLE
    Find-PtJiraUser -Query 'sam.example@example.com' -Exact
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [switch]$IncludeInactive,

        [switch]$Exact,

        [ValidateRange(1, 1000)]
        [int]$First = 50,

        [switch]$NoCache
    )

    $cacheKey = '{0}|{1}|{2}|{3}' -f $Query.ToLowerInvariant(), $IncludeInactive.IsPresent, $Exact.IsPresent, $First
    if (-not $NoCache -and $script:PtJiraUserCache -and $script:PtJiraUserCache.ContainsKey($cacheKey)) {
        $entry = $script:PtJiraUserCache[$cacheKey]
        if (((Get-Date) - $entry.Stored).TotalMinutes -lt 10) { return $entry.Users }
    }

    $users = Invoke-PtJiraRequest -Path '/rest/api/3/user/search' -Query @{ query = $Query; maxResults = $First }

    $found = foreach ($user in @($users)) {
        if (-not $user) { continue }
        if (-not $IncludeInactive -and ($user.active -eq $false -or $user.accountType -ne 'atlassian')) { continue }
        if ($Exact -and $user.displayName -ne $Query -and $user.emailAddress -ne $Query) { continue }

        [pscustomobject]@{
            AccountId    = $user.accountId
            DisplayName  = $user.displayName
            EmailAddress = $user.emailAddress
            Active       = $user.active
            AccountType  = $user.accountType
        }
    }

    if (-not $NoCache) {
        if (-not $script:PtJiraUserCache) { $script:PtJiraUserCache = @{} }
        $script:PtJiraUserCache[$cacheKey] = @{ Stored = Get-Date; Users = @($found) }
    }
    $found
}
