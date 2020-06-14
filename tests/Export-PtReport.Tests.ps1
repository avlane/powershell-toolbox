#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. Writes into TestDrive only.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force

    $rows = @(
        [pscustomobject]@{ Name = 'SQLPROD01'; FreeGB = 12.5; Note = 'ok' },
        [pscustomobject]@{ Name = 'SQLPROD02'; FreeGB = 3; Note = '<script>alert(1)</script> & more' }
    )
}

Describe 'Export-PtReport' {
    It 'infers CSV from the extension' {
        $file = $rows | Export-PtReport -Path (Join-Path $TestDrive 'r.csv')
        $file.Name | Should -Be 'r.csv'
        $back = @(Import-Csv -LiteralPath $file.FullName)
        $back.Count | Should -Be 2
        $back[1].Name | Should -Be 'SQLPROD02'
    }

    It 'writes JSON as an array even for a single row' {
        $file = $rows[0] | Export-PtReport -Path (Join-Path $TestDrive 'one.json')
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $text.TrimStart() | Should -Match '^\['
        @($text | ConvertFrom-Json).Count | Should -Be 1
    }

    It 'encodes values in HTML' {
        $file = $rows | Export-PtReport -Path (Join-Path $TestDrive 'r.html') -Title 'Disks & more'
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $text | Should -Match '<title>Disks &amp; more</title>'
        $text | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt; &amp; more'
        $text | Should -Not -Match '<script>'
        $text | Should -Match '<th>FreeGB</th>'
    }

    It 'creates the folder' {
        $path = Join-Path (Join-Path (Join-Path $TestDrive 'a') 'b') 'c.json'
        $rows | Export-PtReport -Path $path | Out-Null
        Test-Path $path | Should -Be $true
    }

    It 'needs -Format when the extension is unknown' {
        { $rows | Export-PtReport -Path (Join-Path $TestDrive 'r.dat') } | Should -Throw '*Cannot tell the format*'
        $rows | Export-PtReport -Path (Join-Path $TestDrive 'r.dat') -Format Csv | Out-Null
        Test-Path (Join-Path $TestDrive 'r.dat') | Should -Be $true
    }

    It 'writes nothing with -WhatIf' {
        $path = Join-Path $TestDrive 'whatif.csv'
        $rows | Export-PtReport -Path $path -WhatIf
        Test-Path $path | Should -Be $false
    }

    It 'handles an empty result' {
        $file = @() | Export-PtReport -Path (Join-Path $TestDrive 'empty.json')
        (Get-Content -LiteralPath $file.FullName -Raw).Trim() | Should -Be '[]'
    }
}
