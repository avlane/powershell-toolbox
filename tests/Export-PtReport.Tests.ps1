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

    It 'colours rows by Status or Verdict' {
        $data = @(
            [pscustomobject]@{ Name = 'a'; Status = 'OK' },
            [pscustomobject]@{ Name = 'b'; Status = 'Low' },
            [pscustomobject]@{ Name = 'c'; Status = 'Failed' },
            [pscustomobject]@{ Name = 'd'; Verdict = 'Flaky' },
            [pscustomobject]@{ Name = 'e'; Other = 'x' }
        )
        $file = $data | Export-PtReport -Path (Join-Path $TestDrive 'colours.html')
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $text | Should -Match '<tr class="good"><td>a</td>'
        $text | Should -Match '<tr class="warn"><td>b</td>'
        $text | Should -Match '<tr class="bad"><td>c</td>'
        $text | Should -Match '<tr class="warn"><td>d</td>'
        $text | Should -Match '<tr><td>e</td>'
    }

    It 'uses the delimiter it is given' {
        $file = $rows | Export-PtReport -Path (Join-Path $TestDrive 'semi.csv') -Delimiter ';'
        (Get-Content -LiteralPath $file.FullName)[0] | Should -Be '"Name";"FreeGB";"Note"'
    }

    It 'writes a byte order mark only when asked to' {
        $plain = $rows | Export-PtReport -Path (Join-Path $TestDrive 'plain.csv')
        $bom = $rows | Export-PtReport -Path (Join-Path $TestDrive 'bom.csv') -Encoding utf8BOM
        [System.IO.File]::ReadAllBytes($plain.FullName)[0] | Should -Be ([byte][char]'"')
        ([System.IO.File]::ReadAllBytes($bom.FullName)[0..2] -join ',') | Should -Be '239,187,191'
    }

    It 'keeps nested objects up to -JsonDepth and can write compact JSON' {
        $nested = [pscustomobject]@{ Name = 'a'; Inner = [pscustomobject]@{ Deep = [pscustomobject]@{ Value = 1 } } }
        $file = $nested | Export-PtReport -Path (Join-Path $TestDrive 'nested.json') -JsonDepth 4 -Compress
        $text = (Get-Content -LiteralPath $file.FullName -Raw).Trim()
        $text | Should -Be '[{"Name":"a","Inner":{"Deep":{"Value":1}}}]'
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
