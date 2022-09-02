function Rename-PtFileBulk {
    <#
    .SYNOPSIS
    Renames many files with a regular expression, and refuses renames that would collide.

    .DESCRIPTION
    Applies [regex]::Replace to the file name of every file in the folder (not the
    folder part of the path). Before anything is renamed the whole plan is checked:
    a file is not renamed (Status Collision) if its new name is already taken by a
    file that is staying, or if two files would get the same new name. Names that
    would not change are reported as Unchanged. Supports -WhatIf and -Confirm.

    The pattern is case-insensitive unless -CaseSensitive is given. In the
    replacement, $1 and ${name} refer to groups of the pattern.

    .PARAMETER Path
    The folder.

    .PARAMETER Pattern
    The regular expression to look for in the file name (including the extension).

    .PARAMETER Replacement
    What to put instead. May be empty.

    .PARAMETER Filter
    A wildcard filter to select files first. Default *.

    .PARAMETER Recurse
    Also rename files in sub-folders.

    .PARAMETER CaseSensitive
    Match the pattern case-sensitively.

    .EXAMPLE
    Rename-PtFileBulk -Path D:\Scans -Pattern '^IMG_(\d+)\.jpeg$' -Replacement 'scan-$1.jpg' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Pattern,

        [Parameter(Mandatory = $true, Position = 2)]
        [AllowEmptyString()]
        [string]$Replacement,

        [string]$Filter = '*',

        [switch]$Recurse,

        [switch]$CaseSensitive
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Write-Error "The folder $Path does not exist."
            return
        }

        $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        if (-not $CaseSensitive) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        try {
            $regex = New-Object -TypeName System.Text.RegularExpressions.Regex -ArgumentList $Pattern, $options
        }
        catch {
            throw "The pattern is not a valid regular expression: $($_.Exception.Message)"
        }

        $search = @{ LiteralPath = $Path; Filter = $Filter; File = $true; Force = $true; ErrorAction = 'Stop' }
        if ($Recurse) { $search['Recurse'] = $true }
        $files = @(Get-ChildItem @search)

        # the plan: what every file would be called afterwards
        $plan = foreach ($file in $files) {
            $newName = $regex.Replace($file.Name, $Replacement)
            [pscustomobject]@{
                File    = $file
                OldName = $file.Name
                NewName = $newName
                Key     = (Join-Path $file.DirectoryName $newName).ToLowerInvariant()
                Status  = ''
            }
        }

        $staying = @{}
        foreach ($item in $plan) {
            if ($item.NewName -ceq $item.OldName) { $staying[(Join-Path $item.File.DirectoryName $item.OldName).ToLowerInvariant()] = $true }
        }
        $claims = @{}
        foreach ($item in $plan | Where-Object { $_.NewName -cne $_.OldName }) {
            if (-not $claims.ContainsKey($item.Key)) { $claims[$item.Key] = 0 }
            $claims[$item.Key]++
        }

        foreach ($item in $plan) {
            $invalid = $item.NewName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or [string]::IsNullOrWhiteSpace($item.NewName)

            if ($item.NewName -ceq $item.OldName) { $item.Status = 'Unchanged' }
            elseif ($invalid) { $item.Status = 'Failed' }
            elseif ($claims[$item.Key] -gt 1 -or $staying.ContainsKey($item.Key)) { $item.Status = 'Collision' }
            elseif ($item.NewName -ne $item.OldName -and (Test-Path -LiteralPath (Join-Path $item.File.DirectoryName $item.NewName))) { $item.Status = 'Collision' }
            elseif ($PSCmdlet.ShouldProcess($item.File.FullName, "Rename to $($item.NewName)")) {
                try {
                    if ($item.NewName -eq $item.OldName) {
                        # only the case changes: Windows needs a detour through another name
                        $detour = $item.OldName + '.' + [guid]::NewGuid().ToString('N')
                        Rename-Item -LiteralPath $item.File.FullName -NewName $detour -ErrorAction Stop
                        Rename-Item -LiteralPath (Join-Path $item.File.DirectoryName $detour) -NewName $item.NewName -ErrorAction Stop
                    }
                    else {
                        Rename-Item -LiteralPath $item.File.FullName -NewName $item.NewName -ErrorAction Stop
                    }
                    $item.Status = 'Renamed'
                }
                catch {
                    $item.Status = 'Failed'
                    Write-Warning "Could not rename $($item.File.FullName) : $($_.Exception.Message)"
                }
            }
            else {
                $item.Status = 'Skipped'
            }

            [pscustomobject]@{
                Directory = $item.File.DirectoryName
                OldName   = $item.OldName
                NewName   = $item.NewName
                Status    = $item.Status
            }
        }
    }
}
