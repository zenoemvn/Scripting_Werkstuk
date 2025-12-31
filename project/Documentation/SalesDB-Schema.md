# Database Schema Documentation

**Database:** SalesDB
**Server:** localhost\SQLEXPRESS
**Generated:** 2025-12-30 16:08:25

---

## Table of Contents

- [Customers](#customers)
- [Products](#products)
- [Orders](#orders)
- [OrderDetails](#orderdetails)
- [Reviews](#reviews)

---

## Customers

**Row Count:** 5
**Size:** 0.14 MB (144 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| CustomerID | int() |   |  |
| FirstName | nvarchar(50) |   |  |
| LastName | nvarchar(50) |   |  |
| Email | nvarchar(100) |  |  |
| Phone | nvarchar(20) |  |  |
| City | nvarchar(50) |  |  |
| Country | nvarchar(50) |  |  |
| CreatedDate | datetime() |  | (getdate()) |

### Primary Key

- **Columns:** CustomerID

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Customers | CLUSTERED |  | CustomerID |
| UQ_Customers_Email | NONCLUSTERED |  | Email |

### UNIQUE Constraints

| Constraint | Columns |
|------------|---------|
| UQ_Customers_Email | Email |

---

## Products

**Row Count:** 8
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| ProductID | int() |   |  |
| ProductName | nvarchar(100) |   |  |
| Category | nvarchar(50) |  |  |
| Price | decimal() |   |  |
| Stock | int() |  | ((0)) |
| CreatedDate | datetime() |  | (getdate()) |

### Primary Key

- **Columns:** ProductID

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Products | CLUSTERED |  | ProductID |

---

## Orders

**Row Count:** 6
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| OrderID | int() |   |  |
| CustomerID | int() |   |  |
| OrderDate | datetime() |  | (getdate()) |
| Status | nvarchar(20) |  |  |
| TotalAmount | decimal() |  |  |
| ShippingAddress | nvarchar(200) |  |  |

### Primary Key

- **Columns:** OrderID

### Foreign Keys

| Constraint | Column | References |
|------------|--------|------------|
| FK_Orders_Customers | CustomerID | Customers(CustomerID) |

### Indexes

| Index Name | Type | Unique | Columns |
|------------|------|--------|---------|
| PK_Orders | CLUSTERED |  | OrderID |

### CHECK Constraints

| Constraint | Definition |
|------------|------------|
| CHK_Orders_Status | `([Status]='Cancelled' OR [Status]='Delivered' OR [Status]='Shipped' OR [Status]='Processing' OR [Status]='Pending')` |

---

## OrderDetails

**Row Count:** 8
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| OrderDetailID | int() |   |  |
| OrderID | int() |   |  |
| ProductID | int() |   |  |
| Quantity | int() |   |  |
| UnitPrice | decimal() |   |  |
| Discount | decimal() |  | ((0)) |

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
| PK_OrderDetails | CLUSTERED |  | OrderDetailID |

---

## Reviews

**Row Count:** 6
**Size:** 0.07 MB (72 KB)

### Columns

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| ReviewID | int() |   |  |
| ProductID | int() |   |  |
| CustomerID | int() |   |  |
| Rating | int() |  |  |
| Comment | nvarchar(500) |  |  |
| ReviewDate | datetime() |  | (getdate()) |

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
| PK_Reviews | CLUSTERED |  | ReviewID |

### CHECK Constraints

| Constraint | Definition |
|------------|------------|
| CHK_Reviews_Rating | `([Rating]>=(1) AND [Rating]<=(5))` |

---

## Database Summary

- **Total Tables:** 5
- **Total Rows:** 33
- **Total Size:** 0.42 MB (432 KB)

