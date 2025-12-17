BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    
    # Get de private function via module scope
    $module = Get-Module DatabaseMigration
    
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:TestDatabase = "PesterTest_FindFK_$(Get-Random)"
    
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

Describe "Find-ForeignKeysFromData" {
    
    Context "Basic FK Detection" {
        BeforeAll {
            # Maak parent en child tables
            Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    Name NVARCHAR(50)
);

CREATE TABLE Posts (
    PostID INT PRIMARY KEY,
    UserID INT,
    Title NVARCHAR(100)
);

-- Insert test data met geldige referenties
INSERT INTO Users (UserID, Name) VALUES (1, 'Alice'), (2, 'Bob');
INSERT INTO Posts (PostID, UserID, Title) VALUES (1, 1, 'Post 1'), (2, 2, 'Post 2');
"@
        }
        
        It "Should detect FK from column ending in ID" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            $result.Keys | Should -Contain "FK_Posts_Users"
        }
        
        It "Should detect correct FK relationship" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            $fk = $result["FK_Posts_Users"]
            $fk.FromTable | Should -Be "Posts"
            $fk.FromColumn | Should -Be "UserID"
            $fk.ToTable | Should -Be "Users"
            $fk.ToColumn | Should -Be "UserID"
        }
    }
    
    Context "FK Validation" {
        BeforeAll {
            # Maak tables met invalid references
            Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY,
    Name NVARCHAR(50)
);

CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    CategoryID INT,
    Name NVARCHAR(50)
);

-- Insert data met INVALID references
INSERT INTO Categories (CategoryID, Name) VALUES (1, 'Cat1'), (2, 'Cat2');
INSERT INTO Products (ProductID, CategoryID, Name) VALUES (1, 1, 'Prod1'), (2, 999, 'Prod2');
"@
        }
        
        It "Should NOT detect FK when data validation fails" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            # FK_Products_Categories should NOT be detected omdat er een invalid value (999) is
            $result.Keys | Should -Not -Contain "FK_Products_Categories"
        }
    }
    
    Context "NULL Values" {
        BeforeAll {
            Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE Suppliers (
    SupplierID INT PRIMARY KEY,
    Name NVARCHAR(50)
);

CREATE TABLE Items (
    ItemID INT PRIMARY KEY,
    SupplierID INT NULL,
    Name NVARCHAR(50)
);

-- Insert data met NULL values (dit mag wel voor FKs)
INSERT INTO Suppliers (SupplierID, Name) VALUES (1, 'Supplier1');
INSERT INTO Items (ItemID, SupplierID, Name) VALUES (1, 1, 'Item1'), (2, NULL, 'Item2');
"@
        }
        
        It "Should detect FK even with NULL values" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            # NULL values zijn toegestaan voor FKs
            $result.Keys | Should -Contain "FK_Items_Suppliers"
        }
    }
    
    Context "Multiple FKs" {
        BeforeAll {
            Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(50)
);

CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY,
    Name NVARCHAR(50)
);

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    EmployeeID INT
);

INSERT INTO Customers (CustomerID, Name) VALUES (1, 'Customer1');
INSERT INTO Employees (EmployeeID, Name) VALUES (1, 'Employee1');
INSERT INTO Orders (OrderID, CustomerID, EmployeeID) VALUES (1, 1, 1);
"@
        }
        
        It "Should detect multiple FKs from same table" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            $result.Keys | Should -Contain "FK_Orders_Customers"
            $result.Keys | Should -Contain "FK_Orders_Employees"
        }
    }
    
    Context "Edge Cases" {
        BeforeAll {
            Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE TestTable (
    TestID INT PRIMARY KEY,
    RandomID INT,
    Name NVARCHAR(50)
);

INSERT INTO TestTable (TestID, RandomID, Name) VALUES (1, 999, 'Test');
"@
        }
        
        It "Should handle columns ending in ID with no matching table" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            # RandomID should not create a FK because there's no "Random" table
            $fkKeys = $result.Keys | Where-Object { $_ -like "*Random*" }
            $fkKeys | Should -BeNullOrEmpty
        }
        
        It "Should not detect FK from own PK column" {
            $result = & $module { 
                param($si, $db) 
                Find-ForeignKeysFromData -ServerInstance $si -Database $db 
            } $script:ServerInstance $script:TestDatabase
            
            # TestID is the PK, should not be detected as FK
            $fkKeys = $result.Keys | Where-Object { $_ -like "*TestTable_TestTable*" }
            $fkKeys | Should -BeNullOrEmpty
        }
    }
}
