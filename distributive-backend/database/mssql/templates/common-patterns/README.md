# SQL Server Common Patterns

## Overview

This guide covers common design patterns used in SQL Server database design and development. These patterns help solve recurring problems and improve code maintainability.

## Table of Contents

1. [Audit Pattern](#audit-pattern)
2. [Soft Delete Pattern](#soft-delete-pattern)
3. [Multi-Tenant Pattern](#multi-tenant-pattern)
4. [Versioning Pattern](#versioning-pattern)
5. [Computed Columns Pattern](#computed-columns-pattern)
6. [Temporal Tables Pattern](#temporal-tables-pattern)

## Audit Pattern

### Audit Table

```sql
-- Create audit table
CREATE TABLE AuditLog
(
    AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
    TableName NVARCHAR(255) NOT NULL,
    RecordID NVARCHAR(255),
    Operation NVARCHAR(20) NOT NULL,
    OldValues NVARCHAR(MAX),
    NewValues NVARCHAR(MAX),
    ChangedBy NVARCHAR(255),
    ChangedAt DATETIME2 DEFAULT GETUTCDATE()
);
```

### Audit Trigger

```sql
-- Create audit trigger
CREATE TRIGGER trg_Orders_Audit
ON Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    -- Audit logic (see triggers guide)
END;
```

## Soft Delete Pattern

### Soft Delete Implementation

```sql
-- Add soft delete columns
ALTER TABLE Orders
ADD IsDeleted BIT DEFAULT 0,
    DeletedAt DATETIME2 NULL,
    DeletedBy NVARCHAR(255) NULL;

-- Create filtered index
CREATE INDEX IX_Orders_NotDeleted
ON Orders(UserID, OrderDate)
WHERE IsDeleted = 0;

-- Soft delete procedure
CREATE PROCEDURE sp_SoftDeleteOrder
    @OrderID UNIQUEIDENTIFIER
AS
BEGIN
    UPDATE Orders
    SET IsDeleted = 1,
        DeletedAt = GETUTCDATE(),
        DeletedBy = SYSTEM_USER
    WHERE OrderID = @OrderID;
END;
```

## Multi-Tenant Pattern

### Tenant Isolation

```sql
-- Add tenant column
ALTER TABLE Orders
ADD TenantID INT NOT NULL;

-- Create index
CREATE INDEX IX_Orders_TenantID
ON Orders(TenantID, OrderDate);

-- Row-level security
CREATE FUNCTION dbo.fn_tenant_security_predicate(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT);

CREATE SECURITY POLICY TenantSecurityPolicy
ADD FILTER PREDICATE dbo.fn_tenant_security_predicate(TenantID) ON Orders
WITH (STATE = ON);
```

## Versioning Pattern

### Versioned Table

```sql
-- Add version columns
ALTER TABLE Products
ADD Version INT DEFAULT 1,
    PreviousVersionID UNIQUEIDENTIFIER NULL,
    IsCurrentVersion BIT DEFAULT 1;

-- Versioning trigger
CREATE TRIGGER trg_Products_Version
ON Products
AFTER UPDATE
AS
BEGIN
    -- Create new version
    -- Mark old version as not current
END;
```

## Computed Columns Pattern

### Computed Columns

```sql
-- Persisted computed column
ALTER TABLE Orders
ADD TotalAmount AS (Subtotal + TaxAmount + ShippingAmount - DiscountAmount) PERSISTED;

-- Computed column with function
ALTER TABLE Users
ADD FullName AS (FirstName + ' ' + LastName) PERSISTED;
```

## Temporal Tables Pattern

### System-Versioned Temporal Table

```sql
-- Enable temporal table
ALTER TABLE Orders
ADD ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN DEFAULT GETUTCDATE(),
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo);

ALTER TABLE Orders
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.OrdersHistory));
```

## Best Practices

1. **Use appropriate patterns** for your use case
2. **Document pattern usage** in your codebase
3. **Test patterns** thoroughly before deployment
4. **Consider performance impact** of patterns
5. **Review patterns** regularly for optimization

This guide provides common SQL Server design patterns for building maintainable database solutions.

