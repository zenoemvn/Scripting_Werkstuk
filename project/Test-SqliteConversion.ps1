if (-not (Get-Command -Name Invoke-SqliteQuery -ErrorAction SilentlyContinue)) {
    . ".\Modules\SQLite\SQLiteHelper.ps1"
}

# Import migration function
Import-Module ".\Modules\Migration\Convert-SqlServerToSQLite.psm1" -Force

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     SQL Server → SQLite Migration Test         ║" -ForegroundColor Cyan
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
    Write-Host "✗ Database '$Database' not found!" -ForegroundColor Red
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
    Write-Host "`nYou can now inspect the SQLite database:" -ForegroundColor Cyan
    Write-Host "  Download DB Browser: https://sqlitebrowser.org/" -ForegroundColor Gray
    Write-Host "  Or query via PowerShell:" -ForegroundColor Gray
    Write-Host '  Invoke-SqliteQuery -DataSource ".\data\SalesDB.db" -Query "SELECT * FROM Customers"' -ForegroundColor DarkGray
}