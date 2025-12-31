[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SQLitePath,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetDatabase
)

$ErrorActionPreference = "Stop"

# Start time tracking
$startTime = Get-Date

# Import functie
Import-Module ".\Modules\DatabaseMigration.psm1" -Force

# Onderdruk verbose output van ImportExcel module
$oldVerbose = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     SQLite -> SQL Server Migration Test        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Check of SQLite database bestaat
if (-not (Test-Path $SQLitePath)) {
    Write-Host "  SQLite database not found: $SQLitePath" -ForegroundColor Red
    Write-Host "Run Test-SqliteConversion.ps1 first to create it" -ForegroundColor Yellow
    exit
}

# Check of het een bestand is en geen directory
if ((Get-Item $SQLitePath) -is [System.IO.DirectoryInfo]) {
    Write-Host "  Error: '$SQLitePath' is a directory, not a database file" -ForegroundColor Red
    
    # Zoek naar .db bestanden in de directory
    $dbFiles = Get-ChildItem -Path $SQLitePath -Filter "*.db" -File -ErrorAction SilentlyContinue
    
    if ($dbFiles) {
        Write-Host "`nAvailable SQLite databases in this directory:" -ForegroundColor Yellow
        foreach ($file in $dbFiles) {
            Write-Host "  - $($file.FullName)" -ForegroundColor Gray
        }
        Write-Host "`nPlease specify a database file, for example:" -ForegroundColor Yellow
        Write-Host "  .\SqliteToSqlServer.ps1 -SQLitePath '$($dbFiles[0].FullName)' -ServerInstance ... -TargetDatabase ..." -ForegroundColor Gray
    } else {
        Write-Host "`nNo .db files found in this directory." -ForegroundColor Yellow
    }
    
    exit
}

# Check of het een .db bestand is
if ($SQLitePath -notmatch '\.db$') {
    Write-Host " Warning: File does not have .db extension: $SQLitePath" -ForegroundColor Yellow
    Write-Host "  Continuing anyway..." -ForegroundColor Gray
}

Write-Host "`nSQLite database found: $SQLitePath" -ForegroundColor Gray
Write-Host "Size: $([math]::Round((Get-Item $SQLitePath).Length / 1KB, 2)) KB" -ForegroundColor Gray

# Run migration
$result = Convert-SQLiteToSqlServer `
    -SQLitePath $SQLitePath `
    -ServerInstance $ServerInstance `
    -Database $TargetDatabase

# Calculate execution time (totale script tijd)
$endTime = Get-Date
$executionTime = ($endTime - $startTime)
if ($executionTime.TotalSeconds -lt 1) {
    $executionTimeString = "{0:0.000} seconds" -f $executionTime.TotalSeconds
} elseif ($executionTime.TotalMinutes -lt 1) {
    $executionTimeString = "{0:0.00} seconds" -f $executionTime.TotalSeconds
} else {
    $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
}

# Update result object met correcte execution time
$updatedResult = [PSCustomObject]@{
    Success = $result.Success
    Results = $result.Results
    TotalRows = $result.TotalRows
    SQLitePath = $result.SQLitePath
    PrimaryKeysAdded = $result.PrimaryKeysAdded
    ForeignKeysAdded = $result.ForeignKeysAdded
    ServerInstance = $ServerInstance
    Database = $TargetDatabase
    StartTime = $startTime
    EndTime = $endTime
    ExecutionTime = $executionTime
    ExecutionTimeFormatted = $executionTimeString
}

# Genereer rapport
# Herstel verbose preference tijdelijk voor rapport generatie (zodat fouten zichtbaar zijn)
$VerbosePreference = $oldVerbose

$reportPath = ".\Reports\SQLite_To_SqlServer_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
try {
    $reportResult = Export-MigrationReport -MigrationResults $updatedResult -OutputPath $reportPath -MigrationName "SQLite -> SQL Server"
    if ($reportResult -and $reportResult.Success) {
        Write-Host "`n Migration report created: $reportPath" -ForegroundColor Green
    } elseif ($reportResult) {
        Write-Warning "Report generation indicated failure: $($reportResult.Error)"
    } else {
        Write-Warning "Export-MigrationReport returned null"
    }
}
catch {
    Write-Warning "Failed to generate migration report: $_"
    Write-Warning "Error details: $($_.Exception.Message)"
    Write-Warning "Stack trace: $($_.ScriptStackTrace)"
}

# Controleer of het bestand daadwerkelijk is aangemaakt
if (Test-Path $reportPath) {
    $fileSize = [math]::Round((Get-Item $reportPath).Length / 1KB, 2)
    Write-Host "  Report file size: $fileSize KB" -ForegroundColor Gray
} else {
    Write-Warning "Report file was NOT created at: $reportPath"
}

# Onderdruk verbose weer voor de rest
$VerbosePreference = 'SilentlyContinue'

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
            $icon = if ($match) { "" } else { " " }
            $color = if ($match) { "Green" } else { "Red" }
            
            Write-Host "  $icon $table : $($sqliteCount.cnt) -> $($sqlServerCount.cnt)" -ForegroundColor $color
        }
        catch {
            Write-Host "   $table : Could not verify" -ForegroundColor Yellow
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
    Write-Host " JOIN queries work correctly" -ForegroundColor Green
}

# Herstel verbose preference
$VerbosePreference = $oldVerbose
