function ConvertTo-PtAdf {
    <#
    .SYNOPSIS
    Wraps plain text in the Atlassian Document Format that the Jira Cloud v3 API requires.

    .DESCRIPTION
    Version 3 of the Jira REST API no longer takes plain strings for comments and
    descriptions; they must be an ADF document. Every non-empty line of the text
    becomes a paragraph. No formatting, links or mentions are interpreted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $paragraphs = @()
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line.Trim().Length -eq 0) { continue }
        $paragraphs += @{ type = 'paragraph'; content = @(@{ type = 'text'; text = $line }) }
    }
    if ($paragraphs.Count -eq 0) {
        $paragraphs = @(@{ type = 'paragraph'; content = @() })
    }

    @{ type = 'doc'; version = 1; content = $paragraphs }
}
