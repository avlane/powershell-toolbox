function Get-PtJiraIssueChangelog {
    <#
    .SYNOPSIS
    Lists what changed on a Jira issue, field by field, oldest first.

    .DESCRIPTION
    Needs Connect-PtJira first. Reads /rest/api/3/issue/{key}/changelog page by page
    and returns one row per changed field: when, who, which field, the old and the
    new value. For each field, TimeInPreviousValue is how long the old value had
    stood since the field's previous change; it is empty for the first change seen
    (the time before that is not in the changelog, only the issue's creation date
    would give it). With -Field status this gives the time an issue spent in each
    status, which is the raw material for cycle-time numbers.

    .PARAMETER Key
    The issue key, for example OPS-123.

    .PARAMETER Field
    Only changes to this field (case-insensitive), for example status or assignee.

    .PARAMETER Since
    Only changes after this time.

    .EXAMPLE
    Get-PtJiraIssueChangelog OPS-123 -Field status | Format-Table Created, From, To, TimeInPreviousValue
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key,

        [string]$Field,

        [datetimeoffset]$Since
    )

    process {
        $changes = New-Object -TypeName 'System.Collections.Generic.List[object]'
        $startAt = 0
        do {
            $page = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key/changelog" -Query @{ startAt = $startAt; maxResults = 100 }
            $entries = @($page.values)
            foreach ($entry in $entries) {
                if (-not $entry) { continue }
                $created = ConvertFrom-PtJiraDate -Text $entry.created
                foreach ($item in @($entry.items)) {
                    $changes.Add([pscustomobject]@{
                            Key               = $Key
                            Created           = $created
                            Author            = $entry.author.displayName
                            AuthorAccountId   = $entry.author.accountId
                            Field             = $item.field
                            From              = $item.fromString
                            To                = $item.toString
                            TimeInPreviousValue = $null
                        })
                }
            }
            $startAt += $entries.Count
        } while ($entries.Count -gt 0 -and -not $page.isLast)

        # oldest first, and how long each old value had stood
        $ordered = @($changes | Sort-Object -Property Created)
        $lastChange = @{}
        foreach ($change in $ordered) {
            $name = $change.Field.ToLowerInvariant()
            if ($lastChange.ContainsKey($name)) { $change.TimeInPreviousValue = $change.Created - $lastChange[$name] }
            $lastChange[$name] = $change.Created
        }

        foreach ($change in $ordered) {
            if ($Field -and $change.Field -ne $Field) { continue }
            if ($PSBoundParameters.ContainsKey('Since') -and $change.Created -le $Since) { continue }
            $change
        }
    }
}
