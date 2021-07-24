#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Get-WinEvent is mocked, so no event log is read.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtEventLogSummary' {
    Context 'a log with repeated errors' {
        BeforeAll {
            Mock Get-WinEvent -ModuleName PowerShellToolbox {
                $base = [datetime]'2021-07-20 08:00:00'
                $events = @()
                foreach ($minute in 0, 10, 20, 30) {
                    $events += [pscustomobject]@{ ProviderName = 'disk'; Id = 153; LevelDisplayName = 'Warning'; TimeCreated = $base.AddMinutes($minute); Message = "The IO operation was retried.`r`nMore detail" }
                }
                $events += [pscustomobject]@{ ProviderName = 'Service Control Manager'; Id = 7031; LevelDisplayName = 'Error'; TimeCreated = $base.AddMinutes(5); Message = 'The Print Spooler service terminated unexpectedly.' }
                $events += [pscustomobject]@{ ProviderName = 'Service Control Manager'; Id = 7031; LevelDisplayName = 'Error'; TimeCreated = $base.AddMinutes(45); Message = 'The Print Spooler service terminated unexpectedly.' }
                $events += [pscustomobject]@{ ProviderName = 'Kernel-Power'; Id = 41; LevelDisplayName = 'Critical'; TimeCreated = $base.AddMinutes(2); Message = $null }
                $events
            }
            $summary = @(Get-PtEventLogSummary -ComputerName 'SQLPROD01' -Level Critical, Error, Warning)
        }

        It 'groups by provider and event id, most frequent first' {
            $summary.Count | Should -Be 3
            $summary[0].Provider | Should -Be 'disk'
            $summary[0].Count | Should -Be 4
            $summary[1].EventId | Should -Be 7031
            $summary[1].Count | Should -Be 2
            $summary[2].Count | Should -Be 1
        }

        It 'reports the first and last time and the first line of the message' {
            $summary[0].FirstSeen | Should -Be ([datetime]'2021-07-20 08:00:00')
            $summary[0].LastSeen | Should -Be ([datetime]'2021-07-20 08:30:00')
            $summary[0].Message | Should -Be 'The IO operation was retried.'
        }

        It 'copes with an event that has no message' {
            $summary[2].Message | Should -Be ''
        }

        It 'limits the groups with -Top' {
            @(Get-PtEventLogSummary -ComputerName 'SQLPROD01' -Level Critical, Error, Warning -Top 1).Count | Should -Be 1
        }

        It 'translates the levels into numbers for the filter' {
            Get-PtEventLogSummary -ComputerName 'SQLPROD01' -Level Critical, Warning -LogName Application | Out-Null
            Should -Invoke Get-WinEvent -ModuleName PowerShellToolbox -ParameterFilter {
                $FilterHashtable.LogName -eq 'Application' -and ($FilterHashtable.Level -join ',') -eq '1,3'
            }
        }
    }

    Context 'a log without matching events' {
        BeforeAll {
            Mock Get-WinEvent -ModuleName PowerShellToolbox {
                $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList (
                    (New-Object -TypeName System.Exception -ArgumentList 'No events were found that match the specified selection criteria.'),
                    'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null)
                throw $record
            }
        }

        It 'returns nothing and does not warn' {
            $result = Get-PtEventLogSummary -ComputerName 'SQLPROD01' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context 'a log that cannot be read' {
        BeforeAll {
            Mock Get-WinEvent -ModuleName PowerShellToolbox { throw 'The RPC server is unavailable.' }
        }

        It 'warns and carries on' {
            $result = Get-PtEventLogSummary -ComputerName 'DOWN01' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            "$warnings" | Should -Match 'DOWN01'
        }
    }
}
