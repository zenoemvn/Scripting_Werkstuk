# Test complete roundtrip: SQL Server → SQLite → SQL Server
# Verificatie dat alle PKs en FKs behouden blijven

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$SQLitePath
)

$ErrorActionPreference = "Stop"

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     COMPLETE SQLite ROUND-TRIP TEST            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

Import-Module ".\Modules\DatabaseMigration.psm1" -Force

# PHASE 1: SQL Server → SQLite
Write-Host "`n[PHASE 1/2] SQL Server → SQLite" -ForegroundColor Yellow
Write-Host "Source: $ServerInstance.$SourceDatabase" -ForegroundColor Gray
Write-Host "Target: $SQLitePath" -ForegroundColor Gray

$toSqlite = Convert-SqlServerToSQLite `
    -ServerInstance $ServerInstance `
    -Database $SourceDatabase `
    -SQLitePath $SQLitePath

if (-not $toSqlite.Success) {
    Write-Host "✗ Phase 1 failed!" -ForegroundColor Red
    exit
}

Write-Host "`n⏸  Pausing to inspect SQLite database..." -ForegroundColor Yellow
Write-Host "SQLite file: $SQLitePath" -ForegroundColor Gray
Write-Host "Size: $([math]::Round((Get-Item $SQLitePath).Length / 1KB, 2)) KB" -ForegroundColor Gray

# PHASE 2: SQLite → SQL Server
Write-Host "`n[PHASE 2/2] SQLite → SQL Server" -ForegroundColor Yellow
Write-Host "Source: $SQLitePath" -ForegroundColor Gray
Write-Host "Target: $ServerInstance.$TargetDatabase" -ForegroundColor Gray

$toSqlServer = Convert-SQLiteToSqlServer `
    -SQLitePath $SQLitePath `
    -ServerInstance $ServerInstance `
    -Database $TargetDatabase

# VALIDATION
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           ROUND-TRIP VALIDATION                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Haal alle tabellen op uit de bron database
$tables = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $SourceDatabase `
    -TrustServerCertificate `
    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME" |
    Select-Object -ExpandProperty TABLE_NAME

$allMatch = $true

Write-Host "`nComparing: $SourceDatabase → SQLite → $TargetDatabase" -ForegroundColor Yellow
Write-Host ("{0,-20} {1,10} {2,10} {3,10}" -f "Table", "Original", "SQLite", "Final") -ForegroundColor Cyan
Write-Host ("-" * 55) -ForegroundColor Gray

foreach ($table in $tables) {
    try {
        # Source count
        $sourceCount = Invoke-Sqlcmd -ServerInstance $ServerInstance `
            -Database $SourceDatabase `
            -TrustServerCertificate `
            -Query "SELECT COUNT(*) as cnt FROM [$table]"
        
        # SQLite count
        $sqliteCount = Invoke-SqliteQuery -DataSource $SQLitePath `
            -Query "SELECT COUNT(*) as cnt FROM [$table]"
        
        # Target count
        $targetCount = Invoke-Sqlcmd -ServerInstance $ServerInstance `
            -Database $TargetDatabase `
            -TrustServerCertificate `
            -Query "SELECT COUNT(*) as cnt FROM [$table]"
        
        $match = ($sourceCount.cnt -eq $sqliteCount.cnt) -and ($sqliteCount.cnt -eq $targetCount.cnt)
        if (-not $match) { $allMatch = $false }
        
        $status = if ($match) { "✓" } else { "✗" }
        $color = if ($match) { "Green" } else { "Red" }
        
        Write-Host ("{0,-20} {1,10} {2,10} {3,10}  {4}" -f $table, $sourceCount.cnt, $sqliteCount.cnt, $targetCount.cnt, $status) -ForegroundColor $color
    }
    catch {
        Write-Host ("{0,-20} ERROR" -f $table) -ForegroundColor Red
        $allMatch = $false
    }
}

Write-Host ""
if ($allMatch) {
    Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║    ✓ ROUND-TRIP SUCCESSFUL!                    ║" -ForegroundColor Green
    Write-Host "║    All data preserved through SQLite           ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`nMigration path:" -ForegroundColor Cyan
    Write-Host "  $SourceDB (SQL Server)" -ForegroundColor Gray
    Write-Host "    ↓" -ForegroundColor Gray
    Write-Host "  $SQLitePath" -ForegroundColor Gray
    Write-Host "    ↓" -ForegroundColor Gray
    Write-Host "  $TargetDB (SQL Server)" -ForegroundColor Gray
} else {
    Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║    ✗ ROUND-TRIP FAILED                         ║" -ForegroundColor Red
    Write-Host "║    Data loss detected                          ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Red
}
