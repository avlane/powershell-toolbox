# Pester 4 tests for the SQL Server helpers. Invoke-Sqlcmd is mocked, so no
# SQL Server (and no SqlServer module) is needed.
$moduleRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path (Join-Path $moduleRoot 'PowerShellToolbox') 'PowerShellToolbox.psd1'

# a stand-in so the command exists (and can be mocked) without the SqlServer module
function global:Invoke-Sqlcmd { param($ServerInstance, $Database, $Query, $QueryTimeout, $Username, $Password) }

Import-Module $manifest -Force

# global, so the module-scoped mocks below can call it
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

# ConvertFrom-PtDataRow is internal, so these tests run inside the module
InModuleScope PowerShellToolbox {
    Describe 'ConvertFrom-PtDataRow' {
        $row = New-TestDataRow ([ordered]@{ Name = 'master'; Size = 8; Notes = [System.DBNull]::Value })
        $object = ConvertFrom-PtDataRow -Row $row -ServerInstance 'SQLPROD01'

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
}

Describe 'Invoke-PtSqlQuery' {
    Context 'two servers' {
        Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox {
            New-TestDataRow ([ordered]@{ Answer = 42 })
        }

        BeforeAll {
            $result = @(Invoke-PtSqlQuery -ServerInstance 'SQLPROD01', 'SQLPROD02' -Query 'SELECT 42 AS Answer')
        }

        It 'runs the query once per server' {
            Assert-MockCalled Invoke-Sqlcmd -ModuleName PowerShellToolbox -Times 2 -Exactly
        }

        It 'tags every row with its server' {
            $result.Count | Should -Be 2
            $result[0].ServerInstance | Should -Be 'SQLPROD01'
            $result[1].ServerInstance | Should -Be 'SQLPROD02'
            $result[1].Answer | Should -Be 42
        }
    }

    Context 'a SQL login' {
        Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox { }
        $secure = ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'monitor', $secure

        It 'passes the user name and password on' {
            Invoke-PtSqlQuery -ServerInstance 'SQLPROD01' -Query 'SELECT 1' -Credential $credential | Out-Null
            Assert-MockCalled Invoke-Sqlcmd -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
                $Username -eq 'monitor' -and $Password -eq 'not-a-real-password'
            }
        }
    }

    Context 'a server that fails' {
        Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox -ParameterFilter { $ServerInstance -eq 'BAD01' } { throw 'login failed' }
        Mock Invoke-Sqlcmd -ModuleName PowerShellToolbox -ParameterFilter { $ServerInstance -ne 'BAD01' } {
            New-TestDataRow ([ordered]@{ Answer = 1 })
        }

        It 'reports the error and carries on with the next server' {
            $result = @(Invoke-PtSqlQuery -ServerInstance 'BAD01', 'GOOD01' -Query 'SELECT 1' -ErrorAction SilentlyContinue -ErrorVariable problems)
            $result.Count | Should -Be 1
            $result[0].ServerInstance | Should -Be 'GOOD01'
            "$problems" | Should -Match 'BAD01'
        }
    }
}

Describe 'Get-PtBackupStatus' {
    # mock bodies run in the module's scope and cannot see variables of this Describe,
    # so the "current" time is defined inside the mock
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

    BeforeAll {
        $status = @(Get-PtBackupStatus -ServerInstance 'SQLPROD01')
        function Get-Row($name) { $status | Where-Object DatabaseName -eq $name }
    }

    It 'returns a row per database' {
        $status.Count | Should -Be 5
    }

    It 'calls a recent full backup with fresh log backups OK' {
        (Get-Row 'Sales').Status | Should -Be 'OK'
        (Get-Row 'Sales').HoursSinceBase | Should -Be 10
    }

    It 'flags an old full backup as Stale' {
        (Get-Row 'Old').Status | Should -Be 'Stale'
        (Get-Row 'Old').Problems | Should -Match 'no full or differential backup for 168'
    }

    It 'flags a database that was never backed up' {
        (Get-Row 'Never').Status | Should -Be 'NoBackup'
    }

    It 'wants log backups for databases in the full recovery model' {
        (Get-Row 'NoLogs').Status | Should -Be 'Stale'
        (Get-Row 'NoLogs').Problems | Should -Match 'no log backup'
    }

    It 'uses a newer differential backup as the base' {
        (Get-Row 'DiffOnly').Status | Should -Be 'OK'
        (Get-Row 'DiffOnly').HoursSinceBase | Should -Be 5
    }
}
