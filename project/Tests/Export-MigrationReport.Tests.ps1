<#
.SYNOPSIS
Pester tests for Export-MigrationReport function

.DESCRIPTION
Tests the Excel migration reporting functionality
#>

BeforeAll {
    # Import module
    $modulePath = Join-Path $PSScriptRoot "..\Modules\DatabaseMigration.psm1"
    Import-Module $modulePath -Force
    
    # Create temp directory for test reports
    $script:tempReportDir = Join-Path $TestDrive "Reports"
    New-Item -Path $script:tempReportDir -ItemType Directory -Force | Out-Null
}

Describe "Export-MigrationReport" {
    
    Context "With successful migration results" {
        BeforeEach {
            # Create mock successful migration results
            $script:mockResults = [PSCustomObject]@{
                Success = $true
                Results = @(
                    [PSCustomObject]@{
                        TableName = "Customers"
                        Success = $true
                        RowsMigrated = 100
                        RowCountMatch = $true
                    },
                    [PSCustomObject]@{
                        TableName = "Orders"
                        Success = $true
                        RowsMigrated = 250
                        RowCountMatch = $true
                    }
                )
                TotalRows = 350
                PrimaryKeysAdded = 2
                ForeignKeysAdded = 1
            }
            
            $script:reportPath = Join-Path $script:tempReportDir "test_report.xlsx"
        }
        
        It "Should create Excel file" {
            $result = Export-MigrationReport `
                -MigrationResults $script:mockResults `
                -OutputPath $script:reportPath `
                -MigrationName "Test Migration"
            
            $result.Success | Should -Be $true
            Test-Path $script:reportPath | Should -Be $true
        }
        
        It "Should return correct statistics" {
            $result = Export-MigrationReport `
                -MigrationResults $script:mockResults `
                -OutputPath $script:reportPath `
                -MigrationName "Test Migration"
            
            $result.TotalTables | Should -Be 2
            $result.SuccessfulTables | Should -Be 2
            $result.FailedTables | Should -Be 0
            $result.TotalErrors | Should -Be 0
        }
        
        It "Should handle custom migration name" {
            $customName = "My Custom Migration"
            $result = Export-MigrationReport `
                -MigrationResults $script:mockResults `
                -OutputPath $script:reportPath `
                -MigrationName $customName
            
            $result.Success | Should -Be $true
        }
    }
    
    Context "With failed migration results" {
        BeforeEach {
            # Create mock results with errors
            $script:mockResultsWithErrors = [PSCustomObject]@{
                Success = $false
                Results = @(
                    [PSCustomObject]@{
                        TableName = "Customers"
                        Success = $true
                        RowsMigrated = 100
                    },
                    [PSCustomObject]@{
                        TableName = "Orders"
                        Success = $false
                        RowsMigrated = 0
                        Error = "Table creation failed"
                    }
                )
                TotalRows = 100
            }
            
            $script:reportPath = Join-Path $script:tempReportDir "error_report.xlsx"
        }
        
        It "Should create report with errors sheet" {
            $result = Export-MigrationReport `
                -MigrationResults $script:mockResultsWithErrors `
                -OutputPath $script:reportPath `
                -MigrationName "Failed Migration"
            
            $result.Success | Should -Be $true
            $result.TotalErrors | Should -BeGreaterThan 0
        }
        
        It "Should report correct failure count" {
            $result = Export-MigrationReport `
                -MigrationResults $script:mockResultsWithErrors `
                -OutputPath $script:reportPath `
                -MigrationName "Failed Migration"
            
            $result.SuccessfulTables | Should -Be 1
            $result.FailedTables | Should -Be 1
        }
    }
    
    Context "With CSV import results" {
        BeforeEach {
            # Create mock CSV import results
            $script:mockCsvResults = [PSCustomObject]@{
                Success = $true
                TablesProcessed = 3
                SuccessfulImports = 3
                TotalRowsImported = 500
                PrimaryKeysAdded = 3
                ForeignKeysAdded = 2
                Results = @(
                    [PSCustomObject]@{
                        TableName = "Table1"
                        Success = $true
                        RowsImported = 200
                        Errors = @()
                    },
                    [PSCustomObject]@{
                        TableName = "Table2"
                        Success = $true
                        RowsImported = 150
                        Errors = @()
                    },
                    [PSCustomObject]@{
                        TableName = "Table3"
                        Success = $true
                        RowsImported = 150
                        Errors = @()
                    }
                )
            }
            
            $script:reportPath = Join-Path $script:tempReportDir "csv_report.xlsx"
        }
        
        It "Should handle CSV import results" {
            $result = Export-MigrationReport `
                -MigrationResults $script:mockCsvResults `
                -OutputPath $script:reportPath `
                -MigrationName "CSV Import"
            
            $result.Success | Should -Be $true
            $result.TotalTables | Should -Be 3
        }
    }
    
    Context "Edge cases" {
        It "Should handle empty results" {
            $emptyResults = [PSCustomObject]@{
                Success = $true
                Results = @()
                TotalRows = 0
            }
            
            $reportPath = Join-Path $script:tempReportDir "empty_report.xlsx"
            
            $result = Export-MigrationReport `
                -MigrationResults $emptyResults `
                -OutputPath $reportPath `
                -MigrationName "Empty Migration"
            
            $result.Success | Should -Be $true
            $result.TotalTables | Should -Be 0
        }
        
        It "Should create output directory if it doesn't exist" {
            $newDir = Join-Path $TestDrive "NewReports"
            $reportPath = Join-Path $newDir "new_report.xlsx"
            
            $mockResults = [PSCustomObject]@{
                Success = $true
                Results = @()
                TotalRows = 0
            }
            
            $result = Export-MigrationReport `
                -MigrationResults $mockResults `
                -OutputPath $reportPath
            
            Test-Path $newDir | Should -Be $true
        }
        
        It "Should overwrite existing file" {
            $reportPath = Join-Path $script:tempReportDir "overwrite_test.xlsx"
            
            $mockResults = [PSCustomObject]@{
                Success = $true
                Results = @()
                TotalRows = 0
            }
            
            # Create file first time
            Export-MigrationReport `
                -MigrationResults $mockResults `
                -OutputPath $reportPath | Out-Null
            
            # Create again - should overwrite
            $result = Export-MigrationReport `
                -MigrationResults $mockResults `
                -OutputPath $reportPath
            
            $result.Success | Should -Be $true
        }
    }
    
    Context "Parameter validation" {
        It "Should require MigrationResults parameter" {
            { Export-MigrationReport -OutputPath "test.xlsx" } | Should -Throw
        }
        
        It "Should require OutputPath parameter" {
            $mockResults = [PSCustomObject]@{ Success = $true }
            { Export-MigrationReport -MigrationResults $mockResults } | Should -Throw
        }
        
        It "Should use default migration name if not provided" {
            $mockResults = [PSCustomObject]@{
                Success = $true
                Results = @()
                TotalRows = 0
            }
            
            $reportPath = Join-Path $script:tempReportDir "default_name.xlsx"
            
            $result = Export-MigrationReport `
                -MigrationResults $mockResults `
                -OutputPath $reportPath
            
            $result.Success | Should -Be $true
        }
    }
}

AfterAll {
    # Cleanup is automatic with TestDrive
}
