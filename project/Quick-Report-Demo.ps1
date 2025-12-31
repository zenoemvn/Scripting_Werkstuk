<#
.SYNOPSIS
Quick demo script for Excel migration reporting

.DESCRIPTION
Simple demonstration of the Export-MigrationReport functionality.
This script performs a quick SQLite to SQL Server migration and generates an Excel report.

.EXAMPLE
.\Quick-Report-Demo.ps1
#>

param(
    [string]$ServerInstance = "localhost\SQLEXPRESS"
)

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Quick Excel Report Demo                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Import module
Import-Module .\Modules\DatabaseMigration.psm1 -Force

# Check if we have a test database
$testDbPath = ".\data\SalesDB.db"
if (-not (Test-Path $testDbPath)) {
    Write-Host "`n No test database found at $testDbPath" -ForegroundColor Yellow
    Write-Host "Please run one of the test scripts first to create sample data." -ForegroundColor Yellow
    Write-Host "`nExample:" -ForegroundColor Gray
    Write-Host "  .\create-testdatabasewithrelations.ps1 -ServerInstance '$ServerInstance' -DatabaseName 'TestDB'" -ForegroundColor White
    exit 1
}

# Perform migration
Write-Host "`nPerforming SQLite → SQL Server migration..." -ForegroundColor Cyan
$migrationResult = Convert-SQLiteToSqlServer `
    -SQLitePath $testDbPath `
    -ServerInstance $ServerInstance `
    -Database "QuickReportDemo" `
    -ValidateChecksum

# Generate Excel report
Write-Host "`nGenerating Excel report..." -ForegroundColor Cyan

$reportPath = ".\Reports\Quick_Migration_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"

$reportResult = Export-MigrationReport `
    -MigrationResults $migrationResult `
    -OutputPath $reportPath `
    -MigrationName "Quick Demo Migration - SalesDB"

# Display results
if ($reportResult.Success) {
    Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║    REPORT SUCCESSFULLY CREATED                ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`nReport Location:" -ForegroundColor Cyan
    Write-Host "  $($reportResult.OutputPath)" -ForegroundColor White
    
    Write-Host "`nStatistics:" -ForegroundColor Cyan
    Write-Host "  Total Tables:      $($reportResult.TotalTables)" -ForegroundColor Gray
    Write-Host "  Successful:        " -NoNewline -ForegroundColor Gray
    Write-Host "$($reportResult.SuccessfulTables)" -ForegroundColor Green
    Write-Host "  Failed:            " -NoNewline -ForegroundColor Gray
    Write-Host "$($reportResult.FailedTables)" -ForegroundColor $(if ($reportResult.FailedTables -gt 0) { "Red" } else { "Gray" })
    
    if ($reportResult.TotalErrors -gt 0) {
        Write-Host "  Errors Logged:     $($reportResult.TotalErrors)" -ForegroundColor Yellow
    }
    
    Write-Host "`nReport Contents:" -ForegroundColor Cyan
    Write-Host "   Summary Sheet   - Migration overview & statistics" -ForegroundColor Gray
    Write-Host "   Details Sheet   - Per-table breakdown" -ForegroundColor Gray
    if ($reportResult.TotalErrors -gt 0) {
        Write-Host "    Errors Sheet    - Error details & timestamps" -ForegroundColor Yellow
    }
    
    Write-Host "`nTo open the report:" -ForegroundColor Yellow
    Write-Host "  Start-Process '$($reportResult.OutputPath)'" -ForegroundColor White
    
    # Offer to open the report
    $response = Read-Host "`nWould you like to open the report now? (y/n)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Start-Process $reportResult.OutputPath
    }
} else {
    Write-Host "`n Report generation failed" -ForegroundColor Red
    Write-Host "Error: $($reportResult.Error)" -ForegroundColor Red
}
