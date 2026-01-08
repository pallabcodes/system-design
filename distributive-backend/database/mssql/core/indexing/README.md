# SQL Server Indexing Strategies

## Overview

Indexing is critical for query performance in SQL Server. This guide covers the various types of indexes available in SQL Server, their use cases, and best practices for implementation and maintenance.

## Index Types

### 1. Clustered Indexes

**Description**: Sorts and stores the data rows in the table or view based on their key values. There can be only one clustered index per table.

**Key Characteristics**:
- The table data is physically stored in the clustered index order
- Leaf nodes contain the actual data pages
- Usually created on the PRIMARY KEY
- Can be created on any column(s), not just primary key

**Use Case**: 
- Columns frequently used in `ORDER BY`, `GROUP BY`, and range queries
- Usually the Primary Key
- Sequential access patterns

```sql
-- Clustered index on primary key (default)
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    Username NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) NOT NULL
);

-- Custom clustered index (non-primary key)
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY NONCLUSTERED,
    OrderDate DATETIME2 NOT NULL,
    CustomerID INT NOT NULL,
    INDEX CIX_Orders_OrderDate CLUSTERED (OrderDate)
);
```

### 2. Non-Clustered Indexes

**Description**: A structure separate from the data rows. Contains the key values and a pointer to the data row (either a RID for heaps or a Clustered Index Key).

**Key Characteristics**:
- Can have multiple non-clustered indexes per table
- Leaf nodes contain index keys and pointers to data
- Uses clustered index key as pointer (if clustered index exists)
- Uses RID (Row Identifier) as pointer for heaps

**Use Case**: 
- Queries that filter or join on columns not present in the clustered index
- Foreign key columns
- Frequently queried columns

```sql
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
```

### 3. Columnstore Indexes

**Description**: Stores data by column rather than by row. Uses high compression and is optimized for analytical queries.

**Types**:
- **Clustered Columnstore**: The primary storage for the entire table
- **Non-Clustered Columnstore**: Used on top of a rowstore table for real-time operational analytics (HTAP)

**Use Case**: 
- Data warehousing
- Large analytical queries (OLAP)
- Aggregation queries
- Real-time analytics on OLTP tables

```sql
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
```

### 4. XML Indexes

**Description**: For efficient querying of XML data type columns.

**Types**:
- **Primary XML Index**: Base index on XML column
- **Secondary XML Indexes**: PATH, VALUE, PROPERTY

```sql
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
```

### 5. Spatial Indexes

**Description**: For querying geometry and geography data types.

```sql
CREATE TABLE Locations
(
    LocationID INT PRIMARY KEY,
    Coordinates GEOGRAPHY
);

CREATE SPATIAL INDEX SIX_Locations_Coordinates
ON Locations(Coordinates)
USING GEOGRAPHY_GRID
WITH (
    GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
    CELLS_PER_OBJECT = 16
);
```

### 6. Full-Text Indexes

**Description**: For full-text search on text columns.

```sql
CREATE FULLTEXT CATALOG ftCatalog AS DEFAULT;

CREATE FULLTEXT INDEX ON Products(ProductName, Description)
KEY INDEX PK_Products
ON ftCatalog
WITH CHANGE_TRACKING AUTO;
```

## Index Design Strategies

### Covering Indexes (INCLUDE Columns)

```sql
-- Covering index - includes all columns needed by query
CREATE NONCLUSTERED INDEX IX_Orders_Covering
ON Orders(OrderDate)
INCLUDE (CustomerID, TotalAmount, Status);

-- Query can be satisfied entirely from index
SELECT CustomerID, TotalAmount, Status
FROM Orders
WHERE OrderDate BETWEEN '2024-01-01' AND '2024-01-31';
```

### Filtered Indexes

```sql
-- Filtered index for specific conditions
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(OrderDate, TotalAmount)
WHERE Status = 'Active';

-- Useful for:
-- 1. Columns with many NULLs
-- 2. Skewed data distributions
-- 3. Specific query patterns
```

