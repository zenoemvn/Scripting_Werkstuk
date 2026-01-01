<#
.SYNOPSIS
Demo script for schema analysis and documentation generation

.DESCRIPTION
Demonstrates schema documentation features:
- Enhanced JSON metadata export (row counts, sizes, indexes, constraints)
- Markdown documentation generation

.PARAMETER ServerInstance
SQL Server instance (default: localhost\SQLEXPRESS)

.PARAMETER Database
Database name (default: StackOverflow)

.EXAMPLE
.\Demo-SchemaAnalysis.ps1

.EXAMPLE
.\Demo-SchemaAnalysis.ps1 -ServerInstance "localhost\SQLEXPRESS" -Database "MyDatabase"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ServerInstance = "localhost\SQLEXPRESS",
    
    [Parameter()]
    [string]$Database = "StackOverflow"
)

# Import module
Import-Module .\Modules\DatabaseMigration.psm1 -Force

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Schema Analysis & Documentation         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nDatabase: $Database" -ForegroundColor Gray
Write-Host "Server  : $ServerInstance" -ForegroundColor Gray

try {
    # Check if database exists
    Write-Host "`nChecking database..." -ForegroundColor Cyan
    $dbCheck = Invoke-Sqlcmd -ServerInstance $ServerInstance `
        -Query "SELECT DB_ID('$Database') as id" `
        -TrustServerCertificate -ErrorAction Stop
    
    if (-not $dbCheck.id) {
        Write-Host "✗ Database '$Database' not found!" -ForegroundColor Red
        Write-Host "`nTo create it, run:" -ForegroundColor Yellow
        Write-Host "  .\Csvimport.ps1 -CsvFolder `".\Import`" -DatabaseName `"$Database`" -ServerInstance `"$ServerInstance`"" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host "✓ Database found" -ForegroundColor Green
    
    # 1. Export enhanced JSON metadata
    Write-Host "`n[1/2] Exporting enhanced JSON metadata..." -ForegroundColor Cyan
    $outputFolder = ".\Export\${Database}_Docs"
    
    Export-DatabaseSchemaToCsv `
        -ServerInstance $ServerInstance `
        -Database $Database `
        -OutputFolder $outputFolder
    
    Write-Host "✓ JSON metadata exported to: $outputFolder\schema-metadata.json" -ForegroundColor Green
    
    # 2. Generate Markdown documentation
    Write-Host "`n[2/2] Generating Markdown documentation..." -ForegroundColor Cyan
    $markdownPath = ".\Documentation\${Database}-Schema.md"
    
    # Ensure Documentation folder exists
    if (-not (Test-Path ".\Documentation")) {
        New-Item -Path ".\Documentation" -ItemType Directory -Force | Out-Null
    }
    
    Export-DatabaseSchemaToMarkdown `
        -ServerInstance $ServerInstance `
        -Database $Database `
        -OutputPath $markdownPath
    
    Write-Host "✓ Markdown documentation: $markdownPath" -ForegroundColor Green
    
    # Summary
    Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              Demo Completed!                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nGenerated files:" -ForegroundColor White
    Write-Host "  📄 JSON : $outputFolder\schema-metadata.json" -ForegroundColor Gray
    Write-Host "  📝 Markdown : $markdownPath" -ForegroundColor Gray
    
    Write-Host "`nOpen the Markdown file to view documentation:" -ForegroundColor Yellow
    Write-Host "  code $markdownPath" -ForegroundColor Gray
    
}
catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    Write-Host "`nMake sure SQL Server is running and database exists." -ForegroundColor Yellow
    exit 1
}
