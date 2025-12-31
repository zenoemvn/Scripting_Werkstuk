<#
.SYNOPSIS
Database Migration Module - Complete database migration toolkit

.DESCRIPTION
This module provides all functionality for database migrations:
- SQL Server ↔ SQLite conversion
- CSV export/import
- Database schema management

.NOTES
Author: Zeno Van Neygen
Version: 1.0
#>

#region SQLite Helper Functions

# Import PSSQLite module
Import-Module PSSQLite -ErrorAction Stop

#region Data Validation Functions

function Get-DataChecksum {
    <#
    .SYNOPSIS
    Calculates checksum for table data to validate integrity
    
    .DESCRIPTION
    Generates a hash-based checksum of table data for integrity validation
    Supports both SQL Server and SQLite databases
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('SqlServer', 'SQLite')]
        [string]$DatabaseType,
        
        [Parameter(Mandatory, ParameterSetName='SqlServer')]
        [string]$ServerInstance,
        
        [Parameter(Mandatory, ParameterSetName='SqlServer')]
        [string]$Database,
        
        [Parameter(Mandatory, ParameterSetName='SQLite')]
        [string]$SQLitePath,
        
        [Parameter(Mandatory)]
        [string]$TableName
    )
    
    try {
        $data = if ($DatabaseType -eq 'SqlServer') {
            Invoke-Sqlcmd -ServerInstance $ServerInstance `
                -Database $Database `
                -TrustServerCertificate `
                -Query "SELECT * FROM [$TableName] ORDER BY 1"
        } else {
            Invoke-SqliteQuery -DataSource $SQLitePath `
                -Query "SELECT * FROM [$TableName] ORDER BY 1"
        }
        
        if (-not $data) {
            return @{
                TableName = $TableName
                RowCount = 0
                Checksum = "EMPTY_TABLE"
            }
        }
        
        # Convert data to string and calculate hash
        $dataString = ($data | ConvertTo-Json -Compress)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($dataString))
        $checksum = [System.BitConverter]::ToString($hash).Replace("-", "")
        
        return @{
            TableName = $TableName
            RowCount = @($data).Count
            Checksum = $checksum
        }
    }
    catch {
        Write-Warning "Failed to calculate checksum for $TableName : $_"
        return @{
            TableName = $TableName
            RowCount = 0
            Checksum = "ERROR"
            Error = $_.Exception.Message
        }
    }
}

function Test-DataIntegrity {
    <#
    .SYNOPSIS
    Validates data integrity between source and destination tables
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SourceChecksum,
        
        [Parameter(Mandatory)]
        [hashtable]$DestinationChecksum
    )
    
    $result = @{
        TableName = $SourceChecksum.TableName
        RowCountMatch = ($SourceChecksum.RowCount -eq $DestinationChecksum.RowCount)
        ChecksumMatch = ($SourceChecksum.Checksum -eq $DestinationChecksum.Checksum)
        SourceRows = $SourceChecksum.RowCount
        DestinationRows = $DestinationChecksum.RowCount
        Valid = $false
    }
    
    $result.Valid = $result.RowCountMatch -and $result.ChecksumMatch
    
    return $result
}

#endregion

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
        "BINARY" = "BLOB"
        "VARBINARY" = "BLOB"
        "IMAGE" = "BLOB"
        "UNIQUEIDENTIFIER" = "TEXT"
        "XML" = "TEXT"
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

#endregion

#region SQLite to SQL Server Migration

function ConvertTo-SqlServerDataType {
    param([string]$SQLiteType)

    $type = $SQLiteType.Trim().ToUpper()
    
    switch -Regex ($type) {
        '^INTEGER$|^INT$' { 'INT' }
        '^REAL$|^FLOAT$|^DOUBLE$' { 'FLOAT' }
        '^NUMERIC$' { 'DECIMAL(18,2)' }
        '^TEXT$|^VARCHAR$|^CHAR$' { 'NVARCHAR(MAX)' }
        '^BLOB$' { 'VARBINARY(MAX)' }
        default { 'NVARCHAR(MAX)' }
    }
}

function Get-SQLiteTables {
    param([string]$DataSource)
    $tables = Invoke-SqliteQuery -DataSource $DataSource -Query "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name"
    return $tables | Select-Object -Property name, sql
}

function Get-SQLiteForeignKeys {
    param(
        [Parameter(Mandatory)]
        [string]$DataSource,
        [Parameter(Mandatory)]
        [string]$TableName
    )

    try {
        $fks = Invoke-SqliteQuery -DataSource $DataSource -Query "PRAGMA foreign_key_list([$TableName])"
        if ($fks) {
            return $fks | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    FromColumn = $_.from
                    ToTable = $_.table
                    ToColumn = $_.to
                }
            }
        }
        return @()
    }
    catch {
        Write-Verbose "Could not retrieve foreign keys for table $TableName : $_"
        return @()
    }
}

function Parse-SqlitePrimaryKeyInfo {
    param(
        [Parameter(Mandatory)]
        [string]$CreateTableSql,
        [Parameter(Mandatory)]
        [string[]]$ColumnNames
    )

    $result = @{ Columns = @(); AutoIncrement = $null }

    if (-not $CreateTableSql) { return $result }

    $ddl = $CreateTableSql -replace '\s+', ' '
    $ddlLower = $ddl.ToLower()

    # Find table-level PRIMARY KEY
    $tablePkMatch = [regex]::Match($ddlLower, 'primary\s+key\s*\(\s*([^\)]+)\s*\)')
    if ($tablePkMatch.Success) {
        $colsRaw = $tablePkMatch.Groups[1].Value
        # Split by comma and clean up each column name (remove brackets, quotes)
        $cols = $colsRaw -split ',' | ForEach-Object { 
            $cleaned = $_.Trim()
            # Remove square brackets and quotes, but PRESERVE spaces within column names
            $cleaned = $cleaned -replace '[\[\]"`'']', ''
            $cleaned = $cleaned.Trim()
            $cleaned
        }
        $result.Columns = $cols
    }
        
    # Find column-level PRIMARY KEY and AUTOINCREMENT
    foreach ($col in $ColumnNames) {
        $pattern = [regex]::Escape($col.ToLower()) + '\s+[^\),]*primary\s+key'
        if ([regex]::IsMatch($ddlLower, $pattern)) {
            if (-not ($result.Columns -contains $col)) {
                $result.Columns += $col
            }
        }

        $autopattern1 = [regex]::Escape($col.ToLower()) + '\s+[^\),]*autoincrement'
        $autopattern2 = [regex]::Escape($col.ToLower()) + '\s+integer\s+[^\),]*primary\s+key'
        if ([regex]::IsMatch($ddlLower, $autopattern1) -or [regex]::IsMatch($ddlLower, $autopattern2)) {
            $result.AutoIncrement = $col
            if (-not ($result.Columns -contains $col)) {
                $result.Columns += $col
            }
        }
    }

    # Normalize column names
    $normalized = @()
    foreach ($c in $result.Columns) {
        $matched = $ColumnNames | Where-Object { $_.ToLower() -eq $c.ToLower() }
        if ($matched) { 
            # $matched kan een string zijn (1 result) of een array (meerdere results)
            # Als het een string is, neem de hele string, niet het eerste karakter
            if ($matched -is [string]) {
                $normalized += $matched
            } else {
                $normalized += $matched[0]
            }
        } else {
            $normalized += $c
        }
    }
    $result.Columns = $normalized

    return $result
}

function Convert-SQLiteToSqlServer {
    <#
    .SYNOPSIS
    Migrates SQLite database to SQL Server with validation
    
    .PARAMETER BatchSize
    Number of rows to insert per batch (default: 1000)
    
    .PARAMETER ValidateChecksum
    Validates data integrity using checksums after migration
    
    .PARAMETER GenerateReport
    Automatically generates an Excel migration report after completion
    
    .PARAMETER ReportPath
    Custom path for the migration report (default: .\Reports\SQLite_to_SQL_<timestamp>.xlsx)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SQLitePath,
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        [Parameter(Mandatory)]
        [string]$Database,
        [string[]]$Tables = @(),
        
        [Parameter()]
        [int]$BatchSize = 1000,
        
        [Parameter()]
        [switch]$ValidateChecksum,
        
        [Parameter()]
        [switch]$GenerateReport,
        
        [Parameter()]
        [string]$ReportPath
    )

    process {
        try {
            $startTime = Get-Date
            
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║     SQLite → SQL Server Migration             ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host "Source: $SQLitePath" -ForegroundColor Gray
            Write-Host "Target: $ServerInstance.$Database" -ForegroundColor Gray

            Write-Host "`n[1/5] Analyzing SQLite schema..." -ForegroundColor Yellow

            $allTables = Get-SQLiteTables -DataSource $SQLitePath
            if ($Tables.Count -eq 0) {
                $Tables = $allTables.name
            } else {
                $allTables = $allTables | Where-Object { $Tables -contains $_.name }
            }

            $ddlMap = @{}
            foreach ($row in $allTables) {
                $ddlMap[$row.name] = $row.sql
            }

            $parentTables = @('Customers', 'Products')
            $sortedTables = @()
            $sortedTables += $parentTables | Where-Object { $_ -in $Tables }
            $sortedTables += $Tables | Where-Object { $_ -notin $parentTables }
            $Tables = $sortedTables

            Write-Host "Tables to migrate: $($Tables -join ', ')" -ForegroundColor Gray
            Write-Host "Found $($Tables.Count) tables to migrate" -ForegroundColor Gray
            Write-Host "Migration order: $($Tables -join ' → ')" -ForegroundColor DarkGray

            Write-Host "`n[2/5] Creating SQL Server database..." -ForegroundColor Yellow
            $createDbQuery = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = '$Database')
BEGIN
    ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$Database];
