function Export-PtReport {
    <#
    .SYNOPSIS
    Writes the objects from the pipeline to a CSV, JSON or HTML file.

    .DESCRIPTION
    A small report writer for the other commands in this module. The format follows
    the file extension (.csv, .json, .html or .htm) unless -Format is given. The
    HTML output is one styled table in which every value is HTML-encoded, so text
    that comes from a server cannot inject markup. The folder is created when it
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

        [string]$Title = 'Report'
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
                    if ($items.Count -gt 0) { $items | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
                    else { Set-Content -LiteralPath $Path -Value '' -Encoding UTF8 }
                }
                'Json' {
                    ConvertTo-Json -InputObject $items.ToArray() -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
                }
                'Html' {
                    $encode = { param($text) [System.Net.WebUtility]::HtmlEncode([string]$text) }
                    $html = New-Object -TypeName System.Text.StringBuilder
                    [void]$html.AppendLine('<!DOCTYPE html>')
                    [void]$html.AppendLine('<html><head><meta charset="utf-8">')
                    [void]$html.AppendLine("<title>$(& $encode $Title)</title>")
                    [void]$html.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:1.5em}table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:4px 10px;text-align:left}th{background:#eee}</style>')
                    [void]$html.AppendLine('</head><body>')
                    [void]$html.AppendLine("<h1>$(& $encode $Title)</h1>")
                    [void]$html.AppendLine("<p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $($items.Count) rows</p>")
                    if ($items.Count -gt 0) {
                        $columns = @($items[0].PSObject.Properties.Name)
                        [void]$html.AppendLine('<table>')
                        [void]$html.AppendLine('<tr>' + (($columns | ForEach-Object { "<th>$(& $encode $_)</th>" }) -join '') + '</tr>')
                        foreach ($item in $items) {
                            $cells = foreach ($column in $columns) { "<td>$(& $encode $item.$column)</td>" }
                            [void]$html.AppendLine('<tr>' + ($cells -join '') + '</tr>')
                        }
                        [void]$html.AppendLine('</table>')
                    }
                    [void]$html.AppendLine('</body></html>')
                    Set-Content -LiteralPath $Path -Value $html.ToString() -Encoding UTF8
                }
            }

            Get-Item -LiteralPath $Path
        }
    }
}
