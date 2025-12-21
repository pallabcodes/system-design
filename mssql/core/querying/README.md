# SQL Server Advanced Querying

## Overview

SQL Server provides powerful T-SQL querying capabilities including CTEs, window functions, PIVOT/UNPIVOT operations, recursive queries, dynamic SQL, and advanced analytical functions. This guide covers advanced querying techniques for complex data analysis and manipulation.

## Table of Contents

1. [Common Table Expressions (CTEs)](#common-table-expressions-ctes)
2. [Window Functions](#window-functions)
3. [PIVOT and UNPIVOT](#pivot-and-unpivot)
4. [Recursive Queries](#recursive-queries)
5. [Dynamic SQL](#dynamic-sql)
6. [Full-Text Search](#full-text-search)
7. [JSON and XML Processing](#json-and-xml-processing)
8. [Advanced Analytics](#advanced-analytics)
9. [Query Performance](#query-performance)
10. [Best Practices](#best-practices)

## Common Table Expressions (CTEs)

### Basic CTEs

```sql
-- Simple CTE
WITH SalesSummary AS (
    SELECT
        CustomerID,
        SUM(TotalAmount) AS TotalSales,
        COUNT(OrderID) AS OrderCount
    FROM Orders
    WHERE OrderDate >= '2023-01-01'
    GROUP BY CustomerID
)
SELECT
    c.CustomerName,
    ss.TotalSales,
    ss.OrderCount,
    ss.TotalSales / NULLIF(ss.OrderCount, 0) AS AvgOrderValue
FROM SalesSummary ss
INNER JOIN Customers c ON ss.CustomerID = c.CustomerID
ORDER BY ss.TotalSales DESC;
```

### Recursive CTEs

```sql
-- Organizational hierarchy
WITH EmployeeHierarchy AS (
    -- Anchor member
    SELECT
        EmployeeID,
        ManagerID,
        EmployeeName,
        0 AS Level,
        CAST(EmployeeName AS NVARCHAR(MAX)) AS Path
    FROM Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive member
    SELECT
        e.EmployeeID,
        e.ManagerID,
        e.EmployeeName,
        eh.Level + 1,
        CAST(eh.Path + ' > ' + e.EmployeeName AS NVARCHAR(MAX))
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
)
SELECT * FROM EmployeeHierarchy
ORDER BY Path;
```

### Multiple CTEs

```sql
-- Multiple CTEs with dependencies
WITH MonthlySales AS (
    SELECT
        YEAR(OrderDate) AS SalesYear,
        MONTH(OrderDate) AS SalesMonth,
        SUM(TotalAmount) AS MonthlyTotal
    FROM Orders
    GROUP BY YEAR(OrderDate), MONTH(OrderDate)
),
YearlyGrowth AS (
    SELECT
        SalesYear,
        SalesMonth,
        MonthlyTotal,
        LAG(MonthlyTotal) OVER (ORDER BY SalesYear, SalesMonth) AS PrevMonthTotal,
        (MonthlyTotal - LAG(MonthlyTotal) OVER (ORDER BY SalesYear, SalesMonth))
         / NULLIF(LAG(MonthlyTotal) OVER (ORDER BY SalesYear, SalesMonth), 0) * 100 AS GrowthPercent
    FROM MonthlySales
)
SELECT * FROM YearlyGrowth
WHERE GrowthPercent > 10
ORDER BY SalesYear DESC, SalesMonth DESC;
```

## Window Functions

### Ranking Functions

```sql
-- ROW_NUMBER, RANK, DENSE_RANK
SELECT
    ProductName,
    CategoryName,
    UnitPrice,
    ROW_NUMBER() OVER (PARTITION BY CategoryName ORDER BY UnitPrice DESC) AS RowNum,
    RANK() OVER (PARTITION BY CategoryName ORDER BY UnitPrice DESC) AS RankNum,
    DENSE_RANK() OVER (PARTITION BY CategoryName ORDER BY UnitPrice DESC) AS DenseRankNum
FROM Products p
INNER JOIN Categories c ON p.CategoryID = c.CategoryID;
```

### Aggregate Window Functions

```sql
-- Running totals and moving averages
SELECT
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS UNBOUNDED PRECEDING) AS RunningTotal,
    AVG(TotalAmount) OVER (ORDER BY OrderDate ROWS 2 PRECEDING) AS MovingAvg3,
    SUM(TotalAmount) OVER (PARTITION BY MONTH(OrderDate) ORDER BY OrderDate) AS MonthlyRunningTotal
FROM Orders
ORDER BY OrderDate;
```

### Analytic Functions

```sql
-- NTILE, PERCENTILE, LAG/LEAD
SELECT
    EmployeeName,
    Department,
    Salary,
    NTILE(4) OVER (ORDER BY Salary DESC) AS Quartile,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY Department) AS MedianDeptSalary,
    LAG(Salary) OVER (PARTITION BY Department ORDER BY Salary) AS NextLowerSalary,
    LEAD(Salary) OVER (PARTITION BY Department ORDER BY Salary) AS NextHigherSalary
FROM Employees;
```

### Frame Specifications

```sql
-- Different frame specifications
SELECT
    OrderDate,
    TotalAmount,
    -- Cumulative from start to current
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS UNBOUNDED PRECEDING) AS CumulativeTotal,
    -- Rolling 3-period sum
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS 1 PRECEDING AND 1 FOLLOWING) AS RollingSum3,
    -- Current and previous 2
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS 2 PRECEDING AND CURRENT ROW) AS SumLast3IncludingCurrent,
    -- Range-based (same date values)
    AVG(TotalAmount) OVER (ORDER BY OrderDate RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW) AS WeeklyAvg
FROM Orders;
```

## PIVOT and UNPIVOT

### PIVOT Operations

```sql
-- Basic PIVOT
SELECT *
FROM (
    SELECT
        YEAR(OrderDate) AS OrderYear,
        MONTH(OrderDate) AS OrderMonth,
        TotalAmount
    FROM Orders
) AS SourceTable
PIVOT (
    SUM(TotalAmount)
    FOR OrderMonth IN ([1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12])
) AS PivotTable
ORDER BY OrderYear;
```

### Dynamic PIVOT

```sql
-- Dynamic PIVOT with unknown columns
DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);

SELECT @columns = STRING_AGG(QUOTENAME(MonthName), ', ')
FROM (
    SELECT DISTINCT DATENAME(MONTH, OrderDate) AS MonthName
    FROM Orders
    WHERE YEAR(OrderDate) = 2023
) AS Months;

SET @sql = '
SELECT *
FROM (
    SELECT
        YEAR(OrderDate) AS OrderYear,
        DATENAME(MONTH, OrderDate) AS OrderMonth,
        TotalAmount
    FROM Orders
    WHERE YEAR(OrderDate) = 2023
) AS SourceTable
PIVOT (
    SUM(TotalAmount)
    FOR OrderMonth IN (' + @columns + ')
) AS PivotTable
ORDER BY OrderYear;';

EXEC sp_executesql @sql;
```

### UNPIVOT Operations

```sql
-- Basic UNPIVOT
CREATE TABLE SalesByQuarter (
    ProductName NVARCHAR(100),
    Q1 DECIMAL(10,2),
    Q2 DECIMAL(10,2),
    Q3 DECIMAL(10,2),
    Q4 DECIMAL(10,2)
);

INSERT INTO SalesByQuarter VALUES
('Product A', 1000, 1200, 1100, 1300),
('Product B', 800, 950, 1020, 1100);

-- Unpivot the data
SELECT
    ProductName,
    Quarter,
    SalesAmount
FROM SalesByQuarter
UNPIVOT (
    SalesAmount FOR Quarter IN (Q1, Q2, Q3, Q4)
) AS UnpivotedSales;
```

## Recursive Queries

### Basic Recursive CTE

```sql
-- Bill of Materials (BOM)
CREATE TABLE Parts (
    PartID INT PRIMARY KEY,
    PartName NVARCHAR(100),
    ParentPartID INT NULL,
    Quantity INT DEFAULT 1
);

INSERT INTO Parts VALUES
(1, 'Car', NULL, 1),
(2, 'Engine', 1, 1),
(3, 'Transmission', 1, 1),
(4, 'Piston', 2, 4),
(5, 'Cylinder', 2, 4),
(6, 'Gear', 3, 5);

-- Recursive BOM query
WITH BOM AS (
    -- Anchor: top-level parts
    SELECT
        PartID,
        PartName,
        ParentPartID,
        0 AS Level,
        CAST(PartName AS NVARCHAR(MAX)) AS Path,
        Quantity
    FROM Parts
    WHERE ParentPartID IS NULL

    UNION ALL

    -- Recursive: child parts
    SELECT
        p.PartID,
        p.PartName,
        p.ParentPartID,
        b.Level + 1,
        CAST(b.Path + ' > ' + p.PartName AS NVARCHAR(MAX)),
        p.Quantity
    FROM Parts p
    INNER JOIN BOM b ON p.ParentPartID = b.PartID
)
SELECT * FROM BOM
ORDER BY Path;
```

### Advanced Recursive Patterns

```sql
-- Organizational chart with management chain
WITH ManagementChain AS (
    SELECT
        EmployeeID,
        ManagerID,
        EmployeeName,
        1 AS Level,
        CAST('/' + CAST(EmployeeID AS NVARCHAR(10)) + '/' AS NVARCHAR(MAX)) AS Path
    FROM Employees
    WHERE ManagerID IS NULL

    UNION ALL

    SELECT
        e.EmployeeID,
        e.ManagerID,
        e.EmployeeName,
        mc.Level + 1,
        CAST(mc.Path + CAST(e.EmployeeID AS NVARCHAR(10)) + '/' AS NVARCHAR(MAX))
    FROM Employees e
    INNER JOIN ManagementChain mc ON e.ManagerID = mc.EmployeeID
),
EmployeeCounts AS (
    SELECT
        ManagerID,
        COUNT(*) AS DirectReports
    FROM Employees
    WHERE ManagerID IS NOT NULL
    GROUP BY ManagerID
)
SELECT
    mc.EmployeeName,
    mc.Level,
    mc.DirectReports,
    (
        SELECT COUNT(*)
        FROM ManagementChain sub
        WHERE sub.Path LIKE mc.Path + '%'
    ) AS TotalReports
FROM ManagementChain mc
LEFT JOIN EmployeeCounts ec ON mc.EmployeeID = ec.ManagerID
ORDER BY mc.Path;
```

## Dynamic SQL

### Basic Dynamic SQL

```sql
-- Basic dynamic SQL
DECLARE @sql NVARCHAR(MAX);
DECLARE @tableName NVARCHAR(128) = 'Products';
DECLARE @columnName NVARCHAR(128) = 'UnitPrice';
DECLARE @operator NVARCHAR(10) = '>';
DECLARE @value DECIMAL(10,2) = 50.00;

SET @sql = 'SELECT * FROM ' + QUOTENAME(@tableName) +
           ' WHERE ' + QUOTENAME(@columnName) + ' ' + @operator + ' @val';

EXEC sp_executesql @sql, N'@val DECIMAL(10,2)', @val = @value;
```

### Dynamic PIVOT with Metadata

```sql
-- Dynamic pivot with system catalog
DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);

-- Get column names from system catalog
SELECT @columns = STRING_AGG(QUOTENAME(name), ', ')
FROM sys.columns
WHERE object_id = OBJECT_ID('SalesByMonth')
AND name LIKE 'Month%';

SET @sql = '
SELECT *
FROM (
    SELECT ProductName, MonthName, SalesAmount
    FROM SalesByMonth
    UNPIVOT (SalesAmount FOR MonthName IN (' + @columns + ')) AS unpvt
) AS SourceTable
PIVOT (
    SUM(SalesAmount)
    FOR MonthName IN (' + @columns + ')
) AS PivotTable
ORDER BY ProductName;';

EXEC sp_executesql @sql;
```

### Dynamic Search with Multiple Parameters

```sql
-- Dynamic search stored procedure
CREATE PROCEDURE sp_AdvancedSearch
    @SearchTerm NVARCHAR(1000) = NULL,
    @CategoryID INT = NULL,
    @MinPrice DECIMAL(10,2) = NULL,
    @MaxPrice DECIMAL(10,2) = NULL,
    @InStockOnly BIT = 0,
    @SortBy NVARCHAR(50) = 'ProductName',
    @SortOrder NVARCHAR(4) = 'ASC',
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic search query
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @WhereClause NVARCHAR(MAX) = '';
    DECLARE @OrderBy NVARCHAR(100);

    -- Build WHERE clause
    IF @SearchTerm IS NOT NULL
        SET @WhereClause += ' AND (p.ProductName LIKE @SearchTerm OR p.Description LIKE @SearchTerm)';

    IF @CategoryID IS NOT NULL
        SET @WhereClause += ' AND p.CategoryID = @CategoryID';

    IF @MinPrice IS NOT NULL
        SET @WhereClause += ' AND p.UnitPrice >= @MinPrice';

    IF @MaxPrice IS NOT NULL
        SET @WhereClause += ' AND p.UnitPrice <= @MaxPrice';

    IF @InStockOnly = 1
        SET @WhereClause += ' AND p.UnitsInStock > 0';

    -- Build ORDER BY clause
    SET @OrderBy = CASE @SortBy
        WHEN 'ProductName' THEN 'p.ProductName'
        WHEN 'UnitPrice' THEN 'p.UnitPrice'
        ELSE 'p.ProductName'
    END + ' ' + @SortOrder;

    -- Build main query
    SET @SQL = '
    SELECT
        p.ProductID,
        p.ProductName,
        p.UnitPrice,
        p.UnitsInStock,
        c.CategoryName,
        ROW_NUMBER() OVER (ORDER BY ' + @OrderBy + ') AS RowNum,
        COUNT(*) OVER () AS TotalCount
    FROM Products p
    INNER JOIN Categories c ON p.CategoryID = c.CategoryID
    WHERE 1=1' + @WhereClause + '
    ORDER BY ' + @OrderBy + '
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;';

    -- Execute with parameters
    EXEC sp_executesql @SQL,
        N'@SearchTerm NVARCHAR(1000), @CategoryID INT, @MinPrice DECIMAL(10,2),
         @MaxPrice DECIMAL(10,2), @Offset INT, @PageSize INT',
        @SearchTerm = CASE WHEN @SearchTerm IS NOT NULL THEN '%' + @SearchTerm + '%' END,
        @CategoryID = @CategoryID,
        @MinPrice = @MinPrice,
        @MaxPrice = @MaxPrice,
        @Offset = (@PageNumber - 1) * @PageSize,
        @PageSize = @PageSize;
END;
GO
```

## Full-Text Search

### Full-Text Index Setup

```sql
-- Create full-text catalog
CREATE FULLTEXT CATALOG ProductCatalog
WITH ACCENT_SENSITIVITY = OFF;

-- Create full-text index
CREATE FULLTEXT INDEX ON Products
(
    ProductName Language 1033,    -- English
    Description Language 1033
)
KEY INDEX PK_Products_ProductID
ON ProductCatalog
WITH CHANGE_TRACKING AUTO;

-- Full-text search queries
SELECT
    ProductID,
    ProductName,
    Description
FROM Products
WHERE CONTAINS((ProductName, Description), '"wireless mouse" OR "bluetooth mouse"');

-- FREETEXT for natural language search
SELECT
    ProductID,
    ProductName,
    RANK AS RelevanceRank
FROM Products
INNER JOIN CONTAINSTABLE(Products, (ProductName, Description),
                        'high-performance gaming laptop') AS ft
ON Products.ProductID = ft.[KEY]
ORDER BY ft.RANK DESC;
```

### Advanced Full-Text Features

```sql
-- Proximity searches
SELECT * FROM Products
WHERE CONTAINS(Description, 'NEAR((wireless, bluetooth), 5)');

-- Weighted searches
SELECT * FROM Products
WHERE CONTAINS(Description, 'ISABOUT(laptop weight(.8), performance weight(.4))');

-- Thesaurus searches
SELECT * FROM Products
WHERE FREETEXT(Description, 'automobile car vehicle'); -- Uses thesaurus

-- Statistical queries
SELECT
    display_term,
    document_count,
    rank
FROM sys.dm_fts_index_keywords(DB_ID(), OBJECT_ID('Products'))
ORDER BY rank DESC;
```

## JSON and XML Processing

### JSON Functions

```sql
-- JSON storage and querying
CREATE TABLE UserPreferences (
    UserID INT PRIMARY KEY,
    Preferences NVARCHAR(MAX) CHECK (ISJSON(Preferences) = 1),
    LastModified DATETIME2 DEFAULT GETDATE()
);

-- Insert JSON data
INSERT INTO UserPreferences VALUES
(1, '{"theme": "dark", "language": "en", "notifications": {"email": true, "sms": false}}');

-- Query JSON data
SELECT
    UserID,
    JSON_VALUE(Preferences, '$.theme') AS Theme,
    JSON_VALUE(Preferences, '$.language') AS Language,
    JSON_VALUE(Preferences, '$.notifications.email') AS EmailNotifications
FROM UserPreferences;

-- Modify JSON data
UPDATE UserPreferences
SET Preferences = JSON_MODIFY(Preferences, '$.theme', 'light')
WHERE UserID = 1;

-- JSON path queries
SELECT * FROM UserPreferences
WHERE JSON_VALUE(Preferences, '$.theme') = 'dark';
```

### XML Processing

```sql
-- XML data storage
CREATE TABLE ProductCatalog (
    ProductID INT PRIMARY KEY,
    ProductData XML
);

-- Insert XML data
INSERT INTO ProductCatalog VALUES
(1, '<product>
    <name>Laptop</name>
    <specs>
        <cpu>i7</cpu>
        <ram>16GB</ram>
    </specs>
    <price currency="USD">1299.99</price>
</product>');

-- Query XML data
SELECT
    ProductID,
    ProductData.value('(/product/name)[1]', 'NVARCHAR(100)') AS ProductName,
    ProductData.value('(/product/price)[1]', 'DECIMAL(10,2)') AS Price,
    ProductData.value('(/product/specs/cpu)[1]', 'NVARCHAR(50)') AS CPU
FROM ProductCatalog;

-- XML indexing for performance
CREATE PRIMARY XML INDEX PXML_ProductCatalog_ProductData
ON ProductCatalog (ProductData);

CREATE XML INDEX IXML_ProductCatalog_ProductData_Property
ON ProductCatalog (ProductData)
USING XML INDEX PXML_ProductCatalog_ProductData_Property
FOR PROPERTY;

-- XQuery operations
SELECT ProductID,
       ProductData.query('/product/specs') AS Specifications,
       ProductData.exist('/product[price/@currency="USD"]') AS IsUSD
FROM ProductCatalog;
```

## Advanced Analytics

### Statistical Functions

```sql
-- Statistical aggregations
SELECT
    ProductCategory,
    COUNT(*) AS TotalProducts,
    AVG(UnitPrice) AS AvgPrice,
    STDEV(UnitPrice) AS PriceStdDev,
    VAR(UnitPrice) AS PriceVariance,
    MIN(UnitPrice) AS MinPrice,
    MAX(UnitPrice) AS MaxPrice,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY UnitPrice) AS MedianPrice,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY UnitPrice) AS Price95thPercentile
FROM Products
GROUP BY ProductCategory;
```

### Time Series Analysis

```sql
-- Time series with window functions
WITH MonthlySales AS (
    SELECT
        DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1) AS MonthStart,
        SUM(TotalAmount) AS MonthlySales
    FROM Orders
    GROUP BY YEAR(OrderDate), MONTH(OrderDate)
),
SalesWithTrends AS (
    SELECT
        MonthStart,
        MonthlySales,
        LAG(MonthlySales, 1) OVER (ORDER BY MonthStart) AS PrevMonthSales,
        LAG(MonthlySales, 12) OVER (ORDER BY MonthStart) AS PrevYearSales,
        AVG(MonthlySales) OVER (ORDER BY MonthStart ROWS 11 PRECEDING) AS MovingAvg12
    FROM MonthlySales
)
SELECT
    MonthStart,
    MonthlySales,
    CASE
        WHEN PrevMonthSales > 0 THEN
            (MonthlySales - PrevMonthSales) / PrevMonthSales * 100
        ELSE NULL
    END AS MonthOverMonthGrowth,
    CASE
        WHEN PrevYearSales > 0 THEN
            (MonthlySales - PrevYearSales) / PrevYearSales * 100
        ELSE NULL
    END AS YearOverYearGrowth,
    MonthlySales - MovingAvg12 AS DeviationFromTrend
FROM SalesWithTrends
ORDER BY MonthStart;
```

### Cohort Analysis

```sql
-- Customer cohort analysis
WITH CustomerCohorts AS (
    SELECT
        CustomerID,
        DATEFROMPARTS(YEAR(MIN(OrderDate)), MONTH(MIN(OrderDate)), 1) AS CohortMonth,
        DATEDIFF(MONTH, MIN(OrderDate), MAX(OrderDate)) AS CustomerLifetimeMonths
    FROM Orders
    GROUP BY CustomerID
),
CohortMetrics AS (
    SELECT
        CohortMonth,
        COUNT(*) AS CohortSize,
        AVG(CustomerLifetimeMonths) AS AvgLifetimeMonths,
        SUM(CASE WHEN CustomerLifetimeMonths >= 1 THEN 1 ELSE 0 END) AS Retained1Month,
        SUM(CASE WHEN CustomerLifetimeMonths >= 3 THEN 1 ELSE 0 END) AS Retained3Months,
        SUM(CASE WHEN CustomerLifetimeMonths >= 6 THEN 1 ELSE 0 END) AS Retained6Months,
        SUM(CASE WHEN CustomerLifetimeMonths >= 12 THEN 1 ELSE 0 END) AS Retained12Months
    FROM CustomerCohorts
    GROUP BY CohortMonth
)
SELECT
    CohortMonth,
    CohortSize,
    CAST(Retained1Month AS DECIMAL(10,2)) / NULLIF(CohortSize, 0) * 100 AS Retention1MonthPct,
    CAST(Retained3Months AS DECIMAL(10,2)) / NULLIF(CohortSize, 0) * 100 AS Retention3MonthsPct,
    CAST(Retained6Months AS DECIMAL(10,2)) / NULLIF(CohortSize, 0) * 100 AS Retention6MonthsPct,
    CAST(Retained12Months AS DECIMAL(10,2)) / NULLIF(CohortSize, 0) * 100 AS Retention12MonthsPct,
    AvgLifetimeMonths
FROM CohortMetrics
ORDER BY CohortMonth DESC;
```

## Query Performance

### Execution Plan Analysis

```sql
-- Force detailed execution plan
SET SHOWPLAN_ALL ON;
GO

SELECT * FROM Orders WHERE CustomerID = 12345;
GO

SET SHOWPLAN_ALL OFF;
GO

-- Query execution statistics
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    c.CustomerName,
    COUNT(o.OrderID) AS OrderCount,
    SUM(o.TotalAmount) AS TotalSpent
FROM Customers c
INNER JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE c.Region = 'West'
GROUP BY c.CustomerID, c.CustomerName
HAVING SUM(o.TotalAmount) > 10000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

### Query Store Analysis

```sql
-- Query Store queries for performance analysis
SELECT
    qsq.query_id,
    qsq.object_id,
    qt.query_sql_text,
    qsq.count_compiles,
    qsq.avg_compile_duration,
    qsq.last_compile_duration,
    qsq.avg_bind_duration,
    qsq.avg_bind_cpu_time
FROM sys.query_store_query qsq
INNER JOIN sys.query_store_query_text qt ON qsq.query_text_id = qt.query_text_id
WHERE qsq.last_compile_start_time > DATEADD(DAY, -7, GETDATE())
ORDER BY qsq.avg_compile_duration DESC;

-- Runtime statistics
SELECT
    qsq.query_id,
    qt.query_sql_text,
    qrs.count_executions,
    qrs.avg_duration,
    qrs.avg_cpu_time,
    qrs.avg_logical_io_reads,
    qrs.avg_logical_io_writes,
    qrs.avg_physical_io_reads
FROM sys.query_store_query qsq
INNER JOIN sys.query_store_query_text qt ON qsq.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_runtime_stats qrs ON qsq.query_id = qrs.query_id
WHERE qrs.last_execution_time > DATEADD(DAY, -1, GETDATE())
ORDER BY qrs.avg_duration DESC;
```

### Index Usage Analysis

```sql
-- Index usage statistics
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ps.row_count,
    ps.used_page_count * 8 / 1024.0 AS UsedMB,
    ps.reserved_page_count * 8 / 1024.0 AS ReservedMB,
    CASE WHEN ps.row_count > 0 THEN
        CAST(ps.used_page_count * 8 / 1024.0 / ps.row_count * 1000 AS DECIMAL(10,2))
    ELSE 0 END AS KBPerRow,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup,
    ius.last_user_update
FROM sys.indexes i
INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id
WHERE i.type > 0  -- Exclude heaps
ORDER BY ps.used_page_count DESC;
```

## Best Practices

### Query Optimization Guidelines

1. **Use Appropriate Indexes**: Ensure queries use optimal index strategies
2. **Avoid SELECT *** : Explicitly specify required columns
3. **Use EXISTS instead of COUNT**: For existence checks
4. **Minimize Data Transfer**: Use WHERE clauses effectively
5. **Consider Query Hints**: Only when necessary and well-understood
6. **Monitor Execution Plans**: Regularly review and optimize plans

### CTE Usage Guidelines

1. **Use for Recursive Queries**: Natural fit for hierarchical data
2. **Limit CTE Complexity**: Keep logic readable and maintainable
3. **Consider Materialization**: Use when CTE is referenced multiple times
4. **Watch for Performance**: CTEs can sometimes hurt performance
5. **Use Meaningful Names**: Make CTE purpose clear

### Window Function Best Practices

1. **Choose Correct Framing**: Use appropriate ROWS/RANGE specifications
2. **Order Carefully**: ORDER BY affects window function results
3. **Consider Performance**: Some window functions are expensive
4. **Use for Analytics**: Ideal for running totals, rankings, and trends
5. **Combine with GROUP BY**: For complex analytical queries

### Dynamic SQL Considerations

1. **Validate Input**: Prevent SQL injection attacks
2. **Use Parameterization**: Prefer sp_executesql with parameters
3. **Test Performance**: Dynamic SQL can hurt query plan reuse
4. **Document Thoroughly**: Explain why dynamic SQL is necessary
5. **Consider Alternatives**: Views, stored procedures, or ORMs

### Full-Text Search Guidelines

1. **Choose Stop Words**: Configure appropriate noise words
2. **Use Thesaurus**: Expand search capabilities
3. **Consider Indexing Strategy**: Balance search performance with maintenance
4. **Monitor Fragmentation**: Rebuild indexes regularly
5. **Test Thoroughly**: Validate search results accuracy

This comprehensive guide covers advanced T-SQL querying techniques in SQL Server, providing the foundation for complex data analysis, reporting, and application development.