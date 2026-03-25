# SQL Server Querying

## Overview

This guide covers comprehensive SQL Server querying techniques, including SELECT statements, joins, subqueries, CTEs, window functions, and performance optimization strategies.

## Table of Contents

1. [Basic SELECT Queries](#basic-select-queries)
2. [Joins](#joins)
3. [Subqueries](#subqueries)
4. [Common Table Expressions (CTEs)](#common-table-expressions-ctes)
5. [Window Functions](#window-functions)
6. [Aggregations](#aggregations)
7. [Set Operations](#set-operations)
8. [Performance Optimization](#performance-optimization)

## Basic SELECT Queries

### Simple SELECT

```sql
-- Select all columns
SELECT * FROM Users;

-- Select specific columns
SELECT UserID, Email, FirstName, LastName
FROM Users;

-- Select with aliases
SELECT 
    UserID AS ID,
    Email AS EmailAddress,
    FirstName + ' ' + LastName AS FullName
FROM Users;
```

### WHERE Clause

```sql
-- Equality
SELECT * FROM Orders WHERE Status = 'Pending';

-- Comparison operators
SELECT * FROM Products WHERE Price > 100;

-- IN clause
SELECT * FROM Orders WHERE Status IN ('Pending', 'Processing');

-- LIKE pattern matching
SELECT * FROM Users WHERE Email LIKE '%@example.com';

-- NULL handling
SELECT * FROM Users WHERE Phone IS NULL;
SELECT * FROM Users WHERE Phone IS NOT NULL;
```

### ORDER BY

```sql
-- Single column sort
SELECT * FROM Orders ORDER BY OrderDate DESC;

-- Multiple column sort
SELECT * FROM Orders 
ORDER BY Status ASC, OrderDate DESC;

-- Using column position
SELECT OrderID, OrderDate, TotalAmount
FROM Orders
ORDER BY 2 DESC;  -- Sort by OrderDate
```

### TOP and OFFSET-FETCH

```sql
-- TOP N rows
SELECT TOP 10 * FROM Orders ORDER BY OrderDate DESC;

-- TOP with PERCENT
SELECT TOP 10 PERCENT * FROM Orders ORDER BY TotalAmount DESC;

-- OFFSET-FETCH (SQL Server 2012+)
SELECT * FROM Orders
ORDER BY OrderDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

-- Pagination
SELECT * FROM Orders
ORDER BY OrderDate DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;  -- Page 3 (rows 21-30)
```

## Joins

### INNER JOIN

```sql
-- Basic inner join
SELECT 
    o.OrderID,
    o.OrderNumber,
    u.Email,
    u.FirstName + ' ' + u.LastName AS CustomerName
FROM Orders o
INNER JOIN Users u ON o.UserID = u.UserID;

-- Multiple inner joins
SELECT 
    o.OrderNumber,
    u.Email,
    p.ProductName,
    oi.Quantity,
    oi.UnitPrice
FROM Orders o
INNER JOIN Users u ON o.UserID = u.UserID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
INNER JOIN Products p ON oi.ProductID = p.ProductID;
```

### LEFT JOIN

```sql
-- Left join (all orders, even without users)
SELECT 
    o.OrderID,
    o.OrderNumber,
    u.Email
FROM Orders o
LEFT JOIN Users u ON o.UserID = u.UserID;

-- Left join with WHERE (find orders without users)
SELECT 
    o.OrderID,
    o.OrderNumber
FROM Orders o
LEFT JOIN Users u ON o.UserID = u.UserID
WHERE u.UserID IS NULL;
```

### RIGHT JOIN

```sql
-- Right join (all users, even without orders)
SELECT 
    u.UserID,
    u.Email,
    o.OrderID
FROM Orders o
RIGHT JOIN Users u ON o.UserID = u.UserID;
```

### FULL OUTER JOIN

```sql
-- Full outer join
SELECT 
    u.UserID,
    u.Email,
    o.OrderID,
    o.OrderNumber
FROM Users u
FULL OUTER JOIN Orders o ON u.UserID = o.UserID;
```

### CROSS JOIN

```sql
-- Cross join (Cartesian product)
SELECT 
    p.ProductName,
    c.CategoryName
FROM Products p
CROSS JOIN Categories c;
```

## Subqueries

### Scalar Subqueries

```sql
-- Subquery in SELECT
SELECT 
    OrderID,
    OrderNumber,
    TotalAmount,
    (SELECT AVG(TotalAmount) FROM Orders) AS AverageOrderAmount
FROM Orders;

-- Subquery in WHERE
SELECT * FROM Products
WHERE Price > (SELECT AVG(Price) FROM Products);
```

### Correlated Subqueries

```sql
-- Correlated subquery
SELECT 
    o.OrderID,
    o.OrderNumber,
    o.TotalAmount,
    (SELECT COUNT(*) 
     FROM OrderItems oi 
     WHERE oi.OrderID = o.OrderID) AS ItemCount
FROM Orders o;
```

### EXISTS

```sql
-- EXISTS subquery
SELECT * FROM Users u
WHERE EXISTS (
    SELECT 1 FROM Orders o 
    WHERE o.UserID = u.UserID
);

-- NOT EXISTS
SELECT * FROM Users u
WHERE NOT EXISTS (
    SELECT 1 FROM Orders o 
    WHERE o.UserID = u.UserID
);
```

## Common Table Expressions (CTEs)

### Basic CTE

```sql
-- Simple CTE
WITH ActiveUsers AS
(
    SELECT UserID, Email, FirstName, LastName
    FROM Users
    WHERE IsActive = 1
)
SELECT * FROM ActiveUsers;
```

### Recursive CTE

```sql
-- Recursive CTE for hierarchy
WITH CategoryHierarchy AS
(
    -- Anchor member
    SELECT CategoryID, CategoryName, ParentCategoryID, 0 AS Level
    FROM Categories
    WHERE ParentCategoryID IS NULL
    
    UNION ALL
    
    -- Recursive member
    SELECT c.CategoryID, c.CategoryName, c.ParentCategoryID, ch.Level + 1
    FROM Categories c
    INNER JOIN CategoryHierarchy ch ON c.ParentCategoryID = ch.CategoryID
)
SELECT * FROM CategoryHierarchy
ORDER BY Level, CategoryName;
```

### Multiple CTEs

```sql
-- Multiple CTEs
WITH 
OrderSummary AS
(
    SELECT UserID, COUNT(*) AS OrderCount, SUM(TotalAmount) AS TotalSpent
    FROM Orders
    GROUP BY UserID
),
UserDetails AS
(
    SELECT UserID, Email, FirstName + ' ' + LastName AS FullName
    FROM Users
)
SELECT 
    ud.Email,
    ud.FullName,
    os.OrderCount,
    os.TotalSpent
FROM UserDetails ud
INNER JOIN OrderSummary os ON ud.UserID = os.UserID;
```

## Window Functions

### ROW_NUMBER

```sql
-- Row number
SELECT 
    OrderID,
    OrderNumber,
    TotalAmount,
    ROW_NUMBER() OVER (ORDER BY TotalAmount DESC) AS Rank
FROM Orders;
```

### RANK and DENSE_RANK

```sql
-- Rank with gaps
SELECT 
    ProductID,
    ProductName,
    Price,
    RANK() OVER (ORDER BY Price DESC) AS PriceRank
FROM Products;

-- Dense rank without gaps
SELECT 
    ProductID,
    ProductName,
    Price,
    DENSE_RANK() OVER (ORDER BY Price DESC) AS PriceRank
FROM Products;
```

### PARTITION BY

```sql
-- Window function with partition
SELECT 
    OrderID,
    UserID,
    OrderNumber,
    TotalAmount,
    ROW_NUMBER() OVER (PARTITION BY UserID ORDER BY OrderDate DESC) AS UserOrderRank
FROM Orders;
```

### Aggregate Window Functions

```sql
-- Running total
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (ORDER BY OrderDate) AS RunningTotal
FROM Orders;

-- Moving average
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    AVG(TotalAmount) OVER (
        ORDER BY OrderDate 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAverage
FROM Orders;
```

## Aggregations

### GROUP BY

```sql
-- Basic aggregation
SELECT 
    Status,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalRevenue,
    AVG(TotalAmount) AS AverageOrderValue
FROM Orders
GROUP BY Status;

-- Multiple grouping columns
SELECT 
    YEAR(OrderDate) AS OrderYear,
    MONTH(OrderDate) AS OrderMonth,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalRevenue
FROM Orders
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY OrderYear, OrderMonth;
```

### HAVING

```sql
-- Filter aggregated results
SELECT 
    UserID,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSpent
FROM Orders
GROUP BY UserID
HAVING COUNT(*) > 5 AND SUM(TotalAmount) > 1000;
```

## Set Operations

### UNION

```sql
-- Union (distinct)
SELECT Email FROM Users
UNION
SELECT Email FROM Administrators;

-- Union all (includes duplicates)
SELECT ProductName FROM Products
UNION ALL
SELECT ProductName FROM ArchivedProducts;
```

### INTERSECT

```sql
-- Intersect
SELECT UserID FROM Users
INTERSECT
SELECT UserID FROM Orders;
```

### EXCEPT

```sql
-- Except (difference)
SELECT UserID FROM Users
EXCEPT
SELECT UserID FROM Orders;  -- Users without orders
```

## Performance Optimization

### Query Hints

```sql
-- Force index usage
SELECT * FROM Orders WITH (INDEX(IX_Orders_UserID))
WHERE UserID = 'user-guid';

-- Force join order
SELECT * FROM Orders o
INNER LOOP JOIN Users u ON o.UserID = u.UserID;
```

### Execution Plans

```sql
-- View execution plan
SET STATISTICS PROFILE ON;
SELECT * FROM Orders WHERE UserID = 'user-guid';
SET STATISTICS PROFILE OFF;

-- Include actual execution plan in SSMS
-- Or use: SET SHOWPLAN_ALL ON;
```

## Best Practices

1. **Use appropriate joins** for your data relationships
2. **Avoid SELECT *** in production queries
3. **Use CTEs** for complex queries to improve readability
4. **Leverage window functions** for analytical queries
5. **Optimize subqueries** - consider rewriting as joins
6. **Use appropriate aggregation** functions
7. **Test query performance** with execution plans
8. **Index foreign keys** for join performance
9. **Use pagination** for large result sets
10. **Monitor query performance** regularly

This guide provides comprehensive SQL Server querying techniques for efficient data retrieval and analysis.

