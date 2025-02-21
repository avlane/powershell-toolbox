#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtRebootHistory' {
    BeforeAll {
        Mock Get-WinEvent -ModuleName PowerShellToolbox {
            function Props($values) { @($values | ForEach-Object { [pscustomobject]@{ Value = $_ } }) }
            @(
                [pscustomobject]@{ Id = 6005; TimeCreated = [datetime]'2025-02-20 03:07:10'; Properties = (Props @()) },
                [pscustomobject]@{ Id = 1074; TimeCreated = [datetime]'2025-02-20 03:05:00'; Properties = (Props @('C:\Windows\system32\svchost.exe (SQLPROD01)', 'SQLPROD01', 'Operating System: Recovery (Planned)', '0x80020002', 'restart', 'Windows Update', 'NT AUTHORITY\SYSTEM')) },
                [pscustomobject]@{ Id = 6008; TimeCreated = [datetime]'2025-02-10 08:01:00'; Properties = (Props @('8:00:30 AM', '2/10/2025')) },
                [pscustomobject]@{ Id = 41; TimeCreated = [datetime]'2025-02-10 08:00:55'; Properties = (Props @(209, 0, 0)) },
                [pscustomobject]@{ Id = 41; TimeCreated = [datetime]'2025-02-01 12:00:00'; Properties = (Props @(0, 0, 0)) }
            )
        }
        $history = @(Get-PtRebootHistory -ComputerName 'SQLPROD01')
    }

    It 'lists the events newest first with a label' {
        $history.Count | Should -Be 5
        $history[0].Kind | Should -Be 'Boot'
        $history[1].Kind | Should -Be 'Planned'
        $history[-1].Time | Should -Be ([datetime]'2025-02-01 12:00:00')
    }

    It 'shows who restarted the computer, why and with which program' {
        $planned = $history | Where-Object Kind -eq 'Planned'
        $planned.User | Should -Be 'NT AUTHORITY\SYSTEM'
        $planned.Reason | Should -Be 'Operating System: Recovery (Planned)'
        $planned.Process | Should -Match 'svchost'
        $planned.Detail | Should -Be 'Windows Update'
    }

    It 'shows the bugcheck code of a crash, if there was one' {
        $crashes = @($history | Where-Object Kind -eq 'Crash')
        $crashes[0].Detail | Should -Be 'Bugcheck code 0xD1'
        $crashes[1].Detail | Should -Be ''
    }

    It 'asks only for the unexpected events with -OnlyUnexpected' {
        Get-PtRebootHistory -ComputerName 'SQLPROD01' -OnlyUnexpected | Out-Null
        Should -Invoke Get-WinEvent -ModuleName PowerShellToolbox -ParameterFilter { ($FilterHashtable.Id -join ',') -eq '6008,41' }
    }

    It 'stays quiet when there were no restarts' {
        Mock Get-WinEvent -ModuleName PowerShellToolbox {
            $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList (
                (New-Object -TypeName System.Exception -ArgumentList 'No events were found.'),
                'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $null)
            throw $record
        }
        $result = Get-PtRebootHistory -ComputerName 'SQLPROD01' -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $warnings | Should -BeNullOrEmpty
    }
}
