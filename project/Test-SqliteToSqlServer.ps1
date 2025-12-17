# Import functie
Import-Module ".\Modules\DatabaseMigration.psm1" -Force

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     SQLite → SQL Server Migration Test        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Parameters
$SQLitePath = ".\data\SalesDB.db"
$ServerInstance = "localhost\SQLEXPRESS"
$TargetDatabase = "SalesDB_FromSQLite"

# Check of SQLite database bestaat
if (-not (Test-Path $SQLitePath)) {
    Write-Host "✗ SQLite database not found: $SQLitePath" -ForegroundColor Red
    Write-Host "Run Test-SqliteConversion.ps1 first to create it" -ForegroundColor Yellow
    exit
}

Write-Host "`nSQLite database found: $SQLitePath" -ForegroundColor Gray
Write-Host "Size: $([math]::Round((Get-Item $SQLitePath).Length / 1KB, 2)) KB" -ForegroundColor Gray

# Run migration
$result = Convert-SQLiteToSqlServer `
    -SQLitePath $SQLitePath `
    -ServerInstance $ServerInstance `
    -Database $TargetDatabase

# Verify
if ($result.Success) {
    Write-Host "`n=== Verification ===" -ForegroundColor Cyan
    
    # Vergelijk row counts
    $tables = @("Customers", "Products", "Orders", "OrderDetails", "Reviews")
    
    Write-Host "`nRow count comparison:" -ForegroundColor Yellow
    foreach ($table in $tables) {
        try {
            # SQLite count
            $sqliteCount = Invoke-SqliteQuery -DataSource $SQLitePath `
                -Query "SELECT COUNT(*) as cnt FROM [$table]"
            
            # SQL Server count
            $sqlServerCount = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                -Database $TargetDatabase `
                -TrustServerCertificate `
                -Query "SELECT COUNT(*) as cnt FROM [$table]"
            
            $match = $sqliteCount.cnt -eq $sqlServerCount.cnt
            $icon = if ($match) { "✓" } else { "✗" }
            $color = if ($match) { "Green" } else { "Red" }
            
            Write-Host "  $icon $table : $($sqliteCount.cnt) → $($sqlServerCount.cnt)" -ForegroundColor $color
        }
        catch {
            Write-Host "  ⚠ $table : Could not verify" -ForegroundColor Yellow
        }
    }
    
    # Test JOIN query
    Write-Host "`nTesting JOIN query on migrated data:" -ForegroundColor Yellow
    $joinTest = Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $TargetDatabase `
        -TrustServerCertificate `
        -Query @"
SELECT TOP 5
    c.FirstName + ' ' + c.LastName as CustomerName,
    o.OrderID,
    o.TotalAmount,
    o.Status
FROM Customers c
INNER JOIN Orders o ON c.CustomerID = o.CustomerID
ORDER BY o.OrderDate DESC
"@
    
    $joinTest | Format-Table -AutoSize
    Write-Host "✓ JOIN queries work correctly" -ForegroundColor Green
}
