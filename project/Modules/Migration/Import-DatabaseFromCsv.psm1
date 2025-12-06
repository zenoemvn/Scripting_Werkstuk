function Import-DatabaseFromCsv {
    <#
    .SYNOPSIS
    Imports multiple CSV files into SQL Server while respecting foreign key relationships.
    
    .DESCRIPTION
    Analyzes CSV files in a folder and imports them in the correct order based on foreign key dependencies.
    
    .PARAMETER ServerInstance
    SQL Server instance name
    
    .PARAMETER Database
    Database name
    
    .PARAMETER CsvFolder
    Folder containing CSV files to import
    
    .PARAMETER TableOrder
    Optional: Specify exact order of table imports (useful for complex FK dependencies)
    
    .PARAMETER DropTablesIfExist
    If specified, drops existing tables before import
    
    .EXAMPLE
    Import-DatabaseFromCsv -ServerInstance "localhost\SQLEXPRESS" -Database "TestDB" -CsvFolder ".\Output" -TableOrder @("Customers","Products","Orders","OrderDetails","Reviews")
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$CsvFolder,
        
        [string[]]$TableOrder = @(),
        
        [switch]$DropTablesIfExist,
        [Parameter(Mandatory=$false)]
        [hashtable]$PrimaryKeys,  

        [Parameter(Mandatory=$false)]
        [hashtable]$ForeignKeys
    )
    
    begin {
        Write-Verbose "Starting batch CSV import from '$CsvFolder'"
        
     
        Import-Module "$PSScriptRoot\Import-CsvToSqlTable.psm1" -Force
    }
    
    process {
        try {
            # Valideer folder
            if (-not (Test-Path $CsvFolder)) {
                throw "CSV folder not found: $CsvFolder"
            }
            
            # Haal alle CSV files op
            $csvFiles = Get-ChildItem -Path $CsvFolder -Filter "*.csv"
            
            if ($csvFiles.Count -eq 0) {
                throw "No CSV files found in folder: $CsvFolder"
            }
            
            Write-Host "`n=== Batch CSV Import ===" -ForegroundColor Cyan
            Write-Host "Folder: $CsvFolder" -ForegroundColor Gray
            Write-Host "Files found: $($csvFiles.Count)" -ForegroundColor Gray
            Write-Host ""
            
            # Bepaal import volgorde
            if ($TableOrder.Count -gt 0) {
                # Gebruik opgegeven volgorde
                Write-Host "Using specified table order..." -ForegroundColor Yellow
                $importOrder = $TableOrder
            } else {
                # Automatisch: sorteer alfabetisch (werkt voor simpele scenarios)
                Write-Host "Using automatic ordering (alphabetical)..." -ForegroundColor Yellow
                $importOrder = $csvFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
                $importOrder = $importOrder | Sort-Object
            }
            
            # Drop tabellen als gevraagd (in REVERSE volgorde voor FK constraints)
            if ($DropTablesIfExist) {
                Write-Host "`nDropping existing tables..." -ForegroundColor Yellow
                
                $reversedOrder = $importOrder.Clone()
                [Array]::Reverse($reversedOrder)
                
                foreach ($tableName in $reversedOrder) {
                    try {
                        Invoke-Sqlcmd -ServerInstance $ServerInstance `
                            -Database $Database `
                            -TrustServerCertificate `
                            -Query "DROP TABLE IF EXISTS [$tableName]" `
                            -ErrorAction SilentlyContinue
                        
                        Write-Host "  ✓ Dropped $tableName" -ForegroundColor Gray
                    } catch {
                        Write-Verbose "Could not drop $tableName (might not exist)"
                    }
                }
            }
            
            # Import elke tabel
            $results = @()
            $totalRows = 0
            $successCount = 0
            
            Write-Host "`nImporting tables..." -ForegroundColor Cyan
            
            foreach ($tableName in $importOrder) {
                $csvPath = Join-Path $CsvFolder "$tableName.csv"
                
                if (-not (Test-Path $csvPath)) {
                    Write-Warning "CSV file not found for table '$tableName', skipping..."
                    continue
                }
                
                Write-Host "`n[$($successCount + 1)/$($importOrder.Count)] Importing $tableName..." -ForegroundColor Yellow
                
                $result = Import-CsvToSqlTable `
                    -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TableName $tableName `
                    -CsvPath $csvPath `
                    -CreateTable
                
                $results += $result
                $totalRows += $result.RowsImported
                
                if ($result.Success) {
                    $successCount++
                    Write-Host "  ✓ $($result.RowsImported) rows imported" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Import failed" -ForegroundColor Red
                    if ($result.Errors.Count -gt 0) {
                        $result.Errors | Select-Object -First 3 | ForEach-Object {
                            Write-Host "    $_" -ForegroundColor Red
                        }
                    }
                }
            }
            
            # Summary
            Write-Host "`n=== Import Summary ===" -ForegroundColor Cyan
            Write-Host "Tables processed: $($results.Count)" -ForegroundColor Gray
            Write-Host "Successful imports: $successCount" -ForegroundColor Green
            Write-Host "Failed imports: $($results.Count - $successCount)" -ForegroundColor $(if ($successCount -eq $results.Count) { "Gray" } else { "Red" })
            Write-Host "Total rows imported: $totalRows" -ForegroundColor Gray
            
            # Details tabel
            Write-Host "`nDetails:" -ForegroundColor Cyan
            $results | Select-Object TableName, RowsImported, Success | Format-Table -AutoSize
             if ($PrimaryKeys -and $PrimaryKeys.Count -gt 0) {
                Write-Host "`n=== Adding Primary Key Constraints ===" -ForegroundColor Cyan
                
                foreach ($tableName in $PrimaryKeys.Keys) {
                    $pkColumn = $PrimaryKeys[$tableName]
                    
                    try {
                        Write-Host "Adding PK to $tableName..." -ForegroundColor Gray
                        
                        $query = @"
ALTER TABLE [$tableName]
ADD CONSTRAINT PK_$tableName 
PRIMARY KEY ([$pkColumn])
"@
                        
                        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $query -ErrorAction Stop
                        Write-Host "  ✓ Primary key added to $tableName" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "  ✗ Failed to add PK to $tableName : $_" -ForegroundColor Red
                    }
                }
            }
            if ($ForeignKeys -and $ForeignKeys.Count -gt 0) {
                Write-Host "`n=== Adding Foreign Key Constraints ===" -ForegroundColor Cyan
                
                foreach ($fkName in $ForeignKeys.Keys) {
                    $fk = $ForeignKeys[$fkName]
                    
                    try {
                        Write-Host "Adding $fkName..." -ForegroundColor Gray
                        
                        $query = @"
ALTER TABLE [$($fk.FromTable)]
ADD CONSTRAINT $fkName 
FOREIGN KEY ([$($fk.FromColumn)]) 
REFERENCES [$($fk.ToTable)]([$($fk.ToColumn)])
"@
                        
                        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query $query -ErrorAction Stop
                        Write-Host "  ✓ $fkName added" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "  ✗ Failed to add $fkName : $_" -ForegroundColor Red
                    }
                }
            }

            # Return summary object
            return [PSCustomObject]@{
                TablesProcessed = $results.Count
                SuccessfulImports = $successCount
                TotalRowsImported = $totalRows
                Results = $results
                Success = ($successCount -eq $results.Count)
            }
            
        }
        catch {
            Write-Error "Batch import failed: $_"
            return [PSCustomObject]@{
                TablesProcessed = 0
                SuccessfulImports = 0
                TotalRowsImported = 0
                Results = @()
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

Export-ModuleMember -Function Import-DatabaseFromCsv