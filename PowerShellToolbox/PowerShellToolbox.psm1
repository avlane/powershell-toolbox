# PowerShellToolbox - small admin helpers for Windows PowerShell 5.1

function Get-PtDiskReport {
    <#
    .SYNOPSIS
    Reports the free space on the fixed disks of one or more computers.

    .DESCRIPTION
    Queries Win32_LogicalDisk (fixed disks only, DriveType 3) with WMI and returns
    one object per disk with size, free space and a status of OK or Low.

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER WarningPercent
    A disk with less than this percentage free is reported as Low. Default 10.

    .EXAMPLE
    Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 -WarningPercent 15

    Shows the disks of both servers, flagging those under 15 percent free.

    .EXAMPLE
    Get-PtDiskReport | Where-Object Status -eq 'Low'

    Only the local disks that are running out of space.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(1, 99)]
        [int]$WarningPercent = 10
    )

    process {
        foreach ($computer in $ComputerName) {
            try {
                $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $computer -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not query $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($disk in $disks) {
                $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                if ($freePercent -lt $WarningPercent) { $status = 'Low' } else { $status = 'OK' }

                [pscustomobject]@{
                    ComputerName = $computer
                    Drive        = $disk.DeviceID
                    Label        = $disk.VolumeName
                    SizeGB       = [math]::Round($disk.Size / 1GB, 1)
                    FreeGB       = [math]::Round($disk.FreeSpace / 1GB, 1)
                    FreePercent  = $freePercent
                    Status       = $status
                }
            }
        }
    }
}
