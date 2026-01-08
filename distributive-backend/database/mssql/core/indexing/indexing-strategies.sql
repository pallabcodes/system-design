-- SQL Server Indexing Strategies
-- Comprehensive examples of index creation, maintenance, and optimization
-- Adapted for SQL Server with clustered, non-clustered, columnstore, and filtered indexes

-- ===========================================
-- CLUSTERED INDEXES
-- ===========================================

-- Clustered index on primary key (default)
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    Username NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Custom clustered index (non-primary key)
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY NONCLUSTERED,
    OrderDate DATETIME2 NOT NULL,
    CustomerID INT NOT NULL,
    INDEX CIX_Orders_OrderDate CLUSTERED (OrderDate)
);

-- ===========================================
-- NON-CLUSTERED INDEXES
-- ===========================================

-- Basic non-clustered index
CREATE NONCLUSTERED INDEX IX_Users_Email
ON Users(Email);

-- Non-clustered index with included columns (covering index)
CREATE NONCLUSTERED INDEX IX_Orders_Covering
ON Orders(OrderDate)
INCLUDE (CustomerID, TotalAmount, Status);

-- Filtered index
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(OrderDate, TotalAmount)
WHERE Status = 'Active';

-- Composite index
CREATE NONCLUSTERED INDEX IX_Orders_Composite
ON Orders(CustomerID, OrderDate, Status);

-- Unique non-clustered index
CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_Username
ON Users(Username);

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

-- Non-clustered columnstore index
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Products
ON Products(ProductID, CategoryID, Price, StockQuantity);

-- ===========================================
-- XML INDEXES
-- ===========================================

CREATE TABLE ProductCatalog
(
    ProductID INT PRIMARY KEY,
    ProductSpecs XML
);

-- Primary XML index
CREATE PRIMARY XML INDEX PXML_ProductSpecs
ON ProductCatalog(ProductSpecs);

-- Secondary XML index (PATH)
CREATE XML INDEX IXML_ProductSpecs_Path
ON ProductCatalog(ProductSpecs)
USING XML INDEX PXML_ProductSpecs
FOR PATH;

-- Secondary XML index (VALUE)
CREATE XML INDEX IXML_ProductSpecs_Value
ON ProductCatalog(ProductSpecs)
USING XML INDEX PXML_ProductSpecs
FOR VALUE;

-- Secondary XML index (PROPERTY)
CREATE XML INDEX IXML_ProductSpecs_Property
ON ProductCatalog(ProductSpecs)
USING XML INDEX PXML_ProductSpecs
FOR PROPERTY;

-- ===========================================
-- SPATIAL INDEXES
-- ===========================================

CREATE TABLE Locations
(
    LocationID INT PRIMARY KEY,
    LocationName NVARCHAR(100),
    Coordinates GEOGRAPHY,
    Area GEOMETRY
);

-- Geography spatial index
CREATE SPATIAL INDEX SIX_Locations_Coordinates
ON Locations(Coordinates)
USING GEOGRAPHY_GRID
WITH (
    GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
    CELLS_PER_OBJECT = 16
);

-- Geometry spatial index
CREATE SPATIAL INDEX SIX_Locations_Area
ON Locations(Area)
USING GEOMETRY_GRID
WITH (
    BOUNDING_BOX = (0, 0, 100, 100),
    GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
    CELLS_PER_OBJECT = 16
);

-- ===========================================
-- FULL-TEXT INDEXES
-- ===========================================

-- Create full-text catalog
CREATE FULLTEXT CATALOG ftCatalog AS DEFAULT;

-- Create full-text index
CREATE FULLTEXT INDEX ON Products(ProductName, Description)
KEY INDEX PK_Products
ON ftCatalog
WITH CHANGE_TRACKING AUTO;

-- ===========================================
-- INDEXED VIEWS
-- ===========================================

