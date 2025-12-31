[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName
)

Write-Host "=== Creating Test Database with Relations ===" -ForegroundColor Cyan

# Drop + Create database
Write-Host "Setting up database..." -ForegroundColor Yellow
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Query @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '$DatabaseName')
BEGIN
    ALTER DATABASE $DatabaseName SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE $DatabaseName;
END
CREATE DATABASE $DatabaseName;
"@

Write-Host " Database created" -ForegroundColor Green

# Create tables met foreign keys
Write-Host "Creating tables with foreign keys..." -ForegroundColor Yellow

Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $DatabaseName `
    -TrustServerCertificate `
    -Query @"
-- Customers tabel (parent)
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100),
    Phone NVARCHAR(20),
    City NVARCHAR(50),
    Country NVARCHAR(50),
    CreatedDate DATETIME DEFAULT GETDATE(),
    
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerID),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email)
);

-- Products tabel (parent)
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50),
    Price DECIMAL(10,2) NOT NULL,
    Stock INT DEFAULT 0,
    CreatedDate DATETIME DEFAULT GETDATE(),
    
    CONSTRAINT PK_Products PRIMARY KEY (ProductID)
);

-- Orders tabel (child van Customers)
CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1),
    CustomerID INT NOT NULL,
    OrderDate DATETIME DEFAULT GETDATE(),
    Status NVARCHAR(20),
    TotalAmount DECIMAL(10,2),
    ShippingAddress NVARCHAR(200),
    
    CONSTRAINT PK_Orders PRIMARY KEY (OrderID),
    CONSTRAINT CHK_Orders_Status CHECK (Status IN ('Pending','Processing','Shipped','Delivered','Cancelled')),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) 
        REFERENCES Customers(CustomerID)
);

-- OrderDetails tabel (child van Orders en Products)
CREATE TABLE OrderDetails (
    OrderDetailID INT IDENTITY(1,1),
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    Discount DECIMAL(5,2) DEFAULT 0,
    
    CONSTRAINT PK_OrderDetails PRIMARY KEY (OrderDetailID),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID) 
        REFERENCES Orders(OrderID),
    CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (ProductID) 
        REFERENCES Products(ProductID)
);

-- Reviews tabel (child van Products en Customers)
CREATE TABLE Reviews (
    ReviewID INT IDENTITY(1,1),
    ProductID INT NOT NULL,
    CustomerID INT NOT NULL,
    Rating INT,
    Comment NVARCHAR(500),
    ReviewDate DATETIME DEFAULT GETDATE(),
    
    CONSTRAINT PK_Reviews PRIMARY KEY (ReviewID),
    CONSTRAINT CHK_Reviews_Rating CHECK (Rating BETWEEN 1 AND 5),
    CONSTRAINT FK_Reviews_Products FOREIGN KEY (ProductID) 
        REFERENCES Products(ProductID),
    CONSTRAINT FK_Reviews_Customers FOREIGN KEY (CustomerID) 
        REFERENCES Customers(CustomerID)
);
"@

Write-Host " Tables created" -ForegroundColor Green

# Insert test data
Write-Host "Inserting test data..." -ForegroundColor Yellow

Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $DatabaseName `
    -TrustServerCertificate `
    -Query @"
-- Customers
INSERT INTO Customers (FirstName, LastName, Email, Phone, City, Country) VALUES
('John', 'Doe', 'john.doe@email.com', '+32-123-456-789', 'Brussels', 'Belgium'),
('Jane', 'Smith', 'jane.smith@email.com', '+32-987-654-321', 'Antwerp', 'Belgium'),
('Bob', 'Johnson', 'bob.j@email.com', '+32-555-123-456', 'Ghent', 'Belgium'),
('Alice', 'Williams', 'alice.w@email.com', '+32-444-789-012', 'Bruges', 'Belgium'),
('Charlie', 'Brown', 'charlie.b@email.com', '+32-333-456-789', 'Leuven', 'Belgium');

