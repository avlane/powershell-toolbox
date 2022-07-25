function ConvertFrom-PtRetryAfter {
    <#
    .SYNOPSIS
    Turns the value of a Retry-After header into a number of seconds to wait.

    .DESCRIPTION
    The header holds either a number of seconds (Retry-After: 120) or an HTTP date
    (Retry-After: Wed, 21 Oct 2015 07:28:00 GMT). A date in the past gives 0. The
    result is never more than MaxSeconds, so a wrong clock or a silly header cannot
    make a script sleep for hours. Returns $null when there is nothing usable.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,

        [datetimeoffset]$Now = [datetimeoffset]::UtcNow,

        [ValidateRange(1, 86400)]
        [int]$MaxSeconds = 300
    )

    if (-not $Value) { return $null }
    $text = $Value.Trim()

    if ($text -match '^\d+$') {
        return [int][math]::Min([double]$text, $MaxSeconds)
    }

    $when = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($text, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$when)) {
        $seconds = [math]::Ceiling(($when - $Now).TotalSeconds)
        return [int][math]::Min([math]::Max($seconds, 0), $MaxSeconds)
    }

    return $null
}
