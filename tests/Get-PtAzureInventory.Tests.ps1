#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests. The Az module is not needed: stand-in functions are defined so the
# commands exist and can be mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'

    function global:Get-AzContext { }
    function global:Get-AzSubscription { param($SubscriptionId) }
    function global:Set-AzContext { param($SubscriptionId) }
    function global:Get-AzResource { param($ResourceGroupName) }

    Import-Module $manifest -Force
}

AfterAll {
    Remove-Item -Path Function:\global:Get-AzContext, Function:\global:Get-AzSubscription, Function:\global:Set-AzContext, Function:\global:Get-AzResource -ErrorAction SilentlyContinue
}

Describe 'Get-PtAzureInventory' {
    Context 'not signed in' {
        BeforeAll {
            Mock Get-AzContext -ModuleName PowerShellToolbox { $null }
        }

        It 'tells the user to sign in' {
            { Get-PtAzureInventory } | Should -Throw '*Connect-AzAccount*'
        }
    }

    Context 'two subscriptions' {
        BeforeAll {
            Mock Get-AzContext -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'context' } }
            Mock Get-AzSubscription -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'Production' },
                    [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; Name = 'Development' }
                )
            }
            Mock Set-AzContext -ModuleName PowerShellToolbox { }
            Mock Get-AzResource -ModuleName PowerShellToolbox {
                @(
                    [pscustomobject]@{ ResourceGroupName = 'rg-sql'; Name = 'sqlprod01'; ResourceType = 'Microsoft.Compute/virtualMachines'; Location = 'westeurope'; Tags = @{ Owner = 'dba-team'; CostCenter = '4711' } },
                    [pscustomobject]@{ ResourceGroupName = 'rg-sql'; Name = 'disk1'; ResourceType = 'Microsoft.Compute/disks'; Location = 'westeurope'; Tags = $null },
                    [pscustomobject]@{ ResourceGroupName = 'rg-web'; Name = 'web01'; ResourceType = 'Microsoft.Web/sites'; Location = 'northeurope'; Tags = @{ owner = 'web-team' } }
                )
            }
        }

        It 'lists the resources of every subscription' {
            $inventory = @(Get-PtAzureInventory)
            $inventory.Count | Should -Be 6
            @($inventory | Select-Object -ExpandProperty Subscription -Unique) -join ',' | Should -Be 'Production,Development'
            Should -Invoke Set-AzContext -ModuleName PowerShellToolbox -Times 2 -Exactly
        }

        It 'writes the tags as one sorted string' {
            $vm = Get-PtAzureInventory | Where-Object Name -eq 'sqlprod01' | Select-Object -First 1
            $vm.Tags | Should -Be 'CostCenter=4711; Owner=dba-team'
        }

        It 'leaves Tags empty for an untagged resource' {
            $disk = Get-PtAzureInventory | Where-Object Name -eq 'disk1' | Select-Object -First 1
            $disk.Tags | Should -Be ''
        }

        It 'reports missing required tags, ignoring case' {
            $inventory = @(Get-PtAzureInventory -RequiredTag Owner, CostCenter)
            ($inventory | Where-Object Name -eq 'sqlprod01' | Select-Object -First 1).MissingTags | Should -Be ''
            ($inventory | Where-Object Name -eq 'disk1' | Select-Object -First 1).MissingTags | Should -Be 'Owner, CostCenter'
            ($inventory | Where-Object Name -eq 'web01' | Select-Object -First 1).MissingTags | Should -Be 'CostCenter'
        }

        It 'can return only the resources with missing tags' {
            $inventory = @(Get-PtAzureInventory -RequiredTag Owner, CostCenter -OnlyMissingTags)
            @($inventory.Name | Select-Object -Unique) -join ',' | Should -Be 'disk1,web01'
        }

        It 'passes the resource group filter on' {
            Get-PtAzureInventory -ResourceGroupName 'rg-sql' | Out-Null
            Should -Invoke Get-AzResource -ModuleName PowerShellToolbox -ParameterFilter { $ResourceGroupName -eq 'rg-sql' }
        }
    }

    Context 'a chosen subscription' {
        BeforeAll {
            Mock Get-AzContext -ModuleName PowerShellToolbox { [pscustomobject]@{ Name = 'context' } }
            Mock Get-AzSubscription -ModuleName PowerShellToolbox { [pscustomobject]@{ Id = $SubscriptionId; Name = 'Chosen' } }
            Mock Set-AzContext -ModuleName PowerShellToolbox { }
            Mock Get-AzResource -ModuleName PowerShellToolbox { }
        }

        It 'looks up only that subscription' {
            Get-PtAzureInventory -SubscriptionId '33333333-3333-3333-3333-333333333333' | Out-Null
            Should -Invoke Get-AzSubscription -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq '33333333-3333-3333-3333-333333333333' }
        }
    }
}
