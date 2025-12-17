# CSV Export/Import Modes

Er zijn nu **twee modi** voor het werken met CSV exports:

## 1️⃣ Met Schema Metadata (Aanbevolen voor database migraties)

### Export:
```powershell
.\Export.ps1 -Database "SalesDB" -OutputFolder ".\Export\SalesDB" -SaveSchemaMetadata
```
Of gebruik de snelkoppeling:
```powershell
.\Quick-Export-WithMetadata.ps1
```

**Dit bewaart:**
- ✅ Primary Keys
- ✅ Foreign Keys  
- ✅ Data types
- ✅ NULL constraints
- ✅ Alle relationele integriteit

**Output:**
- CSV bestanden met data
- `schema-metadata.json` met complete schema informatie

### Import:
```powershell
.\Csvimport.ps1 -CsvFolder ".\Export\SalesDB" -DatabaseName "SalesDB_Restored"
```

**Het script detecteert automatisch** de `schema-metadata.json` en gebruikt deze om:
- Tabellen te creëren met exacte data types
- Primary Keys toe te voegen
- Foreign Keys toe te voegen
- Juiste volgorde te bepalen (parent tables eerst)

---

## 2️⃣ Zonder Schema Metadata (Voor data analyse)

### Export:
```powershell
.\Export.ps1 -Database "SalesDB" -OutputFolder ".\Export\SalesDB"
```
Of gebruik de snelkoppeling:
```powershell
.\Quick-Export-Simple.ps1
```

**Dit exporteert:**
- Alleen CSV bestanden met data
- Geen schema informatie

**Gebruik voor:**
- Data analyse in Excel
- Import in andere tools
- Simpele data backups

### Import met Auto-detect:
```powershell
.\Csvimport.ps1 -CsvFolder ".\Export\SalesDB" -DatabaseName "NewDB" -AutoDetectRelations
```

**Auto-detect probeert te raden:**
- Primary Keys (kolommen die eindigen op "ID")
- Foreign Keys (matching ID kolommen tussen tabellen)
- ⚠️ Niet 100% betrouwbaar

---

## 🎯 Welke modus gebruiken?

| Scenario | Aanbevolen Modus |
|----------|------------------|
| Database migratie | **Met Metadata** |
| Backup & Restore | **Met Metadata** |
| Development/Testing | **Met Metadata** |
| Data analyse in Excel | Zonder Metadata |
| Quick data export | Zonder Metadata |

---

## 📋 Voorbeelden

### Scenario 1: Volledige database migratie
```powershell
# Export van productie database
.\Export.ps1 -Database "ProductionDB" -OutputFolder ".\Backup\Production" -SaveSchemaMetadata

# Import naar test database
.\Csvimport.ps1 -CsvFolder ".\Backup\Production" -DatabaseName "TestDB"
```

### Scenario 2: Data analyse
```powershell
# Simpele export
.\Export.ps1 -Database "SalesDB" -OutputFolder ".\Analysis"

# Open CSV bestanden in Excel voor analyse
```

### Scenario 3: Roundtrip test
```powershell
# Test complete cyclus
.\Test-CsvRoundtrip.ps1
```

---

## 🔍 Metadata Bestand Structuur

`schema-metadata.json` bevat:
```json
{
  "DatabaseName": "SalesDB",
  "ExportDate": "2025-12-16 15:30:00",
  "Tables": {
    "Customers": {
      "Columns": [...],
      "PrimaryKey": ["CustomerID"],
      "ForeignKeys": []
    },
    "Orders": {
      "Columns": [...],
      "PrimaryKey": ["OrderID"],
      "ForeignKeys": [
        {
          "ConstraintName": "FK_Orders_Customers",
          "Column": "CustomerID",
          "ReferencedTable": "Customers",
          "ReferencedColumn": "CustomerID"
        }
      ]
    }
  }
}
```

---

## ⚠️ Belangrijk

- **Altijd gebruik `-SaveSchemaMetadata`** als je de database exact wilt repliceren
- Zonder metadata gaan **alle constraints verloren**
- Auto-detect is een best-effort poging en niet 100% accuraat
- Metadata modus heeft **geen hardcoded waarden**, alles komt uit de database schema

---

## 🚀 Module Functies

Direct vanuit de module gebruiken:

```powershell
Import-Module ".\Modules\DatabaseMigration.psm1"

# Export met metadata
Export-DatabaseSchemaToCsv `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "SalesDB" `
    -OutputFolder ".\Export\SalesDB"

# Import (detecteert automatisch metadata)
Import-DatabaseFromCsv `
    -ServerInstance "localhost\SQLEXPRESS" `
    -Database "SalesDB_New" `
    -CsvFolder ".\Export\SalesDB"
```