END
CREATE DATABASE [$Database];
"@
            Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query $createDbQuery
            Write-Host " Database created" -ForegroundColor Green

            Write-Host "`n[3/5] Migrating tables..." -ForegroundColor Yellow
            $migrationResults = @()
            $totalRows = 0

            foreach ($tableName in $Tables) {
                Write-Host "`n  Migrating: $tableName" -ForegroundColor Cyan
                try {
                    $schema = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA table_info([$tableName])"
                    $columnNames = $schema | Select-Object -ExpandProperty name

                    $createTableSql = $null
                    if ($ddlMap.ContainsKey($tableName)) { $createTableSql = $ddlMap[$tableName] }

                    $pkInfo = Parse-SqlitePrimaryKeyInfo -CreateTableSql $createTableSql -ColumnNames $columnNames
                    $pkColumns = $pkInfo.Columns
                    $autoIncCol = $pkInfo.AutoIncrement

                    $columnDefs = foreach ($col in $schema) {
                        $colName = $col.name
                        if ($col.pk -eq 1 -and $col.type -match 'INTEGER') {
                            $sqlType = 'INT'
                        }
                        else {
                            $sqlType = ConvertTo-SqlServerDataType -SQLiteType $col.type
                        }
                        
                        # IDENTITY columns MUST be NOT NULL
                        $isIdentity = ($autoIncCol -and ($colName -eq $autoIncCol) -and ($sqlType -match '^INT'))
                        
                        if ($isIdentity -or $col.notnull -eq 1) {
                            $nullable = 'NOT NULL'
                        } else {
                            $nullable = 'NULL'
                        }

                        if ($isIdentity) {
                            "[$colName] $sqlType IDENTITY(1,1) $nullable"
                        }
                        else {
                            "[$colName] $sqlType $nullable"
                        }
                    }

                    if ($pkColumns.Count -gt 0) {
                        $pkConstraint = "CONSTRAINT [PK_$tableName] PRIMARY KEY ([$($pkColumns -join '], [')])"
                        $columnDefs += $pkConstraint
                    }

                    $createTableSqlServer = "CREATE TABLE [$tableName] ($($columnDefs -join ', '))"

                    Write-Host "    Creating schema..." -ForegroundColor Gray
                    Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $createTableSqlServer

                    Write-Host "    Fetching data..." -ForegroundColor Gray
                    $data = Invoke-SqliteQuery -DataSource $SQLitePath -Query "SELECT * FROM [$tableName]"

                    if ($null -eq $data -or $data.Count -eq 0) {
                        Write-Host "     Empty table" -ForegroundColor Yellow
                        $migrationResults += [PSCustomObject]@{ TableName=$tableName; RowsMigrated=0; Success=$true }
                        continue
                    }

                    # Calculate source checksum if validation requested
                    $sourceChecksum = $null
                    if ($ValidateChecksum) {
                        Write-Verbose "Calculating source checksum for $tableName..."
                        $sourceChecksum = Get-DataChecksum -DatabaseType SQLite -SQLitePath $SQLitePath -TableName $tableName
                    }

                    Write-Host "    Inserting $($data.Count) rows..." -ForegroundColor Gray
                    $insertedRows = 0
                    $columnNames = $schema | Select-Object -ExpandProperty name

                    $identityRequired = $false
                    if ($autoIncCol) { $identityRequired = $true }

                    # Process data in batches
                    $totalDataRows = @($data).Count
                    
                    for ($i = 0; $i -lt $totalDataRows; $i += $BatchSize) {
                        $batchEnd = [Math]::Min($i + $BatchSize, $totalDataRows)
                        $batchData = $data[$i..($batchEnd - 1)]
                        
                        # Build all INSERT statements for this batch
                        $insertStatements = foreach ($row in $batchData) {
                            $values = foreach ($colName in $columnNames) {
                                $value = $row.$colName
                                if ($null -eq $value -or $value -eq '') {
                                    'NULL'
                                } else {
                                    $escaped = $value.ToString().Replace("'", "''")
                                    "N'$escaped'"
                                }
                            }
                            
                            "INSERT INTO [$tableName] ([$($columnNames -join '],[')])
                             VALUES ($($values -join ','));"
                        }

                        # Execute batch with IDENTITY_INSERT if needed
                        $batchQuery = ""
                        if ($identityRequired -and $i -eq 0) {
                            $batchQuery += "SET IDENTITY_INSERT [$tableName] ON;`n"
                        }
                        $batchQuery += $insertStatements -join "`n"
                        if ($identityRequired -and $batchEnd -ge $totalDataRows) {
                            $batchQuery += "`nSET IDENTITY_INSERT [$tableName] OFF;"
                        }
                        
                        try {
                            Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $batchQuery
                            $insertedRows += $batchData.Count
                            
                            if (($i / $BatchSize) % 10 -eq 0) {
                                Write-Verbose "  Inserted $insertedRows / $totalDataRows rows..."
                            }
                        }
                        catch {
                            Write-Verbose "Batch insert failed: $_"
                            break
                        }
                    }

                    # Validate row count
                    $destRowCount = (Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate `
                        -Query "SELECT COUNT(*) as cnt FROM [$tableName]").cnt
                    
                    if ($destRowCount -ne $totalDataRows) {
                        Write-Warning "     Row count mismatch! Source: $totalDataRows, Destination: $destRowCount"
                    }
                    
                    # Validate checksum if requested
                    if ($ValidateChecksum -and $sourceChecksum) {
                        $destChecksum = Get-DataChecksum -DatabaseType SqlServer -ServerInstance $ServerInstance -Database $Database -TableName $tableName
                        $validation = Test-DataIntegrity -SourceChecksum $sourceChecksum -DestinationChecksum $destChecksum
                        
                        if (-not $validation.Valid) {
                            Write-Warning "     Data integrity check failed!"
                            Write-Warning "      Row count match: $($validation.RowCountMatch)"
                            Write-Warning "      Checksum match: $($validation.ChecksumMatch)"
                        } else {
                            Write-Host "     Data integrity validated" -ForegroundColor Green
                        }
                    }

                    Write-Host "     Migrated $insertedRows rows" -ForegroundColor Green
                    $totalRows += $insertedRows
                    $migrationResults += [PSCustomObject]@{ 
                        TableName = $tableName
                        RowsMigrated = $insertedRows
                        RowCountMatch = ($destRowCount -eq $totalDataRows)
                        Success = $true
                    }
                }
                catch {
                    Write-Host "      Failed: $_" -ForegroundColor Red
                    $migrationResults += [PSCustomObject]@{ TableName=$tableName; RowsMigrated=0; Success=$false; Error=$_.Exception.Message }
                }
            }

            Write-Host "`n[4/5] Adding foreign keys..." -ForegroundColor Yellow
            $fkCount = 0
            foreach ($tableName in $Tables) {
                $fks = Get-SQLiteForeignKeys -DataSource $SQLitePath -TableName $tableName
                foreach ($fk in $fks) {
                    try {
                        $fkName = "FK_$($tableName)_$($fk.ToTable)_$($fk.FromColumn)"
                        $fkQuery = "ALTER TABLE [$tableName] ADD CONSTRAINT [$fkName] FOREIGN KEY ([$($fk.FromColumn)]) REFERENCES [$($fk.ToTable)]([$($fk.ToColumn)])"
                        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $fkQuery
                        Write-Host "     Added FK: $fkName" -ForegroundColor Green
                        $fkCount++
                    }
                    catch {
                        Write-Host "     Could not add FK: $_" -ForegroundColor Yellow
                    }
                }
            }

            Write-Host "`n[5/5] Verification..." -ForegroundColor Yellow
            Write-Host "Tables in SQL Server: $($Tables.Count)" -ForegroundColor Gray

            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║            MIGRATION SUMMARY                   ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host "Tables migrated: $($migrationResults.Count)" -ForegroundColor Gray
            Write-Host "Total rows: $totalRows" -ForegroundColor Gray

            $successCount = ($migrationResults | Where-Object { $_.Success }).Count
            if ($successCount -eq $migrationResults.Count) {
                Write-Host " Migration completed successfully!" -ForegroundColor Green
            } else {
                Write-Host " Migration completed with errors" -ForegroundColor Yellow
            }

            $endTime = Get-Date
            $executionTime = ($endTime - $startTime)
            
            # Format tijd afhankelijk van duur
            if ($executionTime.TotalSeconds -lt 1) {
                $executionTimeString = "{0:0.000} seconds" -f $executionTime.TotalSeconds
            } elseif ($executionTime.TotalMinutes -lt 1) {
                $executionTimeString = "{0:0.00} seconds" -f $executionTime.TotalSeconds
            } else {
                $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
            }
            
            Write-Host "Execution time: $executionTimeString" -ForegroundColor Gray

            $migrationResult = [PSCustomObject]@{ 
                Success = ($successCount -eq $migrationResults.Count)
                Results = $migrationResults
                TotalRows = $totalRows
                SQLitePath = $SQLitePath
                PrimaryKeysAdded = $Tables.Count
                ForeignKeysAdded = $fkCount
                StartTime = $startTime
                EndTime = $endTime
                ExecutionTime = $executionTime
                ExecutionTimeFormatted = $executionTimeString
            }
            
            # Auto-generate report if requested
            if ($GenerateReport) {
                Write-Host "`n" -NoNewline
                if (-not $ReportPath) {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $ReportPath = ".\Reports\SQLite_to_SQL_$timestamp.xlsx"
                }
                
                try {
                    Export-MigrationReport `
                        -MigrationResults $migrationResult `
                        -OutputPath $ReportPath `
                        -MigrationName "SQLite → SQL Server: $Database"
                }
                catch {
                    Write-Warning "Failed to generate migration report: $_"
                }
            }

            return $migrationResult
        }
        catch {
            Write-Error "Migration failed: $_"
            throw
        }
    }
}

#endregion

#region SQL Server to SQLite Migration

function Get-TableDependencyOrder {
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Tables
    )
    
    if ($Tables.Count -eq 0) {
        return @()
    }
    
    $allFks = @()
    try {
        $allFks = Invoke-Sqlcmd -ServerInstance $ServerInstance `
            -Database $Database `
            -TrustServerCertificate `
            -Query @"
SELECT 
    t.name AS TableName,
    rt.name AS ReferencedTable
FROM sys.foreign_keys fk
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id
WHERE t.name IN ('$($Tables -join "','")')
"@
    }
    catch {
        Write-Verbose "No foreign keys found or error querying: $_"
    }
    
    if ($null -eq $allFks -or $allFks.Count -eq 0) {
        Write-Verbose "No foreign key dependencies found, using original order"
        return $Tables
    }
    
    $dependencies = @{}
    foreach ($table in $Tables) {
        $dependencies[$table] = @()
    }
    
    foreach ($fk in $allFks) {
        if ($fk.ReferencedTable -in $Tables) {
            if (-not $dependencies[$fk.TableName].Contains($fk.ReferencedTable)) {
                $dependencies[$fk.TableName] += $fk.ReferencedTable
            }
        }
    }
    
    $sorted = [System.Collections.ArrayList]@()
    $visited = @{}
    $visiting = @{}
    
    function Visit-Table {
        param(
            [string]$tableName,
            [ref]$sortedRef,
            [ref]$visitedRef,
            [ref]$visitingRef,
            [hashtable]$deps
        )
        
        if ($visitedRef.Value[$tableName]) { return }
        if ($visitingRef.Value[$tableName]) {
            Write-Warning "Circular dependency detected at $tableName"
            return
        }
        
        $visitingRef.Value[$tableName] = $true
        
        foreach ($dep in $deps[$tableName]) {
            Visit-Table -tableName $dep -sortedRef $sortedRef -visitedRef $visitedRef -visitingRef $visitingRef -deps $deps
        }
        
        $visitingRef.Value[$tableName] = $false
        $visitedRef.Value[$tableName] = $true
        [void]$sortedRef.Value.Add($tableName)
    }
    
    foreach ($table in $Tables) {
        Visit-Table -tableName $table -sortedRef ([ref]$sorted) -visitedRef ([ref]$visited) -visitingRef ([ref]$visiting) -deps $dependencies
    }
    
    if ($sorted.Count -ne $Tables.Count) {
        Write-Warning "Topological sort incomplete (sorted: $($sorted.Count), total: $($Tables.Count)), using original order"
        return $Tables
    }
    
    return $sorted
}

function Convert-SqlServerToSQLite {
    <#
    .SYNOPSIS
    Migrates a complete SQL Server database to SQLite
    
    .PARAMETER ServerInstance
    SQL Server instance name
    
    .PARAMETER Database
    SQL Server database name
    
    .PARAMETER SQLitePath
    Path for the SQLite database file
    
    .PARAMETER Tables
    Optional: Specific tables to migrate
    
    .PARAMETER GenerateReport
    Automatically generates an Excel migration report after completion
    
    .PARAMETER ReportPath
    Custom path for the migration report (default: .\Reports\SQL_to_SQLite_<timestamp>.xlsx)
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$SQLitePath,
        
        [string[]]$Tables = @(),
        
        [Parameter()]
        [switch]$GenerateReport,
        
        [Parameter()]
        [string]$ReportPath
    )
    
    process {
        try {
            $startTime = Get-Date
            
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║     SQL Server → SQLite Migration             ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host "Source: $ServerInstance.$Database" -ForegroundColor Gray
            Write-Host "Target: $SQLitePath" -ForegroundColor Gray
            
            Write-Host "`n[1/4] Analyzing SQL Server schema..." -ForegroundColor Yellow
            
            if ($Tables.Count -eq 0) {
                $Tables = (Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'").TABLE_NAME
            }
            
            Write-Host "Found $($Tables.Count) tables" -ForegroundColor Gray
            
            $sortedTables = Get-TableDependencyOrder -ServerInstance $ServerInstance -Database $Database -Tables $Tables
            Write-Host "Migration order: $($sortedTables -join ' → ')" -ForegroundColor DarkGray
            
            Write-Host "`n[2/4] Creating SQLite database..." -ForegroundColor Yellow
            if (Test-Path $SQLitePath) {
                Remove-Item $SQLitePath -Force
                Write-Host "Removed existing SQLite file" -ForegroundColor Gray
            }
            
            $parentDir = Split-Path $SQLitePath -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            
            Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA foreign_keys = ON;"
            Write-Host " SQLite database created" -ForegroundColor Green
            
            Write-Host "`n[3/4] Migrating tables..." -ForegroundColor Yellow
            $migrationResults = @()
            $totalRows = 0
            $foreignKeys = @{}
            $pkCount = 0
            $fkCount = 0
            
            foreach ($tableName in $sortedTables) {
                Write-Host "`n  Migrating: $tableName" -ForegroundColor Cyan
                
                try {
                    $columns = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query @"
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$tableName'
ORDER BY ORDINAL_POSITION
"@

                    $pkColumns = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query @"
SELECT c.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
    AND tc.TABLE_NAME = c.TABLE_NAME
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.TABLE_NAME = '$tableName'
ORDER BY c.ORDINAL_POSITION
"@

                    $fks = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query @"
SELECT 
    fk.name AS FK_Name,
    c.name AS ColumnName,
    rt.name AS ReferencedTable,
    rc.name AS ReferencedColumn
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns c ON fkc.parent_column_id = c.column_id AND fkc.parent_object_id = c.object_id
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id
INNER JOIN sys.columns rc ON fkc.referenced_column_id = rc.column_id AND fkc.referenced_object_id = rc.object_id
WHERE t.name = '$tableName'
"@
                    
                    if ($fks) {
                        $foreignKeys[$tableName] = $fks
                    }
                    
                    $pkColumnNames = @()
                    if ($pkColumns) {
                        $pkColumnNames = $pkColumns | Select-Object -ExpandProperty COLUMN_NAME
                    }
                    
                    $columnDefs = foreach ($col in $columns) {
                        $colName = $col.COLUMN_NAME
                        $dataType = ConvertTo-SQLiteDataType -SqlServerType $col.DATA_TYPE
                        $nullable = if ($col.IS_NULLABLE -eq 'NO') { 'NOT NULL' } else { '' }
                        
                        $fkDef = ''
                        $fk = $fks | Where-Object { $_.ColumnName -eq $colName } | Select-Object -First 1
                        if ($fk) {
                            $fkDef = "REFERENCES [$($fk.ReferencedTable)]([$($fk.ReferencedColumn)])"
                        }
                        
                        "[$colName] $dataType $nullable $fkDef".Trim()
                    }
                    
                    if ($pkColumnNames.Count -gt 0) {
                        $pkConstraint = "PRIMARY KEY ([$($pkColumnNames -join '], [')])"
                        $columnDefs += $pkConstraint
                    }
                    
                    $createTableSql = "CREATE TABLE [$tableName] ($($columnDefs -join ', '))"
                    
                    Write-Host "    Creating schema..." -ForegroundColor Gray
                    Invoke-SqliteQuery -DataSource $SQLitePath -Query $createTableSql
                    
                    $constraintInfo = @()
                    if ($pkColumnNames.Count -gt 0) {
                        $constraintInfo += "$($pkColumnNames.Count) PK"
                        $pkCount++
                    }
                    if ($fks) {
                        $constraintInfo += "$($fks.Count) FK"
                        $fkCount += $fks.Count
                    }
                    
                    if ($constraintInfo.Count -gt 0) {
                        Write-Host "     Schema created with $($constraintInfo -join ', ')" -ForegroundColor Green
                    }
                    
                    Write-Host "    Fetching data..." -ForegroundColor Gray
                    $data = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query "SELECT * FROM [$tableName]"
                    
                    if ($null -eq $data -or $data.Count -eq 0) {
                        Write-Host "     Empty table" -ForegroundColor Yellow
                        $migrationResults += [PSCustomObject]@{
                            TableName = $tableName
                            RowsMigrated = 0
                            Success = $true
                        }
                        continue
                    }
                    
                    Write-Host "    Inserting $($data.Count) rows..." -ForegroundColor Gray
                    
                    $insertedRows = 0
                    $columnNames = $columns | Select-Object -ExpandProperty COLUMN_NAME
                    
                    try {
                        foreach ($row in $data) {
                            $values = foreach ($colName in $columnNames) {
                                $value = $row.$colName
                                
                                if ($null -eq $value -or $value -eq '') {
                                    'NULL'
                                } else {
                                    $escaped = $value.ToString().Replace("'", "''")
                                    "'$escaped'"
                                }
                            }
                            
                            $insertQuery = "INSERT INTO [$tableName] ([$($columnNames -join '],[')])
                                           VALUES ($($values -join ','))"
                            
                            try {
                                Invoke-SqliteQuery -DataSource $SQLitePath -Query $insertQuery
                                $insertedRows++
                            }
                            catch {
                                Write-Verbose "Insert failed for row: $_"
                            }
                        }
                        
                        Write-Host "     Migrated $insertedRows rows" -ForegroundColor Green
                        
                        $totalRows += $insertedRows
                        
                        $migrationResults += [PSCustomObject]@{
                            TableName = $tableName
                            RowsMigrated = $insertedRows
                            Success = $true
                        }
                    }
                    catch {
                        Write-Host "      Failed: $_" -ForegroundColor Red
                        
                        $migrationResults += [PSCustomObject]@{
                            TableName = $tableName
                            RowsMigrated = 0
                            Success = $false
                            Error = $_.Exception.Message
                        }
                    }
                }
                catch {
                    Write-Host "      Table migration failed: $_" -ForegroundColor Red
                    
                    $migrationResults += [PSCustomObject]@{
                        TableName = $tableName
                        RowsMigrated = 0
                        Success = $false
                        Error = $_.Exception.Message
                    }
                }
            }
            
            Write-Host "`n[4/4] Verification..." -ForegroundColor Yellow
            $sqliteTables = Invoke-SqliteQuery -DataSource $SQLitePath -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" | Select-Object -ExpandProperty name
            Write-Host "Tables in SQLite: $($sqliteTables.Count)" -ForegroundColor Gray
            
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║            MIGRATION SUMMARY                   ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host "Tables migrated: $($migrationResults.Count)" -ForegroundColor Gray
            Write-Host "Total rows: $totalRows" -ForegroundColor Gray
            Write-Host "SQLite file: $SQLitePath" -ForegroundColor Gray
            
            if (Test-Path $SQLitePath) {
                Write-Host "File size: $([math]::Round((Get-Item $SQLitePath).Length / 1KB, 2)) KB" -ForegroundColor Gray
            }
            
            Write-Host "`nDetails:" -ForegroundColor Cyan
            $migrationResults | Format-Table -AutoSize
            
            $successCount = ($migrationResults | Where-Object { $_.Success }).Count
            
            if ($successCount -eq $migrationResults.Count) {
                Write-Host " Migration completed successfully!" -ForegroundColor Green
            } else {
                Write-Host " Migration completed with errors" -ForegroundColor Yellow
            }
            
            $endTime = Get-Date
            $executionTime = ($endTime - $startTime)
            
            # Format tijd afhankelijk van duur
            if ($executionTime.TotalSeconds -lt 1) {
                $executionTimeString = "{0:0.000} seconds" -f $executionTime.TotalSeconds
            } elseif ($executionTime.TotalMinutes -lt 1) {
                $executionTimeString = "{0:0.00} seconds" -f $executionTime.TotalSeconds
            } else {
                $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
            }
            
            Write-Host "Execution time: $executionTimeString" -ForegroundColor Gray
            
            $migrationResult = [PSCustomObject]@{
                Success = ($successCount -eq $migrationResults.Count)
                Results = $migrationResults
                TotalRows = $totalRows
                SQLitePath = $SQLitePath
                PrimaryKeysAdded = $pkCount
                ForeignKeysAdded = $fkCount
                StartTime = $startTime
                EndTime = $endTime
                ExecutionTime = $executionTime
                ExecutionTimeFormatted = $executionTimeString
            }
            
            # Auto-generate report if requested
            if ($GenerateReport) {
                Write-Host "`n" -NoNewline
                if (-not $ReportPath) {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $ReportPath = ".\Reports\SQL_to_SQLite_$timestamp.xlsx"
                }
                
                try {
                    Export-MigrationReport `
                        -MigrationResults $migrationResult `
                        -OutputPath $ReportPath `
                        -MigrationName "SQL Server → SQLite: $Database"
                }
                catch {
                    Write-Warning "Failed to generate migration report: $_"
                }
            }
            
            return $migrationResult
        }
        catch {
            Write-Error "Migration failed: $_"
            throw
        }
    }
}

#endregion

#region CSV Export

function Export-DatabaseSchemaToCsv {
    <#
    .SYNOPSIS
    Exports entire database schema to CSV files with metadata (preserves PKs and FKs)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$OutputFolder,
        
        [string[]]$Tables = @()
    )
    
    process {
        try {
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║     Database → CSV Export with Metadata       ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            
            # Create output folder
            if (-not (Test-Path $OutputFolder)) {
                New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            }
            
            # Get all tables if not specified
            if ($Tables.Count -eq 0) {
                $Tables = (Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'").TABLE_NAME
            }
            
            Write-Host "Exporting $($Tables.Count) tables..." -ForegroundColor Yellow
            
            $metadata = @{
                DatabaseName = $Database
                ExportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                Tables = @{}
            }
            
            foreach ($tableName in $Tables) {
                Write-Host "`n  Exporting: $tableName" -ForegroundColor Cyan
                
                # Get table schema
                $columns = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$tableName'
ORDER BY ORDINAL_POSITION
"@
                
                # Get primary key
                $pkInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    tc.CONSTRAINT_NAME,
    c.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
    AND tc.TABLE_NAME = c.TABLE_NAME
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.TABLE_NAME = '$tableName'
ORDER BY c.ORDINAL_POSITION
"@
                
                # Get foreign keys
                $fkInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    fk.name AS CONSTRAINT_NAME,
    c.name AS COLUMN_NAME,
    rt.name AS REFERENCED_TABLE,
    rc.name AS REFERENCED_COLUMN
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns c ON fkc.parent_column_id = c.column_id AND fkc.parent_object_id = c.object_id
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id
INNER JOIN sys.columns rc ON fkc.referenced_column_id = rc.column_id AND fkc.referenced_object_id = rc.object_id
WHERE t.name = '$tableName'
"@
                
                # Get row count
                $rowCountQuery = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT COUNT(*) as cnt FROM [$tableName]"
                
                # Get table size
                $tableStats = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    SUM(a.total_pages) * 8 as TotalSpaceKB,
    SUM(a.used_pages) * 8 as UsedSpaceKB,
    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 as UnusedSpaceKB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name = '$tableName'
GROUP BY t.name
"@
                
                # Get indexes
                $indexInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    i.name as IndexName,
    i.type_desc as IndexType,
    i.is_unique as IsUnique,
    i.is_primary_key as IsPrimaryKey,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) as Columns
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
INNER JOIN sys.tables t ON i.object_id = t.object_id
WHERE t.name = '$tableName' AND i.type > 0
GROUP BY i.name, i.type_desc, i.is_unique, i.is_primary_key
"@
                
                # Get UNIQUE constraints
                $uniqueConstraints = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    tc.CONSTRAINT_NAME,
    STRING_AGG(c.COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY c.ORDINAL_POSITION) as Columns
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
    AND tc.TABLE_NAME = c.TABLE_NAME
WHERE tc.CONSTRAINT_TYPE = 'UNIQUE' 
    AND tc.TABLE_NAME = '$tableName'
GROUP BY tc.CONSTRAINT_NAME
"@
                
                # Get CHECK constraints
                $checkConstraints = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    cc.name as ConstraintName,
    cc.definition as CheckDefinition
FROM sys.check_constraints cc
INNER JOIN sys.tables t ON cc.parent_object_id = t.object_id
WHERE t.name = '$tableName'
"@
                
                # Store metadata
                $tableMetadata = @{
                    RowCount = $rowCountQuery.cnt
                    TotalSpaceKB = if ($tableStats) { $tableStats.TotalSpaceKB } else { 0 }
                    UsedSpaceKB = if ($tableStats) { $tableStats.UsedSpaceKB } else { 0 }
                    UnusedSpaceKB = if ($tableStats) { $tableStats.UnusedSpaceKB } else { 0 }
                    Columns = @()
                    PrimaryKey = @()
                    ForeignKeys = @()
                    Indexes = @()
                    UniqueConstraints = @()
                    CheckConstraints = @()
                }
                
                foreach ($col in $columns) {
                    $tableMetadata.Columns += @{
                        Name = $col.COLUMN_NAME
                        DataType = $col.DATA_TYPE
                        MaxLength = $col.CHARACTER_MAXIMUM_LENGTH
                        IsNullable = ($col.IS_NULLABLE -eq 'YES')
                        DefaultValue = $col.COLUMN_DEFAULT
                    }
                }
                
                if ($pkInfo) {
                    $tableMetadata.PrimaryKey = @($pkInfo | ForEach-Object { $_.COLUMN_NAME })
                }
                
                if ($fkInfo) {
                    foreach ($fk in $fkInfo) {
                        $tableMetadata.ForeignKeys += @{
                            ConstraintName = $fk.CONSTRAINT_NAME
                            Column = $fk.COLUMN_NAME
                            ReferencedTable = $fk.REFERENCED_TABLE
                            ReferencedColumn = $fk.REFERENCED_COLUMN
                        }
                    }
                }
                
                if ($indexInfo) {
                    foreach ($idx in $indexInfo) {
                        $tableMetadata.Indexes += @{
                            Name = $idx.IndexName
                            Type = $idx.IndexType
                            IsUnique = ($idx.IsUnique -eq 1)
                            IsPrimaryKey = ($idx.IsPrimaryKey -eq 1)
                            Columns = $idx.Columns
                        }
                    }
                }
                
                if ($uniqueConstraints) {
                    foreach ($uc in $uniqueConstraints) {
                        $tableMetadata.UniqueConstraints += @{
                            ConstraintName = $uc.CONSTRAINT_NAME
                            Columns = $uc.Columns
                        }
                    }
                }
                
                if ($checkConstraints) {
                    foreach ($cc in $checkConstraints) {
                        $tableMetadata.CheckConstraints += @{
                            ConstraintName = $cc.ConstraintName
                            Definition = $cc.CheckDefinition
                        }
                    }
                }
                
                $metadata.Tables[$tableName] = $tableMetadata
                
                # Export data to CSV
                $csvPath = Join-Path $OutputFolder "$tableName.csv"
                $data = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT * FROM [$tableName]"
                
                if ($data) {
                    $data | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                    Write-Host "     Exported $($data.Count) rows to $tableName.csv" -ForegroundColor Green
                } else {
                    # Create empty CSV with headers
                    $headers = $columns | Select-Object -ExpandProperty COLUMN_NAME
                    $emptyData = [PSCustomObject]@{}
                    foreach ($h in $headers) { $emptyData | Add-Member -NotePropertyName $h -NotePropertyValue $null }
                    @($emptyData) | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                    Write-Host "     Empty table - created CSV with headers only" -ForegroundColor Yellow
                }
            }
            
            # Save metadata to JSON
            $metadataPath = Join-Path $OutputFolder "schema-metadata.json"
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Encoding UTF8
            Write-Host "`n Schema metadata saved to schema-metadata.json" -ForegroundColor Green
            
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║              EXPORT SUMMARY                    ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host "Tables exported: $($Tables.Count)" -ForegroundColor Gray
            Write-Host "Output folder: $OutputFolder" -ForegroundColor Gray
            Write-Host "Metadata file: schema-metadata.json" -ForegroundColor Gray
            
            return [PSCustomObject]@{
                Success = $true
                TablesExported = $Tables.Count
                OutputFolder = $OutputFolder
                MetadataPath = $metadataPath
            }
        }
        catch {
            Write-Error "Export failed: $_"
            throw
        }
    }
}

function Export-DatabaseSchemaToMarkdown {
    <#
    .SYNOPSIS
    Exports database schema to a human-readable Markdown document
    
    .DESCRIPTION
    Creates comprehensive documentation of the database schema including:
    - Tables with row counts and sizes
    - Column definitions
    - Primary keys, Foreign keys
    - Indexes
    - Constraints (UNIQUE, CHECK)
    
    .EXAMPLE
    Export-DatabaseSchemaToMarkdown -ServerInstance "localhost\SQLEXPRESS" -Database "SalesDB" -OutputPath "schema.md"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [string[]]$Tables = @()
    )
    
    process {
        try {
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║   Database Schema → Markdown Documentation    ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            
            # Get all tables if not specified
            if ($Tables.Count -eq 0) {
                $Tables = (Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'").TABLE_NAME
            }
            
            $markdown = [System.Text.StringBuilder]::new()
            
            # Header
            [void]$markdown.AppendLine("# Database Schema Documentation")
            [void]$markdown.AppendLine()
            [void]$markdown.AppendLine("**Database:** $Database")
            [void]$markdown.AppendLine("**Server:** $ServerInstance")
            [void]$markdown.AppendLine("**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            [void]$markdown.AppendLine()
            [void]$markdown.AppendLine("---")
            [void]$markdown.AppendLine()
            
            # Table of Contents
            [void]$markdown.AppendLine("## Table of Contents")
            [void]$markdown.AppendLine()
            foreach ($tableName in $Tables) {
                [void]$markdown.AppendLine("- [$tableName](#$($tableName.ToLower()))")
            }
            [void]$markdown.AppendLine()
            [void]$markdown.AppendLine("---")
            [void]$markdown.AppendLine()
            
            $totalRows = 0
            $totalSizeKB = 0
            
            foreach ($tableName in $Tables) {
                Write-Host "  Documenting: $tableName" -ForegroundColor Cyan
                
                [void]$markdown.AppendLine("## $tableName")
                [void]$markdown.AppendLine()
                
                # Get row count and size
                $rowCount = (Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT COUNT(*) as cnt FROM [$tableName]").cnt
                
                $tableStats = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    SUM(a.total_pages) * 8 as TotalSpaceKB,
    SUM(a.used_pages) * 8 as UsedSpaceKB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name = '$tableName'
GROUP BY t.name
"@
                
                $sizeKB = if ($tableStats) { $tableStats.TotalSpaceKB } else { 0 }
                $totalRows += $rowCount
                $totalSizeKB += $sizeKB
                
                [void]$markdown.AppendLine("**Row Count:** $rowCount")
                [void]$markdown.AppendLine("**Size:** $([Math]::Round($sizeKB / 1024, 2)) MB ($sizeKB KB)")
                [void]$markdown.AppendLine()
                
                # Get columns
                $columns = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$tableName'
ORDER BY ORDINAL_POSITION
"@
                
                # Columns table
                [void]$markdown.AppendLine("### Columns")
                [void]$markdown.AppendLine()
                [void]$markdown.AppendLine("| Column | Type | Nullable | Default |")
                [void]$markdown.AppendLine("|--------|------|----------|---------|")
                
                foreach ($col in $columns) {
                    $dataType = $col.DATA_TYPE
                    if ($col.CHARACTER_MAXIMUM_LENGTH) {
                        $dataType += "($($col.CHARACTER_MAXIMUM_LENGTH))"
                    }
                    $nullable = if ($col.IS_NULLABLE -eq 'YES') { '' } else { ' ' }
                    $default = if ($col.COLUMN_DEFAULT) { $col.COLUMN_DEFAULT } else { '' }
                    
                    [void]$markdown.AppendLine("| $($col.COLUMN_NAME) | $dataType | $nullable | $default |")
                }
                [void]$markdown.AppendLine()
                
                # Primary Key
                $pkInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT c.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
    AND tc.TABLE_NAME = c.TABLE_NAME
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.TABLE_NAME = '$tableName'
ORDER BY c.ORDINAL_POSITION
"@
                
                if ($pkInfo) {
                    [void]$markdown.AppendLine("### Primary Key")
                    [void]$markdown.AppendLine()
                    $pkColumns = ($pkInfo | ForEach-Object { $_.COLUMN_NAME }) -join ', '
                    [void]$markdown.AppendLine("- **Columns:** $pkColumns")
                    [void]$markdown.AppendLine()
                }
                
                # Foreign Keys
                $fkInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    fk.name as CONSTRAINT_NAME,
    c.name AS COLUMN_NAME,
    rt.name AS REFERENCED_TABLE,
    rc.name AS REFERENCED_COLUMN
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns c ON fkc.parent_column_id = c.column_id AND fkc.parent_object_id = c.object_id
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id
INNER JOIN sys.columns rc ON fkc.referenced_column_id = rc.column_id AND fkc.referenced_object_id = rc.object_id
WHERE t.name = '$tableName'
"@
                
                if ($fkInfo) {
                    [void]$markdown.AppendLine("### Foreign Keys")
                    [void]$markdown.AppendLine()
                    [void]$markdown.AppendLine("| Constraint | Column | References |")
                    [void]$markdown.AppendLine("|------------|--------|------------|")
                    
                    foreach ($fk in $fkInfo) {
                        [void]$markdown.AppendLine("| $($fk.CONSTRAINT_NAME) | $($fk.COLUMN_NAME) | $($fk.REFERENCED_TABLE)($($fk.REFERENCED_COLUMN)) |")
                    }
                    [void]$markdown.AppendLine()
                }
                
                # Indexes
                $indexInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    i.name as IndexName,
    i.type_desc as IndexType,
    i.is_unique as IsUnique,
    i.is_primary_key as IsPrimaryKey,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) as Columns
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
INNER JOIN sys.tables t ON i.object_id = t.object_id
WHERE t.name = '$tableName' AND i.type > 0
GROUP BY i.name, i.type_desc, i.is_unique, i.is_primary_key
"@
                
                if ($indexInfo) {
                    [void]$markdown.AppendLine("### Indexes")
                    [void]$markdown.AppendLine()
                    [void]$markdown.AppendLine("| Index Name | Type | Unique | Columns |")
                    [void]$markdown.AppendLine("|------------|------|--------|---------|")
                    
                    foreach ($idx in $indexInfo) {
                        $unique = if ($idx.IsUnique -eq 1) { '' } else { ' ' }
                        [void]$markdown.AppendLine("| $($idx.IndexName) | $($idx.IndexType) | $unique | $($idx.Columns) |")
                    }
                    [void]$markdown.AppendLine()
                }
                
                # UNIQUE Constraints
                $uniqueConstraints = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    tc.CONSTRAINT_NAME,
    STRING_AGG(c.COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY c.ORDINAL_POSITION) as Columns
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
    AND tc.TABLE_NAME = c.TABLE_NAME
WHERE tc.CONSTRAINT_TYPE = 'UNIQUE' 
    AND tc.TABLE_NAME = '$tableName'
GROUP BY tc.CONSTRAINT_NAME
"@
                
                if ($uniqueConstraints) {
                    [void]$markdown.AppendLine("### UNIQUE Constraints")
                    [void]$markdown.AppendLine()
                    [void]$markdown.AppendLine("| Constraint | Columns |")
                    [void]$markdown.AppendLine("|------------|---------|")
                    
                    foreach ($uc in $uniqueConstraints) {
                        [void]$markdown.AppendLine("| $($uc.CONSTRAINT_NAME) | $($uc.Columns) |")
                    }
                    [void]$markdown.AppendLine()
                }
                
                # CHECK Constraints
                $checkConstraints = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query @"
SELECT 
    cc.name as ConstraintName,
    cc.definition as CheckDefinition
FROM sys.check_constraints cc
INNER JOIN sys.tables t ON cc.parent_object_id = t.object_id
WHERE t.name = '$tableName'
"@
                
                if ($checkConstraints) {
                    [void]$markdown.AppendLine("### CHECK Constraints")
                    [void]$markdown.AppendLine()
                    [void]$markdown.AppendLine("| Constraint | Definition |")
                    [void]$markdown.AppendLine("|------------|------------|")
                    
                    foreach ($cc in $checkConstraints) {
                        [void]$markdown.AppendLine("| $($cc.ConstraintName) | ``$($cc.CheckDefinition)`` |")
                    }
                    [void]$markdown.AppendLine()
                }
                
                [void]$markdown.AppendLine("---")
                [void]$markdown.AppendLine()
            }
            
            # Summary
            [void]$markdown.AppendLine("## Database Summary")
            [void]$markdown.AppendLine()
            [void]$markdown.AppendLine("- **Total Tables:** $($Tables.Count)")
            [void]$markdown.AppendLine("- **Total Rows:** $totalRows")
            [void]$markdown.AppendLine("- **Total Size:** $([Math]::Round($totalSizeKB / 1024, 2)) MB ($totalSizeKB KB)")
            
            # Write to file
            $markdown.ToString() | Set-Content -Path $OutputPath -Encoding UTF8
            
            Write-Host "`n Markdown documentation saved to: $OutputPath" -ForegroundColor Green
            Write-Host "  Tables documented: $($Tables.Count)" -ForegroundColor Gray
            Write-Host "  Total size: $([Math]::Round($totalSizeKB / 1024, 2)) MB" -ForegroundColor Gray
            
            return [PSCustomObject]@{
                Success = $true
                TablesDocumented = $Tables.Count
                OutputPath = $OutputPath
                TotalRows = $totalRows
                TotalSizeKB = $totalSizeKB
            }
        }
        catch {
            Write-Error "Markdown export failed: $_"
            throw
        }
    }
}

function Export-SqlTableToCsv {
    <#
    .SYNOPSIS
    Exports a SQL Server table to CSV with optional header mapping
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory=$true)]
        [string]$Database,
        
        [Parameter(Mandatory=$true)]
        [string]$TableName,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$HeaderMapping,
        
        [Parameter(Mandatory=$false)]
        [switch]$InteractiveMapping
    )
    
    begin {
        Write-Verbose "Starting export of table '$TableName' from database '$Database'"
        
        $outputDir = Split-Path -Parent $OutputPath
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
    }
    
    process {
        try {
            # Check if table exists first
            $tableExists = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                                        -Database $Database `
                                        -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName'" `
                                        -TrustServerCertificate
            
            if ($tableExists.cnt -eq 0) {
                Write-Error "Table '$TableName' does not exist in database '$Database'"
                return [PSCustomObject]@{
                    TableName = $TableName
                    OutputPath = $OutputPath
                    RowCount = 0
                    Success = $false
                    ErrorMessage = "Table does not exist"
                }
            }
            
            Write-Verbose "Querying table '$TableName'..."
            $data = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                                  -Database $Database `
                                  -Query "SELECT * FROM [$TableName]" `
                                  -TrustServerCertificate
            
            if ($null -eq $data -or $data.Count -eq 0) {
                Write-Warning "Table '$TableName' is empty"
                return [PSCustomObject]@{
                    TableName = $TableName
                    OutputPath = $OutputPath
                    RowCount = 0
                    Success = $true
                }
            }
            
            Write-Verbose "Found $($data.Count) rows"
            
            if ($InteractiveMapping) {
                Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║     Interactive Header Mapping - $TableName" -ForegroundColor Cyan
                Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host "Press ENTER to keep original name, or type new name" -ForegroundColor Gray
                Write-Host ""
                
                $HeaderMapping = @{}
                $columnNames = $data[0].PSObject.Properties.Name
                
                foreach ($columnName in $columnNames) {
                    Write-Host "Column: " -NoNewline -ForegroundColor Yellow
                    Write-Host "$columnName" -ForegroundColor White
                    $newName = Read-Host "  New name (or ENTER to keep)"
                    
                    if (-not [string]::IsNullOrWhiteSpace($newName)) {
                        $HeaderMapping[$columnName] = $newName.Trim()
                        Write-Host "    → Mapped to: $($newName.Trim())" -ForegroundColor Green
                    } else {
                        Write-Host "    → Keeping: $columnName" -ForegroundColor Gray
                    }
                }
                
                Write-Host ""
            }
            
            if ($HeaderMapping -and $HeaderMapping.Count -gt 0) {
                Write-Verbose "Applying header mapping..."
                
                Write-Host "`nApplying header mapping:" -ForegroundColor Cyan
                foreach ($key in $HeaderMapping.Keys) {
                    Write-Host "  $key → $($HeaderMapping[$key])" -ForegroundColor Gray
                }
                
                $mappedData = foreach ($row in $data) {
                    $newRow = [ordered]@{}
                    
                    foreach ($prop in $row.PSObject.Properties) {
                        $oldName = $prop.Name
                        
                        if ($HeaderMapping.ContainsKey($oldName)) {
                            $newName = $HeaderMapping[$oldName]
                            $newRow[$newName] = $prop.Value
                        } else {
                            $newRow[$oldName] = $prop.Value
                        }
                    }
                    
                    [PSCustomObject]$newRow
                }
                
                $mappedData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                
                Write-Verbose "Applied header mapping for $($HeaderMapping.Count) columns"
            } else {
                $data | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }
            
            Write-Host " Exported $($data.Count) rows to $OutputPath" -ForegroundColor Green
            
            return [PSCustomObject]@{
                TableName = $TableName
                OutputPath = $OutputPath
                RowCount = $data.Count
                HeaderMapping = $HeaderMapping
                Success = $true
            }
        }
        catch {
            Write-Error "Export failed: $_"
            return [PSCustomObject]@{
                TableName = $TableName
                OutputPath = $OutputPath
                RowCount = 0
                Error = $_.Exception.Message
                Success = $false
            }
        }
    }
}

#endregion

#region CSV Import

function Import-CsvToSqlTable {
    <#
    .SYNOPSIS
    Imports CSV data into a SQL Server table with batch processing and transactional support
    
    .PARAMETER BatchSize
    Number of rows to insert per batch (default: 1000). Larger batches are faster but use more memory.
    
    .PARAMETER UseTransaction
    Wraps the entire import in a transaction. On error, all changes are rolled back.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$TableName,
        
        [Parameter(Mandatory)]
        [string]$CsvPath,
        
        [switch]$CreateTable,
        
        [Parameter()]
        [int]$BatchSize = 1000,
        
        [Parameter()]
        [switch]$UseTransaction
    )
    
    begin {
        Write-Verbose "Starting import from '$CsvPath' to table '$TableName'"
        
        function Get-SqlDataType {
            param([string]$Value, [string]$ColumnName, [bool]$IsPrimaryKey = $false)
            
            # Primary Key kolommen zijn altijd NOT NULL
            if ($IsPrimaryKey) {
                return "INT NOT NULL"
            }
            
            # Check voor GUID formaat (heeft voorrang boven ID check)
            if ($Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                return "UNIQUEIDENTIFIER NULL"
            }
            
            # Check voor DATETIME formaat (ISO 8601 of common date formats)
            if ($Value -match '^\d{4}-\d{2}-\d{2}') {
                return "DATETIME NULL"
            }
            
            # ID kolommen die NIET de PK zijn, zijn nullable (foreign keys kunnen NULL zijn)
            if ($ColumnName -like "*ID") {
                return "INT NULL"
            }
            
            if ($Value -match '^\d+$') {
                $num = [int64]$Value
                if ($num -le 2147483647) { return "INT" }
                return "BIGINT"
            }
            
            if ($Value -match '^\d+[,\.]\d+$') {
                return "DECIMAL(18,2)"
            }
            
            
            if ($Value -match '^(true|false|yes|no|0|1)$') {
                return "BIT"
            }
            
            $length = [Math]::Max($Value.Length * 2, 50)
            if ($length -gt 4000) { return "NVARCHAR(MAX)" }
            return "NVARCHAR($length)"
        }
        
        function ConvertTo-SqlString {
            param([string]$Value)
            
            if ($null -eq $Value -or $Value -eq '') {
                return 'NULL'
            }
            
            $escaped = $Value.Replace("'", "''")
            return "N'" + $escaped + "'"
        }
    }
    
    process {
        try {
            if (-not (Test-Path $CsvPath)) {
                throw "CSV file not found: $CsvPath"
            }
            
            Write-Host "Reading CSV file..." -ForegroundColor Cyan
            $csvData = Import-Csv -Path $CsvPath
            
            if ($null -eq $csvData -or $csvData.Count -eq 0) {
                throw "CSV file is empty or invalid"
            }
            
            Write-Host "Found $($csvData.Count) rows in CSV" -ForegroundColor Gray
            
            $tableCheck = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                -Database $Database `
                -TrustServerCertificate `
                -DisableVariables `
                -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName'"
            
            $tableExists = $tableCheck.cnt -gt 0
            
            if (-not $tableExists -and -not $CreateTable) {
                throw "Table '$TableName' does not exist. Use -CreateTable to create it automatically."
            }
            
            if (-not $tableExists -and $CreateTable) {
                Write-Host "Creating table '$TableName'..." -ForegroundColor Gray
                
                $firstRow = $csvData[0]
                $schema = @{}
                $maxLengths = @{}
                
                # Detecteer welke kolom de PK is (eindigt op ID en matcht tabelnaam, of eerste ID kolom)
                $pkColumn = $null
                $columnNames = $firstRow.PSObject.Properties.Name
                $idColumns = $columnNames | Where-Object { $_ -like "*ID" }
                
                if ($idColumns) {
                    # Zoek exact match met tabelnaam
                    $pkColumn = $idColumns | Where-Object { $_ -eq "${TableName}ID" } | Select-Object -First 1
                    if (-not $pkColumn) {
                        # Neem eerste ID kolom
                        $pkColumn = $idColumns | Select-Object -First 1
                    }
                }
                
                foreach ($prop in $firstRow.PSObject.Properties) {
                    $columnName = $prop.Name
                    $value = $prop.Value
                    
                    $isPK = ($columnName -eq $pkColumn)
                    $dataType = Get-SqlDataType -Value $value -ColumnName $columnName -IsPrimaryKey $isPK
                    $schema[$columnName] = $dataType
                    $maxLengths[$columnName] = if ($value) { $value.Length } else { 0 }
                }
                
                foreach ($row in $csvData) {
                    foreach ($prop in $row.PSObject.Properties) {
                        $columnName = $prop.Name
                        $value = $prop.Value
                        
                        if ($value -and $value.Length -gt $maxLengths[$columnName]) {
                            $maxLengths[$columnName] = $value.Length
                        }
                    }
                }
                
                $columnNames = @($schema.Keys)
                foreach ($columnName in $columnNames) {
                    if ($schema[$columnName] -like "NVARCHAR*") {
                        $maxLen = $maxLengths[$columnName]
                        $safeLength = [Math]::Max([Math]::Ceiling($maxLen * 1.2), 50)
                        
                        if ($safeLength -gt 4000) {
                            $schema[$columnName] = "NVARCHAR(MAX)"
                        } else {
                            $schema[$columnName] = "NVARCHAR($safeLength)"
                        }
                    }
                }
                
                $columnDefinitions = $schema.Keys | ForEach-Object {
                    $dataTypeDef = $schema[$_]
                    
                    # Check of de datatype definitie al NULL of NOT NULL bevat
                    if ($dataTypeDef -like "*NOT NULL*" -or $dataTypeDef -like "*NULL*") {
                        "[$_] $dataTypeDef"
                    } else {
                        "[$_] $dataTypeDef NULL"
                    }
                }
                
                $createTableSql = @"
CREATE TABLE [$TableName] (
    $($columnDefinitions -join ",`n    ")
)
"@
                
                Write-Verbose "Create table SQL: $createTableSql"
                
                Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -DisableVariables `
                    -Query $createTableSql
                
                Write-Host " Table created" -ForegroundColor Green
            }
            
            Write-Host "Importing data..." -ForegroundColor Cyan
            $importedRows = 0
            $errors = @()
            
            # Start transaction if requested
            if ($UseTransaction) {
                Write-Verbose "Starting transaction..."
                Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "BEGIN TRANSACTION" `
                    -ErrorAction Stop
            }
            
            try {
                # Process in batches
                $totalRows = $csvData.Count
                $batchNumber = 0
                
                for ($i = 0; $i -lt $totalRows; $i += $BatchSize) {
                    $batchNumber++
                    $batchEnd = [Math]::Min($i + $BatchSize, $totalRows)
                    $batch = $csvData[$i..($batchEnd - 1)]
                    
                    Write-Verbose "Processing batch $batchNumber (rows $($i+1)-$batchEnd of $totalRows)"
                    
                    # Build batch INSERT statement
                    $batchInserts = foreach ($row in $batch) {
                        try {
                            $columns = $row.PSObject.Properties.Name
                            $values = [System.Collections.ArrayList]@()
                            
                            foreach ($prop in $row.PSObject.Properties) {
                                $value = $prop.Value
                                
                                if ($null -eq $value -or $value -eq '') {
                                    [void]$values.Add('NULL')
                                } else {
                                    $strValue = [string]$value
                                    
                                    if ($strValue -match '^\d+$') {
                                        [void]$values.Add($strValue)
                                    } 
                                    elseif ($strValue -match '^\d+[,\.]\d+$') {
                                        $numValue = $strValue.Replace(',', '.')
                                        [void]$values.Add($numValue)
                                    } 
                                    else {
                                        [void]$values.Add((ConvertTo-SqlString -Value $strValue))
                                    }
                                }
                            }
                            
                            $sb = [System.Text.StringBuilder]::new()
                            [void]$sb.Append('INSERT INTO [')
                            [void]$sb.Append($TableName)
                            [void]$sb.Append('] ([')
                            [void]$sb.Append(($columns -join '],['))
                            [void]$sb.Append(']) VALUES (')
                            [void]$sb.Append(($values -join ','))
                            [void]$sb.Append(');')
                            
                            $sb.ToString()
                        }
                        catch {
                            $errorMsg = "Row preparation error: $($_.Exception.Message)"
                            $errors += $errorMsg
                            $null
                        }
                    }
                    
                    # Execute batch
                    $batchSql = $batchInserts -join "`n"
                    
                    try {
                        Invoke-Sqlcmd -ServerInstance $ServerInstance `
                            -Database $Database `
                            -TrustServerCertificate `
                            -DisableVariables `
                            -Query $batchSql `
                            -ErrorAction Stop
                        
                        $importedRows += $batch.Count
                        
                        if ($batchNumber % 10 -eq 0 -or $batchEnd -eq $totalRows) {
                            Write-Host "  Imported $importedRows / $totalRows rows..." -ForegroundColor Gray
                        }
                    }
                    catch {
                        $errorMsg = "Batch $batchNumber failed: $($_.Exception.Message)"
                        $errors += $errorMsg
                        Write-Warning $errorMsg
                        
                        if ($UseTransaction) {
                            throw "Batch import failed, rolling back transaction"
                        }
                    }
                }
                
                # Commit transaction if successful
                if ($UseTransaction) {
                    Write-Verbose "Committing transaction..."
                    Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query "COMMIT TRANSACTION"
                }
                
                Write-Host " Import completed!" -ForegroundColor Green
                Write-Host "  Rows imported: $importedRows" -ForegroundColor Gray
                
                if ($errors.Count -gt 0) {
                    Write-Warning "  Errors encountered: $($errors.Count)"
                    $errors | Select-Object -First 5 | ForEach-Object {
                        Write-Host "    $_" -ForegroundColor Red
                    }
                }
                
                return [PSCustomObject]@{
                    TableName = $TableName
                    RowsImported = $importedRows
                    RowsTotal = $csvData.Count
                    Errors = $errors
                    Success = $errors.Count -eq 0
                    BatchSize = $BatchSize
                    UsedTransaction = $UseTransaction.IsPresent
                }
            }
            catch {
                # Rollback on error if using transaction
                if ($UseTransaction) {
                    Write-Warning "Rolling back transaction due to error..."
                    try {
                        Invoke-Sqlcmd -ServerInstance $ServerInstance `
                            -Database $Database `
                            -TrustServerCertificate `
                            -Query "ROLLBACK TRANSACTION"
                        Write-Host " Transaction rolled back" -ForegroundColor Yellow
                    }
                    catch {
                        Write-Error "Failed to rollback transaction: $_"
                    }
                }
                
                Write-Error "Import failed: $_"
                return [PSCustomObject]@{
                    TableName = $TableName
                    RowsImported = $importedRows
                    RowsTotal = $csvData.Count
                    Errors = @($_.Exception.Message)
                    Success = $false
                    BatchSize = $BatchSize
                    UsedTransaction = $UseTransaction.IsPresent
                }
            }
        }
        catch {
            Write-Error "Import failed: $_"
            return [PSCustomObject]@{
                TableName = $TableName
                RowsImported = 0
                RowsTotal = 0
                Errors = @($_.Exception.Message)
                Success = $false
            }
        }
    }
}

