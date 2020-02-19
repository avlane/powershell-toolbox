@{
    RootModule        = 'PowerShellToolbox.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'cdab71a9-142c-4649-aea1-2bf48a32a9c1'
    Author            = 'Avery Lane'
    Copyright         = '(c) 2019 Avery Lane. MIT License.'
    Description       = 'Small admin helpers: disk, service and event log reports, SQL Server status queries.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Export-PtReport',
        'Get-PtAgentJobReport',
        'Get-PtAzureInventory',
        'Get-PtBackupStatus',
        'Get-PtCertificateExpiry',
        'Get-PtDiskReport',
        'Get-PtEventLogSummary',
        'Get-PtRestoreStatus',
        'Get-PtServiceTriage',
        'Invoke-PtRestRetry',
        'Invoke-PtSqlQuery',
        'Remove-PtOldFile'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
