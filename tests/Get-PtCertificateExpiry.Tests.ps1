#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. The certificate store and Invoke-Command are mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-PtCertificateExpiry' {
    Context 'the local computer' {
        BeforeAll {
            # mock bodies cannot see variables of this block, so the dates are made inside
            Mock Get-ChildItem -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ Subject = 'CN=ok.example.com'; Issuer = 'CN=Example CA'; Thumbprint = 'AAAA'; NotAfter = (Get-Date).AddDays(200); HasPrivateKey = $true; DnsNameList = @([pscustomobject]@{ Unicode = 'ok.example.com' }, [pscustomobject]@{ Unicode = 'www.example.com' }) },
                    [pscustomobject]@{ Subject = 'CN=soon.example.com'; Issuer = 'CN=Example CA'; Thumbprint = 'BBBB'; NotAfter = (Get-Date).AddDays(10); HasPrivateKey = $true; DnsNameList = @() },
                    [pscustomobject]@{ Subject = 'CN=old.example.com'; Issuer = 'CN=Example CA'; Thumbprint = 'CCCC'; NotAfter = (Get-Date).AddDays(-3); HasPrivateKey = $false; DnsNameList = $null }
                )
            }
            Mock Invoke-Command -ModuleName PowerShellToolbox { }
            $report = @(Get-PtCertificateExpiry -ComputerName $env:COMPUTERNAME)
        }

        It 'sorts by expiry date, soonest first' {
            $report.Thumbprint -join ',' | Should -Be 'CCCC,BBBB,AAAA'
        }

        It 'decides a status from the days left' {
            $report[0].Status | Should -Be 'Expired'
            $report[1].Status | Should -Be 'Expiring'
            $report[2].Status | Should -Be 'OK'
            $report[1].DaysLeft | Should -BeIn 9, 10
            $report[0].DaysLeft | Should -BeLessThan 0
        }

        It 'joins the DNS names' {
            $report[2].DnsNames | Should -Be 'ok.example.com, www.example.com'
        }

        It 'reads the local store without remoting' {
            Should -Invoke Invoke-Command -ModuleName PowerShellToolbox -Times 0 -Exactly
        }

        It 'filters by subject' {
            $filtered = @(Get-PtCertificateExpiry -ComputerName 'localhost' -Subject '*soon*')
            $filtered.Count | Should -Be 1
            $filtered[0].Thumbprint | Should -Be 'BBBB'
        }

        It 'ignores excluded thumbprints' {
            $filtered = @(Get-PtCertificateExpiry -ComputerName 'localhost' -ExcludeThumbprint 'CCCC')
            $filtered.Thumbprint -join ',' | Should -Be 'BBBB,AAAA'
        }

        It 'can show only the problems' {
            $filtered = @(Get-PtCertificateExpiry -ComputerName 'localhost' -OnlyProblems)
            $filtered.Thumbprint -join ',' | Should -Be 'CCCC,BBBB'
        }

        It 'uses the warning window' {
            $wide = @(Get-PtCertificateExpiry -ComputerName 'localhost' -WarningDays 365)
            ($wide | Where-Object Thumbprint -eq 'AAAA').Status | Should -Be 'Expiring'
        }
    }

    Context 'a remote computer' {
        It 'uses remoting' {
            Mock Invoke-Command -ModuleName PowerShellToolbox {
                [pscustomobject]@{ Subject = 'CN=web'; Issuer = 'CN=CA'; Thumbprint = 'DDDD'; NotAfter = (Get-Date).AddDays(100); HasPrivateKey = $true; DnsNames = 'web.example.com' }
            }
            $report = @(Get-PtCertificateExpiry -ComputerName 'WEB01' -StoreName 'WebHosting')
            $report.Count | Should -Be 1
            $report[0].ComputerName | Should -Be 'WEB01'
            Should -Invoke Invoke-Command -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'WEB01' -and $ArgumentList[1] -eq 'WebHosting'
            }
        }

        It 'warns when the computer cannot be reached' {
            Mock Invoke-Command -ModuleName PowerShellToolbox { throw 'WinRM cannot connect' }
            $report = Get-PtCertificateExpiry -ComputerName 'DOWN01' -WarningVariable warnings -WarningAction SilentlyContinue
            $report | Should -BeNullOrEmpty
            "$warnings" | Should -Match 'DOWN01'
        }
    }
}
