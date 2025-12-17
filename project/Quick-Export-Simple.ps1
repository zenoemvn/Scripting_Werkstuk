# Quick Export zonder Schema Metadata
# Simpele CSV export voor data analyse

param(
    [Parameter(Mandatory=$true)]
    [string]$Database,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFolder = ".\Export\$Database`_Simple"
)

.\Export.ps1 `
    -Database $Database `
    -ServerInstance $ServerInstance `
    -OutputFolder $OutputFolder

Write-Host "`n═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Next step: Import with auto-detect:" -ForegroundColor Yellow
Write-Host "  .\Csvimport.ps1 -CsvFolder '$OutputFolder' -DatabaseName 'NewDB' -ServerInstance '$ServerInstance' -AutoDetectRelations" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
