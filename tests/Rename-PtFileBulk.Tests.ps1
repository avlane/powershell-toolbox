#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Everything happens inside TestDrive.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Rename-PtFileBulk' {
    BeforeEach {
        $folder = Join-Path $TestDrive 'scans'
        if (Test-Path $folder) { Remove-Item $folder -Recurse -Force }
        New-Item -ItemType Directory -Path (Join-Path $folder 'sub') | Out-Null
        foreach ($name in 'IMG_001.jpeg', 'IMG_002.jpeg', 'notes.txt') {
            Set-Content -LiteralPath (Join-Path $folder $name) -Value $name
        }
        Set-Content -LiteralPath (Join-Path (Join-Path $folder 'sub') 'IMG_003.jpeg') -Value 'deep'
    }

    It 'renames with capture groups' {
        $result = @(Rename-PtFileBulk -Path $folder -Pattern '^IMG_(\d+)\.jpeg$' -Replacement 'scan-$1.jpg' -Confirm:$false)
        ($result | Where-Object Status -eq 'Renamed').Count | Should -Be 2
        Test-Path (Join-Path $folder 'scan-001.jpg') | Should -Be $true
        Test-Path (Join-Path $folder 'IMG_001.jpeg') | Should -Be $false
    }

    It 'reports files that do not match as Unchanged and leaves them alone' {
        $result = @(Rename-PtFileBulk -Path $folder -Pattern '^IMG_(\d+)\.jpeg$' -Replacement 'scan-$1.jpg' -Confirm:$false)
        ($result | Where-Object OldName -eq 'notes.txt').Status | Should -Be 'Unchanged'
        Test-Path (Join-Path $folder 'notes.txt') | Should -Be $true
    }

    It 'stays in the top folder unless -Recurse is given' {
        Rename-PtFileBulk -Path $folder -Pattern 'IMG_' -Replacement 'pic_' -Confirm:$false | Out-Null
        Test-Path (Join-Path (Join-Path $folder 'sub') 'IMG_003.jpeg') | Should -Be $true
        Rename-PtFileBulk -Path $folder -Pattern 'IMG_' -Replacement 'pic_' -Recurse -Confirm:$false | Out-Null
        Test-Path (Join-Path (Join-Path $folder 'sub') 'pic_003.jpeg') | Should -Be $true
    }

    It 'changes nothing with -WhatIf' {
        $result = @(Rename-PtFileBulk -Path $folder -Pattern 'IMG_' -Replacement 'pic_' -WhatIf)
        ($result | Where-Object Status -eq 'Renamed').Count | Should -Be 0
        Test-Path (Join-Path $folder 'IMG_001.jpeg') | Should -Be $true
    }

    It 'does not rename two files to the same name' {
        $result = @(Rename-PtFileBulk -Path $folder -Pattern '\d+' -Replacement 'X' -Filter 'IMG_*' -Confirm:$false)
        ($result | Where-Object Status -eq 'Collision').Count | Should -Be 2
        Test-Path (Join-Path $folder 'IMG_001.jpeg') | Should -Be $true
        Test-Path (Join-Path $folder 'IMG_002.jpeg') | Should -Be $true
    }

    It 'does not overwrite a file that already has the new name' {
        $result = @(Rename-PtFileBulk -Path $folder -Pattern '^IMG_001\.jpeg$' -Replacement 'notes.txt' -Confirm:$false)
        ($result | Where-Object OldName -eq 'IMG_001.jpeg').Status | Should -Be 'Collision'
        Get-Content -LiteralPath (Join-Path $folder 'notes.txt') | Should -Be 'notes.txt'
    }

    It 'rejects names with characters Windows does not allow' {
        $result = @(Rename-PtFileBulk -Path $folder -Pattern '^notes\.txt$' -Replacement 'a?b.txt' -Confirm:$false)
        $result[0].Status | Should -Be 'Failed'
        Test-Path (Join-Path $folder 'notes.txt') | Should -Be $true
    }

    It 'is case-insensitive unless told otherwise' {
        @(Rename-PtFileBulk -Path $folder -Pattern '^img_001' -Replacement 'a' -Confirm:$false | Where-Object Status -eq 'Renamed').Count | Should -Be 1
        @(Rename-PtFileBulk -Path $folder -Pattern '^img_002' -Replacement 'b' -CaseSensitive -Confirm:$false | Where-Object Status -eq 'Renamed').Count | Should -Be 0
    }

    It 'explains an invalid pattern' {
        { Rename-PtFileBulk -Path $folder -Pattern '([unclosed' -Replacement 'x' -Confirm:$false } | Should -Throw '*not a valid regular expression*'
    }
}
