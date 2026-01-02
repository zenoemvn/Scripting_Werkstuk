[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Database,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputFolder,
    
    [Parameter(Mandatory=$false)]
    [switch]$SaveSchemaMetadata,
    
    [Parameter(Mandatory=$false)]
    [switch]$InteractiveMapping,
    
    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeTables = @('sysdiagrams')
)

# Standaard rapport genereren (kan disabled worden met -GenerateReport:$false)
if (-not $PSBoundParameters.ContainsKey('GenerateReport')) {
    $GenerateReport = $true
}

# Start time tracking voor execution time
$startTime = Get-Date

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Export All Tables from Database            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Import module
Import-Module ".\Modules\DatabaseMigration.psm1" -Force

# Als SaveSchemaMetadata is ingeschakeld, gebruik de nieuwe functie
if ($SaveSchemaMetadata) {
    Write-Host "Mode: Export with Schema Metadata (preserves PKs/FKs)" -ForegroundColor Yellow
    
    # Haal tabellen op om exclude filter toe te passen
    $tablesQuery = @"
SELECT t.name AS TableName
FROM sys.tables t
WHERE t.is_ms_shipped = 0
ORDER BY t.name
"@
    
    $allTables = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                                -Database $Database `
                                -TrustServerCertificate `
                                -Query $tablesQuery
    
    $tablesToExport = $allTables | 
                      Where-Object { $ExcludeTables -notcontains $_.TableName } | 
                      Select-Object -ExpandProperty TableName
    
    if ($tablesToExport.Count -eq 0) {
        Write-Error "No tables found in database '$Database'"
        exit
    }
    
    # Gebruik de nieuwe export functie
    $result = Export-DatabaseSchemaToCsv `
        -ServerInstance $ServerInstance `
        -Database $Database `
        -OutputFolder $OutputFolder `
        -Tables $tablesToExport
    
    if ($result.Success) {
        Write-Host "`n Export with metadata completed successfully!" -ForegroundColor Green
        Write-Host "  Schema metadata saved to: schema-metadata.json" -ForegroundColor Gray
        
        # GENEREER RAPPORT
        Write-Host "`n[REPORT] Generating Excel Report..." -ForegroundColor Yellow
        
        $endTime = Get-Date
        $executionTime = ($endTime - $startTime)
        
        if ($executionTime.TotalSeconds -lt 1) {
            $executionTimeString = "{0:0.000} seconds" -f $executionTime.TotalSeconds
        } elseif ($executionTime.TotalMinutes -lt 1) {
            $executionTimeString = "{0:0.00} seconds" -f $executionTime.TotalSeconds
        } else {
            $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
        }
        
        Write-Host "Execution time: $executionTimeString" -ForegroundColor Gray
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ReportPath = ".\Reports\Export_${Database}_${timestamp}.xlsx"
        
        # Ensure Reports folder exists
        if (-not (Test-Path ".\Reports")) {
            New-Item -Path ".\Reports" -ItemType Directory -Force | Out-Null
        }
        
        # Create migration-style result object
        $exportResult = [PSCustomObject]@{
            Success = $result.Success
            Results = $result.Tables | ForEach-Object {
                [PSCustomObject]@{
                    TableName = $_.TableName
                    Success = $true
                    RowsMigrated = $_.RowCount
                    Error = $null
                }
            }
            TotalRows = ($result.Tables | Measure-Object -Property RowCount -Sum).Sum
            TablesProcessed = $result.Tables.Count
            PrimaryKeysAdded = ($result.Tables | Where-Object { $_.PrimaryKey } | Measure-Object).Count
            ForeignKeysAdded = ($result.Tables | ForEach-Object { $_.ForeignKeys.Count } | Measure-Object -Sum).Sum
            StartTime = $startTime
            EndTime = $endTime
            ExecutionTime = $executionTime
            ExecutionTimeFormatted = $executionTimeString
        }
        
        try {
            Export-MigrationReport `
                -MigrationResults $exportResult `
                -OutputPath $ReportPath `
                -MigrationName "CSV Export with Metadata: $Database"
            
            Write-Host "   Report generated: $ReportPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to generate report: $_"
        }
    }
    
    exit
}

# Oude methode: Export zonder metadata
Write-Host "Mode: Export without Schema Metadata (use -SaveSchemaMetadata to preserve PKs/FKs)" -ForegroundColor Yellow

# STAP 1: Detecteer alle tabellen in de database
Write-Host "`n[STEP 1] Discovering tables in database '$Database'..." -ForegroundColor Yellow

$tablesQuery = @"
SELECT 
    t.name AS TableName,
    SUM(p.rows) AS TotalRows
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
  AND t.is_ms_shipped = 0
GROUP BY t.name
ORDER BY t.name
"@

$tables = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query $tablesQuery

# Filter uitgesloten tabellen
$tables = $tables | Where-Object { $ExcludeTables -notcontains $_.TableName }

if ($tables.Count -eq 0) {
    Write-Error "No tables found in database '$Database'"
    exit
}

Write-Host "Found $($tables.Count) tables:" -ForegroundColor Green
$tables | ForEach-Object { 
    Write-Host "  - $($_.TableName) ($($_.TotalRows) rows)" -ForegroundColor Gray 
}

# STAP 2: Maak output folder aan
Write-Host "`n[STEP 2] Creating output folder..." -ForegroundColor Yellow

if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    Write-Host "   Created folder: $OutputFolder" -ForegroundColor Green
} else {
    Write-Host "   Using existing folder: $OutputFolder" -ForegroundColor Green
}

# STAP 3: Export elke tabel
Write-Host "`n[STEP 3] Exporting tables..." -ForegroundColor Yellow

$exportResults = @()
$totalRows = 0

foreach ($table in $tables) {
    $tableName = $table.TableName
    $outputPath = Join-Path $OutputFolder "$tableName.csv"
    
    Write-Host "`n────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "Exporting: $tableName" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor Cyan
    
    try {
        if ($InteractiveMapping) {
            $result = Export-SqlTableToCsv -ServerInstance $ServerInstance `
                                          -Database $Database `
                                          -TableName $tableName `
                                          -OutputPath $outputPath `
                                          -InteractiveMapping
        } else {
            $result = Export-SqlTableToCsv -ServerInstance $ServerInstance `
                                          -Database $Database `
                                          -TableName $tableName `
                                          -OutputPath $outputPath
        }
        
        $exportResults += $result
        $totalRows += $result.RowCount
        
        Write-Host "   Exported successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "    Export failed: $_" -ForegroundColor Red
        $exportResults += [PSCustomObject]@{
            TableName = $tableName
            OutputPath = $outputPath
            RowCount = 0
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# STAP 4: Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              Export Summary                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

$successCount = ($exportResults | Where-Object { $_.Success }).Count
$failedCount = ($exportResults | Where-Object { -not $_.Success }).Count

Write-Host "Database       : $Database" -ForegroundColor Gray
Write-Host "Output Folder  : $OutputFolder" -ForegroundColor Gray
Write-Host "Tables Found   : $($tables.Count)" -ForegroundColor Gray
Write-Host "Successful     : $successCount" -ForegroundColor $(if ($successCount -eq $tables.Count) { "Green" } else { "Yellow" })
Write-Host "Failed         : $failedCount" -ForegroundColor $(if ($failedCount -eq 0) { "Gray" } else { "Red" })
Write-Host "Total Rows     : $totalRows" -ForegroundColor Gray

# Details tabel
Write-Host "`nExport Details:" -ForegroundColor Cyan
$exportResults | Select-Object TableName, RowCount, Success, @{Name='HeadersMapped';Expression={if($_.HeaderMapping){$_.HeaderMapping.Count -gt 0}else{$false}}} | Format-Table -AutoSize

if ($failedCount -gt 0) {
    Write-Host "`nFailed Exports:" -ForegroundColor Red
    $exportResults | Where-Object { -not $_.Success } | ForEach-Object {
        Write-Host "  - $($_.TableName): $($_.Error)" -ForegroundColor Red
    }
}

# STAP 5: Sla export metadata op
Write-Host "`n[STEP 5] Saving export metadata..." -ForegroundColor Yellow

$metadata = [PSCustomObject]@{
    ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Database = $Database
    ServerInstance = $ServerInstance
    TablesExported = $successCount
    TotalRows = $totalRows
    InteractiveMapping = $InteractiveMapping.IsPresent
    Tables = $exportResults | Select-Object TableName, RowCount, Success, HeaderMapping
}

$metadataPath = Join-Path $OutputFolder "export-metadata.json"
$metadata | ConvertTo-Json -Depth 5 | Out-File -FilePath $metadataPath -Encoding UTF8

Write-Host "   Metadata saved to: $metadataPath" -ForegroundColor Green

# STAP 6: Generate report (standaard enabled)
if ($GenerateReport) {
    Write-Host "`n[STEP 6] Generating Excel Report..." -ForegroundColor Yellow
    
    # Calculate execution time
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
    
    if (-not $ReportPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ReportPath = ".\Reports\Export_Report_$timestamp.xlsx"
    }
    
    # Create migration-style result object
    $exportResult = [PSCustomObject]@{
        Success = ($successCount -eq $tables.Count)
        Results = $exportResults | ForEach-Object {
            [PSCustomObject]@{
                TableName = $_.TableName
                Success = $_.Success
                RowsMigrated = $_.RowCount
                Error = $_.Error
            }
        }
        TotalRows = $totalRows
        TablesProcessed = $tables.Count
        PrimaryKeysAdded = 0
        ForeignKeysAdded = 0
        StartTime = $startTime
        EndTime = $endTime
        ExecutionTime = $executionTime
        ExecutionTimeFormatted = $executionTimeString
    }
    
    try {
        Export-MigrationReport `
            -MigrationResults $exportResult `
            -OutputPath $ReportPath `
            -MigrationName "CSV Export: $Database"
        
        Write-Host "   Report generated: $ReportPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to generate report: $_"
    }
}

# FINAL SUMMARY
if ($successCount -eq $tables.Count) {
    Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║          Export Successful!                   ║" -ForegroundColor Green
    Write-Host "║   All tables exported to CSV                   ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
} else {
    Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║       Export Completed with Warnings          ║" -ForegroundColor Yellow
    Write-Host "║   Some tables failed to export                 ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Yellow
}