#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests for the SQL Server helpers. Invoke-Sqlcmd is mocked, so no SQL
# Server (and no SqlServer module) is needed.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'

    # a stand-in so the command exists (and can be mocked) without the SqlServer module
    function global:Invoke-Sqlcmd { param($ServerInstance, $Database, $Query, $QueryTimeout, $Username, $Password, [switch]$TrustServerCertificate, $Encrypt) }

    # global, so the module-scoped mocks can call it
    function global:New-TestDataRow {
        param([System.Collections.Specialized.OrderedDictionary]$Values)
        $table = New-Object -TypeName System.Data.DataTable
        foreach ($name in $Values.Keys) { [void]$table.Columns.Add($name, [object]) }
        $row = $table.NewRow()
        foreach ($name in $Values.Keys) { $row[$name] = $Values[$name] }
        $table.Rows.Add($row)
        # unary comma: stop PowerShell from enumerating the DataRow on its way out
        , $row
    }

    Import-Module $manifest -Force
}

AfterAll {
    Remove-Item -Path Function:\global:Invoke-Sqlcmd, Function:\global:New-TestDataRow -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-PtDataRow' {
    # an internal function, so it is called from inside the module
    BeforeAll {
        $object = InModuleScope PowerShellToolbox {
            $row = New-TestDataRow ([ordered]@{ Name = 'master'; Size = 8; Notes = [System.DBNull]::Value })
            ConvertFrom-PtDataRow -Row $row -ServerInstance 'SQLPROD01'
        }
    }

    It 'puts the server first and keeps the column order' {
        @($object.PSObject.Properties.Name) -join ',' | Should -Be 'ServerInstance,Name,Size,Notes'
    }

    It 'copies values' {
        $object.Name | Should -Be 'master'
        $object.Size | Should -Be 8
    }

    It 'turns DBNull into $null' {
        $object.Notes | Should -BeNullOrEmpty
        $object.Notes -is [System.DBNull] | Should -Be $false
    }
}

Describe 'Invoke-PtSqlQuery' {
    Context 'two servers' {
        BeforeAll {
            Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox {
                New-TestDataRow ([ordered]@{ Answer = 42 })
            }
            $result = @(Invoke-PtSqlQuery -ServerInstance 'SQLPROD01', 'SQLPROD02' -Query 'SELECT 42 AS Answer' -ThrottleLimit 1)
        }

        It 'runs the query once per server' {
            Should -Invoke Invoke-Sqlcmd -ModuleName PowerShellToolbox -Times 2 -Exactly
        }

        It 'tags every row with its server' {
            $result.Count | Should -Be 2
            $result[0].ServerInstance | Should -Be 'SQLPROD01'
            $result[1].ServerInstance | Should -Be 'SQLPROD02'
            $result[1].Answer | Should -Be 42
        }
    }

    Context 'a SQL login' {
        BeforeAll {
            Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox { }
            $secure = ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force
            $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'monitor', $secure
        }

        It 'passes the user name and password on' {
            Invoke-PtSqlQuery -ServerInstance 'SQLPROD01' -Query 'SELECT 1' -Credential $credential -ThrottleLimit 1 | Out-Null
            Should -Invoke Invoke-Sqlcmd -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
                $Username -eq 'monitor' -and $Password -eq 'not-a-real-password'
            }
        }
    }

    Context 'connection security options' {
        BeforeAll {
            Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox { }
        }

        It 'passes -TrustServerCertificate and -Encrypt on' {
            Invoke-PtSqlQuery -ServerInstance 'SQLPROD01' -Query 'SELECT 1' -TrustServerCertificate -Encrypt Optional -ThrottleLimit 1 | Out-Null
            Should -Invoke Invoke-Sqlcmd -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
                $TrustServerCertificate -eq $true -and $Encrypt -eq 'Optional'
            }
        }

        It 'does not send them when they were not asked for' {
            Invoke-PtSqlQuery -ServerInstance 'SQLPROD01' -Query 'SELECT 1' -ThrottleLimit 1 | Out-Null
            Should -Invoke Invoke-Sqlcmd -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { -not $TrustServerCertificate -and -not $Encrypt }
        }

        It 'explains that the SqlServer module is too old' {
            Mock Test-PtCommandParameter -ModuleName PowerShellToolbox { $false }
            { Invoke-PtSqlQuery -ServerInstance 'SQLPROD01' -Query 'SELECT 1' -TrustServerCertificate -ThrottleLimit 1 } | Should -Throw '*Update-Module SqlServer*'
        }
    }

    Context 'a server that fails' {
        BeforeAll {
            Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox -ParameterFilter { $ServerInstance -eq 'BAD01' } { throw 'login failed' }
            Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox -ParameterFilter { $ServerInstance -ne 'BAD01' } {
                New-TestDataRow ([ordered]@{ Answer = 1 })
            }
        }

        It 'reports the error and carries on with the next server' {
            $result = @(Invoke-PtSqlQuery -ServerInstance 'BAD01', 'GOOD01' -Query 'SELECT 1' -ThrottleLimit 1 -ErrorAction SilentlyContinue -ErrorVariable problems)
            $result.Count | Should -Be 1
            $result[0].ServerInstance | Should -Be 'GOOD01'
            "$problems" | Should -Match 'BAD01'
        }
    }
}

