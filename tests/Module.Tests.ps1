#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Tests about the module as a whole: the manifest, the exports and the conventions
# every command is supposed to follow. They use PowerShell's own parser, so a syntax
# error in any file shows up here first.

BeforeDiscovery {
    $moduleFolder = Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox'
    $allFiles = @(Get-ChildItem -Path (Join-Path $moduleFolder 'Public'), (Join-Path $moduleFolder 'Private') -Filter '*.ps1')
    $publicFiles = @(Get-ChildItem -Path (Join-Path $moduleFolder 'Public') -Filter '*.ps1')
    $allCases = @($allFiles | ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } })
    $publicCases = @($publicFiles | ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } })
}

BeforeAll {
    $moduleFolder = Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox'
    $manifest = Join-Path $moduleFolder 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force

    function Get-FunctionAst {
        param([string]$Path)
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        [pscustomobject]@{
            Errors    = @($errors)
            Functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
            Ast       = $ast
        }
    }
}

Describe 'The module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $manifest -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the files in Public' {
        $exported = @((Get-Module PowerShellToolbox).ExportedFunctions.Keys | Sort-Object)
        $expected = @(Get-ChildItem -Path (Join-Path $moduleFolder 'Public') -Filter '*.ps1' | ForEach-Object BaseName | Sort-Object)
        ($exported -join ',') | Should -Be ($expected -join ',')
    }

    It 'lists the same functions in FunctionsToExport' {
        $data = Import-PowerShellDataFile -Path $manifest
        (@($data.FunctionsToExport | Sort-Object) -join ',') | Should -Be (@((Get-Module PowerShellToolbox).ExportedFunctions.Keys | Sort-Object) -join ',')
    }

    It 'keeps the private functions private' {
        $private = @(Get-ChildItem -Path (Join-Path $moduleFolder 'Private') -Filter '*.ps1' | ForEach-Object BaseName)
        foreach ($name in $private) {
            (Get-Module PowerShellToolbox).ExportedFunctions.Keys | Should -Not -Contain $name
        }
    }
}

Describe 'Every function file' {
    It '<Name> parses without errors and defines the function of that name' -ForEach $allCases {
        $result = Get-FunctionAst -Path $Path
        $result.Errors | Should -BeNullOrEmpty
        @($result.Functions | ForEach-Object Name) | Should -Contain $Name
    }

    It '<Name> does not use Write-Host' -ForEach $allCases {
        $result = Get-FunctionAst -Path $Path
        $calls = $result.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Host' }, $true)
        @($calls).Count | Should -Be 0
    }
}

Describe 'Every public command' {
    It '<Name> has comment-based help with a synopsis, a description and an example' -ForEach $publicCases {
        $function = (Get-FunctionAst -Path $Path).Functions | Where-Object Name -eq $Name | Select-Object -First 1
        $help = $function.GetHelpContent()
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.Examples).Count | Should -BeGreaterThan 0
    }

    It '<Name> documents every parameter it has' -ForEach $publicCases {
        $function = (Get-FunctionAst -Path $Path).Functions | Where-Object Name -eq $Name | Select-Object -First 1
        $help = $function.GetHelpContent()
        $documented = @($help.Parameters.Keys | ForEach-Object { $_.ToUpperInvariant() })
        $declared = @($function.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath.ToUpperInvariant() })
        $missing = @($declared | Where-Object { $documented -notcontains $_ })
        ($missing -join ',') | Should -Be ''
    }

    It '<Name> uses [CmdletBinding()] and an approved verb' -ForEach $publicCases {
        $function = (Get-FunctionAst -Path $Path).Functions | Where-Object Name -eq $Name | Select-Object -First 1
        $attributes = @($function.Body.ParamBlock.Attributes | ForEach-Object { $_.TypeName.Name })
        $attributes | Should -Contain 'CmdletBinding'
        (Get-Verb).Verb | Should -Contain ($Name -split '-')[0]
    }

    It '<Name> supports -WhatIf because it changes something' -ForEach @(
        $publicCases | Where-Object { (($_.Name -split '-')[0]) -in 'Remove', 'Rename', 'Restart', 'Register', 'Set', 'Compress', 'Copy', 'Add', 'New', 'Import', 'Export', 'Invoke' -and $_.Name -notin 'New-PtJql', 'Invoke-PtSqlQuery', 'Invoke-PtRestRetry', 'Invoke-PtRestPaged', 'Invoke-PtJiraRequest', 'Export-PtReport' -or $_.Name -eq 'Export-PtReport' }
    ) {
        $function = (Get-FunctionAst -Path $Path).Functions | Where-Object Name -eq $Name | Select-Object -First 1
        $cmdletBinding = $function.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' } | Select-Object -First 1
        @($cmdletBinding.NamedArguments | Where-Object ArgumentName -eq 'SupportsShouldProcess').Count | Should -Be 1
    }
}
