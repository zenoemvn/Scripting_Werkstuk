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

# Option 1: SQL Server → SQLite Migration Report
Write-Host "`n=== Demo 1: SQL Server to SQLite Migration ===" -ForegroundColor Yellow

if ($CreateTestData) {
    Write-Host "Creating test database..." -ForegroundColor Gray
    
    # Create test database
    $createDbQuery = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MigrationDemo')
BEGIN
    ALTER DATABASE [MigrationDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MigrationDemo];
END
CREATE DATABASE [MigrationDemo];
USE [MigrationDemo];

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
    
    Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query $createDbQuery
    Write-Host "✓ Test database created" -ForegroundColor Green
}

# Perform SQLite migration
Write-Host "`nPerforming SQL Server → SQLite migration..." -ForegroundColor Cyan
$sqliteResult = Convert-SqlServerToSQLite `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo" `
    -SQLitePath ".\data\MigrationDemo.db"

# Generate Excel report
Write-Host "`nGenerating Excel report..." -ForegroundColor Cyan
$report1 = Export-MigrationReport `
    -MigrationResults $sqliteResult `
    -OutputPath "$reportFolder\SqlServer_to_SQLite_Report.xlsx" `
    -MigrationName "SQL Server to SQLite - MigrationDemo"

if ($report1.Success) {
    Write-Host "✓ Report saved: $($report1.OutputPath)" -ForegroundColor Green
    Write-Host "  - Tables: $($report1.TotalTables)" -ForegroundColor Gray
    Write-Host "  - Success: $($report1.SuccessfulTables)" -ForegroundColor Green
    Write-Host "  - Failed: $($report1.FailedTables)" -ForegroundColor $(if ($report1.FailedTables -gt 0) { "Red" } else { "Gray" })
}

# Option 2: SQLite → SQL Server Migration Report (with validation)
Write-Host "`n=== Demo 2: SQLite to SQL Server Migration (with Checksum Validation) ===" -ForegroundColor Yellow

Write-Host "Performing SQLite → SQL Server migration with validation..." -ForegroundColor Cyan
$sqlServerResult = Convert-SQLiteToSqlServer `
    -SQLitePath ".\data\MigrationDemo.db" `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo_Restored" `
    -BatchSize 1000 `
    -ValidateChecksum

# Generate Excel report
Write-Host "`nGenerating Excel report..." -ForegroundColor Cyan
$report2 = Export-MigrationReport `
    -MigrationResults $sqlServerResult `
    -OutputPath "$reportFolder\SQLite_to_SqlServer_Report.xlsx" `
    -MigrationName "SQLite to SQL Server - Restore with Validation"

if ($report2.Success) {
    Write-Host "✓ Report saved: $($report2.OutputPath)" -ForegroundColor Green
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
$importResult = Import-DatabaseFromCsv `
    -ServerInstance $ServerInstance `
    -Database "MigrationDemo_FromCSV" `
    -CsvFolder $exportFolder `
    -DropTablesIfExist

# Generate Excel report
Write-Host "`nGenerating Excel report..." -ForegroundColor Cyan
$report3 = Export-MigrationReport `
    -MigrationResults $importResult `
    -OutputPath "$reportFolder\CSV_Import_Report.xlsx" `
    -MigrationName "CSV Import - MigrationDemo"

if ($report3.Success) {
    Write-Host "✓ Report saved: $($report3.OutputPath)" -ForegroundColor Green
    if ($report3.TotalErrors -gt 0) {
        Write-Host "  ⚠ Errors logged: $($report3.TotalErrors)" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              DEMO COMPLETE                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Excel reports created in: $reportFolder" -ForegroundColor Gray
Write-Host "`nTo view reports, open them in Excel:" -ForegroundColor Yellow
Write-Host "  - SqlServer_to_SQLite_Report.xlsx" -ForegroundColor White
Write-Host "  - SQLite_to_SqlServer_Report.xlsx" -ForegroundColor White
Write-Host "  - CSV_Import_Report.xlsx" -ForegroundColor White
Write-Host "`nEach report contains:" -ForegroundColor Yellow
Write-Host "  • Summary sheet (overview with statistics)" -ForegroundColor Gray
Write-Host "  • Details sheet (per-table breakdown)" -ForegroundColor Gray
Write-Host "  • Errors sheet (if any errors occurred)" -ForegroundColor Gray
