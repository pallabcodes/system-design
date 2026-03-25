-- SQL Server DDL (Data Definition Language) Schema Design Examples
-- Comprehensive examples of table creation, constraints, indexes, and schema evolution
-- Adapted for SQL Server with clustered indexes, filegroups, temporal tables, and SQL Server-specific features

-- ===========================================
-- BASIC TABLE CREATION PATTERNS
-- ===========================================

-- Simple table with identity primary key
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL UNIQUE,
    Email NVARCHAR(255) NOT NULL UNIQUE,
    PasswordHash NVARCHAR(255) NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Table with GUID primary key
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductName NVARCHAR(255) NOT NULL,
    SKU NVARCHAR(50) UNIQUE NOT NULL,
    Description NVARCHAR(MAX),
    Price DECIMAL(10,2) NOT NULL CHECK (Price > 0),
    StockQuantity INT DEFAULT 0 CHECK (StockQuantity >= 0),
    CategoryID INT,
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    
    INDEX IX_Products_CategoryID (CategoryID),
    INDEX IX_Products_IsActive (IsActive),
    INDEX IX_Products_Price (Price),
    FULLTEXT INDEX ON Products(ProductName, Description) KEY INDEX PK_Products
);

-- ===========================================
-- ADVANCED CONSTRAINTS AND RELATIONSHIPS
-- ===========================================

-- Categories table with self-referencing foreign key
CREATE TABLE Categories
(
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    ParentCategoryID INT NULL,
    CategoryPath AS (
        CASE
            WHEN ParentCategoryID IS NULL THEN '/' + CAST(CategoryID AS NVARCHAR(10))
            ELSE '/' + CAST(CategoryID AS NVARCHAR(10))  -- Would need trigger for full path
        END
    ) PERSISTED,
    IsActive BIT DEFAULT 1,
    SortOrder INT DEFAULT 0,
    
    CONSTRAINT FK_Categories_Parent
        FOREIGN KEY (ParentCategoryID)
        REFERENCES Categories(CategoryID)
        ON DELETE SET NULL,
    CONSTRAINT UQ_CategoryName_Parent UNIQUE (CategoryName, ParentCategoryID),
    INDEX IX_Categories_Parent (ParentCategoryID),
    INDEX IX_Categories_Active (IsActive, SortOrder)
);

-- Orders table with complex relationships
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL,
    OrderNumber NVARCHAR(20) UNIQUE NOT NULL,
    OrderStatus NVARCHAR(20) DEFAULT 'Pending'
        CHECK (OrderStatus IN ('Pending', 'Confirmed', 'Processing', 'Shipped', 'Delivered', 'Cancelled')),
    
    -- Billing address
    BillingAddressLine1 NVARCHAR(255) NOT NULL,
    BillingAddressLine2 NVARCHAR(255),
    BillingCity NVARCHAR(100) NOT NULL,
    BillingState NVARCHAR(50) NOT NULL,
    BillingPostalCode NVARCHAR(20) NOT NULL,
    BillingCountry NVARCHAR(50) DEFAULT 'USA',
    
    -- Shipping address (can be different from billing)
    ShippingAddressLine1 NVARCHAR(255),
    ShippingAddressLine2 NVARCHAR(255),
    ShippingCity NVARCHAR(100),
    ShippingState NVARCHAR(50),
    ShippingPostalCode NVARCHAR(20),
    ShippingCountry NVARCHAR(50),
    
    -- Order totals (calculated fields)
    Subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    ShippingAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    DiscountAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    TotalAmount AS (Subtotal + TaxAmount + ShippingAmount - DiscountAmount) PERSISTED,
    
    -- Payment info
    PaymentMethod NVARCHAR(20) DEFAULT 'CreditCard'
        CHECK (PaymentMethod IN ('CreditCard', 'PayPal', 'BankTransfer', 'CashOnDelivery')),
    PaymentStatus NVARCHAR(20) DEFAULT 'Pending'
        CHECK (PaymentStatus IN ('Pending', 'Paid', 'Failed', 'Refunded')),
    
    -- Dates
    OrderDate DATETIME2 DEFAULT GETUTCDATE(),
    ShippedDate DATETIME2 NULL,
    DeliveredDate DATETIME2 NULL,
    EstimatedDeliveryDate DATE,
    
    -- Metadata
    Notes NVARCHAR(MAX),
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    
    INDEX IX_Orders_UserID (UserID),
    INDEX IX_Orders_OrderDate (OrderDate),
    INDEX IX_Orders_Status (OrderStatus),
    INDEX IX_Orders_PaymentStatus (PaymentStatus)
);

