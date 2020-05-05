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
