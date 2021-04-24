#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Everything happens inside TestDrive.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Copy-PtFileSafe' {
    BeforeEach {
        $source = Join-Path $TestDrive 'source'
        $target = Join-Path $TestDrive 'target'
        foreach ($folder in $source, $target) {
            if (Test-Path $folder) { Remove-Item $folder -Recurse -Force }
        }
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'a.bak') -Value 'backup A'
        Set-Content -LiteralPath (Join-Path $source 'b.bak') -Value 'backup B'
    }

    It 'copies a file and creates the destination folder' {
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target
        $result.Status | Should -Be 'Copied'
        Get-Content -LiteralPath (Join-Path $target 'a.bak') | Should -Be 'backup A'
        Test-Path (Join-Path $source 'a.bak') | Should -Be $true
    }

    It 'returns the hash and size' {
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target
        $result.Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $source 'a.bak') -Algorithm SHA256).Hash
        $result.Bytes | Should -BeGreaterThan 0
    }

    It 'moves a file only after the copy was verified' {
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target -Move
        $result.Status | Should -Be 'Moved'
        Test-Path (Join-Path $source 'a.bak') | Should -Be $false
        Test-Path (Join-Path $target 'a.bak') | Should -Be $true
    }

    It 'accepts files from Get-ChildItem' {
        $results = @(Get-ChildItem -LiteralPath $source -Filter '*.bak' | Copy-PtFileSafe -Destination $target)
        $results.Count | Should -Be 2
        @(Get-ChildItem -LiteralPath $target).Count | Should -Be 2
    }

    It 'leaves no temporary file behind' {
        Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target | Out-Null
        Test-Path (Join-Path $target 'a.bak.ptcopy') | Should -Be $false
    }

    It 'does not replace a different file unless asked to' {
        New-Item -ItemType Directory -Path $target | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'a.bak') -Value 'something else'
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target
        $result.Status | Should -Be 'SkippedExists'
        Get-Content -LiteralPath (Join-Path $target 'a.bak') | Should -Be 'something else'

        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target -Overwrite
        $result.Status | Should -Be 'Copied'
        Get-Content -LiteralPath (Join-Path $target 'a.bak') | Should -Be 'backup A'
    }

    It 'recognises an identical file and still removes the source with -Move' {
        New-Item -ItemType Directory -Path $target | Out-Null
        Copy-Item -LiteralPath (Join-Path $source 'a.bak') -Destination $target
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target -Move
        $result.Status | Should -Be 'Identical'
        Test-Path (Join-Path $source 'a.bak') | Should -Be $false
    }

    It 'does nothing with -WhatIf' {
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target -Move -WhatIf
        $result | Should -BeNullOrEmpty
        Test-Path $target | Should -Be $false
        Test-Path (Join-Path $source 'a.bak') | Should -Be $true
    }

    It 'reports a missing source file as an error' {
        { Copy-PtFileSafe -Path (Join-Path $source 'nope.bak') -Destination $target -ErrorAction Stop } | Should -Throw '*does not exist*'
    }

    It 'supports other hash algorithms' {
        $result = Copy-PtFileSafe -Path (Join-Path $source 'a.bak') -Destination $target -Algorithm MD5
        $result.Hash.Length | Should -Be 32
    }
}
