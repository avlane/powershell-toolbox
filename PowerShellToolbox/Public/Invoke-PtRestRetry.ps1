function Invoke-PtRestRetry {
    <#
    .SYNOPSIS
    Calls Invoke-RestMethod and tries again when the server is busy or unreachable.

    .DESCRIPTION
    Retries on network errors and on HTTP 429, 500, 502, 503 and 504, up to
    MaxRetries more times. Between tries it waits as long as the Retry-After header
    says when the server sent one (as seconds or as an HTTP date, but never more than
    five minutes), otherwise it backs off
    exponentially (2, 4, 8 ... seconds, at most 60). Other errors, for example 400,
    401 or 404, are thrown immediately because trying again cannot help.

    The HTTP status and headers are read from the response (-SkipHttpErrorCheck)
    rather than from an exception. Connection failures and timeouts still arrive as
    exceptions and are retried.

    .PARAMETER Uri
    The address to call.

    .PARAMETER Method
    The HTTP method. Default Get.

    .PARAMETER Headers
    A hashtable of request headers.

    .PARAMETER Body
    The request body. A hashtable or object is sent as JSON; a string is sent as is.

    .PARAMETER Form
    A hashtable for a multipart/form-data upload, for example @{ file = Get-Item .\x.pdf }.
    FileInfo values are sent as files. Cannot be combined with -Body.

    .PARAMETER MaxRetries
    How many times to retry after the first attempt. Default 3.

    .PARAMETER InitialDelaySeconds
    The first back-off delay. Default 2.

    .PARAMETER TimeoutSec
    Timeout of each attempt. Default 60.

    .PARAMETER NoJitter
    By default each back-off delay is varied randomly by up to 25 percent either way,
    so that many clients that failed together do not all retry at the same instant.
    -NoJitter turns that off. A delay taken from Retry-After is never changed.

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

        [hashtable]$Form,

        [ValidateRange(0, 20)]
        [int]$MaxRetries = 3,

        [ValidateRange(1, 300)]
        [int]$InitialDelaySeconds = 2,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSec = 60,

        [switch]$NoJitter,

        [switch]$Raw
    )

    # HTTP error responses are handed back instead of thrown (-SkipHttpErrorCheck), so
    # the status code, the Retry-After header and the body of a 429 or 503 are at hand
    $parameters = @{ Uri = $Uri; Method = $Method; TimeoutSec = $TimeoutSec; ErrorAction = 'Stop'; SkipHttpErrorCheck = $true }
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

    if ($Form) {
        if ($null -ne $Body) { throw 'Use either -Body or -Form, not both.' }
        $parameters['Form'] = $Form
    }

    $command = 'Invoke-RestMethod'
    if ($Raw) {
        $command = 'Invoke-WebRequest'
    }
    else {
        $parameters['StatusCodeVariable'] = 'statusCode'
        $parameters['ResponseHeadersVariable'] = 'responseHeaders'
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

        $retryAfter = ConvertFrom-PtRetryAfter -Value $detail.RetryAfter
        if ($null -ne $retryAfter) {
            $delay = $retryAfter
        }
        else {
            $delay = [math]::Min(60, $InitialDelaySeconds * [math]::Pow(2, $attempt - 1))
            if (-not $NoJitter) { $delay = [math]::Round($delay * (0.75 + (Get-Random -Minimum 0.0 -Maximum 0.5)), 1) }
        }

        Write-Verbose "Attempt $attempt of $($MaxRetries + 1) failed ($($detail.Message)); waiting $delay seconds."
        Start-Sleep -Seconds $delay
    }
}
