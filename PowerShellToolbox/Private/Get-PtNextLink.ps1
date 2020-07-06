function Get-PtNextLink {
    <#
    .SYNOPSIS
    Returns the rel="next" address from an HTTP Link header, or $null.

    .DESCRIPTION
    GitHub, GitLab and many other APIs page their results with a header like
    <https://api.example.com/items?page=2>; rel="next", <https://api.example.com/items?page=9>; rel="last"
    A header that arrives as several strings is joined first.
    #>
    [CmdletBinding()]
    param(
        [string[]]$LinkHeader
    )

    if (-not $LinkHeader) { return $null }

    $text = $LinkHeader -join ','
    $match = [regex]::Match($text, '<([^>]+)>\s*;[^,]*?rel="?next"?')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}
