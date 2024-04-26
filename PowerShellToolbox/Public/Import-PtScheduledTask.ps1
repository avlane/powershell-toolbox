function Import-PtScheduledTask {
    <#
    .SYNOPSIS
    Registers scheduled tasks from the XML files written by Export-PtScheduledTask.

    .DESCRIPTION
    Every .xml file below Path is registered with Register-ScheduledTask -Xml. The
    folders below Path give the task path (Ops\Nightly.xml becomes \Ops\Nightly) and
    the file name gives the task name. A task that already exists is left alone
    unless -Force is given. Tasks that run as a named account need -Credential, since
    the export does not contain passwords; tasks that run as SYSTEM or a group
    managed service account do not. Supports -WhatIf and -Confirm.

    .PARAMETER Path
    The folder with the XML files.

    .PARAMETER Credential
    The account password to register tasks with (applied to every task that has a
    user principal other than SYSTEM).

    .PARAMETER Force
    Replace tasks that already exist.

    .EXAMPLE
    Import-PtScheduledTask -Path D:\Backups\tasks\SQLPROD01 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [pscredential]$Credential,

        [switch]$Force
    )

    $root = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd('\', '/')

    foreach ($file in (Get-ChildItem -LiteralPath $root -Filter '*.xml' -File -Recurse | Sort-Object -Property FullName)) {
        $relativeFolder = $file.DirectoryName.Substring($root.Length).Trim('\', '/')
        $taskPath = $relativeFolder ? ('\' + ($relativeFolder -replace '/', '\') + '\') : '\'
        $taskName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

        $status = 'Registered'
        if ((Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue) -and -not $Force) {
            $status = 'SkippedExists'
        }
        elseif ($PSCmdlet.ShouldProcess("$taskPath$taskName", "Register from $($file.FullName)")) {
            try {
                $parameters = @{ TaskName = $taskName; TaskPath = $taskPath; Xml = (Get-Content -LiteralPath $file.FullName -Raw); Force = $true; ErrorAction = 'Stop' }
                if ($Credential) {
                    $parameters['User'] = $Credential.UserName
                    $parameters['Password'] = $Credential.GetNetworkCredential().Password
                }
                [void](Register-ScheduledTask @parameters)
            }
            catch {
                $status = 'Failed'
                Write-Warning "Could not register $taskPath$taskName : $($_.Exception.Message)"
            }
        }
        else {
            $status = 'Skipped'
        }

        [pscustomobject]@{
            TaskPath = $taskPath
            TaskName = $taskName
            File     = $file.FullName
            Status   = $status
        }
    }
}
