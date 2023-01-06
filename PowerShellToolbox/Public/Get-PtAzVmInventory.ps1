function Get-PtAzVmInventory {
    <#
    .SYNOPSIS
    Lists the Azure virtual machines of one or more subscriptions with size, power state and disks.

    .DESCRIPTION
    Uses the Az.Compute module and the account you are signed in with. For every
    subscription it calls Get-AzVM twice, once for the configuration and once with
    -Status for the power state, and merges them. A VM that is stopped but not
    deallocated is flagged, because it still costs money.

    .PARAMETER SubscriptionId
    The subscriptions to read. Default: all that the account can see.

    .PARAMETER ResourceGroupName
    Only this resource group in each subscription.

    .EXAMPLE
    Get-PtAzVmInventory | Where-Object Flag | Format-Table Subscription, Name, PowerState, Flag
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubscriptionId,

        [string]$ResourceGroupName
    )

    if (-not (Get-Command -Name Get-AzVM -ErrorAction SilentlyContinue)) {
        throw 'The Az.Compute module is not installed. Install it with: Install-Module Az'
    }
    if (-not (Get-AzContext)) {
        throw 'Not signed in to Azure. Run Connect-AzAccount first.'
    }

    $subscriptions = $SubscriptionId ? @($SubscriptionId | ForEach-Object { Get-AzSubscription -SubscriptionId $_ }) : @(Get-AzSubscription)

    foreach ($subscription in $subscriptions) {
        [void](Set-AzContext -SubscriptionId $subscription.Id)

        $parameters = @{}
        if ($ResourceGroupName) { $parameters['ResourceGroupName'] = $ResourceGroupName }

        # the configuration does not contain the power state; -Status does, but not the size
        $states = @{}
        foreach ($status in @(Get-AzVM @parameters -Status)) {
            $states["$($status.ResourceGroupName)/$($status.Name)".ToLowerInvariant()] = $status.PowerState
        }

        foreach ($vm in @(Get-AzVM @parameters)) {
            $powerState = $states["$($vm.ResourceGroupName)/$($vm.Name)".ToLowerInvariant()] ?? 'unknown'

            $flag = ''
            if ($powerState -eq 'VM stopped') { $flag = 'Stopped but not deallocated (still billed)' }
            elseif ($powerState -eq 'unknown') { $flag = 'Power state not reported' }

            [pscustomobject]@{
                Subscription      = $subscription.Name
                ResourceGroup     = $vm.ResourceGroupName
                Name              = $vm.Name
                Location          = $vm.Location
                Size              = $vm.HardwareProfile.VmSize
                PowerState        = $powerState
                OsType            = [string]$vm.StorageProfile.OsDisk.OsType
                Image             = (@($vm.StorageProfile.ImageReference.Offer, $vm.StorageProfile.ImageReference.Sku) | Where-Object { $_ }) -join ' '
                Zones             = @($vm.Zones) -join ','
                DataDisks         = @($vm.StorageProfile.DataDisks).Count
                NetworkInterfaces = @($vm.NetworkProfile.NetworkInterfaces).Count
                ProvisioningState = $vm.ProvisioningState
                Flag              = $flag
            }
        }
    }
}
