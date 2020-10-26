function Get-PtHttpErrorDetail {
    <#
    .SYNOPSIS
    Pulls the status code and Retry-After header out of a failed web request.

    .DESCRIPTION
    In Windows PowerShell 5.1 Invoke-RestMethod throws a WebException whose
    Response holds the HTTP details (PowerShell 7 throws an HttpRequestException
    without a response only when the connection itself fails). This returns them as a plain object so the
    retry logic (and its tests) do not have to dig through exception types.
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
        $header = $response.Headers['Retry-After']
        if ($header) { $retryAfter = [string]$header }
    }

    [pscustomobject]@{
        StatusCode     = $statusCode
        RetryAfter     = $retryAfter
        IsNetworkError = (($null -eq $response) -and ($exception -is [System.Net.WebException] -or $exception.GetType().FullName -eq 'System.Net.Http.HttpRequestException'))
        Message        = $exception.Message
    }
}
