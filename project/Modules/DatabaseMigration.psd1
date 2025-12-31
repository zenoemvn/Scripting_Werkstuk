@{
    # Script module or binary module file associated with this manifest
    RootModule = 'DatabaseMigration.psm1'
    
    # Version number of this module
    ModuleVersion = '1.0.0'
    
    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')
    
    # ID used to uniquely identify this module
    GUID = 'a3e4f5b6-7c8d-9e0f-1a2b-3c4d5e6f7a8b'
    
    # Author of this module
    Author = 'Zeno Van Neygen'
    
    # Company or vendor of this module
    CompanyName = 'Erasmus Hogeschool Brussel'
    
    # Copyright statement for this module
    Copyright = '(c) 2024-2025 Zeno Van Neygen. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = @'
Database Migration Toolkit - Complete solution for database migrations and schema management.

Features:
- Bidirectional migration between SQL Server and SQLite
- CSV export/import with metadata preservation
- Automatic schema analysis and documentation (Markdown/JSON)
- Foreign key and constraint auto-detection
- Data integrity validation with checksums
- Excel migration reports with detailed analytics
- Batch processing for large datasets

Supports:
- SQL Server (LocalDB, Express, Standard, Enterprise)
- SQLite databases
- CSV files with metadata
'@
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ ModuleName = 'SqlServer'; ModuleVersion = '21.0.0'; },
        @{ ModuleName = 'PSSQLite'; ModuleVersion = '1.0.0'; },
        @{ ModuleName = 'ImportExcel'; ModuleVersion = '7.0.0'; }
    )
    
    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()
    
    # Script files (.ps1) that are run in the caller's environment prior to importing this module
    # ScriptsToProcess = @()
    
    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()
    
    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()
    
    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()
    
    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry
    FunctionsToExport = @(
        # SQLite ↔ SQL Server Migration
        'Convert-SQLiteToSqlServer',
        'Convert-SqlServerToSQLite',
        
        # CSV Operations
        'Export-DatabaseSchemaToCsv',
        'Export-DatabaseSchemaToMarkdown',
        'Export-SqlTableToCsv',
        'Import-CsvToSqlTable',
        'Import-DatabaseFromCsv',
        
        # Data Validation
        'Get-DataChecksum',
        'Test-DataIntegrity',
        
        # Reporting
        'Export-MigrationReport',
        
        # Helper Functions
        'ConvertTo-SQLiteDataType',
        'ConvertTo-SqlServerDataType',
        'Get-TableDependencyOrder'
    )
    
    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry
    AliasesToExport = @()
    
    # DSC resources to export from this module
    # DscResourcesToExport = @()
    
    # List of all modules packaged with this module
    # ModuleList = @()
    
    # List of all files packaged with this module
    FileList = @(
        'DatabaseMigration.psm1',
        'DatabaseMigration.psd1'
    )
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for online galleries
            Tags = @(
                'Database',
                'Migration',
                'SQLServer',
                'SQLite',
                'CSV',
                'Schema',
                'Export',
                'Import',
                'DataMigration',
                'DatabaseTools',
                'Scripting'
            )
            
            # A URL to the license for this module
            # LicenseUri = ''
            
            # A URL to the main website for this project
            # ProjectUri = ''
            
            # A URL to an icon representing this module
            # IconUri = ''
            
            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.0.0 (2024-12-25)
- Initial release
- Bidirectional SQL Server ↔ SQLite migration
- CSV export/import with full metadata support
- Automatic schema analysis and documentation
- Foreign key auto-detection from data patterns
- Data integrity validation with checksums
- Excel migration reports with multiple sheets
- Batch processing support for large datasets
- Execution time tracking with fractional seconds
- Primary and Foreign Key preservation
'@
            
            # Prerelease string of this module
            # Prerelease = ''
            
            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false
            
            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }
    
    # HelpInfo URI of this module
    # HelpInfoURI = ''
    
    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix
    # DefaultCommandPrefix = ''
}
