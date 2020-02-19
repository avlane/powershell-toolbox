# PowerShellToolbox - small admin helpers for Windows PowerShell 5.1

function Get-PtDiskReport {
    <#
    .SYNOPSIS
    Reports the free space on the fixed disks of one or more computers.

    .DESCRIPTION
    Queries Win32_LogicalDisk (fixed disks only, DriveType 3) with WMI and returns
    one object per disk with size, free space and a status of OK, Low or Unknown
    (Unknown: the size could not be read).

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER WarningPercent
    A disk with less than this percentage free is reported as Low. Default 10.

    .EXAMPLE
    Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 -WarningPercent 15

    Shows the disks of both servers, flagging those under 15 percent free.

    .EXAMPLE
    Get-PtDiskReport | Where-Object Status -eq 'Low'

    Only the local disks that are running out of space.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(1, 99)]
        [int]$WarningPercent = 10
    )

    process {
        foreach ($computer in $ComputerName) {
            try {
                $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $computer -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not query $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($disk in $disks) {
                # WMI returns no size for a volume it cannot read (a locked BitLocker
                # volume, for example); dividing by that used to stop the whole report
                if ($disk.Size -gt 0) {
                    $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                    if ($freePercent -lt $WarningPercent) { $status = 'Low' } else { $status = 'OK' }
                    $sizeGb = [math]::Round($disk.Size / 1GB, 1)
                    $freeGb = [math]::Round($disk.FreeSpace / 1GB, 1)
                }
                else {
                    $freePercent = $null
                    $status = 'Unknown'
                    $sizeGb = $null
                    $freeGb = $null
                }

                [pscustomobject]@{
                    ComputerName = $computer
                    Drive        = $disk.DeviceID
                    Label        = $disk.VolumeName
                    SizeGB       = $sizeGb
                    FreeGB       = $freeGb
                    FreePercent  = $freePercent
                    Status       = $status
                }
            }
        }
    }
}

function Get-PtServiceTriage {
    <#
    .SYNOPSIS
    Lists services that are set to start automatically but are not running.

    .DESCRIPTION
    Uses Win32_Service on each computer and returns the automatic services that are
    stopped, together with the account they run as and the exit code of their
    last run. A short list of well-known services that are meant to stop
    themselves after doing their work is left out unless -IncludeExpected is given.

    .PARAMETER ComputerName
    The computers to query. Defaults to the local computer.

    .PARAMETER IncludeExpected
    Also list services that normally stop on their own, such as the Software
    Protection and Google Update services.

    .EXAMPLE
    Get-PtServiceTriage -ComputerName SQLPROD01

    .EXAMPLE
    Get-PtServiceTriage | Format-Table ComputerName, Name, StartName, ExitCode
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [switch]$IncludeExpected
    )

    begin {
        # automatic services that exit after doing their work
        $expected = @('sppsvc', 'gupdate', 'gupdatem', 'RemoteRegistry', 'ClrOptimization_v4.0.30319_32', 'ClrOptimization_v4.0.30319_64', 'TrustedInstaller')
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $services = Get-WmiObject -Class Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'" -ComputerName $computer -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not query $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($service in $services) {
                if (-not $IncludeExpected -and $expected -contains $service.Name) { continue }

                [pscustomobject]@{
                    ComputerName = $computer
                    Name         = $service.Name
                    DisplayName  = $service.DisplayName
                    State        = $service.State
                    StartName    = $service.StartName
                    ExitCode     = $service.ExitCode
                }
            }
        }
    }
}

