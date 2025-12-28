# SQL Server Constraints

## Overview

Constraints in SQL Server are rules enforced by the database engine to maintain data integrity. They prevent invalid data from being inserted or updated, ensuring the consistency and reliability of your database.

## Table of Contents

1. [Primary Key Constraints](#primary-key-constraints)
2. [Foreign Key Constraints](#foreign-key-constraints)
3. [Unique Constraints](#unique-constraints)
4. [Check Constraints](#check-constraints)
5. [Not-Null Constraints](#not-null-constraints)
6. [Default Constraints](#default-constraints)
7. [Constraint Management](#constraint-management)
8. [Enterprise Patterns](#enterprise-patterns)

## Primary Key Constraints

### Basic Primary Keys

```sql
-- Single column primary key with IDENTITY
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL,
    Email NVARCHAR(255) NOT NULL
);

-- Single column primary key with UNIQUEIDENTIFIER
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductName NVARCHAR(255) NOT NULL,
    SKU NVARCHAR(50) NOT NULL
);

-- Composite primary key
CREATE TABLE OrderItems
(
    OrderID UNIQUEIDENTIFIER NOT NULL,
    ProductID UNIQUEIDENTIFIER NOT NULL,
    Quantity INT NOT NULL,
    PRIMARY KEY (OrderID, ProductID)
);

-- Named primary key constraint
CREATE TABLE Categories
(
    CategoryID INT IDENTITY(1,1),
    CategoryName NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Categories PRIMARY KEY (CategoryID)
);
```

### Primary Key Best Practices

```sql
-- Use IDENTITY for sequential IDs
CREATE TABLE Orders
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderNumber AS ('ORD-' + CAST(OrderID AS NVARCHAR(10))) PERSISTED,
    OrderDate DATETIME2 DEFAULT GETUTCDATE()
);

-- Use UNIQUEIDENTIFIER for distributed systems
CREATE TABLE Sessions
(
    SessionID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);
```

## Foreign Key Constraints

### Basic Foreign Keys

```sql
-- Foreign key with default actions
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID UNIQUEIDENTIFIER NOT NULL,
    OrderDate DATETIME2 DEFAULT GETUTCDATE(),
    CONSTRAINT FK_Orders_Users
        FOREIGN KEY (UserID)
        REFERENCES Users(UserID)
);

-- Foreign key with CASCADE delete
CREATE TABLE OrderItems
(
    OrderItemID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderID UNIQUEIDENTIFIER NOT NULL,
    ProductID UNIQUEIDENTIFIER NOT NULL,
    Quantity INT NOT NULL,
    CONSTRAINT FK_OrderItems_Orders
        FOREIGN KEY (OrderID)
        REFERENCES Orders(OrderID)
        ON DELETE CASCADE,
    CONSTRAINT FK_OrderItems_Products
        FOREIGN KEY (ProductID)
        REFERENCES Products(ProductID)
        ON DELETE RESTRICT
);

-- Foreign key with SET NULL
CREATE TABLE Employees
(
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    ManagerID INT NULL,
    EmployeeName NVARCHAR(100) NOT NULL,
    CONSTRAINT FK_Employees_Manager
        FOREIGN KEY (ManagerID)
        REFERENCES Employees(EmployeeID)
        ON DELETE SET NULL
);
```

### Self-Referencing Foreign Keys

```sql
-- Hierarchical data structure
CREATE TABLE Categories
(
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    ParentCategoryID INT NULL,
    CategoryName NVARCHAR(100) NOT NULL,
    CONSTRAINT FK_Categories_Parent
        FOREIGN KEY (ParentCategoryID)
        REFERENCES Categories(CategoryID)
        ON DELETE NO ACTION
);
```

## Unique Constraints

### Basic Unique Constraints

```sql
-- Single column unique constraint
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) NOT NULL,
    CONSTRAINT UQ_Users_Email UNIQUE (Email)
);

-- Multiple column unique constraint
CREATE TABLE UserRoles
(
    UserID INT NOT NULL,
    RoleID INT NOT NULL,
    CONSTRAINT UQ_UserRoles_User_Role UNIQUE (UserID, RoleID)
);

-- Unique constraint with WHERE clause (filtered unique index)
CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_ActiveEmail
ON Users(Email)
WHERE IsActive = 1;
```

## Check Constraints

### Basic Check Constraints

```sql
-- Single column check constraint
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductName NVARCHAR(255) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    StockQuantity INT NOT NULL,
    CONSTRAINT CK_Products_Price CHECK (Price > 0),
    CONSTRAINT CK_Products_StockQuantity CHECK (StockQuantity >= 0)
);

-- Multiple column check constraint
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderDate DATETIME2 NOT NULL,
    ShipDate DATETIME2 NULL,
    CONSTRAINT CK_Orders_ShipDate CHECK (ShipDate IS NULL OR ShipDate >= OrderDate)
);

-- Check constraint with function
CREATE TABLE Employees
(
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) NOT NULL,
    CONSTRAINT CK_Employees_Email CHECK (Email LIKE '%_@_%._%')
);
```

## Not-Null Constraints

### Basic Not-Null Constraints

```sql
-- Not-null constraint
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) NOT NULL,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Phone NVARCHAR(20) NULL  -- Optional field
);

-- Adding NOT NULL to existing column
ALTER TABLE Users
ALTER COLUMN Email NVARCHAR(255) NOT NULL;
```

## Default Constraints

### Basic Default Constraints

```sql
-- Default constraint with function
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderDate DATETIME2 DEFAULT GETUTCDATE(),
    Status NVARCHAR(20) DEFAULT 'Pending',
    CreatedBy NVARCHAR(100) DEFAULT SYSTEM_USER
);

-- Default constraint with constant
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Named default constraint
CREATE TABLE Users
(
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    CreatedAt DATETIME2,
    CONSTRAINT DF_Users_CreatedAt DEFAULT GETUTCDATE() FOR CreatedAt
);
```

## Constraint Management

### Adding Constraints

```sql
-- Add primary key constraint
ALTER TABLE Categories
ADD CONSTRAINT PK_Categories PRIMARY KEY (CategoryID);

-- Add foreign key constraint
ALTER TABLE Orders
ADD CONSTRAINT FK_Orders_Users
    FOREIGN KEY (UserID)
    REFERENCES Users(UserID);

-- Add check constraint
ALTER TABLE Products
ADD CONSTRAINT CK_Products_Price CHECK (Price > 0);

-- Add unique constraint
ALTER TABLE Users
ADD CONSTRAINT UQ_Users_Email UNIQUE (Email);
```

### Dropping Constraints

```sql
-- Drop constraint by name
ALTER TABLE Products
DROP CONSTRAINT CK_Products_Price;

-- Drop primary key constraint
ALTER TABLE Categories
DROP CONSTRAINT PK_Categories;

-- Drop foreign key constraint
ALTER TABLE Orders
DROP CONSTRAINT FK_Orders_Users;
```

### Disabling and Enabling Constraints

```sql
-- Disable constraint (use with caution)
ALTER TABLE Orders
NOCHECK CONSTRAINT FK_Orders_Users;

-- Re-enable constraint
ALTER TABLE Orders
CHECK CONSTRAINT FK_Orders_Users;

-- Disable all constraints on table
ALTER TABLE Orders
NOCHECK CONSTRAINT ALL;

-- Re-enable all constraints
ALTER TABLE Orders
CHECK CONSTRAINT ALL;
```

### Querying Constraints

```sql
-- List all constraints on a table
SELECT
    CONSTRAINT_NAME,
    CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'Orders';

-- List foreign key constraints
SELECT
    fk.name AS ForeignKeyName,
    tp.name AS ParentTable,
    cp.name AS ParentColumn,
    tr.name AS ReferencedTable,
    cr.name AS ReferencedColumn
FROM sys.foreign_keys fk
INNER JOIN sys.tables tp ON fk.parent_object_id = tp.object_id
INNER JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns cp ON fkc.parent_object_id = cp.object_id AND fkc.parent_column_id = cp.column_id
INNER JOIN sys.columns cr ON fkc.referenced_object_id = cr.object_id AND fkc.referenced_column_id = cr.column_id
WHERE tp.name = 'Orders';
```

## Enterprise Patterns

### Soft Delete Pattern

```sql
-- Soft delete with check constraint
CREATE TABLE Products
(
    ProductID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    ProductName NVARCHAR(255) NOT NULL,
    IsDeleted BIT DEFAULT 0,
    DeletedAt DATETIME2 NULL,
    CONSTRAINT CK_Products_SoftDelete CHECK (
        (IsDeleted = 0 AND DeletedAt IS NULL) OR
        (IsDeleted = 1 AND DeletedAt IS NOT NULL)
    )
);
```

### Audit Pattern

```sql
-- Audit columns with defaults
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderNumber NVARCHAR(50) NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    CreatedBy NVARCHAR(100) DEFAULT SYSTEM_USER,
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedBy NVARCHAR(100) DEFAULT SYSTEM_USER,
    CONSTRAINT CK_Orders_Audit CHECK (
        UpdatedAt >= CreatedAt
    )
);
```

### Multi-Tenant Pattern

```sql
-- Multi-tenant with check constraint
CREATE TABLE Orders
(
    OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    TenantID INT NOT NULL,
    OrderNumber NVARCHAR(50) NOT NULL,
    CONSTRAINT FK_Orders_Tenants
        FOREIGN KEY (TenantID)
        REFERENCES Tenants(TenantID),
    CONSTRAINT UQ_Orders_Tenant_OrderNumber UNIQUE (TenantID, OrderNumber)
);
```

## Best Practices

1. **Name constraints explicitly** for easier management
2. **Use appropriate constraint types** for data integrity
3. **Consider performance impact** of foreign keys
4. **Use CASCADE carefully** to avoid unintended deletions
5. **Validate data** before adding constraints to existing tables
6. **Document constraint purposes** in comments
7. **Monitor constraint violations** in application logs
8. **Use filtered unique indexes** for conditional uniqueness
9. **Consider soft deletes** instead of CASCADE DELETE
10. **Test constraint behavior** in development first

This guide provides comprehensive SQL Server constraint patterns for maintaining data integrity and enforcing business rules.