### Composite Indexes

```sql
-- Multi-column index - column order matters!
CREATE NONCLUSTERED INDEX IX_Orders_Composite
ON Orders(CustomerID, OrderDate, Status);

-- Can be used for:
-- WHERE CustomerID = ? AND OrderDate = ? AND Status = ?
-- WHERE CustomerID = ? AND OrderDate = ?
-- WHERE CustomerID = ?
-- BUT NOT: WHERE OrderDate = ? (skipping CustomerID)
```

### Indexed Views

```sql
-- Create indexed view
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

-- Create unique clustered index
CREATE UNIQUE CLUSTERED INDEX IX_vw_OrderSummary
ON vw_OrderSummary(CustomerID);
```

## Index Maintenance

### Fragmentation

Fragmentation occurs when indexes have pages in which the logical ordering does not match the physical ordering.

```sql
-- Check fragmentation
SELECT
    OBJECT_NAME(object_id) AS TableName,
    index_id,
    avg_fragmentation_in_percent,
    page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
WHERE avg_fragmentation_in_percent > 30
ORDER BY avg_fragmentation_in_percent DESC;

-- Reorganize (online, defragments leaf level)
ALTER INDEX IX_Orders_OrderDate
ON Orders
REORGANIZE;

-- Rebuild (can be online in Enterprise edition)
ALTER INDEX IX_Orders_OrderDate
ON Orders
REBUILD
WITH (ONLINE = ON, FILLFACTOR = 90);
```

### Statistics

```sql
-- Update statistics
UPDATE STATISTICS Orders
WITH FULLSCAN;

-- Auto-create and update statistics (database option)
ALTER DATABASE SalesDB
SET AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON;
```

## Best Practices

### 1. Index Selectivity

- Index columns with high selectivity (many unique values)
- Avoid indexing columns with few unique values (e.g., boolean columns)
- Use filtered indexes for low-selectivity columns

### 2. Covering Indexes

- Use `INCLUDE` to create covering indexes that satisfy queries without key lookups
- Reduces I/O by avoiding table lookups

### 3. Write Overhead

- Avoid over-indexing OLTP tables
- Every index adds overhead to `INSERT`, `UPDATE`, and `DELETE` operations
- Balance between read performance and write performance

### 4. Column Order in Composite Indexes

- Order columns by selectivity (most selective first)
- Consider query patterns when ordering columns
- Equality predicates before range predicates

### 5. Filtered Indexes

- Use for columns with many NULLs
- Use for skewed data distributions
- Reduces index size and maintenance overhead

## Common Anti-Patterns

### 1. Duplicate Indexes

```sql
-- BAD: Duplicate indexes
CREATE INDEX IX1 ON Orders(CustomerID);
CREATE INDEX IX2 ON Orders(CustomerID);  -- Duplicate!

-- GOOD: Single index
CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
```

### 2. Unused Indexes

```sql
-- Find unused indexes
SELECT
    OBJECT_NAME(object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s
    ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND s.user_seeks = 0
    AND s.user_scans = 0
    AND s.user_lookups = 0
    AND i.name IS NOT NULL;
```

### 3. Wide Keys

- Large index keys reduce the number of keys per page
- Increases I/O and reduces cache efficiency
- Consider using included columns instead

### 4. Too Many Indexes

- Each index consumes storage and maintenance time
- Monitor index usage and remove unused indexes
- Balance between query performance and maintenance overhead

## Index Monitoring

### Key Metrics

```sql
-- Index usage statistics
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    s.last_user_seek,
    s.last_user_scan
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i
    ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC;

-- Missing index recommendations
SELECT
    OBJECT_NAME(object_id) AS TableName,
    equality_columns,
    inequality_columns,
    included_columns,
    avg_user_impact,
    user_seeks,
    user_scans
FROM sys.dm_db_missing_index_details
ORDER BY avg_user_impact DESC;
```

This comprehensive guide provides enterprise-grade SQL Server indexing strategies for building high-performance database systems with optimal index design and maintenance.

