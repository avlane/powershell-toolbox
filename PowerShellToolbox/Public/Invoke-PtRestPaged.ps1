function Invoke-PtRestPaged {
    <#
    .SYNOPSIS
    Reads every page of a paged REST API and returns the items one by one.

    .DESCRIPTION
    Calls the address with Invoke-PtRestRetry (so busy servers are retried), pulls
    the items out of each response and follows the link to the next page until
    there is none. Three ways of paging are supported:

      -UseLinkHeader      the Link: <...>; rel="next" header (GitHub, GitLab, ...)
      -NextLinkProperty   a property of the response body that holds the next address
                          (for example nextLink, or '@odata.nextLink' for Microsoft Graph)
      -OffsetParameter    the name of a query parameter that carries the position
                          (offset, start, page ...), together with -PageSize; paging
                          ends with the first page that has fewer items than a full
                          page

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

    .PARAMETER OffsetParameter
    The query parameter that carries the position. It is added to the address, which
    must not contain it already.

    .PARAMETER LimitParameter
    The query parameter that carries the page size, if the API has one (limit, per_page,
    pageSize ...). Sent together with -PageSize.

    .PARAMETER PageSize
    Items per page for offset paging. A page with fewer items ends the paging, so when
    the API sets the page size itself (no -LimitParameter) this must be given and must
    match it. Default 100 when -LimitParameter sends it to the API.

    .PARAMETER PageBased
    The position parameter is a page number starting at 1, not an item offset.

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

        [string]$OffsetParameter,

        [string]$LimitParameter,

        [ValidateRange(1, 100000)]
        [int]$PageSize = 100,

        [switch]$PageBased,

        [ValidateRange(1, 100000)]
        [int]$MaxPages = 1000,

        [ValidateRange(0, 20)]
        [int]$MaxRetries = 3
    )

    $modes = @($UseLinkHeader.IsPresent, [bool]$NextLinkProperty, [bool]$OffsetParameter) | Where-Object { $_ }
    if (@($modes).Count -gt 1) {
        throw 'Use only one of -UseLinkHeader, -NextLinkProperty and -OffsetParameter, not several.'
    }
    if (@($modes).Count -eq 0) {
        throw 'Say how to find the next page: -UseLinkHeader, -NextLinkProperty or -OffsetParameter.'
    }

    # Without -LimitParameter the API chooses the page size, and the default of 100 here
    # would be wrong for an API that returns 30 per page: paging would stop after the
    # first page, because it was "short". So the page size must be given explicitly.
    if ($OffsetParameter -and -not $LimitParameter -and -not $PSBoundParameters.ContainsKey('PageSize')) {
        throw 'The API chooses its own page size, so say how large its pages are with -PageSize (or name the parameter that sets it with -LimitParameter).'
    }

    $request = @{ MaxRetries = $MaxRetries }
    if ($Headers) { $request['Headers'] = $Headers }

    if ($OffsetParameter) {
        $position = $PageBased ? 1 : 0
        $page = 0
        while ($true) {
            $page++
            if ($page -gt $MaxPages) {
                Write-Warning "Stopped after $MaxPages pages; there may be more data."
                break
            }

            $pageUri = $Uri + ($Uri.Contains('?') ? '&' : '?') + [uri]::EscapeDataString($OffsetParameter) + '=' + $position
            if ($LimitParameter) { $pageUri = $pageUri + '&' + [uri]::EscapeDataString($LimitParameter) + '=' + $PageSize }

            $body = Invoke-PtRestRetry -Uri $pageUri @request
            $items = @(($ItemsProperty ? $body.$ItemsProperty : $body) | Where-Object { $null -ne $_ })
            foreach ($item in $items) { $item }

            if ($items.Count -lt $PageSize) { break }
            $position += $PageBased ? 1 : $items.Count
        }
        return
    }

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
