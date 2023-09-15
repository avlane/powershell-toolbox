function ConvertTo-PtMarkdownTable {
    <#
    .SYNOPSIS
    Formats objects as a GitHub-flavoured Markdown table.

    .DESCRIPTION
    Handy for pasting a report into a Jira comment, a wiki page, a pull request or a
    chat message. Column headings come from the property names of the first object
    (or -Property). Cell values are made safe: a pipe becomes \|, line breaks become
    spaces, dates are written as yyyy-MM-dd HH:mm:ss, $null as an empty cell, arrays
    as comma separated lists, and long text is cut to MaxCellLength characters.

    .PARAMETER InputObject
    The rows, normally from the pipeline.

    .PARAMETER Property
    The properties to show, in this order. Default: all properties of the first row.

    .PARAMETER MaxCellLength
    Longer cell text is cut and ends in three dots. Default 200.

    .EXAMPLE
    Get-PtBackupStatus -ServerInstance SQLPROD01 | Where-Object Status -ne 'OK' | ConvertTo-PtMarkdownTable -Property DatabaseName, Status, Problems
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject,

        [string[]]$Property,

        [ValidateRange(10, 5000)]
        [int]$MaxCellLength = 200
    )

    begin {
        $items = New-Object -TypeName 'System.Collections.Generic.List[object]'

        $cell = {
            param($value)
            if ($null -eq $value) { return '' }
            if ($value -is [datetime]) { $text = $value.ToString('yyyy-MM-dd HH:mm:ss') }
            elseif ($value -is [datetimeoffset]) { $text = $value.ToString('yyyy-MM-dd HH:mm:ss') }
            elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { $text = (@($value) | ForEach-Object { "$_" }) -join ', ' }
            else { $text = [string]$value }
            $text = $text -replace '\r?\n', ' '
            if ($text.Length -gt $MaxCellLength) { $text = $text.Substring(0, $MaxCellLength - 3) + '...' }
            $text.Replace('|', '\|')
        }
    }

    process {
        if ($null -ne $InputObject) { $items.Add($InputObject) }
    }

    end {
        if ($items.Count -eq 0) { return '' }

        $columns = $Property ?? @($items[0].PSObject.Properties.Name)
        $lines = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $lines.Add('| ' + (($columns | ForEach-Object { & $cell $_ }) -join ' | ') + ' |')
        $lines.Add('| ' + (($columns | ForEach-Object { '---' }) -join ' | ') + ' |')
        foreach ($item in $items) {
            $lines.Add('| ' + (($columns | ForEach-Object { & $cell $item.$_ }) -join ' | ') + ' |')
        }
        $lines -join [Environment]::NewLine
    }
}
