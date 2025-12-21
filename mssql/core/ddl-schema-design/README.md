# SQL Server DDL Schema Design

## Overview

Data Definition Language (DDL) in SQL Server provides powerful features for creating and managing database objects. This guide covers SQL Server-specific DDL features including filegroups, partitioning, memory-optimized tables, temporal tables, and advanced data types.

## Table of Contents

1. [Database Creation](#database-creation)
2. [Filegroups and Files](#filegroups-and-files)
3. [Advanced Data Types](#advanced-data-types)
4. [Memory-Optimized Tables](#memory-optimized-tables)
5. [Temporal Tables](#temporal-tables)
6. [Columnstore Indexes](#columnstore-indexes)
7. [Partitioning](#partitioning)
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
    ALLOW_SNAPSHOT_ISOLATION ON;
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
    NAME = 'SalesArchive_Data',
    FILENAME = 'C:\SQLData\SalesArchive.ndf',
    SIZE = 500MB
)
TO FILEGROUP SalesArchive;

-- Make filegroup default
ALTER DATABASE SalesDB
MODIFY FILEGROUP SalesArchive DEFAULT;

-- Remove file from filegroup (must be empty)
ALTER DATABASE SalesDB
REMOVE FILE SalesArchive_Data;

-- Remove filegroup (must be empty)
ALTER DATABASE SalesDB
REMOVE FILEGROUP SalesArchive;
```

### File Management

```sql
-- Add secondary data file
ALTER DATABASE SalesDB
ADD FILE
(
    NAME = 'SalesDB_Data2',
    FILENAME = 'C:\SQLData\SalesDB_Data2.ndf',
    SIZE = 500MB,
    MAXSIZE = 2GB,
    FILEGROWTH = 100MB
);

-- Modify existing file
ALTER DATABASE SalesDB
MODIFY FILE
(
    NAME = 'SalesDB_Data2',
    SIZE = 1GB,
    FILEGROWTH = 200MB
);

-- Remove file (must be empty)
ALTER DATABASE SalesDB
REMOVE FILE SalesDB_Data2;
```

## Advanced Data Types

### Spatial Data Types

```sql
-- Create table with spatial data
CREATE TABLE Locations
(
    LocationID INT PRIMARY KEY,
    LocationName NVARCHAR(100),
    GeoLocation GEOGRAPHY,
    Area GEOMETRY,
    CreatedDate DATETIME2 DEFAULT GETDATE()
);

-- Insert spatial data
INSERT INTO Locations (LocationID, LocationName, GeoLocation, Area)
VALUES
(1, 'Headquarters', GEOGRAPHY::STGeomFromText('POINT(-122.4194 37.7749)', 4326),
 GEOMETRY::STGeomFromText('POLYGON((-122.5 37.7, -122.3 37.7, -122.3 37.8, -122.5 37.8, -122.5 37.7))', 0));

-- Query spatial data
SELECT LocationName,
       GeoLocation.STAsText() AS Coordinates,
       GeoLocation.STDistance(GEOGRAPHY::STGeomFromText('POINT(-122.0 37.0)', 4326)) / 1000 AS DistanceKm
FROM Locations;
```

### HierarchyID

```sql
-- Create hierarchical table
CREATE TABLE Organization
(
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100),
    ManagerID INT,
    OrgLevel HIERARCHYID,
    Salary DECIMAL(10,2)
);

-- Create index on hierarchy
CREATE INDEX IX_Organization_OrgLevel
ON Organization (OrgLevel);

-- Insert hierarchical data
INSERT INTO Organization (EmployeeID, EmployeeName, ManagerID, OrgLevel, Salary)
VALUES
(1, 'CEO', NULL, HIERARCHYID::GetRoot(), 500000),
(2, 'VP Sales', 1, HIERARCHYID::GetRoot().GetDescendant(NULL, NULL), 200000),
(3, 'VP Engineering', 1, HIERARCHYID::GetRoot().GetDescendant(HIERARCHYID::Parse('/1/'), NULL), 250000);

-- Query hierarchy
SELECT
    EmployeeID,
    EmployeeName,
    OrgLevel.ToString() AS LevelPath,
    OrgLevel.GetLevel() AS Level,
    Salary
FROM Organization
ORDER BY OrgLevel;
```

### XML Data Type

```sql
-- Create table with XML column
CREATE TABLE ProductCatalog
(
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100),
    ProductData XML,
    LastUpdated DATETIME2 DEFAULT GETDATE()
);

-- Create XML index
CREATE PRIMARY XML INDEX IX_ProductCatalog_ProductData
ON ProductCatalog (ProductData);

-- Insert XML data
INSERT INTO ProductCatalog (ProductID, ProductName, ProductData)
VALUES
(1, 'Laptop', '<product>
    <specs>
        <cpu>i7-9750H</cpu>
        <ram>16GB</ram>
        <storage>512GB SSD</storage>
    </specs>
    <price currency="USD">1299.99</price>
</product>');

-- Query XML data
SELECT
    ProductID,
    ProductName,
    ProductData.value('(/product/price)[1]', 'DECIMAL(10,2)') AS Price,
    ProductData.value('(/product/specs/cpu)[1]', 'NVARCHAR(50)') AS CPU
FROM ProductCatalog
WHERE ProductData.exist('/product[price/@currency="USD"]') = 1;
```

### JSON Support (SQL Server 2016+)

```sql
-- JSON storage and querying
CREATE TABLE UserPreferences
(
    UserID INT PRIMARY KEY,
    Preferences NVARCHAR(MAX) CHECK (ISJSON(Preferences) = 1),
    LastModified DATETIME2 DEFAULT GETDATE()
);

-- Insert JSON data
INSERT INTO UserPreferences (UserID, Preferences)
VALUES
(1, '{"theme": "dark", "language": "en", "notifications": {"email": true, "sms": false}}');

-- Query JSON data
SELECT
    UserID,
    JSON_VALUE(Preferences, '$.theme') AS Theme,
    JSON_VALUE(Preferences, '$.language') AS Language,
    JSON_VALUE(Preferences, '$.notifications.email') AS EmailNotifications
FROM UserPreferences
WHERE JSON_VALUE(Preferences, '$.theme') = 'dark';
```

## Memory-Optimized Tables

### Memory-Optimized Filegroup

```sql
-- Add memory-optimized filegroup
ALTER DATABASE SalesDB
ADD FILEGROUP MemoryOptimizedFG CONTAINS MEMORY_OPTIMIZED_DATA;

-- Add file to memory-optimized filegroup
ALTER DATABASE SalesDB
ADD FILE
(
    NAME = 'MemoryOptimizedFile',
    FILENAME = 'C:\SQLData\SalesDB_Memory'
)
TO FILEGROUP MemoryOptimizedFG;
```

### Memory-Optimized Tables

```sql
-- Create memory-optimized table
CREATE TABLE dbo.ShoppingCart
(
    CartID INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100000),
    UserID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    AddedDate DATETIME2 NOT NULL DEFAULT GETDATE(),

    INDEX IX_UserID NONCLUSTERED (UserID),
    INDEX IX_ProductID NONCLUSTERED (ProductID)
)
WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- Natively compiled stored procedure
CREATE PROCEDURE dbo.AddToCart
(
    @CartID INT,
    @UserID INT,
    @ProductID INT,
    @Quantity INT
)
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN ATOMIC WITH
(
    TRANSACTION ISOLATION LEVEL = SNAPSHOT,
    LANGUAGE = 'us_english'
)
    INSERT INTO dbo.ShoppingCart (CartID, UserID, ProductID, Quantity)
    VALUES (@CartID, @UserID, @ProductID, @Quantity);
END;
```

### Durability Options

```sql
-- Schema-only durability (data lost on restart)
CREATE TABLE SessionCache
(
    SessionID UNIQUEIDENTIFIER PRIMARY KEY NONCLUSTERED,
    Data NVARCHAR(MAX),
    ExpiresAt DATETIME2
)
WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_ONLY);

-- Schema and data durability (survives restart)
CREATE TABLE UserSessions
(
    SessionID UNIQUEIDENTIFIER PRIMARY KEY NONCLUSTERED,
    UserID INT,
    LoginTime DATETIME2,
    LastActivity DATETIME2
)
WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
```

## Temporal Tables

### System-Versioned Temporal Table

```sql
-- Create temporal table
CREATE TABLE EmployeeHistory
(
    EmployeeID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Department NVARCHAR(50),
    Salary DECIMAL(10,2),
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.EmployeeHistory_History));

-- Insert data
INSERT INTO EmployeeHistory (EmployeeID, Name, Department, Salary)
VALUES (1, 'John Doe', 'IT', 75000);

-- Update data (creates history)
UPDATE EmployeeHistory
SET Salary = 80000
WHERE EmployeeID = 1;

-- Query current data
SELECT * FROM EmployeeHistory;

-- Query historical data
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME AS OF '2023-01-01 00:00:00';

-- Query data between dates
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME BETWEEN '2023-01-01 00:00:00' AND '2023-12-31 23:59:59';

-- Query all history
SELECT * FROM EmployeeHistory
FOR SYSTEM_TIME ALL;
```

### Custom Versioning

```sql
-- Manual versioning table
CREATE TABLE ProductVersions
(
    ProductID INT,
    VersionNumber INT,
    ProductName NVARCHAR(100),
    Price DECIMAL(10,2),
    ValidFrom DATETIME2,
    ValidTo DATETIME2,
    IsCurrent BIT DEFAULT 0,
    PRIMARY KEY (ProductID, VersionNumber)
);

-- Trigger for versioning
CREATE TRIGGER TR_ProductVersions
ON Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Mark old version as not current
    UPDATE pv
    SET pv.ValidTo = GETDATE(), pv.IsCurrent = 0
    FROM ProductVersions pv
    INNER JOIN inserted i ON pv.ProductID = i.ProductID
    WHERE pv.IsCurrent = 1;

    -- Insert new version
    INSERT INTO ProductVersions (ProductID, VersionNumber, ProductName, Price, ValidFrom, IsCurrent)
    SELECT i.ProductID,
           ISNULL((SELECT MAX(VersionNumber) FROM ProductVersions WHERE ProductID = i.ProductID), 0) + 1,
           i.ProductName,
           i.Price,
           GETDATE(),
           1
    FROM inserted i;
END;
```

## Columnstore Indexes

### Clustered Columnstore Index

```sql
-- Create table with clustered columnstore index
CREATE TABLE SalesFact
(
    SalesID INT IDENTITY(1,1),
    ProductID INT,
    CustomerID INT,
    SalesDate DATE,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    TotalAmount AS (Quantity * UnitPrice) PERSISTED,
    INDEX CCI_SalesFact CLUSTERED COLUMNSTORE
);

-- Load data
INSERT INTO SalesFact (ProductID, CustomerID, SalesDate, Quantity, UnitPrice)
SELECT TOP 1000000
    ABS(CHECKSUM(NEWID())) % 1000 + 1,
    ABS(CHECKSUM(NEWID())) % 10000 + 1,
    DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 365, GETDATE()),
    ABS(CHECKSUM(NEWID())) % 10 + 1,
    ABS(CHECKSUM(NEWID())) % 1000 + 10.00
FROM sys.all_objects a1
CROSS JOIN sys.all_objects a2;
```

### Non-Clustered Columnstore Index

```sql
-- Create traditional table
CREATE TABLE SalesTransactions
(
    TransactionID INT PRIMARY KEY,
    CustomerID INT,
    ProductID INT,
    SalesDate DATE,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    TotalAmount DECIMAL(10,2)
);

-- Add non-clustered columnstore index
CREATE NONCLUSTERED COLUMNSTORE INDEX NCI_SalesTransactions
ON SalesTransactions (CustomerID, ProductID, SalesDate, Quantity, UnitPrice, TotalAmount);

-- Query with columnstore index
SELECT
    YEAR(SalesDate) AS SalesYear,
    MONTH(SalesDate) AS SalesMonth,
    SUM(TotalAmount) AS MonthlySales,
    AVG(UnitPrice) AS AvgPrice,
    COUNT(*) AS TransactionCount
FROM SalesTransactions
GROUP BY YEAR(SalesDate), MONTH(SalesDate)
ORDER BY SalesYear, SalesMonth;
```

### Columnstore Index Maintenance

```sql
-- Rebuild columnstore index
ALTER INDEX CCI_SalesFact ON SalesFact REBUILD;

-- Reorganize columnstore index
ALTER INDEX CCI_SalesFact ON SalesFact REORGANIZE;

-- Check fragmentation
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    csrg.row_group_id,
    csrg.state_description,
    csrg.total_rows,
    csrg.deleted_rows,
    100.0 * csrg.deleted_rows / NULLIF(csrg.total_rows, 0) AS FragmentationPercent
FROM sys.column_store_row_groups csrg
INNER JOIN sys.indexes i ON csrg.object_id = i.object_id AND csrg.index_id = i.index_id
WHERE i.name = 'CCI_SalesFact';
```

## Partitioning

### Partition Function and Scheme

```sql
-- Create partition function
CREATE PARTITION FUNCTION pf_SalesDate (DATETIME2)
AS RANGE RIGHT FOR VALUES
('2020-01-01', '2021-01-01', '2022-01-01', '2023-01-01', '2024-01-01');

-- Create partition scheme
CREATE PARTITION SCHEME ps_SalesDate
AS PARTITION pf_SalesDate
TO (fg_2020, fg_2021, fg_2022, fg_2023, fg_2024, fg_future);

-- Create partitioned table
CREATE TABLE SalesPartitioned
(
    SalesID INT IDENTITY(1,1),
    CustomerID INT,
    ProductID INT,
    SalesDate DATETIME2,
    Amount DECIMAL(10,2),
    PRIMARY KEY (SalesID, SalesDate)
)
ON ps_SalesDate (SalesDate);
```

### Partition Management

```sql
-- Add new partition
ALTER PARTITION SCHEME ps_SalesDate
NEXT USED fg_2025;

ALTER PARTITION FUNCTION pf_SalesDate()
SPLIT RANGE ('2025-01-01');

-- Merge partitions
ALTER PARTITION FUNCTION pf_SalesDate()
MERGE RANGE ('2020-01-01');

-- Switch partition
ALTER TABLE SalesStaging SWITCH TO SalesPartitioned PARTITION 1;

-- Query partition information
SELECT
    t.name AS TableName,
    i.name AS IndexName,
    p.partition_number,
    p.rows,
    prv.value AS BoundaryValue
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
LEFT JOIN sys.partition_range_values prv ON prv.function_id = i.data_space_id
    AND prv.boundary_id = p.partition_number - 1
WHERE t.name = 'SalesPartitioned'
ORDER BY p.partition_number;
```

## Computed Columns

### Deterministic Computed Columns

```sql
-- Create table with computed columns
CREATE TABLE Products
(
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100),
    UnitPrice DECIMAL(10,2),
    QuantityInStock INT,
    TotalValue AS (UnitPrice * QuantityInStock) PERSISTED,
    PriceCategory AS
        CASE
            WHEN UnitPrice < 10 THEN 'Budget'
            WHEN UnitPrice < 100 THEN 'Standard'
            ELSE 'Premium'
        END PERSISTED
);