Describe 'Get-PtBackupStatus' {
    BeforeAll {
        # mock bodies run in the module's scope and cannot see variables of this
        # Describe, so the "current" time is defined inside the mock
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
            $now = [datetime]'2019-08-01 12:00:00'
            @(
                [pscustomobject]@{ DatabaseName = 'Sales'; RecoveryModel = 'FULL'; ServerTime = $now; LastFull = $now.AddHours(-10); LastDiff = $null; LastLog = $now.AddMinutes(-10) },
                [pscustomobject]@{ DatabaseName = 'Old'; RecoveryModel = 'SIMPLE'; ServerTime = $now; LastFull = $now.AddDays(-7); LastDiff = $null; LastLog = $null },
                [pscustomobject]@{ DatabaseName = 'Never'; RecoveryModel = 'SIMPLE'; ServerTime = $now; LastFull = $null; LastDiff = $null; LastLog = $null },
                [pscustomobject]@{ DatabaseName = 'NoLogs'; RecoveryModel = 'FULL'; ServerTime = $now; LastFull = $now.AddHours(-2); LastDiff = $null; LastLog = $null },
                [pscustomobject]@{ DatabaseName = 'DiffOnly'; RecoveryModel = 'SIMPLE'; ServerTime = $now; LastFull = $now.AddDays(-7); LastDiff = $now.AddHours(-5); LastLog = $null }
            )
        }
        $status = @(Get-PtBackupStatus -ServerInstance 'SQLPROD01')
    }

    It 'returns a row per database' {
        $status.Count | Should -Be 5
    }

    It 'calls a recent full backup with fresh log backups OK' {
        $row = $status | Where-Object DatabaseName -eq 'Sales'
        $row.Status | Should -Be 'OK'
        $row.HoursSinceBase | Should -Be 10
    }

    It 'flags an old full backup as Stale' {
        $row = $status | Where-Object DatabaseName -eq 'Old'
        $row.Status | Should -Be 'Stale'
        $row.Problems | Should -Match 'no full or differential backup for 168'
    }

    It 'flags a database that was never backed up' {
        ($status | Where-Object DatabaseName -eq 'Never').Status | Should -Be 'NoBackup'
    }

    It 'wants log backups for databases in the full recovery model' {
        $row = $status | Where-Object DatabaseName -eq 'NoLogs'
        $row.Status | Should -Be 'Stale'
        $row.Problems | Should -Match 'no log backup'
    }

    It 'uses a newer differential backup as the base' {
        $row = $status | Where-Object DatabaseName -eq 'DiffOnly'
        $row.Status | Should -Be 'OK'
        $row.HoursSinceBase | Should -Be 5
    }
}

Describe 'Get-PtAgentJobReport' {
    BeforeAll {
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ JobName = 'Backup full'; Enabled = 1; LastRunStatus = 1; LastRunTime = $null; LastRunSeconds = 300; LastMessage = 'ok'; NextRunTime = $null; FailedRuns = 0 },
                [pscustomobject]@{ JobName = 'Index maintenance'; Enabled = 1; LastRunStatus = 0; LastRunTime = $null; LastRunSeconds = 10; LastMessage = 'failed'; NextRunTime = $null; FailedRuns = 2 },
                [pscustomobject]@{ JobName = 'Cleanup'; Enabled = 1; LastRunStatus = 1; LastRunTime = $null; LastRunSeconds = 5; LastMessage = 'ok'; NextRunTime = $null; FailedRuns = 1 },
                [pscustomobject]@{ JobName = 'Old job'; Enabled = 0; LastRunStatus = 0; LastRunTime = $null; LastRunSeconds = 5; LastMessage = 'x'; NextRunTime = $null; FailedRuns = 0 },
                [pscustomobject]@{ JobName = 'Brand new'; Enabled = 1; LastRunStatus = $null; LastRunTime = $null; LastRunSeconds = $null; LastMessage = $null; NextRunTime = $null; FailedRuns = 0 }
            )
        }
    }

    It 'decides a verdict per job' {
        $report = @(Get-PtAgentJobReport -ServerInstance 'SQLPROD01')
        ($report | Where-Object JobName -eq 'Backup full').Verdict | Should -Be 'OK'
        ($report | Where-Object JobName -eq 'Index maintenance').Verdict | Should -Be 'Failed'
        ($report | Where-Object JobName -eq 'Cleanup').Verdict | Should -Be 'Flaky'
        ($report | Where-Object JobName -eq 'Old job').Verdict | Should -Be 'Disabled'
        ($report | Where-Object JobName -eq 'Brand new').LastRunStatus | Should -Be 'NeverRun'
    }

    It 'can show only the problems' {
        $report = @(Get-PtAgentJobReport -ServerInstance 'SQLPROD01' -OnlyProblems)
        $report.Count | Should -Be 3
        $report.JobName | Should -Not -Contain 'Backup full'
    }

    It 'adds the failed step and its message with -IncludeStepDetail' {
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match 'CROSS APPLY' } {
            [pscustomobject]@{ JobName = 'Index maintenance'; StepId = 2; StepName = 'Rebuild'; Message = 'Executed as user: CORP\\svc. Could not allocate space. [SQLSTATE 42000]' }
        }
        $report = @(Get-PtAgentJobReport -ServerInstance 'SQLPROD01' -IncludeStepDetail)
        $failed = $report | Where-Object JobName -eq 'Index maintenance'
        $failed.FailedStep | Should -Be '2 Rebuild'
        $failed.FailedStepMessage | Should -Match 'Could not allocate space'
        ($report | Where-Object JobName -eq 'Backup full').FailedStep | Should -BeNullOrEmpty
    }

    It 'does not ask for step details unless told to' {
        Get-PtAgentJobReport -ServerInstance 'SQLPROD01' | Out-Null
        Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -Times 1 -Exactly
    }

    It 'puts the window into the query' {
        Get-PtAgentJobReport -ServerInstance 'SQLPROD01' -Hours 72 | Out-Null
        Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match 'DATEADD\(HOUR, -72, GETDATE\(\)\)' }
    }
}
