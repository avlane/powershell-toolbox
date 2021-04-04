function Copy-PtFileSafe {
    <#
    .SYNOPSIS
    Copies (or moves) files and checks with a hash that the copy is identical before trusting it.

    .DESCRIPTION
    Each file is first copied to a temporary name in the destination folder, then
    its hash is compared with the hash of the source, and only then is it renamed
    to its final name. A copy that was interrupted or corrupted therefore never
    appears under the real name. With -Move the source is deleted after the
    verification, never before.

    A file that already exists at the destination is left alone unless -Overwrite
    is given; if it is identical to the source that is reported as Identical (and,
    with -Move, the source is still removed). Supports -WhatIf and -Confirm.

    .PARAMETER Path
    The files to copy. Objects from Get-ChildItem work through the pipeline.

    .PARAMETER Destination
    The target folder. It is created when it does not exist.

    .PARAMETER Move
    Delete the source after a verified copy.

    .PARAMETER Overwrite
    Replace a different file of the same name at the destination.

    .PARAMETER Algorithm
    The hash algorithm: SHA256 (default), SHA1 or MD5.

    .EXAMPLE
    Get-ChildItem D:\Backups\*.bak | Copy-PtFileSafe -Destination \\nas01\sqlbackups -Move -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Destination,

        [switch]$Move,

        [switch]$Overwrite,

        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )

    process {
        foreach ($file in $Path) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                Write-Error "The file $file does not exist."
                continue
            }

            $source = Get-Item -LiteralPath $file
            $target = Join-Path -Path $Destination -ChildPath $source.Name
            $status = $null
            $hash = $null

            if (-not $PSCmdlet.ShouldProcess($source.FullName, "Copy to $target")) {
                continue
            }

            try {
                if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop)
                }

                $hash = (Get-FileHash -LiteralPath $source.FullName -Algorithm $Algorithm -ErrorAction Stop).Hash

                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    $existingHash = (Get-FileHash -LiteralPath $target -Algorithm $Algorithm -ErrorAction Stop).Hash
                    if ($existingHash -eq $hash) { $status = 'Identical' }
                    elseif (-not $Overwrite) { $status = 'SkippedExists' }
                }

                if (-not $status) {
                    $temporary = $target + '.ptcopy'
                    try {
                        Copy-Item -LiteralPath $source.FullName -Destination $temporary -Force -ErrorAction Stop
                        $copyHash = (Get-FileHash -LiteralPath $temporary -Algorithm $Algorithm -ErrorAction Stop).Hash
                        if ($copyHash -ne $hash) { throw "The copy of $($source.Name) does not match the source ($Algorithm differs)." }
                        Move-Item -LiteralPath $temporary -Destination $target -Force -ErrorAction Stop
                        $status = 'Copied'
                    }
                    finally {
                        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
                    }
                }

                if ($Move -and ($status -eq 'Copied' -or $status -eq 'Identical')) {
                    Remove-Item -LiteralPath $source.FullName -Force -ErrorAction Stop
                    if ($status -eq 'Copied') { $status = 'Moved' }
                }
            }
            catch {
                $status = 'Failed'
                Write-Warning "$($source.FullName): $($_.Exception.Message)"
            }

            [pscustomobject]@{
                Source      = $source.FullName
                Destination = $target
                Status      = $status
                Hash        = $hash
                Bytes       = $source.Length
            }
        }
    }
}
