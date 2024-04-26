#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtLinearSlope' {
    It 'finds the slope of a straight line' {
        $slope = InModuleScope PowerShellToolbox { Get-PtLinearSlope -X 0, 1, 2, 3 -Y 10, 12, 14, 16 }
        $slope | Should -Be 2
    }

    It 'fits a line through noisy points' {
        $slope = InModuleScope PowerShellToolbox { Get-PtLinearSlope -X 0, 1, 2, 3, 4 -Y 0, 1, 1, 2, 2 }
        [math]::Round($slope, 3) | Should -Be 0.5
    }

    It 'is zero for a flat series and negative for a shrinking one' {
        (InModuleScope PowerShellToolbox { Get-PtLinearSlope -X 0, 1, 2 -Y 5, 5, 5 }) | Should -Be 0
        (InModuleScope PowerShellToolbox { Get-PtLinearSlope -X 0, 1, 2 -Y 9, 6, 3 }) | Should -Be -3
    }

    It 'returns nothing without a usable line' {
        (InModuleScope PowerShellToolbox { Get-PtLinearSlope -X 1 -Y 1 }) | Should -BeNullOrEmpty
        (InModuleScope PowerShellToolbox { Get-PtLinearSlope -X 2, 2, 2 -Y 1, 2, 3 }) | Should -BeNullOrEmpty
    }
}

Describe 'Get-PtDatabaseGrowth' {
    BeforeAll {
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
            $start = [datetime]'2024-01-01'
            $rows = @()
            foreach ($day in 0..9) {
                $rows += [pscustomobject]@{ DatabaseName = 'Sales'; BackupDate = $start.AddDays($day); SizeMB = 1000.0 + 10 * $day }
                $rows += [pscustomobject]@{ DatabaseName = 'Flat'; BackupDate = $start.AddDays($day); SizeMB = 500.0 }
            }
            $rows += [pscustomobject]@{ DatabaseName = 'New'; BackupDate = $start.AddDays(8); SizeMB = 20.0 }
            $rows += [pscustomobject]@{ DatabaseName = 'New'; BackupDate = $start.AddDays(9); SizeMB = 25.0 }
            $rows
        }
        $growth = @(Get-PtDatabaseGrowth -ServerInstance 'SQLPROD01')
    }

    It 'estimates MB per day and percent per 30 days' {
        $sales = $growth | Where-Object DatabaseName -eq 'Sales'
        $sales.GrowthMBPerDay | Should -Be 10
        $sales.FirstSizeMB | Should -Be 1000
        $sales.LastSizeMB | Should -Be 1090
        $sales.GrowthPercentPer30Days | Should -Be 27.5
        $sales.Samples | Should -Be 10
    }

    It 'reports a flat database as zero growth' {
        ($growth | Where-Object DatabaseName -eq 'Flat').GrowthMBPerDay | Should -Be 0
    }

    It 'does not guess with fewer than three days of data' {
        $new = $growth | Where-Object DatabaseName -eq 'New'
        $new.Status | Should -Be 'NotEnoughData'
        $new.GrowthMBPerDay | Should -BeNullOrEmpty
    }

    It 'can be limited to some databases' {
        @(Get-PtDatabaseGrowth -ServerInstance 'SQLPROD01' -Database 'Flat').Count | Should -Be 1
    }
}
