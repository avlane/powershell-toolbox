@{
    RootModule        = 'PowerShellToolbox.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'cdab71a9-142c-4649-aea1-2bf48a32a9c1'
    Author            = 'Avery Lane'
    Copyright         = '(c) 2019 Avery Lane. MIT License.'
    Description       = 'Small admin helpers: disk, service and event log reports, SQL Server status queries.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Add-PtJiraComment',
        'Compress-PtOldFile',
        'Connect-PtJira',
        'Copy-PtFileSafe',
        'Export-PtReport',
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
        'Search-PtJiraIssue',
        'Set-PtSecret'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
