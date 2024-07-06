function Get-PtAzureTagSummary {
    <#
    .SYNOPSIS
    Counts Azure resources by the value of one or more tags, for cost allocation and clean-up.

    .DESCRIPTION
    Takes the output of Get-PtAzureInventory (from the pipeline, or by calling it
    itself) and, for each requested tag, counts the resources per tag value, with
    the resources that lack the tag grouped under (missing). Tag names are matched
    without regard to case; values are compared exactly. The resource types that
    make up each group are listed, most common first.

    The Tags column of the inventory is a "name=value; name=value" string, so tag
    values that themselves contain "; " cannot be told apart.

    .PARAMETER Tag
    The tag names to summarise, for example CostCenter or Owner.

    .PARAMETER InputObject
    Inventory rows. If none are piped in, Get-PtAzureInventory is called.

    .PARAMETER SubscriptionId
    Passed to Get-PtAzureInventory when it is called here.

    .EXAMPLE
    Get-PtAzureTagSummary -Tag CostCenter | Format-Table Tag, Value, Count, ResourceTypes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Tag,

        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject,

        [string[]]$SubscriptionId
    )

    begin {
        $rows = New-Object -TypeName 'System.Collections.Generic.List[object]'
    }

    process {
        foreach ($item in @($InputObject)) { if ($null -ne $item) { $rows.Add($item) } }
    }

    end {
        if ($rows.Count -eq 0) {
            $inventoryParameters = @{}
            if ($SubscriptionId) { $inventoryParameters['SubscriptionId'] = $SubscriptionId }
            foreach ($item in (Get-PtAzureInventory @inventoryParameters)) { $rows.Add($item) }
        }

        # read the tags of every resource once
        $parsed = foreach ($row in $rows) {
            $tags = @{}
            foreach ($pair in ([string]$row.Tags -split '; ' | Where-Object { $_ })) {
                $separator = $pair.IndexOf('=')
                if ($separator -gt 0) { $tags[$pair.Substring(0, $separator)] = $pair.Substring($separator + 1) }
            }
            [pscustomobject]@{ Type = $row.Type; Tags = $tags }
        }

        foreach ($name in $Tag) {
            $groups = $parsed | Group-Object -Property { $_.Tags.ContainsKey($name) ? $_.Tags[$name] : '(missing)' }
            foreach ($group in ($groups | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)) {
                $types = $group.Group | Group-Object -Property Type | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First 3
                [pscustomobject]@{
                    Tag           = $name
                    Value         = $group.Name
                    Count         = $group.Count
                    ResourceTypes = ($types | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', '
                }
            }
        }
    }
}
