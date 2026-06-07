#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. The ScheduledTasks cmdlets exist only on Windows, so the whole
# file is skipped elsewhere.

BeforeDiscovery {
    $onWindows = $IsWindows
}

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtScheduledTaskReport' -Tag 'Windows' -Skip:(-not $onWindows) {
    BeforeAll {
        Mock Get-ScheduledTask -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ TaskName = 'Nightly'; TaskPath = '\Ops\'; State = 'Ready'; Principal = [pscustomobject]@{ UserId = 'SYSTEM' }; Actions = @([pscustomobject]@{ Execute = 'powershell.exe'; Arguments = '-File C:\job.ps1' }) },
                [pscustomobject]@{ TaskName = 'Broken'; TaskPath = '\Ops\'; State = 'Ready'; Principal = [pscustomobject]@{ UserId = 'svc-sql' }; Actions = @() },
                [pscustomobject]@{ TaskName = 'Fresh'; TaskPath = '\Ops\'; State = 'Ready'; Principal = [pscustomobject]@{ UserId = 'SYSTEM' }; Actions = @() },
                [pscustomobject]@{ TaskName = 'Off'; TaskPath = '\Ops\'; State = 'Disabled'; Principal = [pscustomobject]@{ UserId = 'SYSTEM' }; Actions = @() },
                [pscustomobject]@{ TaskName = 'Missed'; TaskPath = '\Ops\'; State = 'Ready'; Principal = [pscustomobject]@{ UserId = 'SYSTEM' }; Actions = @() },
                [pscustomobject]@{ TaskName = 'Update'; TaskPath = '\Microsoft\Windows\WindowsUpdate\'; State = 'Ready'; Principal = [pscustomobject]@{ UserId = 'SYSTEM' }; Actions = @() }
            )
        }
        Mock Get-ScheduledTaskInfo -ModuleName PowerShellToolbox {
            $results = @{ Nightly = 0; Broken = 1; Fresh = 267011; Off = 0; Missed = 0; Update = 0 }
            $next = (Get-Date).AddHours(12)
            if ($TaskName -eq 'Missed') { $next = (Get-Date).AddHours(-30) }
            [pscustomobject]@{ LastTaskResult = $results[$TaskName]; LastRunTime = [datetime]'2020-04-01 03:00:00'; NextRunTime = $next }
        }
    }

    It 'leaves out the Microsoft tasks by default' {
        $report = @(Get-PtScheduledTaskReport)
        $report.Count | Should -Be 5
        $report.TaskName | Should -Not -Contain 'Update'
    }

    It 'includes them on request' {
        @(Get-PtScheduledTaskReport -IncludeMicrosoft).Count | Should -Be 6
    }

    It 'derives a status from the state and the last result' {
        $report = @(Get-PtScheduledTaskReport)
        ($report | Where-Object TaskName -eq 'Nightly').Status | Should -Be 'OK'
        ($report | Where-Object TaskName -eq 'Broken').Status | Should -Be 'Failed'
        ($report | Where-Object TaskName -eq 'Broken').LastResult | Should -Be '0x1'
        ($report | Where-Object TaskName -eq 'Fresh').Status | Should -Be 'NeverRun'
        ($report | Where-Object TaskName -eq 'Off').Status | Should -Be 'Disabled'
        ($report | Where-Object TaskName -eq 'Missed').Status | Should -Be 'Overdue'
    }

    It 'can be told how late is too late' {
        $report = @(Get-PtScheduledTaskReport -OverdueHours 48)
        ($report | Where-Object TaskName -eq 'Missed').Status | Should -Be 'OK'
    }

    It 'shows the command line' {
        (Get-PtScheduledTaskReport | Where-Object TaskName -eq 'Nightly').Command | Should -Be 'powershell.exe -File C:\job.ps1'
    }

    It 'can show only problems' {
        $report = @(Get-PtScheduledTaskReport -OnlyProblems)
        @($report.TaskName | Sort-Object) -join ',' | Should -Be 'Broken,Fresh,Missed'
    }
}
