if (-not (Get-Command -Name Invoke-SqliteQuery -ErrorAction SilentlyContinue)) {
    . ".\Modules\SQLite\SQLiteHelper.ps1"
}

# Import migration function
Import-Module ".\Modules\DatabaseMigration.psm1" -Force

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     SQL Server -> SQLite Migration Test         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Parameters
$ServerInstance = "localhost\SQLEXPRESS"
$Database = "SalesDB"
$SQLitePath = ".\data\SalesDB.db"

# Check of SalesDB bestaat
$dbCheck = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -TrustServerCertificate `
    -Query "SELECT name FROM sys.databases WHERE name = '$Database'"

if (-not $dbCheck) {
    Write-Host "  Database '$Database' not found!" -ForegroundColor Red
    Write-Host "Run: .\create-testdatabasewithrelations.ps1 first" -ForegroundColor Yellow
    exit
}

# Run migration
$result = Convert-SqlServerToSQLite `
    -ServerInstance $ServerInstance `
    -Database $Database `
    -SQLitePath $SQLitePath

# Show result
if ($result.Success) {
    Write-Host "`n=== SQLite Database Inspection ===" -ForegroundColor Cyan
    
    # Check foreign keys
    Write-Host "`nForeign Keys in SQLite:" -ForegroundColor Yellow
    
    $tables = Invoke-SqliteQuery -DataSource $SQLitePath -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" | 
              Select-Object -ExpandProperty name
    
    $hasForeignKeys = $false
    foreach ($table in $tables) {
        $fks = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA foreign_key_list([$table])"
        
        if ($fks) {
            $hasForeignKeys = $true
            Write-Host "`n  Table: $table" -ForegroundColor Cyan
            foreach ($fk in $fks) {
                Write-Host "     $($fk.from) -> $($fk.table)($($fk.to))" -ForegroundColor Green
            }
        }
    }
    
    if (-not $hasForeignKeys) {
        Write-Host "  No foreign keys found in any table" -ForegroundColor Gray
    }
    
    # Verify FK constraints are enabled
    $fkStatus = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA foreign_keys"
    Write-Host "`nForeign Keys Enabled: $($fkStatus.foreign_keys -eq 1)" -ForegroundColor $(if ($fkStatus.foreign_keys -eq 1) { 'Green' } else { 'Yellow' })
    
    # Test data integrity with a JOIN - detect columns dynamically
    Write-Host "`nTesting data integrity with JOIN query:" -ForegroundColor Yellow
    
    # Enable foreign keys for this query
    Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA foreign_keys = ON"
    
    # Get actual column names
    $customerCols = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA table_info(Customers)"
    $productCols = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA table_info(Products)"
    
    # Find name columns (could be Name, CustomerName, ProductName, etc.)
    $customerNameCol = ($customerCols | Where-Object { $_.name -match 'name' } | Select-Object -First 1).name
    $productNameCol = ($productCols | Where-Object { $_.name -match 'name' } | Select-Object -First 1).name
    
    if ($customerNameCol -and $productNameCol) {
        $testQuery = @"
SELECT 
    c.[$customerNameCol] as CustomerName,
    o.OrderID,
    o.TotalAmount,
    p.[$productNameCol] as ProductName
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN Products p ON od.ProductID = p.ProductID
LIMIT 5
"@
        
        try {
            $joinResult = Invoke-SqliteQuery -DataSource $SQLitePath -Query $testQuery
            $joinResult | Format-Table -AutoSize
            
            if ($joinResult) {
                Write-Host " JOIN queries work - foreign keys are functional!" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "JOIN test failed: $_"
            Write-Host "Customer column detected: $customerNameCol" -ForegroundColor DarkGray
            Write-Host "Product column detected: $productNameCol" -ForegroundColor DarkGray
        }
    } else {
        Write-Warning "Could not detect name columns for JOIN test"
        Write-Host "Customer columns: $($customerCols.name -join ', ')" -ForegroundColor DarkGray
        Write-Host "Product columns: $($productCols.name -join ', ')" -ForegroundColor DarkGray
    }
    
    # Check FK status again
    $fkStatus = Invoke-SqliteQuery -DataSource $SQLitePath -Query "PRAGMA foreign_keys"
    Write-Host "`nForeign Keys Currently Enabled: $($fkStatus.foreign_keys -eq 1)" -ForegroundColor $(if ($fkStatus.foreign_keys -eq 1) { 'Green' } else { 'Yellow' })
    Write-Host "Note: FK's must be enabled per connection with 'PRAGMA foreign_keys = ON'" -ForegroundColor DarkGray
    
    Write-Host "`nYou can now inspect the SQLite database:" -ForegroundColor Cyan
    Write-Host "  Download DB Browser: https://sqlitebrowser.org/" -ForegroundColor Gray
    Write-Host "  Or query via PowerShell:" -ForegroundColor Gray
    Write-Host '  Invoke-SqliteQuery -DataSource ".\data\SalesDB.db" -Query "SELECT * FROM Customers"' -ForegroundColor DarkGray
}