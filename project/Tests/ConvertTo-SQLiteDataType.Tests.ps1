BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
}

Describe "ConvertTo-SQLiteDataType" {
    
    Context "Integer Types" {
        It "Should convert INT to INTEGER" {
            ConvertTo-SQLiteDataType -SqlServerType "int" | Should -Be "INTEGER"
        }
        
        It "Should convert BIGINT to INTEGER" {
            ConvertTo-SQLiteDataType -SqlServerType "bigint" | Should -Be "INTEGER"
        }
        
        It "Should convert SMALLINT to INTEGER" {
            ConvertTo-SQLiteDataType -SqlServerType "smallint" | Should -Be "INTEGER"
        }
        
        It "Should convert TINYINT to INTEGER" {
            ConvertTo-SQLiteDataType -SqlServerType "tinyint" | Should -Be "INTEGER"
        }
        
        It "Should convert BIT to INTEGER" {
            ConvertTo-SQLiteDataType -SqlServerType "bit" | Should -Be "INTEGER"
        }
    }
    
    Context "String Types" {
        It "Should convert VARCHAR to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "varchar" | Should -Be "TEXT"
        }
        
        It "Should convert NVARCHAR to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "nvarchar" | Should -Be "TEXT"
        }
        
        It "Should convert CHAR to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "char" | Should -Be "TEXT"
        }
        
        It "Should convert NCHAR to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "nchar" | Should -Be "TEXT"
        }
        
        It "Should convert TEXT to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "text" | Should -Be "TEXT"
        }
        
        It "Should convert NTEXT to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "ntext" | Should -Be "TEXT"
        }
    }
    
    Context "Decimal Types" {
        It "Should convert DECIMAL to REAL" {
            ConvertTo-SQLiteDataType -SqlServerType "decimal" | Should -Be "REAL"
        }
        
        It "Should convert NUMERIC to REAL" {
            ConvertTo-SQLiteDataType -SqlServerType "numeric" | Should -Be "REAL"
        }
        
        It "Should convert FLOAT to REAL" {
            ConvertTo-SQLiteDataType -SqlServerType "float" | Should -Be "REAL"
        }
        
        It "Should convert REAL to REAL" {
            ConvertTo-SQLiteDataType -SqlServerType "real" | Should -Be "REAL"
        }
        
        It "Should convert MONEY to REAL" {
            ConvertTo-SQLiteDataType -SqlServerType "money" | Should -Be "REAL"
        }
    }
    
    Context "Date/Time Types" {
        It "Should convert DATETIME to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "datetime" | Should -Be "TEXT"
        }
        
        It "Should convert DATETIME2 to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "datetime2" | Should -Be "TEXT"
        }
        
        It "Should convert DATE to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "date" | Should -Be "TEXT"
        }
        
        It "Should convert TIME to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "time" | Should -Be "TEXT"
        }
    }
    
    Context "Binary Types" {
        It "Should convert BINARY to BLOB" {
            ConvertTo-SQLiteDataType -SqlServerType "binary" | Should -Be "BLOB"
        }
        
        It "Should convert VARBINARY to BLOB" {
            ConvertTo-SQLiteDataType -SqlServerType "varbinary" | Should -Be "BLOB"
        }
        
        It "Should convert IMAGE to BLOB" {
            ConvertTo-SQLiteDataType -SqlServerType "image" | Should -Be "BLOB"
        }
    }
    
    Context "Special Types" {
        It "Should convert UNIQUEIDENTIFIER to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "uniqueidentifier" | Should -Be "TEXT"
        }
        
        It "Should convert XML to TEXT" {
            ConvertTo-SQLiteDataType -SqlServerType "xml" | Should -Be "TEXT"
        }
    }
    
    Context "Case Insensitivity" {
        It "Should handle uppercase type names" {
            ConvertTo-SQLiteDataType -SqlServerType "INT" | Should -Be "INTEGER"
        }
        
        It "Should handle mixed case type names" {
            ConvertTo-SQLiteDataType -SqlServerType "VarChar" | Should -Be "TEXT"
        }
    }
    
    Context "Unknown Types" {
        It "Should return TEXT for unknown types" {
            ConvertTo-SQLiteDataType -SqlServerType "unknowntype" | Should -Be "TEXT"
        }
    }
}
