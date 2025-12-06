param(
    [string]$ServerInstance = "localhost\SQLEXPRESS",
    [string]$Database = "TestDB"
)

Write-Host "`n=== DATABASE OVERVIEW ===" -ForegroundColor Cyan
Write-Host "Server: $ServerInstance" -ForegroundColor Yellow
Write-Host "Database: $Database`n" -ForegroundColor Yellow

# Alle tabellen
$tables = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $Database `
    -TrustServerCertificate `
    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'"

Write-Host "Tables in database:" -ForegroundColor Green
foreach ($table in $tables) {
    $tableName = $table.TABLE_NAME
    
    # Row count - FIX: gebruik COUNT(*) zonder alias in de query zelf
    $countResult = Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $Database `
        -TrustServerCertificate `
        -Query "SELECT COUNT(*) FROM [$tableName]"
    
    # Haal de waarde op uit de eerste kolom
    $count = $countResult[0]
    
    Write-Host "  - $tableName ($count rows)" -ForegroundColor White
    
    # Preview data
    $preview = Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Database $Database `
        -TrustServerCertificate `
        -Query "SELECT TOP 3 * FROM [$tableName]"
    
    $preview | Format-Table -AutoSize | Out-String | Write-Host
}