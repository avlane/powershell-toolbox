function Remove-PtOldFile {
    <#
    .SYNOPSIS
    Deletes files that have not been written to for a number of days.

    .DESCRIPTION
    Meant for log, backup and temp folders. Every deletion goes through
    ShouldProcess, so -WhatIf shows what would be removed and the default
    confirmation prompt (ConfirmImpact is High) protects interactive use; pass
    -Confirm:$false in scheduled jobs.

    The command refuses to work on the root of a drive and only ever deletes files
    (never folders), unless -RemoveEmptyFolders is given, which also deletes folders
    below the path that are empty afterwards.

    .PARAMETER Path
    One or more folders.

    .PARAMETER OlderThanDays
    Files whose LastWriteTime is more than this many days ago are deleted.

    .PARAMETER Filter
    A file name filter such as *.bak. Default *.

    .PARAMETER Recurse
    Also look in sub-folders.

    .PARAMETER RemoveEmptyFolders
    With -Recurse, delete sub-folders that are empty after the files were removed.

    .EXAMPLE
    Remove-PtOldFile -Path D:\Backups\Sales -Filter *.bak -OlderThanDays 14 -WhatIf

    .EXAMPLE
    Remove-PtOldFile -Path E:\Logs -OlderThanDays 30 -Recurse -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$OlderThanDays,

        [string]$Filter = '*',

        [switch]$Recurse,

        [switch]$RemoveEmptyFolders
    )

    process {
        $cutoff = (Get-Date).AddDays(-$OlderThanDays)

        foreach ($folder in $Path) {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-Error "The folder $folder does not exist."
                continue
            }
            $resolved = (Resolve-Path -LiteralPath $folder).ProviderPath
            if ($resolved -eq [System.IO.Path]::GetPathRoot($resolved)) {
                Write-Error "Refusing to clean up the root of a drive: $resolved"
                continue
            }

            $searchParameters = @{ LiteralPath = $resolved; Filter = $Filter; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
            if ($Recurse) { $searchParameters['Recurse'] = $true }

            foreach ($file in (Get-ChildItem @searchParameters | Where-Object { $_.LastWriteTime -lt $cutoff })) {
                $removed = $false
                $failure = $null
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete (last written $($file.LastWriteTime))")) {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                        $removed = $true
                    }
                    catch {
                        $failure = $_.Exception.Message
                        Write-Warning "Could not delete $($file.FullName) : $failure"
                    }
                }

                [pscustomobject]@{
                    Path          = $file.FullName
                    SizeMB        = [math]::Round($file.Length / 1MB, 2)
                    LastWriteTime = $file.LastWriteTime
                    Removed       = $removed
                    Error         = $failure
                }
            }

            if ($RemoveEmptyFolders -and $Recurse) {
                $folders = Get-ChildItem -LiteralPath $resolved -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object -Property FullName -Descending
                foreach ($directory in $folders) {
                    $isEmpty = -not (Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue)
                    if ($isEmpty -and $PSCmdlet.ShouldProcess($directory.FullName, 'Delete empty folder')) {
                        Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}