function Get-PtEventLogSummary {
    <#
    .SYNOPSIS
    Summarises the errors and warnings in an event log by source and event id.

    .DESCRIPTION
    Reads the events of the last few hours with Get-WinEvent and groups them by
    provider and event id, so a flood of the same error shows up as one row with a
    count instead of thousands of lines. The most frequent groups come first.

    .PARAMETER ComputerName
    The computers to read. Defaults to the local computer.

    .PARAMETER LogName
    The log to read. Default System.

    .PARAMETER Hours
    How far back to look. Default 24.

    .PARAMETER Level
    Which severities to include: Critical, Error, Warning. Default Critical and Error.

    .PARAMETER Top
    How many groups to return per computer. Default 10.

    .EXAMPLE
    Get-PtEventLogSummary -ComputerName SQLPROD01 -LogName Application -Hours 6 -Level Error, Warning
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [string]$LogName = 'System',

        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [ValidateSet('Critical', 'Error', 'Warning')]
        [string[]]$Level = @('Critical', 'Error'),

        [ValidateRange(1, 1000)]
        [int]$Top = 10
    )

    begin {
        $levelNumbers = @{ Critical = 1; Error = 2; Warning = 3 }
        $levels = @($Level | ForEach-Object { $levelNumbers[$_] })
        $start = (Get-Date).AddHours(-$Hours)
    }

    process {
        foreach ($computer in $ComputerName) {
            $filter = @{ LogName = $LogName; Level = $levels; StartTime = $start }
            try {
                $events = Get-WinEvent -ComputerName $computer -FilterHashtable $filter -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not read the $LogName log on $computer : $($_.Exception.Message)"
                continue
            }

            $groups = $events | Group-Object -Property ProviderName, Id | Sort-Object -Property Count -Descending | Select-Object -First $Top
            foreach ($group in $groups) {
                $newest = $group.Group | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
                $oldest = $group.Group | Sort-Object -Property TimeCreated | Select-Object -First 1
                $firstLine = ''
                if ($newest.Message) { $firstLine = ($newest.Message -split "`r?`n")[0] }

                [pscustomobject]@{
                    ComputerName = $computer
                    Provider     = $newest.ProviderName
                    EventId      = $newest.Id
                    Level        = $newest.LevelDisplayName
                    Count        = $group.Count
                    FirstSeen    = $oldest.TimeCreated
                    LastSeen     = $newest.TimeCreated
                    Message      = $firstLine
                }
            }
        }
    }
}

function ConvertFrom-PtDataRow {
    <#
    .SYNOPSIS
    Turns a DataRow from Invoke-Sqlcmd into a plain object.

    .DESCRIPTION
    DataRow objects print badly, hold DBNull instead of $null and carry a lot of
    baggage. This copies the columns into a PSCustomObject, converts DBNull to
    $null and puts the server name in front.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Data.DataRow]$Row,

        [string]$ServerInstance
    )

    process {
        $properties = [ordered]@{}
        if ($ServerInstance) { $properties['ServerInstance'] = $ServerInstance }
        foreach ($column in $Row.Table.Columns) {
            $value = $Row[$column.ColumnName]
            if ($value -is [System.DBNull]) { $value = $null }
            $properties[$column.ColumnName] = $value
        }
        [pscustomobject]$properties
    }
}

function Invoke-PtSqlQuery {
    <#
    .SYNOPSIS
    Runs a T-SQL query on one or more SQL Server instances and returns plain objects.

    .DESCRIPTION
    A thin wrapper around Invoke-Sqlcmd from the SqlServer module. It runs the same
    query on every instance, stops on errors, turns the DataRows into
    PSCustomObjects (DBNull becomes $null) and adds a ServerInstance property so
    results from several servers can be combined.

    Without -Credential the current Windows account is used.

    .PARAMETER ServerInstance
    One or more instances, for example SQLPROD01 or SQLPROD02\REPORTING.

    .PARAMETER Database
    The database to run in. Default master.

    .PARAMETER Query
    The T-SQL text.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .PARAMETER QueryTimeout
    Seconds before the query is cancelled. Default 30.

    .EXAMPLE
    Invoke-PtSqlQuery -ServerInstance SQLPROD01, SQLPROD02 -Query 'SELECT @@VERSION AS Version'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [string]$Database = 'master',

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Query,

        [pscredential]$Credential,

        [ValidateRange(0, 65535)]
        [int]$QueryTimeout = 30
    )

    begin {
        if (-not (Get-Command -Name Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
            throw 'Invoke-Sqlcmd was not found. Install the SqlServer module with: Install-Module SqlServer'
        }
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{
                ServerInstance = $server
                Database       = $Database
                Query          = $Query
                QueryTimeout   = $QueryTimeout
                ErrorAction    = 'Stop'
            }
            if ($Credential) {
                $parameters['Username'] = $Credential.UserName
                $parameters['Password'] = $Credential.GetNetworkCredential().Password
            }

            try {
                $rows = @(Invoke-Sqlcmd @parameters)
            }
            catch {
                Write-Error "The query failed on $server : $($_.Exception.Message)"
                continue
            }

            foreach ($row in $rows) {
                ConvertFrom-PtDataRow -Row $row -ServerInstance $server
            }
        }
    }
}

