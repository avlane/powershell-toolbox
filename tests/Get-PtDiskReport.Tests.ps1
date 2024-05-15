#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Run from the repository root with: Invoke-Pester .\tests
#
# Mocks only reach the current runspace, so the tests pass -ThrottleLimit 1, which
# selects the serial code path. The -Parallel path needs real computers.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtDiskReport' {

    Context 'a server with two fixed disks' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'OS'; Size = 100GB; FreeSpace = 50GB },
                    [pscustomobject]@{ DeviceID = 'D:'; VolumeName = 'Data'; Size = 200GB; FreeSpace = 10GB }
                )
            }
            $report = @(Get-PtDiskReport -ComputerName 'SQLPROD01' -WarningPercent 15 -ThrottleLimit 1)
        }

        It 'returns one row per disk' {
            $report.Count | Should -Be 2
        }

        It 'reports sizes in GB and the free percentage' {
            $report[0].SizeGB | Should -Be 100
            $report[0].FreeGB | Should -Be 50
            $report[0].FreePercent | Should -Be 50
        }

        It 'marks only the disk under the warning level as Low' {
            $report[0].Status | Should -Be 'OK'
            $report[1].Status | Should -Be 'Low'
        }

        It 'carries the computer name' {
            $report[0].ComputerName | Should -Be 'SQLPROD01'
        }
    }

    Context 'a volume whose size cannot be read' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ DeviceID = 'E:'; VolumeName = 'Locked'; Size = $null; FreeSpace = $null },
                    [pscustomobject]@{ DeviceID = 'F:'; VolumeName = 'Empty'; Size = 0; FreeSpace = 0 },
                    [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'OS'; Size = 100GB; FreeSpace = 5GB }
                )
            }
            $report = @(Get-PtDiskReport -ComputerName 'SQLPROD01' -ThrottleLimit 1)
        }

        It 'still reports every disk' {
            $report.Count | Should -Be 3
        }

        It 'marks the unreadable ones Unknown' {
            $report[0].Status | Should -Be 'Unknown'
            $report[0].FreePercent | Should -BeNullOrEmpty
            $report[1].Status | Should -Be 'Unknown'
        }

        It 'does not let them affect the readable disk' {
            $report[2].Status | Should -Be 'Low'
            $report[2].FreePercent | Should -Be 5
        }
    }

    Context 'volumes mounted in folders' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
                [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'OS'; Size = 100GB; FreeSpace = 50GB }
            }
            Mock Get-CimInstance -ModuleName PowerShellToolbox -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
                @(
                    [pscustomobject]@{ Name = 'E:\SQLData\'; Label = 'Data'; Capacity = 500GB; FreeSpace = 20GB },
                    [pscustomobject]@{ Name = '\\?\Volume{0a1b2c3d-0000-0000-0000-100000000000}\'; Label = 'Recovery'; Capacity = 1GB; FreeSpace = 0.1GB }
                )
            }
        }

        It 'does not look for them unless asked to' {
            $report = @(Get-PtDiskReport -ComputerName 'SQLPROD01' -ThrottleLimit 1)
            $report.Count | Should -Be 1
            Should -Invoke Get-CimInstance -ModuleName PowerShellToolbox -Times 0 -Exactly -ParameterFilter { $ClassName -eq 'Win32_Volume' }
        }

        It 'adds mount points, with the folder as the drive, and skips volumes that are not mounted anywhere' {
            $report = @(Get-PtDiskReport -ComputerName 'SQLPROD01' -ThrottleLimit 1 -IncludeMountPoints)
            $report.Count | Should -Be 2
            $mount = $report | Where-Object Drive -eq 'E:\SQLData\'
            $mount.Label | Should -Be 'Data'
            $mount.SizeGB | Should -Be 500
            $mount.Status | Should -Be 'Low'
            $mount.FreePercent | Should -Be 4
        }
    }

    Context 'a computer that cannot be reached' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox { throw 'WinRM cannot process the request' }
        }

        It 'warns and returns nothing instead of failing' {
            $result = Get-PtDiskReport -ComputerName 'DOWN01' -ThrottleLimit 1 -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'several computers from the pipeline' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox {
                [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'OS'; Size = 100GB; FreeSpace = 50GB }
            }
        }

        It 'queries each one' {
            $result = @('A', 'B', 'C' | Get-PtDiskReport -ThrottleLimit 1)
            $result.Count | Should -Be 3
            Should -Invoke Get-CimInstance -ModuleName PowerShellToolbox -Times 3 -Exactly
        }
    }
}
