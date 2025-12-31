Write-Host "=== Installing PSSQLite Module ===" -ForegroundColor Cyan

# Installeer PSSQLite
Install-Module -Name PSSQLite -Scope CurrentUser -Force -AllowClobber

Write-Host " PSSQLite installed" -ForegroundColor Green

# Test
Write-Host "`nTesting PSSQLite..." -ForegroundColor Yellow
Import-Module PSSQLite

# Maak lib folder VOOR we de database maken
New-Item -ItemType Directory -Path ".\lib" -Force | Out-Null

$testDb = ".\lib\test.db"
$result = Invoke-SqliteQuery -DataSource $testDb -Query "SELECT sqlite_version() as Version"
Write-Host " SQLite version: $($result.Version)" -ForegroundColor Green

# Cleanup
Remove-Item $testDb -ErrorAction SilentlyContinue

Write-Host "`n Setup complete! PSSQLite is ready to use." -ForegroundColor Green