function Get-PtBackupStatus {
    <#
    .SYNOPSIS
    Shows when each database was last backed up and flags the ones that are overdue.

    .DESCRIPTION
    Reads msdb.dbo.backupset on each instance and returns, per online database, the
    time of the last full, differential and log backup, how old they are, and a
    Status of OK, Stale or NoBackup. A database in the full or bulk-logged recovery
    model is also Stale when its last log backup is older than MaxLogAgeMinutes.

    Copy-only backups count as backups here. Ages are measured against the clock of
    the server, not of the machine running this command.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER MaxFullAgeHours
    A database whose newest full or differential backup is older than this is
    Stale. Default 36.

    .PARAMETER MaxLogAgeMinutes
    Same for log backups. Default 120.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtBackupStatus -ServerInstance SQLPROD01, SQLPROD02 | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 8760)]
        [int]$MaxFullAgeHours = 36,

        [ValidateRange(1, 10080)]
        [int]$MaxLogAgeMinutes = 120,

        [pscredential]$Credential
    )

    begin {
        $query = @'
SELECT d.name AS DatabaseName,
       d.recovery_model_desc AS RecoveryModel,
       GETDATE() AS ServerTime,
       MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFull,
       MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiff,
       MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLog
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b ON b.database_name = d.name
WHERE d.name <> 'tempdb' AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;
'@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'master' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                # the newest of the full and differential backups is what restores depend on
                $lastBase = $row.LastFull
                if ($row.LastDiff -is [datetime] -and ($lastBase -isnot [datetime] -or $row.LastDiff -gt $lastBase)) {
                    $lastBase = $row.LastDiff
                }

                $problems = @()
                $baseAge = $null
                if ($lastBase -is [datetime]) {
                    $baseAge = [math]::Round(($row.ServerTime - $lastBase).TotalHours, 1)
                    if ($baseAge -gt $MaxFullAgeHours) { $problems += "no full or differential backup for $baseAge hours" }
                }
                else {
                    $problems += 'never backed up'
                }

                $logAge = $null
                if ($row.LastLog -is [datetime]) {
                    $logAge = [math]::Round(($row.ServerTime - $row.LastLog).TotalMinutes, 0)
                }
                if ($row.RecoveryModel -ne 'SIMPLE' -and $row.DatabaseName -ne 'model') {
                    if ($null -eq $logAge) { $problems += 'no log backup' }
                    elseif ($logAge -gt $MaxLogAgeMinutes) { $problems += "no log backup for $logAge minutes" }
                }

                if ($lastBase -isnot [datetime]) { $status = 'NoBackup' }
                elseif ($problems.Count -gt 0) { $status = 'Stale' }
                else { $status = 'OK' }

                [pscustomobject]@{
                    ServerInstance    = $server
                    DatabaseName      = $row.DatabaseName
                    RecoveryModel     = $row.RecoveryModel
                    LastFull          = $row.LastFull
                    LastDiff          = $row.LastDiff
                    LastLog           = $row.LastLog
                    HoursSinceBase    = $baseAge
                    MinutesSinceLog   = $logAge
                    Status            = $status
                    Problems          = $problems -join '; '
                }
            }
        }
    }
}

