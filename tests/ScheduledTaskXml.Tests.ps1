#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. The ScheduledTasks cmdlets exist only on Windows, so the whole
# file is skipped elsewhere. Files go into TestDrive.

BeforeDiscovery {
    $onWindows = $IsWindows
}

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Export-PtScheduledTask and Import-PtScheduledTask' -Skip:(-not $onWindows) {
    BeforeAll {
        Mock Get-ScheduledTask -ModuleName PowerShellToolbox -ParameterFilter { $TaskPath -eq '\*' } {
            @(
                [pscustomobject]@{ TaskName = 'Nightly'; TaskPath = '\Ops\' },
                [pscustomobject]@{ TaskName = 'Weekly report'; TaskPath = '\Ops\Reports\' },
                [pscustomobject]@{ TaskName = 'Top level'; TaskPath = '\' },
                [pscustomobject]@{ TaskName = 'Update'; TaskPath = '\Microsoft\Windows\WindowsUpdate\' }
            )
        }
        Mock Export-ScheduledTask -ModuleName PowerShellToolbox { "<Task><!-- $TaskPath$TaskName --></Task>" }
    }

    BeforeEach {
        $target = Join-Path $TestDrive 'export'
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    }

    It 'writes a folder tree that mirrors the task path' {
        $result = @(Export-PtScheduledTask -Path $target)
        $result.Count | Should -Be 3
        Test-Path (Join-Path (Join-Path $target 'Ops') 'Nightly.xml') | Should -Be $true
        Test-Path (Join-Path (Join-Path (Join-Path $target 'Ops') 'Reports') 'Weekly report.xml') | Should -Be $true
        Test-Path (Join-Path $target 'Top level.xml') | Should -Be $true
    }

    It 'skips the Microsoft tasks unless asked' {
        (Export-PtScheduledTask -Path $target).TaskName | Should -Not -Contain 'Update'
        @(Export-PtScheduledTask -Path $target -IncludeMicrosoft -Force).Count | Should -Be 4
    }

    It 'does not overwrite without -Force' {
        Export-PtScheduledTask -Path $target | Out-Null
        $again = @(Export-PtScheduledTask -Path $target)
        ($again | Where-Object Status -eq 'SkippedExists').Count | Should -Be 3
    }

    It 'writes nothing with -WhatIf' {
        Export-PtScheduledTask -Path $target -WhatIf | Out-Null
        Test-Path $target | Should -Be $false
    }

    It 'registers the exported files under the right task paths' {
        Export-PtScheduledTask -Path $target | Out-Null
        Mock Get-ScheduledTask -ModuleName PowerShellToolbox -ParameterFilter { $TaskPath -ne '\*' } { $null }
        Mock Register-ScheduledTask -ModuleName PowerShellToolbox { }

        $result = @(Import-PtScheduledTask -Path $target -Confirm:$false)
        $result.Count | Should -Be 3
        @($result | Where-Object Status -eq 'Registered').Count | Should -Be 3
        Should -Invoke Register-ScheduledTask -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $TaskPath -eq '\Ops\Reports\' -and $TaskName -eq 'Weekly report' -and $Xml -match 'Weekly report'
        }
        Should -Invoke Register-ScheduledTask -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $TaskPath -eq '\' -and $TaskName -eq 'Top level' }
    }

    It 'leaves existing tasks alone unless -Force is given' {
        Export-PtScheduledTask -Path $target | Out-Null
        Mock Get-ScheduledTask -ModuleName PowerShellToolbox -ParameterFilter { $TaskPath -ne '\*' } { [pscustomobject]@{ TaskName = 'exists' } }
        Mock Register-ScheduledTask -ModuleName PowerShellToolbox { }

        @(Import-PtScheduledTask -Path $target -Confirm:$false | Where-Object Status -eq 'SkippedExists').Count | Should -Be 3
        Should -Invoke Register-ScheduledTask -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'passes a credential on' {
        Export-PtScheduledTask -Path $target | Out-Null
        Mock Get-ScheduledTask -ModuleName PowerShellToolbox -ParameterFilter { $TaskPath -ne '\*' } { $null }
        Mock Register-ScheduledTask -ModuleName PowerShellToolbox { }
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'CORP\svc-tasks', (ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force)

        Import-PtScheduledTask -Path $target -Credential $credential -Confirm:$false | Out-Null
        Should -Invoke Register-ScheduledTask -ModuleName PowerShellToolbox -Times 3 -Exactly -ParameterFilter { $User -eq 'CORP\svc-tasks' -and $Password -eq 'not-a-real-password' }
    }
}
