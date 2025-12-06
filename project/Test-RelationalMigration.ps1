. ".\Modules\Migration\Export-SqlTableToCsv.ps1"

$ServerInstance = "localhost\SQLEXPRESS"
$Database = "SalesDB"  # Of "AdventureWorksLT"

Write-Host "=== Testing Relational Database Migration ===" -ForegroundColor Cyan

# Export alle tabellen
$tables = @("Customers", "Products", "Orders", "OrderDetails", "Reviews")

foreach ($table in $tables) {
    Write-Host "`nExporting $table..." -ForegroundColor Yellow
    
    Export-SqlTableToCsv `
        -ServerInstance $ServerInstance `
        -Database $Database `
        -TableName $table `
        -OutputPath ".\Output\${table}.csv"
}

Write-Host "`n✓ All tables exported!" -ForegroundColor Green
Write-Host "Check .\Output\ folder for CSV files" -ForegroundColor Gray