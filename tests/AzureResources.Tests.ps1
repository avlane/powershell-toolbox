#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests for the Azure VM and SQL inventories. The Az modules are not needed:
# stand-in functions are defined so the commands exist and can be mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'

    function global:Get-AzContext { }
    function global:Get-AzSubscription { param($SubscriptionId) }
    function global:Set-AzContext { param($SubscriptionId) }
    function global:Get-AzVM { param($ResourceGroupName, [switch]$Status) }
    function global:Get-AzSqlServer { param($ResourceGroupName) }
    function global:Get-AzSqlDatabase { param($ServerName, $ResourceGroupName) }

    Import-Module $manifest -Force
}

AfterAll {
    Remove-Item -Path Function:\global:Get-AzContext, Function:\global:Get-AzSubscription, Function:\global:Set-AzContext, Function:\global:Get-AzVM, Function:\global:Get-AzSqlServer, Function:\global:Get-AzSqlDatabase -ErrorAction SilentlyContinue
}

Describe 'Get-PtAzVmInventory' {
    BeforeAll {
        Mock Get-AzContext -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'context' } }
        Mock Get-AzSubscription -ModuleName PowerShellToolbox { [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'Production' } }
        Mock Set-AzContext -ModuleName PowerShellToolbox { }
        Mock Get-AzVM -ModuleName PowerShellToolbox -ParameterFilter { $Status } {
            @(
                [pscustomobject]@{ ResourceGroupName = 'RG-SQL'; Name = 'sqlprod01'; PowerState = 'VM running' },
                [pscustomobject]@{ ResourceGroupName = 'rg-sql'; Name = 'sqltest01'; PowerState = 'VM stopped' },
                [pscustomobject]@{ ResourceGroupName = 'rg-sql'; Name = 'sqldr01'; PowerState = 'VM deallocated' }
            )
        }
        Mock Get-AzVM -ModuleName PowerShellToolbox -ParameterFilter { -not $Status } {
            @(
                [pscustomobject]@{
                    ResourceGroupName = 'rg-sql'; Name = 'sqlprod01'; Location = 'westeurope'; Zones = @('1'); ProvisioningState = 'Succeeded'
                    HardwareProfile = [pscustomobject]@{ VmSize = 'Standard_E8ds_v5' }
                    StorageProfile = [pscustomobject]@{ OsDisk = [pscustomobject]@{ OsType = 'Windows' }; ImageReference = [pscustomobject]@{ Offer = 'sql2019-ws2022'; Sku = 'enterprise-gen2' }; DataDisks = @(1, 2, 3) }
                    NetworkProfile = [pscustomobject]@{ NetworkInterfaces = @(1) }
                },
                [pscustomobject]@{
                    ResourceGroupName = 'rg-sql'; Name = 'sqltest01'; Location = 'westeurope'; Zones = $null; ProvisioningState = 'Succeeded'
                    HardwareProfile = [pscustomobject]@{ VmSize = 'Standard_D4s_v5' }
                    StorageProfile = [pscustomobject]@{ OsDisk = [pscustomobject]@{ OsType = 'Windows' }; ImageReference = $null; DataDisks = @() }
                    NetworkProfile = [pscustomobject]@{ NetworkInterfaces = @(1) }
                },
                [pscustomobject]@{
                    ResourceGroupName = 'rg-sql'; Name = 'sqldr01'; Location = 'northeurope'; Zones = $null; ProvisioningState = 'Succeeded'
                    HardwareProfile = [pscustomobject]@{ VmSize = 'Standard_E8ds_v5' }
                    StorageProfile = [pscustomobject]@{ OsDisk = [pscustomobject]@{ OsType = 'Windows' }; ImageReference = $null; DataDisks = @(1) }
                    NetworkProfile = [pscustomobject]@{ NetworkInterfaces = @(1) }
                }
            )
        }
        $inventory = @(Get-PtAzVmInventory)
    }

    It 'returns a row per VM' {
        $inventory.Count | Should -Be 3
    }

    It 'merges the power state, ignoring the case of the resource group' {
        ($inventory | Where-Object Name -eq 'sqlprod01').PowerState | Should -Be 'VM running'
    }

    It 'takes size, image, zones and disk count from the configuration' {
        $vm = $inventory | Where-Object Name -eq 'sqlprod01'
        $vm.Size | Should -Be 'Standard_E8ds_v5'
        $vm.Image | Should -Be 'sql2019-ws2022 enterprise-gen2'
        $vm.Zones | Should -Be '1'
        $vm.DataDisks | Should -Be 3
        $vm.OsType | Should -Be 'Windows'
    }

    It 'flags a VM that is stopped but not deallocated' {
        ($inventory | Where-Object Name -eq 'sqltest01').Flag | Should -Match 'still billed'
        ($inventory | Where-Object Name -eq 'sqldr01').Flag | Should -Be ''
        ($inventory | Where-Object Name -eq 'sqlprod01').Flag | Should -Be ''
    }
}

