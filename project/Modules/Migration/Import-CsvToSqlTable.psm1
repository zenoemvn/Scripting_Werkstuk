function Import-CsvToSqlTable {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory)]
        [string]$Database,
        
        [Parameter(Mandatory)]
        [string]$TableName,
        
        [Parameter(Mandatory)]
        [string]$CsvPath,
        
        [switch]$CreateTable
    )
    
    begin {
        Write-Verbose "Starting import from '$CsvPath' to table '$TableName'"
        
        # Functie om SQL data type te bepalen
        function Get-SqlDataType {
            param([string]$Value, [string]$ColumnName)
            
            # Check of het een ID kolom is - NIET NULL!
            if ($ColumnName -like "*ID") {
                return "INT NOT NULL"
            }
            
            # Check for integer
            if ($Value -match '^\d+$') {
                $num = [int64]$Value
                if ($num -le 2147483647) { return "INT" }
                return "BIGINT"
            }
            
            # Check for decimal/money (met komma OF punt)
            if ($Value -match '^\d+[,\.]\d+$') {
                return "DECIMAL(18,2)"
            }
            
            # Check for date
            if ($Value -match '^\d{1,2}[-/]\d{1,2}[-/]\d{2,4}' -or 
                $Value -match '^\d{4}[-/]\d{1,2}[-/]\d{1,2}') {
                return "DATETIME"
            }
            
            # Check for boolean
            if ($Value -match '^(true|false|yes|no|0|1)$') {
                return "BIT"
            }
            
            # Default: string with appropriate length
            $length = [Math]::Max($Value.Length * 2, 50)
            if ($length -gt 4000) { return "NVARCHAR(MAX)" }
            return "NVARCHAR($length)"
        }
    }
    
    process {
        try {
            # Valideer of CSV bestaat
            if (-not (Test-Path $CsvPath)) {
                throw "CSV file not found: $CsvPath"
            }
            
            Write-Host "Reading CSV file..." -ForegroundColor Cyan
            $csvData = Import-Csv -Path $CsvPath
            
            if ($null -eq $csvData -or $csvData.Count -eq 0) {
                throw "CSV file is empty or invalid"
            }
            
            Write-Host "Found $($csvData.Count) rows in CSV" -ForegroundColor Gray
            
            # Check of tabel bestaat
            $tableCheck = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                -Database $Database `
                -TrustServerCertificate `
                -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName'"
            
            $tableExists = $tableCheck.cnt -gt 0
            
            if (-not $tableExists -and -not $CreateTable) {
                throw "Table '$TableName' does not exist. Use -CreateTable to create it automatically."
            }
            
            # Maak tabel aan als nodig MET CORRECTE DATA TYPES
            if (-not $tableExists -and $CreateTable) {
                Write-Host "Creating table '$TableName'..." -ForegroundColor Gray
                
                # Analyze data types from first row
                $firstRow = $csvData[0]
                $schema = @{}
                
                foreach ($prop in $firstRow.PSObject.Properties) {
                    $columnName = $prop.Name
                    $value = $prop.Value
                    
                    # Bepaal data type op basis van waarde
                    $dataType = Get-SqlDataType -Value $value -ColumnName $columnName
                    $schema[$columnName] = $dataType
                }
                
                # Maak column definitions - ID kolommen hebben al NOT NULL
                $columnDefinitions = $schema.Keys | ForEach-Object {
                    if ($schema[$_] -like "*NOT NULL*") {
                        "[$_] $($schema[$_])"
                    } else {
                        "[$_] $($schema[$_]) NULL"
                    }
                }
                
                $createTableSql = @"
CREATE TABLE [$TableName] (
    $($columnDefinitions -join ",`n    ")
)
"@
                
                Write-Verbose "Create table SQL: $createTableSql"
                
                Invoke-Sqlcmd -ServerInstance $ServerInstance `
                    -Database $Database `
                    -TrustServerCertificate `
                    -Query $createTableSql
                
                Write-Host "✓ Table created" -ForegroundColor Green
            }
            
            # Import data
            Write-Host "Importing data..." -ForegroundColor Cyan
            $importedRows = 0
            $errors = @()
            
            foreach ($row in $csvData) {
                try {
                    # Bouw INSERT statement
                    $columns = $row.PSObject.Properties.Name
                    $values = $row.PSObject.Properties.Value | ForEach-Object {
                        if ($null -eq $_ -or $_ -eq '') {
                            "NULL"
                        } else {
                            # Vervang komma door punt voor decimalen
                            $value = $_ -replace ',', '.'
                            # Escape single quotes
                            $escaped = $value -replace "'", "''"
                            
                            # Check of het een getal is (dan geen quotes)
                            if ($value -match '^\d+\.?\d*$') {
                                $value
                            } else {
                                "'$escaped'"
                            }
                        }
                    }
                    
                    $insertSql = @"
INSERT INTO [$TableName] ([$(($columns -join "], ["))])
VALUES ($(($values -join ", ")))
"@
                    
                    Invoke-Sqlcmd -ServerInstance $ServerInstance `
                        -Database $Database `
                        -TrustServerCertificate `
                        -Query $insertSql
                    
                    $importedRows++
                    
                    # Progress indicator
                    if ($importedRows % 100 -eq 0) {
                        Write-Host "  Imported $importedRows rows..." -ForegroundColor Gray
                    }
                }
                catch {
                    $errors += "Row $importedRows : $($_.Exception.Message)"
                }
            }
            
            # Success bericht
            Write-Host "✓ Import completed successfully!" -ForegroundColor Green
            Write-Host "  Rows imported: $importedRows" -ForegroundColor Gray
            if ($errors.Count -gt 0) {
                Write-Warning "  Errors encountered: $($errors.Count)"
            }
            
            # Return info object
            return [PSCustomObject]@{
                TableName = $TableName
                RowsImported = $importedRows
                RowsTotal = $csvData.Count
                Errors = $errors
                Success = $errors.Count -eq 0
            }
        }
        catch {
            Write-Error "Import failed: $_"
            return [PSCustomObject]@{
                TableName = $TableName
                RowsImported = 0
                RowsTotal = 0
                Errors = @($_.Exception.Message)
                Success = $false
            }
        }
    }
}

Export-ModuleMember -Function Import-CsvToSqlTable