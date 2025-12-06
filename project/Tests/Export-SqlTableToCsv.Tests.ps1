BeforeAll {
    # Import de functie
    . "$PSScriptRoot\..\Modules\Migration\Export-SqlTableToCsv.ps1"
    
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:Database = "TestDB"
    $script:TestOutputPath = "$PSScriptRoot\..\Output\Test_Export.csv"
}

Describe "Export-SqlTableToCsv" {
    
    It "Should export Users table successfully" {
        $result = Export-SqlTableToCsv -ServerInstance $script:ServerInstance `
            -Database $script:Database `
            -TableName "Users" `
            -OutputPath $script:TestOutputPath
        
        $result.Success | Should -Be $true
        Test-Path $script:TestOutputPath | Should -Be $true
    }
    
    It "Should export correct number of rows" {
        $result = Export-SqlTableToCsv -ServerInstance $script:ServerInstance `
            -Database $script:Database `
            -TableName "Users" `
            -OutputPath $script:TestOutputPath
        
        $result.RowCount | Should -Be 3
    }
    
    It "Should fail for non-existent table" {
        $result = Export-SqlTableToCsv -ServerInstance $script:ServerInstance `
            -Database $script:Database `
            -TableName "NonExistentTable" `
            -OutputPath $script:TestOutputPath `
            -ErrorAction SilentlyContinue
        
        $result.Success | Should -Be $false
    }
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestOutputPath) {
        Remove-Item $script:TestOutputPath
    }
}