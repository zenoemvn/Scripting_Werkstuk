# Test: SQL Server -> CSV -> SQL Server (met behoud van schema)
# Dit script test of Primary Keys en Foreign Keys behouden blijven

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$ExportFolder
)

$ErrorActionPreference = "Stop"

Import-Module ".\Modules\DatabaseMigration.psm1" -Force

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     CSV Roundtrip Test (Schema Preservation)  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# STAP 1: Export database naar CSV (met metadata)
Write-Host "`n[STEP 1] Exporting $SourceDatabase to CSV with metadata..." -ForegroundColor Yellow

$exportResult = Export-DatabaseSchemaToCsv `
    -ServerInstance $ServerInstance `
    -Database $SourceDatabase `
    -OutputFolder $ExportFolder

Write-Host " Export completed" -ForegroundColor Green

# Toon rapportlocatie als die bestaat  
if ($exportResult.OutputPath) {
    Write-Host " Export report: $($exportResult.OutputPath)" -ForegroundColor Cyan
}

# STAP 2: Inspect metadata
Write-Host "`n[STEP 2] Inspecting metadata..." -ForegroundColor Yellow

$metadataPath = Join-Path $ExportFolder "schema-metadata.json"
$metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json

Write-Host "Database: $($metadata.DatabaseName)" -ForegroundColor Gray
Write-Host "Export Date: $($metadata.ExportDate)" -ForegroundColor Gray
Write-Host "Tables: $($metadata.Tables.PSObject.Properties.Count)" -ForegroundColor Gray

Write-Host "`nSchema details:" -ForegroundColor Cyan
foreach ($tableName in $metadata.Tables.PSObject.Properties.Name) {
    $table = $metadata.Tables.$tableName
    Write-Host "  $tableName" -ForegroundColor White
    
    if ($table.PrimaryKey -and $table.PrimaryKey.Count -gt 0) {
        Write-Host "    PK: $($table.PrimaryKey -join ', ')" -ForegroundColor Green
    }
    
    if ($table.ForeignKeys -and $table.ForeignKeys.Count -gt 0) {
        foreach ($fk in $table.ForeignKeys) {
            Write-Host "    FK: $($fk.Column) -> $($fk.ReferencedTable).$($fk.ReferencedColumn)" -ForegroundColor Yellow
        }
    }
}

# STAP 3: Create target database
Write-Host "`n[STEP 3] Creating target database '$TargetDatabase'..." -ForegroundColor Yellow

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$TargetDatabase')
BEGIN
    ALTER DATABASE [$TargetDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$TargetDatabase];
END
CREATE DATABASE [$TargetDatabase];
"@

Write-Host " Target database created" -ForegroundColor Green

# STAP 4: Import CSV naar nieuwe database (met metadata)
Write-Host "`n[STEP 4] Importing CSV to $TargetDatabase (using metadata)..." -ForegroundColor Yellow

$importResult = Import-DatabaseFromCsv `
    -ServerInstance $ServerInstance `
    -Database $TargetDatabase `
    -CsvFolder $ExportFolder `
    -GenerateReport

Write-Host " Import completed" -ForegroundColor Green

# Toon rapportlocatie als die bestaat
if ($importResult.ReportPath) {
    Write-Host " Import report: $($importResult.ReportPath)" -ForegroundColor Cyan
}

# STAP 5: Verify schema in restored database
Write-Host "`n[STEP 5] Verifying restored schema..." -ForegroundColor Yellow

# Check Primary Keys
Write-Host "`nPrimary Keys in restored database:" -ForegroundColor Cyan
$restoredPKs = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $TargetDatabase `
    -TrustServerCertificate `
    -Query @"
SELECT 
    tc.TABLE_NAME,
    tc.CONSTRAINT_NAME,
    STRING_AGG(c.COLUMN_NAME, ', ') as COLUMNS
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
GROUP BY tc.TABLE_NAME, tc.CONSTRAINT_NAME
ORDER BY tc.TABLE_NAME
"@

$restoredPKs | Format-Table -AutoSize

# Check Foreign Keys
Write-Host "Foreign Keys in restored database:" -ForegroundColor Cyan
$restoredFKs = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $TargetDatabase `
    -TrustServerCertificate `
    -Query @"
SELECT 
    OBJECT_NAME(fk.parent_object_id) AS TABLE_NAME,
    fk.name AS CONSTRAINT_NAME,
    c.name AS COLUMN_NAME,
    OBJECT_NAME(fk.referenced_object_id) AS REFERENCED_TABLE,
    rc.name AS REFERENCED_COLUMN
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns c ON fkc.parent_column_id = c.column_id AND fkc.parent_object_id = c.object_id
INNER JOIN sys.columns rc ON fkc.referenced_column_id = rc.column_id AND fkc.referenced_object_id = rc.object_id
ORDER BY TABLE_NAME, CONSTRAINT_NAME
"@

$restoredFKs | Format-Table -AutoSize

# STAP 6: Compare row counts
Write-Host "`n[STEP 6] Comparing row counts..." -ForegroundColor Yellow

$tables = $metadata.Tables.PSObject.Properties.Name

foreach ($table in $tables) {
    $sourceCount = (Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $SourceDatabase `
        -TrustServerCertificate `
        -Query "SELECT COUNT(*) as cnt FROM [$table]").cnt
    
    $targetCount = (Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $TargetDatabase `
        -TrustServerCertificate `
        -Query "SELECT COUNT(*) as cnt FROM [$table]").cnt
    
    $status = if ($sourceCount -eq $targetCount) { "" } else { " " }
    $color = if ($sourceCount -eq $targetCount) { "Green" } else { "Red" }
    
    Write-Host "  $status $table : $sourceCount -> $targetCount" -ForegroundColor $color
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              ROUNDTRIP TEST RESULT             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Source Database    : $SourceDatabase" -ForegroundColor Gray
Write-Host "Target Database    : $TargetDatabase" -ForegroundColor Gray
Write-Host "Tables Exported    : $($exportResult.TablesExported)" -ForegroundColor Gray
Write-Host "Tables Imported    : $($importResult.TablesProcessed)" -ForegroundColor Gray
Write-Host "Primary Keys       : $($restoredPKs.Count)" -ForegroundColor Gray
Write-Host "Foreign Keys       : $($restoredFKs.Count)" -ForegroundColor Gray

if ($importResult.Success -and $restoredPKs.Count -gt 0 -and $restoredFKs.Count -gt 0) {
    Write-Host "`n Schema successfully preserved through CSV export/import!" -ForegroundColor Green
} else {
    Write-Host "`n Schema may not be fully preserved" -ForegroundColor Yellow
}
