function Export-PtScheduledTask {
    <#
    .SYNOPSIS
    Saves scheduled task definitions as XML files, one per task, in a folder tree that mirrors Task Scheduler.

    .DESCRIPTION
    Uses Get-ScheduledTask and Export-ScheduledTask. A task \Ops\Nightly is written
    to <Path>\Ops\Nightly.xml, so Import-PtScheduledTask can put it back in the same
    place. Meant for backing up the tasks of a server before a rebuild and for
    moving them to another one. Tasks under \Microsoft\ are skipped unless
    -IncludeMicrosoft is given. Existing files are only overwritten with -Force.
    Supports -WhatIf.

    Passwords are not part of the XML: tasks that run as a named account need the
    password again when imported.

    .PARAMETER Path
    The folder to write to.

    .PARAMETER TaskPath
    Only tasks under this path. Default \* (all).

    .PARAMETER IncludeMicrosoft
    Also export the tasks under \Microsoft\.

    .PARAMETER Force
    Overwrite existing files.

    .EXAMPLE
    Export-PtScheduledTask -Path D:\Backups\tasks\SQLPROD01 -TaskPath '\Ops\*'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [string]$TaskPath = '\*',

        [switch]$IncludeMicrosoft,

        [switch]$Force
    )

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $clean = { param($text) (($text.ToCharArray() | ForEach-Object { $invalid -contains $_ ? '_' : [string]$_ }) -join '') }

    foreach ($task in @(Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop)) {
        if (-not $IncludeMicrosoft -and $task.TaskPath -like '\Microsoft\*') { continue }

        $folder = $Path
        foreach ($part in ($task.TaskPath -split '\\' | Where-Object { $_ })) { $folder = Join-Path $folder (& $clean $part) }
        $file = Join-Path $folder ((& $clean $task.TaskName) + '.xml')

        $status = 'Exported'
        if ((Test-Path -LiteralPath $file) -and -not $Force) {
            $status = 'SkippedExists'
        }
        elseif ($PSCmdlet.ShouldProcess($file, "Export $($task.TaskPath)$($task.TaskName)")) {
            [void](New-Item -ItemType Directory -Path $folder -Force)
            $xml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
            Set-Content -LiteralPath $file -Value $xml -Encoding Unicode
        }
        else {
            $status = 'Skipped'
        }

        [pscustomobject]@{
            TaskPath = $task.TaskPath
            TaskName = $task.TaskName
            File     = $file
            Status   = $status
        }
    }
}
