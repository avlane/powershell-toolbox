function Sync-PtFolder {
    <#
    .SYNOPSIS
    Copies a folder tree with robocopy, with guards against the usual ways of wiping a destination.

    .DESCRIPTION
    Without -Mirror it copies new and changed files, including empty folders (/E), and
    never deletes anything. With -Mirror the destination is made identical to the
    source (/MIR), which deletes files that only exist in the destination; that is
    only done when the source contains something, and never for the root of a drive.

    With -WhatIf robocopy is run in list-only mode (/L), so you see exactly which
    files would be copied or deleted, and nothing is changed. Without it, a real run
    asks for confirmation (ConfirmImpact is High).

    Robocopy's exit codes below 8 mean success (1 = files copied, 2 = extra files in
    the destination, 4 = mismatches, added together); 8 and above mean that some files
    could not be copied or that the command itself failed.

    .PARAMETER Source
    The folder to copy from.

    .PARAMETER Destination
    The folder to copy to. Created if it does not exist.

    .PARAMETER Mirror
    Make the destination identical to the source, deleting extra files there.

    .PARAMETER ExcludeFile
    File name patterns to leave out, for example *.tmp.

    .PARAMETER ExcludeDirectory
    Folder names or paths to leave out.

    .PARAMETER Threads
    Number of copy threads (/MT). Default 8.

    .PARAMETER Retries
    How often to retry a file that fails (/R). Default 2.

    .PARAMETER WaitSeconds
    Seconds between retries (/W). Default 5.

    .PARAMETER LogPath
    Also write robocopy's log to this file (appended).

    .EXAMPLE
    Sync-PtFolder -Source D:\Reports -Destination \\nas01\reports -ExcludeFile *.tmp -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Source,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Destination,

        [switch]$Mirror,

        [string[]]$ExcludeFile,

        [string[]]$ExcludeDirectory,

        [ValidateRange(1, 128)]
        [int]$Threads = 8,

        [ValidateRange(0, 100)]
        [int]$Retries = 2,

        [ValidateRange(0, 3600)]
        [int]$WaitSeconds = 5,

        [string]$LogPath
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "The source folder $Source does not exist."
    }
    $sourceFull = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
    $destinationFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')

    if ($sourceFull -eq $destinationFull) { throw 'The source and the destination are the same folder.' }
    if ($destinationFull.StartsWith($sourceFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The destination is inside the source; that would copy the copy into itself.'
    }

    if ($Mirror) {
        if ($destinationFull -eq [System.IO.Path]::GetPathRoot($destinationFull).TrimEnd('\')) {
            throw "Refusing to mirror onto the root of a drive: $Destination"
        }
        if (-not (Get-ChildItem -LiteralPath $sourceFull -Force | Select-Object -First 1)) {
            throw "The source folder $Source is empty; mirroring it would delete everything in the destination."
        }
    }

    $arguments = @($sourceFull, $destinationFull)
    $arguments += $Mirror ? '/MIR' : '/E'
    $arguments += "/MT:$Threads", "/R:$Retries", "/W:$WaitSeconds", '/NP', '/NJH', '/NDL'
    if ($ExcludeFile) { $arguments += '/XF'; $arguments += $ExcludeFile }
    if ($ExcludeDirectory) { $arguments += '/XD'; $arguments += $ExcludeDirectory }
    if ($LogPath) { $arguments += "/LOG+:$LogPath" }

    $action = $Mirror ? 'Mirror (deletes extra files in the destination)' : 'Copy new and changed files'
    $listOnly = -not $PSCmdlet.ShouldProcess("$sourceFull -> $destinationFull", $action)
    if ($listOnly) { $arguments += '/L' }

    $result = Invoke-PtRobocopy -Argument $arguments

    [pscustomobject]@{
        Source      = $sourceFull
        Destination = $destinationFull
        ListOnly    = $listOnly
        ExitCode    = $result.ExitCode
        Succeeded   = $result.ExitCode -lt 8
        Output      = $result.Output
    }
}
