BeforeAll {
    # Import de module
    Import-Module "$PSScriptRoot\..\Modules\DatabaseMigration.psm1" -Force
    
    $script:ServerInstance = "localhost\SQLEXPRESS"
    $script:Database = "PesterTest_Export_$(Get-Random)"
    $script:TestOutputPath = "$PSScriptRoot\..\Output\Test_Export.csv"
    
    # Maak test database met data
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:Database)')
BEGIN
    ALTER DATABASE [$($script:Database)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:Database)];
END
CREATE DATABASE [$($script:Database)];
"@
    
    Invoke-Sqlcmd -ServerInstance $script:ServerInstance -Database $script:Database -TrustServerCertificate -Query @"
CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    Username NVARCHAR(50),
    Email NVARCHAR(100)
);

INSERT INTO Users (UserID, Username, Email) VALUES 
    (1, 'alice', 'alice@test.com'),
    (2, 'bob', 'bob@test.com'),
    (3, 'charlie', 'charlie@test.com');
"@
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
        Remove-Item $script:TestOutputPath -ErrorAction SilentlyContinue
    }
    
    # Drop test database
    try {
        Invoke-Sqlcmd -ServerInstance $script:ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($script:Database)')
BEGIN
    ALTER DATABASE [$($script:Database)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$($script:Database)];
END
"@
    }
    catch {
        Write-Warning "Could not clean up test database: $_"
    }
}