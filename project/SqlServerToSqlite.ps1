# Test SQL Server naar SQLite conversie
# Test of alle Primary Keys en Foreign Keys correct worden overgezet

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$SQLitePath
)

$ErrorActionPreference = "Stop"

# Start time tracking
$startTime = Get-Date

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   SQL Server → SQLite Migration Test          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

Import-Module ".\Modules\DatabaseMigration.psm1" -Force

# Onderdruk verbose output van ImportExcel module
$oldVerbose = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'

# STAP 1: Analyseer bron database
Write-Host "`n[STEP 1] Analyzing source database..." -ForegroundColor Yellow

$sourceTables = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $SourceDatabase `
    -TrustServerCertificate `
    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'" | 
    Select-Object -ExpandProperty TABLE_NAME

Write-Host "Tables in source: $($sourceTables.Count)" -ForegroundColor Gray

# Haal alle PKs op
$sourcePKs = @{}
foreach ($table in $sourceTables) {
    $pk = Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $SourceDatabase `
        -TrustServerCertificate `
        -Query @"
SELECT c.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.TABLE_NAME = '$table'
"@
    
    if ($pk) {
        $sourcePKs[$table] = $pk | Select-Object -ExpandProperty COLUMN_NAME
    }
}

# Haal alle FKs op
$sourceFKs = @{}
foreach ($table in $sourceTables) {
    $fks = Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $SourceDatabase `
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
WHERE t.name = '$table'
"@
    
    if ($fks) {
        $sourceFKs[$table] = $fks
    }
}

Write-Host "Primary Keys found: $($sourcePKs.Count)" -ForegroundColor Gray
Write-Host "Tables with Foreign Keys: $($sourceFKs.Count)" -ForegroundColor Gray

# STAP 2: Migreer naar SQLite
Write-Host "`n[STEP 2] Migrating to SQLite..." -ForegroundColor Yellow

$result = Convert-SqlServerToSQLite `
    -ServerInstance $ServerInstance `
    -Database $SourceDatabase `
    -SQLitePath $SQLitePath

Write-Host "✓ Migration completed" -ForegroundColor Green

# Calculate execution time (totale script tijd)
$endTime = Get-Date
$executionTime = ($endTime - $startTime)
if ($executionTime.TotalSeconds -lt 1) {
    $executionTimeString = "{0:0.000} seconds" -f $executionTime.TotalSeconds
} elseif ($executionTime.TotalMinutes -lt 1) {
    $executionTimeString = "{0:0.00} seconds" -f $executionTime.TotalSeconds
} else {
    $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
}

# Update result object met correcte execution time
$updatedResult = [PSCustomObject]@{
    Success = $result.Success
    Results = $result.Results
    TotalRows = $result.TotalRows
    SQLitePath = $result.SQLitePath
    PrimaryKeysAdded = $result.PrimaryKeysAdded
    ForeignKeysAdded = $result.ForeignKeysAdded
    ServerInstance = $ServerInstance
    Database = $SourceDatabase
    StartTime = $startTime
    EndTime = $endTime
    ExecutionTime = $executionTime
    ExecutionTimeFormatted = $executionTimeString
}

# Genereer rapport
# Herstel verbose preference tijdelijk voor rapport generatie (zodat fouten zichtbaar zijn)
$VerbosePreference = $oldVerbose

$reportPath = ".\Reports\SqlServer_To_SQLite_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
try {
    $reportResult = Export-MigrationReport -MigrationResults $updatedResult -OutputPath $reportPath -MigrationName "SQL Server → SQLite"
    if ($reportResult -and $reportResult.Success) {
        Write-Host "`n✓ Migration report created: $reportPath" -ForegroundColor Green
    } elseif ($reportResult) {
        Write-Warning "Report generation indicated failure: $($reportResult.Error)"
    } else {
        Write-Warning "Export-MigrationReport returned null"
    }
}
catch {
    Write-Warning "Failed to generate migration report: $_"
    Write-Warning "Error details: $($_.Exception.Message)"
    Write-Warning "Stack trace: $($_.ScriptStackTrace)"
}

# Controleer of het bestand daadwerkelijk is aangemaakt
if (Test-Path $reportPath) {
    $fileSize = [math]::Round((Get-Item $reportPath).Length / 1KB, 2)
    Write-Host "  Report file size: $fileSize KB" -ForegroundColor Gray
} else {
    Write-Warning "Report file was NOT created at: $reportPath"
}

