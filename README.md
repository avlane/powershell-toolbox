# powershell-toolbox

A PowerShell module of small admin helpers: disk and certificate reports,
service, event log and scheduled task triage, SQL Server backup, restore and
Agent job status, REST helpers with retries and paging, Jira Cloud commands, an
Azure inventory and a safe old-file cleaner.

## Requirements

- PowerShell 7.2 or later on Windows (the commands use CIM, the event log, the
  certificate provider and similar Windows features). Remote CIM queries need WinRM
  on the target computers. Version 0.3.0 was the last to support Windows PowerShell 5.1.
- For the SQL commands: the `SqlServer` module (`Install-Module SqlServer`).
- For the Jira commands: a Jira Cloud site and an API token.
- For `Get-PtAzureInventory`: the `Az` module and a signed-in session (`Connect-AzAccount`).
- For the tests: Pester 5 (`Install-Module Pester -MinimumVersion 5.0.0 -SkipPublisherCheck`).

## Using it

```powershell
Import-Module .\PowerShellToolbox\PowerShellToolbox.psd1

Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 | Where-Object Status -ne 'OK'
Get-PtBackupStatus -ServerInstance SQLPROD01 | Export-PtReport -Path .\backups.html -Title 'Backups'
Remove-PtOldFile -Path D:\Backups\Sales -Filter *.bak -OlderThanDays 14 -WhatIf
```

Jira Cloud (API token from <https://id.atlassian.com/manage-profile/security/api-tokens>):

```powershell
$env:JIRA_EMAIL = 'avery@example.com'; $env:JIRA_API_TOKEN = '...'
Connect-PtJira -BaseUri https://example.atlassian.net -FromEnvironment
Search-PtJiraIssue 'project = OPS AND resolution = Unresolved ORDER BY updated DESC' -First 20
Invoke-PtJiraTransition -Key OPS-123 -Transition 'Done' -Comment 'Fixed.' -WhatIf
```

Every command has comment-based help: `Get-Help Get-PtDiskReport -Full`.

| command | what it does |
| --- | --- |
| `Get-PtDiskReport` | free space of fixed disks, flags low ones |
| `Get-PtServiceTriage` | automatic services that are not running |
| `Get-PtEventLogSummary` | errors and warnings grouped by provider and event id |
| `Invoke-PtSqlQuery` | run T-SQL on several instances, get plain objects back |
| `Get-PtBackupStatus` | last full, differential and log backup per database, with a verdict |
| `Get-PtAgentJobReport` | SQL Server Agent jobs: last result, next run, recent failures |
| `Get-PtRestoreStatus` | running restores and restore history |
| `Get-PtScheduledTaskReport` | scheduled tasks with last result and a status |
| `Register-PtMaintenanceTask` | create a daily/weekly scheduled task for a script (`-WhatIf` aware) |
| `Get-PtCertificateExpiry` | certificates in a store with days until expiry |
| `Get-PtAzureInventory` | resources and tags per subscription (Az) |
| `Remove-PtOldFile` | delete old files with `-WhatIf` / `-Confirm` support |
| `Export-PtReport` | write objects to CSV, JSON or HTML |
| `Invoke-PtRestRetry` | `Invoke-RestMethod` with retries, back-off and Retry-After |
| `Invoke-PtRestPaged` | follow a Link header or a next-link property through all pages |
| `Connect-PtJira`, `Invoke-PtJiraRequest` | sign in to Jira Cloud with an API token; raw API calls |
| `Search-PtJiraIssue`, `Get-PtJiraIssue` | JQL search and single issues as flat objects |
| `Add-PtJiraComment`, `Get-PtJiraTransition`, `Invoke-PtJiraTransition` | comment on and move issues |

## Tests

```powershell
Invoke-Pester .\tests
```

The tests mock the commands that talk to other machines (`Get-CimInstance`,
`Invoke-Sqlcmd`) and use `TestDrive` for file operations. They are written for
Pester 5.

`./scripts/Invoke-Tests.ps1` runs them with a CI configuration (NUnit results,
optional `-Coverage`).

Lint settings for PSScriptAnalyzer are in `PSScriptAnalyzerSettings.psd1`.

## Layout

```
PowerShellToolbox/         the module (loader .psm1, manifest .psd1)
  Public/                  one file per exported command
  Private/                 internal helpers
tests/                     Pester 5 tests
scripts/Invoke-Tests.ps1   CI test runner
.github/workflows/         tests on PowerShell 7 and PSScriptAnalyzer
```
