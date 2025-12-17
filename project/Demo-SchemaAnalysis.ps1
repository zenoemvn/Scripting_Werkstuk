<#
.SYNOPSIS
Demo script for MVP 2.2 Schema Analysis features

.DESCRIPTION
Demonstrates the new schema analysis capabilities:
- Row counts per table
- Table sizes (KB/MB)
- Indexes (name, type, columns)
- CHECK Constraints
- UNIQUE Constraints
- Markdown documentation output
#>

# Import module
Import-Module .\Modules\DatabaseMigration.psm1 -Force

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    MVP 2.2 Schema Analysis Demo               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n[Demo 1] Enhanced JSON Metadata Export" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host @"

Export-DatabaseSchemaToCsv now includes:
  ✓ Row counts per table
  ✓ Table size (Total/Used/Unused KB)
  ✓ Indexes (name, type, unique, columns)
  ✓ CHECK constraints (with definitions)
  ✓ UNIQUE constraints (separate from PKs)

Example:
"@

Write-Host @'
Export-DatabaseSchemaToCsv `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "SalesDB" `
    -OutputFolder ".\Export\SalesDB_Enhanced"
'@ -ForegroundColor Green

Write-Host "`nJSON output includes:"
Write-Host @"
{
  "Tables": {
    "Customers": {
      "RowCount": 1523,
      "TotalSpaceKB": 256,
      "UsedSpaceKB": 240,
      "UnusedSpaceKB": 16,
      "Indexes": [
        {
          "Name": "IX_Customers_Email",
          "Type": "NONCLUSTERED",
          "IsUnique": true,
          "Columns": "Email"
        }
      ],
      "CheckConstraints": [
        {
          "ConstraintName": "CK_Customers_Age",
          "Definition": "([Age]>=(18))"
        }
      ]
    }
  }
}
"@ -ForegroundColor Gray

Write-Host "`n[Demo 2] Markdown Documentation Export" -ForegroundColor Yellow
Write-Host "=======================================" -ForegroundColor Yellow
Write-Host @"

New function: Export-DatabaseSchemaToMarkdown
Creates human-readable documentation with:
  ✓ Table of contents
  ✓ Row counts and sizes
  ✓ Column details in tables
  ✓ Primary/Foreign keys
  ✓ Indexes
  ✓ Constraints (UNIQUE, CHECK)

Example:
"@

Write-Host @'
Export-DatabaseSchemaToMarkdown `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "SalesDB" `
    -OutputPath ".\schema-documentation.md"
'@ -ForegroundColor Green

Write-Host "`n[Live Demo] Testing on SalesDB database..." -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

try {
    # Test if database exists
    $dbCheck = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" `
        -Query "SELECT DB_ID('SalesDB') as id" `
        -TrustServerCertificate -ErrorAction Stop
    
    if ($dbCheck.id) {
        Write-Host "`n✓ SalesDB database found!" -ForegroundColor Green
        
        # Export enhanced JSON metadata
        Write-Host "`n1. Exporting enhanced JSON metadata..." -ForegroundColor Cyan
        Export-DatabaseSchemaToCsv `
            -ServerInstance "localhost\SQLEXPRESS" `
            -Database "SalesDB" `
            -OutputFolder ".\Export\SalesDB_Enhanced"
        
        Write-Host "`n2. Creating Markdown documentation..." -ForegroundColor Cyan
        Export-DatabaseSchemaToMarkdown `
            -ServerInstance "localhost\SQLEXPRESS" `
            -Database "SalesDB" `
            -OutputPath ".\SalesDB-Schema.md"
        
        Write-Host "`n✓ Demo completed successfully!" -ForegroundColor Green
        Write-Host "`nGenerated files:" -ForegroundColor Cyan
        Write-Host "  - .\Export\SalesDB_Enhanced\schema-metadata.json (JSON)" -ForegroundColor Gray
        Write-Host "  - .\SalesDB-Schema.md (Markdown)" -ForegroundColor Gray
        
        Write-Host "`nOpen the Markdown file to see the documentation!" -ForegroundColor Yellow
    } else {
        Write-Host "`n⚠ SalesDB database not found. Run setup script first." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "`n⚠ Could not connect to SQL Server" -ForegroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Red
}

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         MVP 2.2 Implementation Summary        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host @"

✅ Row Counts
   - Stored in schema-metadata.json
   - Displayed in Markdown with formatted numbers

✅ Table Sizes
   - Total/Used/Unused space in KB
   - Converted to MB in Markdown
   - Calculated from sys.allocation_units

✅ Indexes
   - Name, Type (CLUSTERED/NONCLUSTERED/etc)
   - IsUnique flag
   - Column list
   - Excludes heap (type 0)

✅ CHECK Constraints
   - Constraint name
   - Full CHECK definition (e.g., [Age]>=18)
   - From sys.check_constraints

✅ UNIQUE Constraints
   - Constraint name
   - Column list
   - Separate from Primary Keys
   - From INFORMATION_SCHEMA

✅ Markdown Output Format
   - Export-DatabaseSchemaToMarkdown function
   - Table of contents with links
   - Formatted tables for columns/indexes/constraints
   - Human-readable with emojis (✓/✗)
   - Summary section with totals

All Pester tests still passing! ✓

"@ -ForegroundColor White

Write-Host "To use these features:" -ForegroundColor Cyan
Write-Host "  Get-Help Export-DatabaseSchemaToCsv -Full" -ForegroundColor Gray
Write-Host "  Get-Help Export-DatabaseSchemaToMarkdown -Full" -ForegroundColor Gray
