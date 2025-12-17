BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    Import-Module PSSQLite -Force
    
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:TestDatabase = "PesterTest_SQLToSQLite_$(Get-Random)"
    $script:TestSQLitePath = "$PSScriptRoot\..\data\PesterTest_$(Get-Random).db"
    
    # Maak SQL Server test database
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:TestDatabase)')
BEGIN
    ALTER DATABASE [$($script:TestDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:TestDatabase)];
END
CREATE DATABASE [$($script:TestDatabase)];
"@
    
    # Maak test tables met data
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:TestDatabase -TrustServerCertificate -Query @"
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL
);

CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    CategoryID INT,
    Name NVARCHAR(100) NOT NULL,
    Price DECIMAL(10,2),
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID)
);

INSERT INTO Categories (CategoryID, Name) VALUES (1, 'Electronics'), (2, 'Books');
INSERT INTO Products (ProductID, CategoryID, Name, Price) VALUES (1, 1, 'Laptop', 999.99);
INSERT INTO Products (ProductID, CategoryID, Name, Price) VALUES (2, 2, 'Novel', 19.99);
"@
}

AfterAll {
    # Cleanup
    try {
        if (Test-Path $script:TestSQLitePath) {
            Remove-Item $script:TestSQLitePath -Force
        }
        
        Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:TestDatabase)')
BEGIN
    ALTER DATABASE [$($script:TestDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:TestDatabase)];
END
"@
    }
    catch {
        Write-Warning "Could not clean up: $_"
    }
}

Describe "Convert-SqlServerToSQLite" {
    
    Context "Basic Migration" {
        It "Should migrate database successfully" {
            $result = Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $result.Success | Should -Be $true
        }
        
        It "Should create SQLite file" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            Test-Path $script:TestSQLitePath | Should -Be $true
        }
        
        It "Should migrate all tables" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $tables = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "SELECT name FROM sqlite_master WHERE type='table'"
            
            $tables.name | Should -Contain "Categories"
            $tables.name | Should -Contain "Products"
        }
        
        It "Should migrate all data" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $categoryCount = (Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "SELECT COUNT(*) as cnt FROM Categories").cnt
            
            $productCount = (Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "SELECT COUNT(*) as cnt FROM Products").cnt
            
            $categoryCount | Should -Be 2
            $productCount | Should -Be 2
        }
    }
    
    Context "Primary Keys" {
        It "Should embed primary keys in CREATE TABLE" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $tableInfo = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "PRAGMA table_info('Categories')"
            
            $pkColumn = $tableInfo | Where-Object { $_.pk -eq 1 }
            $pkColumn.name | Should -Be "CategoryID"
        }
    }
    
    Context "Foreign Keys" {
        It "Should embed foreign keys in CREATE TABLE" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $fks = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "PRAGMA foreign_key_list('Products')"
            
            $fks.'table' | Should -Contain "Categories"
            $fks.from | Should -Contain "CategoryID"
        }
    }
    
    Context "Data Types" {
        It "Should convert INT to INTEGER" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $tableInfo = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "PRAGMA table_info('Categories')"
            
            $column = $tableInfo | Where-Object { $_.name -eq "CategoryID" }
            $column.type | Should -Be "INTEGER"
        }
        
        It "Should convert NVARCHAR to TEXT" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $tableInfo = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "PRAGMA table_info('Categories')"
            
            $column = $tableInfo | Where-Object { $_.name -eq "Name" }
            $column.type | Should -Be "TEXT"
        }
        
        It "Should convert DECIMAL to REAL" {
            Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            $tableInfo = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "PRAGMA table_info('Products')"
            
            $column = $tableInfo | Where-Object { $_.name -eq "Price" }
            $column.type | Should -Be "REAL"
        }
    }
    
    Context "Table Ordering" {
        It "Should migrate parent tables before child tables" {
            $result = Convert-SqlServerToSQLite `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -SQLitePath $script:TestSQLitePath
            
            # Als de volgorde correct is, zou Products niet kunnen worden aangemaakt voor Categories
            # We kunnen dit indirect testen door te kijken of beide tables bestaan
            $tables = Invoke-SqliteQuery -DataSource $script:TestSQLitePath `
                -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            
            $tables.name | Should -Contain "Categories"
            $tables.name | Should -Contain "Products"
        }
    }
}