-- Products
INSERT INTO Products (ProductName, Category, Price, Stock) VALUES
('Laptop Pro 15', 'Electronics', 1299.99, 50),
('Wireless Mouse', 'Electronics', 29.99, 200),
('Office Chair', 'Furniture', 349.99, 30),
('Desk Lamp', 'Furniture', 59.99, 100),
('USB-C Cable', 'Accessories', 19.99, 500),
('Monitor 27"', 'Electronics', 399.99, 40),
('Keyboard Mechanical', 'Electronics', 129.99, 80),
('Notebook A4', 'Stationery', 5.99, 1000);

-- Orders
INSERT INTO Orders (CustomerID, Status, TotalAmount, ShippingAddress) VALUES
(1, 'Delivered', 1329.98, 'Rue de la Loi 123, Brussels'),
(1, 'Processing', 349.99, 'Rue de la Loi 123, Brussels'),
(2, 'Shipped', 459.98, 'Meir 45, Antwerp'),
(3, 'Delivered', 89.97, 'Veldstraat 78, Ghent'),
(4, 'Pending', 1299.99, 'Markt 12, Bruges'),
(5, 'Delivered', 19.99, 'Bondgenotenlaan 90, Leuven');

-- OrderDetails
INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice, Discount) VALUES
-- Order 1
(1, 1, 1, 1299.99, 0),
(1, 2, 1, 29.99, 0),
-- Order 2
(2, 3, 1, 349.99, 0),
-- Order 3
(3, 6, 1, 399.99, 10),
(3, 7, 1, 129.99, 0),
-- Order 4
(4, 2, 3, 29.99, 0),
-- Order 5
(5, 1, 1, 1299.99, 0),
-- Order 6
(6, 5, 1, 19.99, 0);

-- Reviews
INSERT INTO Reviews (ProductID, CustomerID, Rating, Comment) VALUES
(1, 1, 5, 'Excellent laptop, very fast!'),
(1, 3, 4, 'Good performance but a bit pricey'),
(2, 1, 5, 'Perfect wireless mouse'),
(3, 2, 4, 'Comfortable chair'),
(6, 2, 5, 'Great monitor for the price'),
(7, 3, 5, 'Best mechanical keyboard I have used');
"@

Write-Host " Test data inserted" -ForegroundColor Green

# Show summary
Write-Host "`n=== Database Summary ===" -ForegroundColor Cyan

$summary = Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $DatabaseName `
    -TrustServerCertificate `
    -Query @"
SELECT 'Customers' as TableName, COUNT(*) as [RowCount] FROM Customers
UNION ALL
SELECT 'Products', COUNT(*) FROM Products
UNION ALL
SELECT 'Orders', COUNT(*) FROM Orders
UNION ALL
SELECT 'OrderDetails', COUNT(*) FROM OrderDetails
UNION ALL
SELECT 'Reviews', COUNT(*) FROM Reviews
"@

$summary | Format-Table -AutoSize

# Show foreign keys
Write-Host "`nForeign Keys:" -ForegroundColor Cyan
Invoke-Sqlcmd -ServerInstance $ServerInstance `
    -Database $DatabaseName `
    -TrustServerCertificate `
    -Query @"
SELECT 
    fk.name AS ConstraintName,
    OBJECT_NAME(fk.parent_object_id) AS ChildTable,
    COL_NAME(fc.parent_object_id, fc.parent_column_id) AS ChildColumn,
    OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
    COL_NAME(fc.referenced_object_id, fc.referenced_column_id) AS ParentColumn
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fc ON fk.object_id = fc.constraint_object_id
ORDER BY ChildTable
"@ | Format-Table -AutoSize

Write-Host "`n Setup complete!" -ForegroundColor Green
Write-Host "Database: $DatabaseName" -ForegroundColor Yellow
Write-Host "You can now test migrations with realistic relational data!" -ForegroundColor Gray
