function Get-PtHttpErrorDetail {
    <#
    .SYNOPSIS
    Describes an exception thrown by Invoke-RestMethod or Invoke-WebRequest for the retry logic.

    .DESCRIPTION
    With -SkipHttpErrorCheck HTTP error responses do not throw, so what arrives here
    is a connection-level failure: a refused or reset connection, a DNS failure or
    a timeout. Those are reported with IsNetworkError set. If the exception does
    carry a response (an HttpResponseException) its status code and Retry-After
    header are returned as well. The result is a plain object so the retry logic and
    its tests do not have to dig through exception types.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    $statusCode = $null
    $retryAfter = $null

    $response = $exception.Response
    if ($response) {
        $statusCode = [int]$response.StatusCode
        $values = $null
        if ($response.Headers.TryGetValues('Retry-After', [ref]$values)) { $retryAfter = [string]@($values)[0] }
    }

    $networkTypes = @(
        'System.Net.Http.HttpRequestException'
        'System.Threading.Tasks.TaskCanceledException'
        'System.Net.Sockets.SocketException'
        'System.IO.IOException'
    )
    $typeNames = @($exception.GetType().FullName)
    if ($exception.InnerException) { $typeNames += $exception.InnerException.GetType().FullName }

    [pscustomobject]@{
        StatusCode     = $statusCode
        RetryAfter     = $retryAfter
        IsNetworkError = (($null -eq $response) -and (@($typeNames | Where-Object { $networkTypes -contains $_ }).Count -gt 0))
        Message        = $exception.Message
    }
}
