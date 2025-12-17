BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    Import-Module PSSQLite -Force
    
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:TestDatabase = "PesterTest_SQLiteToSQL_$(Get-Random)"
    $script:TestSQLitePath = "$PSScriptRoot\..\data\PesterTest_$(Get-Random).db"
    
    # Maak SQLite test database met data
    Invoke-SqliteQuery -DataSource $script:TestSQLitePath -Query @"
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY AUTOINCREMENT,
    Username TEXT NOT NULL,
    Email TEXT
);

CREATE TABLE Posts (
    PostID INTEGER PRIMARY KEY,
    UserID INTEGER,
    Title TEXT NOT NULL,
    Content TEXT,
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
);

INSERT INTO Users (Username, Email) VALUES ('alice', 'alice@test.com');
INSERT INTO Users (Username, Email) VALUES ('bob', 'bob@test.com');
INSERT INTO Posts (PostID, UserID, Title, Content) VALUES (1, 1, 'First Post', 'Content 1');
INSERT INTO Posts (PostID, UserID, Title, Content) VALUES (2, 2, 'Second Post', 'Content 2');
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

Describe "Convert-SQLiteToSqlServer" {
    
    Context "Basic Migration" {
        It "Should migrate database successfully" {
            $result = Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $result.Success | Should -Be $true
        }
        
        It "Should migrate all tables" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $tables = Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'"
            
            $tables.TABLE_NAME | Should -Contain "Users"
            $tables.TABLE_NAME | Should -Contain "Posts"
        }
        
        It "Should migrate all data" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $userCount = (Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query "SELECT COUNT(*) as cnt FROM Users").cnt
            
            $postCount = (Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query "SELECT COUNT(*) as cnt FROM Posts").cnt
            
            $userCount | Should -Be 2
            $postCount | Should -Be 2
        }
    }
    
    Context "Primary Keys" {
        It "Should create primary keys" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $pk = Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query @"
SELECT c.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE c 
    ON tc.CONSTRAINT_NAME = c.CONSTRAINT_NAME 
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.TABLE_NAME = 'Users'
"@
            
            $pk.COLUMN_NAME | Should -Be "UserID"
        }
    }
    
    Context "Foreign Keys" {
        It "Should create foreign keys" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $fks = Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query @"
SELECT 
    c.name AS ColumnName,
    rt.name AS ReferencedTable
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns c ON fkc.parent_column_id = c.column_id AND fkc.parent_object_id = c.object_id
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id
WHERE t.name = 'Posts'
"@
            
            $fks.ColumnName | Should -Contain "UserID"
            $fks.ReferencedTable | Should -Contain "Users"
        }
    }
    
    Context "Data Types" {
        It "Should convert INTEGER to INT" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $dataType = Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='Users' AND COLUMN_NAME='UserID'"
            
            $dataType.DATA_TYPE | Should -Be "int"
        }
        
        It "Should convert TEXT to NVARCHAR" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $dataType = Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='Users' AND COLUMN_NAME='Username'"
            
            $dataType.DATA_TYPE | Should -Be "nvarchar"
        }
    }
    
    Context "IDENTITY columns" {
        It "Should create IDENTITY for AUTOINCREMENT columns" {
            Convert-SQLiteToSqlServer `
                -SQLitePath $script:TestSQLitePath `
                -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase
            
            $identity = Invoke-Sqlcmd -ServerInstance $script:ServerInstance `
                -Database $script:TestDatabase `
                -TrustServerCertificate `
                -Query @"
SELECT COLUMNPROPERTY(OBJECT_ID('Users'), 'UserID', 'IsIdentity') as IsIdentity
"@
            
            $identity.IsIdentity | Should -Be 1
        }
    }
}
