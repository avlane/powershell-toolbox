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
| **Servers and Windows** | |
| `Get-PtDiskReport` | free space of fixed disks, flags low ones (parallel over computers) |
| `Get-PtServiceTriage` | automatic services that are not running |
| `Restart-PtFailedService` | start such services through CIM and wait for them (`-WhatIf` aware) |
| `Get-PtEventLogSummary` | errors and warnings grouped by provider and event id |
| `Get-PtCertificateExpiry` | certificates in a store with days until expiry |
| `Get-PtScheduledTaskReport` | scheduled tasks with last result and a status (Failed, Overdue, ...) |
| `Register-PtMaintenanceTask` | create a daily/weekly scheduled task for a script |
| **SQL Server** | |
| `Invoke-PtSqlQuery` | run T-SQL on several instances (in parallel), get plain objects back |
| `Get-PtBackupStatus` | last full, differential and log backup per database, with a verdict |
| `Get-PtRestoreStatus` | running restores and restore history |
| `Get-PtAgentJobReport` | Agent jobs: last result, next run, recent failures, failed step |
| `Get-PtDatabaseSpace` | file sizes, growth settings, volume free space |
| `Get-PtBlockingSession` | blocked requests, chains and head blockers |
| `Get-PtLongRunningQuery` | user requests that have run for a while |
| **Files** | |
| `Remove-PtOldFile` | delete old files with `-WhatIf` / `-Confirm` support |
| `Compress-PtOldFile` | zip old files one by one, remove the original after a check |
| `Copy-PtFileSafe` | copy or move with a hash check before the final rename |
| `Rename-PtFileBulk` | regex renames that refuse collisions |
| **REST and Jira Cloud** | |
| `Invoke-PtRestRetry` | `Invoke-RestMethod` with retries, back-off and Retry-After |
| `Invoke-PtRestPaged` | follow a Link header or a next-link property through all pages |
| `Connect-PtJira`, `Invoke-PtJiraRequest` | sign in with an API token; raw API calls |
| `Search-PtJiraIssue`, `Get-PtJiraIssue` | JQL search and single issues as flat objects |
| `New-PtJiraIssue`, `Add-PtJiraComment`, `Add-PtJiraWorklog` | create issues, comment, log time |
| `Get-PtJiraTransition`, `Invoke-PtJiraTransition` | move issues through the workflow |
| `Find-PtJiraUser` | find account ids by name or e-mail |
| **Azure, secrets and output** | |
| `Get-PtAzureInventory` | resources and tags per subscription (Az), missing required tags |
| `Initialize-PtVault`, `Set-PtSecret`, `Get-PtSecret` | SecretManagement / SecretStore helpers |
| `Export-PtReport` | write objects to CSV, JSON or HTML |
| `Format-PtStatusSummary` | "OK: 12, Low: 2, Failed: 1" for any report |

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
