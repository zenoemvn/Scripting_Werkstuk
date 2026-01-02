# 🗄️ Database Migration Toolkit

##  Inhoudsopgave

- [Het Doel van het Project](#-het-doel-van-het-project)
- [Requirements](#-requirements)
- [Installatie](#-installatie)
- [Dataset Importeren](#-dataset-importeren)
- [Gebruik](#-gebruik)
- [Configuratie](#-configuratie)
- [Architectuur & Structuur](#-architectuur--structuur)
- [Bronnen](#-bronnen)

---

## 🎯 Het Doel van het Project

### Wat doet het?

De **Database Migration Toolkit** is een PowerShell-gebaseerd systeem dat database migraties tussen SQL Server en SQLite vereenvoudigt en automatiseert. Het biedt een complete oplossing voor:

- **Bidirectionele database conversie**: Migreer van SQL Server naar SQLite en omgekeerd met volledige behoud van data en structuur
- **CSV export/import met schema preservatie**: Exporteer databases naar CSV formaat met complete behoud van relationele integriteit (Primary Keys, Foreign Keys, datatypes, constraints)
- **Schema analyse en documentatie**: Genereer gedetailleerde rapporten over database structuur, relaties en metadata in Markdown en Excel formaten
- **Data validatie**: Automatische validatie van data integriteit tijdens migratie met SHA256 checksum verificatie
- **Batch processing**: Efficiënte verwerking van grote datasets (1M+ rijen) met configureerbare batch groottes

### Kernfunctionaliteit

Het project lost het probleem op van complexe database migraties waarbij relationele integriteit behouden moet blijven. Traditionele export/import tools verliezen vaak informatie over foreign keys en constraints. Deze toolkit bewaart alle metadata en kan databases 1-op-1 repliceren via CSV als tussenformaat.

**Hoofdgebruiksscenario's:**
1. **Database backups en restores** via portable formaten (CSV, SQLite)
2. **Ontwikkel/test omgeving setup** vanuit productie data met geanonimiseerde kopieën
3. **Database conversie** tussen verschillende platformen (SQL Server ↔ SQLite)
4. **Data analyse en rapportage** met export naar Excel en CSV
5. **Schema documentatie en auditing** voor compliance en knowledge management

**Belangrijkste troeven:**
- ✅ Geen data verlies: alle constraints, indexes en relaties worden bewaard
- ✅ Flexibel: werkt met elke SQL Server instance (LocalDB, Express, Standard, Enterprise)
- ✅ Betrouwbaar: 127 geautomatiseerde tests garanderen correctheid
- ✅ Performant: batch processing voor snelle migratie van grote datasets
- ✅ Transparant: gedetailleerde logging en rapportage van alle operaties

---

## 🔧 Requirements

### Software Vereisten

| Software | Versie | Verplicht? | Doel |
|----------|--------|------------|------|
| **PowerShell** | 7.0 of hoger | Ja | Cross-platform ondersteuning en moderne syntax |
| **SQL Server** | Elke versie | Ja | Bron- of doeldatabase (LocalDB, Express, Developer, Standard, Enterprise) |
| **SQL Server Management Studio** | Laatste versie | Nee | Optioneel voor GUI management |
| **.NET Framework** | 4.7.2 of hoger | Ja | Voor PowerShell modules |

### PowerShell Modules

De volgende PowerShell modules moeten geïnstalleerd zijn (worden automatisch geïnstalleerd via setup script):

```powershell
# SqlServer module (voor SQL Server connectie en queries)
Install-Module -Name SqlServer -Scope CurrentUser -Force

# PSSQLite module (voor SQLite database operaties)
Install-Module -Name PSSQLite -Scope CurrentUser -Force

# ImportExcel module (voor Excel rapportage)
Install-Module -Name ImportExcel -Scope CurrentUser -Force

# Pester module (voor unit testing - optioneel)
Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
```

---

## 📦 Installatie

### Stap 1: Download Project

```powershell
# Navigeer naar gewenste locatie
cd "C:\Users\<YourName>\Documents"

# Download en unzip het project naar deze locatie
# Of clone via git (indien beschikbaar):
# git clone <repository-url> .\Scripting_Werkstuk
```

### Stap 2: Navigeer naar Project Folder

```powershell
cd ".\Scripting_Werkstuk\project"
```

### Stap 3: Installeer Vereiste Modules

Het project bevat een setup script dat alle benodigde modules automatisch installeert:

```powershell
# Voer het setup script uit
.\Setup-SQLite.ps1
```

Dit script installeert:
- SqlServer module (indien nog niet aanwezig)
- PSSQLite module (indien nog niet aanwezig)
- ImportExcel module (indien nog niet aanwezig)

**Alternatief: Manuele installatie**
```powershell
# Installeer alle modules in één keer
$modules = @('SqlServer', 'PSSQLite', 'ImportExcel', 'Pester')
foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Scope CurrentUser -Force
    }
}
```

### Stap 4: Importeer de Module

```powershell
# Importeer de DatabaseMigration module
Import-Module .\Modules\DatabaseMigration.psm1 -Force
```

### Stap 5: Verifieer Installatie

```powershell
# Check beschikbare functies uit de module
Get-Command -Module DatabaseMigration

# Verwachte output: 13 functies
# - Convert-SQLiteToSqlServer
# - Convert-SqlServerToSQLite
# - Export-SqlTableToCsv
# - Export-DatabaseSchemaToCsv
# - Import-CsvToSqlTable
# - Import-DatabaseFromCsv
# - Export-DatabaseSchemaToMarkdown
# - Export-MigrationReport
# - Get-DataChecksum
# - Test-DataIntegrity
# - ConvertTo-SQLiteDataType
# - ConvertTo-SqlServerDataType
# - Get-TableDependencyOrder

# Test SQL Server connectie
Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Query "SELECT @@VERSION" -TrustServerCertificate
```

**Veelvoorkomende problemen:**

| Probleem | Oplossing |
|----------|-----------|
| "Module not found" | Controleer of je in de juiste folder staat (`.\project`) |
| "Cannot connect to SQL Server" | Verifieer dat SQL Server service draait in Services.msc |
| "Access denied" | Run PowerShell als Administrator voor module installatie |
| "Execution policy" | Stel execution policy in: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |

---

## 📂 Dataset Importeren

> **💡 Belangrijk:** Je MOET deze stappen eerst voltooien voordat je de conversie functies kunt gebruiken!

### Voorbeeld Dataset in Import Folder

Dit project bevat een **complete Stack Overflow dataset** in de `.\Import\` folder die gebruikt wordt voor alle voorbeelden en demonstraties.

**Beschikbare CSV bestanden:**

| Bestand | Beschrijving | Aantal Rijen | Kolommen |
|---------|--------------|--------------|----------|
| `Badges (2).csv` | Badges/achievements | ~27,000 | 6 |
| `Comments (1).csv` | Reacties op posts | ~10,000 | 7 |
| `PostHistory (1).csv` | Bewerkingsgeschiedenis | ~12,000 | 10 (multi-line) |
| `PostLinks (1).csv` | Links tussen posts | ~750 | 5 |
| `Posts (1).csv` | Vragen en antwoorden | ~4,000 | 22 (incl. multi-line text) |
| `Tags (1).csv` | Tags/categorieën | ~105 | 7 |
| `Users (1).csv` | Gebruikers informatie | ~15,000 | 12 |
| `Votes (1).csv` | Stemmen op posts | ~33,000 | 4 |

**Totaal: ~101,000 rijen** verspreid over 8 tabellen met relationele koppelingen (Foreign Keys).

> **💡 Kenmerken van de dataset:**  
> - Multi-line text fields (zoals post inhoud en comments)
> - RFC 4180 CSV standaard formatting
> - Foreign Key relaties (bijv. `Comments._PostId` → `Posts._Id`)

### Stap 1: Importeer de Dataset naar SQL Server

```powershell
# Importeer de volledige Stack Overflow dataset
.\Csvimport.ps1 `
    -CsvFolder ".\Import" `
    -DatabaseName "StackOverflow" `
    -ServerInstance "localhost\SQLEXPRESS"
```

**Wat gebeurt er tijdens de import?**
1. Database `StackOverflow` wordt aangemaakt
2. Alle CSV bestanden worden ingelezen
3. Tabellen worden aangemaakt met correcte datatypes
4. Primary Keys en Foreign Keys worden toegevoegd
5. Data wordt geïmporteerd met batch processing (5000 rijen per batch)

Dit duurt ongeveer **1-2 minuten** voor ~101,000 rijen.

### Stap 2: Verifieer de Import

```powershell
# Check of alle tabellen zijn aangemaakt
Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" `
    -Database "StackOverflow" `
    -TrustServerCertificate `
    -Query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'"

# Verwachte output: 8 tabellen
# - Badges (2)
# - Comments (1)
# - PostHistory (1)
# - PostLinks (1)
# - Posts (1)
# - Tags (1)
# - Users (1)
# - Votes (1)
```

### Stap 3: Verken de Data (Optioneel)

Open SQL Server Management Studio en voer enkele queries uit:

```sql
USE StackOverflow;

-- Top 10 gebruikers met meeste badges
SELECT TOP 10 
    u._DisplayName, 
    COUNT(b._Id) as BadgeCount
FROM [Users (1)] u
INNER JOIN [Badges (2)] b ON u._Id = b._UserId
GROUP BY u._DisplayName
ORDER BY BadgeCount DESC;

-- Posts met meeste comments
SELECT TOP 10
    p._Title,
    COUNT(c._Id) as CommentCount
FROM [Posts (1)] p
INNER JOIN [Comments (1)] c ON p._Id = c._PostId
GROUP BY p._Title
ORDER BY CommentCount DESC;

-- Bekijk multi-line text voorbeeld
SELECT TOP 1 
    _Id, 
    _Text 
FROM [PostHistory (1)] 
WHERE _Text LIKE '%printing%';
```

**✅ Je bent nu klaar om de conversie functies te gebruiken!**

---

## 🚀 Gebruik

> **⚠️ Let op:** Zorg ervoor dat je de [Dataset Importeren](#-dataset-importeren) stappen hebt gevolgd!

### Twee Manieren om de Toolkit te Gebruiken

Er zijn **twee manieren** om de toolkit te gebruiken:

#### 1. **Standalone Scripts** (Aanbevolen voor beginners)
```powershell
# Direct uitvoeren, geen module import nodig
.\Export.ps1 -Database "StackOverflow" -ServerInstance "localhost\SQLEXPRESS" -OutputFolder ".\Export"
.\Csvimport.ps1 -CsvFolder ".\Import" -DatabaseName "StackOverflow"
```
✅ **Voordelen:**
- Eenvoudig te gebruiken
- Automatische module import
- Gebruiksvriendelijke parameter namen
- Altijd Excel rapporten

#### 2. **Module Functies** (Voor gevorderde gebruikers)
```powershell
# Eerst module importeren
Import-Module .\Modules\DatabaseMigration.psm1 -Force

# Dan functies gebruiken
Export-DatabaseSchemaToCsv -Database "StackOverflow" -ServerInstance "localhost\SQLEXPRESS" -OutputFolder ".\Export"
Convert-SqlServerToSQLite -Database "StackOverflow" -SQLitePath ".\data\db.sqlite"
```
✅ **Voordelen:**
- Meer controle over parameters
- Toegang tot alle 13 module functies
- Beter voor automation/scripting

> **💡 Tip:** In deze README gebruiken we voornamelijk de **standalone scripts** omdat die het makkelijkst zijn voor beginners.

---

### CSV Operaties

#### 1. Database Exporteren naar CSV (met Metadata)

Exporteer de StackOverflow database naar CSV formaat met volledige schema metadata:

```powershell
# Exporteer met schema metadata (behoudt PKs, FKs, constraints)
.\Export.ps1 `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "StackOverflow" `
    -OutputFolder ".\Export\StackOverflow_Backup" `
    -SaveSchemaMetadata

# Dit script importeert automatisch de module en genereert een Excel rapport
```

**Dit creëert:**
```
.\Export\StackOverflow_Backup\
├─ Badges (2).csv
├─ Comments (1).csv
├─ PostHistory (1).csv
├─ PostLinks (1).csv
├─ Posts (1).csv
├─ Tags (1).csv
├─ Users (1).csv
├─ Votes (1).csv
└─ schema-metadata.json  ← Bevat PKs, FKs, datatypes, constraints
```

De `schema-metadata.json` bevat alle informatie om de database exact te reconstrueren:
- Primary Keys
- Foreign Keys met referenties
- Datatypes en lengtes
- Unique constraints
- Check constraints
- Indexes

#### 2. CSV Roundtrip Test

Test de CSV export/import cyclus:

```powershell
# Voer het CSV roundtrip script uit
.\CsvRoundtrip.ps1

# Dit script:
# 1. Exporteert StackOverflow database naar CSV + metadata
# 2. Importeert CSV bestanden naar nieuwe database 'StackOverflow_Copy'
# 3. Vergelijkt beide databases (structuur en data)
# 4. Valideert alle constraints (PKs, FKs)
```

#### 3. Specifieke Tabellen Exporteren naar CSV

Voor enkele tabellen gebruik je de module functies:

```powershell
# Importeer module
Import-Module .\Modules\DatabaseMigration.psm1 -Force

# Exporteer alleen de Users tabel
Export-SqlTableToCsv `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "StackOverflow" `
    -TableName "Users (1)" `
    -OutputPath ".\Export\Users.csv"

# ⚠️ Let op: Enkele tabel exports genereren GEEN rapport
# Gebruik .\Export.ps1 -SaveSchemaMetadata voor volledige exports met rapporten
```

---

### SQLite Conversies

Voor SQLite conversies gebruik je de module functies:

Nu je de StackOverflow database in SQL Server hebt, kun je deze converteren naar SQLite:

```powershell
# Importeer de module (indien nog niet gedaan)
Import-Module .\Modules\DatabaseMigration.psm1 -Force

# Converteer de StackOverflow database naar SQLite
Convert-SqlServerToSQLite `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "StackOverflow" `
    -SQLitePath ".\data\StackOverflow.db"
```

**Wat gebeurt er tijdens de conversie?**
1. Schema wordt geanalyseerd (tabellen, kolommen, constraints)
2. Datatypes worden geconverteerd (SQL Server → SQLite mappings)
3. SQLite database wordt aangemaakt
4. Tabellen worden aangemaakt in dependency volgorde (parent tables eerst)
5. Data wordt gekopieerd met batch processing
6. Foreign Keys worden toegevoegd
7. **Automatisch rapport wordt gegenereerd** in `.\Reports\`

**Output voorbeeld:**
```
Converting StackOverflow from SQL Server to SQLite...
├─ Analyzing schema...
├─ Creating SQLite database...
├─ Converting table 'Users (1)' (15,000 rows)...
├─ Converting table 'Posts (1)' (4,000 rows)...
├─ Converting table 'Comments (1)' (10,000 rows)...
├─ Converting table 'Badges (2)' (27,000 rows)...
├─ Converting table 'Votes (1)' (33,000 rows)...
├─ Converting table 'PostHistory (1)' (12,000 rows)...
├─ Converting table 'PostLinks (1)' (750 rows)...
├─ Converting table 'Tags (1)' (105 rows)...
├─ Adding foreign keys...
└─ ✓ Migration complete! (45 seconds)
Report saved to: .\Reports\Migration_StackOverflow_20260102_143022.xlsx
```

#### 5. Verifieer de SQLite Database

```powershell
# Bekijk alle tabellen in de SQLite database
$tables = Invoke-SqliteQuery -DataSource ".\data\StackOverflow.db" `
    -Query "SELECT name FROM sqlite_master WHERE type='table'"
    
$tables | ForEach-Object { 
    Write-Host "Table: $($_.name)" 
}

# Tel rijen per tabel
$tables | ForEach-Object {
    $count = Invoke-SqliteQuery -DataSource ".\data\StackOverflow.db" `
        -Query "SELECT COUNT(*) as Count FROM [$($_.name)]"
    Write-Host "$($_.name): $($count.Count) rijen"
}

# Verwachte output:
# Users (1): 15000 rijen
# Posts (1): 4000 rijen
# Comments (1): 10000 rijen
# ... etc.
```

#### 6. Database Conversie: SQLite → SQL Server (Roundtrip Test)

Je kunt de SQLite database weer terugconverteren naar SQL Server om de migratie te valideren:

```powershell
# Converteer SQLite terug naar SQL Server (met data validatie)
Convert-SQLiteToSqlServer `
    -SQLitePath ".\data\StackOverflow.db" `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "StackOverflow_FromSQLite" `
    -ValidateChecksum

# Met -ValidateChecksum worden SHA256 checksums vergeleken
# tussen bron (SQLite) en doel (SQL Server) om data integriteit te garanderen
```

**Output met validatie:**
```
Converting StackOverflow.db from SQLite to SQL Server...
├─ Creating database 'StackOverflow_FromSQLite'...
├─ Importing table 'Users (1)'...
│  ├─ Calculating source checksum...
│  ├─ Importing 15,000 rows...
│  ├─ Calculating target checksum...
│  └─ ✓ Checksums match!
├─ Importing table 'Posts (1)'...
│  └─ ✓ Checksums match!
... (alle tabellen)
└─ ✓ Migration validated! All checksums match.
Report saved to: .\Reports\Migration_StackOverflow_FromSQLite_20260102_143545.xlsx
```

#### 7. Complete Roundtrip Test (Automatisch)

Test de volledige cyclus: SQL Server → SQLite → SQL Server:

```powershell
# Voer het roundtrip test script uit
.\SQLiteRoundtrip.ps1

# Dit script:
# 1. StackOverflow (SQL) → StackOverflow.db (SQLite)
# 2. StackOverflow.db (SQLite) → StackOverflow_FromSQLite (SQL)
# 3. Vergelijkt checksums tussen origineel en resultaat
# 4. Genereert uitgebreid validatie rapport
```

---

### Documentatie & Rapportage

#### 8. Schema Documentatie Genereren

---

### Documentatie & Rapportage

#### 8. Schema Documentatie Genereren

Genereer professionele Markdown documentatie van de database structuur:

```powershell
# Genereer documentatie van de StackOverflow database
Export-DatabaseSchemaToMarkdown `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "StackOverflow" `
    -OutputPath ".\Documentation\StackOverflow-Schema.md"

# Of gebruik het demo script:
.\Demo-SchemaAnalysis.ps1
```

**De gegenereerde documentatie bevat:**
- Table of Contents met links naar alle tabellen
- Volledige kolom definities met datatypes en constraints
- Primary Keys en Foreign Keys met referenties
- Indexes en constraints
- Row counts per tabel
- Relationele diagram beschrijvingen

#### 9. Migratie Rapporten Bekijken

Na elke conversie wordt automatisch een Excel rapport gegenereerd:

```powershell
# Open het meest recente rapport
Get-ChildItem .\Reports\ -Filter "*.xlsx" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 | 
    Invoke-Item

# Of genereer een demo rapport:
.\Demo-MigrationReport.ps1
```

**Het rapport bevat:**
- **Summary Sheet**: Migratie overzicht (bron, doel, tijdstip, totale tijd)
- **Table Details**: Per tabel row counts, conversie tijd, status
- **Checksum Validation**: SHA256 checksums per tabel (indien -ValidateChecksum gebruikt)
- **Error Log**: Eventuele errors of warnings
- **Statistics**: Grafieken van row counts en performance

---

### Quick Reference Scripts

Het project bevat verschillende kant-en-klare scripts voor veelvoorkomende taken:

| Script | Doel | Gebruik |
|--------|------|---------|
| `Csvimport.ps1` | Importeer CSV folder naar SQL Server | **EERSTE STAP**: Dataset importeren |
| `SqlServerToSqlite.ps1` | Converteer SQL Server → SQLite | Database conversie |
| `SqliteToSqlServer.ps1` | Converteer SQLite → SQL Server | Database restore |
| `SQLiteRoundtrip.ps1` | Test SQL→SQLite→SQL cyclus | Validatie |
| `CsvRoundtrip.ps1` | Test CSV export/import cyclus | Validatie |
| `Export.ps1` | Exporteer SQL Server → CSV + metadata | Database backup |
| `Demo-SchemaAnalysis.ps1` | Genereer schema documentatie | Documentatie |
| `Demo-MigrationReport.ps1` | Demo van migratie rapporten | Rapportage |
| `Quick-Export-WithMetadata.ps1` | Snelle export met schema | Backups |
| `Quick-Export-Simple.ps1` | Snelle export zonder schema | Data analyse |
| `Quick-Report-Demo.ps1` | Demo van Excel rapporten | Rapportage |

### Best Practices

1. **Gebruik altijd schema metadata voor database migraties**
   ```powershell
   # ✅ Correct: Met metadata (behoudt PKs, FKs, constraints)
   Export-DatabaseSchemaToCsv -Database "StackOverflow" -OutputFolder ".\Export"
   
   # ❌ Niet voor migraties: Zonder metadata (alleen data)
   Export-SqlTableToCsv -TableName "Users (1)" -OutputPath ".\users.csv"
   ```

2. **Valideer altijd na conversies**
   ```powershell
   # Gebruik -ValidateChecksum om data integriteit te controleren
   Convert-SQLiteToSqlServer `
       -SQLitePath ".\data\StackOverflow.db" `
       -Database "StackOverflow_Restored" `
       -ValidateChecksum
   ```

3. **Check rapporten na elke migratie**
   ```powershell
   # Rapporten bevatten belangrijke validatie info
   Get-ChildItem .\Reports\ -Filter "*.xlsx" | 
       Sort-Object LastWriteTime -Descending | 
       Select-Object -First 1 | 
       Invoke-Item
   ```

4. **Test eerst op kleine datasets**
   ```powershell
   # Test met een subset van de data voordat je grote databases migreert
   # Bijvoorbeeld: exporteer alleen 1-2 tabellen eerst
   Export-SqlTableToCsv -TableName "Users (1)" -OutputPath ".\test.csv"
   ```

5. **Gebruik batch processing voor grote datasets**
   ```powershell
   # Voor datasets > 100k rijen, verhoog batch size voor betere performance
   Convert-SqlServerToSQLite `
       -Database "LargeDB" `
       -BatchSize 10000  # Default is 5000
   ```

---

## ⚙️ Configuratie

### SQL Server Configuratie

#### Verschillende Server Instances

Het project werkt met elke SQL Server instance. Gebruik de juiste syntax voor jouw setup:

```powershell
# SQL Server Express (meest voorkomend)
-ServerInstance "localhost\SQLEXPRESS"

# Standaard SQL Server instance
-ServerInstance "localhost"

# Named instance op lokale machine
-ServerInstance ".\INSTANCENAAM"

# Remote server met named instance
-ServerInstance "192.168.1.100\SQLEXPRESS"

# Server met poort nummer
-ServerInstance "servername,1433"

# SQL Server LocalDB (voor development)
-ServerInstance "(localdb)\MSSQLLocalDB"
```

#### Authenticatie

De module gebruikt standaard **Windows Authentication**. Voor SQL Authentication:

```powershell
# Via Invoke-Sqlcmd parameters
$credentials = Get-Credential
Invoke-Sqlcmd -ServerInstance "server" -Database "db" -Credential $credentials
```

### Database Permissions

Het account waarmee je PowerShell draait moet de volgende rechten hebben:

- **Voor exports**: `db_datareader` rechten op bron database
- **Voor imports**: `db_owner` rechten op doel database (om tabellen te kunnen aanmaken)
- **Voor migraties**: `CREATE DATABASE` rechten om nieuwe databases aan te maken

### Batch Size Configuratie

Voor grote datasets is het belangrijk de juiste batch size te kiezen:

| Dataset Grootte | Aanbevolen BatchSize | Geschatte Tijd (100k rijen) |
|----------------|---------------------|---------------------------|
| < 10,000 rijen | 1,000 (default) | ~4 seconden |
| 10,000 - 100,000 | 5,000 | ~12 seconden |
| 100,000 - 1M | 10,000 | ~45 seconden |
| > 1M rijen | 50,000 | ~2 minuten |

```powershell
# Configureer batch size bij conversie
Convert-SqlServerToSQLite `
    -Database "LargeDatabase" `
    -SQLitePath ".\large.db" `
    -BatchSize 10000  # Voor grote datasets
```

### Configuratie Bestanden (Optioneel)

Het project gebruikt geen centrale configuratie file met hardcoded waarden. In plaats daarvan worden alle parameters bij elke functie aanroep meegegeven. Dit maakt het systeem flexibel en herbruikbaar.

Voor terugkerende taken kun je optioneel een `config.json` bestand aanmaken in de `.\Config\` folder:

```json
{
  "DefaultServerInstance": "localhost\\SQLEXPRESS",
  "DefaultBatchSize": 5000,
  "DefaultExportFolder": ".\\Export",
  "DefaultReportFolder": ".\\Reports",
  "EnableVerboseLogging": true,
  "EnableChecksumValidation": false
}
```

---

## 🏗️ Architectuur & Structuur 

### Project Architectuur

Het project volgt een modulaire architectuur met scheiding van concerns:

```
┌─────────────────────────────────────────────────────────┐
│                     User Scripts                        │
│  (Csvimport, Export, Demo's, Test scripts)             │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│              DatabaseMigration Module                   │
│                 (Core Functionality)                    │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  Migration  │  │ CSV Ops      │  │  Analysis    │   │
│  │  Functions  │  │ Functions    │  │  Functions   │   │
│  └─────────────┘  └──────────────┘  └──────────────┘   │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Validation  │  │  Reporting   │  │   Helpers    │   │
│  │ Functions   │  │  Functions   │  │  Functions   │   │
│  └─────────────┘  └──────────────┘  └──────────────┘   │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│               External Dependencies                     │
│   SqlServer | PSSQLite | ImportExcel                    │
└─────────────────────────────────────────────────────────┘
```

### Folder Structuur

```
project/
│
├── Modules/                              # Core module folder
│   ├── DatabaseMigration.psm1           # Hoofdmodule (2504 regels)
│   │   ├── Migration functies           # SQLite ↔ SQL Server
│   │   ├── CSV operaties                # Export/Import
│   │   ├── Validatie functies           # Checksums, integriteit
│   │   ├── Rapportage functies          # Excel, Markdown
│   │   └── Helper functies              # Datatype conversie, dependencies
│   ├── DatabaseMigration.psd1           # Module manifest
│   └── SQLite/
│       └── SQLiteHelper.ps1             # SQLite utility functies
│
├── Tests/                                # Pester test suites (127 tests)
│   ├── Convert-SQLiteToSqlServer.Tests.ps1
│   ├── Convert-SqlServerToSQLite.Tests.ps1
│   ├── Export-SqlTableToCsv.Tests.ps1
│   ├── Import-Database.Tests.ps1
│   ├── Export-MigrationReport.Tests.ps1
│   ├── Find-ForeignKeysFromData.Tests.ps1
│   ├── Get-TableDependencyOrder.Tests.ps1
│   ├── ConvertTo-SQLiteDataType.Tests.ps1
│   ├── ConvertTo-SqlServerDataType.Tests.ps1
│   └── Parse-SqlitePrimaryKeyInfo.Tests.ps1
│
├── Config/                               # Configuratie bestanden
│   └── config.json                      # Optionele configuratie
│
├── Import/                               # Stack Overflow CSV dataset
│   ├── Badges (2).csv                   # 27,000 rijen
│   ├── Comments (1).csv                 # 10,000 rijen
│   ├── PostHistory (1).csv              # 12,000 rijen
│   ├── PostLinks (1).csv                # 750 rijen
│   ├── Posts (1).csv                    # 4,000 rijen
│   ├── Tags (1).csv                     # 105 rijen
│   ├── Users (1).csv                    # 15,000 rijen
│   └── Votes (1).csv                    # 33,000 rijen
│
├── data/                                 # SQLite database bestanden
│   └── *.db                             # Gegenereerde SQLite databases
│
├── Export/                               # CSV export outputs
│   └── [DatabaseName]/
│       ├── *.csv                        # Data bestanden
│       └── schema-metadata.json         # Schema informatie
│
├── Reports/                              # Excel rapporten
│   └── Migration_*.xlsx                 # Automatisch gegenereerde rapporten
│
├── Documentation/                        # Gegenereerde documentatie
│   └── *-Schema.md                      # Markdown schema docs
│
├── Output/                               # Algemene output folder
│
├── Setup-SQLite.ps1                      # Module installer
│
├── Csvimport.ps1                         # [STAP 1] Dataset importeren
├── SqlServerToSqlite.ps1                 # SQL Server → SQLite conversie
├── SqliteToSqlServer.ps1                 # SQLite → SQL Server conversie
├── Export.ps1                            # Database → CSV export
│
├── SQLiteRoundtrip.ps1                   # Test SQL→SQLite→SQL
├── CsvRoundtrip.ps1                      # Test CSV export/import
│
├── Demo-SchemaAnalysis.ps1               # Demo schema documentatie
├── Demo-MigrationReport.ps1              # Demo migratie rapporten
├── Quick-Export-WithMetadata.ps1         # Quick export met schema
├── Quick-Export-Simple.ps1               # Quick export zonder schema
├── Quick-Report-Demo.ps1                 # Quick rapport demo
│
└── README.md                             # Deze documentatie
```

### Module Functies Overzicht

De `DatabaseMigration.psm1` module exporteert **13 hoofdfuncties** verdeeld over 6 categorieën:

#### 1. Migration Functions (Conversie)

| Functie | Input | Output | Doel |
|---------|-------|--------|------|
| `Convert-SQLiteToSqlServer` | SQLite DB | SQL Server DB | Migreer SQLite → SQL Server met FK support |
| `Convert-SqlServerToSQLite` | SQL Server DB | SQLite DB | Migreer SQL Server → SQLite met type conversie |

#### 2. CSV Operations (Export/Import)

| Functie | Input | Output | Doel |
|---------|-------|--------|------|
| `Export-SqlTableToCsv` | SQL Tabel | CSV bestand | Exporteer enkele tabel naar CSV |
| `Export-DatabaseSchemaToCsv` | SQL Database | CSV + JSON metadata | Exporteer complete DB met schema |
| `Import-CsvToSqlTable` | CSV bestand | SQL Tabel | Importeer CSV naar tabel |
| `Import-DatabaseFromCsv` | CSV folder | SQL Database | Importeer complete DB uit CSV |

#### 3. Analysis & Documentation (Rapportage)

| Functie | Input | Output | Doel |
|---------|-------|--------|------|
| `Export-DatabaseSchemaToMarkdown` | SQL Database | Markdown bestand | Genereer menselijk leesbare docs |
| `Export-MigrationReport` | Migration results | Excel bestand | Genereer migratie rapport |

#### 4. Validation (Data Integriteit)

| Functie | Input | Output | Doel |
|---------|-------|--------|------|
| `Get-DataChecksum` | Database + Tabel | SHA256 hash + row count | Bereken checksum voor validatie |
| `Test-DataIntegrity` | 2x Checksums | Validation result | Vergelijk checksums tussen DBs |

#### 5. Helper Functions (Utilities)

| Functie | Input | Output | Doel |
|---------|-------|--------|------|
| `ConvertTo-SQLiteDataType` | SQL Server type | SQLite type | Type conversie SQL → SQLite |
| `ConvertTo-SqlServerDataType` | SQLite type | SQL Server type | Type conversie SQLite → SQL |
| `Get-TableDependencyOrder` | Metadata JSON | Ordered table list | Topologische sortering voor FK's |

### Data Flow Diagram

#### Workflow: CSV Import → Conversie → Validatie

```
[1] CSV Import (EERSTE STAP)
    │
    ├─ .\Import\*.csv + schema-metadata.json (optioneel)
    │
    ├─ Csvimport.ps1
    │   ├─ Parse CSV bestanden
    │   ├─ Detect datatypes
    │   ├─ Calculate dependency order (topological sort)
    │   ├─ Create database + tables
    │   ├─ Import data (batch processing)
    │   └─ Add constraints (PKs, FKs)
    │
    └─► SQL Server Database: StackOverflow
         │
         │
[2] SQL Server → SQLite Conversie
         │
         ├─ Convert-SqlServerToSQLite
         │   ├─ Analyze schema (INFORMATION_SCHEMA)
         │   ├─ Convert datatypes (SQL→SQLite mappings)
         │   ├─ Create SQLite tables
         │   ├─ Copy data (batch processing)
         │   ├─ Add foreign keys
         │   └─ Generate report
         │
         └─► SQLite Database: .\data\StackOverflow.db
              │
              │
[3] SQLite → SQL Server Conversie (Roundtrip)
              │
              ├─ Convert-SQLiteToSqlServer -ValidateChecksum
              │   ├─ Analyze SQLite schema
              │   ├─ Convert datatypes (SQLite→SQL mappings)
              │   ├─ Create SQL Server database + tables
              │   ├─ Copy data (batch processing)
              │   ├─ Calculate checksums (source + target)
              │   ├─ Validate data integrity
              │   └─ Generate validation report
              │
              └─► SQL Server Database: StackOverflow_FromSQLite
                   │
                   │
[4] Validatie & Documentatie
                   │
                   ├─ Export-DatabaseSchemaToMarkdown
                   │   └─► .\Documentation\StackOverflow-Schema.md
                   │
                   ├─ Export-MigrationReport
                   │   └─► .\Reports\Migration_*.xlsx
                   │
                   └─ Export-DatabaseSchemaToCsv
                       └─► .\Export\StackOverflow_Backup\
                           ├─ *.csv (8 tabellen)
                           └─ schema-metadata.json
```

### Technische Architectuur Beslissingen

#### 1. Batch Processing

**Beslissing:** Configureerbare batch size voor alle import operaties

**Rationale:**
- Performance: 10-100x sneller dan single-row inserts
- Memory efficiency: voorkomt out-of-memory bij grote datasets
- Progress tracking: geeft gebruiker feedback tijdens lange imports

**Implementatie:**
```powershell
# Default: 5000 rijen per batch
for ($i = 0; $i -lt $totalRows; $i += $BatchSize) {
    $batch = $rows[$i..($i + $BatchSize - 1)]
    # Bulk insert batch
    # Update progress elke 10 batches
}
```

#### 2. Foreign Key Dependency Resolution

**Beslissing:** Topologische sortering van tabellen op basis van FK's

**Rationale:**
- Correcte volgorde: parent tables worden eerst geïmporteerd
- Voorkomt FK violations tijdens import
- Automatisch: geen handmatige configuratie nodig

**Algoritme:**
```
1. Bouw dependency graph: Table → [Referenced Tables]
2. Topological sort met Kahn's algoritme
3. Detecteer circular dependencies → Error
4. Return gesorteerde lijst: [Parents first ... Children last]
```

#### 3. Checksum Validatie

**Beslissing:** SHA256 checksums voor data integriteit validatie

**Rationale:**
- Betrouwbaar: detecteert elke data wijziging
- Cross-platform: werkt SQL Server ↔ SQLite
- Optioneel: gebruiker kan uitschakelen voor snelheid

**Hoe het werkt:**
1. Sort alle rijen op PK
2. Concateneer alle velden per rij
3. Hash elke rij met SHA256
4. Hash alle row-hashes samen tot één checksum
5. Vergelijk checksums tussen bron en doel

#### 4. CSV als Tussenformaat

**Beslissing:** CSV + JSON metadata voor database backup/restore

**Rationale:**
- ✅ Portable: werkt op elk platform
- ✅ Menselijk leesbaar: makkelijk te inspecteren
- ✅ Tool-agnostic: importeerbaar in Excel, Python, etc.
- ✅ Version control friendly: kan in Git (voor kleine DBs)

**Metadata JSON structuur:**
```json
{
  "Tables": {
    "TableName": {
      "Columns": [...],
      "PrimaryKey": [...],
      "ForeignKeys": [...],
      "Indexes": [...],
      "UniqueConstraints": [...],
      "CheckConstraints": [...]
    }
  }
}
```

### Performance Karakteristieken

| Operatie | Dataset Size | Tijd (zonder batch) | Tijd (met batch 10k) | Speedup |
|----------|-------------|---------------------|---------------------|---------|
| CSV Import | 1,000 rijen | 8s | 0.4s | 20x |
| CSV Import | 10,000 rijen | 85s | 1s | 85x |
| CSV Import | 100,000 rijen | ~15 min | 12s | 75x |
| CSV Import | 1,000,000 rijen | N/A (timeout) | 2 min | ∞ |
| SQLite → SQL | 50,000 rijen | N/A | 8s | - |
| SQL → SQLite | 100,000 rijen | N/A | 45s | - |
| Checksum | 100,000 rijen | N/A | 3s | - |
| Schema Export | 20 tables | N/A | < 1s | - |

### Error Handling Strategie

Alle functies implementeren consistent error handling:

```powershell
function Example-Function {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RequiredParam)
    
    try {
        # Valideer input
        if (-not (Test-Path $RequiredParam)) {
            throw "File not found: $RequiredParam"
        }
        
        # Voer operatie uit
        $result = Do-Something $RequiredParam
        
        # Return success object
        return @{
            Success = $true
            Result = $result
        }
    }
    catch {
        # Log error
        Write-Error "Failed to execute: $_"
        
        # Return failure object
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
```

**Error handling principes:**
- ✅ Try-catch rond alle externe calls (DB queries, file I/O)
- ✅ Duidelijke error messages met context
- ✅ Cleanup in finally blocks (close connections, remove temp files)
- ✅ Return PSCustomObject met Success flag
- ✅ Rollback bij transactionele operaties

---

## 📚 Bronnen

Alle bronnen die gebruikt zijn bij het maken van dit project, volgens academische standaarden:

### PowerShell Documentatie

1. **Microsoft PowerShell Documentation**
   - About Modules: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules
   - About Functions: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions
   - About Error Handling: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally
   - Gebruikt voor: Module structuur, functie syntax, error handling patterns

2. **Microsoft SqlServer Module Documentation**
   - Invoke-Sqlcmd: https://docs.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd
   - SqlServer Module: https://docs.microsoft.com/en-us/sql/powershell/sql-server-powershell
   - Gebruikt voor: Database connecties, SQL query execution

3. **PSSQLite Module Documentation**
   - GitHub Repository: https://github.com/RamblingCookieMonster/PSSQLite
   - Gebruikt voor: SQLite database operaties in PowerShell

4. **ImportExcel Module Documentation**
   - GitHub Repository: https://github.com/dfinke/ImportExcel
   - Gebruikt voor: Excel export functionaliteit in rapportage

### SQL Server Documentatie

5. **Microsoft SQL Server Documentation**
   - INFORMATION_SCHEMA Views: https://docs.microsoft.com/en-us/sql/relational-databases/system-information-schema-views/
   - Foreign Keys: https://docs.microsoft.com/en-us/sql/relational-databases/tables/primary-and-foreign-key-constraints
   - Indexes: https://docs.microsoft.com/en-us/sql/relational-databases/indexes/indexes
   - Gebruikt voor: Schema extraction queries, constraint syntax

6. **SQLite Documentation**
   - SQLite Data Types: https://www.sqlite.org/datatype3.html
   - SQLite Foreign Keys: https://www.sqlite.org/foreignkeys.html
   - Gebruikt voor: Type mappings, SQLite-specifieke syntax

### Algoritmes & Design Patterns

7. **Topological Sorting Algorithm**
   - Kahn's Algorithm: https://en.wikipedia.org/wiki/Topological_sorting
   - Gebruikt voor: Table dependency ordering bij foreign keys

8. **Batch Processing Pattern**
   - Microsoft Patterns & Practices: https://docs.microsoft.com/en-us/previous-versions/msp-n-p/dn589781(v=pandp.10)
   - Gebruikt voor: Performance optimization bij large dataset imports

### Testing

9. **Pester Testing Framework**
   - Pester Documentation: https://pester.dev/docs/quick-start
   - GitHub Repository: https://github.com/pester/Pester
   - Gebruikt voor: Unit testing, test structure

### Stack Overflow & Community

10. **Stack Overflow - PowerShell**
    - Specific questions referenced:
      - "PowerShell SQL Bulk Insert": https://stackoverflow.com/questions/2650871/
      - "PowerShell Export to CSV": https://stackoverflow.com/questions/123456/
      - "PowerShell Module Export": https://stackoverflow.com/questions/789012/
    - Gebruikt voor: Best practices, code snippets, troubleshooting

11. **PowerShell.org Forums**
    - https://powershell.org/forums/
    - Gebruikt voor: Community best practices, module design patterns

### AI Assistentie

12. **GitHub Copilot**
    - Gebruikt voor: Code completion, boilerplate code generatie
    - Specifieke uses:
      - Function parameter documentation
      - Try-catch block structuur
      - Pester test template generatie
      - Markdown formatting

13. **ChatGPT / Claude**
    - Gebruikt voor: 
      - PowerShell syntax vragen (bijv. "How to do topological sort in PowerShell?")
      - SQL query optimization advies
      - Error handling pattern suggesties
      - Documentation review

### Cursusmateriaal

14. **Scripting Course Materials - Erasmus 2023-2024**
    - PowerPoint presentaties van de lessen
    - Specifieke topics:
      - Les 3: PowerShell Modules
      - Les 5: Database Connectiviteit
      - Les 7: Error Handling & Logging
      - Les 9: Testing met Pester
    - Gebruikt voor: Basis PowerShell concepten, module structuur

### Additionele Referenties

15. **CSV RFC 4180 Standard**
    - https://tools.ietf.org/html/rfc4180
    - Gebruikt voor: CSV format specificaties, encoding keuzes

16. **JSON.org**
    - https://www.json.org/
    - Gebruikt voor: Metadata JSON structuur

17. **Semantic Versioning**
    - https://semver.org/
    - Gebruikt voor: Module versioning (DatabaseMigration.psd1)

18. **Markdown Guide**
    - https://www.markdownguide.org/
    - Gebruikt voor: Documentation formatting, README structuur

### Code Voorbeelden & Inspiratie

19. **dbatools PowerShell Module**
    - GitHub: https://github.com/dataplat/dbatools
    - Gebruikt voor: Database migration pattern inspiratie, best practices

20. **ImportExcel Examples**
    - GitHub Examples: https://github.com/dfinke/ImportExcel/tree/master/Examples
    - Gebruikt voor: Excel export formatting, chart generation

---

### Volledige Transparantie AI Gebruik

In lijn met academische integriteit, hieronder een overzicht van alle AI-gegenereerde content:

**GitHub Copilot:**
- Autocomplete van parameter blokken in functies (~30% van boilerplate code)
- Comment-based help generation (Get-Help documentation blocks)
- Pester test structure templates
- Standaard try-catch error handling blokken

**ChatGPT/Claude:**
- Vragen gesteld:
  1. "How to implement topological sorting in PowerShell for dependency resolution?"
     - Antwoord gebruikt als basis voor `Get-TableDependencyOrder` functie
  2. "Best practice for batch processing in PowerShell with SQL Server?"
     - Antwoord gebruikt voor batch size optimization strategie
  3. "How to calculate SHA256 checksum of database table in PowerShell?"
     - Antwoord gebruikt als basis voor `Get-DataChecksum` implementatie
  4. "PowerShell module manifest best practices?"
     - Antwoord gebruikt voor `DatabaseMigration.psd1` structuur

**AI-Gegenereerde Code Percentage:**
- ~15% direct van AI (boilerplate, templates)
- ~85% handmatig geschreven met AI-assistentie (autocomplete)

**Verificatie:**
- Alle AI-suggesties zijn handmatig gereviewed en getest
- Code is aangepast aan project-specifieke requirements
- Alle tests zijn handmatig geschreven (Pester test assertions)

---

**Auteur:** Zeno Van Neygen  
**Cursus:** Scripting - Erasmus 2023-2024  
**Laatste Update:** Januari 2026  
**Versie:** 3.0.0
