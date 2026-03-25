# SQL Server Partitioning

## Overview

Partitioning in SQL Server allows you to divide large tables and indexes into smaller, more manageable pieces. This improves query performance, simplifies maintenance, and enables efficient data archival strategies.

## Table of Contents

1. [Partitioning Fundamentals](#partitioning-fundamentals)
2. [Range Partitioning](#range-partitioning)
3. [List Partitioning](#list-partitioning)
4. [Hash Partitioning](#hash-partitioning)
5. [Partition Management](#partition-management)
6. [Partition Switching](#partition-switching)
7. [Index Alignment](#index-alignment)
8. [Performance Considerations](#performance-considerations)
9. [Enterprise Patterns](#enterprise-patterns)

## Partitioning Fundamentals

### What is Partitioning?

Partitioning divides a table into multiple physical storage units (partitions) while maintaining a single logical table. Each partition can be stored on different filegroups for better I/O distribution.

### Benefits of Partitioning

* **Improved Query Performance**: Partition elimination reduces data scanned
* **Easier Maintenance**: Operations on individual partitions
* **Efficient Archival**: Switch partitions to archive tables
* **Better Parallelism**: Multiple partitions can be processed in parallel
* **Storage Management**: Distribute partitions across filegroups

## Range Partitioning

### Creating Range Partition Function

```sql
-- Create partition function for date range
CREATE PARTITION FUNCTION PF_Orders_Date (DATETIME2)
AS RANGE RIGHT FOR VALUES
(
    '2024-01-01',
    '2024-04-01',
    '2024-07-01',
    '2024-10-01'
);
-- Creates partitions: < 2024-01-01, 2024-01-01 to 2024-04-01, etc.
```

### Creating Partition Scheme

```sql
-- Create partition scheme
CREATE PARTITION SCHEME PS_Orders_Date
AS PARTITION PF_Orders_Date
TO
(
    [FG_Q1_2024],
    [FG_Q2_2024],
    [FG_Q3_2024],
    [FG_Q4_2024],
    [FG_Future]
);
```

### Creating Partitioned Table

```sql
-- Create partitioned table
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderNumber NVARCHAR(50) NOT NULL,
    UserID UNIQUEIDENTIFIER NOT NULL,
    OrderDate DATETIME2 NOT NULL,
    TotalAmount DECIMAL(12,2) NOT NULL
)
ON PS_Orders_Date(OrderDate);

-- Create indexes aligned with partition scheme
CREATE INDEX IX_Orders_UserID_OrderDate
ON Orders(UserID, OrderDate)
ON PS_Orders_Date(OrderDate);
```

## List Partitioning

### Creating List Partition Function

```sql
-- Create partition function for status list
CREATE PARTITION FUNCTION PF_Orders_Status (NVARCHAR(20))
AS RANGE LEFT FOR VALUES
(
    'Pending',
    'Processing',
    'Shipped',
    'Delivered'
);
```

### Creating List Partition Scheme

```sql
-- Create partition scheme for status
CREATE PARTITION SCHEME PS_Orders_Status
AS PARTITION PF_Orders_Status
TO
(
    [FG_Pending],
    [FG_Processing],
    [FG_Shipped],
    [FG_Delivered],
    [FG_Other]
);
```

## Hash Partitioning

### Creating Hash Partition Function

```sql
-- Create hash partition function
CREATE PARTITION FUNCTION PF_Orders_Hash (UNIQUEIDENTIFIER)
AS RANGE LEFT FOR VALUES
(
    -- Hash partitions (requires specific values)
    -- Typically used with computed columns
);
```

## Partition Management

### Adding Partitions

```sql
-- Split partition to add new partition
ALTER PARTITION FUNCTION PF_Orders_Date()
SPLIT RANGE ('2025-01-01');

-- Add filegroup for new partition
ALTER DATABASE SalesDB
ADD FILEGROUP FG_Q1_2025;

ALTER DATABASE SalesDB
ADD FILE
(
    NAME = 'FG_Q1_2025_Data',
    FILENAME = 'C:\SQLData\FG_Q1_2025_Data.ndf',
    SIZE = 1GB
)
TO FILEGROUP FG_Q1_2025;

-- Modify partition scheme to include new filegroup
ALTER PARTITION SCHEME PS_Orders_Date
NEXT USED FG_Q1_2025;
```

### Merging Partitions

```sql
-- Merge partitions
ALTER PARTITION FUNCTION PF_Orders_Date()
MERGE RANGE ('2024-04-01');
-- Merges Q1 and Q2 partitions
```

### Querying Partition Information

```sql
-- Get partition information
SELECT
    p.partition_number,
    p.rows,
    fg.name AS filegroup_name,
    prv.value AS partition_boundary
FROM sys.partitions p
INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
INNER JOIN sys.destination_data_spaces dds ON ps.data_space_id = dds.partition_scheme_id
    AND p.partition_number = dds.destination_id
INNER JOIN sys.filegroups fg ON dds.data_space_id = fg.data_space_id
LEFT JOIN sys.partition_range_values prv ON ps.function_id = prv.function_id
    AND p.partition_number = prv.boundary_id + 1
WHERE p.object_id = OBJECT_ID('Orders')
  AND i.index_id IN (0, 1)
ORDER BY p.partition_number;
```

## Partition Switching

### Switching Partitions

```sql
-- Create staging table with same structure
CREATE TABLE Orders_Archive_2023
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY,
    OrderNumber NVARCHAR(50) NOT NULL,
    UserID UNIQUEIDENTIFIER NOT NULL,
    OrderDate DATETIME2 NOT NULL,
    TotalAmount DECIMAL(12,2) NOT NULL
)
ON FG_Q1_2024;  -- Same filegroup as source partition

-- Switch partition to archive table
ALTER TABLE Orders
SWITCH PARTITION 1 TO Orders_Archive_2023;

-- Verify switch
SELECT COUNT(*) FROM Orders_Archive_2023;
```

### Switching In

```sql
-- Switch data into partitioned table
ALTER TABLE Orders_Staging
SWITCH TO Orders PARTITION 1;
```

## Index Alignment

### Aligned Indexes

```sql
-- Create aligned index (same partition scheme)
CREATE INDEX IX_Orders_UserID
ON Orders(UserID)
ON PS_Orders_Date(OrderDate);

-- Non-aligned index (different partition scheme or no partitioning)
CREATE INDEX IX_Orders_OrderNumber
ON Orders(OrderNumber)
ON [PRIMARY];  -- Not aligned
```

### Benefits of Alignment

* **Easier Maintenance**: Index partitions can be rebuilt individually
* **Better Performance**: Partition elimination works with indexes
* **Efficient Switching**: Aligned indexes switch with data

## Performance Considerations

### Partition Elimination

```sql
-- Query with partition elimination
SELECT * FROM Orders
WHERE OrderDate >= '2024-07-01' AND OrderDate < '2024-10-01';
-- Only scans Q3 partition

-- Query without partition elimination
SELECT * FROM Orders
WHERE YEAR(OrderDate) = 2024;
-- Scans all partitions (function on partition key)
```

### Statistics and Maintenance

```sql
-- Update statistics on specific partition
UPDATE STATISTICS Orders
WITH FULLSCAN, RESAMPLE
ON PARTITIONS (1);

-- Rebuild index on specific partition
ALTER INDEX IX_Orders_UserID_OrderDate
ON Orders
REBUILD PARTITION = 1;
```

## Enterprise Patterns

### Time-Based Archival

```sql
-- Monthly archival process
CREATE PROCEDURE sp_ArchiveOldOrders
    @ArchiveDate DATETIME2
AS
BEGIN
    -- Create archive table
    DECLARE @ArchiveTableName NVARCHAR(255) = 'Orders_Archive_' + 
        FORMAT(@ArchiveDate, 'yyyyMM');
    
    -- Dynamic SQL to create archive table and switch partition
    -- ... implementation ...
END;
GO
```

### Sliding Window Pattern

```sql
-- Add new partition for current period
ALTER PARTITION FUNCTION PF_Orders_Date()
SPLIT RANGE ('2025-01-01');

-- Archive oldest partition
ALTER TABLE Orders
SWITCH PARTITION 1 TO Orders_Archive_2023;

-- Merge oldest partition (after archival)
ALTER PARTITION FUNCTION PF_Orders_Date()
MERGE RANGE ('2023-01-01');
```

## Best Practices

1. **Choose appropriate partition key** (frequently filtered, evenly distributed)
2. **Use RANGE RIGHT** for date partitioning (more intuitive)
3. **Align indexes** with partition scheme when possible
4. **Monitor partition elimination** in query plans
5. **Plan partition maintenance** schedules
6. **Use partition switching** for efficient archival
7. **Distribute partitions** across multiple filegroups
8. **Test partition operations** in development first
9. **Document partition strategy** and maintenance procedures
10. **Monitor partition sizes** and adjust boundaries as needed

This guide provides comprehensive SQL Server partitioning strategies for managing large tables and optimizing query performance.

