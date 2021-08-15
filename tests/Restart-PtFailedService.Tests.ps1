#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. CIM is mocked, so no service is touched.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Restart-PtFailedService' {
    BeforeEach {
        $global:PtTestQueries = 0
        Mock Start-Sleep -ModuleName PowerShellToolbox { }
    }

    AfterAll {
        Remove-Variable -Name PtTestQueries -Scope Global -ErrorAction SilentlyContinue
    }

    It 'starts a stopped service and waits for Running' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox {
            $global:PtTestQueries++
            if ($global:PtTestQueries -le 1) { [pscustomobject]@{ Name = 'SQLSERVERAGENT'; State = 'Stopped' } }
            else { [pscustomobject]@{ Name = 'SQLSERVERAGENT'; State = 'Running' } }
        }
        Mock Invoke-CimMethod -ModuleName PowerShellToolbox { [pscustomobject]@{ ReturnValue = 0 } }

        $result = Restart-PtFailedService -Name 'SQLSERVERAGENT' -ComputerName 'SQLPROD01' -Confirm:$false
        $result.Result | Should -Be 'Started'
        $result.State | Should -Be 'Running'
        Should -Invoke Invoke-CimMethod -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $MethodName -eq 'StartService' }
    }

    It 'does not touch a service that is already running' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'Spooler'; State = 'Running' } }
        Mock Invoke-CimMethod -ModuleName PowerShellToolbox { }
        (Restart-PtFailedService -Name 'Spooler' -Confirm:$false).Result | Should -Be 'AlreadyRunning'
        Should -Invoke Invoke-CimMethod -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'reports a service that does not exist' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { $null }
        Mock Invoke-CimMethod -ModuleName PowerShellToolbox { }
        $result = Restart-PtFailedService -Name 'NoSuchService' -Confirm:$false
        $result.Result | Should -Be 'NotFound'
        $result.Detail | Should -Match 'NoSuchService'
    }

    It 'reports a StartService error code' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'Broken'; State = 'Stopped' } }
        Mock Invoke-CimMethod -ModuleName PowerShellToolbox { [pscustomobject]@{ ReturnValue = 14 } }
        $result = Restart-PtFailedService -Name 'Broken' -Confirm:$false
        $result.Result | Should -Be 'Failed'
        $result.Detail | Should -Match 'code 14'
    }

    It 'gives up when the service never reaches Running' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'Slow'; State = 'StartPending' } }
        Mock Invoke-CimMethod -ModuleName PowerShellToolbox { [pscustomobject]@{ ReturnValue = 0 } }
        $result = Restart-PtFailedService -Name 'Slow' -TimeoutSeconds 1 -Confirm:$false
        $result.Result | Should -Be 'Failed'
        $result.Detail | Should -Match 'still StartPending'
    }

    It 'starts nothing with -WhatIf' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'SQLSERVERAGENT'; State = 'Stopped' } }
        Mock Invoke-CimMethod -ModuleName PowerShellToolbox { }
        Restart-PtFailedService -Name 'SQLSERVERAGENT' -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Invoke-CimMethod -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'refuses wildcards in the name' {
        { Restart-PtFailedService -Name 'SQL*' -Confirm:$false } | Should -Throw
    }

    It 'quotes a single quote in the name for the WQL filter' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { $null }
        Restart-PtFailedService -Name "odd'name" -Confirm:$false | Out-Null
        Should -Invoke Get-CimInstance -ModuleName PowerShellToolbox -ParameterFilter { $Filter -eq "Name = 'odd''name'" }
    }

    It 'takes service and computer from Get-PtServiceTriage output' {
        Mock Get-CimInstance -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'Spooler'; State = 'Running' } }
        $triage = [pscustomobject]@{ ComputerName = 'SQLPROD02'; Name = 'Spooler' }
        ($triage | Restart-PtFailedService -Confirm:$false).ComputerName | Should -Be 'SQLPROD02'
    }
}