function Find-ForeignKeysFromData {
    <#
    .SYNOPSIS
    Auto-detects foreign key relationships by analyzing database tables and data
    
    .DESCRIPTION
    Scans all tables for columns that might be foreign keys:
    - Columns ending in "ID" or "_ID"
    - Validates that values exist in potential referenced table's PK
    - Returns hashtable of detected foreign key constraints
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database
    )
    
    $detectedFKs = @{}
    
    try {
        # Get all tables
        $tablesQuery = @"
SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_TYPE = 'BASE TABLE'
"@
        $tables = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $tablesQuery
        
        # Get primary keys for all tables
        $primaryKeys = @{}
        foreach ($table in $tables) {
            $tableName = $table.TABLE_NAME
            
            $pkQuery = @"
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE TABLE_NAME = '$tableName'
  AND CONSTRAINT_NAME LIKE 'PK_%'
"@
            $pkResult = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $pkQuery -ErrorAction SilentlyContinue
            
            if ($pkResult) {
                $primaryKeys[$tableName] = $pkResult.COLUMN_NAME
            }
        }
        
        Write-Host "  Analyzing $($tables.Count) tables..." -ForegroundColor Gray
        
        # Check each table for potential FK columns
        foreach ($table in $tables) {
            $tableName = $table.TABLE_NAME
            
            # Get all columns for this table
            $columnsQuery = @"
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$tableName'
"@
            $columns = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $columnsQuery
            
            foreach ($column in $columns) {
                $columnName = $column.COLUMN_NAME
                
                # Check if column looks like a foreign key
                # Pattern 1: Ends with "ID" but not the table's own PK
                # Pattern 2: Format like "_TableNameID" or "_TableName"
                if ($columnName -match 'ID$' -and $columnName -ne $primaryKeys[$tableName]) {
                    
                    # Try to find referenced table
                    # Remove leading underscore if present
                    $cleanName = $columnName -replace '^_', ''
                    
                    # Remove "ID" suffix to get potential table name
                    $potentialTableName = $cleanName -replace 'ID$', ''
                    
                    # Check if a table with this name exists (case-insensitive)
                    $referencedTable = $tables | Where-Object { 
                        $_.TABLE_NAME -eq $potentialTableName -or 
                        $_.TABLE_NAME -eq "${potentialTableName}s" -or
                        "${_.TABLE_NAME}s" -eq $potentialTableName
                    } | Select-Object -First 1
                    
                    if ($referencedTable -and $primaryKeys.ContainsKey($referencedTable.TABLE_NAME)) {
                        $refTableName = $referencedTable.TABLE_NAME
                        $refPkColumn = $primaryKeys[$refTableName]
                        
                        # Validate: Check if all non-NULL values in FK column exist in referenced PK
                        $validationQuery = @"
SELECT COUNT(*) as InvalidCount
FROM [$tableName]
WHERE [$columnName] IS NOT NULL
  AND [$columnName] NOT IN (SELECT [$refPkColumn] FROM [$refTableName])
"@
                        $validationResult = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $validationQuery
                        
                        if ($validationResult.InvalidCount -eq 0) {
                            # Valid FK relationship found!
                            $fkName = "FK_${tableName}_${refTableName}"
                            $detectedFKs[$fkName] = @{
                                FromTable = $tableName
                                FromColumn = $columnName
                                ToTable = $refTableName
                                ToColumn = $refPkColumn
                            }
                            
                            Write-Host "     $tableName.$columnName → $refTableName.$refPkColumn" -ForegroundColor Green
                        }
                    }
                }
            }
        }
        
        return $detectedFKs
    }
    catch {
        Write-Warning "FK auto-detection error: $_"
        return @{}
    }
}

