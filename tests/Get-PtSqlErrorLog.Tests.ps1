#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtSqlErrorLog' {
    BeforeAll {
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
            function Row($time, $text) { [pscustomobject]@{ LogDate = [datetime]$time; ProcessInfo = 'Logon'; Text = $text } }
            @(
                (Row '2026-04-05 08:00:00' 'Error: 18456, Severity: 14, State: 8.'),
                (Row '2026-04-05 08:00:00' "Login failed for user 'CORP\svc-app'. Reason: Password did not match that for the login provided."),
                (Row '2026-04-05 07:00:00' 'Database backed up. Database: Sales, creation date(time): 2026/01/01(10:00:00), pages dumped: 1000'),
                (Row '2026-04-05 06:30:00' 'Login succeeded for user ''CORP\reporting''. Connection made using Windows Authentication.'),
                (Row '2026-04-05 06:00:00' 'Error: 823, Severity: 24, State: 2.'),
                (Row '2026-04-04 23:00:00' 'SQL Server is starting at normal priority base (=7).')
            )
        }
    }

    It 'removes routine messages by default' {
        $log = @(Get-PtSqlErrorLog -ServerInstance 'SQLPROD01')
        $log.Count | Should -Be 4
        ($log.Text -join '|') | Should -Not -Match 'Database backed up'
        ($log.Text -join '|') | Should -Not -Match 'Login succeeded'
    }

    It 'keeps them with -IncludeRoutine' {
        @(Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -IncludeRoutine).Count | Should -Be 6
    }

    It 'returns the newest entries first' {
        $log = @(Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -IncludeRoutine)
        $log[0].LogDate | Should -Be ([datetime]'2026-04-05 08:00:00')
        $log[-1].Text | Should -Match 'starting'
    }

    It 'splits the error header row into number, severity and state' {
        $errors = @(Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' | Where-Object ErrorNumber)
        $errors.Count | Should -Be 2
        ($errors | Where-Object ErrorNumber -eq 823).Severity | Should -Be 24
        ($errors | Where-Object ErrorNumber -eq 18456).State | Should -Be 8
    }

    It 'filters by time' {
        $log = @(Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -Since ([datetime]'2026-04-05 06:30:00') -Until ([datetime]'2026-04-05 08:00:00') -IncludeRoutine)
        $log.Count | Should -Be 1
        $log[0].Text | Should -Match 'Database backed up'
    }

    It 'limits the number of entries' {
        @(Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -First 2).Count | Should -Be 2
    }

    It 'builds the sp_readerrorlog call, escaping quotes in the search terms' {
        Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -LogNumber 2 -Search "it's", 'failed' | Out-Null
        Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter {
            $Query -eq "EXEC sys.sp_readerrorlog @p1 = 2, @p2 = 1, @p3 = N'it''s', @p4 = N'failed';"
        }
    }

    It 'reads the Agent log with -Agent' {
        Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -Agent | Out-Null
        Should -Invoke Invoke-PtSqlQuery -ModuleName PowerShellToolbox -ParameterFilter { $Query -eq 'EXEC sys.sp_readerrorlog @p1 = 0, @p2 = 2;' }
    }

    It 'accepts at most two search terms' {
        { Get-PtSqlErrorLog -ServerInstance 'SQLPROD01' -Search 'a', 'b', 'c' } | Should -Throw
    }
}
