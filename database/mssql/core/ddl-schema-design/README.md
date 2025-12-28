# SQL Server DDL Schema Design

## Overview

Data Definition Language (DDL) in SQL Server provides powerful features for creating and managing database objects. This guide covers SQL Server-specific DDL features including filegroups, partitioning, memory-optimized tables, temporal tables, columnstore indexes, and advanced data types.

## Table of Contents

1. [Database Creation](#database-creation)
2. [Filegroups and Files](#filegroups-and-files)
3. [Advanced Data Types](#advanced-data-types)
4. [Memory-Optimized Tables](#memory-optimized-tables)
5. [Temporal Tables](#temporal-tables)
6. [Columnstore Indexes](#columnstore-indexes)
7. [Partitioning](#partitions)
8. [Computed Columns](#computed-columns)
9. [Constraints](#constraints)
10. [Defaults and Rules](#defaults-and-rules)

## Database Creation

### Basic Database Creation

```sql
-- Basic database creation
CREATE DATABASE SalesDB
ON PRIMARY
(
    NAME = 'SalesDB_Primary',
    FILENAME = 'C:\SQLData\SalesDB.mdf',
    SIZE = 100MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 10MB
)
LOG ON
(
    NAME = 'SalesDB_Log',
    FILENAME = 'C:\SQLLogs\SalesDB.ldf',
    SIZE = 50MB,
    MAXSIZE = 500MB,
    FILEGROWTH = 10MB
);
```

### Database with Multiple Filegroups

```sql
-- Database with multiple filegroups for performance
CREATE DATABASE AnalyticsDB
ON PRIMARY
(
    NAME = 'AnalyticsDB_Primary',
    FILENAME = 'C:\SQLData\AnalyticsDB_Primary.mdf',
    SIZE = 100MB
),
FILEGROUP Analytics_FG1
(
    NAME = 'AnalyticsDB_FG1_Data1',
    FILENAME = 'D:\SQLData\AnalyticsDB_FG1_Data1.ndf',
    SIZE = 1GB
),
FILEGROUP Analytics_FG2
(
    NAME = 'AnalyticsDB_FG2_Data1',
    FILENAME = 'E:\SQLData\AnalyticsDB_FG2_Data1.ndf',
    SIZE = 1GB
)
LOG ON
(
    NAME = 'AnalyticsDB_Log',
    FILENAME = 'F:\SQLLogs\AnalyticsDB.ldf',
    SIZE = 100MB
);
```

### Database Options

```sql
-- Configure database options
ALTER DATABASE SalesDB
SET
    RECOVERY FULL,
    PAGE_VERIFY CHECKSUM,
    AUTO_CREATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS ON,
    AUTO_UPDATE_STATISTICS_ASYNC ON,
    PARAMETERIZATION FORCED,
    READ_COMMITTED_SNAPSHOT ON,
    ALLOW_SNAPSHOT_ISOLATION ON,
    QUERY_STORE = ON;
```

## Filegroups and Files

### Filegroup Management

```sql
-- Add filegroup
ALTER DATABASE SalesDB
ADD FILEGROUP SalesArchive;

-- Add file to filegroup
ALTER DATABASE SalesDB
ADD FILE
(
    NAME = 'SalesArchive_Data1',
    FILENAME = 'E:\SQLData\SalesArchive_Data1.ndf',
    SIZE = 500MB,
    FILEGROWTH = 50MB
)
TO FILEGROUP SalesArchive;

-- Set default filegroup
ALTER DATABASE SalesDB
MODIFY FILEGROUP SalesArchive DEFAULT;
```

### Filegroup Strategy

- **PRIMARY**: System objects and small tables
- **Data Filegroups**: User tables organized by access patterns
- **Index Filegroups**: Separate indexes for performance
- **Archive Filegroups**: Historical data on slower storage

## Advanced Data Types

### XML Data Type

```sql
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
```

### JSON Support

```sql
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
```

### Spatial Data Types

```sql
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
```

### HierarchyID

```sql
CREATE TABLE Organization
(
    OrgNode HIERARCHYID PRIMARY KEY,
    OrgLevel AS OrgNode.GetLevel(),
    EmployeeID INT,
    EmployeeName NVARCHAR(100)
);

-- Hierarchy Index
CREATE INDEX IX_Organization_OrgLevel
ON Organization(OrgLevel, OrgNode);
```

## Memory-Optimized Tables

### Creating Memory-Optimized Tables

```sql
-- Enable memory-optimized data
ALTER DATABASE SalesDB
ADD FILEGROUP SalesDB_MemoryOptimized
CONTAINS MEMORY_OPTIMIZED_DATA;

ALTER DATABASE SalesDB
ADD FILE
(
    NAME = 'SalesDB_MemoryOptimized_File',
    FILENAME = 'C:\SQLData\SalesDB_MemoryOptimized'
)
TO FILEGROUP SalesDB_MemoryOptimized;

-- Create memory-optimized table
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
```

### Natively Compiled Stored Procedures

```sql
CREATE PROCEDURE sp_GetCartItems
    @UserID INT
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN ATOMIC
WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'English')
    SELECT CartID, ProductID, Quantity, AddedDate
    FROM dbo.ShoppingCart
    WHERE UserID = @UserID
END;
```

## Temporal Tables

### System-Versioned Temporal Tables

```sql
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

-- Query historical data
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME AS OF '2024-01-01 10:00:00';

SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-01-31';

SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME ALL;
```

## Columnstore Indexes

### Clustered Columnstore Index

```sql
CREATE TABLE SalesFact
(
    SaleID INT,
    ProductID INT,
    CustomerID INT,
    SaleDate DATE,
    Quantity INT,
    Amount DECIMAL(10,2)
);

-- Clustered columnstore index
CREATE CLUSTERED COLUMNSTORE INDEX CCI_SalesFact
ON SalesFact;
```

### Nonclustered Columnstore Index

```sql
-- Nonclustered columnstore index on existing table
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Products
ON Products(ProductID, CategoryID, Price, StockQuantity);
```

## Partitioning

### Range Partitioning

```sql
-- Partition function
CREATE PARTITION FUNCTION PF_SalesDate (DATE)
AS RANGE RIGHT FOR VALUES
('2024-01-01', '2024-04-01', '2024-07-01', '2024-10-01');

-- Partition scheme
CREATE PARTITION SCHEME PS_SalesDate
AS PARTITION PF_SalesDate
TO (FG_Q1, FG_Q2, FG_Q3, FG_Q4, FG_Future);

-- Partitioned table
CREATE TABLE Sales
(
    SaleID INT,
    SaleDate DATE,
    Amount DECIMAL(10,2)
)
ON PS_SalesDate(SaleDate);
```

### Partition Switching

```sql
-- Switch partition to archive table
ALTER TABLE Sales
SWITCH PARTITION 1 TO SalesArchive PARTITION 1;

-- Split partition
ALTER PARTITION FUNCTION PF_SalesDate()
SPLIT RANGE ('2025-01-01');

-- Merge partitions
ALTER PARTITION FUNCTION PF_SalesDate()
MERGE RANGE ('2024-04-01');
```

## Computed Columns

### Persisted Computed Columns

```sql
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    TotalAmount AS (Quantity * UnitPrice) PERSISTED,
    OrderDate DATE,
    OrderYear AS YEAR(OrderDate) PERSISTED
);

-- Index on computed column
CREATE INDEX IX_Orders_OrderYear
ON Orders(OrderYear);
```

### Non-Persisted Computed Columns

```sql
CREATE TABLE Products
(
    ProductID INT PRIMARY KEY,
    FirstName NVARCHAR(50),
    LastName NVARCHAR(50),
    FullName AS (FirstName + ' ' + LastName),
    Price DECIMAL(10,2),
    TaxRate DECIMAL(5,4),
    PriceWithTax AS (Price * (1 + TaxRate))
);
```

## Constraints

### Check Constraints

```sql
CREATE TABLE Products
(
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    StockQuantity INT NOT NULL,
    CONSTRAINT CK_Price_Positive CHECK (Price > 0),
    CONSTRAINT CK_Stock_NonNegative CHECK (StockQuantity >= 0),
    CONSTRAINT CK_ProductName_Length CHECK (LEN(ProductName) >= 3)
);
```

### Unique Constraints

```sql
CREATE TABLE Users
(
    UserID INT PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) NOT NULL,
    CONSTRAINT UQ_Users_Username UNIQUE (Username),
    CONSTRAINT UQ_Users_Email UNIQUE (Email)
);

-- Unique constraint with filter
CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_ActiveEmail
ON Users(Email)
WHERE IsActive = 1;
```

### Foreign Key Constraints

```sql
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    UserID INT NOT NULL,
    OrderDate DATETIME2 NOT NULL,
    CONSTRAINT FK_Orders_Users
        FOREIGN KEY (UserID)
        REFERENCES Users(UserID)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
```

## Defaults and Rules

### Default Constraints

```sql
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    OrderDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    Status NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    CreatedBy NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER
);
```

### Default Objects (Legacy)

```sql
-- Create default object
CREATE DEFAULT df_Status AS 'Active';

-- Bind to column
EXEC sp_bindefault 'df_Status', 'Users.Status';
```

## Best Practices

### 1. Filegroup Strategy

- Use PRIMARY for system objects only
- Create separate filegroups for data, indexes, and archives
- Distribute files across multiple drives for I/O performance
- Use filegroups for backup strategies

### 2. Index Design

- Clustered index on primary key (usually)
- Non-clustered indexes for foreign keys and frequently queried columns
- Include columns to create covering indexes
- Filtered indexes for conditional queries
- Columnstore indexes for analytics workloads

### 3. Partitioning Strategy

- Partition large tables by date ranges
- Use partition switching for data archival
- Align indexes with partition scheme
- Monitor partition elimination in query plans

### 4. Temporal Tables

- Use for audit trails and history tracking
- Consider storage requirements for history table
- Use FOR SYSTEM_TIME queries for point-in-time analysis
- Archive old history data periodically

This comprehensive guide provides enterprise-grade SQL Server DDL patterns and implementations for building production-ready database schemas with advanced features and performance optimizations.