function Get-PtCertificateExpiry {
    <#
    .SYNOPSIS
    Lists certificates in a Windows certificate store with the days left until they expire.

    .DESCRIPTION
    Reads Cert:\<StoreLocation>\<StoreName> on each computer (remote computers
    are reached with Invoke-Command, so PowerShell remoting must be enabled) and
    returns one object per certificate, oldest expiry first. Status is Expired,
    Expiring (within WarningDays) or OK.

    .PARAMETER ComputerName
    The computers to check. Defaults to the local computer.

    .PARAMETER StoreName
    The store, for example My (personal), WebHosting or Root. Default My.

    .PARAMETER StoreLocation
    LocalMachine (default) or CurrentUser.

    .PARAMETER WarningDays
    Certificates that expire within this many days are Expiring. Default 30.

    .EXAMPLE
    Get-PtCertificateExpiry -ComputerName WEB01, WEB02 | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [string]$StoreName = 'My',

        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation = 'LocalMachine',

        [ValidateRange(1, 3650)]
        [int]$WarningDays = 30
    )

    begin {
        $readStore = {
            param($Location, $Store)
            Get-ChildItem -Path "Cert:\$Location\$Store" | ForEach-Object {
                [pscustomobject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    Thumbprint    = $_.Thumbprint
                    NotAfter      = $_.NotAfter
                    HasPrivateKey = $_.HasPrivateKey
                    DnsNames      = (@($_.DnsNameList | ForEach-Object { $_.Unicode }) -join ', ')
                }
            }
        }
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                if ($localNames -contains $computer) {
                    $certificates = @(& $readStore $StoreLocation $StoreName)
                }
                else {
                    $certificates = @(Invoke-Command -ComputerName $computer -ScriptBlock $readStore -ArgumentList $StoreLocation, $StoreName -ErrorAction Stop)
                }
            }
            catch {
                Write-Warning "Could not read the $StoreLocation\$StoreName store on $computer : $($_.Exception.Message)"
                continue
            }

            foreach ($certificate in ($certificates | Sort-Object -Property NotAfter)) {
                $daysLeft = [int][math]::Floor(($certificate.NotAfter - (Get-Date)).TotalDays)
                if ($daysLeft -lt 0) { $status = 'Expired' }
                elseif ($daysLeft -le $WarningDays) { $status = 'Expiring' }
                else { $status = 'OK' }

                [pscustomobject]@{
                    ComputerName  = $computer
                    Subject       = $certificate.Subject
                    DnsNames      = $certificate.DnsNames
                    Thumbprint    = $certificate.Thumbprint
                    NotAfter      = $certificate.NotAfter
                    DaysLeft      = $daysLeft
                    Status        = $status
                    HasPrivateKey = $certificate.HasPrivateKey
                    Issuer        = $certificate.Issuer
                }
            }
        }
    }
}

function Get-PtAzureInventory {
    <#
    .SYNOPSIS
    Lists the Azure resources in one or more subscriptions, with their tags.

    .DESCRIPTION
    Uses the Az module (Install-Module Az) and the account you are already
    signed in with (Connect-AzAccount). For every subscription it
    returns one object per resource: resource group, name, type, location and the
    tags as a single "key=value; key=value" string, which is handy in a CSV.

    .PARAMETER SubscriptionId
    The subscriptions to read. Default: all that the account can see.

    .PARAMETER ResourceGroupName
    Only this resource group in each subscription.

    .EXAMPLE
    Get-PtAzureInventory | Export-Csv -Path .\inventory.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubscriptionId,

        [string]$ResourceGroupName
    )

    if (-not (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)) {
        throw 'The Az module is not installed. Install it with: Install-Module Az'
    }
    if (-not (Get-AzContext)) {
        throw 'Not signed in to Azure. Run Connect-AzAccount first.'
    }

    if ($SubscriptionId) {
        $subscriptions = @($SubscriptionId | ForEach-Object { Get-AzSubscription -SubscriptionId $_ })
    }
    else {
        $subscriptions = @(Get-AzSubscription)
    }

    foreach ($subscription in $subscriptions) {
        [void](Set-AzContext -SubscriptionId $subscription.Id)

        $parameters = @{}
        if ($ResourceGroupName) { $parameters['ResourceGroupName'] = $ResourceGroupName }

        foreach ($resource in (Get-AzResource @parameters)) {
            $tags = ''
            if ($resource.Tags) {
                $pairs = foreach ($tag in ($resource.Tags.GetEnumerator() | Sort-Object -Property Name)) { "$($tag.Name)=$($tag.Value)" }
                $tags = $pairs -join '; '
            }

            [pscustomobject]@{
                Subscription  = $subscription.Name
                ResourceGroup = $resource.ResourceGroupName
                Name          = $resource.Name
                Type          = $resource.ResourceType
                Location      = $resource.Location
                Tags          = $tags
            }
        }
    }
}

