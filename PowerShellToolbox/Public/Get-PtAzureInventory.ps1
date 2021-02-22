function Get-PtAzureInventory {
    <#
    .SYNOPSIS
    Lists the Azure resources in one or more subscriptions, with their tags.

    .DESCRIPTION
    Uses the Az module (Install-Module Az) and the account you are already
    signed in with (Connect-AzAccount). For every subscription it
    returns one object per resource: resource group, name, type, location and the
    tags as a single "key=value; key=value" string, which is handy in a CSV.

    .PARAMETER SubscriptionId
    The subscriptions to read. Default: all that the account can see.

    .PARAMETER ResourceGroupName
    Only this resource group in each subscription.

    .PARAMETER RequiredTag
    Tag names every resource should have (for example Owner, CostCenter). The
    output gets a MissingTags column listing the ones a resource lacks. Tag names
    are not case-sensitive in Azure, and neither is this check.

    .PARAMETER OnlyMissingTags
    With -RequiredTag, return only the resources that lack at least one of them.

    .EXAMPLE
    Get-PtAzureInventory -RequiredTag Owner, CostCenter -OnlyMissingTags | Export-Csv -Path .\untagged.csv -NoTypeInformation

    .EXAMPLE
    Get-PtAzureInventory | Export-Csv -Path .\inventory.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubscriptionId,

        [string]$ResourceGroupName,

        [string[]]$RequiredTag,

        [switch]$OnlyMissingTags
    )

    if (-not (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)) {
        throw 'The Az module is not installed. Install it with: Install-Module Az'
    }
    if (-not (Get-AzContext)) {
        throw 'Not signed in to Azure. Run Connect-AzAccount first.'
    }

    if ($SubscriptionId) {
        $subscriptions = @($SubscriptionId | ForEach-Object { Get-AzSubscription -SubscriptionId $_ })
    }
    else {
        $subscriptions = @(Get-AzSubscription)
    }

    foreach ($subscription in $subscriptions) {
        [void](Set-AzContext -SubscriptionId $subscription.Id)

        $parameters = @{}
        if ($ResourceGroupName) { $parameters['ResourceGroupName'] = $ResourceGroupName }

        foreach ($resource in (Get-AzResource @parameters)) {
            $tags = ''
            if ($resource.Tags) {
                $pairs = foreach ($tag in ($resource.Tags.GetEnumerator() | Sort-Object -Property Name)) { "$($tag.Name)=$($tag.Value)" }
                $tags = $pairs -join '; '
            }

            $present = @()
            if ($resource.Tags) { $present = @($resource.Tags.Keys) }
            $missing = @()
            foreach ($required in @($RequiredTag)) {
                if ($required -and -not ($present -contains $required)) { $missing += $required }
            }
            if ($OnlyMissingTags -and $missing.Count -eq 0) { continue }

            [pscustomobject]@{
                Subscription  = $subscription.Name
                ResourceGroup = $resource.ResourceGroupName
                Name          = $resource.Name
                Type          = $resource.ResourceType
                Location      = $resource.Location
                Tags          = $tags
                MissingTags   = ($missing -join ', ')
            }
        }
    }
}
