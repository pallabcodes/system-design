-- =============================================
-- SQL Server Indexing Strategies
-- =============================================

-- 1. Clustered Index
-- Typically created automatically with PRIMARY KEY, but can be separate.
CREATE TABLE Sales.Orders (
    OrderID INT IDENTITY(1,1),
    OrderDate DATETIME NOT NULL,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2),
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID)
);
GO

-- 2. Non-Clustered Index
-- Basic index to speed up lookups by CustomerID
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Sales.Orders (CustomerID);
GO

-- 3. Covering Index (using INCLUDE)
-- Optimized for a query like: SELECT TotalAmount FROM Sales.Orders WHERE OrderDate = @Date
-- Avoids Key Lookups by including TotalAmount at the leaf level.
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate_Include_TotalAmount
ON Sales.Orders (OrderDate)
INCLUDE (TotalAmount);
GO

-- 4. Filtered Index
-- Useful for columns with sparse data (e.g., ProcessedDate is NULL for active items)
-- Drastically smaller than a full index.
CREATE NONCLUSTERED INDEX IX_Orders_Unprocessed
ON Sales.Orders (OrderDate)
WHERE TotalAmount IS NULL; -- Example condition
GO

-- 5. Clustered Columnstore Index (CCI)
-- For high-performance analytics on large tables.
-- Note: A table with a CCI cannot have other B-Tree indexes in older versions of SQL Server,
-- but mixed usage is supported in newer versions.
CREATE TABLE Sales.OrderHistory (
    HistoryID INT,
    OrderDate DATETIME,
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(18,2)
);

CREATE CLUSTERED COLUMNSTORE INDEX CCI_OrderHistory
ON Sales.OrderHistory;
GO

-- 6. Non-Clustered Columnstore Index (NCCI)
-- Real-time Operational Analytics on OLTP tables.
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Orders_Analytics
ON Sales.Orders (OrderID, OrderDate, CustomerID, TotalAmount);
GO

-- =============================================
-- Index Maintenance
-- =============================================

-- Checking Fragmentation
SELECT 
    dps.object_id,
    object_name(dps.object_id) as table_name,
    i.name as index_name,
    dps.index_type_desc,
    dps.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') dps
JOIN sys.indexes i ON dps.object_id = i.object_id AND dps.index_id = i.index_id
WHERE dps.avg_fragmentation_in_percent > 10;
GO

-- Reorganize (Low Fragmentation: 5-30%)
ALTER INDEX IX_Orders_CustomerID ON Sales.Orders REORGANIZE;
GO

-- Rebuild (High Fragmentation: > 30%)
ALTER INDEX IX_Orders_CustomerID ON Sales.Orders REBUILD;
GO