-- Create index on computed column
CREATE INDEX IX_Products_PriceCategory ON Products (PriceCategory);

-- Query computed columns
SELECT
    ProductID,
    ProductName,
    UnitPrice,
    QuantityInStock,
    TotalValue,
    PriceCategory
FROM Products
WHERE PriceCategory = 'Premium';
```

### Non-Deterministic Computed Columns

```sql
-- Non-persisted computed column
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    OrderDate DATETIME2 DEFAULT GETDATE(),
    TotalAmount DECIMAL(10,2),
    OrderStatus NVARCHAR(20) DEFAULT 'Pending',
    DaysSinceOrder AS DATEDIFF(DAY, OrderDate, GETDATE())
);

-- Query non-persisted computed column
SELECT
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    DaysSinceOrder
FROM Orders
WHERE DaysSinceOrder > 30;
```

## Constraints

### Advanced Constraints

```sql
-- Table with multiple constraints
CREATE TABLE Employees
(
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeNumber NVARCHAR(10) UNIQUE,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    HireDate DATE NOT NULL,
    Salary DECIMAL(10,2) CHECK (Salary > 0),
    DepartmentID INT,
    ManagerID INT,

    -- Foreign key constraints
    CONSTRAINT FK_Employees_Department FOREIGN KEY (DepartmentID)
        REFERENCES Departments(DepartmentID),
    CONSTRAINT FK_Employees_Manager FOREIGN KEY (ManagerID)
        REFERENCES Employees(EmployeeID),

    -- Check constraints
    CONSTRAINT CK_Employees_Email CHECK (Email LIKE '%@%'),
    CONSTRAINT CK_Employees_HireDate CHECK (HireDate <= GETDATE()),
    CONSTRAINT CK_Employees_Salary CHECK (Salary BETWEEN 30000 AND 1000000),

    -- Unique constraints
    CONSTRAINT UQ_Employees_EmployeeNumber UNIQUE (EmployeeNumber),
    CONSTRAINT UQ_Employees_Email UNIQUE (Email)
);

