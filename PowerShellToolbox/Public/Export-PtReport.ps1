function Export-PtReport {
    <#
    .SYNOPSIS
    Writes the objects from the pipeline to a CSV, JSON or HTML file.

    .DESCRIPTION
    A small report writer for the other commands in this module. The format follows
    the file extension (.csv, .json, .html or .htm) unless -Format is given. The
    HTML output is one styled table in which every value is HTML-encoded, so text
    that comes from a server cannot inject markup. If the objects have a Status or
    Verdict property (as the reports in this module do), the row is coloured red,
    yellow or marked green according to the word (see Get-PtStatusSeverity). The folder is created when it
    does not exist, and the file is only written if ShouldProcess agrees (-WhatIf).

    Returns the file that was written.

    .PARAMETER InputObject
    The objects to export, normally from the pipeline.

    .PARAMETER Path
    The file to write. An existing file is overwritten.

    .PARAMETER Format
    Csv, Json or Html. Default: from the extension of Path.

    .PARAMETER Title
    The heading of the HTML report.

    .PARAMETER Delimiter
    The CSV field separator. Default a comma; use ';' for Excel in locales that
    expect a semicolon.

    .PARAMETER Encoding
    utf8 (default; PowerShell 7 writes no byte order mark), utf8BOM, utf8NoBOM, utf32
    or ascii. Excel only recognises a UTF-8 CSV as such when it starts with a byte
    order mark, so use utf8BOM for files that are meant to be opened in Excel.

    .PARAMETER JsonDepth
    How many levels of nested objects to write to JSON. Default 5. Deeper levels are
    flattened to their type name by ConvertTo-Json, which is rarely what you want.

    .PARAMETER Compress
    Write the JSON on one line instead of indented.

    .EXAMPLE
    Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 | Export-PtReport -Path .\disks.html -Title 'Disk space'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [ValidateSet('Csv', 'Json', 'Html')]
        [string]$Format,

        [string]$Title = 'Report',

        [ValidateLength(1, 1)]
        [string]$Delimiter = ',',

        [ValidateSet('utf8', 'utf8BOM', 'utf8NoBOM', 'utf32', 'ascii')]
        [string]$Encoding = 'utf8',

        [ValidateRange(1, 100)]
        [int]$JsonDepth = 5,

        [switch]$Compress
    )

    begin {
        $items = New-Object -TypeName 'System.Collections.Generic.List[object]'
    }

    process {
        if ($null -ne $InputObject) { $items.Add($InputObject) }
    }

    end {
        if (-not $Format) {
            switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
                '.csv'  { $Format = 'Csv' }
                '.json' { $Format = 'Json' }
                '.html' { $Format = 'Html' }
                '.htm'  { $Format = 'Html' }
                default { throw "Cannot tell the format from the extension of $Path. Use -Format Csv, Json or Html." }
            }
        }

        if ($PSCmdlet.ShouldProcess($Path, "Write $($items.Count) rows as $Format")) {
            $folder = Split-Path -Path $Path -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) {
                [void](New-Item -ItemType Directory -Path $folder -Force)
            }

            switch ($Format) {
                'Csv' {
                    if ($items.Count -gt 0) { $items | Export-Csv -LiteralPath $Path -NoTypeInformation -Delimiter $Delimiter -Encoding $Encoding }
                    else { Set-Content -LiteralPath $Path -Value '' -Encoding $Encoding }
                }
                'Json' {
                    ConvertTo-Json -InputObject $items.ToArray() -Depth $JsonDepth -Compress:$Compress | Set-Content -LiteralPath $Path -Encoding $Encoding
                }
                'Html' {
                    $encode = { param($text) [System.Net.WebUtility]::HtmlEncode([string]$text) }
                    $html = New-Object -TypeName System.Text.StringBuilder
                    [void]$html.AppendLine('<!DOCTYPE html>')
                    [void]$html.AppendLine('<html><head><meta charset="utf-8">')
                    [void]$html.AppendLine("<title>$(& $encode $Title)</title>")
                    [void]$html.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:1.5em}table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:4px 10px;text-align:left}th{background:#eee}tr.bad td{background:#fde2e2}tr.warn td{background:#fff3cd}tr.good td:first-child{border-left:4px solid #5cb85c}</style>')
                    [void]$html.AppendLine('</head><body>')
                    [void]$html.AppendLine("<h1>$(& $encode $Title)</h1>")
                    [void]$html.AppendLine("<p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $($items.Count) rows</p>")
                    if ($items.Count -gt 0) {
                        $columns = @($items[0].PSObject.Properties.Name)
                        [void]$html.AppendLine('<table>')
                        [void]$html.AppendLine('<tr>' + (($columns | ForEach-Object { "<th>$(& $encode $_)</th>" }) -join '') + '</tr>')
                        # rows are coloured by a Status or Verdict column if the objects have one
                        foreach ($item in $items) {
                            $rowClass = ''
                            foreach ($statusColumn in 'Status', 'Verdict') {
                                $severity = Get-PtStatusSeverity -Status ([string]$item.$statusColumn)
                                if ($severity -ne 'neutral') { $rowClass = " class=`"$severity`""; break }
                            }
                            $cells = foreach ($column in $columns) { "<td>$(& $encode $item.$column)</td>" }
                            [void]$html.AppendLine("<tr$rowClass>" + ($cells -join '') + '</tr>')
                        }
                        [void]$html.AppendLine('</table>')
                    }
                    [void]$html.AppendLine('</body></html>')
                    Set-Content -LiteralPath $Path -Value $html.ToString() -Encoding $Encoding
                }
            }

            Get-Item -LiteralPath $Path
        }
    }
}
