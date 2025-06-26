@{
    RootModule        = 'PowerShellToolbox.psm1'
    ModuleVersion     = '1.3.0'
    GUID              = 'cdab71a9-142c-4649-aea1-2bf48a32a9c1'
    Author            = 'Avery Lane'
    Copyright         = '(c) 2019 Avery Lane. MIT License.'
    Description       = 'Small admin helpers: disk, certificate, service, event log and scheduled task reports; SQL Server backup, restore, Agent job, space and blocking status; REST and Jira Cloud helpers; safe file cleanup.'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Add-PtJiraAttachment',
        'Add-PtJiraComment',
        'Add-PtJiraWorklog',
        'Compress-PtOldFile',
        'Connect-PtJira',
        'ConvertTo-PtMarkdownTable',
        'Copy-PtFileSafe',
        'Export-PtReport',
        'Export-PtScheduledTask',
        'Find-PtJiraUser',
        'Format-PtStatusSummary',
        'Get-PtAgentJobReport',
        'Get-PtAzSqlInventory',
        'Get-PtAzureInventory',
        'Get-PtAzureTagSummary',
        'Get-PtAzVmInventory',
        'Get-PtBackupChain',
        'Get-PtBackupStatus',
        'Get-PtBlockingSession',
        'Get-PtCertificateExpiry',
        'Get-PtDatabaseGrowth',
        'Get-PtDatabaseSpace',
        'Get-PtDiskReport',
        'Get-PtEventLogSummary',
        'Get-PtJiraIssue',
        'Get-PtJiraIssueChangelog',
        'Get-PtJiraTransition',
        'Get-PtLongRunningQuery',
        'Get-PtRebootHistory',
        'Get-PtRestoreStatus',
        'Get-PtScheduledTaskReport',
        'Get-PtSecret',
        'Get-PtSecretInfo',
        'Get-PtServiceTriage',
        'Get-PtSqlServerInfo',
        'Get-PtStatusSeverity',
        'Get-PtWaitStats',
        'Import-PtScheduledTask',
        'Initialize-PtVault',
        'Invoke-PtAzResourceGraph',
        'Invoke-PtJiraRequest',
        'Invoke-PtJiraTransition',
        'Invoke-PtRestPaged',
        'Invoke-PtRestRetry',
        'Invoke-PtSqlQuery',
        'New-PtJiraIssue',
        'New-PtJql',
        'Register-PtMaintenanceTask',
        'Remove-PtOldFile',
        'Remove-PtSecret',
        'Rename-PtFileBulk',
        'Restart-PtFailedService',
        'Search-PtJiraIssue',
        'Set-PtSecret',
        'Sync-PtFolder',
        'Test-PtTlsCertificate'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('SQLServer', 'Admin', 'Monitoring', 'Jira', 'Azure', 'Windows')
            ReleaseNotes = 'See CHANGELOG.md in the repository.'
        }
    }
}
