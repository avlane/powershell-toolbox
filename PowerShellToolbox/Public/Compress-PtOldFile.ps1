function Compress-PtOldFile {
    <#
    .SYNOPSIS
    Zips old log files one by one and removes the originals once the zip has been checked.

    .DESCRIPTION
    For every file in the folder that matches the filter and has not been written
    to for OlderThanDays days, a NAME.EXT.zip is created next to it with
    Compress-Archive. The zip is opened again and its single entry must have the
    same length as the original; only then is the original deleted (unless
    -KeepOriginal is given). Files that are already zips are ignored.

    Compress-Archive in Windows PowerShell 5.1 cannot handle files of 2 GB or more;
    those are reported as TooLarge and left alone. Supports -WhatIf and -Confirm.

    .PARAMETER Path
    One or more folders.

    .PARAMETER OlderThanDays
    Only files whose LastWriteTime is more than this many days ago.

    .PARAMETER Filter
    A file name filter. Default *.log.

    .PARAMETER Recurse
    Also look in sub-folders.

    .PARAMETER KeepOriginal
    Keep the original file after the zip was verified.

    .EXAMPLE
    Compress-PtOldFile -Path E:\Logs\IIS -OlderThanDays 7 -Recurse -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$OlderThanDays,

        [string]$Filter = '*.log',

        [switch]$Recurse,

        [switch]$KeepOriginal
    )

    begin {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    process {
        $cutoff = (Get-Date).AddDays(-$OlderThanDays)

        foreach ($folder in $Path) {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-Error "The folder $folder does not exist."
                continue
            }
            $resolved = (Resolve-Path -LiteralPath $folder).ProviderPath

            $search = @{ LiteralPath = $resolved; Filter = $Filter; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
            if ($Recurse) { $search['Recurse'] = $true }

            $candidates = Get-ChildItem @search | Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Extension -ne '.zip' }
            foreach ($file in $candidates) {
                $archive = $file.FullName + '.zip'
                $status = 'Compressed'

                if ($file.Length -ge 2GB -and $PSVersionTable.PSVersion.Major -lt 6) {
                    $status = 'TooLarge'
                }
                elseif (Test-Path -LiteralPath $archive) {
                    $status = 'ArchiveExists'
                }
                elseif ($PSCmdlet.ShouldProcess($file.FullName, 'Compress and remove the original')) {
                    try {
                        Compress-Archive -LiteralPath $file.FullName -DestinationPath $archive -ErrorAction Stop

                        $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
                        try {
                            $entries = @($zip.Entries)
                            if ($entries.Count -ne 1 -or $entries[0].Length -ne $file.Length) {
                                throw 'the archive does not contain the file as expected'
                            }
                        }
                        finally {
                            $zip.Dispose()
                        }

                        if (-not $KeepOriginal) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
                    }
                    catch {
                        $status = 'Failed'
                        Write-Warning "Could not compress $($file.FullName) : $($_.Exception.Message)"
                        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
                    }
                }
                else {
                    $status = 'Skipped'
                }

                $archiveLength = $null
                if ($status -eq 'Compressed') { $archiveLength = (Get-Item -LiteralPath $archive).Length }

                [pscustomobject]@{
                    Path       = $file.FullName
                    Archive    = $archive
                    OriginalMB = [math]::Round($file.Length / 1MB, 2)
                    ArchiveMB  = if ($null -ne $archiveLength) { [math]::Round($archiveLength / 1MB, 2) } else { $null }
                    Status     = $status
                }
            }
        }
    }
}
