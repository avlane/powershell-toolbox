function ConvertFrom-PtRobocopySummary {
    <#
    .SYNOPSIS
    Reads the counters from the summary table at the end of robocopy's output.

    .DESCRIPTION
    The table has a row for Dirs and one for Files, each with the columns Total,
    Copied, Skipped, Mismatch, FAILED and Extras. This returns the numbers for files
    and directories, or $null for a counter that is not in the output (the table is
    missing when robocopy failed early or was run with /NJS).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Output = @()
    )

    $read = {
        param($label)
        foreach ($line in $Output) {
            if ($line -match "^\s*$label\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$") {
                return [pscustomobject]@{
                    Total    = [int64]$Matches[1]
                    Copied   = [int64]$Matches[2]
                    Skipped  = [int64]$Matches[3]
                    Mismatch = [int64]$Matches[4]
                    Failed   = [int64]$Matches[5]
                    Extras   = [int64]$Matches[6]
                }
            }
        }
        return $null
    }

    $files = & $read 'Files'
    $dirs = & $read 'Dirs'

    [pscustomobject]@{
        FilesCopied  = ${files}?.Copied
        FilesSkipped = ${files}?.Skipped
        FilesFailed  = ${files}?.Failed
        FilesExtra   = ${files}?.Extras
        DirsCopied   = ${dirs}?.Copied
        DirsExtra    = ${dirs}?.Extras
    }
}
