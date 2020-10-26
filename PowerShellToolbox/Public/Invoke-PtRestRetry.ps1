function Invoke-PtRestRetry {
    <#
    .SYNOPSIS
    Calls Invoke-RestMethod and tries again when the server is busy or unreachable.

    .DESCRIPTION
    Retries on network errors and on HTTP 429, 500, 502, 503 and 504, up to
    MaxRetries more times. Between tries it waits for the number of seconds in the
    Retry-After header when the server sent one, otherwise it backs off
    exponentially (2, 4, 8 ... seconds, at most 60). Other errors, for example 400,
    401 or 404, are thrown immediately because trying again cannot help.

    TLS 1.2 is switched on for the session, which Windows PowerShell 5.1 does not
    always do by default.

    On PowerShell 7 the HTTP status and headers are read from the response
    (-SkipHttpErrorCheck) instead of from an exception; on Windows PowerShell 5.1
    they come from the WebException.

    .PARAMETER Uri
    The address to call.

    .PARAMETER Method
    The HTTP method. Default Get.

    .PARAMETER Headers
    A hashtable of request headers.

    .PARAMETER Body
    The request body. A hashtable or object is sent as JSON; a string is sent as is.

    .PARAMETER MaxRetries
    How many times to retry after the first attempt. Default 3.

    .PARAMETER InitialDelaySeconds
    The first back-off delay. Default 2.

    .PARAMETER TimeoutSec
    Timeout of each attempt. Default 60.

    .PARAMETER Raw
    Return the web response (status, headers, content) from Invoke-WebRequest
    instead of the parsed body from Invoke-RestMethod. Needed to read headers such
    as Link.

    .EXAMPLE
    Invoke-PtRestRetry -Uri 'https://api.example.com/v1/items' -Headers @{ Authorization = 'Bearer abc' } -MaxRetries 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Uri,

        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [string]$Method = 'Get',

        [hashtable]$Headers,

        [object]$Body,

        [ValidateRange(0, 20)]
        [int]$MaxRetries = 3,

        [ValidateRange(1, 300)]
        [int]$InitialDelaySeconds = 2,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSec = 60,

        [switch]$Raw
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    # PowerShell 7 can hand back HTTP error responses instead of throwing, which
    # keeps the status code, headers and body of a 429 or 503 within easy reach
    $isCore = $PSVersionTable.PSVersion.Major -ge 7

    $parameters = @{ Uri = $Uri; Method = $Method; TimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
    if ($Headers) { $parameters['Headers'] = $Headers }
    if ($null -ne $Body) {
        if ($Body -is [string]) {
            $parameters['Body'] = $Body
        }
        else {
            $parameters['Body'] = ConvertTo-Json -InputObject $Body -Depth 10
            $parameters['ContentType'] = 'application/json'
        }
    }

    $command = 'Invoke-RestMethod'
    if ($Raw) {
        $command = 'Invoke-WebRequest'
        $parameters['UseBasicParsing'] = $true    # Windows PowerShell 5.1 would otherwise need Internet Explorer's engine
    }
    if ($isCore) {
        $parameters['SkipHttpErrorCheck'] = $true
        if (-not $Raw) {
            $parameters['StatusCodeVariable'] = 'statusCode'
            $parameters['ResponseHeadersVariable'] = 'responseHeaders'
        }
    }

    $retryableStatus = @(429, 500, 502, 503, 504)
    $attempt = 0
    while ($true) {
        $attempt++
        $detail = $null
        $caught = $null
        $statusCode = $null
        $responseHeaders = $null
        $result = $null

        try {
            $result = & $command @parameters

            if ($isCore) {
                if ($Raw) {
                    $statusCode = [int]$result.StatusCode
                    $responseHeaders = $result.Headers
                }
                if ($statusCode -ge 400) {
                    $retryAfter = $null
                    if ($responseHeaders -and $responseHeaders['Retry-After']) {
                        $retryAfter = [string](@($responseHeaders['Retry-After'])[0])
                    }
                    $detail = [pscustomobject]@{ StatusCode = $statusCode; RetryAfter = $retryAfter; IsNetworkError = $false; Message = "HTTP $statusCode" }
                }
            }
        }
        catch {
            $caught = $_
            $detail = Get-PtHttpErrorDetail -ErrorRecord $_
        }

        if (-not $detail) { return $result }

        $retryable = $detail.IsNetworkError -or ($retryableStatus -contains $detail.StatusCode)
        if (-not $retryable -or $attempt -gt $MaxRetries) {
            if ($caught) { throw $caught }
            $text = if ($result -is [string]) { $result } elseif ($Raw) { [string]$result.Content } else { ConvertTo-Json -InputObject $result -Depth 3 -Compress }
            if ($text.Length -gt 500) { $text = $text.Substring(0, 500) }
            throw "$($detail.Message) from $Uri : $text"
        }

        $delay = [math]::Min(60, $InitialDelaySeconds * [math]::Pow(2, $attempt - 1))
        if ($detail.RetryAfter -match '^\d+$') { $delay = [int]$detail.RetryAfter }

        Write-Verbose "Attempt $attempt of $($MaxRetries + 1) failed ($($detail.Message)); waiting $delay seconds."
        Start-Sleep -Seconds $delay
    }
}