# Onderdruk verbose weer voor de rest
$VerbosePreference = 'SilentlyContinue'

# STAP 3: Verificatie
Write-Host "`n[STEP 3] Verifying SQLite schema..." -ForegroundColor Yellow

$sqliteTables = Invoke-SqliteQuery -DataSource $SQLitePath `
    -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" | 
    Select-Object -ExpandProperty name

Write-Host "Tables in SQLite: $($sqliteTables.Count)" -ForegroundColor Gray

# Check PKs in SQLite
Write-Host "`n[VERIFICATION] Primary Keys:" -ForegroundColor Cyan

$pkMismatches = 0
foreach ($table in $sourceTables) {
    if (-not $sourcePKs.ContainsKey($table)) {
        continue
    }
    
    # Haal SQLite table info op
    $tableInfo = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA table_info('$table')"
    $sqlitePK = $tableInfo | Where-Object { $_.pk -gt 0 } | Select-Object -ExpandProperty name
    
    $sourcePK = $sourcePKs[$table]
    
    if ($sqlitePK.Count -eq $sourcePK.Count) {
        $match = $true
        foreach ($pk in $sourcePK) {
            if ($sqlitePK -notcontains $pk) {
                $match = $false
                break
            }
        }
        
        if ($match) {
            Write-Host "  ✓ $table : $($sourcePK -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $table : Expected [$($sourcePK -join ', ')] but got [$($sqlitePK -join ', ')]" -ForegroundColor Red
            $pkMismatches++
        }
    } else {
        Write-Host "  ✗ $table : Expected $($sourcePK.Count) PK columns but got $($sqlitePK.Count)" -ForegroundColor Red
        $pkMismatches++
    }
}

# Check FKs in SQLite
Write-Host "`n[VERIFICATION] Foreign Keys:" -ForegroundColor Cyan

$fkMismatches = 0
foreach ($table in $sourceTables) {
    if (-not $sourceFKs.ContainsKey($table)) {
        continue
    }
    
    # Haal SQLite FK info op
    $sqliteFKs = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA foreign_key_list('$table')"
    
    $sourceFKList = $sourceFKs[$table]
    
    if ($sqliteFKs) {
        if ($sqliteFKs.Count -eq $sourceFKList.Count) {
            Write-Host "  ✓ $table : $($sqliteFKs.Count) FK(s)" -ForegroundColor Green
            
            foreach ($fk in $sqliteFKs) {
                Write-Host "      $($fk.from) → $($fk.table)($($fk.to))" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠ $table : Expected $($sourceFKList.Count) FK(s) but got $($sqliteFKs.Count)" -ForegroundColor Yellow
            $fkMismatches++
        }
    } else {
        Write-Host "  ✗ $table : Expected $($sourceFKList.Count) FK(s) but got 0" -ForegroundColor Red
        $fkMismatches++
        
        Write-Host "    Source FKs:" -ForegroundColor Gray
        foreach ($fk in $sourceFKList) {
            Write-Host "      $($fk.ColumnName) → $($fk.ReferencedTable)($($fk.ReferencedColumn))" -ForegroundColor Gray
        }
    }
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║            VERIFICATION SUMMARY                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "Tables: $($sourceTables.Count)" -ForegroundColor Gray
Write-Host "Primary Keys:" -ForegroundColor Gray
Write-Host "  - Source: $($sourcePKs.Count)" -ForegroundColor Gray
Write-Host "  - Mismatches: $pkMismatches" -ForegroundColor $(if ($pkMismatches -eq 0) { "Green" } else { "Red" })

Write-Host "Foreign Keys:" -ForegroundColor Gray
Write-Host "  - Source tables with FKs: $($sourceFKs.Count)" -ForegroundColor Gray
Write-Host "  - Mismatches: $fkMismatches" -ForegroundColor $(if ($fkMismatches -eq 0) { "Green" } else { "Red" })

if ($pkMismatches -eq 0 -and $fkMismatches -eq 0) {
    Write-Host "`n✓ All constraints migrated correctly!" -ForegroundColor Green
} else {
    Write-Host "`n✗ Some constraints were not migrated correctly" -ForegroundColor Red
}

# Herstel verbose preference
$VerbosePreference = $oldVerbose
