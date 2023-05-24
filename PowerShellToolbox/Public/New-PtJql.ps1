function New-PtJql {
    <#
    .SYNOPSIS
    Builds a JQL query from parameters, with the values quoted properly.

    .DESCRIPTION
    Covers the filters used most often; every parameter you give adds one AND-ed
    condition. Values are put in double quotes with backslashes and quotes escaped.
    For anything else, add your own text with -Clause (it is used as given).
    The result is a string for Search-PtJiraIssue.

    .PARAMETER Project
    One or more project keys.

    .PARAMETER IssueType
    One or more issue type names.

    .PARAMETER Status
    One or more status names.

    .PARAMETER NotStatusCategory
    Exclude a status category, usually Done: -NotStatusCategory Done.

    .PARAMETER AssigneeAccountId
    One or more account ids.

    .PARAMETER Unassigned
    Only issues without an assignee.

    .PARAMETER Label
    Issues that have all of these labels.

    .PARAMETER UpdatedWithinDays
    Only issues updated in the last N days.

    .PARAMETER CreatedAfter
    Only issues created on or after this date.

    .PARAMETER Text
    Free text search in summary, description and comments.

    .PARAMETER Clause
    Extra JQL, added as it is.

    .PARAMETER OrderBy
    The field to sort by. Default none.

    .PARAMETER Descending
    Sort descending.

    .EXAMPLE
    New-PtJql -Project OPS -NotStatusCategory Done -UpdatedWithinDays 7 -OrderBy updated -Descending

    project = "OPS" AND statusCategory != "Done" AND updated >= -7d ORDER BY updated DESC
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string[]]$Project,
        [string[]]$IssueType,
        [string[]]$Status,
        [string]$NotStatusCategory,
        [string[]]$AssigneeAccountId,
        [switch]$Unassigned,
        [string[]]$Label,
        [ValidateRange(1, 3650)]
        [int]$UpdatedWithinDays,
        [datetime]$CreatedAfter,
        [string]$Text,
        [string[]]$Clause,
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_ ]*$')]
        [string]$OrderBy,
        [switch]$Descending
    )

    $parts = @()

    foreach ($pair in @(@('project', $Project), @('issuetype', $IssueType), @('status', $Status), @('assignee', $AssigneeAccountId))) {
        $field = $pair[0]
        $values = @($pair[1] | Where-Object { $_ })
        if ($values.Count -eq 1) { $parts += "$field = $(ConvertTo-PtJqlString -Value $values[0])" }
        elseif ($values.Count -gt 1) { $parts += "$field IN ($(($values | ForEach-Object { ConvertTo-PtJqlString -Value $_ }) -join ', '))" }
    }

    if ($Unassigned) { $parts += 'assignee IS EMPTY' }
    if ($NotStatusCategory) { $parts += "statusCategory != $(ConvertTo-PtJqlString -Value $NotStatusCategory)" }
    foreach ($item in @($Label | Where-Object { $_ })) { $parts += "labels = $(ConvertTo-PtJqlString -Value $item)" }
    if ($UpdatedWithinDays) { $parts += "updated >= -${UpdatedWithinDays}d" }
    if ($PSBoundParameters.ContainsKey('CreatedAfter')) { $parts += "created >= $(ConvertTo-PtJqlString -Value $CreatedAfter.ToString('yyyy-MM-dd'))" }
    if ($Text) { $parts += "text ~ $(ConvertTo-PtJqlString -Value $Text)" }
    foreach ($extra in @($Clause | Where-Object { $_ })) { $parts += "($extra)" }

    $jql = $parts -join ' AND '
    if ($OrderBy) { $jql = ($jql + ' ORDER BY ' + $OrderBy + ($Descending ? ' DESC' : ' ASC')).Trim() }
    $jql
}
