function Format-PtStatusSummary {
    <#
    .SYNOPSIS
    Turns a list of report rows into a one-line count per status, such as "OK: 12, Low: 2, Failed: 1".

    .DESCRIPTION
    Counts the rows by their Status property (or Verdict, or the property named by
    -Property) and returns one string. The counts are coloured with $PSStyle
    (green, yellow, red) when the output goes to a terminal; redirected output gets
    plain text. The string is
    returned rather than written, so it can also go into a log or a mail.

    .PARAMETER InputObject
    The rows, normally from the pipeline.

    .PARAMETER Property
    The property that holds the status. Default: Status, otherwise Verdict.

    .PARAMETER Color
    Auto (default), Always or Never.

    .EXAMPLE
    Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 | Format-PtStatusSummary
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject,

        [string]$Property,

        [ValidateSet('Auto', 'Always', 'Never')]
        [string]$Color = 'Auto'
    )

    begin {
        $counts = [ordered]@{}
        $total = 0
    }

    process {
        if ($null -eq $InputObject) { return }
        $total++

        $name = $Property
        if (-not $name) {
            if ($null -ne $InputObject.PSObject.Properties['Status']) { $name = 'Status' } else { $name = 'Verdict' }
        }
        $value = [string]$InputObject.$name
        if (-not $value) { $value = '(none)' }
        if ($counts.Contains($value)) { $counts[$value]++ } else { $counts[$value] = 1 }
    }

    end {
        $style = $PSStyle
        $useColor = $false
        if ($Color -eq 'Always') { $useColor = $true }
        elseif ($Color -eq 'Auto' -and -not [Console]::IsOutputRedirected -and $style.OutputRendering -ne 'PlainText') { $useColor = $true }

        $parts = foreach ($key in $counts.Keys) {
            $text = '{0}: {1}' -f $key, $counts[$key]
            if ($useColor) {
                switch (Get-PtStatusSeverity -Status $key) {
                    'good' { $text = $style.Foreground.Green + $text + $style.Reset }
                    'warn' { $text = $style.Foreground.Yellow + $text + $style.Reset }
                    'bad'  { $text = $style.Foreground.Red + $text + $style.Reset }
                }
            }
            $text
        }

        if ($total -eq 0) { return 'No rows' }
        '{0} ({1} total)' -f ($parts -join ', '), $total
    }
}
