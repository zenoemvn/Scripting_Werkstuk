BeforeAll {
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
}

Describe "ConvertTo-SqlServerDataType" {
    
    Context "INTEGER Type" {
        It "Should convert INTEGER to INT" {
            ConvertTo-SqlServerDataType -SQLiteType "INTEGER" | Should -Be "INT"
        }
        
        It "Should convert INT to INT" {
            ConvertTo-SqlServerDataType -SQLiteType "INT" | Should -Be "INT"
        }
    }
    
    Context "TEXT Type" {
        It "Should convert TEXT to NVARCHAR(MAX)" {
            ConvertTo-SqlServerDataType -SQLiteType "TEXT" | Should -Be "NVARCHAR(MAX)"
        }
        
        It "Should convert VARCHAR to NVARCHAR(MAX)" {
            ConvertTo-SqlServerDataType -SQLiteType "VARCHAR" | Should -Be "NVARCHAR(MAX)"
        }
        
        It "Should convert CHAR to NVARCHAR(MAX)" {
            ConvertTo-SqlServerDataType -SQLiteType "CHAR" | Should -Be "NVARCHAR(MAX)"
        }
    }
    
    Context "REAL Type" {
        It "Should convert REAL to FLOAT" {
            ConvertTo-SqlServerDataType -SQLiteType "REAL" | Should -Be "FLOAT"
        }
        
        It "Should convert FLOAT to FLOAT" {
            ConvertTo-SqlServerDataType -SQLiteType "FLOAT" | Should -Be "FLOAT"
        }
        
        It "Should convert DOUBLE to FLOAT" {
            ConvertTo-SqlServerDataType -SQLiteType "DOUBLE" | Should -Be "FLOAT"
        }
    }
    
    Context "BLOB Type" {
        It "Should convert BLOB to VARBINARY(MAX)" {
            ConvertTo-SqlServerDataType -SQLiteType "BLOB" | Should -Be "VARBINARY(MAX)"
        }
    }
    
    Context "NUMERIC Type" {
        It "Should convert NUMERIC to DECIMAL(18,2)" {
            ConvertTo-SqlServerDataType -SQLiteType "NUMERIC" | Should -Be "DECIMAL(18,2)"
        }
    }
    
    Context "Case Insensitivity" {
        It "Should handle uppercase type names" {
            ConvertTo-SqlServerDataType -SQLiteType "INTEGER" | Should -Be "INT"
        }
        
        It "Should handle lowercase type names" {
            ConvertTo-SqlServerDataType -SQLiteType "integer" | Should -Be "INT"
        }
        
        It "Should handle mixed case type names" {
            ConvertTo-SqlServerDataType -SQLiteType "TeXt" | Should -Be "NVARCHAR(MAX)"
        }
    }
    
    Context "Unknown Types" {
        It "Should return NVARCHAR(MAX) for unknown types" {
            ConvertTo-SqlServerDataType -SQLiteType "unknowntype" | Should -Be "NVARCHAR(MAX)"
        }
    }
}
