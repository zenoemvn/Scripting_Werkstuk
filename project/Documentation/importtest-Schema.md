# Database Schema Documentation

**Database:** importtest
**Server:** localhost\SQLEXPRESS
**Generated:** 2025-12-30 16:08:27

---

## Table of Contents

- [Customers](#customers)
- [Products](#products)
- [OrderDetails](#orderdetails)
- [Orders](#orders)
- [Reviews](#reviews)

---

## Customers

**Row Count:** 5
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| LastName | nvarchar(50) | ✓ |  |
| FirstName | nvarchar(50) | ✓ |  |
| Country | nvarchar(50) | ✓ |  |
| CreatedDate | nvarchar(50) | ✓ |  |
| CustomerID | int() | ✗ |  |
| City | nvarchar(50) | ✓ |  |
| Email | nvarchar(50) | ✓ |  |
| Phone | nvarchar(50) | ✓ |  |

### Primary Key

- **Columns:** CustomerID

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Customers | CLUSTERED | ✓ | CustomerID |

---

## Products

**Row Count:** 8
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| ProductID | int() | ✗ |  |
| CreatedDate | nvarchar(50) | ✓ |  |
| ProductName | nvarchar(50) | ✓ |  |
| Stock | int() | ✓ |  |
| Category | nvarchar(50) | ✓ |  |
| Price | decimal() | ✓ |  |

### Primary Key

- **Columns:** ProductID

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Products | CLUSTERED | ✓ | ProductID |

---

## OrderDetails

**Row Count:** 8
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| ProductID | int() | ✓ |  |
| Quantity | int() | ✓ |  |
| Discount | decimal() | ✓ |  |
| UnitPrice | decimal() | ✓ |  |
| OrderDetailID | int() | ✗ |  |
| OrderID | int() | ✓ |  |

### Primary Key

- **Columns:** OrderDetailID

### Foreign Keys

| Constraint | Column | References |
|------------|--------|------------|
| FK_OrderDetails_Products | ProductID | Products(ProductID) |
| FK_OrderDetails_Orders | OrderID | Orders(OrderID) |

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
| ShippingAddress | nvarchar(50) | ✓ |  |
| OrderID | int() | ✗ |  |
| CustomerID | int() | ✓ |  |
| TotalAmount | decimal() | ✓ |  |
| OrderDate | nvarchar(50) | ✓ |  |
| Status | nvarchar(50) | ✓ |  |

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

## Reviews

**Row Count:** 6
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| ProductID | int() | ✓ |  |
| ReviewDate | nvarchar(50) | ✓ |  |
| ReviewID | int() | ✗ |  |
| CustomerID | int() | ✓ |  |
| Comment | nvarchar(50) | ✓ |  |
| Rating | int() | ✓ |  |

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

