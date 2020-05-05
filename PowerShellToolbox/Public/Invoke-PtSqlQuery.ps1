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
