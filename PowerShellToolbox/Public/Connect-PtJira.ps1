function Connect-PtJira {
    <#
    .SYNOPSIS
    Stores the address and API token of a Jira Cloud site for the other Jira commands.

    .DESCRIPTION
    Jira Cloud accepts basic authentication with the account's e-mail address as the
    user name and an API token as the password (create one at
    https://id.atlassian.com/manage-profile/security/api-tokens). Pass them as a
    credential, or use -FromEnvironment to read JIRA_EMAIL and JIRA_API_TOKEN, which
    keeps the token out of scripts and shell history.

    The connection is kept in memory for the current session only. The command
    checks it by calling /rest/api/3/myself, and returns the signed-in user (the
    token itself is never returned or written anywhere).

    .PARAMETER BaseUri
    The site, for example https://example.atlassian.net

    .PARAMETER Credential
    User name = the account's e-mail address, password = the API token.

    .PARAMETER FromEnvironment
    Read JIRA_EMAIL and JIRA_API_TOKEN from the environment.

    .PARAMETER SkipValidation
    Do not call Jira to check the credentials.

    .EXAMPLE
    Connect-PtJira -BaseUri https://example.atlassian.net -FromEnvironment

    .EXAMPLE
    $token = Read-Host -AsSecureString 'API token'
    Connect-PtJira https://example.atlassian.net -Credential (New-Object pscredential 'avery@example.com', $token)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^https://[A-Za-z0-9-]+\.atlassian\.net/?$')]
        [string]$BaseUri,

        [Parameter(Mandatory = $true, ParameterSetName = 'Credential')]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true, ParameterSetName = 'Environment')]
        [switch]$FromEnvironment,

        [switch]$SkipValidation
    )

    if ($FromEnvironment) {
        if (-not $env:JIRA_EMAIL -or -not $env:JIRA_API_TOKEN) {
            throw 'JIRA_EMAIL and JIRA_API_TOKEN must both be set in the environment.'
        }
        $email = $env:JIRA_EMAIL
        $token = $env:JIRA_API_TOKEN
    }
    else {
        $email = $Credential.UserName
        $token = $Credential.GetNetworkCredential().Password
    }

    # ${email} because "$email:" would be read as a variable in a scope called email
    $pair = [System.Text.Encoding]::UTF8.GetBytes("${email}:${token}")
    $script:PtJira = @{
        BaseUri = $BaseUri.TrimEnd('/')
        Email   = $email
        Headers = @{
            Authorization = 'Basic ' + [Convert]::ToBase64String($pair)
            Accept        = 'application/json'
        }
    }

    if ($SkipValidation) {
        return [pscustomobject]@{ BaseUri = $script:PtJira.BaseUri; Email = $email; AccountId = $null; DisplayName = $null }
    }

    try {
        $me = Invoke-PtJiraRequest -Path '/rest/api/3/myself'
    }
    catch {
        $script:PtJira = $null
        throw "Could not sign in to $BaseUri as $email : $($_.Exception.Message)"
    }

    [pscustomobject]@{
        BaseUri     = $script:PtJira.BaseUri
        Email       = $email
        AccountId   = $me.accountId
        DisplayName = $me.displayName
    }
}
