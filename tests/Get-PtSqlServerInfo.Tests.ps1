#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtSqlServerInfo' {
    Context 'a server left at its defaults' {
        BeforeAll {
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
                [pscustomobject]@{
                    MachineName = 'SQLPROD01'; ProductVersion = '15.0.4298.1'; ProductLevel = 'RTM'; ProductUpdateLevel = 'CU18'
                    Edition = 'Enterprise Edition (64-bit)'; IsClustered = 0; IsHadrEnabled = 1
                    StartTime = [datetime]'2023-03-01 02:00:00'; ServerTime = [datetime]'2023-03-15 14:00:00'
                    CpuCount = 16; PhysicalMemoryMB = 262144; MaxServerMemoryMB = 2147483647; Maxdop = 0; CostThreshold = 5; TempdbFiles = 1
                }
            }
            $info = Get-PtSqlServerInfo -ServerInstance 'SQLPROD01'
        }

        It 'names the version and level' {
            $info.Version | Should -Be 'SQL Server 2019 (15.0.4298.1)'
            $info.Level | Should -Be 'CU18'
            $info.AvailabilityGroups | Should -Be $true
            $info.Clustered | Should -Be $false
        }

        It 'works out the uptime' {
            $info.UptimeDays | Should -Be 14.5
        }

        It 'flags the settings that are still at their defaults' {
            $info.Flags | Should -Be 'MaxMemoryNotSet, MaxdopZeroOnManyCores, CostThresholdDefault, FewTempdbFiles'
        }
    }

    Context 'a server that was tuned' {
        BeforeAll {
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
                [pscustomobject]@{
                    MachineName = 'SQLPROD02'; ProductVersion = '16.0.1000.6'; ProductLevel = 'RTM'; ProductUpdateLevel = $null
                    Edition = 'Standard Edition (64-bit)'; IsClustered = 1; IsHadrEnabled = 0
                    StartTime = [datetime]'2023-03-15 08:00:00'; ServerTime = [datetime]'2023-03-15 15:00:00'
                    CpuCount = 4; PhysicalMemoryMB = 32768; MaxServerMemoryMB = 28672; Maxdop = 4; CostThreshold = 50; TempdbFiles = 4
                }
            }
            $info = Get-PtSqlServerInfo -ServerInstance 'SQLPROD02'
        }

        It 'has no flags' {
            $info.Flags | Should -Be ''
        }

        It 'falls back to the product level when there is no update level' {
            $info.Version | Should -Be 'SQL Server 2022 (16.0.1000.6)'
            $info.Level | Should -Be 'RTM'
            $info.UptimeDays | Should -Be 0.3
        }
    }
}
