BeforeAll {
    # Import module
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    
    # Test configuratie
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:TestDatabase = "PesterTestDB_$(Get-Random)"
    $script:CsvFolder = "$PSScriptRoot\..\TestData\ImportTest_$(Get-Random)"
    
    # Maak CSV folder
    New-Item -Path $script:CsvFolder -ItemType Directory -Force | Out-Null
    
    # Genereer test CSV files
    $customersData = @"
CustomerID,Name,Email,Phone,CreatedDate
1,Alice Johnson,alice@test.com,555-0001,2024-01-15
2,Bob Smith,bob@test.com,555-0002,2024-01-16
3,Charlie Brown,charlie@test.com,555-0003,2024-01-17
4,Diana Prince,diana@test.com,555-0004,2024-01-18
5,Eve Adams,eve@test.com,555-0005,2024-01-19
"@
    
    $productsData = @"
ProductID,Name,Price,Stock,CategoryID
1,Laptop,999.99,10,1
2,Mouse,29.99,50,1
3,Keyboard,79.99,30,1
4,Monitor,299.99,15,1
5,Headphones,149.99,25,2
6,Webcam,89.99,20,2
7,USB Cable,9.99,100,3
8,HDMI Cable,19.99,75,3
"@
    
    $ordersData = @"
OrderID,CustomerID,OrderDate,TotalAmount,Status
1,1,2024-02-01,1029.98,Shipped
2,2,2024-02-02,79.99,Delivered
3,3,2024-02-03,329.98,Processing
4,1,2024-02-04,149.99,Shipped
5,4,2024-02-05,999.99,Delivered
6,5,2024-02-06,29.99,Processing
"@
    
    $orderDetailsData = @"
OrderDetailID,OrderID,ProductID,Quantity,UnitPrice
1,1,1,1,999.99
2,1,2,1,29.99
3,2,3,1,79.99
4,3,4,1,299.99
5,3,2,1,29.99
6,4,5,1,149.99
7,5,1,1,999.99
8,6,2,1,29.99
"@
    
    $reviewsData = @"
ReviewID,ProductID,CustomerID,Rating,Comment,ReviewDate
1,1,1,5,Great laptop!,2024-02-10
2,2,2,4,Good mouse,2024-02-11
3,3,3,5,Excellent keyboard,2024-02-12
4,1,4,4,Very satisfied,2024-02-13
5,5,1,5,Best headphones,2024-02-14
6,4,5,3,Decent monitor,2024-02-15
"@
    
    $customersData | Out-File "$($script:CsvFolder)\Customers.csv" -Encoding UTF8
    $productsData | Out-File "$($script:CsvFolder)\Products.csv" -Encoding UTF8
    $ordersData | Out-File "$($script:CsvFolder)\Orders.csv" -Encoding UTF8
    $orderDetailsData | Out-File "$($script:CsvFolder)\OrderDetails.csv" -Encoding UTF8
    $reviewsData | Out-File "$($script:CsvFolder)\Reviews.csv" -Encoding UTF8
    
    # Maak test database
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:TestDatabase)')
BEGIN
    ALTER DATABASE [$($script:TestDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:TestDatabase)];
END
CREATE DATABASE [$($script:TestDatabase)];
"@
}

