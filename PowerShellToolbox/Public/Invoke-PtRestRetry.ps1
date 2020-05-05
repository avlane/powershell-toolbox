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
        [int]$TimeoutSec = 60
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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

    $retryableStatus = @(429, 500, 502, 503, 504)
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return Invoke-RestMethod @parameters
        }
        catch {
            $detail = Get-PtHttpErrorDetail -ErrorRecord $_
            $retryable = $detail.IsNetworkError -or ($retryableStatus -contains $detail.StatusCode)
            if (-not $retryable -or $attempt -gt $MaxRetries) { throw }

            $delay = [math]::Min(60, $InitialDelaySeconds * [math]::Pow(2, $attempt - 1))
            if ($detail.RetryAfter -match '^\d+$') { $delay = [int]$detail.RetryAfter }

            Write-Verbose "Attempt $attempt of $($MaxRetries + 1) failed ($($detail.Message)); waiting $delay seconds."
            Start-Sleep -Seconds $delay
        }
    }
}
