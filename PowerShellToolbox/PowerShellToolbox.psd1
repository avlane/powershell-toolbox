@{
    RootModule        = 'PowerShellToolbox.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = 'cdab71a9-142c-4649-aea1-2bf48a32a9c1'
    Author            = 'Avery Lane'
    Copyright         = '(c) 2019 Avery Lane. MIT License.'
    Description       = 'Small admin helpers: disk, certificate, service, event log and scheduled task reports; SQL Server backup, restore, Agent job, space and blocking status; REST and Jira Cloud helpers; safe file cleanup.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Add-PtJiraComment',
        'Compress-PtOldFile',
        'Connect-PtJira',
        'Copy-PtFileSafe',
        'Export-PtReport',
        'Format-PtStatusSummary',
        'Get-PtAgentJobReport',
        'Get-PtAzureInventory',
        'Get-PtBackupStatus',
        'Get-PtBlockingSession',
        'Get-PtCertificateExpiry',
        'Get-PtDatabaseSpace',
        'Get-PtDiskReport',
        'Get-PtEventLogSummary',
        'Get-PtJiraIssue',
        'Get-PtJiraTransition',
        'Get-PtLongRunningQuery',
        'Get-PtRestoreStatus',
        'Get-PtScheduledTaskReport',
        'Get-PtSecret',
        'Get-PtServiceTriage',
        'Initialize-PtVault',
        'Invoke-PtJiraRequest',
        'Invoke-PtJiraTransition',
        'Invoke-PtRestPaged',
        'Invoke-PtRestRetry',
        'Invoke-PtSqlQuery',
        'Register-PtMaintenanceTask',
        'Remove-PtOldFile',
        'Restart-PtFailedService',
        'Search-PtJiraIssue',
        'Set-PtSecret'
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
