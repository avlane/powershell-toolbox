#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtWaitStats' {
    BeforeEach {
        $global:PtTestReadings = 0
        Mock Start-Sleep -ModuleName PowerShellToolbox { }
    }

    AfterAll {
        Remove-Variable -Name PtTestReadings -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'cumulative' {
        BeforeEach {
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ WaitType = 'SLEEP_TASK'; WaitingTasks = 100; WaitTimeMs = 9000000; SignalWaitTimeMs = 100 },
                    [pscustomobject]@{ WaitType = 'PAGEIOLATCH_SH'; WaitingTasks = 1000; WaitTimeMs = 60000; SignalWaitTimeMs = 1000 },
                    [pscustomobject]@{ WaitType = 'WRITELOG'; WaitingTasks = 4000; WaitTimeMs = 30000; SignalWaitTimeMs = 4000 },
                    [pscustomobject]@{ WaitType = 'MYSTERY_WAIT'; WaitingTasks = 10; WaitTimeMs = 10000; SignalWaitTimeMs = 0 },
                    [pscustomobject]@{ WaitType = 'XE_TIMER_EVENT'; WaitingTasks = 5; WaitTimeMs = 500000; SignalWaitTimeMs = 0 }
                )
            }
        }

        It 'leaves out idle waits and sorts by wait time' {
            $waits = @(Get-PtWaitStats -ServerInstance 'SQLPROD01')
            $waits.WaitType -join ',' | Should -Be 'PAGEIOLATCH_SH,WRITELOG,MYSTERY_WAIT'
        }

        It 'works out the share of the remaining waits' {
            $waits = @(Get-PtWaitStats -ServerInstance 'SQLPROD01')
            $waits[0].Percent | Should -Be 60
            $waits[1].Percent | Should -Be 30
            $waits[2].Percent | Should -Be 10
        }

        It 'splits signal and resource time and averages per wait' {
            $first = Get-PtWaitStats -ServerInstance 'SQLPROD01' | Select-Object -First 1
            $first.WaitSeconds | Should -Be 60
            $first.SignalSeconds | Should -Be 1
            $first.ResourceSeconds | Should -Be 59
            $first.AvgMsPerWait | Should -Be 60
        }

        It 'explains the common waits and is quiet about the others' {
            $waits = @(Get-PtWaitStats -ServerInstance 'SQLPROD01')
            $waits[0].Description | Should -Match 'read from disk'
            $waits[2].Description | Should -Be ''
        }

        It 'limits the list with -Top' {
            @(Get-PtWaitStats -ServerInstance 'SQLPROD01' -Top 1).Count | Should -Be 1
        }
    }

    Context 'sampled' {
        BeforeAll {
            Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
                $global:PtTestReadings++
                if ($global:PtTestReadings -eq 1) {
                    @(
                        [pscustomobject]@{ WaitType = 'WRITELOG'; WaitingTasks = 1000; WaitTimeMs = 10000; SignalWaitTimeMs = 100 },
                        [pscustomobject]@{ WaitType = 'PAGEIOLATCH_SH'; WaitingTasks = 500; WaitTimeMs = 50000; SignalWaitTimeMs = 100 }
                    )
                }
                else {
                    @(
                        [pscustomobject]@{ WaitType = 'WRITELOG'; WaitingTasks = 1500; WaitTimeMs = 15000; SignalWaitTimeMs = 150 },
                        [pscustomobject]@{ WaitType = 'PAGEIOLATCH_SH'; WaitingTasks = 500; WaitTimeMs = 50000; SignalWaitTimeMs = 100 },
                        [pscustomobject]@{ WaitType = 'LCK_M_X'; WaitingTasks = 5; WaitTimeMs = 3000; SignalWaitTimeMs = 0 }
                    )
                }
            }
        }

        It 'reports only what happened between the two readings' {
            $global:PtTestReadings = 0
            $waits = @(Get-PtWaitStats -ServerInstance 'SQLPROD01' -SampleSeconds 30)
            $waits.WaitType -join ',' | Should -Be 'WRITELOG,LCK_M_X'
            $waits[0].WaitSeconds | Should -Be 5
            $waits[0].WaitingTasks | Should -Be 500
            $waits[0].Percent | Should -Be 62.5
            Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
        }
    }
}
