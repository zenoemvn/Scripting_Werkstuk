[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$CsvFolder,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoDetectRelations
)

$ErrorActionPreference = "Stop"

# Start time tracking
$startTime = Get-Date

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      Generic CSV to Database Import            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Import module
Import-Module ".\Modules\DatabaseMigration.psm1" -Force

# Onderdruk verbose output van ImportExcel module
$oldVerbose = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'

# Check of er metadata aanwezig is
$metadataPath = Join-Path $CsvFolder "schema-metadata.json"
$hasMetadata = Test-Path $metadataPath

if ($hasMetadata) {
    Write-Host "`n Found schema-metadata.json - using metadata mode" -ForegroundColor Green
    Write-Host "  This will automatically restore Primary Keys and Foreign Keys" -ForegroundColor Gray
    Write-Host "  (Auto-detect and manual parameters will be ignored)" -ForegroundColor DarkGray
    
    # Create Database
    Write-Host "`n[STEP 1] Creating database '$DatabaseName'..." -ForegroundColor Yellow
    
    Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$DatabaseName')
BEGIN
    ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DatabaseName];
END
CREATE DATABASE [$DatabaseName];
"@
    
    Write-Host "   Database created" -ForegroundColor Green
    
    # Import met metadata - zonder automatisch rapport
    Write-Host "`n[STEP 2] Importing CSV files with metadata..." -ForegroundColor Yellow
    
    $importResult = Import-DatabaseFromCsv `
        -ServerInstance $ServerInstance `
        -Database $DatabaseName `
        -CsvFolder $CsvFolder
    
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
    # Maak een nieuw object om array problemen te vermijden
    $updatedResult = [PSCustomObject]@{
        TablesProcessed = $importResult.TablesProcessed
        SuccessfulImports = $importResult.SuccessfulImports
        TotalRowsImported = $importResult.TotalRowsImported
        PrimaryKeysAdded = $importResult.PrimaryKeysAdded
        ForeignKeysAdded = $importResult.ForeignKeysAdded
        Results = $importResult.Results
        Success = $importResult.Success
        StartTime = $startTime
        EndTime = $endTime
        ExecutionTime = $executionTime
        ExecutionTimeFormatted = $executionTimeString
    }
    
    # Nu rapport genereren met de juiste tijd
    $reportPath = ".\Reports\CSV_Import_Metadata_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
    Export-MigrationReport -MigrationResults $updatedResult -OutputPath $reportPath -MigrationName "CSV Import (Metadata)"
    
    # Summary
    Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              IMPORT SUMMARY                    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Database      : $DatabaseName" -ForegroundColor Gray
    Write-Host "Mode          : Metadata-based import" -ForegroundColor Green
    Write-Host "Total Rows    : $($importResult.TotalRowsImported)" -ForegroundColor Gray
    Write-Host "Execution Time: $executionTimeString" -ForegroundColor Gray
    
    if ($importResult.Success) {
        Write-Host "`n Import completed successfully!" -ForegroundColor Green
        Write-Host "  All constraints (PKs and FKs) have been restored" -ForegroundColor Gray
    } else {
        Write-Host "`n  Import completed with errors" -ForegroundColor Red
    }
    
    exit
}

Write-Host "`n No schema-metadata.json found - using auto-detect mode" -ForegroundColor Yellow
Write-Host "  Constraints will be inferred from column names" -ForegroundColor Gray
Write-Host "  Use Export.ps1 with -SaveSchemaMetadata to preserve exact schema" -ForegroundColor DarkGray

# STAP 1: Detecteer alle CSV bestanden
Write-Host "`n[STEP 1] Discovering CSV files in '$CsvFolder'..." -ForegroundColor Yellow

$csvFiles = Get-ChildItem -Path $CsvFolder -Filter "*.csv" -File | Sort-Object Name

if ($csvFiles.Count -eq 0) {
    Write-Error "No CSV files found in '$CsvFolder'"
    exit
}

Write-Host "Found $($csvFiles.Count) CSV files:" -ForegroundColor Green
$csvFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }

# STAP 2: Analyseer CSV structuur
Write-Host "`n[STEP 2] Analyzing CSV structure..." -ForegroundColor Yellow

$tableInfo = @{}
$allColumns = @{}

foreach ($file in $csvFiles) {
    $tableName = $file.BaseName
    $sampleData = Import-Csv $file.FullName | Select-Object -First 1
    
    $columns = $sampleData.PSObject.Properties.Name
    $tableInfo[$tableName] = @{
        FileName = $file.Name
        RowCount = (Import-Csv $file.FullName).Count
        Columns = $columns
    }
    
    foreach ($col in $columns) {
        $allColumns[$col] = $true
    }
    
    Write-Host "  $tableName : $($tableInfo[$tableName].RowCount) rows, $($columns.Count) columns" -ForegroundColor Gray
}

# STAP 3: Auto-detecteer Primary Keys (kolommen die eindigen op 'ID')
Write-Host "`n[STEP 3] Auto-detecting primary keys..." -ForegroundColor Yellow

$primaryKeys = @{}

foreach ($tableName in $tableInfo.Keys) {
    $idColumns = $tableInfo[$tableName].Columns | Where-Object { $_ -like "*ID" }
    
    # Neem de eerste ID kolom die matcht met de tabelnaam
    $pkColumn = $idColumns | Where-Object { $_ -eq "${tableName}ID" } | Select-Object -First 1
    
    if (-not $pkColumn) {
        # Als geen exacte match, neem de eerste ID kolom
        $pkColumn = $idColumns | Select-Object -First 1
    }
    
    if ($pkColumn) {
        $primaryKeys[$tableName] = $pkColumn
        Write-Host "  $tableName -> PK: $pkColumn" -ForegroundColor Green
    } else {
        Write-Host "  $tableName -> No PK detected" -ForegroundColor Yellow
    }
}

