function ConvertFrom-PtAdf {
    <#
    .SYNOPSIS
    Extracts the plain text from an Atlassian Document Format node.

    .DESCRIPTION
    Walks the document tree and joins the text nodes. Paragraphs, headings, list
    items and code blocks end with a line break; mentions are written as their @name.
    Formatting, tables and media are dropped. A plain string (as the v2 API returns)
    is passed through. Returns an empty string for $null.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Node
    )

    if ($null -eq $Node) { return '' }
    if ($Node -is [string]) { return $Node }

    switch ($Node.type) {
        'text'      { return [string]$Node.text }
        'hardBreak' { return "`n" }
        'mention'   { return [string]$Node.attrs.text }
    }

    $text = ''
    if ($Node.content) {
        $parts = foreach ($child in @($Node.content)) { ConvertFrom-PtAdf -Node $child }
        $text = $parts -join ''
    }
    if ($Node.type -in 'paragraph', 'heading', 'listItem', 'codeBlock', 'blockquote') {
        $text = $text + "`n"
    }
    return $text
}
