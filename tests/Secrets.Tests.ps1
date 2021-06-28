#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests for the SecretManagement wrappers. The real modules are not needed:
# stand-in functions are defined so the commands exist and can be mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'

    function global:Get-Secret { param($Name, $Vault, [switch]$AsPlainText) }
    function global:Set-Secret { param($Name, $Secret, $Vault) }
    function global:Get-SecretVault { param($Name) }
    function global:Register-SecretVault { param($Name, $ModuleName, [switch]$DefaultVault) }

    Import-Module $manifest -Force
}

AfterAll {
    Remove-Item -Path Function:\global:Get-Secret, Function:\global:Set-Secret, Function:\global:Get-SecretVault, Function:\global:Register-SecretVault -ErrorAction SilentlyContinue
}

Describe 'Get-PtSecret and Set-PtSecret' {
    BeforeAll {
        Mock Get-Secret -ModuleName PowerShellToolbox { 'the secret' }
        Mock Set-Secret -ModuleName PowerShellToolbox { }
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'avery@example.com', (ConvertTo-SecureString 'tok' -AsPlainText -Force)
    }

    It 'reads from the default vault' {
        Get-PtSecret -Name 'x' | Should -Be 'the secret'
        Should -Invoke Get-Secret -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Name -eq 'x' -and $Vault -eq 'PowerShellToolbox' }
    }

    It 'passes -AsPlainText on' {
        Get-PtSecret -Name 'x' -AsPlainText | Out-Null
        Should -Invoke Get-Secret -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $AsPlainText }
    }

    It 'stores a credential in the default vault' {
        Set-PtSecret -Name 'jira' -Credential $credential
        Should -Invoke Set-Secret -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'jira' -and $Vault -eq 'PowerShellToolbox' -and $Secret.UserName -eq 'avery@example.com'
        }
    }

    It 'does not store anything with -WhatIf' {
        Set-PtSecret -Name 'jira' -Credential $credential -WhatIf
        Should -Invoke Set-Secret -ModuleName PowerShellToolbox -Times 0 -Exactly
    }
}

Describe 'Initialize-PtVault' {
    It 'asks for the modules to be installed first' {
        Mock Get-Module -ModuleName PowerShellToolbox { $null }
        { Initialize-PtVault } | Should -Throw '*Install-Module Microsoft.PowerShell.SecretManagement*'
    }

    It 'registers a SecretStore vault when there is none' {
        Mock Get-Module -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'present' } }
        Mock Get-SecretVault -ModuleName PowerShellToolbox { $null }
        Mock Register-SecretVault -ModuleName PowerShellToolbox { }
        Initialize-PtVault | Out-Null
        Should -Invoke Register-SecretVault -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PowerShellToolbox' -and $ModuleName -eq 'Microsoft.PowerShell.SecretStore'
        }
    }

    It 'leaves an existing vault alone' {
        Mock Get-Module -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'present' } }
        Mock Get-SecretVault -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'PowerShellToolbox' } }
        Mock Register-SecretVault -ModuleName PowerShellToolbox { }
        (Initialize-PtVault).Name | Should -Be 'PowerShellToolbox'
        Should -Invoke Register-SecretVault -ModuleName PowerShellToolbox -Times 0 -Exactly
    }
}

Describe 'Connect-PtJira -SecretName' {
    BeforeEach {
        Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox { }
    }

    It 'signs in with the stored credential' {
        Mock Get-PtSecret -ModuleName PowerShellToolbox {
            New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'avery@example.com', (ConvertTo-SecureString 's3cr3t' -AsPlainText -Force)
        }
        $connection = Connect-PtJira -BaseUri 'https://example.atlassian.net' -SecretName 'jira-api-token' -SkipValidation
        $connection.Email | Should -Be 'avery@example.com'
        Invoke-PtJiraRequest -Path '/x' | Out-Null
        Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Headers.Authorization -eq 'Basic YXZlcnlAZXhhbXBsZS5jb206czNjcjN0'
        }
    }

    It 'rejects a secret that is not a credential' {
        Mock Get-PtSecret -ModuleName PowerShellToolbox { ConvertTo-SecureString 'just a token' -AsPlainText -Force }
        { Connect-PtJira -BaseUri 'https://example.atlassian.net' -SecretName 'jira-api-token' -SkipValidation } | Should -Throw '*not a credential*'
    }
}
