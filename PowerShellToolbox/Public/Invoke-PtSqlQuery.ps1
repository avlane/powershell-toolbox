function Invoke-PtSqlQuery {
    <#
    .SYNOPSIS
    Runs a T-SQL query on one or more SQL Server instances and returns plain objects.

    .DESCRIPTION
    A thin wrapper around Invoke-Sqlcmd from the SqlServer module. It runs the same
    query on every instance, stops on errors, turns the DataRows into
    PSCustomObjects (DBNull becomes $null) and adds a ServerInstance property so
    results from several servers can be combined. Several instances are queried in
    parallel; the rows come back in the order the instances were given.

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

    .PARAMETER ThrottleLimit
    How many instances to query at the same time when there are several. Default 4;
    1 means one after the other.

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
        [int]$QueryTimeout = 30,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4
    )

    begin {
        if (-not (Get-Command -Name Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
            throw 'Invoke-Sqlcmd was not found. Install the SqlServer module with: Install-Module SqlServer'
        }
        $servers = New-Object -TypeName 'System.Collections.Generic.List[string]'
    }

    process {
        foreach ($server in $ServerInstance) { $servers.Add($server) }
    }

    end {
        $baseParameters = @{
            Database     = $Database
            Query        = $Query
            QueryTimeout = $QueryTimeout
            ErrorAction  = 'Stop'
        }
        if ($Credential) {
            $baseParameters['Username'] = $Credential.UserName
            $baseParameters['Password'] = $Credential.GetNetworkCredential().Password
        }

        if ($ThrottleLimit -gt 1 -and $servers.Count -gt 1) {
            # the parallel runspaces do not have this module, so they call Invoke-Sqlcmd
            # themselves (the SqlServer module loads on demand) and the rows are
            # converted afterwards
            $results = $servers | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $target = $_    # inside catch, $_ is the error record
                $parameters = ($using:baseParameters).Clone()
                $parameters['ServerInstance'] = $target
                try {
                    [pscustomobject]@{ Server = $target; Rows = @(Invoke-Sqlcmd @parameters); Error = $null }
                }
                catch {
                    [pscustomobject]@{ Server = $target; Rows = @(); Error = $_.Exception.Message }
                }
            }
        }
        else {
            $results = foreach ($target in $servers) {
                $parameters = $baseParameters.Clone()
                $parameters['ServerInstance'] = $target
                try {
                    [pscustomobject]@{ Server = $target; Rows = @(Invoke-Sqlcmd @parameters); Error = $null }
                }
                catch {
                    [pscustomobject]@{ Server = $target; Rows = @(); Error = $_.Exception.Message }
                }
            }
        }

        # parallel results arrive in any order; give them back in the order of the servers
        foreach ($server in $servers) {
            $result = $results | Where-Object { $_.Server -eq $server } | Select-Object -First 1
            if ($result.Error) {
                Write-Error "The query failed on $server : $($result.Error)"
                continue
            }
            foreach ($row in $result.Rows) {
                ConvertFrom-PtDataRow -Row $row -ServerInstance $server
            }
        }
    }
}
