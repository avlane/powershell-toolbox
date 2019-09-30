# PowerShellToolbox - small admin helpers for Windows PowerShell 5.1

function Get-PtDiskReport {
    <#
    .SYNOPSIS
    Reports the free space on the fixed disks of one or more computers.

    .DESCRIPTION
    Queries Win32_LogicalDisk (fixed disks only, DriveType 3) with WMI and returns
    one object per disk with size, free space and a status of OK or Low.

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
                $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                if ($freePercent -lt $WarningPercent) { $status = 'Low' } else { $status = 'OK' }

                [pscustomobject]@{
                    ComputerName = $computer
                    Drive        = $disk.DeviceID
                    Label        = $disk.VolumeName
                    SizeGB       = [math]::Round($disk.Size / 1GB, 1)
                    FreeGB       = [math]::Round($disk.FreeSpace / 1GB, 1)
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
