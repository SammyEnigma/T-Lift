/*=====================================================================
  T-Lift Test Suite — Database & Schema Setup
  
  This script:
    1. Creates the TLift_Engine database (hosts sp_tlift)
    2. Creates the TLift_TestDB database (hosts test tables & procedures)
    3. Populates sample data
    4. Installs sp_tlift into TLift_Engine
  
  Run this ONCE before executing test_cases.sql.
=====================================================================*/

-- ===================================================================
-- 1. Create databases
-- ===================================================================
USE [master];
GO

IF DB_ID('TLift_Engine') IS NULL
    CREATE DATABASE [TLift_Engine];
GO

IF DB_ID('TLift_TestDB') IS NULL
    CREATE DATABASE [TLift_TestDB];
GO

-- ===================================================================
-- 2. Create sample tables and populate data in TLift_TestDB
-- ===================================================================
USE [TLift_TestDB];
GO

-- Drop tables if they exist (idempotent re-runs)
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.Products', 'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

-- Customers
CREATE TABLE dbo.Customers (
    CustomerID   INT IDENTITY(1,1) PRIMARY KEY,
    FirstName    NVARCHAR(50)  NOT NULL,
    LastName     NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(100) NOT NULL,
    City         NVARCHAR(50)  NOT NULL,
    Country      NVARCHAR(50)  NOT NULL,
    CreatedDate  DATE          NOT NULL DEFAULT GETDATE()
);

-- Products
CREATE TABLE dbo.Products (
    ProductID    INT IDENTITY(1,1) PRIMARY KEY,
    ProductName  NVARCHAR(100) NOT NULL,
    Category     NVARCHAR(50)  NOT NULL,
    UnitPrice    DECIMAL(10,2) NOT NULL,
    IsActive     BIT           NOT NULL DEFAULT 1
);

-- Orders
CREATE TABLE dbo.Orders (
    OrderID      INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID   INT           NOT NULL REFERENCES dbo.Customers(CustomerID),
    OrderDate    DATE          NOT NULL,
    Status       NVARCHAR(20)  NOT NULL,
    TotalAmount  DECIMAL(12,2) NOT NULL DEFAULT 0
);

-- OrderItems
CREATE TABLE dbo.OrderItems (
    OrderItemID  INT IDENTITY(1,1) PRIMARY KEY,
    OrderID      INT           NOT NULL REFERENCES dbo.Orders(OrderID),
    ProductID    INT           NOT NULL REFERENCES dbo.Products(ProductID),
    Quantity     INT           NOT NULL,
    UnitPrice    DECIMAL(10,2) NOT NULL,
    LineTotal    AS (Quantity * UnitPrice) PERSISTED
);
GO

-- -------------------------------------------------------------------
-- Populate Customers (~500 rows)
-- -------------------------------------------------------------------
;WITH Nums AS (
    SELECT TOP 500 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_columns a CROSS JOIN sys.all_columns b
)
INSERT INTO dbo.Customers (FirstName, LastName, Email, City, Country, CreatedDate)
SELECT
    CHOOSE((n % 10) + 1, 'Alice','Bob','Carol','Dave','Eve','Frank','Grace','Hank','Ivy','Jack'),
    CHOOSE((n % 8) + 1, 'Smith','Jones','Brown','Davis','Wilson','Taylor','Clark','Hall'),
    'user' + CAST(n AS VARCHAR(10)) + '@test.com',
    CHOOSE((n % 6) + 1, 'Berlin','Munich','Hamburg','Vienna','Zurich','Prague'),
    CHOOSE((n % 4) + 1, 'Germany','Austria','Switzerland','Czech Republic'),
    DATEADD(DAY, -(n % 730), '2025-12-31')
FROM Nums;

-- -------------------------------------------------------------------
-- Populate Products (~50 rows)
-- -------------------------------------------------------------------
;WITH Nums AS (
    SELECT TOP 50 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_columns
)
INSERT INTO dbo.Products (ProductName, Category, UnitPrice, IsActive)
SELECT
    'Product_' + CAST(n AS VARCHAR(10)),
    CHOOSE((n % 5) + 1, 'Electronics','Clothing','Food','Books','Tools'),
    CAST(5.00 + (n * 3.50) AS DECIMAL(10,2)),
    CASE WHEN n % 7 = 0 THEN 0 ELSE 1 END
FROM Nums;

-- -------------------------------------------------------------------
-- Populate Orders (~5000 rows)
-- -------------------------------------------------------------------
;WITH Nums AS (
    SELECT TOP 5000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_columns a CROSS JOIN sys.all_columns b
)
INSERT INTO dbo.Orders (CustomerID, OrderDate, Status, TotalAmount)
SELECT
    (n % 500) + 1,
    DATEADD(DAY, -(n % 365), '2025-12-31'),
    CHOOSE((n % 4) + 1, 'Pending','Shipped','Delivered','Cancelled'),
    CAST(10.00 + (n % 500) * 2.5 AS DECIMAL(12,2))
FROM Nums;

-- -------------------------------------------------------------------
-- Populate OrderItems (~20000 rows)
-- -------------------------------------------------------------------
;WITH Nums AS (
    SELECT TOP 20000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_columns a CROSS JOIN sys.all_columns b
)
INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
SELECT
    (n % 5000) + 1,
    (n % 50) + 1,
    (n % 10) + 1,
    CAST(5.00 + (n % 50) * 3.50 AS DECIMAL(10,2))
FROM Nums;
GO

-- -------------------------------------------------------------------
-- Add useful indexes
-- -------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON dbo.Orders(CustomerID);
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON dbo.Orders(OrderDate);
CREATE NONCLUSTERED INDEX IX_Orders_Status ON dbo.Orders(Status);
CREATE NONCLUSTERED INDEX IX_OrderItems_OrderID ON dbo.OrderItems(OrderID);
CREATE NONCLUSTERED INDEX IX_OrderItems_ProductID ON dbo.OrderItems(ProductID);
GO

DECLARE @cnt1 INT, @cnt2 INT, @cnt3 INT, @cnt4 INT;
SELECT @cnt1 = COUNT(*) FROM dbo.Customers;
SELECT @cnt2 = COUNT(*) FROM dbo.Products;
SELECT @cnt3 = COUNT(*) FROM dbo.Orders;
SELECT @cnt4 = COUNT(*) FROM dbo.OrderItems;
PRINT '=== TLift_TestDB: Tables and data created successfully ===';
PRINT 'Customers: ' + CAST(@cnt1 AS VARCHAR);
PRINT 'Products:  ' + CAST(@cnt2 AS VARCHAR);
PRINT 'Orders:    ' + CAST(@cnt3 AS VARCHAR);
PRINT 'OrderItems:' + CAST(@cnt4 AS VARCHAR);
GO
