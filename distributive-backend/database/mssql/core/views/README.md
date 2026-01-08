# SQL Server Views

## Overview

Views in SQL Server are virtual tables that represent the result of a stored query. They provide a way to simplify complex queries, enforce security, and abstract the underlying table structure.

## Table of Contents

1. [View Types](#view-types)
2. [Creating Views](#creating-views)
3. [Indexed Views](#indexed-views)
4. [Partitioned Views](#partitioned-views)
5. [View Management](#view-management)
6. [Security with Views](#security-with-views)
7. [Enterprise Patterns](#enterprise-patterns)

## View Types

### Standard Views

Virtual tables that execute the underlying query each time they are accessed.

### Indexed Views

Materialized views with a unique clustered index for improved performance.

### Partitioned Views

Views that combine data from multiple tables with the same structure.

## Creating Views

### Basic View

```sql
-- Simple view
CREATE VIEW vw_ActiveUsers
AS
SELECT 
    UserID,
    Email,
    FirstName + ' ' + LastName AS FullName,
    CreatedAt
FROM Users
WHERE IsActive = 1;
GO

-- Query view
SELECT * FROM vw_ActiveUsers;
```

### View with Joins

```sql
-- View with joins
CREATE VIEW vw_OrderDetails
AS
SELECT 
    o.OrderID,
    o.OrderNumber,
    o.OrderDate,
    o.TotalAmount,
    o.Status,
    u.Email AS CustomerEmail,
    u.FirstName + ' ' + u.LastName AS CustomerName,
    COUNT(oi.OrderItemID) AS ItemCount
FROM Orders o
INNER JOIN Users u ON o.UserID = u.UserID
LEFT JOIN OrderItems oi ON o.OrderID = oi.OrderID
GROUP BY 
    o.OrderID,
    o.OrderNumber,
    o.OrderDate,
    o.TotalAmount,
    o.Status,
    u.Email,
    u.FirstName,
    u.LastName;
GO
```

### View with Computed Columns

```sql
-- View with computed columns
CREATE VIEW vw_ProductSummary
AS
SELECT 
    ProductID,
    ProductName,
    BasePrice,
    SalePrice,
    CASE 
        WHEN SalePrice IS NOT NULL THEN SalePrice
        ELSE BasePrice
    END AS CurrentPrice,
    StockQuantity,
    CASE 
        WHEN StockQuantity = 0 THEN 'Out of Stock'
        WHEN StockQuantity < 10 THEN 'Low Stock'
        ELSE 'In Stock'
    END AS StockStatus,
    BasePrice * 0.08 AS EstimatedTax
FROM Products
WHERE IsActive = 1;
GO
```

## Indexed Views

### Creating Indexed View

```sql
-- Create view with SCHEMABINDING
CREATE VIEW vw_OrderTotals
WITH SCHEMABINDING
AS
SELECT 
    UserID,
    COUNT_BIG(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSpent,
    AVG(TotalAmount) AS AverageOrderValue,
    MAX(OrderDate) AS LastOrderDate
FROM dbo.Orders
GROUP BY UserID;
GO

-- Create unique clustered index
CREATE UNIQUE CLUSTERED INDEX IX_vw_OrderTotals_UserID
ON vw_OrderTotals(UserID);
GO

-- Create non-clustered indexes
CREATE NONCLUSTERED INDEX IX_vw_OrderTotals_TotalSpent
ON vw_OrderTotals(TotalSpent DESC);
GO
```

### Indexed View Requirements

* View must use SCHEMABINDING
* Must use COUNT_BIG(*) instead of COUNT(*)
* Cannot use OUTER JOIN, TOP, DISTINCT, UNION
* Base tables must be in same database
* Must reference tables with two-part names (schema.table)

## Partitioned Views

### Creating Partitioned View

```sql
-- Create partitioned view across multiple tables
CREATE VIEW vw_Orders_All
AS
SELECT * FROM Orders_2024_Q1
UNION ALL
SELECT * FROM Orders_2024_Q2
UNION ALL
SELECT * FROM Orders_2024_Q3
UNION ALL
SELECT * FROM Orders_2024_Q4;
GO
```

## View Management

### Altering Views

```sql
-- Alter view definition
ALTER VIEW vw_ActiveUsers
AS
SELECT 
    UserID,
    Email,
    FirstName + ' ' + LastName AS FullName,
    CreatedAt,
    LastLoginAt  -- Added column
FROM Users
WHERE IsActive = 1;
GO
```

### Dropping Views

```sql
-- Drop view
DROP VIEW vw_ActiveUsers;

-- Drop view if exists (SQL Server 2016+)
DROP VIEW IF EXISTS vw_ActiveUsers;
```

### Viewing View Definitions

```sql
-- Get view definition
SELECT OBJECT_DEFINITION(OBJECT_ID('vw_ActiveUsers')) AS ViewDefinition;

-- List all views
SELECT 
    name AS ViewName,
    create_date AS CreatedDate,
    modify_date AS ModifiedDate
FROM sys.views
WHERE schema_id = SCHEMA_ID('dbo');

-- List views with their columns
SELECT 
    v.name AS ViewName,
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length AS MaxLength
FROM sys.views v
INNER JOIN sys.columns c ON v.object_id = c.object_id
INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
ORDER BY v.name, c.column_id;
```

## Security with Views

### Row-Level Security

```sql
-- View with row-level security
CREATE VIEW vw_UserOrders
AS
SELECT 
    o.OrderID,
    o.OrderNumber,
    o.TotalAmount,
    o.OrderDate
FROM Orders o
WHERE o.UserID = SUSER_SNAME();  -- Only show current user's orders
GO

-- Grant access to view
GRANT SELECT ON vw_UserOrders TO [AppUser];
```

### Column-Level Security

```sql
-- View hiding sensitive columns
CREATE VIEW vw_Users_Public
AS
SELECT 
    UserID,
    FirstName + ' ' + LastName AS FullName,
    Email,  -- Exclude password, SSN, etc.
    CreatedAt
FROM Users
WHERE IsActive = 1;
GO
```

## Enterprise Patterns

### Reporting View

```sql
-- Comprehensive reporting view
CREATE VIEW vw_SalesReport
AS
SELECT 
    YEAR(o.OrderDate) AS OrderYear,
    MONTH(o.OrderDate) AS OrderMonth,
    u.Email AS CustomerEmail,
    COUNT(DISTINCT o.OrderID) AS OrderCount,
    SUM(o.TotalAmount) AS TotalRevenue,
    AVG(o.TotalAmount) AS AverageOrderValue,
    SUM(oi.Quantity) AS TotalItemsSold,
    COUNT(DISTINCT oi.ProductID) AS UniqueProductsSold
FROM Orders o
INNER JOIN Users u ON o.UserID = u.UserID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
WHERE o.Status = 'Completed'
GROUP BY 
    YEAR(o.OrderDate),
    MONTH(o.OrderDate),
    u.Email;
GO
```

### Aggregation View

```sql
-- Pre-aggregated view for performance
CREATE VIEW vw_ProductSales
WITH SCHEMABINDING
AS
SELECT 
    p.ProductID,
    p.ProductName,
    COUNT_BIG(DISTINCT o.OrderID) AS OrderCount,
    SUM(oi.Quantity) AS TotalQuantitySold,
    SUM(oi.TotalPrice) AS TotalRevenue,
    AVG(oi.UnitPrice) AS AverageSellingPrice
FROM dbo.Products p
INNER JOIN dbo.OrderItems oi ON p.ProductID = oi.ProductID
INNER JOIN dbo.Orders o ON oi.OrderID = o.OrderID
WHERE o.Status = 'Completed'
GROUP BY p.ProductID, p.ProductName;
GO

-- Create indexed view
CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSales_ProductID
ON vw_ProductSales(ProductID);
GO
```

### Denormalized View

```sql
-- Denormalized view for read performance
CREATE VIEW vw_OrderDetails_Denormalized
AS
SELECT 
    o.OrderID,
    o.OrderNumber,
    o.OrderDate,
    o.TotalAmount,
    o.Status,
    -- User details (denormalized)
    u.UserID,
    u.Email AS CustomerEmail,
    u.FirstName + ' ' + u.LastName AS CustomerName,
    -- Product details (denormalized)
    oi.ProductID,
    oi.ProductName,
    oi.Quantity,
    oi.UnitPrice,
    oi.TotalPrice
FROM Orders o
INNER JOIN Users u ON o.UserID = u.UserID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID;
GO
```

## Best Practices

1. **Use views for complex queries** to simplify access
2. **Create indexed views** for frequently accessed aggregations
3. **Use SCHEMABINDING** for indexed views and stability
4. **Document view purposes** and usage patterns
5. **Consider performance** - views execute underlying queries
6. **Use views for security** to hide sensitive data
7. **Avoid nested views** deeply (can impact performance)
8. **Test view performance** with execution plans
9. **Keep views focused** on specific use cases
10. **Review and optimize** views regularly

This guide provides comprehensive SQL Server view patterns for simplifying queries and improving security.

