# Changelog

## 1.0.0 - 2022-02

- **Breaking:** requires PowerShell 7.2 or later; Windows PowerShell 5.1 is no
  longer supported (0.3.0 is the last release that supports it).
- `Invoke-PtRestRetry` always reads status and headers from the response; the
  TLS 1.2 switch and the WebException handling are gone.
- `Get-PtDiskReport` queries in parallel whenever there is more than one computer.
- `Compress-PtOldFile` no longer has the 2 GB limit of the old Compress-Archive.
- `Register-PtMaintenanceTask` runs scripts with `pwsh.exe` by default
  (`-PowerShellPath`).
- New: `Get-PtLongRunningQuery`.

## 0.3.0 - 2021-10

- SQL Server: `Get-PtDatabaseSpace`, `Get-PtBlockingSession`.
- Files: `Copy-PtFileSafe` (hash-verified copy or move), `Compress-PtOldFile`.
- Services: `Restart-PtFailedService` (CIM, `-WhatIf` aware).
- Secrets: `Initialize-PtVault`, `Set-PtSecret`, `Get-PtSecret` on top of
  SecretManagement; `Connect-PtJira -SecretName`.
- `Get-PtAzureInventory -RequiredTag` reports resources missing mandatory tags.
- `Export-PtReport` colours HTML rows by `Status` or `Verdict`.
- Fixed: `Get-PtEventLogSummary` warned about logs without matching events.
- Fixed: `Connect-PtJira` failed with a conversion error for a non-credential secret.
- Tests for most commands; manifest metadata.

## 0.2.0 - 2020-05

- The module is split into `Public/` and `Private/`, one function per file.
- CIM instead of WMI; `Get-PtDiskReport` queries in parallel on PowerShell 7.
- New: `Get-PtAgentJobReport`, `Get-PtRestoreStatus`, `Get-PtScheduledTaskReport`,
  `Register-PtMaintenanceTask`, `Invoke-PtRestPaged`, Jira Cloud commands.
- `Get-PtAzureInventory` moved from AzureRM to Az.
- Tests migrated to Pester 5; CI workflow.

## 0.1.0 - 2019

- Disk, service, event log, certificate, backup status, Azure inventory, old file
  cleanup, report export, REST with retries.
- Fixed: `Get-PtDiskReport` produced wrong numbers for volumes without a size.
