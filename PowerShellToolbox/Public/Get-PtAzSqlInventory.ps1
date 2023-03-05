function Get-PtAzSqlInventory {
    <#
    .SYNOPSIS
    Lists Azure SQL logical servers and their databases with edition, size and a few security flags.

    .DESCRIPTION
    Uses the Az.Sql module and the account you are signed in with. Returns one object
    per database (the master database is skipped), with the properties of its
    server repeated on each row so the result can go straight into a CSV. Flags:
    PublicAccess when the server accepts connections from the public network, and
    OldTls when its minimum TLS version is lower than 1.2 or not set.

    .PARAMETER SubscriptionId
    The subscriptions to read. Default: all that the account can see.

    .PARAMETER ResourceGroupName
    Only this resource group in each subscription.

    .EXAMPLE
    Get-PtAzSqlInventory | Where-Object Flags | Format-Table Server, Database, Edition, Flags
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubscriptionId,

        [string]$ResourceGroupName
    )

    if (-not (Get-Command -Name Get-AzSqlServer -ErrorAction SilentlyContinue)) {
        throw 'The Az.Sql module is not installed. Install it with: Install-Module Az.Sql'
    }
    if (-not (Get-AzContext)) {
        throw 'Not signed in to Azure. Run Connect-AzAccount first.'
    }

    $subscriptions = $SubscriptionId ? @($SubscriptionId | ForEach-Object { Get-AzSubscription -SubscriptionId $_ }) : @(Get-AzSubscription)

    foreach ($subscription in $subscriptions) {
        [void](Set-AzContext -SubscriptionId $subscription.Id)

        $serverParameters = @{}
        if ($ResourceGroupName) { $serverParameters['ResourceGroupName'] = $ResourceGroupName }

        foreach ($server in @(Get-AzSqlServer @serverParameters)) {
            $serverFlags = @()
            if ($server.PublicNetworkAccess -eq 'Enabled') { $serverFlags += 'PublicAccess' }
            # 'None' (or nothing) means there is no minimum, so TLS 1.0 and 1.1 are accepted too
            $minimumTls = $server.MinimalTlsVersion
            if (-not $minimumTls -or $minimumTls -eq 'None' -or [version]$minimumTls -lt [version]'1.2') { $serverFlags += 'OldTls' }

            $databases = @(Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName | Where-Object { $_.DatabaseName -ne 'master' })
            foreach ($database in $databases) {
                [pscustomobject]@{
                    Subscription  = $subscription.Name
                    ResourceGroup = $server.ResourceGroupName
                    Server        = $server.FullyQualifiedDomainName
                    Database      = $database.DatabaseName
                    Edition       = $database.Edition
                    Objective     = $database.CurrentServiceObjectiveName
                    MaxSizeGB     = [math]::Round($database.MaxSizeBytes / 1GB, 1)
                    Status        = $database.Status
                    ZoneRedundant = $database.ZoneRedundant
                    Location      = $server.Location
                    ServerVersion = $server.ServerVersion
                    Flags         = $serverFlags -join ', '
                }
            }

            if ($databases.Count -eq 0) {
                [pscustomobject]@{
                    Subscription  = $subscription.Name
                    ResourceGroup = $server.ResourceGroupName
                    Server        = $server.FullyQualifiedDomainName
                    Database      = $null
                    Edition       = $null
                    Objective     = $null
                    MaxSizeGB     = $null
                    Status        = $null
                    ZoneRedundant = $null
                    Location      = $server.Location
                    ServerVersion = $server.ServerVersion
                    Flags         = $serverFlags -join ', '
                }
            }
        }
    }
}
