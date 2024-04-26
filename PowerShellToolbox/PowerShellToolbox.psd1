@{
    RootModule        = 'PowerShellToolbox.psm1'
    ModuleVersion     = '1.2.0'
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
        'ConvertTo-PtMarkdownTable',
        'Connect-PtJira',
        'Copy-PtFileSafe',
        'Export-PtReport',
        'Export-PtScheduledTask',
        'Find-PtJiraUser',
        'Format-PtStatusSummary',
        'Get-PtAgentJobReport',
        'Get-PtAzureInventory',
        'Get-PtAzSqlInventory',
        'Get-PtAzVmInventory',
        'Get-PtBackupStatus',
        'Get-PtBackupChain',
        'Get-PtBlockingSession',
        'Get-PtCertificateExpiry',
        'Get-PtDatabaseGrowth',
        'Get-PtDatabaseSpace',
        'Get-PtDiskReport',
        'Get-PtEventLogSummary',
        'Get-PtJiraIssue',
        'Get-PtJiraTransition',
        'Get-PtLongRunningQuery',
        'Get-PtRestoreStatus',
        'Get-PtScheduledTaskReport',
        'Get-PtSecret',
        'Get-PtSecretInfo',
        'Get-PtServiceTriage',
        'Get-PtSqlServerInfo',
        'Import-PtScheduledTask',
        'Initialize-PtVault',
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
