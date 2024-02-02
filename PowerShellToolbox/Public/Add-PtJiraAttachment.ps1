function Add-PtJiraAttachment {
    <#
    .SYNOPSIS
    Attaches one or more files to a Jira issue.

    .DESCRIPTION
    Needs Connect-PtJira first. Each file is uploaded as multipart/form-data with the
    X-Atlassian-Token: no-check header that the API requires for attachments. Jira
    limits attachment size (10 MB by default, set by the site administrator); files
    larger than -MaxSizeMB are refused before anything is sent. Supports -WhatIf and
    -Confirm.

    .PARAMETER Key
    The issue key, for example OPS-123.

    .PARAMETER Path
    The files to attach.

    .PARAMETER MaxSizeMB
    Refuse files larger than this. Default 10.

    .EXAMPLE
    Get-PtBackupStatus -ServerInstance SQLPROD01 | Export-PtReport -Path .\backups.html | Add-PtJiraAttachment -Key OPS-123
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('IssueKey')]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]+-\d+$')]
        [string]$Key,

        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [ValidateRange(1, 1024)]
        [int]$MaxSizeMB = 10
    )

    process {
        foreach ($file in $Path) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                Write-Error "The file $file does not exist."
                continue
            }
            $info = Get-Item -LiteralPath $file
            if ($info.Length -gt $MaxSizeMB * 1MB) {
                Write-Error "$($info.Name) is $([math]::Round($info.Length / 1MB, 1)) MB, more than the limit of $MaxSizeMB MB."
                continue
            }
            if ($info.Length -eq 0) {
                Write-Error "$($info.Name) is empty; Jira refuses empty attachments."
                continue
            }

            if ($PSCmdlet.ShouldProcess($Key, "Attach $($info.Name)")) {
                $response = Invoke-PtJiraRequest -Path "/rest/api/3/issue/$Key/attachments" -Method Post -Form @{ file = $info } -Headers @{ 'X-Atlassian-Token' = 'no-check' }
                foreach ($attachment in @($response)) {
                    [pscustomobject]@{
                        Key          = $Key
                        AttachmentId = $attachment.id
                        FileName     = $attachment.filename
                        SizeKB       = [math]::Round($attachment.size / 1KB, 1)
                        MimeType     = $attachment.mimeType
                    }
                }
            }
        }
    }
}