AfterAll {
    # Cleanup: verwijder test database
    try {
        Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:TestDatabase)')
BEGIN
    ALTER DATABASE [$($script:TestDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:TestDatabase)];
END
"@
        Write-Host " Test database cleaned up" -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not clean up test database: $_"
    }
    
    # Cleanup: verwijder test CSV folder
    if (Test-Path $script:CsvFolder) {
        Remove-Item $script:CsvFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "CSV to Database Import Tests" {
    
    Context "Module Import Tests" {
        It "Should import Import-DatabaseFromCsv module" {
            Get-Command Import-DatabaseFromCsv -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should import Import-CsvToSqlTable module" {
            Get-Command Import-CsvToSqlTable -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "CSV File Validation Tests" {
        It "Should find CSV files in Output folder" {
            $csvFiles = Get-ChildItem -Path $script:CsvFolder -Filter "*.csv"
            $csvFiles.Count | Should -BeGreaterThan 0
        }
        
        It "Should find Customers.csv" {
            Test-Path "$($script:CsvFolder)\Customers.csv" | Should -Be $true
        }
        
        It "Should find Products.csv" {
            Test-Path "$($script:CsvFolder)\Products.csv" | Should -Be $true
        }
        
        It "Should find Orders.csv" {
            Test-Path "$($script:CsvFolder)\Orders.csv" | Should -Be $true
        }
        
        It "Should find OrderDetails.csv" {
            Test-Path "$($script:CsvFolder)\OrderDetails.csv" | Should -Be $true
        }
        
        It "Should find Reviews.csv" {
            Test-Path "$($script:CsvFolder)\Reviews.csv" | Should -Be $true
        }
    }
    
    Context "Database Import Tests" {
        BeforeAll {
            # Voer import uit
            $script:primaryKeys = @{
                'Customers' = 'CustomerID'
                'Products' = 'ProductID'
                'Orders' = 'OrderID'
                'OrderDetails' = 'OrderDetailID'
                'Reviews' = 'ReviewID'
            }
            
            $script:foreignKeys = @{
                'FK_Orders_Customers' = @{
                    FromTable = 'Orders'
                    FromColumn = 'CustomerID'
                    ToTable = 'Customers'
                    ToColumn = 'CustomerID'
                }
                'FK_OrderDetails_Orders' = @{
                    FromTable = 'OrderDetails'
                    FromColumn = 'OrderID'
                    ToTable = 'Orders'
                    ToColumn = 'OrderID'
                }
                'FK_OrderDetails_Products' = @{
                    FromTable = 'OrderDetails'
                    FromColumn = 'ProductID'
                    ToTable = 'Products'
                    ToColumn = 'ProductID'
                }
                'FK_Reviews_Products' = @{
                    FromTable = 'Reviews'
                    FromColumn = 'ProductID'
                    ToTable = 'Products'
                    ToColumn = 'ProductID'
                }
                'FK_Reviews_Customers' = @{
                    FromTable = 'Reviews'
                    FromColumn = 'CustomerID'
                    ToTable = 'Customers'
                    ToColumn = 'CustomerID'
                }
            }
            
            $script:tables = @("Customers", "Products", "Orders", "OrderDetails", "Reviews")
            
            $script:importResult = Import-DatabaseFromCsv `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -CsvFolder $script:CsvFolder `
                -TableOrder $script:tables `
                -PrimaryKeys $script:primaryKeys `
                -ForeignKeys $script:foreignKeys
        }
        
        It "Should complete import successfully" {
            $script:importResult.Success | Should -Be $true
        }
        
        It "Should import all 5 tables" {
            $script:importResult.TablesProcessed | Should -Be 5
        }
        
        It "Should have no failed imports" {
            $failedCount = $script:importResult.Results | Where-Object { -not $_.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $failedCount | Should -Be 0
        }
        
        It "Should import total of 33 rows" {
            $script:importResult.TotalRowsImported | Should -Be 33
        }
    }
    
    Context "Table Structure Tests" {
        It "Should create Customers table" {
            $table = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Customers'"
            $table.cnt | Should -Be 1
        }
        
        It "Should create Products table" {
            $table = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Products'"
            $table.cnt | Should -Be 1
        }
        
        It "Should create Orders table" {
            $table = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Orders'"
            $table.cnt | Should -Be 1
        }
        
        It "Should create OrderDetails table" {
            $table = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'OrderDetails'"
            $table.cnt | Should -Be 1
        }
        
        It "Should create Reviews table" {
            $table = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Reviews'"
            $table.cnt | Should -Be 1
        }
    }
    
    Context "Data Validation Tests" {
        It "Should import 5 customers" {
            $count = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM Customers"
            $count.cnt | Should -Be 5
        }
        
        It "Should import 8 products" {
            $count = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM Products"
            $count.cnt | Should -Be 8
        }
        
        It "Should import 6 orders" {
            $count = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM Orders"
            $count.cnt | Should -Be 6
        }
        
        It "Should import 8 order details" {
            $count = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM OrderDetails"
            $count.cnt | Should -Be 8
        }
        
        It "Should import 6 reviews" {
            $count = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query "SELECT COUNT(*) as cnt FROM Reviews"
            $count.cnt | Should -Be 6
        }
    }
    
    Context "Primary Key Tests" {
        It "Should have CustomerID as primary key in Customers" {
            $pk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'Customers' AND CONSTRAINT_TYPE = 'PRIMARY KEY'
"@
            $pk.cnt | Should -Be 1
        }
        
        It "Should have ProductID as primary key in Products" {
            $pk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'Products' AND CONSTRAINT_TYPE = 'PRIMARY KEY'
"@
            $pk.cnt | Should -Be 1
        }
        
        It "Should have total of 5 primary keys" {
            $pk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'PRIMARY KEY'
"@
            $pk.cnt | Should -Be 5
        }
    }
    
    Context "Foreign Key Tests" {
        It "Should have FK_Orders_Customers foreign key" {
            $fk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM sys.foreign_keys
WHERE name = 'FK_Orders_Customers'
"@
            $fk.cnt | Should -Be 1
        }
        
        It "Should have FK_OrderDetails_Orders foreign key" {
            $fk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM sys.foreign_keys
WHERE name = 'FK_OrderDetails_Orders'
"@
            $fk.cnt | Should -Be 1
        }
        
        It "Should have total of 5 foreign keys" {
            $fk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM sys.foreign_keys
"@
            $fk.cnt | Should -Be 5
        }
    }
    
    Context "Referential Integrity Tests" {
        It "Should have no orphaned Orders (all Orders have valid Customers)" {
            $orphans = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM Orders o
LEFT JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL
"@
            $orphans.cnt | Should -Be 0
        }
        
        It "Should have no orphaned OrderDetails (all have valid Orders)" {
            $orphans = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM OrderDetails od
LEFT JOIN Orders o ON od.OrderID = o.OrderID
WHERE o.OrderID IS NULL
"@
            $orphans.cnt | Should -Be 0
        }
        
        It "Should have no orphaned OrderDetails (all have valid Products)" {
            $orphans = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM OrderDetails od
LEFT JOIN Products p ON od.ProductID = p.ProductID
WHERE p.ProductID IS NULL
"@
            $orphans.cnt | Should -Be 0
        }
        
        It "Should have no orphaned Reviews (all have valid Products)" {
            $orphans = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM Reviews r
LEFT JOIN Products p ON r.ProductID = p.ProductID
WHERE p.ProductID IS NULL
"@
            $orphans.cnt | Should -Be 0
        }
        
        It "Should have no orphaned Reviews (all have valid Customers)" {
            $orphans = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT COUNT(*) as cnt
FROM Reviews r
LEFT JOIN Customers c ON r.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL
"@
            $orphans.cnt | Should -Be 0
        }
    }
    
    Context "Data Type Tests" {
        It "Should have CustomerID as INT" {
            $dataType = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Customers' AND COLUMN_NAME = 'CustomerID'
"@
            $dataType.DATA_TYPE | Should -Be 'int'
        }
        
        It "Should have Price as DECIMAL" {
            $dataType = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Products' AND COLUMN_NAME = 'Price'
"@
            $dataType.DATA_TYPE | Should -Be 'decimal'
        }
        
        It "Should have CreatedDate as DATETIME" {
            $dataType = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Customers' AND COLUMN_NAME = 'CreatedDate'
"@
            $dataType.DATA_TYPE | Should -Be 'datetime'
        }
    }
    
    Context "Join Query Tests" {
        It "Should successfully join Orders with Customers" {
            $result = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT o.OrderID, c.Email
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
"@
            $result.Count | Should -BeGreaterThan 0
        }
        
        It "Should successfully join OrderDetails with Products" {
            $result = Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
SELECT od.OrderDetailID, p.Name as ProductName
FROM OrderDetails od
INNER JOIN Products p ON od.ProductID = p.ProductID
"@
            $result.Count | Should -BeGreaterThan 0
        }
    }
}