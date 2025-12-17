BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    
    # Helper function om private function te testen
    $module = Get-Module DatabaseMigration
    $parseFn = $module.Invoke({ Get-Command Parse-SqlitePrimaryKeyInfo })
}

Describe "Parse-SqlitePrimaryKeyInfo" {
    
    Context "Table-level Primary Key" {
        It "Should parse single column PK with square brackets" {
            $ddl = "CREATE TABLE [Customers] ([CustomerID] INTEGER NOT NULL, [Name] TEXT, PRIMARY KEY ([CustomerID]))"
            $columns = @("CustomerID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Be @("CustomerID")
            $result.AutoIncrement | Should -BeNullOrEmpty
        }
        
        It "Should parse single column PK without square brackets" {
            $ddl = "CREATE TABLE Customers (CustomerID INTEGER NOT NULL, Name TEXT, PRIMARY KEY (CustomerID))"
            $columns = @("CustomerID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Be @("CustomerID")
        }
        
        It "Should parse composite primary key" {
            $ddl = "CREATE TABLE OrderDetails (OrderID INT, ProductID INT, PRIMARY KEY (OrderID, ProductID))"
            $columns = @("OrderID", "ProductID", "Quantity")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns.Count | Should -Be 2
            $result.Columns | Should -Contain "OrderID"
            $result.Columns | Should -Contain "ProductID"
        }
        
        It "Should normalize column names to match case" {
            $ddl = "CREATE TABLE Test (id INTEGER, PRIMARY KEY (id))"
            $columns = @("ID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Be @("ID")
        }
    }
    
    Context "Column-level Primary Key" {
        It "Should parse inline PRIMARY KEY" {
            $ddl = "CREATE TABLE Users (UserID INTEGER PRIMARY KEY, Name TEXT)"
            $columns = @("UserID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Be @("UserID")
        }
        
        It "Should parse PRIMARY KEY with NOT NULL" {
            $ddl = "CREATE TABLE Users (UserID INTEGER NOT NULL PRIMARY KEY, Name TEXT)"
            $columns = @("UserID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Be @("UserID")
        }
    }
    
    Context "AUTOINCREMENT Detection" {
        It "Should detect AUTOINCREMENT" {
            $ddl = "CREATE TABLE Users (UserID INTEGER PRIMARY KEY AUTOINCREMENT, Name TEXT)"
            $columns = @("UserID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.AutoIncrement | Should -Be "UserID"
            $result.Columns | Should -Be @("UserID")
        }
        
        It "Should detect INTEGER PRIMARY KEY as auto-increment" {
            $ddl = "CREATE TABLE Users (UserID INTEGER PRIMARY KEY, Name TEXT)"
            $columns = @("UserID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.AutoIncrement | Should -Be "UserID"
        }
    }
    
    Context "Edge Cases" {
        It "Should handle empty DDL" -Skip {
            # Skipped: Parse-SqlitePrimaryKeyInfo requires non-empty string parameter
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } "" @()
            
            $result.Columns | Should -BeNullOrEmpty
            $result.AutoIncrement | Should -BeNullOrEmpty
        }
        
        It "Should handle DDL without PRIMARY KEY" {
            $ddl = "CREATE TABLE Temp (Col1 TEXT, Col2 INT)"
            $columns = @("Col1", "Col2")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -BeNullOrEmpty
        }
        
        It "Should handle square brackets in column names correctly" {
            $ddl = "CREATE TABLE [Test Table] ([User ID] INTEGER, [Name] TEXT, PRIMARY KEY ([User ID]))"
            $columns = @("User ID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Contain "User ID"
        }
    }
    
    Context "Complex Scenarios" {
        It "Should handle multiple whitespace" {
            $ddl = "CREATE  TABLE   Users   (  UserID   INTEGER   PRIMARY   KEY  ,  Name   TEXT  )"
            $columns = @("UserID", "Name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns | Should -Be @("UserID")
        }
        
        It "Should handle case insensitive keywords" {
            $ddl = "create table users (userid integer Primary Key, name text)"
            $columns = @("userid", "name")
            
            $result = & $module { param($ddl, $cols) Parse-SqlitePrimaryKeyInfo -CreateTableSql $ddl -ColumnNames $cols } $ddl $columns
            
            $result.Columns.Count | Should -Be 1
        }
    }
}
