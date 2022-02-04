#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force

    $rows = @(
        [pscustomobject]@{ Name = 'a'; Status = 'OK' },
        [pscustomobject]@{ Name = 'b'; Status = 'OK' },
        [pscustomobject]@{ Name = 'c'; Status = 'Low' },
        [pscustomobject]@{ Name = 'd'; Status = 'Failed' }
    )
}

Describe 'Format-PtStatusSummary' {
    It 'counts rows per status, in order of first appearance' {
        ($rows | Format-PtStatusSummary -Color Never) | Should -Be 'OK: 2, Low: 1, Failed: 1 (4 total)'
    }

    It 'falls back to the Verdict property' {
        $verdicts = @([pscustomobject]@{ Verdict = 'Flaky' }, [pscustomobject]@{ Verdict = 'OK' })
        ($verdicts | Format-PtStatusSummary -Color Never) | Should -Be 'Flaky: 1, OK: 1 (2 total)'
    }

    It 'uses the property it is told to' {
        $custom = @([pscustomobject]@{ State = 'Running' }, [pscustomobject]@{ State = 'Stopped' }, [pscustomobject]@{ State = 'Running' })
        ($custom | Format-PtStatusSummary -Property State -Color Never) | Should -Be 'Running: 2, Stopped: 1 (3 total)'
    }

    It 'says so when there is nothing to count' {
        (@() | Format-PtStatusSummary -Color Never) | Should -Be 'No rows'
    }

    It 'never colours with -Color Never' {
        ($rows | Format-PtStatusSummary -Color Never) | Should -Not -Match ([string][char]27)
    }

    It 'colours with $PSStyle when asked to' {
        ($rows | Format-PtStatusSummary -Color Always) | Should -Match ([string][char]27)
    }
}

Describe 'Get-PtStatusSeverity' {
    It 'classifies the status words' -ForEach @(
        @{ Word = 'OK'; Severity = 'good' },
        @{ Word = 'Started'; Severity = 'good' },
        @{ Word = 'Low'; Severity = 'warn' },
        @{ Word = 'Stale'; Severity = 'warn' },
        @{ Word = 'Failed'; Severity = 'bad' },
        @{ Word = 'NoBackup'; Severity = 'bad' },
        @{ Word = 'Something else'; Severity = 'neutral' },
        @{ Word = ''; Severity = 'neutral' }
    ) {
        InModuleScope PowerShellToolbox -Parameters @{ Word = $Word } { Get-PtStatusSeverity -Status $Word } | Should -Be $Severity
    }
}
