function Export-SqlTableToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerInstance,
        
        [Parameter(Mandatory=$true)]
        [string]$Database,
        
        [Parameter(Mandatory=$true)]
        [string]$TableName,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$HeaderMapping,
        
        [Parameter(Mandatory=$false)]
        [switch]$InteractiveMapping
    )
    
    begin {
        Write-Verbose "Starting export of table '$TableName' from database '$Database'"
        
        $outputDir = Split-Path -Parent $OutputPath
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
    }
    
    process {
        try {
            Write-Verbose "Querying table '$TableName'..."
            $data = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                                  -Database $Database `
                                  -Query "SELECT * FROM [$TableName]" `
                                  -TrustServerCertificate
            
            if ($null -eq $data -or $data.Count -eq 0) {
                Write-Warning "Table '$TableName' is empty"
                return [PSCustomObject]@{
                    TableName = $TableName
                    OutputPath = $OutputPath
                    RowCount = 0
                    Success = $true
                }
            }
            
            Write-Verbose "Found $($data.Count) rows"
            
            # Interactieve header-mapping
            if ($InteractiveMapping) {
                Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║     Interactive Header Mapping - $TableName" -ForegroundColor Cyan
                Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host "Press ENTER to keep original name, or type new name" -ForegroundColor Gray
                Write-Host ""
                
                $HeaderMapping = @{}
                $columnNames = $data[0].PSObject.Properties.Name
                
                foreach ($columnName in $columnNames) {
                    Write-Host "Column: " -NoNewline -ForegroundColor Yellow
                    Write-Host "$columnName" -ForegroundColor White
                    $newName = Read-Host "  New name (or ENTER to keep)"
                    
                    if (-not [string]::IsNullOrWhiteSpace($newName)) {
                        $HeaderMapping[$columnName] = $newName.Trim()
                        Write-Host "    → Mapped to: $($newName.Trim())" -ForegroundColor Green
                    } else {
                        Write-Host "    → Keeping: $columnName" -ForegroundColor Gray
                    }
                }
                
                Write-Host ""
            }
            
            # Pas header-mapping toe
            if ($HeaderMapping -and $HeaderMapping.Count -gt 0) {
                Write-Verbose "Applying header mapping..."
                
                Write-Host "`nApplying header mapping:" -ForegroundColor Cyan
                foreach ($key in $HeaderMapping.Keys) {
                    Write-Host "  $key → $($HeaderMapping[$key])" -ForegroundColor Gray
                }
                
                $mappedData = foreach ($row in $data) {
                    $newRow = [ordered]@{}
                    
                    foreach ($prop in $row.PSObject.Properties) {
                        $oldName = $prop.Name
                        
                        if ($HeaderMapping.ContainsKey($oldName)) {
                            $newName = $HeaderMapping[$oldName]
                            $newRow[$newName] = $prop.Value
                        } else {
                            $newRow[$oldName] = $prop.Value
                        }
                    }
                    
                    [PSCustomObject]$newRow
                }
                
                $mappedData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                
                Write-Verbose "Applied header mapping for $($HeaderMapping.Count) columns"
            } else {
                $data | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }
            
            Write-Host "✓ Exported $($data.Count) rows to $OutputPath" -ForegroundColor Green
            
            return [PSCustomObject]@{
                TableName = $TableName
                OutputPath = $OutputPath
                RowCount = $data.Count
                HeaderMapping = $HeaderMapping
                Success = $true
            }
        }
        catch {
            Write-Error "Export failed: $_"
            return [PSCustomObject]@{
                TableName = $TableName
                OutputPath = $OutputPath
                RowCount = 0
                Error = $_.Exception.Message
                Success = $false
            }
        }
    }
}

Export-ModuleMember -Function Export-SqlTableToCsv