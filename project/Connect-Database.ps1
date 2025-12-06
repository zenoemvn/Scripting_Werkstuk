function Get-DbConnection {
    [CmdletBinding()]
    param(
        [string]$ServerInstance = "localhost\SQLEXPRESS",
        [string]$Database = "master"
    )
    
    return @{
        ServerInstance = $ServerInstance
        Database = $Database
        TrustServerCertificate = $true
        ErrorAction = 'Stop'
    }
}

# Gebruik dan:
$connParams = Get-DbConnection
Invoke-Sqlcmd @connParams -Query "SELECT @@VERSION"