# Database Schema Documentation

**Database:** SalesDB_Restored
**Server:** localhost\SQLEXPRESS
**Generated:** 2025-12-30 12:32:06

---

## Table of Contents

- [Customers](#customers)
- [OrderDetails](#orderdetails)
- [Orders](#orders)
- [Products](#products)
- [Reviews](#reviews)

---

## Customers

**Row Count:** 5
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| Email | nvarchar(50) | ✓ |  |
| CreatedDate | nvarchar(50) | ✓ |  |
| City | nvarchar(50) | ✓ |  |
| LastName | nvarchar(50) | ✓ |  |
| Country | nvarchar(50) | ✓ |  |
| CustomerID | int() | ✗ |  |
| Phone | nvarchar(50) | ✓ |  |
| FirstName | nvarchar(50) | ✓ |  |

### Primary Key

- **Columns:** CustomerID

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Customers | CLUSTERED | ✓ | CustomerID |

---

## OrderDetails

**Row Count:** 8
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| OrderID | int() | ✓ |  |
| UnitPrice | decimal() | ✓ |  |
| ProductID | int() | ✓ |  |
| Discount | decimal() | ✓ |  |
| Quantity | int() | ✓ |  |
| OrderDetailID | int() | ✗ |  |

### Primary Key

- **Columns:** OrderDetailID

### Foreign Keys

| Constraint | Column | References |
|------------|--------|------------|
| FK_OrderDetails_Orders | OrderID | Orders(OrderID) |
| FK_OrderDetails_Products | ProductID | Products(ProductID) |

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_OrderDetails | CLUSTERED | ✓ | OrderDetailID |

---

## Orders

**Row Count:** 6
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| OrderID | int() | ✗ |  |
| TotalAmount | decimal() | ✓ |  |
| OrderDate | nvarchar(50) | ✓ |  |
| Status | nvarchar(50) | ✓ |  |
| ShippingAddress | nvarchar(50) | ✓ |  |
| CustomerID | int() | ✓ |  |

### Primary Key

- **Columns:** OrderID

### Foreign Keys

| Constraint | Column | References |
|------------|--------|------------|
| FK_Orders_Customers | CustomerID | Customers(CustomerID) |

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Orders | CLUSTERED | ✓ | OrderID |

---

## Products

**Row Count:** 8
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| Stock | int() | ✓ |  |
| Price | decimal() | ✓ |  |
| CreatedDate | nvarchar(50) | ✓ |  |
| ProductID | int() | ✗ |  |
| ProductName | nvarchar(50) | ✓ |  |
| Category | nvarchar(50) | ✓ |  |

### Primary Key

- **Columns:** ProductID

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Products | CLUSTERED | ✓ | ProductID |

---

## Reviews

**Row Count:** 6
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| Rating | int() | ✓ |  |
| Comment | nvarchar(50) | ✓ |  |
| ProductID | int() | ✓ |  |
| ReviewID | int() | ✗ |  |
| CustomerID | int() | ✓ |  |
| ReviewDate | nvarchar(50) | ✓ |  |

### Primary Key

- **Columns:** ReviewID

### Foreign Keys

| Constraint | Column | References |
|------------|--------|------------|
| FK_Reviews_Customers | CustomerID | Customers(CustomerID) |
| FK_Reviews_Products | ProductID | Products(ProductID) |

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Reviews | CLUSTERED | ✓ | ReviewID |

---

## Database Summary

- **Total Tables:** 5
- **Total Rows:** 33
- **Total Size:** 0.35 MB (360 KB)

