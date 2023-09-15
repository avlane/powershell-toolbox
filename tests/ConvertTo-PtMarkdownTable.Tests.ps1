#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
    $newline = [Environment]::NewLine
}

Describe 'ConvertTo-PtMarkdownTable' {
    It 'writes a header, a separator and one line per row' {
        $rows = @([pscustomobject]@{ Name = 'a'; Count = 1 }, [pscustomobject]@{ Name = 'b'; Count = 2 })
        $expected = @('| Name | Count |', '| --- | --- |', '| a | 1 |', '| b | 2 |') -join $newline
        ($rows | ConvertTo-PtMarkdownTable) | Should -Be $expected
    }

    It 'shows only the properties asked for, in that order' {
        $row = [pscustomobject]@{ A = 1; B = 2; C = 3 }
        ($row | ConvertTo-PtMarkdownTable -Property C, A) | Should -Be (@('| C | A |', '| --- | --- |', '| 3 | 1 |') -join $newline)
    }

    It 'makes cell values safe' {
        $row = [pscustomobject]@{ Text = "one | two`r`nthree"; Nothing = $null; List = @('x', 'y'); When = [datetime]'2023-09-17 08:30:00' }
        $table = $row | ConvertTo-PtMarkdownTable
        $table | Should -Match ([regex]::Escape('| one \| two three |  | x, y | 2023-09-17 08:30:00 |'))
    }

    It 'cuts long text' {
        $row = [pscustomobject]@{ Text = ('x' * 50) }
        $table = $row | ConvertTo-PtMarkdownTable -MaxCellLength 20
        $table | Should -Match ([regex]::Escape('| ' + ('x' * 17) + '... |'))
    }

    It 'gives an empty string for no rows' {
        (@() | ConvertTo-PtMarkdownTable) | Should -Be ''
    }

    It 'is available as a report format' {
        $rows = @([pscustomobject]@{ Name = 'a'; Status = 'OK' })
        $file = $rows | Export-PtReport -Path (Join-Path $TestDrive 'report.md') -Title 'Disks'
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $text | Should -Match '^# Disks'
        $text | Should -Match '\| Name \| Status \|'
        $text | Should -Match '\| a \| OK \|'
    }
}
