function Invoke-PtRobocopy {
    <#
    .SYNOPSIS
    Runs robocopy.exe with the given arguments and returns its exit code and output.

    .DESCRIPTION
    The only place that starts the native program, so that everything around it can
    be tested with this function mocked. Robocopy's exit code is a bit mask, not
    a plain success flag; it is returned as it is.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Argument
    )

    $output = & robocopy.exe @Argument 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($output | ForEach-Object { [string]$_ })
    }
}
