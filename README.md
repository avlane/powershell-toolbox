# powershell-toolbox

A PowerShell module of small admin helpers: disk and certificate reports,
service and event log triage, SQL Server backup status, a REST helper with
retries, an Azure inventory and a safe old-file cleaner.

## Requirements

- Windows PowerShell 5.1 (the commands use WMI, the event log, the certificate
  provider and similar Windows features).
- For the SQL commands: the `SqlServer` module (`Install-Module SqlServer`).
- For `Get-PtAzureInventory`: the `AzureRM` module and a signed-in session.
- For the tests: Pester 4 (`Install-Module Pester -RequiredVersion 4.10.1`).

## Using it

```powershell
Import-Module .\PowerShellToolbox\PowerShellToolbox.psd1

Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 | Where-Object Status -ne 'OK'
Get-PtBackupStatus -ServerInstance SQLPROD01 | Export-PtReport -Path .\backups.html -Title 'Backups'
Remove-PtOldFile -Path D:\Backups\Sales -Filter *.bak -OlderThanDays 14 -WhatIf
```

Every command has comment-based help: `Get-Help Get-PtDiskReport -Full`.

| command | what it does |
| --- | --- |
| `Get-PtDiskReport` | free space of fixed disks, flags low ones |
| `Get-PtServiceTriage` | automatic services that are not running |
| `Get-PtEventLogSummary` | errors and warnings grouped by provider and event id |
| `Invoke-PtSqlQuery` | run T-SQL on several instances, get plain objects back |
| `Get-PtBackupStatus` | last full, differential and log backup per database, with a verdict |
| `Get-PtCertificateExpiry` | certificates in a store with days until expiry |
| `Get-PtAzureInventory` | resources and tags per subscription (AzureRM) |
| `Remove-PtOldFile` | delete old files with `-WhatIf` / `-Confirm` support |
| `Export-PtReport` | write objects to CSV, JSON or HTML |
| `Invoke-PtRestRetry` | `Invoke-RestMethod` with retries, back-off and Retry-After |

## Tests

```powershell
Invoke-Pester .\tests
```

The tests mock the commands that talk to other machines (`Get-WmiObject`,
`Invoke-Sqlcmd`) and use `TestDrive` for file operations. They are written for
Pester 4.

Lint settings for PSScriptAnalyzer are in `PSScriptAnalyzerSettings.psd1`.
