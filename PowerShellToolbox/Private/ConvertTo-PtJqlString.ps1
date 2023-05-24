function ConvertTo-PtJqlString {
    <#
    .SYNOPSIS
    Quotes a value for use in JQL.

    .DESCRIPTION
    JQL text values go in double quotes; a backslash or a double quote inside the
    value must be escaped with a backslash. Building queries by pasting text
    together without this breaks on names like O"Brien and lets input change the
    meaning of the query.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    '"' + ($Value.Replace('\', '\\').Replace('"', '\"')) + '"'
}
