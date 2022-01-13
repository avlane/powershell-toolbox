#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtLongRunningQuery' {
    BeforeAll {
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ SessionId = 55; DatabaseName = 'Sales'; LoginName = 'CORP\report'; HostName = 'APP01'; ProgramName = 'Report'; Status = 'running'; Command = 'SELECT'; StartTime = $null; ElapsedSeconds = 600; CpuMs = 45000; LogicalReads = 123456; WaitType = 'PAGEIOLATCH_SH'; BlockingSessionId = 0; StatementText = 'SELECT * FROM big' },
                [pscustomobject]@{ SessionId = 61; DatabaseName = 'Sales'; LoginName = 'sa'; HostName = 'SQLPROD01'; ProgramName = 'SSMS'; Status = 'suspended'; Command = 'BACKUP DATABASE'; StartTime = $null; ElapsedSeconds = 3000; CpuMs = 100; LogicalReads = 5; WaitType = 'BACKUPIO'; BlockingSessionId = 0; StatementText = 'BACKUP DATABASE [Sales] ...' },
                [pscustomobject]@{ SessionId = 70; DatabaseName = 'Sales'; LoginName = 'CORP\etl'; HostName = 'ETL01'; ProgramName = 'SSIS'; Status = 'suspended'; Command = 'UPDATE'; StartTime = $null; ElapsedSeconds = 90; CpuMs = 10; LogicalReads = 7; WaitType = 'LCK_M_X'; BlockingSessionId = 55; StatementText = 'UPDATE t SET x = 1' }
            )
        }
    }

    It 'leaves out maintenance commands by default' {
        $result = @(Get-PtLongRunningQuery -ServerInstance 'SQLPROD01')
        $result.SessionId -join ',' | Should -Be '55,70'
    }

    It 'includes them on request' {
        @(Get-PtLongRunningQuery -ServerInstance 'SQLPROD01' -IncludeMaintenance).Count | Should -Be 3
    }

    It 'converts CPU to seconds and shows the blocker only when there is one' {
        $result = @(Get-PtLongRunningQuery -ServerInstance 'SQLPROD01')
        $result[0].CpuSeconds | Should -Be 45
        $result[0].BlockedBy | Should -BeNullOrEmpty
        $result[1].BlockedBy | Should -Be 55
    }

    It 'puts the minimum into the query' {
        Get-PtLongRunningQuery -ServerInstance 'SQLPROD01' -MinimumSeconds 120 | Out-Null
        Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -match '>= 120' }
    }
}
