# Import PSSQLite module
Import-Module PSSQLite -ErrorAction Stop

# Verwijder je eigen wrapper, gebruik direct PSSQLite
# Je hebt geen eigen Invoke-SQLiteQuery nodig!

function ConvertTo-SQLiteDataType {
    <#
    .SYNOPSIS
    Converts SQL Server data type to SQLite data type
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SqlServerType
    )
    
    # Default mappings
    $mappings = @{
        "INT" = "INTEGER"
        "BIGINT" = "INTEGER"
        "SMALLINT" = "INTEGER"
        "TINYINT" = "INTEGER"
        "BIT" = "INTEGER"
        "DECIMAL" = "REAL"
        "NUMERIC" = "REAL"
        "FLOAT" = "REAL"
        "REAL" = "REAL"
        "MONEY" = "REAL"
        "SMALLMONEY" = "REAL"
        "VARCHAR" = "TEXT"
        "NVARCHAR" = "TEXT"
        "CHAR" = "TEXT"
        "NCHAR" = "TEXT"
        "TEXT" = "TEXT"
        "NTEXT" = "TEXT"
        "DATE" = "TEXT"
        "DATETIME" = "TEXT"
        "DATETIME2" = "TEXT"
        "TIME" = "TEXT"
    }
    
    # Extract base type (remove size)
    $baseType = ($SqlServerType -replace '\(.*\)', '').Trim().ToUpper()
    
    if ($mappings.ContainsKey($baseType)) {
        return $mappings[$baseType]
    } else {
        Write-Warning "Unknown SQL Server type: $SqlServerType, defaulting to TEXT"
        return "TEXT"
    }
}

function Get-SQLiteTables {
    <#
    .SYNOPSIS
    Gets all tables in SQLite database
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DataSource
    )
    
    $query = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    
    # Gebruik direct PSSQLite's Invoke-SqliteQuery (met kleine 's')
    $result = Invoke-SqliteQuery -DataSource $DataSource -Query $query
    
    if ($result) {
        return $result | Select-Object -ExpandProperty name
    } else {
        return @()
    }
}