function Get-PtStatusSeverity {
    <#
    .SYNOPSIS
    Classifies a status word from one of the reports as good, warn, bad or neutral.

    .PARAMETER Status
    The word, for example OK, Low or Failed.

    .EXAMPLE
    Get-PtDiskReport | Where-Object { (Get-PtStatusSeverity -Status $_.Status) -in 'warn', 'bad' }

    .DESCRIPTION
    The reports in this module use a handful of words (OK, Low, Failed, Stale,
    Expiring ...). This keeps the meaning of those words in one place so that the
    HTML export and the console summary colour them the same way. Unknown words
    are neutral.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Status
    )

    $good = @('OK', 'Succeeded', 'Started', 'Copied', 'Moved', 'Identical', 'AlreadyRunning', 'Compressed')
    $warn = @('Low', 'Stale', 'Expiring', 'Flaky', 'BadGrowth', 'NeverRun', 'Skipped', 'SkippedExists', 'Overdue', 'Collision')
    $bad = @('Failed', 'Expired', 'NoBackup', 'LowVolume', 'Critical', 'Unknown', 'NotFound')

    if ($good -contains $Status) { return 'good' }
    if ($warn -contains $Status) { return 'warn' }
    if ($bad -contains $Status) { return 'bad' }
    return 'neutral'
}
