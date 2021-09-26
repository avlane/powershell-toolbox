#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Get-CimInstance is mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtServiceTriage' {
    Context 'a server with stopped services' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ Name = 'MSSQLSERVER'; DisplayName = 'SQL Server'; State = 'Stopped'; StartName = 'CORP\svc-sql'; ExitCode = 1067 },
                    [pscustomobject]@{ Name = 'sppsvc'; DisplayName = 'Software Protection'; State = 'Stopped'; StartName = 'NT AUTHORITY\NetworkService'; ExitCode = 0 },
                    [pscustomobject]@{ Name = 'gupdate'; DisplayName = 'Google Update'; State = 'Stopped'; StartName = 'LocalSystem'; ExitCode = 0 }
                )
            }
        }

        It 'lists the failed service with its account and exit code' {
            $result = @(Get-PtServiceTriage -ComputerName 'SQLPROD01')
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'MSSQLSERVER'
            $result[0].StartName | Should -Be 'CORP\svc-sql'
            $result[0].ExitCode | Should -Be 1067
            $result[0].ComputerName | Should -Be 'SQLPROD01'
        }

        It 'leaves out services that are meant to stop, unless asked' {
            @(Get-PtServiceTriage -ComputerName 'SQLPROD01' -IncludeExpected).Count | Should -Be 3
        }

        It 'asks only for automatic services that are not running' {
            Get-PtServiceTriage -ComputerName 'SQLPROD01' | Out-Null
            Should -Invoke Get-CimInstance -ModuleName PowerShellToolbox -ParameterFilter {
                $ClassName -eq 'Win32_Service' -and $Filter -match "StartMode = 'Auto'" -and $Filter -match "State <> 'Running'"
            }
        }
    }

    Context 'a computer that cannot be reached' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox { throw 'WinRM cannot process the request' }
        }

        It 'warns and moves on' {
            $result = Get-PtServiceTriage -ComputerName 'DOWN01' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            "$warnings" | Should -Match 'DOWN01'
        }
    }
}
