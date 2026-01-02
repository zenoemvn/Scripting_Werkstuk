<#
.SYNOPSIS
Demo script for Excel migration reporting functionality

.DESCRIPTION
Demonstrates how to use the new Export-MigrationReport function
to create Excel reports from migration results.

.EXAMPLE
.\Demo-MigrationReport.ps1 -ServerInstance "localhost\SQLEXPRESS" -CreateTestData
#>

param(
    [Parameter(Mandatory)]
    [string]$ServerInstance,
    
    [switch]$CreateTestData
)

# Import the module
Import-Module .\Modules\DatabaseMigration.psm1 -Force

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Migration Report Demo                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Create output directories
$reportFolder = ".\Reports"
$exportFolder = ".\Export\ReportDemo"

if (-not (Test-Path $reportFolder)) {
    New-Item -Path $reportFolder -ItemType Directory -Force | Out-Null
}

# Option 1: SQL Server -> SQLite Migration Report
Write-Host "`n=== Demo 1: SQL Server to SQLite Migration ===" -ForegroundColor Yellow

# Always create/recreate test database for demo purposes
Write-Host "Creating demo database..." -ForegroundColor Yellow
    
# Create test database
$createDbQuery = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MigrationDemo')
BEGIN
    ALTER DATABASE [MigrationDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MigrationDemo];
END
CREATE DATABASE [MigrationDemo];
"@
    
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query $createDbQuery

# Create tables and insert data
$createTablesQuery = @"
-- Create test tables
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100)
);

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Total DECIMAL(10,2),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

-- Insert test data
INSERT INTO Customers (Name, Email) VALUES 
('John Doe', 'john@example.com'),
('Jane Smith', 'jane@example.com'),
('Bob Johnson', 'bob@example.com');

INSERT INTO Orders (CustomerID, OrderDate, Total) VALUES 
(1, '2024-01-15', 150.50),
(1, '2024-02-20', 200.00),
(2, '2024-01-18', 99.99),
(3, '2024-03-10', 350.00);
"@
    
Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "MigrationDemo" -TrustServerCertificate -Query $createTablesQuery
Write-Host " Demo database created with sample data" -ForegroundColor Green

# Perform SQLite migration
Write-Host "`nPerforming SQL Server -> SQLite migration..." -ForegroundColor Cyan
$sqliteResult = Convert-SqlServerToSQLite `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo" `
    -SQLitePath ".\data\MigrationDemo.db"

if ($sqliteResult.Success) {
    Write-Host " Migration successful!" -ForegroundColor Green
    Write-Host "  Tables: $($sqliteResult.Results.Count)" -ForegroundColor Gray
    Write-Host "  Total rows: $($sqliteResult.TotalRows)" -ForegroundColor Gray
    Write-Host "  Report: $($sqliteResult.OutputPath)" -ForegroundColor Cyan
}

# Option 2: SQLite -> SQL Server Migration Report (with validation)
Write-Host "`n=== Demo 2: SQLite to SQL Server Migration (with Checksum Validation) ===" -ForegroundColor Yellow

Write-Host "Performing SQLite -> SQL Server migration with validation..." -ForegroundColor Cyan
$sqlServerResult = Convert-SQLiteToSqlServer `
    -SQLitePath ".\data\MigrationDemo.db" `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo_Restored" `
    -BatchSize 500

if ($sqlServerResult.Success) {
    Write-Host " Migration successful!" -ForegroundColor Green
    Write-Host "  Tables: $($sqlServerResult.Results.Count)" -ForegroundColor Gray
    Write-Host "  Total rows: $($sqlServerResult.TotalRows)" -ForegroundColor Gray  
    Write-Host "  Report: $($sqlServerResult.OutputPath)" -ForegroundColor Cyan
}

# Option 3: CSV Import Report
Write-Host "`n=== Demo 3: CSV Import Migration Report ===" -ForegroundColor Yellow

# First export to CSV
Write-Host "Exporting database to CSV..." -ForegroundColor Cyan
$exportResult = Export-DatabaseSchemaToCsv `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo" `
    -OutputFolder $exportFolder

# Then import from CSV
Write-Host "`nImporting from CSV..." -ForegroundColor Cyan

# Create target database first
$createTargetDb = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MigrationDemo_FromCSV')
BEGIN
    ALTER DATABASE [MigrationDemo_FromCSV] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MigrationDemo_FromCSV];
END
CREATE DATABASE [MigrationDemo_FromCSV];
"@
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query $createTargetDb

$importResult = Import-DatabaseFromCsv `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo_FromCSV" `
    -CsvFolder $exportFolder `
    -GenerateReport

if ($importResult.Success) {
    Write-Host " Import successful!" -ForegroundColor Green
    Write-Host "  Tables: $($importResult.TablesProcessed)" -ForegroundColor Gray
    Write-Host "  Total rows: $($importResult.TotalRowsImported)" -ForegroundColor Gray
    Write-Host "  Report: $($importResult.ReportPath)" -ForegroundColor Cyan
}
else {
    Write-Host " Import completed with errors" -ForegroundColor Yellow
    Write-Host "  Report: $($importResult.ReportPath)" -ForegroundColor Cyan
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              DEMO COMPLETE                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Excel reports created in: $reportFolder" -ForegroundColor Green
Write-Host "`nAll migrations automatically generated Excel reports with:" -ForegroundColor Yellow
Write-Host "  • Summary sheet (overview with statistics)" -ForegroundColor Gray
Write-Host "  • Details sheet (per-table breakdown)" -ForegroundColor Gray
Write-Host "  • Errors sheet (if any failures occurred)" -ForegroundColor Gray
Write-Host "  • Details sheet (per-table breakdown)" -ForegroundColor Gray
Write-Host "  • Errors sheet (if any errors occurred)" -ForegroundColor Gray
