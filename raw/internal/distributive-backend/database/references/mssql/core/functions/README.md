# SQL Server Functions

## Overview

SQL Server functions (user-defined functions) are powerful tools for encapsulating business logic, improving performance, and maintaining data consistency. Functions can be scalar-valued or table-valued, and can be written in T-SQL or CLR.

## Table of Contents

1. [Function Types](#function-types)
2. [Scalar-Valued Functions](#scalar-valued-functions)
3. [Table-Valued Functions](#table-valued-functions)
4. [Inline Table-Valued Functions](#inline-table-valued-functions)
5. [Function Parameters](#function-parameters)
6. [Error Handling](#error-handling)
7. [Performance Considerations](#performance-considerations)
8. [Security and Permissions](#security-and-permissions)
9. [Enterprise Patterns](#enterprise-patterns)

## Function Types

### Scalar-Valued Functions

Return a single value of a specific data type.

```sql
-- Basic scalar function
CREATE FUNCTION dbo.GetFullName
(
    @FirstName NVARCHAR(100),
    @LastName NVARCHAR(100)
)
RETURNS NVARCHAR(201)
AS
BEGIN
    RETURN @FirstName + ' ' + @LastName;
END;
GO

-- Usage
SELECT dbo.GetFullName('John', 'Doe') AS FullName;
```

### Table-Valued Functions

Return a table result set.

```sql
-- Inline table-valued function
CREATE FUNCTION dbo.GetUserOrders
(
    @UserID UNIQUEIDENTIFIER
)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderNumber, TotalAmount, CreatedAt
    FROM Orders
    WHERE UserID = @UserID
);
GO

-- Usage
SELECT * FROM dbo.GetUserOrders('user-guid-here');
```

## Scalar-Valued Functions

### Basic Scalar Functions

```sql
-- Calculate total with tax
CREATE FUNCTION dbo.CalculateTotalWithTax
(
    @Subtotal DECIMAL(10,2),
    @TaxRate DECIMAL(5,4)
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN @Subtotal * (1 + @TaxRate);
END;
GO

-- Format phone number
CREATE FUNCTION dbo.FormatPhoneNumber
(
    @PhoneNumber NVARCHAR(20)
)
RETURNS NVARCHAR(20)
AS
BEGIN
    DECLARE @Formatted NVARCHAR(20);
    
    -- Remove non-numeric characters
    SET @Formatted = REPLACE(REPLACE(REPLACE(REPLACE(@PhoneNumber, '(', ''), ')', ''), '-', ''), ' ', '');
    
    -- Format as (XXX) XXX-XXXX
    IF LEN(@Formatted) = 10
        SET @Formatted = '(' + SUBSTRING(@Formatted, 1, 3) + ') ' + 
                         SUBSTRING(@Formatted, 4, 3) + '-' + 
                         SUBSTRING(@Formatted, 7, 4);
    
    RETURN @Formatted;
END;
GO
```

### Deterministic Functions

```sql
-- Deterministic function (can be indexed)
CREATE FUNCTION dbo.GetOrderYear
(
    @OrderDate DATETIME2
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN YEAR(@OrderDate);
END;
GO

-- Use in computed column
ALTER TABLE Orders
ADD OrderYear AS dbo.GetOrderYear(OrderDate) PERSISTED;
```

## Table-Valued Functions

### Inline Table-Valued Functions

```sql
-- Inline table-valued function (better performance)
CREATE FUNCTION dbo.GetActiveProducts
(
    @CategoryID INT = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT ProductID, ProductName, BasePrice, StockQuantity
    FROM Products
    WHERE IsActive = 1
      AND (@CategoryID IS NULL OR CategoryID = @CategoryID)
);
GO

-- Usage
SELECT * FROM dbo.GetActiveProducts(1);
SELECT * FROM dbo.GetActiveProducts();  -- All active products
```

### Multi-Statement Table-Valued Functions

```sql
-- Multi-statement table-valued function
CREATE FUNCTION dbo.GetProductSalesSummary
(
    @ProductID UNIQUEIDENTIFIER,
    @StartDate DATETIME2,
    @EndDate DATETIME2
)
RETURNS @Summary TABLE
(
    ProductID UNIQUEIDENTIFIER,
    ProductName NVARCHAR(255),
    TotalSales INT,
    TotalRevenue DECIMAL(12,2),
    AverageOrderValue DECIMAL(10,2)
)
AS
BEGIN
    INSERT INTO @Summary
    SELECT
        p.ProductID,
        p.ProductName,
        COUNT(oi.OrderItemID) AS TotalSales,
        SUM(oi.TotalPrice) AS TotalRevenue,
        AVG(oi.TotalPrice) AS AverageOrderValue
    FROM Products p
    INNER JOIN OrderItems oi ON p.ProductID = oi.ProductID
    INNER JOIN Orders o ON oi.OrderID = o.OrderID
    WHERE p.ProductID = @ProductID
      AND o.OrderDate BETWEEN @StartDate AND @EndDate
    GROUP BY p.ProductID, p.ProductName;
    
    RETURN;
END;
GO
```

## Function Parameters

### Default Parameters

```sql
-- Function with default parameters
CREATE FUNCTION dbo.GetOrders
(
    @UserID UNIQUEIDENTIFIER = NULL,
    @Status NVARCHAR(20) = NULL,
    @StartDate DATETIME2 = NULL,
    @EndDate DATETIME2 = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderNumber, TotalAmount, Status, OrderDate
    FROM Orders
    WHERE (@UserID IS NULL OR UserID = @UserID)
      AND (@Status IS NULL OR Status = @Status)
      AND (@StartDate IS NULL OR OrderDate >= @StartDate)
      AND (@EndDate IS NULL OR OrderDate <= @EndDate)
);
GO
```

### Table-Valued Parameters

```sql
-- Create user-defined table type
CREATE TYPE dbo.OrderIDList AS TABLE
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY
);
GO

-- Function using table-valued parameter
CREATE FUNCTION dbo.GetOrderDetails
(
    @OrderIDs dbo.OrderIDList READONLY
)
RETURNS TABLE
AS
RETURN
(
    SELECT o.OrderID, o.OrderNumber, o.TotalAmount, oi.ProductName, oi.Quantity
    FROM Orders o
    INNER JOIN @OrderIDs ids ON o.OrderID = ids.OrderID
    INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
);
GO
```

## Error Handling

### Try-Catch in Functions

```sql
-- Function with error handling
CREATE FUNCTION dbo.SafeDivide
(
    @Numerator DECIMAL(10,2),
    @Denominator DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @Result DECIMAL(10,2);
    
    BEGIN TRY
        IF @Denominator = 0
            RETURN NULL;
        
        SET @Result = @Numerator / @Denominator;
        RETURN @Result;
    END TRY
    BEGIN CATCH
        RETURN NULL;
    END CATCH
END;
GO
```

## Performance Considerations

### Inline vs Multi-Statement

```sql
-- Prefer inline table-valued functions (better performance)
CREATE FUNCTION dbo.GetUserOrders_Inline
(
    @UserID UNIQUEIDENTIFIER
)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderNumber, TotalAmount
    FROM Orders
    WHERE UserID = @UserID
);
GO

-- Multi-statement functions are less efficient
CREATE FUNCTION dbo.GetUserOrders_MultiStatement
(
    @UserID UNIQUEIDENTIFIER
)
RETURNS @Results TABLE
(
    OrderID UNIQUEIDENTIFIER,
    OrderNumber NVARCHAR(50),
    TotalAmount DECIMAL(12,2)
)
AS
BEGIN
    INSERT INTO @Results
    SELECT OrderID, OrderNumber, TotalAmount
    FROM Orders
    WHERE UserID = @UserID;
    
    RETURN;
END;
GO
```

### Function Execution Context

```sql
-- Use SCHEMABINDING for better performance
CREATE FUNCTION dbo.CalculateTotal
(
    @Subtotal DECIMAL(10,2),
    @Tax DECIMAL(10,2),
    @Shipping DECIMAL(10,2)
)
RETURNS DECIMAL(12,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN @Subtotal + @Tax + @Shipping;
END;
GO
```

## Security and Permissions

### Granting Permissions

```sql
-- Grant execute permission
GRANT EXECUTE ON dbo.GetUserOrders TO [AppUser];

-- Grant execute on schema
GRANT EXECUTE ON SCHEMA::dbo TO [AppUser];
```

### Function Ownership

```sql
-- Change function owner
ALTER AUTHORIZATION ON dbo.GetUserOrders TO [dbo];
```

## Enterprise Patterns

### Audit Function

```sql
-- Function to get audit trail
CREATE FUNCTION dbo.GetAuditTrail
(
    @TableName NVARCHAR(255),
    @RecordID UNIQUEIDENTIFIER
)
RETURNS TABLE
AS
RETURN
(
    SELECT AuditID, Operation, OldValues, NewValues, ChangedBy, ChangedAt
    FROM AuditLog
    WHERE TableName = @TableName
      AND RecordID = @RecordID
    ORDER BY ChangedAt DESC
);
GO
```

### Validation Functions

```sql
-- Email validation function
CREATE FUNCTION dbo.IsValidEmail
(
    @Email NVARCHAR(255)
)
RETURNS BIT
AS
BEGIN
    IF @Email LIKE '%_@_%._%'
        RETURN 1;
    RETURN 0;
END;
GO

-- Use in check constraint
ALTER TABLE Users
ADD CONSTRAINT CK_Users_Email CHECK (dbo.IsValidEmail(Email) = 1);
```

## Best Practices

1. **Use inline table-valued functions** when possible for better performance
2. **Use SCHEMABINDING** for deterministic functions
3. **Avoid functions in WHERE clauses** that prevent index usage
4. **Use table-valued parameters** for multiple values
5. **Handle errors gracefully** in functions
6. **Document function purposes** and parameters
7. **Test functions** with various input scenarios
8. **Consider performance impact** of scalar functions in queries
9. **Use appropriate return types** for functions
10. **Grant minimal permissions** needed for function execution

This guide provides comprehensive SQL Server function patterns for encapsulating business logic and improving code reusability.

