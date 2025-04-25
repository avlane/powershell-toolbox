#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. robocopy itself is never started: Invoke-PtRobocopy is mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'ConvertFrom-PtRobocopyExitCode' {
    It 'explains the exit code <Code>' -ForEach @(
        @{ Code = 0; Succeeded = $true; Text = 'already in sync' },
        @{ Code = 1; Succeeded = $true; Text = 'Files were copied' },
        @{ Code = 3; Succeeded = $true; Text = 'extra files' },
        @{ Code = 5; Succeeded = $true; Text = 'mismatched' },
        @{ Code = 9; Succeeded = $false; Text = 'could not be copied' },
        @{ Code = 16; Succeeded = $false; Text = 'Serious error' }
    ) {
        $result = InModuleScope PowerShellToolbox -Parameters @{ Code = $Code } { ConvertFrom-PtRobocopyExitCode -ExitCode $Code }
        $result.Succeeded | Should -Be $Succeeded
        ($result.Meaning -join ' ') | Should -Match $Text
    }

    It 'lists every bit that is set' {
        $result = InModuleScope PowerShellToolbox { ConvertFrom-PtRobocopyExitCode -ExitCode 7 }
        $result.Meaning.Count | Should -Be 3
    }
}

Describe 'ConvertFrom-PtRobocopySummary' {
    It 'reads the Dirs and Files rows' {
        $summary = InModuleScope PowerShellToolbox {
            ConvertFrom-PtRobocopySummary -Output @(
                '------------------------------------------------------------------------------',
                '               Total    Copied   Skipped  Mismatch    FAILED    Extras',
                '    Dirs :         5         1         4         0         0         0',
                '   Files :        20         3        16         0         1         2',
                '   Bytes :   1.2 m   300 k   0.9 m         0         0         0'
            )
        }
        $summary.FilesCopied | Should -Be 3
        $summary.FilesSkipped | Should -Be 16
        $summary.FilesFailed | Should -Be 1
        $summary.FilesExtra | Should -Be 2
        $summary.DirsCopied | Should -Be 1
    }

    It 'gives empty counters when there is no table' {
        $summary = InModuleScope PowerShellToolbox { ConvertFrom-PtRobocopySummary -Output @('ERROR : something went wrong') }
        $summary.FilesCopied | Should -BeNullOrEmpty
        $summary.DirsCopied | Should -BeNullOrEmpty
    }
}

Describe 'Sync-PtFolder' {
    BeforeAll {
        $source = Join-Path $TestDrive 'source'
        $target = Join-Path $TestDrive 'target'
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'a.txt') -Value 'a'
    }

    BeforeEach {
        Mock Invoke-PtRobocopy -ModuleName PowerShellToolbox {
            [pscustomobject]@{ ExitCode = 1; Output = @('   Dirs :         1         0         1         0         0         0', '   Files :         1         1         0         0         0         0') }
        }
    }

    It 'copies without deleting by default' {
        $result = Sync-PtFolder -Source $source -Destination $target -Confirm:$false
        $result.Succeeded | Should -Be $true
        $result.FilesCopied | Should -Be 1
        $result.Meaning | Should -Be 'Files were copied.'
        $result.ListOnly | Should -Be $false
        Should -Invoke Invoke-PtRobocopy -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Argument -contains '/E' -and $Argument -notcontains '/MIR' -and $Argument -notcontains '/L' -and $Argument -contains '/MT:8'
        }
    }

    It 'mirrors only when asked to' {
        Sync-PtFolder -Source $source -Destination $target -Mirror -Confirm:$false | Out-Null
        Should -Invoke Invoke-PtRobocopy -ModuleName PowerShellToolbox -ParameterFilter { $Argument -contains '/MIR' -and $Argument -notcontains '/E' }
    }

    It 'only lists what it would do with -WhatIf' {
        $result = Sync-PtFolder -Source $source -Destination $target -WhatIf
        $result.ListOnly | Should -Be $true
        Should -Invoke Invoke-PtRobocopy -ModuleName PowerShellToolbox -ParameterFilter { $Argument -contains '/L' }
    }

    It 'passes exclusions and the log path on' {
        Sync-PtFolder -Source $source -Destination $target -ExcludeFile '*.tmp', '*.bak' -ExcludeDirectory 'cache' -LogPath (Join-Path $TestDrive 'sync.log') -Confirm:$false | Out-Null
        Should -Invoke Invoke-PtRobocopy -ModuleName PowerShellToolbox -ParameterFilter {
            ($Argument -join ' ') -match '/XF \*\.tmp \*\.bak' -and ($Argument -join ' ') -match '/XD cache' -and ($Argument -join ' ') -match '/LOG\+:'
        }
    }

    It 'reports a failed run' {
        Mock Invoke-PtRobocopy -ModuleName PowerShellToolbox { [pscustomobject]@{ ExitCode = 9; Output = @('ERROR : access denied') } }
        $result = Sync-PtFolder -Source $source -Destination $target -Confirm:$false
        $result.Succeeded | Should -Be $false
        $result.Meaning | Should -Match 'could not be copied'
    }

    It 'refuses nonsense' {
        { Sync-PtFolder -Source (Join-Path $TestDrive 'missing') -Destination $target -Confirm:$false } | Should -Throw '*does not exist*'
        { Sync-PtFolder -Source $source -Destination $source -Confirm:$false } | Should -Throw '*same folder*'
        { Sync-PtFolder -Source $source -Destination (Join-Path $source 'inside') -Confirm:$false } | Should -Throw '*inside the source*'
    }

    It 'will not mirror an empty source or onto a drive root' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Sync-PtFolder -Source $empty -Destination $target -Mirror -Confirm:$false } | Should -Throw '*is empty*'
        { Sync-PtFolder -Source $source -Destination ([System.IO.Path]::GetPathRoot($source)) -Mirror -Confirm:$false } | Should -Throw '*root of a drive*'
        Should -Invoke Invoke-PtRobocopy -ModuleName PowerShellToolbox -Times 0 -Exactly
    }
}
