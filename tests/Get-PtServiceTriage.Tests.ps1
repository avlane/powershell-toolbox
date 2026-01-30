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

        It 'with -OnlyFailed lists only services that stopped with an error' {
            Mock Get-CimInstance -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ Name = 'MSSQLSERVER'; DisplayName = 'SQL Server'; State = 'Stopped'; StartName = 'CORP\svc-sql'; ExitCode = 1067 },
                    [pscustomobject]@{ Name = 'Clean'; DisplayName = 'Stopped on purpose'; State = 'Stopped'; StartName = 'LocalSystem'; ExitCode = 0 },
                    [pscustomobject]@{ Name = 'Delayed'; DisplayName = 'Not started yet'; State = 'Stopped'; StartName = 'LocalSystem'; ExitCode = 1077 },
                    [pscustomobject]@{ Name = 'Specific'; DisplayName = 'Own error code'; State = 'Stopped'; StartName = 'LocalSystem'; ExitCode = 1066 }
                )
            }
            @(Get-PtServiceTriage -ComputerName 'SQLPROD01' -OnlyFailed).Name -join ',' | Should -Be 'MSSQLSERVER,Specific'
            @(Get-PtServiceTriage -ComputerName 'SQLPROD01').Count | Should -Be 4
        }

        It 'asks only for automatic services that are not running' {
            Get-PtServiceTriage -ComputerName 'SQLPROD01' | Out-Null
            Should -Invoke Get-CimInstance -ModuleName PowerShellToolbox -ParameterFilter {
                $ClassName -eq 'Win32_Service' -and $Filter -match "StartMode = 'Auto'" -and $Filter -match "State <> 'Running'"
            }
        }
    }

    Context 'with the last event' {
        BeforeAll {
            Mock Get-CimInstance -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ Name = 'MSSQLSERVER'; DisplayName = 'SQL Server (MSSQLSERVER)'; State = 'Stopped'; StartName = 'CORP\svc-sql'; ExitCode = 1067 },
                    [pscustomobject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; State = 'Stopped'; StartName = 'LocalSystem'; ExitCode = 0 }
                )
            }
            Mock Get-WinEvent -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ TimeCreated = [datetime]'2023-07-29 03:00:00'; Id = 7031; Message = "The SQL Server (MSSQLSERVER) service terminated unexpectedly.`r`nIt has done this 1 time(s)." },
                    [pscustomobject]@{ TimeCreated = [datetime]'2023-07-30 01:00:00'; Id = 7034; Message = 'The SQL Server (MSSQLSERVER) service terminated unexpectedly.' },
                    [pscustomobject]@{ TimeCreated = [datetime]'2023-07-28 01:00:00'; Id = 7000; Message = 'Something about another service.' }
                )
            }
        }

        It 'adds the newest matching event to each service' {
            $result = @(Get-PtServiceTriage -ComputerName 'SQLPROD01' -IncludeLastEvent)
            $sql = $result | Where-Object Name -eq 'MSSQLSERVER'
            $sql.LastEventId | Should -Be 7034
            $sql.LastEventTime | Should -Be ([datetime]'2023-07-30 01:00:00')
            $sql.LastEventMessage | Should -Be 'The SQL Server (MSSQLSERVER) service terminated unexpectedly.'
        }

        It 'leaves the event columns empty for a service without events' {
            $spooler = Get-PtServiceTriage -ComputerName 'SQLPROD01' -IncludeLastEvent | Where-Object Name -eq 'Spooler'
            $spooler.LastEventTime | Should -BeNullOrEmpty
            $spooler.LastEventMessage | Should -BeNullOrEmpty
        }

        It 'does not read the event log unless asked to' {
            Get-PtServiceTriage -ComputerName 'SQLPROD01' | Out-Null
            Should -Invoke Get-WinEvent -ModuleName PowerShellToolbox -Times 0 -Exactly
        }

        It 'adds no event columns by default' {
            (Get-PtServiceTriage -ComputerName 'SQLPROD01' | Select-Object -First 1).PSObject.Properties.Name | Should -Not -Contain 'LastEventId'
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