function Remove-PtOldFile {
    <#
    .SYNOPSIS
    Deletes files that have not been written to for a number of days.

    .DESCRIPTION
    Meant for log, backup and temp folders. Every deletion goes through
    ShouldProcess, so -WhatIf shows what would be removed and the default
    confirmation prompt (ConfirmImpact is High) protects interactive use; pass
    -Confirm:$false in scheduled jobs.

    The command refuses to work on the root of a drive and only ever deletes files
    (never folders), unless -RemoveEmptyFolders is given, which also deletes folders
    below the path that are empty afterwards.

    .PARAMETER Path
    One or more folders.

    .PARAMETER OlderThanDays
    Files whose LastWriteTime is more than this many days ago are deleted.

    .PARAMETER Filter
    A file name filter such as *.bak. Default *.

    .PARAMETER Recurse
    Also look in sub-folders.

    .PARAMETER RemoveEmptyFolders
    With -Recurse, delete sub-folders that are empty after the files were removed.

    .EXAMPLE
    Remove-PtOldFile -Path D:\Backups\Sales -Filter *.bak -OlderThanDays 14 -WhatIf

    .EXAMPLE
    Remove-PtOldFile -Path E:\Logs -OlderThanDays 30 -Recurse -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$OlderThanDays,

        [string]$Filter = '*',

        [switch]$Recurse,

        [switch]$RemoveEmptyFolders
    )

    process {
        $cutoff = (Get-Date).AddDays(-$OlderThanDays)

        foreach ($folder in $Path) {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-Error "The folder $folder does not exist."
                continue
            }
            $resolved = (Resolve-Path -LiteralPath $folder).ProviderPath
            if ($resolved -eq [System.IO.Path]::GetPathRoot($resolved)) {
                Write-Error "Refusing to clean up the root of a drive: $resolved"
                continue
            }

            $searchParameters = @{ LiteralPath = $resolved; Filter = $Filter; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
            if ($Recurse) { $searchParameters['Recurse'] = $true }

            foreach ($file in (Get-ChildItem @searchParameters | Where-Object { $_.LastWriteTime -lt $cutoff })) {
                $removed = $false
                $failure = $null
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete (last written $($file.LastWriteTime))")) {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                        $removed = $true
                    }
                    catch {
                        $failure = $_.Exception.Message
                        Write-Warning "Could not delete $($file.FullName) : $failure"
                    }
                }

                [pscustomobject]@{
                    Path          = $file.FullName
                    SizeMB        = [math]::Round($file.Length / 1MB, 2)
                    LastWriteTime = $file.LastWriteTime
                    Removed       = $removed
                    Error         = $failure
                }
            }

            if ($RemoveEmptyFolders -and $Recurse) {
                $folders = Get-ChildItem -LiteralPath $resolved -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object -Property FullName -Descending
                foreach ($directory in $folders) {
                    $isEmpty = -not (Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue)
                    if ($isEmpty -and $PSCmdlet.ShouldProcess($directory.FullName, 'Delete empty folder')) {
                        Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}

function Export-PtReport {
    <#
    .SYNOPSIS
    Writes the objects from the pipeline to a CSV, JSON or HTML file.

    .DESCRIPTION
    A small report writer for the other commands in this module. The format follows
    the file extension (.csv, .json, .html or .htm) unless -Format is given. The
    HTML output is one styled table in which every value is HTML-encoded, so text
    that comes from a server cannot inject markup. The folder is created when it
    does not exist, and the file is only written if ShouldProcess agrees (-WhatIf).

    Returns the file that was written.

    .PARAMETER InputObject
    The objects to export, normally from the pipeline.

    .PARAMETER Path
    The file to write. An existing file is overwritten.

    .PARAMETER Format
    Csv, Json or Html. Default: from the extension of Path.

    .PARAMETER Title
    The heading of the HTML report.

    .EXAMPLE
    Get-PtDiskReport -ComputerName SQLPROD01, SQLPROD02 | Export-PtReport -Path .\disks.html -Title 'Disk space'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [ValidateSet('Csv', 'Json', 'Html')]
        [string]$Format,

        [string]$Title = 'Report'
    )

    begin {
        $items = New-Object -TypeName 'System.Collections.Generic.List[object]'
    }

    process {
        if ($null -ne $InputObject) { $items.Add($InputObject) }
    }

    end {
        if (-not $Format) {
            switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
                '.csv'  { $Format = 'Csv' }
                '.json' { $Format = 'Json' }
                '.html' { $Format = 'Html' }
                '.htm'  { $Format = 'Html' }
                default { throw "Cannot tell the format from the extension of $Path. Use -Format Csv, Json or Html." }
            }
        }

        if ($PSCmdlet.ShouldProcess($Path, "Write $($items.Count) rows as $Format")) {
            $folder = Split-Path -Path $Path -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) {
                [void](New-Item -ItemType Directory -Path $folder -Force)
            }

            switch ($Format) {
                'Csv' {
                    if ($items.Count -gt 0) { $items | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
                    else { Set-Content -LiteralPath $Path -Value '' -Encoding UTF8 }
                }
                'Json' {
                    ConvertTo-Json -InputObject $items.ToArray() -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
                }
                'Html' {
                    $encode = { param($text) [System.Net.WebUtility]::HtmlEncode([string]$text) }
                    $html = New-Object -TypeName System.Text.StringBuilder
                    [void]$html.AppendLine('<!DOCTYPE html>')
                    [void]$html.AppendLine('<html><head><meta charset="utf-8">')
                    [void]$html.AppendLine("<title>$(& $encode $Title)</title>")
                    [void]$html.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:1.5em}table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:4px 10px;text-align:left}th{background:#eee}</style>')
                    [void]$html.AppendLine('</head><body>')
                    [void]$html.AppendLine("<h1>$(& $encode $Title)</h1>")
                    [void]$html.AppendLine("<p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $($items.Count) rows</p>")
                    if ($items.Count -gt 0) {
                        $columns = @($items[0].PSObject.Properties.Name)
                        [void]$html.AppendLine('<table>')
                        [void]$html.AppendLine('<tr>' + (($columns | ForEach-Object { "<th>$(& $encode $_)</th>" }) -join '') + '</tr>')
                        foreach ($item in $items) {
                            $cells = foreach ($column in $columns) { "<td>$(& $encode $item.$column)</td>" }
                            [void]$html.AppendLine('<tr>' + ($cells -join '') + '</tr>')
                        }
                        [void]$html.AppendLine('</table>')
                    }
                    [void]$html.AppendLine('</body></html>')
                    Set-Content -LiteralPath $Path -Value $html.ToString() -Encoding UTF8
                }
            }

            Get-Item -LiteralPath $Path
        }
    }
}

