function Get-PtDiskReport {
    <#
    .SYNOPSIS
    Reports the free space on the fixed disks of one or more computers.

    .DESCRIPTION
    Queries Win32_LogicalDisk (fixed disks only, DriveType 3) with CIM and returns
    one object per disk with size, free space and a status of OK, Low or Unknown
    (Unknown: the size could not be read).

    With more than one computer, the computers are queried in parallel (see
    -ThrottleLimit).

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER WarningPercent
    A disk with less than this percentage free is reported as Low. Default 10.

    .PARAMETER ThrottleLimit
    How many computers to query at the same time. Default 5.
    1 means one at a time.

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
        [int]$WarningPercent = 10,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 5
    )

    begin {
        $computers = New-Object -TypeName 'System.Collections.Generic.List[string]'
    }

    process {
        foreach ($computer in $ComputerName) { $computers.Add($computer) }
    }

    end {
        # Fetching is the slow part, so only that is done in parallel. The runspaces
        # started by -Parallel do not have this module's functions, which is why the
        # block calls Get-CimInstance directly and the rows are built afterwards.
        if ($ThrottleLimit -gt 1 -and $computers.Count -gt 1) {
            $fetched = $computers | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $target = $_    # inside catch, $_ is the error record
                try {
                    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $target -ErrorAction Stop)
                    [pscustomobject]@{ Computer = $target; Disks = $disks; Error = $null }
                }
                catch {
                    [pscustomobject]@{ Computer = $target; Disks = @(); Error = $_.Exception.Message }
                }
            }
        }
        else {
            $fetched = foreach ($computer in $computers) {
                try {
                    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $computer -ErrorAction Stop)
                    [pscustomobject]@{ Computer = $computer; Disks = $disks; Error = $null }
                }
                catch {
                    [pscustomobject]@{ Computer = $computer; Disks = @(); Error = $_.Exception.Message }
                }
            }
        }

        foreach ($result in $fetched) {
            if ($result.Error) {
                Write-Warning "Could not query $($result.Computer) : $($result.Error)"
                continue
            }

            foreach ($disk in $result.Disks) {
                # WMI returns no size for a volume it cannot read (a locked BitLocker
                # volume, for example); dividing by that would give wrong numbers
                if ($disk.Size -gt 0) {
                    $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                    $status = $freePercent -lt $WarningPercent ? 'Low' : 'OK'
                    $sizeGb = [math]::Round($disk.Size / 1GB, 1)
                    $freeGb = [math]::Round($disk.FreeSpace / 1GB, 1)
                }
                else {
                    $freePercent = $null
                    $status = 'Unknown'
                    $sizeGb = $null
                    $freeGb = $null
                }

                [pscustomobject]@{
                    ComputerName = $result.Computer
                    Drive        = $disk.DeviceID
                    Label        = $disk.VolumeName
                    SizeGB       = $sizeGb
                    FreeGB       = $freeGb
                    FreePercent  = $freePercent
                    Status       = $status
                }
            }
        }
    }
}
