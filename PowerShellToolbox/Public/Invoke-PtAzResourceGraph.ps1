function Invoke-PtAzResourceGraph {
    <#
    .SYNOPSIS
    Runs an Azure Resource Graph (Kusto) query and returns all rows, paging as needed.

    .DESCRIPTION
    Wraps Search-AzGraph from the Az.ResourceGraph module. One call returns at most
    1000 rows, so this asks for the next page (-Skip) until a page comes back
    short, and writes the rows to the pipeline. Resource Graph is much faster than
    Get-AzResource when you want something across many subscriptions, and it can
    answer questions the portal cannot, such as "which VMs have no backup".

    Needs Az.ResourceGraph and a signed-in session (Connect-AzAccount).

    .PARAMETER Query
    The query, for example: Resources | where type =~ 'microsoft.compute/virtualmachines' | project name, location

    .PARAMETER Subscription
    Limit the query to these subscription ids. Default: everything the account can see.

    .PARAMETER ManagementGroup
    Limit the query to these management groups.

    .PARAMETER PageSize
    Rows per request, 1 to 1000. Default 1000.

    .PARAMETER First
    Stop after this many rows in total.

    .EXAMPLE
    Invoke-PtAzResourceGraph -Query "Resources | where isnull(tags['Owner']) | project name, type, resourceGroup" | Export-Csv .\no-owner.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [string[]]$Subscription,

        [string[]]$ManagementGroup,

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000,

        [ValidateRange(1, 1000000)]
        [int]$First = 1000000
    )

    if (-not (Get-Command -Name Search-AzGraph -ErrorAction SilentlyContinue)) {
        throw 'Search-AzGraph was not found. Install the module with: Install-Module Az.ResourceGraph'
    }
    if ($Subscription -and $ManagementGroup) {
        throw 'Use either -Subscription or -ManagementGroup, not both.'
    }

    $skip = 0
    $returned = 0
    while ($returned -lt $First) {
        $parameters = @{ Query = $Query; First = [math]::Min($PageSize, $First - $returned) }
        if ($skip -gt 0) { $parameters['Skip'] = $skip }
        if ($Subscription) { $parameters['Subscription'] = $Subscription }
        if ($ManagementGroup) { $parameters['ManagementGroup'] = $ManagementGroup }

        $response = Search-AzGraph @parameters
        $rows = @($response.Data)
        foreach ($row in $rows) {
            $row
            $returned++
        }

        if ($rows.Count -lt $parameters['First']) { break }
        $skip += $rows.Count
    }
}