-- Add constraint after table creation
ALTER TABLE Employees
ADD CONSTRAINT CK_Employees_Salary_Range
CHECK (Salary >= 30000 AND Salary <= 1000000);

-- Disable constraint
ALTER TABLE Employees
NOCHECK CONSTRAINT CK_Employees_Salary_Range;

-- Enable constraint
ALTER TABLE Employees
CHECK CONSTRAINT CK_Employees_Salary_Range;
```

## Defaults and Rules

### Default Constraints

```sql
-- Create table with default constraints
CREATE TABLE UserAccounts
(
    UserID INT PRIMARY KEY,
    Username NVARCHAR(50) UNIQUE,
    Email NVARCHAR(100) UNIQUE,
    CreatedDate DATETIME2 DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1,
    AccountType NVARCHAR(20) DEFAULT 'Standard',
    LastLogin DATETIME2 DEFAULT NULL,
    LoginAttempts INT DEFAULT 0
);

-- Alter default constraint
ALTER TABLE UserAccounts
ADD CONSTRAINT DF_UserAccounts_CreatedDate
DEFAULT GETDATE() FOR CreatedDate;

-- Drop default constraint
ALTER TABLE UserAccounts
DROP CONSTRAINT DF_UserAccounts_CreatedDate;
```

### Rules (Deprecated but still supported)

```sql
-- Create rule
CREATE RULE SalaryRule
AS @Salary > 0 AND @Salary <= 1000000;