Describe 'Get-PtAzSqlInventory' {
    BeforeAll {
        Mock Get-AzContext -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'context' } }
        Mock Get-AzSubscription -ModuleName PowerShellToolbox { [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'Production' } }
        Mock Set-AzContext -ModuleName PowerShellToolbox { }
        Mock Get-AzSqlServer -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ ServerName = 'sql-prod'; ResourceGroupName = 'rg-data'; FullyQualifiedDomainName = 'sql-prod.database.windows.net'; Location = 'westeurope'; ServerVersion = '12.0'; PublicNetworkAccess = 'Disabled'; MinimalTlsVersion = '1.2' },
                [pscustomobject]@{ ServerName = 'sql-old'; ResourceGroupName = 'rg-data'; FullyQualifiedDomainName = 'sql-old.database.windows.net'; Location = 'westeurope'; ServerVersion = '12.0'; PublicNetworkAccess = 'Enabled'; MinimalTlsVersion = '1.0' },
                [pscustomobject]@{ ServerName = 'sql-empty'; ResourceGroupName = 'rg-data'; FullyQualifiedDomainName = 'sql-empty.database.windows.net'; Location = 'northeurope'; ServerVersion = '12.0'; PublicNetworkAccess = 'Disabled'; MinimalTlsVersion = 'None' }
            )
        }
        Mock Get-AzSqlDatabase -ModuleName PowerShellToolbox {
            if ($ServerName -eq 'sql-empty') { return }
            @(
                [pscustomobject]@{ DatabaseName = 'master'; Edition = 'System'; CurrentServiceObjectiveName = 'System'; MaxSizeBytes = 32GB; Status = 'Online'; ZoneRedundant = $false },
                [pscustomobject]@{ DatabaseName = "app-$ServerName"; Edition = 'GeneralPurpose'; CurrentServiceObjectiveName = 'GP_Gen5_2'; MaxSizeBytes = 64GB; Status = 'Online'; ZoneRedundant = $true }
            )
        }
        $inventory = @(Get-PtAzSqlInventory)
    }

    It 'skips master and returns one row per database, plus a row for a server without databases' {
        $inventory.Count | Should -Be 3
        $inventory.Database | Should -Not -Contain 'master'
    }

    It 'repeats the server properties on each row' {
        $row = $inventory | Where-Object Database -eq 'app-sql-prod'
        $row.Server | Should -Be 'sql-prod.database.windows.net'
        $row.Edition | Should -Be 'GeneralPurpose'
        $row.MaxSizeGB | Should -Be 64
        $row.ZoneRedundant | Should -Be $true
    }

    It 'flags public access and old TLS' {
        ($inventory | Where-Object Database -eq 'app-sql-prod').Flags | Should -Be ''
        ($inventory | Where-Object Database -eq 'app-sql-old').Flags | Should -Be 'PublicAccess, OldTls'
    }

    It 'treats a minimum TLS version of None as old' {
        ($inventory | Where-Object Server -eq 'sql-empty.database.windows.net').Flags | Should -Be 'OldTls'
    }
}
