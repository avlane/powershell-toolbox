#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. The msdb history is mocked; the numbers are log sequence numbers.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force

    Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
        function Row($db, $model, $type, $copyOnly, $hour, $first, $last) {
            $start = ([datetime]'2023-03-26 00:00:00').AddHours($hour)
            [pscustomobject]@{
                DatabaseName = $db; RecoveryModel = $model; BackupType = $type; IsCopyOnly = $copyOnly
                BackupStart = $start; BackupFinish = $start.AddMinutes(5); FirstLsn = [decimal]$first; LastLsn = [decimal]$last
            }
        }
        @(
            (Row 'Intact' 'FULL' 'D' $false 1 1000 1100),
            (Row 'Intact' 'FULL' 'L' $false 2 1090 1200),
            (Row 'Intact' 'FULL' 'L' $false 3 1200 1300),
            (Row 'Intact' 'FULL' 'L' $false 4 1300 1400),

            (Row 'Gap' 'FULL' 'D' $false 1 1000 1100),
            (Row 'Gap' 'FULL' 'L' $false 2 1100 1200),
            (Row 'Gap' 'FULL' 'L' $false 4 1300 1400),

            (Row 'LateStart' 'FULL' 'D' $false 1 1000 1100),
            (Row 'LateStart' 'FULL' 'L' $false 2 1500 1600),

            (Row 'NoFull' 'FULL' 'L' $false 2 1100 1200),

            (Row 'Simple' 'SIMPLE' 'D' $false 1 1000 1100),

            (Row 'CopyOnly' 'FULL' 'D' $false 1 1000 1100),
            (Row 'CopyOnly' 'FULL' 'D' $true 3 1150 1250),
            (Row 'CopyOnly' 'FULL' 'L' $false 5 1100 1200),

            (Row 'NoLogs' 'FULL' 'D' $false 1 1000 1100),

            (Row 'Rolled' 'FULL' 'L' $false 0 800 900),
            (Row 'Rolled' 'FULL' 'D' $false 1 1000 1100),
            (Row 'Rolled' 'FULL' 'L' $false 2 1000 1250)
        )
    }
}

Describe 'Get-PtBackupChain' {
    BeforeAll {
        $chains = @(Get-PtBackupChain -ServerInstance 'SQLPROD01')
        function Get-Chain($name) { $chains | Where-Object DatabaseName -eq $name }
    }

    It 'skips databases in the simple recovery model' {
        Get-Chain 'Simple' | Should -BeNullOrEmpty
    }

    It 'accepts a chain where each log backup starts where the last one ended' {
        $chain = Get-Chain 'Intact'
        $chain.ChainIntact | Should -Be $true
        $chain.LogBackups | Should -Be 3
        $chain.GapAfter | Should -BeNullOrEmpty
    }

    It 'finds a gap in the middle and says when it starts' {
        $chain = Get-Chain 'Gap'
        $chain.ChainIntact | Should -Be $false
        $chain.GapAfter | Should -Be ([datetime]'2023-03-26 02:05:00')
        $chain.Detail | Should -Match 'missing'
    }

    It 'finds a first log backup that starts too late' {
        $chain = Get-Chain 'LateStart'
        $chain.ChainIntact | Should -Be $false
        $chain.GapAfter | Should -Be ([datetime]'2023-03-26 01:05:00')
        $chain.Detail | Should -Match 'too late'
    }

    It 'reports a database without a full backup' {
        $chain = Get-Chain 'NoFull'
        $chain.ChainIntact | Should -Be $false
        $chain.Detail | Should -Match 'No full backup'
    }

    It 'does not let a copy-only full backup start a chain' {
        $chain = Get-Chain 'CopyOnly'
        $chain.ChainIntact | Should -Be $true
        $chain.LastFull | Should -Be ([datetime]'2023-03-26 01:05:00')
    }

    It 'reports a full backup with no log backups after it' {
        $chain = Get-Chain 'NoLogs'
        $chain.ChainIntact | Should -Be $false
        $chain.Detail | Should -Match 'No log backup'
    }

    It 'ignores log backups from before the last full backup' {
        $chain = Get-Chain 'Rolled'
        $chain.LogBackups | Should -Be 1
        $chain.ChainIntact | Should -Be $true
    }

    It 'can show only the problems' {
        $problems = @(Get-PtBackupChain -ServerInstance 'SQLPROD01' -OnlyProblems)
        @($problems.DatabaseName | Sort-Object) -join ',' | Should -Be 'Gap,LateStart,NoFull,NoLogs'
    }
}