-- Bind rule to datatype
EXEC sp_bindrule 'SalaryRule', 'DECIMAL(10,2)';

-- Create table using ruled datatype
CREATE TABLE Staff
(
    StaffID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Salary DECIMAL(10,2)
);

-- Unbind rule
EXEC sp_unbindrule 'DECIMAL(10,2)';
```

## Best Practices

### Schema Design Guidelines

1. **Use Appropriate Data Types**: Choose the most efficient data type for each column
2. **Normalize Appropriately**: Balance normalization with performance requirements
3. **Plan for Growth**: Design schemas that can scale with data growth
4. **Use Constraints Wisely**: Implement appropriate constraints for data integrity
5. **Consider Partitioning**: Plan for partitioning in large tables from the start
6. **Document Your Schema**: Maintain clear documentation of table relationships and business rules

### Performance Considerations

1. **Filegroup Strategy**: Place heavily used tables on separate filegroups
2. **Memory-Optimized Tables**: Use for high-throughput, low-latency workloads
3. **Temporal Tables**: Enable for tables requiring historical tracking
4. **Columnstore Indexes**: Implement for analytical workloads
5. **Partitioning**: Use for large tables with time-based or range-based data

### Maintenance Considerations

1. **Regular Statistics Updates**: Keep statistics current for optimal query plans
2. **Index Maintenance**: Rebuild or reorganize indexes regularly
3. **Filegroup Management**: Monitor file and filegroup usage
4. **Backup Verification**: Regularly test backup integrity
5. **Security Reviews**: Regularly audit security configurations

This comprehensive guide covers the essential DDL features in SQL Server, providing a solid foundation for designing robust, scalable, and maintainable database schemas.
