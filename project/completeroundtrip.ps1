$ErrorActionPreference = "Stop"

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      CSV to Database Import                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Import module
Import-Module ".\Modules\DatabaseMigration.psm1" -Force

$ServerInstance = "localhost\SQLEXPRESS"
$TargetDB = "SalesDB"
$CsvFolder = ".\Export\SalesDB_WithMetadata"
$tables = @("Customers", "Products", "Orders", "OrderDetails", "Reviews")

# PHASE 1: Create/Recreate Database
Write-Host "`n[PHASE 1/2] Creating database $TargetDB..." -ForegroundColor Yellow

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$TargetDB')
BEGIN
    ALTER DATABASE $TargetDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE $TargetDB;
END
CREATE DATABASE $TargetDB;
"@

Write-Host "   Database created" -ForegroundColor Green

# Definieer Primary Keys
$primaryKeys = @{
    'Customers' = 'CustomerID'
    'Products' = 'ProductID'
    'Orders' = 'OrderID'
    'OrderDetails' = 'OrderDetailID'
    'Reviews' = 'ReviewID'
}
# Definieer Foreign Keys
$foreignKeys = @{
    'FK_Orders_Customers' = @{
        FromTable = 'Orders'
        FromColumn = 'CustomerID'
        ToTable = 'Customers'
        ToColumn = 'CustomerID'
    }
    'FK_OrderDetails_Orders' = @{
        FromTable = 'OrderDetails'
        FromColumn = 'OrderID'
        ToTable = 'Orders'
        ToColumn = 'OrderID'
    }
    'FK_OrderDetails_Products' = @{
        FromTable = 'OrderDetails'
        FromColumn = 'ProductID'
        ToTable = 'Products'
        ToColumn = 'ProductID'
    }
    'FK_Reviews_Products' = @{
        FromTable = 'Reviews'
        FromColumn = 'ProductID'
        ToTable = 'Products'
        ToColumn = 'ProductID'
    }
    'FK_Reviews_Customers' = @{
        FromTable = 'Reviews'
        FromColumn = 'CustomerID'
        ToTable = 'Customers'
        ToColumn = 'CustomerID'
    }
}
# PHASE 2: Import CSV files
Write-Host "`n[PHASE 2/2] Importing CSV files to $TargetDB..." -ForegroundColor Yellow

$importResult = Import-DatabaseFromCsv `
    -ServerInstance $ServerInstance `
    -Database $TargetDB `
    -CsvFolder $CsvFolder `
    -TableOrder $tables `
    -PrimaryKeys $primaryKeys `
    -ForeignKeys $foreignKeys `
    -Verbose

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          IMPORT SUCCESSFUL!                   ║" -ForegroundColor Green
Write-Host "║   Database created from CSV files              ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green