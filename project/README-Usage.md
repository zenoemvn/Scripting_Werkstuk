# Database Migration Toolkit - Gebruikshandleiding

## Overzicht
Dit project bevat geen hardcoded database namen of server instances. Alle parameters moeten expliciet worden opgegeven, zodat iedereen het kan gebruiken met hun eigen configuratie.

## Vereisten
- PowerShell 7+
- SQL Server (elke versie/instance)
- SqlServer PowerShell module
- PSSQLite module (voor SQLite conversies)

## Belangrijkste Scripts

### 1. Database Aanmaken met Test Data
```powershell
.\create-testdatabasewithrelations.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -DatabaseName "MijnDatabase"
```

### 2. Export naar CSV (MET Schema)
Behoudt Primary Keys en Foreign Keys:
```powershell
.\Export.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDatabase" `
    -OutputFolder ".\Export\MijnExport" `
    -SaveSchemaMetadata
```

Of gebruik de quick versie:
```powershell
.\Quick-Export-WithMetadata.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDatabase"
```

### 3. Export naar CSV (ZONDER Schema)
Simpele CSV export voor data analyse:
```powershell
.\Export.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDatabase" `
    -OutputFolder ".\Export\MijnExport"
```

Of gebruik de quick versie:
```powershell
.\Quick-Export-Simple.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDatabase"
```

### 4. Import van CSV naar Database
Met auto-detectie van Foreign Keys:
```powershell
.\Csvimport.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -CsvFolder ".\Export\MijnExport" `
    -DatabaseName "NieuweDatabase"
```

### 5. Database Relaties Testen
Test de integriteit van je database:
```powershell
.\relaties-testen.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDatabase"
```

### 6. Database Overzicht Tonen
```powershell
.\Show-Database.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDatabase"
```

### 7. Complete Roundtrip Test
Test SQL → CSV → SQL met schema behoud:
```powershell
.\Test-CsvRoundtrip.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -SourceDatabase "Bron" `
    -TargetDatabase "Doel" `
    -ExportFolder ".\Export\Test"
```

## Verschillende Server Instances Gebruiken

Voor **SQL Server Express**:
```powershell
-ServerInstance "localhost\SQLEXPRESS"
```

Voor **standaard SQL Server**:
```powershell
-ServerInstance "localhost"
```

Voor **named instance**:
```powershell
-ServerInstance "COMPUTERNAAM\INSTANCENAAM"
```

Voor **remote server**:
```powershell
-ServerInstance "192.168.1.100\SQLEXPRESS"
```

## Module Functies Direct Gebruiken

Import de module eerst:
```powershell
Import-Module ".\Modules\DatabaseMigration.psm1"
```

### Export met Schema Metadata
```powershell
Export-DatabaseSchemaToCsv `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDB" `
    -OutputFolder ".\Export\MijnDB"
```

### Import met Auto-detectie
```powershell
Import-DatabaseFromCsv `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "NieuweDB" `
    -CsvFolder ".\Export\MijnDB"
```

### SQLite naar SQL Server
```powershell
Convert-SQLiteToSqlServer `
    -SQLitePath ".\data\mijn.db" `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "NieuweDB"
```

### SQL Server naar SQLite
```powershell
Convert-SqlServerToSQLite `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "MijnDB" `
    -SQLitePath ".\data\export.db"
```

## Automatische Foreign Key Detectie

Wanneer je een CSV importeert **zonder** schema-metadata.json, zal het systeem automatisch:
1. Primary Keys detecteren (kolommen eindigend op "ID")
2. Foreign Keys detecteren door:
   - Kolommen te zoeken die eindigen op "ID"
   - Te kijken of een tabel met die naam bestaat
   - Te valideren dat alle waarden bestaan in de gerefereerde tabel
   - Alleen FKs aan te maken als validatie slaagt

## Tips
- Gebruik altijd **-SaveSchemaMetadata** als je schema wilt behouden
- Zonder metadata wordt er automatisch gedetecteerd (maar minder betrouwbaar)
- Test scripts eerst met kleine databases
- Controleer altijd de output folders na export

## Voorbeelden

### Complete workflow: Test DB → CSV → Nieuwe DB
```powershell
# Stap 1: Maak test database
.\create-testdatabasewithrelations.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -DatabaseName "TestDB"

# Stap 2: Export met schema
.\Export.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "TestDB" `
    -OutputFolder ".\Export\TestDB" `
    -SaveSchemaMetadata

# Stap 3: Import naar nieuwe database
.\Csvimport.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -CsvFolder ".\Export\TestDB" `
    -DatabaseName "TestDB_Clone"

# Stap 4: Verifieer resultaat
.\relaties-testen.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "TestDB_Clone"
```
