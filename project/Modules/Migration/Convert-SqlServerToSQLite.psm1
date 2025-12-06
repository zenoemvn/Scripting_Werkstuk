# Helper function to convert SQL Server data types to SQLite
function ConvertTo-SQLiteDataType {
    param([string]$SqlServerType)
    
    switch -Regex ($SqlServerType) {
        '^(bit|tinyint|smallint|int|bigint)$' { 'INTEGER' }
        '^(real|float|decimal|numeric|money|smallmoney)$' { 'REAL' }
        '^(date|datetime|datetime2|smalldatetime|time|datetimeoffset)$' { 'TEXT' }
        '^(char|varchar|nchar|nvarchar|text|ntext)$' { 'TEXT' }
        '^(binary|varbinary|image)$' { 'BLOB' }
        default { 'TEXT' }
    }
}

# Helper function to get tables from SQLite database
function Get-SQLiteTables {
    param([string]$DataSource)
    
    $tables = Invoke-SqliteQuery -DataSource $DataSource -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    return $tables
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
    
    .EXAMPLE
    Convert-SqlServerToSQLite -ServerInstance "localhost\SQLEXPRESS" -Database "SalesDB" -SQLitePath ".\data\SalesDB.db"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$SQLitePath,
        
        [string[]]$Tables = @()
    )
    
    begin {
         # Import SQLite helper ONLY if not already loaded
        if (-not (Get-Command -Name Invoke-SqliteQuery -ErrorAction SilentlyContinue)) {
            . "$PSScriptRoot\..\SQLite\SQLiteHelper.ps1"
        }
    }
    
    process {
        try {
            Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║     SQL Server → SQLite Migration             ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host "Source: $ServerInstance.$Database" -ForegroundColor Gray
            Write-Host "Target: $SQLitePath" -ForegroundColor Gray
            
            # Stap 1: Haal tabellen op
            Write-Host "`n[1/4] Analyzing SQL Server schema..." -ForegroundColor Yellow
            
            if ($Tables.Count -eq 0) {
                $tableList = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME"
                
                $Tables = $tableList | Select-Object -ExpandProperty TABLE_NAME
            }
            
            Write-Host "Found $($Tables.Count) tables to migrate" -ForegroundColor Gray
            
            # Stap 2: Maak SQLite database
            Write-Host "`n[2/4] Creating SQLite database..." -ForegroundColor Yellow
            
            # Verwijder oude database
            if (Test-Path $SQLitePath) {
                Remove-Item $SQLitePath -Force
                Write-Host "Removed existing database" -ForegroundColor Gray
            }
            
            # Maak folder als die niet bestaat
            $folder = Split-Path $SQLitePath -Parent
            if ($folder -and -not (Test-Path $folder)) {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
            }
            
            # Maak lege database
            Invoke-SqliteQuery -DataSource $SQLitePath -Query "SELECT 1" | Out-Null
            Write-Host "✓ SQLite database created" -ForegroundColor Green
            
            # Stap 3: Migreer tables
            Write-Host "`n[3/4] Migrating tables..." -ForegroundColor Yellow
            
            $migrationResults = @()
            $totalRows = 0
            
            foreach ($tableName in $Tables) {
                Write-Host "`n  Migrating: $tableName" -ForegroundColor Cyan
                
                try {
                    # Haal kolommen op
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
                    
                    # Bouw CREATE TABLE statement
                    $columnDefs = foreach ($col in $columns) {
                        $colName = $col.COLUMN_NAME
                        $sqliteType = ConvertTo-SQLiteDataType -SqlServerType $col.DATA_TYPE
                        $nullable = if ($col.IS_NULLABLE -eq 'NO') { 'NOT NULL' } else { '' }
                        
                        "[$colName] $sqliteType $nullable".Trim()
                    }
                    
                    $createTableSql = "CREATE TABLE [$tableName] ($($columnDefs -join ', '))"
                    
                    Write-Host "    Creating schema..." -ForegroundColor Gray
                    Invoke-SqliteQuery -DataSource $SQLitePath -Query $createTableSql
                    
                    # Haal data op
                    Write-Host "    Fetching data..." -ForegroundColor Gray
                    $data = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query "SELECT * FROM [$tableName]"
                    
                    if ($null -eq $data -or $data.Count -eq 0) {
                        Write-Host "    ⚠ Empty table" -ForegroundColor Yellow
                        $migrationResults += [PSCustomObject]@{
                            TableName = $tableName
                            RowsMigrated = 0
                            Success = $true
                        }
                        continue
                    }
                    
                    # Insert data
                    Write-Host "    Inserting $($data.Count) rows..." -ForegroundColor Gray
                    
                    $insertedRows = 0
                    $columnNames = $columns | Select-Object -ExpandProperty COLUMN_NAME
                    
                    try {
                        foreach ($row in $data) {
                            try {
                                $values = foreach ($colName in $columnNames) {
                                    $value = $row.$colName
                                    
                                    if ($null -eq $value -or [DBNull]::Value -eq $value) {
                                        "NULL"
                                    } elseif ($value -is [string]) {
                                        $escaped = $value -replace "'", "''"
                                        "'$escaped'"
                                    } elseif ($value -is [DateTime]) {
                                        "'$($value.ToString('yyyy-MM-dd HH:mm:ss'))'"
                                    } elseif ($value -is [bool]) {
                                        if ($value) { "1" } else { "0" }
                                    } else {
                                        "$value"
                                    }
                                }
                                
                                $insertSql = "INSERT INTO [$tableName] ([$($columnNames -join '], [')]) VALUES ($($values -join ', '))"
                                Invoke-SqliteQuery -DataSource $SQLitePath -Query $insertSql
                                
                                $insertedRows++
                                
                                if ($insertedRows % 100 -eq 0) {
                                    Write-Host "      $insertedRows rows..." -ForegroundColor DarkGray
                                }
                            }
                            catch {
                                Write-Warning "Failed to insert row: $_"
                            }
                        }
                        
                        Write-Host "    ✓ Migrated $insertedRows rows" -ForegroundColor Green
                        
                        $totalRows += $insertedRows
                        
                        $migrationResults += [PSCustomObject]@{
                            TableName = $tableName
                            RowsMigrated = $insertedRows
                            Success = $true
                            Error = $null
                        }
                    }
                    catch {
                        Write-Host "    ✗ Failed: $_" -ForegroundColor Red
                        
                        $migrationResults += [PSCustomObject]@{
                            TableName = $tableName
                            RowsMigrated = 0
                            Success = $false
                            Error = $_.Exception.Message
                        }
                    }
                }
                catch {
                    Write-Host "    ✗ Table migration failed: $_" -ForegroundColor Red
                    
                    $migrationResults += [PSCustomObject]@{
                        TableName = $tableName
                        RowsMigrated = 0
                        Success = $false
                        Error = $_.Exception.Message
                    }
                }
            }
            
            # Stap 4: Verificatie
            Write-Host "`n[4/4] Verification..." -ForegroundColor Yellow
            $sqliteTables = Get-SQLiteTables -DataSource $SQLitePath
            Write-Host "Tables in SQLite: $($sqliteTables.Count)" -ForegroundColor Gray
            
            # Summary
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
                Write-Host "✓ Migration completed successfully!" -ForegroundColor Green
            } else {
                Write-Host "⚠ Migration completed with errors" -ForegroundColor Yellow
            }
            
            return [PSCustomObject]@{
                Success = ($successCount -eq $migrationResults.Count)
                Results = $migrationResults
                TotalRows = $totalRows
                SQLitePath = $SQLitePath
            }
        }
        catch {
            Write-Error "Migration failed: $_"
            throw
        }
    }
}
Export-ModuleMember -Function Convert-SqlServerToSQLite