#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Only the decision logic is tested. Test-PtTlsCertificate itself needs a live TLS
# endpoint.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtTlsStatus' {
    It 'picks the status from the dates and the policy errors' -ForEach @(
        @{ Days = 100; Errors = 'None'; Expected = 'OK' },
        @{ Days = 10; Errors = 'None'; Expected = 'Expiring' },
        @{ Days = -1; Errors = 'None'; Expected = 'Expired' },
        @{ Days = 100; Errors = 'RemoteCertificateNameMismatch'; Expected = 'NameMismatch' },
        @{ Days = 100; Errors = 'RemoteCertificateChainErrors'; Expected = 'Untrusted' },
        @{ Days = 10; Errors = 'RemoteCertificateChainErrors'; Expected = 'Untrusted' },
        @{ Days = -5; Errors = 'RemoteCertificateNameMismatch'; Expected = 'Expired' },
        @{ Days = 100; Errors = 'RemoteCertificateNameMismatch, RemoteCertificateChainErrors'; Expected = 'NameMismatch' }
    ) {
        $result = InModuleScope PowerShellToolbox -Parameters @{ Days = $Days; Errors = $Errors } {
            Get-PtTlsStatus -NotAfter ([datetime]'2023-10-22').AddDays($Days) -PolicyErrors $Errors -Now ([datetime]'2023-10-22')
        }
        $result | Should -Be $Expected
    }

    It 'uses the warning window' {
        $result = InModuleScope PowerShellToolbox {
            Get-PtTlsStatus -NotAfter ([datetime]'2023-12-01') -WarningDays 60 -Now ([datetime]'2023-10-22')
        }
        $result | Should -Be 'Expiring'
    }
}
