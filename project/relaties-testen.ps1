[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$Database
)

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      Database Integrity Tests                  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Test 1: Check alle tabellen en row counts
Write-Host "`n[TEST 1] Table Contents" -ForegroundColor Yellow
$tables = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT 
    t.name AS TableName,
    SUM(p.rows) AS [RowCount]
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
GROUP BY t.name
ORDER BY t.name
"@
$tables | Format-Table -AutoSize

# Test 2: Check Foreign Keys
Write-Host "`n[TEST 2] Foreign Key Constraints" -ForegroundColor Yellow
$fks = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT 
    fk.name AS ConstraintName,
    tp.name AS ParentTable,
    cp.name AS ParentColumn,
    tr.name AS ReferencedTable,
    cr.name AS ReferencedColumn
FROM sys.foreign_keys fk
INNER JOIN sys.tables tp ON fk.parent_object_id = tp.object_id
INNER JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns cp ON fkc.parent_object_id = cp.object_id AND fkc.parent_column_id = cp.column_id
INNER JOIN sys.columns cr ON fkc.referenced_object_id = cr.object_id AND fkc.referenced_column_id = cr.column_id
ORDER BY tp.name, fk.name
"@

if ($fks) {
    $fks | Format-Table -AutoSize
    Write-Host "✓ Foreign keys found: $($fks.Count)" -ForegroundColor Green
} else {
    Write-Host "⚠ No foreign keys found!" -ForegroundColor Red
}

# Test 3: Test referential integrity
Write-Host "`n[TEST 3] Referential Integrity Tests" -ForegroundColor Yellow

# Test Orders -> Customers
Write-Host "Testing Orders -> Customers..." -ForegroundColor Gray
$orphans = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT COUNT(*) AS OrphanCount
FROM Orders o
LEFT JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL
"@
if ($orphans.OrphanCount -eq 0) {
    Write-Host "  ✓ All Orders have valid Customers" -ForegroundColor Green
} else {
    Write-Host "  ✗ Found $($orphans.OrphanCount) orphaned Orders!" -ForegroundColor Red
}

# Test OrderDetails -> Orders
Write-Host "Testing OrderDetails -> Orders..." -ForegroundColor Gray
$orphans = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT COUNT(*) AS OrphanCount
FROM OrderDetails od
LEFT JOIN Orders o ON od.OrderID = o.OrderID
WHERE o.OrderID IS NULL
"@
if ($orphans.OrphanCount -eq 0) {
    Write-Host "  ✓ All OrderDetails have valid Orders" -ForegroundColor Green
} else {
    Write-Host "  ✗ Found $($orphans.OrphanCount) orphaned OrderDetails!" -ForegroundColor Red
}

# Test OrderDetails -> Products
Write-Host "Testing OrderDetails -> Products..." -ForegroundColor Gray
$orphans = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT COUNT(*) AS OrphanCount
FROM OrderDetails od
LEFT JOIN Products p ON od.ProductID = p.ProductID
WHERE p.ProductID IS NULL
"@
if ($orphans.OrphanCount -eq 0) {
    Write-Host "  ✓ All OrderDetails have valid Products" -ForegroundColor Green
} else {
    Write-Host "  ✗ Found $($orphans.OrphanCount) orphaned OrderDetails!" -ForegroundColor Red
}

# Test Reviews -> Products
Write-Host "Testing Reviews -> Products..." -ForegroundColor Gray
$orphans = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT COUNT(*) AS OrphanCount
FROM Reviews r
LEFT JOIN Products p ON r.ProductID = p.ProductID
WHERE p.ProductID IS NULL
"@
if ($orphans.OrphanCount -eq 0) {
    Write-Host "  ✓ All Reviews have valid Products" -ForegroundColor Green
} else {
    Write-Host "  ✗ Found $($orphans.OrphanCount) orphaned Reviews!" -ForegroundColor Red
}

# Test Reviews -> Customers
Write-Host "Testing Reviews -> Customers..." -ForegroundColor Gray
$orphans = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT COUNT(*) AS OrphanCount
FROM Reviews r
LEFT JOIN Customers c ON r.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL
"@
if ($orphans.OrphanCount -eq 0) {
    Write-Host "  ✓ All Reviews have valid Customers" -ForegroundColor Green
} else {
    Write-Host "  ✗ Found $($orphans.OrphanCount) orphaned Reviews!" -ForegroundColor Red
}

# Test 4: Sample Join Query
Write-Host "`n[TEST 4] Sample Join Query" -ForegroundColor Yellow

# Eerst: check welke kolommen er zijn
Write-Host "Checking column names in tables..." -ForegroundColor Gray
$columns = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('Customers', 'Orders', 'OrderDetails', 'Products')
ORDER BY TABLE_NAME, ORDINAL_POSITION
"@
$columns | Format-Table -AutoSize

Write-Host "`nGetting orders with customer and product details..." -ForegroundColor Gray
$sampleData = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -TrustServerCertificate -Query @"
SELECT TOP 5
    o.OrderID,
    c.CustomerID,
    c.Email,
    o.OrderDate,
    p.ProductName,
    od.Quantity,
    od.UnitPrice
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN Products p ON od.ProductID = p.ProductID
ORDER BY o.OrderDate DESC
"@
$sampleData | Format-Table -AutoSize

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Tests Complete!                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan