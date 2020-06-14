#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Uses TestDrive, so nothing outside the temporary folder is touched.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force

    function New-TestFile {
        param([string]$Path, [int]$AgeDays)
        Set-Content -LiteralPath $Path -Value 'x'
        (Get-Item -LiteralPath $Path).LastWriteTime = (Get-Date).AddDays(-$AgeDays)
    }
}

Describe 'Remove-PtOldFile' {
    BeforeEach {
        $folder = Join-Path $TestDrive 'backups'
        if (Test-Path $folder) { Remove-Item $folder -Recurse -Force }
        New-Item -ItemType Directory -Path (Join-Path $folder 'sub') | Out-Null
        New-TestFile (Join-Path $folder 'old.bak') 40
        New-TestFile (Join-Path $folder 'new.bak') 2
        New-TestFile (Join-Path $folder 'old.txt') 40
        New-TestFile (Join-Path (Join-Path $folder 'sub') 'deep-old.bak') 60
    }

    It 'deletes only old files that match the filter' {
        $result = @(Remove-PtOldFile -Path $folder -Filter '*.bak' -OlderThanDays 30 -Confirm:$false)
        $result.Count | Should -Be 1
        $result[0].Removed | Should -Be $true
        Test-Path (Join-Path $folder 'old.bak') | Should -Be $false
        Test-Path (Join-Path $folder 'new.bak') | Should -Be $true
        Test-Path (Join-Path $folder 'old.txt') | Should -Be $true
    }

    It 'leaves sub-folders alone unless -Recurse is given' {
        $deep = Join-Path (Join-Path $folder 'sub') 'deep-old.bak'
        Remove-PtOldFile -Path $folder -OlderThanDays 30 -Confirm:$false | Out-Null
        Test-Path $deep | Should -Be $true
        Remove-PtOldFile -Path $folder -OlderThanDays 30 -Recurse -Confirm:$false | Out-Null
        Test-Path $deep | Should -Be $false
    }

    It 'does not delete anything with -WhatIf' {
        $result = @(Remove-PtOldFile -Path $folder -OlderThanDays 30 -Recurse -WhatIf)
        $result.Count | Should -Be 3
        ($result | Where-Object Removed).Count | Should -Be 0
        Test-Path (Join-Path $folder 'old.bak') | Should -Be $true
    }

    It 'removes folders that end up empty when asked to' {
        Remove-PtOldFile -Path $folder -OlderThanDays 30 -Recurse -RemoveEmptyFolders -Confirm:$false | Out-Null
        Test-Path (Join-Path $folder 'sub') | Should -Be $false
        Test-Path $folder | Should -Be $true
    }

    It 'refuses the root of a drive' {
        $root = [System.IO.Path]::GetPathRoot($folder)
        { Remove-PtOldFile -Path $root -OlderThanDays 1 -Confirm:$false -ErrorAction Stop } | Should -Throw '*root of a drive*'
    }

    It 'reports a missing folder as an error' {
        { Remove-PtOldFile -Path (Join-Path $TestDrive 'nope') -OlderThanDays 1 -Confirm:$false -ErrorAction Stop } | Should -Throw '*does not exist*'
    }
}