-- ===========================================
-- TEMPORAL TABLES (SYSTEM-VERSIONED)
-- ===========================================

-- Temporal table for audit trail
CREATE TABLE EmployeeHistory
(
    EmployeeID INT NOT NULL PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    DepartmentID INT NOT NULL,
    Salary DECIMAL(10,2) NOT NULL,
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.EmployeeHistoryArchive));

-- Query temporal data
-- Point in time
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME AS OF '2024-01-01 10:00:00';

-- Time range
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-01-31';

-- All history
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME ALL;

-- ===========================================
-- MEMORY-OPTIMIZED TABLES
-- ===========================================

-- Enable memory-optimized data (run once per database)
-- ALTER DATABASE CurrentDB
-- ADD FILEGROUP CurrentDB_MemoryOptimized
-- CONTAINS MEMORY_OPTIMIZED_DATA;
--
-- ALTER DATABASE CurrentDB
-- ADD FILE (NAME = 'CurrentDB_MemoryOptimized_File', FILENAME = 'C:\SQLData\CurrentDB_MemoryOptimized')
-- TO FILEGROUP CurrentDB_MemoryOptimized;

-- Memory-optimized table
CREATE TABLE ShoppingCart
(
    CartID INT IDENTITY(1,1) PRIMARY KEY NONCLUSTERED,
    UserID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    AddedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    INDEX IX_ShoppingCart_UserID NONCLUSTERED HASH (UserID) WITH (BUCKET_COUNT = 10000)
)
WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- ===========================================
-- COLUMNSTORE INDEXES
-- ===========================================

-- Clustered columnstore index
CREATE TABLE SalesFact
(
    SaleID INT,
    ProductID INT,
    CustomerID INT,
    SaleDate DATE,
    Quantity INT,
    Amount DECIMAL(10,2),
    INDEX CCI_SalesFact CLUSTERED COLUMNSTORE
);

-- Nonclustered columnstore index
CREATE TABLE Products
(
    ProductID INT PRIMARY KEY,
    CategoryID INT,
    Price DECIMAL(10,2),
    StockQuantity INT
);

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Products
ON Products(ProductID, CategoryID, Price, StockQuantity);

-- ===========================================
-- PARTITIONED TABLES
-- ===========================================

-- Partition function
CREATE PARTITION FUNCTION PF_SalesDate (DATE)
AS RANGE RIGHT FOR VALUES
('2024-01-01', '2024-04-01', '2024-07-01', '2024-10-01');

-- Partition scheme
CREATE PARTITION SCHEME PS_SalesDate
AS PARTITION PF_SalesDate
TO ([PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY]);

-- Partitioned table
CREATE TABLE Sales
(
    SaleID INT,
    SaleDate DATE,
    Amount DECIMAL(10,2),
    INDEX IX_Sales_SaleDate (SaleDate)
)
ON PS_SalesDate(SaleDate);

-- ===========================================
-- COMPUTED COLUMNS
-- ===========================================

CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    TotalAmount AS (Quantity * UnitPrice) PERSISTED,
    OrderDate DATE,
    OrderYear AS YEAR(OrderDate) PERSISTED,
    INDEX IX_Orders_OrderYear (OrderYear)
);

-- ===========================================
-- XML DATA TYPE
-- ===========================================

CREATE TABLE ProductCatalog
(
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100),
    ProductSpecs XML,
    CONSTRAINT CK_XML_Valid CHECK (ProductSpecs.exist('/Product[@ID]') = 1)
);

-- XML Indexes
CREATE PRIMARY XML INDEX PXML_ProductSpecs
ON ProductCatalog(ProductSpecs);

CREATE XML INDEX IXML_ProductSpecs_Path
ON ProductCatalog(ProductSpecs)
USING XML INDEX PXML_ProductSpecs
FOR PATH;

-- ===========================================
-- JSON SUPPORT
-- ===========================================

CREATE TABLE UserPreferences
(
    UserID INT PRIMARY KEY,
    Preferences NVARCHAR(MAX),
    CONSTRAINT CK_JSON_Valid CHECK (ISJSON(Preferences) = 1)
);

-- JSON Index (using computed column)
ALTER TABLE UserPreferences
ADD Preferences_JSON AS JSON_QUERY(Preferences);

