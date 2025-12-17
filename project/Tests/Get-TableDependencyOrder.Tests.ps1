BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:TestDatabase = "PesterTest_DependencyOrder_$(Get-Random)"
    
    # Maak test database met dependencies
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:TestDatabase)')
BEGIN
    ALTER DATABASE [$($script:TestDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:TestDatabase)];
END
CREATE DATABASE [$($script:TestDatabase)];
"@
    
    # Maak test tables met FK relationships
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
-- Parent tables (geen dependencies)
CREATE TABLE Categories (CategoryID INT PRIMARY KEY, Name NVARCHAR(50));
CREATE TABLE Suppliers (SupplierID INT PRIMARY KEY, Name NVARCHAR(50));

-- Child table (hangt af van Categories en Suppliers)
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    CategoryID INT,
    SupplierID INT,
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID),
    FOREIGN KEY (SupplierID) REFERENCES Suppliers(SupplierID)
);

-- Grandchild table (hangt af van Products)
CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY,
    ProductID INT,
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);
"@
}

AfterAll {
    # Cleanup
    try {
        Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:TestDatabase)')
BEGIN
    ALTER DATABASE [$($script:TestDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:TestDatabase)];
END
"@
    }
    catch {
        Write-Warning "Could not clean up test database: $_"
    }
}

Describe "Get-TableDependencyOrder" {
    
    Context "Basic Dependency Resolution" {
        It "Should order parent tables before child tables" {
            $tables = @("Products", "Categories", "Suppliers")
            
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables $tables
            
            $categoriesIndex = [array]::IndexOf($result, "Categories")
            $productsIndex = [array]::IndexOf($result, "Products")
            
            $categoriesIndex | Should -BeLessThan $productsIndex
        }
        
        It "Should handle multiple levels of dependencies" {
            $tables = @("OrderDetails", "Products", "Categories", "Suppliers")
            
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables $tables
            
            $productsIndex = [array]::IndexOf($result, "Products")
            $orderDetailsIndex = [array]::IndexOf($result, "OrderDetails")
            
            $productsIndex | Should -BeLessThan $orderDetailsIndex
        }
        
        It "Should return all input tables" {
            $tables = @("Categories", "Suppliers", "Products", "OrderDetails")
            
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables $tables
            
            $result.Count | Should -Be $tables.Count
            foreach ($table in $tables) {
                $result | Should -Contain $table
            }
        }
    }
    
    Context "Edge Cases" {
        It "Should handle empty table list" {
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables @()
            
            $result | Should -BeNullOrEmpty
        }
        
        It "Should handle single table" {
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables @("Categories")
            
            $result | Should -Be @("Categories")
        }
        
        It "Should handle tables with no dependencies" {
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables @("Categories", "Suppliers")
            
            $result.Count | Should -Be 2
            $result | Should -Contain "Categories"
            $result | Should -Contain "Suppliers"
        }
    }
    
    Context "Self-referencing Tables" {
        BeforeAll {
            # Maak self-referencing table
            Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY,
    ManagerID INT,
    Name NVARCHAR(50),
    FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID)
);
"@
        }
        
        It "Should handle self-referencing tables" {
            $result = Get-TableDependencyOrder -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -Tables @("Employees")
            
            $result | Should -Contain "Employees"
        }
    }
}
