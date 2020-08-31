function ConvertFrom-PtJiraDate {
    <#
    .SYNOPSIS
    Parses a Jira timestamp such as 2020-08-30T10:11:12.345+0000 into a DateTimeOffset.

    .DESCRIPTION
    Jira writes the UTC offset without a colon (+0000), which .NET does not parse
    in the general case. Returns $null for empty or unparseable input.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if (-not $Text) { return $null }

    $fixed = $Text -replace '([+-]\d{2})(\d{2})$', '$1:$2'
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($fixed, [ref]$parsed)) { return $parsed }
    return $null
}