CREATE INDEX IX_UserPreferences_JSON
ON UserPreferences(Preferences_JSON);

-- ===========================================
-- SPATIAL DATA TYPES
-- ===========================================

CREATE TABLE Locations
(
    LocationID INT PRIMARY KEY,
    LocationName NVARCHAR(100),
    Coordinates GEOGRAPHY,
    Area GEOMETRY
);

-- Spatial Index
CREATE SPATIAL INDEX SIX_Locations_Coordinates
ON Locations(Coordinates)
USING GEOGRAPHY_GRID
WITH (
    GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
    CELLS_PER_OBJECT = 16
);

-- ===========================================
-- HIERARCHYID
-- ===========================================

CREATE TABLE Organization
(
    OrgNode HIERARCHYID PRIMARY KEY,
    OrgLevel AS OrgNode.GetLevel(),
    EmployeeID INT,
    EmployeeName NVARCHAR(100),
    INDEX IX_Organization_OrgLevel (OrgLevel, OrgNode)
);

-- ===========================================
-- INDEXED VIEWS
-- ===========================================

CREATE VIEW vw_OrderSummary
WITH SCHEMABINDING
AS
SELECT
    UserID,
    COUNT_BIG(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSpent,
    AVG(TotalAmount) AS AverageOrderValue
FROM dbo.Orders
GROUP BY UserID;
GO

CREATE UNIQUE CLUSTERED INDEX IX_vw_OrderSummary
ON vw_OrderSummary(UserID);

-- ===========================================
-- FILTERED INDEXES
-- ===========================================

CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    OrderStatus NVARCHAR(20),
    OrderDate DATETIME2,
    TotalAmount DECIMAL(10,2)
);

-- Filtered index for active orders only
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(OrderDate, TotalAmount)
WHERE OrderStatus IN ('Pending', 'Processing');

-- ===========================================
-- INCLUDED COLUMNS (COVERING INDEXES)
-- ===========================================

CREATE NONCLUSTERED INDEX IX_Orders_Covering
ON Orders(OrderDate)
INCLUDE (OrderStatus, TotalAmount, UserID);

-- ===========================================
-- TABLE ALTERATION PATTERNS
-- ===========================================

-- Add column
ALTER TABLE Users
ADD LastLoginDate DATETIME2 NULL;

-- Add column with default
ALTER TABLE Users
ADD IsActive BIT NOT NULL DEFAULT 1;

-- Modify column
ALTER TABLE Users
ALTER COLUMN Email NVARCHAR(500) NOT NULL;

-- Drop column
ALTER TABLE Users
DROP COLUMN LastLoginDate;

-- Add constraint
ALTER TABLE Products
ADD CONSTRAINT CK_Price_Positive CHECK (Price > 0);

-- Drop constraint
ALTER TABLE Products
DROP CONSTRAINT CK_Price_Positive;

-- ===========================================
-- SCHEMA EVOLUTION PATTERNS
-- ===========================================

-- Add new table with foreign key
CREATE TABLE OrderItems
(
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID UNIQUEIDENTIFIER NOT NULL,
    ProductID UNIQUEIDENTIFIER NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    TotalPrice AS (Quantity * UnitPrice) PERSISTED,
    
    CONSTRAINT FK_OrderItems_Orders
        FOREIGN KEY (OrderID)
        REFERENCES Orders(OrderID)
        ON DELETE CASCADE,
    CONSTRAINT FK_OrderItems_Products
        FOREIGN KEY (ProductID)
        REFERENCES Products(ProductID),
    CONSTRAINT UQ_OrderItem_Order_Product UNIQUE (OrderID, ProductID)
);

-- Add index after table creation
CREATE INDEX IX_OrderItems_OrderID
ON OrderItems(OrderID);

CREATE INDEX IX_OrderItems_ProductID
ON OrderItems(ProductID);

/*
This comprehensive SQL Server DDL examples file provides enterprise-grade patterns for:
- Table creation with various primary key strategies
- Advanced constraints and relationships
- Temporal tables for audit trails
- Memory-optimized tables for high-performance scenarios
- Columnstore indexes for analytics workloads
- Table partitioning for large datasets
- Computed columns and indexed views
- XML, JSON, spatial, and hierarchyid data types
- Filtered indexes and covering indexes
- Schema evolution and table alteration patterns

All examples are adapted for SQL Server with proper T-SQL syntax and SQL Server-specific features.
*/

