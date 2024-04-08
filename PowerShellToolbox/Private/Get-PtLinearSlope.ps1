function Get-PtLinearSlope {
    <#
    .SYNOPSIS
    Returns the slope of the least-squares line through the points (X, Y).

    .DESCRIPTION
    slope = (n * sum(xy) - sum(x) * sum(y)) / (n * sum(x^2) - sum(x)^2)
    Returns $null when there are fewer than two points or all X are equal.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$X,

        [Parameter(Mandatory = $true)]
        [double[]]$Y
    )

    if ($X.Count -ne $Y.Count) { throw 'X and Y must have the same number of values.' }
    $n = $X.Count
    if ($n -lt 2) { return $null }

    $sumX = 0.0; $sumY = 0.0; $sumXY = 0.0; $sumXX = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $sumX += $X[$i]
        $sumY += $Y[$i]
        $sumXY += $X[$i] * $Y[$i]
        $sumXX += $X[$i] * $X[$i]
    }

    $denominator = $n * $sumXX - $sumX * $sumX
    if ($denominator -eq 0) { return $null }
    return ($n * $sumXY - $sumX * $sumY) / $denominator
}
