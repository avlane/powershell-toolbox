# Changelog

## 2.1.0 - 2026-09

- New: `Get-PtJiraWorklog`, `Get-PtSqlErrorLog`; `examples/New-JiraIssuesForLowDisks.ps1`.
- `Get-PtServiceTriage -OnlyFailed`; `Format-PtStatusSummary -GroupBy`.
- `Invoke-DailyReport.ps1` lets the configuration choose the checks.
- `Invoke-Tests.ps1 -Tag / -ExcludeTag`; the Windows-only tests are tagged.
- Fixed: `Get-PtBlockingSession` reported the wrong head blocker when a session in the
  middle of a chain had only just started to wait.
- Tests for `Get-PtBlockingSession`, `Get-PtDatabaseSpace`, `Get-PtSqlErrorLog`.

## 2.0.0 - 2026-01

- **Breaking:** requires PowerShell 7.4. PowerShell 7.2 left support in November 2024;
  1.4.0 is the last release for it.

## 1.4.0 - 2025-11

- New: `Get-PtWaitStats`, `Get-PtRebootHistory`, `Sync-PtFolder`,
  `Get-PtJiraIssueChangelog`, `Invoke-PtAzResourceGraph`.
- `Export-PtReport` writes JSON Lines.
- `Invoke-PtRestRetry -MaxTotalDelaySeconds`; `Find-PtJiraUser` remembers answers.
- Fixed: `Invoke-PtRestPaged` stopped after the first page of an API whose page size is
  smaller than the default; `-PageSize` is required in that case.
- Module-level tests (manifest, exports, help, parameters, verbs, `-WhatIf`);
  `docs/troubleshooting.md`; `.editorconfig`.

## 1.3.0 - 2024-12

- **Jira:** `Search-PtJiraIssue` uses the enhanced search endpoint
  (`/rest/api/3/search/jql`, page tokens); the old `/rest/api/3/search` is no longer
  used. The query must be bounded. New: `Add-PtJiraAttachment`.
- New: `Get-PtDatabaseGrowth`, `Export-PtScheduledTask`, `Import-PtScheduledTask`,
  `Get-PtAzureTagSummary`, `Get-PtSecretInfo`, `Remove-PtSecret`.
- `scripts/Invoke-DailyReport.ps1` with an example configuration;
  `Get-PtStatusSeverity` is public.
- `Get-PtDiskReport -IncludeMountPoints`; `Get-PtAgentJobReport` category and name
  filters; `Get-PtCertificateExpiry` reads remote computers in one call.
- Tests for the Jira date and issue converters.

## 1.2.0 - 2023-11

- New: `Get-PtBackupChain`, `Get-PtSqlServerInfo`, `Get-PtAzVmInventory`,
  `Get-PtAzSqlInventory`, `Test-PtTlsCertificate`, `New-PtJql`,
  `ConvertTo-PtMarkdownTable`.
- `Export-PtReport` writes Markdown.
- `Invoke-PtRestRetry` adds jitter to its back-off (`-NoJitter`); `Invoke-PtRestPaged`
  pages by offset or page number.
- `Get-PtServiceTriage -IncludeLastEvent`; `Get-PtEventLogSummary -BucketMinutes`
  (timeline); `Remove-PtOldFile -Recycle`.
- Fixed: `Get-PtAzSqlInventory` threw on a server whose minimum TLS version is `None`.
- CI uses `actions/checkout@v4`; Dependabot keeps the actions current.

## 1.1.0 - 2022-12

- New: `Find-PtJiraUser`, `New-PtJiraIssue`, `Add-PtJiraWorklog`, `Rename-PtFileBulk`.
- `Invoke-PtSqlQuery` queries instances in parallel, understands
  `-TrustServerCertificate` / `-Encrypt` and passes `-Credential` to newer
  `Invoke-Sqlcmd` versions.
- `Invoke-PtRestRetry` reads Retry-After given as an HTTP date.
- `Get-PtAgentJobReport -IncludeStepDetail`; `Get-PtScheduledTaskReport` flags
  `Overdue` tasks; `Get-PtCertificateExpiry` filters.
- `Export-PtReport`: `-Delimiter`, `-Encoding`, `-JsonDepth`, `-Compress`.
- CI: `scripts/Invoke-Lint.ps1`, test results kept as an artifact.

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
