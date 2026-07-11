#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtBlockingSession' {
    Context 'a chain of three sessions' {
        BeforeAll {
            # 70 waits for 60, 60 waits for 55 (just started waiting), 55 is waiting for nobody
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match 'dm_exec_requests' } {
                @(
                    [pscustomobject]@{ SessionId = 70; BlockingSessionId = 60; WaitType = 'LCK_M_X'; WaitTimeMs = 42000; DatabaseName = 'Sales'; LoginName = 'CORP\etl'; HostName = 'ETL01'; ProgramName = 'SSIS'; StatementText = 'UPDATE t SET x = 1' },
                    [pscustomobject]@{ SessionId = 60; BlockingSessionId = 55; WaitType = 'LCK_M_U'; WaitTimeMs = 800; DatabaseName = 'Sales'; LoginName = 'CORP\app'; HostName = 'APP01'; ProgramName = 'App'; StatementText = 'UPDATE u SET y = 2' }
                )
            }
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match 'dm_exec_input_buffer' } {
                [pscustomobject]@{ SessionId = 55; LoginName = 'CORP\dba'; HostName = 'LAPTOP7'; ProgramName = 'SSMS'; Status = 'sleeping'; LastRequestStart = [datetime]'2026-07-12 09:00:00'; OpenTransactions = 1; InputBuffer = 'BEGIN TRAN; UPDATE t SET x = 0' }
            }
        }

        It 'reports only the request that has waited long enough' {
            $rows = @(Get-PtBlockingSession -ServerInstance 'SQLPROD01')
            $rows.Count | Should -Be 1
            $rows[0].SessionId | Should -Be 70
            $rows[0].WaitSeconds | Should -Be 42
        }

        It 'follows the chain through the short wait to the real head blocker' {
            $rows = @(Get-PtBlockingSession -ServerInstance 'SQLPROD01')
            $rows[0].BlockedBy | Should -Be 60
            $rows[0].HeadBlocker | Should -Be 55
        }

        It 'adds the head blocker with its input buffer on request' {
            $rows = @(Get-PtBlockingSession -ServerInstance 'SQLPROD01' -IncludeHeadBlocker)
            $head = $rows | Where-Object Kind -eq 'HeadBlocker'
            $head.SessionId | Should -Be 55
            $head.LoginName | Should -Be 'CORP\dba'
            $head.Text | Should -Match 'BEGIN TRAN'
            Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match 'IN \(55\)' }
        }

        It 'lowers the bar with -MinimumWaitSeconds' {
            @(Get-PtBlockingSession -ServerInstance 'SQLPROD01' -MinimumWaitSeconds 0).Count | Should -Be 2
        }
    }

    Context 'nothing is blocked' {
        It 'returns nothing and does not ask for head blockers' {
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox { }
            Get-PtBlockingSession -ServerInstance 'SQLPROD01' -IncludeHeadBlocker | Should -BeNullOrEmpty
            Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -Times 1 -Exactly
        }
    }

    Context 'sessions that block each other' {
        It 'does not loop forever' {
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match 'dm_exec_requests' } {
                @(
                    [pscustomobject]@{ SessionId = 51; BlockingSessionId = 52; WaitType = 'LCK_M_X'; WaitTimeMs = 9000; DatabaseName = 'db'; LoginName = 'a'; HostName = 'h'; ProgramName = 'p'; StatementText = 's1' },
                    [pscustomobject]@{ SessionId = 52; BlockingSessionId = 51; WaitType = 'LCK_M_X'; WaitTimeMs = 9000; DatabaseName = 'db'; LoginName = 'b'; HostName = 'h'; ProgramName = 'p'; StatementText = 's2' }
                )
            }
            $rows = @(Get-PtBlockingSession -ServerInstance 'SQLPROD01')
            $rows.Count | Should -Be 2
        }
    }
}
