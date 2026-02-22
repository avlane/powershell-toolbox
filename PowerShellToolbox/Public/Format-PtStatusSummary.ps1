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

    .PARAMETER GroupBy
    A property to group by, for example ComputerName. The result is then one line per
    group, "SQLPROD01: OK: 2, Low: 1 (3 total)", in order of first appearance.

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

        [string]$GroupBy,

        [ValidateSet('Auto', 'Always', 'Never')]
        [string]$Color = 'Auto'
    )

    begin {
        # group name -> ordered table of status -> count; one group with an empty name without -GroupBy
        $groups = [ordered]@{}
        $totals = @{}
    }

    process {
        if ($null -eq $InputObject) { return }

        $name = $Property
        if (-not $name) {
            if ($null -ne $InputObject.PSObject.Properties['Status']) { $name = 'Status' } else { $name = 'Verdict' }
        }
        $value = [string]$InputObject.$name
        if (-not $value) { $value = '(none)' }

        $group = $GroupBy ? [string]$InputObject.$GroupBy : ''
        if (-not $groups.Contains($group)) {
            $groups[$group] = [ordered]@{}
            $totals[$group] = 0
        }
        $totals[$group]++
        if ($groups[$group].Contains($value)) { $groups[$group][$value]++ } else { $groups[$group][$value] = 1 }
    }

    end {
        if ($groups.Count -eq 0) { return 'No rows' }

        $style = $PSStyle
        $useColor = $false
        if ($Color -eq 'Always') { $useColor = $true }
        elseif ($Color -eq 'Auto' -and -not [Console]::IsOutputRedirected -and $style.OutputRendering -ne 'PlainText') { $useColor = $true }

        foreach ($group in $groups.Keys) {
            $counts = $groups[$group]
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

            $line = '{0} ({1} total)' -f ($parts -join ', '), $totals[$group]
            if ($GroupBy) { "${group}: $line" } else { $line }
        }
    }
}
