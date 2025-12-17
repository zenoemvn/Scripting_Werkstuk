# Quick Export met Schema Metadata
# Dit behoudt alle Primary Keys en Foreign Keys

param(
    [Parameter(Mandatory=$true)]
    [string]$Database,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFolder = ".\Export\$Database`_WithMetadata"
)

.\Export.ps1 `
    -Database $Database `
    -ServerInstance $ServerInstance `
    -OutputFolder $OutputFolder `
    -SaveSchemaMetadata

Write-Host "`n═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Next step: Import with:" -ForegroundColor Yellow
Write-Host "  .\Csvimport.ps1 -CsvFolder '$OutputFolder' -DatabaseName 'NewDB' -ServerInstance '$ServerInstance'" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
