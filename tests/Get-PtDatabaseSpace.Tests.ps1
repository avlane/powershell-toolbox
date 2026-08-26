#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtDatabaseSpace' {
    BeforeAll {
        Mock Invoke-PtSqlQuery -ModuleName PowerShellToolbox {
            function File($db, $name, $type, $sizeMb, $maxPages, $growth, $percent, $volume, $freeMb, $totalMb) {
                [pscustomobject]@{
                    DatabaseName = $db; LogicalName = $name; FileType = $type; PhysicalName = "$volume$name"; SizeMB = $sizeMb
                    MaxSizePages = $maxPages; Growth = $growth; IsPercentGrowth = $percent
                    Volume = $volume; VolumeFreeMB = $freeMb; VolumeTotalMB = $totalMb
                }
            }
            @(
                (File 'Sales' 'Sales' 'ROWS' 51200 -1 8192 $false 'E:\' 300000 500000),
                (File 'Sales' 'Sales_log' 'LOG' 8192 268435456 10 $true 'F:\' 100000 200000),
                (File 'Small' 'Small' 'ROWS' 100 -1 128 $false 'E:\' 300000 500000),
                (File 'Full' 'Full' 'ROWS' 2000 1048576 0 $false 'G:\' 5000 100000),
                (File 'Odd' 'Odd' 'ROWS' 10 -1 8192 $false 'H:\' 10 0)
            )
        }
        $space = @(Get-PtDatabaseSpace -ServerInstance 'SQLPROD01')
        function Get-File($logical) { $space | Where-Object LogicalName -eq $logical }
    }

    It 'describes growth in MB, percent or fixed size' {
        (Get-File 'Sales').Growth | Should -Be '64 MB'
        (Get-File 'Sales_log').Growth | Should -Be '10 percent'
        (Get-File 'Full').Growth | Should -Be 'fixed size'
    }

    It 'describes the maximum size' {
        (Get-File 'Sales').MaxSize | Should -Be 'unlimited'
        (Get-File 'Sales_log').MaxSize | Should -Be 'unlimited'
        (Get-File 'Full').MaxSize | Should -Be '8192 MB'
    }

    It 'works out the free percentage of the volume' {
        (Get-File 'Sales').VolumeFreePercent | Should -Be 60
        (Get-File 'Full').VolumeFreePercent | Should -Be 5
        (Get-File 'Odd').VolumeFreePercent | Should -BeNullOrEmpty
    }

    It 'flags a nearly full volume' {
        (Get-File 'Full').Status | Should -Be 'LowVolume'
    }

    It 'flags percentage growth and growth in tiny steps' {
        (Get-File 'Sales_log').Status | Should -Be 'BadGrowth'
        (Get-File 'Small').Status | Should -Be 'BadGrowth'
    }

    It 'calls a sensible file OK' {
        (Get-File 'Sales').Status | Should -Be 'OK'
    }

    It 'copes with a volume without a size' {
        (Get-File 'Odd').Status | Should -Be 'OK'
    }

    It 'can be limited to some databases' {
        @(Get-PtDatabaseSpace -ServerInstance 'SQLPROD01' -Database 'Small').Count | Should -Be 1
    }

    It 'uses the low-volume limit it is given' {
        (Get-PtDatabaseSpace -ServerInstance 'SQLPROD01' -LowVolumePercent 70 | Where-Object LogicalName -eq 'Sales').Status | Should -Be 'LowVolume'
    }
}
