# Pester 4 tests. Run from the repository root with: Invoke-Pester .\tests
$moduleRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path (Join-Path $moduleRoot 'PowerShellToolbox') 'PowerShellToolbox.psd1'
Import-Module $manifest -Force

Describe 'Get-PtDiskReport' {

    Context 'a server with two fixed disks' {
        Mock Get-WmiObject -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'OS'; Size = 100GB; FreeSpace = 50GB },
                [pscustomobject]@{ DeviceID = 'D:'; VolumeName = 'Data'; Size = 200GB; FreeSpace = 10GB }
            )
        }

        BeforeAll {
            $report = @(Get-PtDiskReport -ComputerName 'SQLPROD01' -WarningPercent 15)
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

    Context 'a computer that cannot be reached' {
        Mock Get-WmiObject -ModuleName PowerShellToolbox { throw 'RPC server is unavailable' }

        It 'warns and returns nothing instead of failing' {
            $result = Get-PtDiskReport -ComputerName 'DOWN01' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'several computers from the pipeline' {
        Mock Get-WmiObject -ModuleName PowerShellToolbox {
            [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'OS'; Size = 100GB; FreeSpace = 50GB }
        }

        It 'queries each one' {
            $result = @('A', 'B', 'C' | Get-PtDiskReport)
            $result.Count | Should -Be 3
            Assert-MockCalled Get-WmiObject -ModuleName PowerShellToolbox -Times 3 -Exactly
        }
    }
}