function Get-PtHttpErrorDetail {
    <#
    .SYNOPSIS
    Pulls the status code and Retry-After header out of a failed web request.

    .DESCRIPTION
    In Windows PowerShell 5.1 Invoke-RestMethod throws a WebException whose
    Response holds the HTTP details. This returns them as a plain object so the
    retry logic (and its tests) do not have to dig through exception types.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    $statusCode = $null
    $retryAfter = $null

    $response = $exception.Response
    if ($response) {
        $statusCode = [int]$response.StatusCode
        $header = $response.Headers['Retry-After']
        if ($header) { $retryAfter = [string]$header }
    }

    [pscustomobject]@{
        StatusCode     = $statusCode
        RetryAfter     = $retryAfter
        IsNetworkError = (($null -eq $response) -and ($exception -is [System.Net.WebException]))
        Message        = $exception.Message
    }
}

function Invoke-PtRestRetry {
    <#
    .SYNOPSIS
    Calls Invoke-RestMethod and tries again when the server is busy or unreachable.

    .DESCRIPTION
    Retries on network errors and on HTTP 429, 500, 502, 503 and 504, up to
    MaxRetries more times. Between tries it waits for the number of seconds in the
    Retry-After header when the server sent one, otherwise it backs off
    exponentially (2, 4, 8 ... seconds, at most 60). Other errors, for example 400,
    401 or 404, are thrown immediately because trying again cannot help.

    TLS 1.2 is switched on for the session, which Windows PowerShell 5.1 does not
    always do by default.

    .PARAMETER Uri
    The address to call.

    .PARAMETER Method
    The HTTP method. Default Get.

    .PARAMETER Headers
    A hashtable of request headers.

    .PARAMETER Body
    The request body. A hashtable or object is sent as JSON; a string is sent as is.

    .PARAMETER MaxRetries
    How many times to retry after the first attempt. Default 3.

    .PARAMETER InitialDelaySeconds
    The first back-off delay. Default 2.

    .PARAMETER TimeoutSec
    Timeout of each attempt. Default 60.

    .EXAMPLE
    Invoke-PtRestRetry -Uri 'https://api.example.com/v1/items' -Headers @{ Authorization = 'Bearer abc' } -MaxRetries 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Uri,

        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [string]$Method = 'Get',

        [hashtable]$Headers,

        [object]$Body,

        [ValidateRange(0, 20)]
        [int]$MaxRetries = 3,

        [ValidateRange(1, 300)]
        [int]$InitialDelaySeconds = 2,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSec = 60
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $parameters = @{ Uri = $Uri; Method = $Method; TimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
    if ($Headers) { $parameters['Headers'] = $Headers }
    if ($null -ne $Body) {
        if ($Body -is [string]) {
            $parameters['Body'] = $Body
        }
        else {
            $parameters['Body'] = ConvertTo-Json -InputObject $Body -Depth 10
            $parameters['ContentType'] = 'application/json'
        }
    }

    $retryableStatus = @(429, 500, 502, 503, 504)
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return Invoke-RestMethod @parameters
        }
        catch {
            $detail = Get-PtHttpErrorDetail -ErrorRecord $_
            $retryable = $detail.IsNetworkError -or ($retryableStatus -contains $detail.StatusCode)
            if (-not $retryable -or $attempt -gt $MaxRetries) { throw }

            $delay = [math]::Min(60, $InitialDelaySeconds * [math]::Pow(2, $attempt - 1))
            if ($detail.RetryAfter -match '^\d+$') { $delay = [int]$detail.RetryAfter }

            Write-Verbose "Attempt $attempt of $($MaxRetries + 1) failed ($($detail.Message)); waiting $delay seconds."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-PtAgentJobReport {
    <#
    .SYNOPSIS
    Reports the state of the SQL Server Agent jobs: last result, next run and recent failures.

    .DESCRIPTION
    Reads msdb on each instance and returns one object per job with the outcome and
    start time of its last run, how long it took, when it runs next and how many
    runs failed in the last few hours. Verdict is Failed (the last run failed),
    Flaky (the last run succeeded but there were failures in the window), Disabled
    or OK.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Hours
    The window for counting failed runs. Default 24.

    .PARAMETER OnlyProblems
    Leave out jobs whose Verdict is OK.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtAgentJobReport -ServerInstance SQLPROD01, SQLPROD02 -OnlyProblems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [switch]$OnlyProblems,

        [pscredential]$Credential
    )

    begin {
        # job outcome codes in msdb.dbo.sysjobhistory.run_status
        $statusNames = @{ 0 = 'Failed'; 1 = 'Succeeded'; 2 = 'Retry'; 3 = 'Canceled'; 4 = 'InProgress' }

        $query = @"
WITH last_run AS (
    SELECT h.job_id, h.run_status, h.run_date, h.run_time, h.run_duration, h.message,
           ROW_NUMBER() OVER (PARTITION BY h.job_id ORDER BY h.instance_id DESC) AS rn
    FROM msdb.dbo.sysjobhistory AS h
    WHERE h.step_id = 0
),
failures AS (
    SELECT h.job_id, COUNT(*) AS failed_runs
    FROM msdb.dbo.sysjobhistory AS h
    WHERE h.step_id = 0 AND h.run_status = 0
      AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(HOUR, -$Hours, GETDATE())
    GROUP BY h.job_id
),
next_run AS (
    SELECT job_id, MIN(msdb.dbo.agent_datetime(next_run_date, next_run_time)) AS next_run_time
    FROM msdb.dbo.sysjobschedules
    WHERE next_run_date > 0
    GROUP BY job_id
)
SELECT j.name AS JobName,
       j.enabled AS Enabled,
       l.run_status AS LastRunStatus,
       msdb.dbo.agent_datetime(l.run_date, l.run_time) AS LastRunTime,
       (l.run_duration / 10000) * 3600 + ((l.run_duration / 100) % 100) * 60 + (l.run_duration % 100) AS LastRunSeconds,
       l.message AS LastMessage,
       n.next_run_time AS NextRunTime,
       ISNULL(f.failed_runs, 0) AS FailedRuns
FROM msdb.dbo.sysjobs AS j
LEFT JOIN last_run AS l ON l.job_id = j.job_id AND l.rn = 1
LEFT JOIN failures AS f ON f.job_id = j.job_id
LEFT JOIN next_run AS n ON n.job_id = j.job_id
ORDER BY j.name;
"@
    }

    process {
        foreach ($server in $ServerInstance) {
            $parameters = @{ ServerInstance = $server; Query = $query; Database = 'msdb' }
            if ($Credential) { $parameters['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @parameters)) {
                $lastStatus = 'NeverRun'
                if ($null -ne $row.LastRunStatus) { $lastStatus = $statusNames[[int]$row.LastRunStatus] }

                if (-not $row.Enabled) { $verdict = 'Disabled' }
                elseif ($lastStatus -eq 'Failed') { $verdict = 'Failed' }
                elseif ($row.FailedRuns -gt 0) { $verdict = 'Flaky' }
                else { $verdict = 'OK' }

                if ($OnlyProblems -and $verdict -eq 'OK') { continue }

                [pscustomobject]@{
                    ServerInstance = $server
                    JobName        = $row.JobName
                    Enabled        = [bool]$row.Enabled
                    LastRunStatus  = $lastStatus
                    LastRunTime    = $row.LastRunTime
                    LastRunSeconds = $row.LastRunSeconds
                    NextRunTime    = $row.NextRunTime
                    FailedRuns     = $row.FailedRuns
                    Verdict        = $verdict
                    LastMessage    = $row.LastMessage
                }
            }
        }
    }
}

function Get-PtRestoreStatus {
    <#
    .SYNOPSIS
    Shows restores that are running now and the restore history of the last days.

    .DESCRIPTION
    Combines two sources on each instance. Running restores come from
    sys.dm_exec_requests, with the percentage done and the estimated finish time.
    History comes from msdb.dbo.restorehistory: which backup was restored into which
    database, when, and by whom. Each output object has a Kind of Running or
    History.

    .PARAMETER ServerInstance
    One or more instances.

    .PARAMETER Days
    How far back the history goes. Default 7.

    .PARAMETER RunningOnly
    Skip the history.

    .PARAMETER Credential
    A SQL Server login. Leave out to use Windows authentication.

    .EXAMPLE
    Get-PtRestoreStatus -ServerInstance SQLDR02 -RunningOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ServerInstance,

        [ValidateRange(1, 3650)]
        [int]$Days = 7,

        [switch]$RunningOnly,

        [pscredential]$Credential
    )

    begin {
        $restoreTypes = @{ D = 'Database'; F = 'File'; G = 'Filegroup'; I = 'Differential'; L = 'Log'; V = 'Verify only' }

        $runningQuery = @'
SELECT r.session_id AS SessionId,
       DB_NAME(r.database_id) AS DatabaseName,
       r.command AS Command,
       r.percent_complete AS PercentComplete,
       r.start_time AS StartTime,
       DATEADD(SECOND, r.estimated_completion_time / 1000, GETDATE()) AS EstimatedFinish,
       s.login_name AS LoginName
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.command LIKE 'RESTORE%'
ORDER BY r.start_time;
'@

        $historyQuery = @"
SELECT rh.destination_database_name AS DatabaseName,
       rh.restore_date AS RestoreDate,
       rh.restore_type AS RestoreType,
       rh.user_name AS RestoredBy,
       bs.server_name AS SourceServer,
       bs.database_name AS SourceDatabase,
       bs.backup_finish_date AS BackupFinished,
       bmf.physical_device_name AS BackupFile
FROM msdb.dbo.restorehistory AS rh
JOIN msdb.dbo.backupset AS bs ON bs.backup_set_id = rh.backup_set_id
LEFT JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE rh.restore_date >= DATEADD(DAY, -$Days, GETDATE())
ORDER BY rh.restore_date DESC;
"@
    }

    process {
        foreach ($server in $ServerInstance) {
            $common = @{ ServerInstance = $server; Database = 'master' }
            if ($Credential) { $common['Credential'] = $Credential }

            foreach ($row in (Invoke-PtSqlQuery @common -Query $runningQuery)) {
                [pscustomobject]@{
                    ServerInstance  = $server
                    Kind            = 'Running'
                    DatabaseName    = $row.DatabaseName
                    Detail          = "$($row.Command) on session $($row.SessionId) by $($row.LoginName)"
                    PercentComplete = [math]::Round([double]$row.PercentComplete, 1)
                    Started         = $row.StartTime
                    Finished        = $row.EstimatedFinish
                }
            }

            if ($RunningOnly) { continue }

            foreach ($row in (Invoke-PtSqlQuery @common -Query $historyQuery)) {
                $type = $restoreTypes["$($row.RestoreType)"]
                if (-not $type) { $type = "$($row.RestoreType)" }
                [pscustomobject]@{
                    ServerInstance  = $server
                    Kind            = 'History'
                    DatabaseName    = $row.DatabaseName
                    Detail          = "$type restore of $($row.SourceDatabase) from $($row.SourceServer) (backup finished $($row.BackupFinished)) by $($row.RestoredBy): $($row.BackupFile)"
                    PercentComplete = 100
                    Started         = $row.RestoreDate
                    Finished        = $row.RestoreDate
                }
            }
        }
    }
}
