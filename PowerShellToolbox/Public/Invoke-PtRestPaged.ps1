function Invoke-PtRestPaged {
    <#
    .SYNOPSIS
    Reads every page of a paged REST API and returns the items one by one.

    .DESCRIPTION
    Calls the address with Invoke-PtRestRetry (so busy servers are retried), pulls
    the items out of each response and follows the link to the next page until
    there is none. Two ways of finding the next page are supported:

      -UseLinkHeader      the Link: <...>; rel="next" header (GitHub, GitLab, ...)
      -NextLinkProperty   a property of the response body that holds the next address
                          (for example nextLink, or '@odata.nextLink' for Microsoft Graph)

    Items are written to the pipeline as they arrive, so a large listing can be
    processed without holding it all in memory.

    .PARAMETER Uri
    The first page.

    .PARAMETER Headers
    Request headers, for example Authorization.

    .PARAMETER ItemsProperty
    The property of the body that holds the array of items, for example value or
    items. Leave out when the body itself is the array.

    .PARAMETER NextLinkProperty
    The body property with the address of the next page.

    .PARAMETER UseLinkHeader
    Follow the Link header instead.

    .PARAMETER MaxPages
    A safety limit against endless paging. Default 1000.

    .PARAMETER MaxRetries
    Passed to Invoke-PtRestRetry. Default 3.

    .EXAMPLE
    Invoke-PtRestPaged -Uri 'https://api.github.com/orgs/example/repos?per_page=100' -UseLinkHeader -Headers @{ 'User-Agent' = 'pt' }

    .EXAMPLE
    Invoke-PtRestPaged -Uri 'https://graph.microsoft.com/v1.0/users' -ItemsProperty value -NextLinkProperty '@odata.nextLink' -Headers $headers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Uri,

        [hashtable]$Headers,

        [string]$ItemsProperty,

        [string]$NextLinkProperty,

        [switch]$UseLinkHeader,

        [ValidateRange(1, 100000)]
        [int]$MaxPages = 1000,

        [ValidateRange(0, 20)]
        [int]$MaxRetries = 3
    )

    if ($UseLinkHeader -and $NextLinkProperty) {
        throw 'Use either -UseLinkHeader or -NextLinkProperty, not both.'
    }
    if (-not $UseLinkHeader -and -not $NextLinkProperty) {
        throw 'Say how to find the next page: -UseLinkHeader or -NextLinkProperty.'
    }

    $request = @{ MaxRetries = $MaxRetries }
    if ($Headers) { $request['Headers'] = $Headers }

    $next = $Uri
    $page = 0
    while ($next) {
        $page++
        if ($page -gt $MaxPages) {
            Write-Warning "Stopped after $MaxPages pages; there is more data."
            break
        }

        if ($UseLinkHeader) {
            $response = Invoke-PtRestRetry -Uri $next -Raw @request
            $body = $response.Content | ConvertFrom-Json
            $next = Get-PtNextLink -LinkHeader $response.Headers['Link']
        }
        else {
            $body = Invoke-PtRestRetry -Uri $next @request
            $next = $body.$NextLinkProperty
        }

        if ($ItemsProperty) { $items = @($body.$ItemsProperty) } else { $items = @($body) }
        foreach ($item in $items) {
            if ($null -ne $item) { $item }
        }
    }
}
