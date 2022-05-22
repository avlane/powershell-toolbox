function Add-PtJiraWorklog {
    <#
    .SYNOPSIS
    Logs time on a Jira issue.

    .DESCRIPTION
    Needs Connect-PtJira first. The time is written the way Jira does, for example
    '2h 30m' or '1d'. The start time defaults to now and is sent in the format the
    API insists on (offset without a colon). An optional comment is sent as an
    Atlassian Document Format document. Supports -WhatIf and -Confirm.

    .PARAMETER Key
    The issue key, for example OPS-123.

    .PARAMETER TimeSpent
    The time as weeks, days, hours and minutes: 1w, 2d, 3h, 45m, or a combination
    such as '1h 30m'. What a day or a week is depends on the Jira time tracking
    settings.

    .PARAMETER Started
    When the work started. Default: now.

    .PARAMETER Comment
    A note for the worklog.

    .EXAMPLE
    Add-PtJiraWorklog -Key OPS-123 -TimeSpent '45m' -Comment 'Extended the volume and re-ran the disk report.'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidatePattern('^\d+[wdhm]( \d+[wdhm])*$')]
        [string]$TimeSpent,

        [datetimeoffset]$Started = [datetimeoffset]::Now,

        [string]$Comment
    )

    process {
        # Jira wants 2022-05-22T09:00:00.000+0200, not +02:00
        $startedText = $Started.ToString("yyyy-MM-dd'T'HH:mm:ss.fffzzz") -replace '([+-]\d{2}):(\d{2})$', '$1$2'

        $body = @{ timeSpent = $TimeSpent; started = $startedText }
        if ($Comment) { $body['comment'] = ConvertTo-PtAdf -Text $Comment }

        if ($PSCmdlet.ShouldProcess($Key, "Log $TimeSpent starting $startedText")) {
            $response = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key/worklog" -Method Post -Body $body
            [pscustomobject]@{
                Key         = $Key
                WorklogId   = $response.id
                TimeSpent   = $response.timeSpent
                Started     = ConvertFrom-PtJiraDate -Text $response.started
            }
        }
    }
}
