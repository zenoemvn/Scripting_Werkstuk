function Get-DbConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory=$true)]
        [string]$Database
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