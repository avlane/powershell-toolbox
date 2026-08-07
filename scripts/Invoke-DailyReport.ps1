<#
.SYNOPSIS
Runs the daily health checks from a JSON configuration and writes one HTML report per check.

.DESCRIPTION
Meant to be run by a scheduled task (see Register-PtMaintenanceTask). For the SQL
Server instances, computers and certificates named in the configuration file it
runs Get-PtBackupStatus, Get-PtAgentJobReport, Get-PtDiskReport and
Get-PtCertificateExpiry, writes each result as HTML into <outputFolder>\yyyy-MM-dd\,
prints a one-line summary per check and, if the configuration has a "jira" section,
adds the summary as a comment on the given issue.

The exit code is 0 when everything is OK and 1 when any check found a problem, so a
scheduler can alert on it. Supports -WhatIf: the checks still run, but no file is
written and no comment is posted.

The configuration is a JSON file, see examples\daily-report.json:

  servers      SQL Server instances for the backup, Agent job and database space checks
  computers    computers for the disk, certificate and scheduled task checks
  outputFolder where the daily folders are created
  checks       optional: which checks to run, from Backups, AgentJobs, DatabaseSpace,
               Disks, Certs and Tasks. Default: Backups, AgentJobs, Disks and Certs.
  jira         optional: baseUri, issueKey and secretName (a PSCredential stored with
               Set-PtSecret: e-mail address and API token)

.PARAMETER ConfigPath
The JSON configuration file.

.EXAMPLE
./scripts/Invoke-DailyReport.ps1 -ConfigPath .\examples\daily-report.json -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigPath
)

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Join-Path $root 'PowerShellToolbox') 'PowerShellToolbox.psd1') -Force -ErrorAction Stop

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($required in 'servers', 'computers', 'outputFolder') {
    if (-not $config.$required) { throw "The configuration file has no '$required' entry." }
}

$day = Get-Date -Format 'yyyy-MM-dd'
$folder = Join-Path $config.outputFolder $day

$available = [ordered]@{
    'Backups'       = { Get-PtBackupStatus -ServerInstance @($config.servers) }
    'AgentJobs'     = { Get-PtAgentJobReport -ServerInstance @($config.servers) -OnlyProblems }
    'DatabaseSpace' = { Get-PtDatabaseSpace -ServerInstance @($config.servers) }
    'Disks'         = { Get-PtDiskReport -ComputerName @($config.computers) -IncludeMountPoints }
    'Certs'         = { Get-PtCertificateExpiry -ComputerName @($config.computers) -OnlyProblems }
    'Tasks'         = { Get-PtScheduledTaskReport -OnlyProblems }
}

$wanted = $config.checks ? @($config.checks) : @('Backups', 'AgentJobs', 'Disks', 'Certs')
$unknown = @($wanted | Where-Object { -not $available.Contains($_) })
if ($unknown.Count -gt 0) { throw "Unknown check(s) in the configuration: $($unknown -join ', '). Available: $($available.Keys -join ', ')." }

$checks = [ordered]@{}
foreach ($name in $available.Keys) {
    if ($wanted -contains $name) { $checks[$name] = $available[$name] }
}

$summary = New-Object -TypeName 'System.Collections.Generic.List[string]'
$problems = 0
foreach ($name in $checks.Keys) {
    try {
        $rows = @(& $checks[$name])
    }
    catch {
        $summary.Add("${name}: the check failed: $($_.Exception.Message)")
        $problems++
        continue
    }

    $notOk = @($rows | Where-Object { (Get-PtStatusSeverity -Status ([string]($_.Status ?? $_.Verdict))) -in 'warn', 'bad' })
    $summary.Add("${name}: " + ($rows | Format-PtStatusSummary -Color Never))
    $problems += $notOk.Count

    $rows | Export-PtReport -Path (Join-Path $folder "$name.html") -Title "$name $day" -WhatIf:$WhatIfPreference | Out-Null
}

$summary | ForEach-Object { Write-Output $_ }

if ($config.jira -and $PSCmdlet.ShouldProcess("$($config.jira.issueKey)", 'Post the daily summary as a comment')) {
    Connect-PtJira -BaseUri $config.jira.baseUri -SecretName $config.jira.secretName | Out-Null
    Add-PtJiraComment -Key $config.jira.issueKey -Body ("Daily report $day`n" + ($summary -join "`n")) -Confirm:$false | Out-Null
}

exit ($problems -gt 0 ? 1 : 0)