CREATE VIEW vw_OrderSummary
WITH SCHEMABINDING
AS
SELECT
    CustomerID,
    COUNT_BIG(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSpent,
    AVG(TotalAmount) AS AverageOrderValue
FROM dbo.Orders
GROUP BY CustomerID;
GO

-- Create unique clustered index on view
CREATE UNIQUE CLUSTERED INDEX IX_vw_OrderSummary
ON vw_OrderSummary(CustomerID);

-- ===========================================
-- INDEX MAINTENANCE
-- ===========================================

-- Check fragmentation
SELECT
    OBJECT_NAME(object_id) AS TableName,
    index_id,
    avg_fragmentation_in_percent,
    page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
WHERE avg_fragmentation_in_percent > 30
ORDER BY avg_fragmentation_in_percent DESC;

-- Reorganize index (online, defragments leaf level)
ALTER INDEX IX_Orders_OrderDate
ON Orders
REORGANIZE
WITH (LOB_COMPACTION = ON);

-- Rebuild index (can be online in Enterprise edition)
ALTER INDEX IX_Orders_OrderDate
ON Orders
REBUILD
WITH (
    ONLINE = ON,
    FILLFACTOR = 90,
    PAD_INDEX = ON,
    STATISTICS_NORECOMPUTE = OFF
);

-- Rebuild all indexes on table
ALTER INDEX ALL
ON Orders
REBUILD
WITH (ONLINE = ON);

-- Disable index
ALTER INDEX IX_Orders_OrderDate
ON Orders
DISABLE;

-- Re-enable index
ALTER INDEX IX_Orders_OrderDate
ON Orders
REBUILD;

-- Drop index
DROP INDEX IX_Orders_OrderDate
ON Orders;

-- ===========================================
-- STATISTICS
-- ===========================================

-- Create statistics
CREATE STATISTICS ST_Orders_OrderDate
ON Orders(OrderDate);

-- Update statistics
UPDATE STATISTICS Orders
WITH FULLSCAN;

-- Update statistics with sample
UPDATE STATISTICS Orders
WITH SAMPLE 50 PERCENT;

-- Auto-create and update statistics (database option)
ALTER DATABASE SalesDB
SET AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON;

-- ===========================================
-- INDEX MONITORING
-- ===========================================

-- Index usage statistics
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    s.last_user_seek,
    s.last_user_scan,
    s.last_user_lookup,
    s.last_user_update
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i
    ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
    AND s.database_id = DB_ID()
ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC;

-- Missing index recommendations
SELECT
    OBJECT_NAME(object_id) AS TableName,
    equality_columns,
    inequality_columns,
    included_columns,
    avg_user_impact,
    user_seeks,
    user_scans,
    avg_total_user_cost,
    avg_user_impact * (user_seeks + user_scans) AS improvement_measure
FROM sys.dm_db_missing_index_details
ORDER BY improvement_measure DESC;

-- Index fragmentation details
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    ips.avg_page_space_used_in_percent,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'OK'
    END AS Recommendation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i
    ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- ===========================================
-- INDEX OPTIMIZATION PATTERNS
-- ===========================================

-- Covering index pattern
-- Query: SELECT CustomerID, TotalAmount FROM Orders WHERE OrderDate = ?
CREATE NONCLUSTERED INDEX IX_Orders_Covering
ON Orders(OrderDate)
INCLUDE (CustomerID, TotalAmount);

-- Composite index for multiple predicates
-- Query: SELECT * FROM Orders WHERE CustomerID = ? AND OrderDate BETWEEN ? AND ?
CREATE NONCLUSTERED INDEX IX_Orders_Customer_Date
ON Orders(CustomerID, OrderDate);

-- Filtered index for specific conditions
-- Query: SELECT * FROM Orders WHERE Status = 'Active' AND OrderDate > ?
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(OrderDate)
WHERE Status = 'Active';

-- Index for sorting
-- Query: SELECT * FROM Orders ORDER BY OrderDate DESC
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate_Desc
ON Orders(OrderDate DESC);

-- Index for joins
-- Query: SELECT * FROM Orders o INNER JOIN Customers c ON o.CustomerID = c.CustomerID
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Orders(CustomerID);

/*
This comprehensive SQL Server indexing examples file provides enterprise-grade patterns for:
- Clustered and non-clustered indexes
- Columnstore indexes for analytics
- XML and spatial indexes
- Full-text indexes for search
- Indexed views for materialized aggregations
- Index maintenance and fragmentation management
- Statistics creation and updates
- Index monitoring and optimization
- Covering indexes and filtered indexes
- Composite indexes with proper column ordering

All examples are adapted for SQL Server with proper T-SQL syntax and SQL Server-specific features.
*/

