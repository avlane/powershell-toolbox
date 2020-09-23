function Get-PtJiraTransition {
    <#
    .SYNOPSIS
    Lists the workflow transitions available for an issue right now.

    .DESCRIPTION
    Which transitions exist depends on the issue's current status and the project's
    workflow. Returns the id, the name of the transition and the status it leads to.

    .PARAMETER Key
    The issue key, for example OPS-123.

    .EXAMPLE
    Get-PtJiraTransition OPS-123
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key
    )

    process {
        $response = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key/transitions"
        foreach ($transition in @($response.transitions)) {
            [pscustomobject]@{
                Key      = $Key
                Id       = $transition.id
                Name     = $transition.name
                ToStatus = $transition.to.name
            }
        }
    }
}