function Import-DatabaseFromCsv {
    <#
    .SYNOPSIS
    Batch imports multiple CSV files into SQL Server tables
    Automatically uses schema-metadata.json if present to restore PKs and FKs
    
    .PARAMETER GenerateReport
    Automatically generates an Excel migration report after completion
    
    .PARAMETER ReportPath
    Custom path for the migration report (default: .\Reports\CSV_Import_<timestamp>.xlsx)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$CsvFolder,
        
        [string[]]$TableOrder = @(),
        
        [switch]$DropTablesIfExist,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$PrimaryKeys,  

        [Parameter(Mandatory=$false)]
        [hashtable]$ForeignKeys,
        
        [Parameter()]
        [switch]$GenerateReport,
        
        [Parameter()]
        [string]$ReportPath
    )
    
    process {
        try {
            $startTime = Get-Date
            
            if (-not (Test-Path $CsvFolder)) {
                throw "CSV folder not found: $CsvFolder"
            }
            
            # Check for metadata file
            $metadataPath = Join-Path $CsvFolder "schema-metadata.json"
            $useMetadata = Test-Path $metadataPath
            
            if ($useMetadata) {
                Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║   CSV Import with Metadata (Schema Preserved) ║" -ForegroundColor Cyan
                Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host " Found schema-metadata.json - using stored schema" -ForegroundColor Green
                
                $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
                
                # Extract PKs and FKs from metadata
                $PrimaryKeys = @{}
                $ForeignKeys = @{}
                
                foreach ($tableName in $metadata.Tables.PSObject.Properties.Name) {
                    $tableInfo = $metadata.Tables.$tableName
                    
                    # Primary Keys
                    if ($tableInfo.PrimaryKey -and $tableInfo.PrimaryKey.Count -gt 0) {
                        if ($tableInfo.PrimaryKey.Count -eq 1) {
                            $PrimaryKeys[$tableName] = $tableInfo.PrimaryKey[0]
                        } else {
                            # Composite key - join with comma
                            $PrimaryKeys[$tableName] = $tableInfo.PrimaryKey -join ','
                        }
                    }
                    
                    # Foreign Keys
                    if ($tableInfo.ForeignKeys) {
                        foreach ($fk in $tableInfo.ForeignKeys) {
                            $fkName = $fk.ConstraintName
                            $ForeignKeys[$fkName] = @{
                                FromTable = $tableName
                                FromColumn = $fk.Column
                                ToTable = $fk.ReferencedTable
                                ToColumn = $fk.ReferencedColumn
                            }
                        }
                    }
                }
                
                Write-Host "Loaded from metadata:" -ForegroundColor Gray
                Write-Host "  - Primary Keys: $($PrimaryKeys.Count)" -ForegroundColor Gray
                Write-Host "  - Foreign Keys: $($ForeignKeys.Count)" -ForegroundColor Gray
            } else {
                Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║      CSV Import without Metadata               ║" -ForegroundColor Cyan
                Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host " No schema-metadata.json found - constraints may be lost" -ForegroundColor Yellow
            }
            
            $csvFiles = Get-ChildItem -Path $CsvFolder -Filter "*.csv"
            
            # Exclude metadata files
            $csvFiles = $csvFiles | Where-Object { $_.Name -ne "schema-metadata.json" }
            
            if ($csvFiles.Count -eq 0) {
                throw "No CSV files found in folder: $CsvFolder"
            }
            
            Write-Host "`n=== Batch CSV Import ===" -ForegroundColor Cyan
            Write-Host "Folder: $CsvFolder" -ForegroundColor Gray
            Write-Host "Files found: $($csvFiles.Count)" -ForegroundColor Gray
            Write-Host ""
            
            if ($TableOrder.Count -gt 0) {
                Write-Host "Using specified table order..." -ForegroundColor Yellow
                $importOrder = $TableOrder
            } else {
                Write-Host "Using automatic ordering (alphabetical)..." -ForegroundColor Yellow
                $importOrder = $csvFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
                $importOrder = $importOrder | Sort-Object
            }
            
            if ($DropTablesIfExist) {
                Write-Host "`nDropping existing tables..." -ForegroundColor Yellow
                
                $reversedOrder = $importOrder.Clone()
                [Array]::Reverse($reversedOrder)
                
                foreach ($tableName in $reversedOrder) {
                    try {
                        Invoke-Sqlcmd -ServerInstance $ServerInstance `
                            -Database $Database `
                            -TrustServerCertificate `
                            -Query "DROP TABLE IF EXISTS [$tableName]" `
                            -ErrorAction SilentlyContinue
                        
                        Write-Host "   Dropped $tableName" -ForegroundColor Gray
                    } catch {
                        Write-Verbose "Could not drop $tableName (might not exist)"
                    }
                }
            }
            
            $results = @()
            $totalRows = 0
            $successCount = 0
            
            Write-Host "`nImporting tables..." -ForegroundColor Cyan
            
            foreach ($tableName in $importOrder) {
                $csvPath = Join-Path $CsvFolder "$tableName.csv"
                
                if (-not (Test-Path $csvPath)) {
                    Write-Warning "CSV file not found for table '$tableName', skipping..."
                    continue
                }
                
                Write-Host "`n[$($successCount + 1)/$($importOrder.Count)] Importing $tableName..." -ForegroundColor Yellow
                
                $result = Import-CsvToSqlTable `
                    -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TableName $tableName `
                    -CsvPath $csvPath `
                    -CreateTable
                
                $results += $result
                $totalRows += $result.RowsImported
                
                if ($result.Success) {
                    $successCount++
                    Write-Host "   $($result.RowsImported) rows imported" -ForegroundColor Green
                } else {
                    Write-Host "    Import failed" -ForegroundColor Red
                    if ($result.Errors.Count -gt 0) {
                        $result.Errors | Select-Object -First 3 | ForEach-Object {
                            Write-Host "    $_" -ForegroundColor Red
                        }
                    }
                }
            }
            
            Write-Host "`n=== Import Summary ===" -ForegroundColor Cyan
            Write-Host "Tables processed: $($results.Count)" -ForegroundColor Gray
            Write-Host "Successful imports: $successCount" -ForegroundColor Green
            Write-Host "Failed imports: $($results.Count - $successCount)" -ForegroundColor $(if ($successCount -eq $results.Count) { "Gray" } else { "Red" })
            Write-Host "Total rows imported: $totalRows" -ForegroundColor Gray
            
            Write-Host "`nDetails:" -ForegroundColor Cyan
            $results | Select-Object TableName, RowsImported, Success | Format-Table -AutoSize
            
            if ($PrimaryKeys -and $PrimaryKeys.Count -gt 0) {
                Write-Host "`n=== Adding Primary Key Constraints ===" -ForegroundColor Cyan
                
                foreach ($tableName in $PrimaryKeys.Keys) {
                    $pkColumn = $PrimaryKeys[$tableName]
                    
                    try {
                        Write-Host "Adding PK to $tableName..." -ForegroundColor Gray
                        
                        # Sanitize table name voor constraint naam (verwijder speciale karakters)
                        $sanitizedName = $tableName -replace '[^a-zA-Z0-9_]', '_'
                        
                        $query = @"
ALTER TABLE [$tableName]
ADD CONSTRAINT [PK_$sanitizedName] 
PRIMARY KEY ([$pkColumn])
"@
                        
                        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $query -ErrorAction Stop
                        Write-Host "   Primary key added to $tableName" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "    Failed to add PK to $tableName : $_" -ForegroundColor Red
                    }
                }
            }
            
            # Auto-detect foreign keys if no metadata
            if (-not $useMetadata -or ($ForeignKeys -eq $null) -or ($ForeignKeys.Count -eq 0)) {
                Write-Host "`n=== Auto-Detecting Foreign Keys ===" -ForegroundColor Cyan
                $detectedFKs = Find-ForeignKeysFromData -ServerInstance $ServerInstance -Database $Database
                
                if ($detectedFKs.Count -gt 0) {
                    Write-Host "   Detected $($detectedFKs.Count) potential foreign key(s)" -ForegroundColor Green
                    $ForeignKeys = $detectedFKs
                } else {
                    Write-Host "   No foreign keys detected automatically" -ForegroundColor Yellow
                }
            }
            
            if ($ForeignKeys -and $ForeignKeys.Count -gt 0) {
                Write-Host "`n=== Adding Foreign Key Constraints ===" -ForegroundColor Cyan
                
                foreach ($fkName in $ForeignKeys.Keys) {
                    $fk = $ForeignKeys[$fkName]
                    
                    try {
                        Write-Host "Adding $fkName..." -ForegroundColor Gray
                        
                        # Sanitize FK name (verwijder speciale karakters)
                        $sanitizedFkName = $fkName -replace '[^a-zA-Z0-9_]', '_'
                        
                        $query = @"
ALTER TABLE [$($fk.FromTable)]
ADD CONSTRAINT [$sanitizedFkName] 
FOREIGN KEY ([$($fk.FromColumn)]) 
REFERENCES [$($fk.ToTable)]([$($fk.ToColumn)])
"@
                        
                        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $query -ErrorAction Stop
                        Write-Host "   $fkName added" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "    Failed to add $fkName : $_" -ForegroundColor Red
                    }
                }
            }

            $endTime = Get-Date
            $executionTime = ($endTime - $startTime)
            
            # Format tijd afhankelijk van duur
            if ($executionTime.TotalSeconds -lt 1) {
                $executionTimeString = "{0:0.000} seconds" -f $executionTime.TotalSeconds
            } elseif ($executionTime.TotalMinutes -lt 1) {
                $executionTimeString = "{0:0.00} seconds" -f $executionTime.TotalSeconds
            } else {
                $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
            }
            
            # Execution time wordt nu getoond door het wrapper script
            
            $importResult = [PSCustomObject]@{
                TablesProcessed = $results.Count
                SuccessfulImports = $successCount
                TotalRowsImported = $totalRows
                PrimaryKeysAdded = if ($PrimaryKeys) { $PrimaryKeys.Count } else { 0 }
                ForeignKeysAdded = if ($ForeignKeys) { $ForeignKeys.Count } else { 0 }
                Results = $results
                Success = ($successCount -eq $results.Count)
                StartTime = $startTime
                EndTime = $endTime
                ExecutionTime = $executionTime
                ExecutionTimeFormatted = $executionTimeString
            }
            
            # Auto-generate report if requested
            if ($GenerateReport) {
                Write-Host "`n" -NoNewline
                if (-not $ReportPath) {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $ReportPath = ".\Reports\CSV_Import_$timestamp.xlsx"
                }
                
                try {
                    Export-MigrationReport `
                        -MigrationResults $importResult `
                        -OutputPath $ReportPath `
                        -MigrationName "CSV Import: $Database"
                }
                catch {
                    Write-Warning "Failed to generate migration report: $_"
                }
            }
            
            return $importResult
        }
        catch {
            Write-Error "Batch import failed: $_"
            return [PSCustomObject]@{
                TablesProcessed = 0
                SuccessfulImports = 0
                TotalRowsImported = 0
                Results = @()
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

#endregion

#region Migration Reporting

function Export-MigrationReport {
    <#
    .SYNOPSIS
    Exports migration results to an Excel report with multiple sheets
    
    .DESCRIPTION
    Creates a comprehensive Excel report with:
    - Summary sheet (totals, success/failure ratio, execution times)
    - Details sheet (per-table breakdown)
    - Errors sheet (if any errors occurred)
    
    Requires the ImportExcel module to be installed.
    
    .PARAMETER MigrationResults
    The results object returned from a migration function (Convert-SQLiteToSqlServer, Convert-SqlServerToSQLite, etc.)
    
    .PARAMETER OutputPath
    Path for the Excel file to create (e.g., ".\Reports\Migration_Report.xlsx")
    
    .PARAMETER MigrationName
    Optional name for the migration (e.g., "SQLite to SQL Server - ProductionDB")
    
    .PARAMETER IncludeCharts
    Include pie charts in the summary sheet
    
    .EXAMPLE
    $result = Convert-SQLiteToSqlServer -SQLitePath ".\data\source.db" -ServerInstance "localhost\SQLEXPRESS" -Database "TargetDB"
    Export-MigrationReport -MigrationResults $result -OutputPath ".\Reports\Migration.xlsx" -MigrationName "SQLite to SQL Server"
    
    .EXAMPLE
    $result = Import-DatabaseFromCsv -ServerInstance "localhost\SQLEXPRESS" -Database "TestDB" -CsvFolder ".\Export"
    Export-MigrationReport -MigrationResults $result -OutputPath ".\Reports\CSV_Import.xlsx"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$MigrationResults,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter()]
        [string]$MigrationName = "Database Migration",
        
        [Parameter()]
        [switch]$IncludeCharts
    )
    
    process {
        try {
            # Check if ImportExcel module is available
            if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                Write-Warning "ImportExcel module not found. Installing..."
                try {
                    Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
                    Write-Host " ImportExcel module installed" -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to install ImportExcel module. Please install it manually: Install-Module -Name ImportExcel"
                    return
                }
            }
            
            Import-Module ImportExcel -ErrorAction Stop
            
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║        Creating Migration Report              ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            
            # Ensure output directory exists
            $outputDir = Split-Path -Path $OutputPath -Parent
            if ($outputDir -and -not (Test-Path $outputDir)) {
                New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
            }
            
            # Remove existing file if present
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force
            }
            
            $timestamp = Get-Date
            
            # Handle both PSCustomObject and OrderedDictionary for MigrationResults
            $results = if ($MigrationResults.Results) { $MigrationResults.Results } elseif ($MigrationResults['Results']) { $MigrationResults['Results'] } else { $null }
            $success = if ($null -ne $MigrationResults.Success) { $MigrationResults.Success } elseif ($null -ne $MigrationResults['Success']) { $MigrationResults['Success'] } else { $false }
            
            # Prepare summary data
            $totalTables = if ($results) { $results.Count } else { 0 }
            $successfulTables = if ($results) { 
                ($results | Where-Object { 
                    if ($_.Success) { $_.Success } elseif ($_['Success']) { $_['Success'] } else { $false }
                }).Count 
            } else { 0 }
            $failedTables = $totalTables - $successfulTables
            
            # Handle TotalRows (try multiple properties)
            $totalRows = if ($MigrationResults.TotalRows) { $MigrationResults.TotalRows } 
                         elseif ($MigrationResults['TotalRows']) { $MigrationResults['TotalRows'] }
                         elseif ($MigrationResults.TotalRowsImported) { $MigrationResults.TotalRowsImported }
                         elseif ($MigrationResults['TotalRowsImported']) { $MigrationResults['TotalRowsImported'] }
                         else { 0 }
            
            # Determine migration type
            $migrationType = "Unknown"
            $sqlitePath = if ($MigrationResults.SQLitePath) { $MigrationResults.SQLitePath } elseif ($MigrationResults['SQLitePath']) { $MigrationResults['SQLitePath'] } else { $null }
            $tablesProcessed = if ($MigrationResults.TablesProcessed) { $MigrationResults.TablesProcessed } elseif ($MigrationResults['TablesProcessed']) { $MigrationResults['TablesProcessed'] } else { $null }
            
            if ($sqlitePath) {
                $migrationType = "SQL Server ↔ SQLite"
            } elseif ($tablesProcessed) {
                $migrationType = "CSV Import"
            } elseif ($results -and $results.Count -gt 0) {
                $firstResult = $results[0]
                if (($firstResult.PSObject.Properties.Name -contains 'RowsMigrated') -or 
                    ($firstResult -is [System.Collections.Specialized.OrderedDictionary] -and $firstResult.Contains('RowsMigrated'))) {
                    $migrationType = "Database Migration"
                }
            }
            
            # Handle PrimaryKeysAdded and ForeignKeysAdded
            $primaryKeysAdded = if ($MigrationResults.PrimaryKeysAdded) { $MigrationResults.PrimaryKeysAdded } 
                                elseif ($MigrationResults['PrimaryKeysAdded']) { $MigrationResults['PrimaryKeysAdded'] }
                                else { "N/A" }
            $foreignKeysAdded = if ($MigrationResults.ForeignKeysAdded) { $MigrationResults.ForeignKeysAdded }
                                elseif ($MigrationResults['ForeignKeysAdded']) { $MigrationResults['ForeignKeysAdded'] }
                                else { "N/A" }
            
            # Calculate execution time (if available)
            $executionTime = "Not available"
            if ($MigrationResults.ExecutionTimeFormatted) {
                $executionTime = $MigrationResults.ExecutionTimeFormatted
            } elseif ($MigrationResults['ExecutionTimeFormatted']) {
                $executionTime = $MigrationResults['ExecutionTimeFormatted']
            } elseif ($MigrationResults.ExecutionTime) {
                $executionTime = "{0:hh\:mm\:ss}" -f $MigrationResults.ExecutionTime
            } elseif ($MigrationResults['ExecutionTime']) {
                $executionTime = "{0:hh\:mm\:ss}" -f $MigrationResults['ExecutionTime']
            } elseif ($MigrationResults.StartTime -and $MigrationResults.EndTime) {
                $duration = $MigrationResults.EndTime - $MigrationResults.StartTime
                $executionTime = "{0:hh\:mm\:ss}" -f $duration
            } elseif ($MigrationResults['StartTime'] -and $MigrationResults['EndTime']) {
                $duration = $MigrationResults['EndTime'] - $MigrationResults['StartTime']
                $executionTime = "{0:hh\:mm\:ss}" -f $duration
            }
            
            # 1. SUMMARY SHEET
            Write-Host "Creating Summary sheet..." -ForegroundColor Gray
            
            # Create summary as array to avoid OrderedDictionary issues with Export-Excel
            $summaryData = @(
                [PSCustomObject]@{ Property = 'Migration Name'; Value = $MigrationName }
                [PSCustomObject]@{ Property = 'Migration Type'; Value = $migrationType }
                [PSCustomObject]@{ Property = 'Date & Time'; Value = $timestamp.ToString("yyyy-MM-dd HH:mm:ss") }
                [PSCustomObject]@{ Property = 'Overall Status'; Value = if ($success) { " Success" } else { " Completed with errors" } }
                [PSCustomObject]@{ Property = ''; Value = '' }
                [PSCustomObject]@{ Property = 'Total Tables'; Value = $totalTables }
                [PSCustomObject]@{ Property = 'Successful Tables'; Value = $successfulTables }
                [PSCustomObject]@{ Property = 'Failed Tables'; Value = $failedTables }
                [PSCustomObject]@{ Property = 'Success Rate'; Value = if ($totalTables -gt 0) { "{0:P1}" -f ($successfulTables / $totalTables) } else { "N/A" } }
                [PSCustomObject]@{ Property = ' '; Value = '' }
                [PSCustomObject]@{ Property = 'Total Rows Migrated'; Value = $totalRows }
                [PSCustomObject]@{ Property = 'Primary Keys Added'; Value = $primaryKeysAdded }
                [PSCustomObject]@{ Property = 'Foreign Keys Added'; Value = $foreignKeysAdded }
                [PSCustomObject]@{ Property = '  '; Value = '' }
                [PSCustomObject]@{ Property = 'Execution Time'; Value = $executionTime }
            )
            
            try {
                $summaryData | Export-Excel -Path $OutputPath -WorksheetName "Summary" -AutoSize -TableStyle Medium2 -ErrorAction Stop
            }
            catch {
                Write-Error "Failed to create Summary sheet: $_"
                throw
            }
            
            # 2. DETAILS SHEET
            Write-Host "Creating Details sheet..." -ForegroundColor Gray
            
            if ($results -and $results.Count -gt 0) {
                $detailsData = foreach ($result in $results) {
                    # Handle both PSCustomObject and OrderedDictionary
                    $tableName = if ($result.TableName) { $result.TableName } elseif ($result['TableName']) { $result['TableName'] } else { "Unknown" }
                    $success = if ($null -ne $result.Success) { $result.Success } elseif ($null -ne $result['Success']) { $result['Success'] } else { $false }
                    
                    # Get error message (avoid using 'Error' property name to prevent PSScriptAnalyzer warnings)
                    $errorMsg = ""
                    if ($result.PSObject.Properties.Name -contains 'Error' -and $result.Error) {
                        $errorMsg = $result.Error
                    } elseif ($result -is [System.Collections.Specialized.OrderedDictionary] -and $result.Contains('Error')) {
                        $errorMsg = $result['Error']
                    }
                    
                    $rowCount = if ($result.RowsMigrated) { $result.RowsMigrated } 
                                elseif ($result['RowsMigrated']) { $result['RowsMigrated'] }
                                elseif ($result.RowsImported) { $result.RowsImported }
                                elseif ($result['RowsImported']) { $result['RowsImported'] }
                                else { 0 }
                    
                    # Check for RowCountMatch (property or key)
                    $rowCountMatch = $null
                    if ($result.PSObject.Properties.Name -contains 'RowCountMatch') { 
                        $rowCountMatch = $result.RowCountMatch 
                    } elseif ($result -is [System.Collections.Specialized.OrderedDictionary] -and $result.Contains('RowCountMatch')) {
                        $rowCountMatch = $result['RowCountMatch']
                    }
                    
                    # Check for ChecksumMatch (property or key)
                    $checksumMatch = $null
                    if ($result.PSObject.Properties.Name -contains 'ChecksumMatch') { 
                        $checksumMatch = $result.ChecksumMatch 
                    } elseif ($result -is [System.Collections.Specialized.OrderedDictionary] -and $result.Contains('ChecksumMatch')) {
                        $checksumMatch = $result['ChecksumMatch']
                    }
                    
                    [PSCustomObject]@{
                        'Table Name' = $tableName
                        'Status' = if ($success) { " Success" } else { "  Failed" }
                        'Rows Processed' = $rowCount
                        'Row Count Match' = if ($null -ne $rowCountMatch) { 
                            if ($rowCountMatch) { " Yes" } else { "  No" }
                        } else { "N/A" }
                        'Checksum Valid' = if ($null -ne $checksumMatch) { 
                            if ($checksumMatch) { " Yes" } else { "  No" }
                        } else { "N/A" }
                        'Error Message' = $errorMsg
                    }
                }
                
                $detailsData | Export-Excel -Path $OutputPath -WorksheetName "Details" -AutoSize -TableName "MigrationDetails" -TableStyle Medium6 `
                    -ConditionalText $(
                        New-ConditionalText -Text " Success" -ConditionalTextColor Green -BackgroundColor LightGreen
                        New-ConditionalText -Text "  Failed" -ConditionalTextColor Red -BackgroundColor LightPink
                    )
            }
            
            # 3. ERRORS SHEET (only if errors exist)
            $errors = @()
        
            # Collect errors from Results
            if ($results) {
                foreach ($result in $results) {
                    # Handle both PSCustomObject and OrderedDictionary
                    $tableName = if ($result.TableName) { $result.TableName } elseif ($result['TableName']) { $result['TableName'] } else { "Unknown" }
                    $success = if ($null -ne $result.Success) { $result.Success } elseif ($null -ne $result['Success']) { $result['Success'] } else { $false }
                    
                    # Get error message (avoid using 'Error' property name to prevent PSScriptAnalyzer warnings)
                    $errorMsg = $null
                    if ($result.PSObject.Properties.Name -contains 'Error' -and $result.Error) {
                        $errorMsg = $result.Error
                    } elseif ($result -is [System.Collections.Specialized.OrderedDictionary] -and $result.Contains('Error')) {
                        $errorMsg = $result['Error']
                    }
                    
                    if (-not $success -and $errorMsg) {
                        $errors += [PSCustomObject]@{
                            'Table Name' = $tableName
                            'Error Type' = 'Migration Error'
                            'Error Message' = $errorMsg
                            'Timestamp' = $timestamp.ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    }
                    
                    # Check for Errors collection (from CSV imports)
                    $errorCollection = if ($result.Errors) { $result.Errors } elseif ($result['Errors']) { $result['Errors'] } else { $null }
                    if ($errorCollection -and $errorCollection.Count -gt 0) {
                        foreach ($err in $errorCollection) {
                            $errors += [PSCustomObject]@{
                                'Table Name' = $tableName
                                'Error Type' = 'Data Error'
                                'Error Message' = $err
                                'Timestamp' = $timestamp.ToString("yyyy-MM-dd HH:mm:ss")
                            }
                        }
                    }
                }
            }
            
            if ($errors.Count -gt 0) {
                Write-Host "Creating Errors sheet..." -ForegroundColor Gray
                $errors | Export-Excel -Path $OutputPath -WorksheetName "Errors" -AutoSize -TableName "MigrationErrors" -TableStyle Medium3 `
                    -ConditionalText $(
                        New-ConditionalText -Text "Migration Error" -ConditionalTextColor DarkRed -BackgroundColor LightPink
                        New-ConditionalText -Text "Data Error" -ConditionalTextColor DarkOrange -BackgroundColor LightYellow
                    )
            }
            
            # 4. ADD CHARTS (if requested)
            if ($IncludeCharts -and $totalTables -gt 0) {
                Write-Host "Adding charts..." -ForegroundColor Gray
                
                try {
                    $excel = Open-ExcelPackage -Path $OutputPath
                    $null = $excel.Workbook.Worksheets['Summary']
                    
                    # Success/Failure Pie Chart
                    $null = @(
                        [PSCustomObject]@{ Category = 'Successful'; Count = $successfulTables }
                        [PSCustomObject]@{ Category = 'Failed'; Count = $failedTables }
                    )
                    
                    # Only add chart if there's data
                    if ($successfulTables -gt 0 -or $failedTables -gt 0) {
                        $null = New-ExcelChartDefinition -Title "Migration Results" -ChartType Pie `
                            -XRange "Category" -YRange "Count" -Column 8 -ColumnOffsetPixels 10 `
                            -Row 2 -RowOffsetPixels 10 -Width 400 -Height 300
                        
                        # Note: Chart creation requires more complex Excel manipulation
                        # For now, we skip this to avoid complexity
                    }
                    
                    Close-ExcelPackage $excel
                }
                catch {
                    Write-Verbose "Could not add charts: $_"
                }
            }
            
            Write-Host "`n Migration report created: $OutputPath" -ForegroundColor Green
            Write-Host "  Sheets included:" -ForegroundColor Gray
            Write-Host "    - Summary (overview)" -ForegroundColor Gray
            if ($results -and $results.Count -gt 0) {
                Write-Host "    - Details ($($results.Count) tables)" -ForegroundColor Gray
            }
            if ($errors.Count -gt 0) {
                Write-Host "    - Errors ($($errors.Count) errors)" -ForegroundColor DarkYellow
            }
            
            # Verify file was actually created
            if (-not (Test-Path $OutputPath)) {
                Write-Warning "Report file was not created at: $OutputPath"
                return [PSCustomObject]@{
                    Success = $false
                    Error = "File was not created"
                }
            }
            
            return [PSCustomObject]@{
                Success = $true
                OutputPath = $OutputPath
                TotalTables = $totalTables
                SuccessfulTables = $successfulTables
                FailedTables = $failedTables
                TotalErrors = $errors.Count
            }
        }
        catch {
            Write-Error "Failed to create migration report: $_"
            return [PSCustomObject]@{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    # SQLite ↔ SQL Server
    'Convert-SQLiteToSqlServer',
    'Convert-SqlServerToSQLite',
    # CSV Operations
    'Export-DatabaseSchemaToCsv',
    'Export-DatabaseSchemaToMarkdown',
    'Export-SqlTableToCsv',
    'Import-CsvToSqlTable',
    'Import-DatabaseFromCsv',
    # Data Validation
    'Get-DataChecksum',
    'Test-DataIntegrity',
    # Reporting
    'Export-MigrationReport',
    # Helper functions (for testing)
    'ConvertTo-SQLiteDataType',
    'ConvertTo-SqlServerDataType',
    'Get-TableDependencyOrder'
)