# STAP 4: Auto-detecteer Foreign Keys (als enabled)
$foreignKeys = @{}

if ($AutoDetectRelations) {
    Write-Host "`n[STEP 4] Auto-detecting foreign keys..." -ForegroundColor Yellow
    
    foreach ($tableName in $tableInfo.Keys) {
        foreach ($column in $tableInfo[$tableName].Columns) {
            # Skip als het de primary key is
            if ($primaryKeys[$tableName] -eq $column) {
                continue
            }
            
            # Check of deze kolom verwijst naar een andere tabel
            if ($column -like "*ID") {
                # Probeer te matchen met een primary key van een andere tabel
                foreach ($otherTable in $primaryKeys.Keys) {
                    if ($primaryKeys[$otherTable] -eq $column) {
                        $fkName = "FK_${tableName}_${otherTable}"
                        $foreignKeys[$fkName] = @{
                            FromTable = $tableName
                            FromColumn = $column
                            ToTable = $otherTable
                            ToColumn = $column
                        }
                        Write-Host "  $fkName : $tableName.$column -> $otherTable.$column" -ForegroundColor Green
                        break
                    }
                }
            }
        }
    }
    
    if ($foreignKeys.Count -eq 0) {
        Write-Host "  No foreign keys detected" -ForegroundColor Yellow
    }
}

# STAP 5: Bepaal import volgorde (parent tables eerst)
Write-Host "`n[STEP 5] Determining import order..." -ForegroundColor Yellow

function Get-ImportOrder {
    param($tables, $foreignKeys)
    
    $ordered = @()
    $remaining = $tables.Clone()
    
    while ($remaining.Count -gt 0) {
        $addedThisRound = @()
        
        foreach ($table in $remaining) {
            # Check of deze tabel dependencies heeft
            $dependencies = $foreignKeys.Values | 
                Where-Object { $_.FromTable -eq $table } | 
                ForEach-Object { $_.ToTable }
            
            # Als alle dependencies al in de ordered list zitten, voeg deze toe
            $canAdd = $true
            foreach ($dep in $dependencies) {
                if ($dep -ne $table -and $ordered -notcontains $dep) {
                    $canAdd = $false
                    break
                }
            }
            
            if ($canAdd) {
                $addedThisRound += $table
            }
        }
        
        if ($addedThisRound.Count -eq 0) {
            # Circular dependency of geen dependencies - voeg rest toe
            $ordered += $remaining
            break
        }
        
        $ordered += $addedThisRound
        $remaining = $remaining | Where-Object { $addedThisRound -notcontains $_ }
    }
    
    return $ordered
}

$importOrder = Get-ImportOrder -tables @($tableInfo.Keys) -foreignKeys $foreignKeys

Write-Host "Import order:" -ForegroundColor Gray
for ($i = 0; $i -lt $importOrder.Count; $i++) {
    Write-Host "  $($i+1). $($importOrder[$i])" -ForegroundColor Gray
}

# STAP 6: Create Database
Write-Host "`n[STEP 6] Creating database '$DatabaseName'..." -ForegroundColor Yellow

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$DatabaseName')
BEGIN
    ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DatabaseName];
END
CREATE DATABASE [$DatabaseName];
"@

Write-Host "   Database created" -ForegroundColor Green

# STAP 7: Import data
Write-Host "`n[STEP 7] Importing CSV files to '$DatabaseName'..." -ForegroundColor Yellow

$importParams = @{
    ServerInstance = $ServerInstance
    Database = $DatabaseName
    CsvFolder = $CsvFolder
    TableOrder = $importOrder
}

if ($primaryKeys.Count -gt 0) {
    $importParams['PrimaryKeys'] = $primaryKeys
}

if ($foreignKeys.Count -gt 0) {
    $importParams['ForeignKeys'] = $foreignKeys
}

# Voeg rapport generatie toe - maar pas NA het berekenen van de totale execution time
$importParams['GenerateReport'] = $false

$importResult = Import-DatabaseFromCsv @importParams

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
# Maak een nieuw object om array problemen te vermijden
$updatedResult = [PSCustomObject]@{
    TablesProcessed = $importResult.TablesProcessed
    SuccessfulImports = $importResult.SuccessfulImports
    TotalRowsImported = $importResult.TotalRowsImported
    PrimaryKeysAdded = $primaryKeys.Count
    ForeignKeysAdded = $foreignKeys.Count
    Results = $importResult.Results
    Success = $importResult.Success
    StartTime = $startTime
    EndTime = $endTime
    ExecutionTime = $executionTime
    ExecutionTimeFormatted = $executionTimeString
}

# Nu rapport genereren met de juiste tijd
$reportPath = ".\Reports\CSV_Import_AutoDetect_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
Export-MigrationReport -MigrationResults $updatedResult -OutputPath $reportPath -MigrationName "CSV Import (Auto-Detect)"

# Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              IMPORT SUMMARY                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Database      : $DatabaseName" -ForegroundColor Gray
Write-Host "Tables        : $($importOrder.Count)" -ForegroundColor Gray
Write-Host "Primary Keys  :  $($primaryKeys.Count)" -ForegroundColor Gray
Write-Host "Foreign Keys  :  $($foreignKeys.Count)" -ForegroundColor Gray
Write-Host "Total Rows    :  $($importResult.TotalRowsImported)" -ForegroundColor Gray
Write-Host "Execution Time: $executionTimeString" -ForegroundColor Gray

if ($importResult.Success) {
    Write-Host "`n Import completed successfully!" -ForegroundColor Green
} else {
    Write-Host "`n  Import completed with errors" -ForegroundColor Red
}

# Herstel verbose preference
$VerbosePreference = $oldVerbose