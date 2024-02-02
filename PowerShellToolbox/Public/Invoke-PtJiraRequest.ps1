function Invoke-PtJiraRequest {
    <#
    .SYNOPSIS
    Calls the Jira Cloud REST API with the connection made by Connect-PtJira.

    .DESCRIPTION
    Adds the site address and authentication, builds the query string (values are
    URL-encoded) and goes through Invoke-PtRestRetry, so rate limiting (HTTP 429)
    and short outages are retried. Returns the parsed response.

    .PARAMETER Path
    The path below the site, for example /rest/api/3/issue/ABC-1

    .PARAMETER Method
    The HTTP method. Default Get.

    .PARAMETER Query
    A hashtable of query string parameters.

    .PARAMETER Body
    A hashtable or object that is sent as JSON.

    .PARAMETER Form
    A hashtable for a multipart/form-data upload (attachments).

    .PARAMETER Headers
    Extra request headers; they are added to the authentication headers.

    .EXAMPLE
    Invoke-PtJiraRequest -Path /rest/api/3/issue/ABC-1 -Query @{ fields = 'summary,status' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^/')]
        [string]$Path,

        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string]$Method = 'Get',

        [hashtable]$Query,

        [object]$Body,

        [hashtable]$Form,

        [hashtable]$Headers
    )

    if (-not $script:PtJira) {
        throw 'Not connected to Jira. Run Connect-PtJira first.'
    }

    $uri = $script:PtJira.BaseUri + $Path
    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($key in ($Query.Keys | Sort-Object)) {
            '{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$Query[$key])
        }
        $uri = $uri + '?' + ($pairs -join '&')
    }

    $allHeaders = $script:PtJira.Headers.Clone()
    foreach ($key in @($Headers.Keys)) { $allHeaders[$key] = $Headers[$key] }

    $parameters = @{ Uri = $uri; Method = $Method; Headers = $allHeaders }
    if ($null -ne $Body) { $parameters['Body'] = $Body }
    if ($Form) { $parameters['Form'] = $Form }

    Invoke-PtRestRetry @parameters
}
