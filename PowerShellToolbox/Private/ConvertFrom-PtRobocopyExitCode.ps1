function ConvertFrom-PtRobocopyExitCode {
    <#
    .SYNOPSIS
    Explains robocopy's exit code.

    .DESCRIPTION
    The exit code is a bit mask: 1 files were copied, 2 there are extra files or
    folders in the destination, 4 there are mismatches, 8 some files could not be
    copied, 16 a serious error (nothing was copied). The values add up, so 3 means
    copied and extras. Codes below 8 are a success; 8 and above are not. 0 means
    the two trees were already identical.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    $meaning = @()
    if ($ExitCode -eq 0) { $meaning += 'Nothing to copy; source and destination are already in sync.' }
    if ($ExitCode -band 1) { $meaning += 'Files were copied.' }
    if ($ExitCode -band 2) { $meaning += 'There are extra files or folders in the destination.' }
    if ($ExitCode -band 4) { $meaning += 'There are mismatched files or folders.' }
    if ($ExitCode -band 8) { $meaning += 'Some files or folders could not be copied.' }
    if ($ExitCode -band 16) { $meaning += 'Serious error: robocopy did not copy anything.' }

    [pscustomobject]@{
        ExitCode  = $ExitCode
        Succeeded = $ExitCode -lt 8
        Meaning   = $meaning
    }
}
