# SQL Server Database Normalization

## Overview

Database normalization is the process of organizing data to minimize redundancy and improve data integrity. This guide covers the normalization process in SQL Server, from 1NF through 5NF, with practical examples and performance considerations.

## Table of Contents

1. [Normalization Fundamentals](#normalization-fundamentals)
2. [First Normal Form (1NF)](#first-normal-form-1nf)
3. [Second Normal Form (2NF)](#second-normal-form-2nf)
4. [Third Normal Form (3NF)](#third-normal-form-3nf)
5. [Boyce-Codd Normal Form (BCNF)](#boyce-codd-normal-form-bcnf)
6. [Fourth Normal Form (4NF)](#fourth-normal-form-4nf)
7. [Fifth Normal Form (5NF)](#fifth-normal-form-5nf)
8. [Denormalization](#denormalization)
9. [Performance Considerations](#performance-considerations)
10. [SQL Server Tools](#sql-server-tools)

## Normalization Fundamentals

### What is Normalization?

Normalization is the process of organizing data in a database to:
- **Eliminate redundant data**
- **Ensure data dependencies make sense**
- **Support data integrity**
- **Simplify maintenance operations**

### Normal Forms Hierarchy

- **1NF**: Eliminate repeating groups
- **2NF**: Remove partial dependencies
- **3NF**: Remove transitive dependencies
- **BCNF**: Every determinant is a candidate key
- **4NF**: Eliminate multi-valued dependencies
- **5NF**: Eliminate join dependencies

### Keys and Dependencies

```sql
-- Understanding keys and dependencies
CREATE TABLE Students
(
    StudentID INT PRIMARY KEY,           -- Primary Key
    StudentName NVARCHAR(100),
    CourseID INT,                        -- Foreign Key
    CourseName NVARCHAR(100),            -- Dependent on CourseID
    InstructorID INT,                    -- Foreign Key
    InstructorName NVARCHAR(100),        -- Dependent on InstructorID
    EnrollmentDate DATE,
    Grade CHAR(2)
);
```

## First Normal Form (1NF)

### 1NF Requirements

A table is in 1NF if:
- All columns contain atomic (indivisible) values
- No repeating groups or arrays
- Each column contains values of a single type

### 1NF Violation Example

```sql
-- NOT in 1NF - repeating groups
CREATE TABLE StudentCourses_Bad
(
    StudentID INT,
    StudentName NVARCHAR(100),
    CourseIDs NVARCHAR(500),      -- Comma-separated list
    CourseNames NVARCHAR(1000),   -- Comma-separated list
    PRIMARY KEY (StudentID)
);

-- Sample data with violation
INSERT INTO StudentCourses_Bad VALUES
(1, 'John Doe', 'CS101,MATH101,ENG101', 'Computer Science,Mathematics,English');
```

### Converting to 1NF

```sql
-- 1NF - atomic values, no repeating groups
CREATE TABLE Students
(
    StudentID INT PRIMARY KEY,
    StudentName NVARCHAR(100)
);

CREATE TABLE Courses
(
    CourseID NVARCHAR(10) PRIMARY KEY,
    CourseName NVARCHAR(100),
    Credits INT
);

CREATE TABLE Enrollments
(
    StudentID INT,
    CourseID NVARCHAR(10),
    EnrollmentDate DATE,
    Grade CHAR(2),
    PRIMARY KEY (StudentID, CourseID),
    FOREIGN KEY (StudentID) REFERENCES Students(StudentID),
    FOREIGN KEY (CourseID) REFERENCES Courses(CourseID)
);
```

## Second Normal Form (2NF)

### 2NF Requirements

A table is in 2NF if:
- It is in 1NF
- All non-key attributes are fully functionally dependent on the entire primary key
- No partial dependencies exist

### 2NF Violation Example

```sql
-- NOT in 2NF - partial dependency
CREATE TABLE Enrollments_Bad
(
    StudentID INT,
    CourseID NVARCHAR(10),
    StudentName NVARCHAR(100),    -- Depends only on StudentID
    CourseName NVARCHAR(100),    -- Depends only on CourseID
    InstructorName NVARCHAR(100), -- Depends only on CourseID
    Grade CHAR(2),
    PRIMARY KEY (StudentID, CourseID)
);
```

### Converting to 2NF

```sql
-- 2NF - remove partial dependencies
CREATE TABLE Students
(
    StudentID INT PRIMARY KEY,
    StudentName NVARCHAR(100)
);

CREATE TABLE Courses
(
    CourseID NVARCHAR(10) PRIMARY KEY,
    CourseName NVARCHAR(100),
    InstructorName NVARCHAR(100)
);

CREATE TABLE Enrollments
(
    StudentID INT,
    CourseID NVARCHAR(10),
    EnrollmentDate DATE,
    Grade CHAR(2),
    PRIMARY KEY (StudentID, CourseID),
    FOREIGN KEY (StudentID) REFERENCES Students(StudentID),
    FOREIGN KEY (CourseID) REFERENCES Courses(CourseID)
);
```

## Third Normal Form (3NF)

### 3NF Requirements

A table is in 3NF if:
- It is in 2NF
- No transitive dependencies exist
- Non-key attributes depend only on the primary key

### 3NF Violation Example

```sql
-- NOT in 3NF - transitive dependency
CREATE TABLE Employees_Bad
(
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100),
    DepartmentID INT,
    DepartmentName NVARCHAR(100),    -- Depends on DepartmentID
    Location NVARCHAR(100),          -- Depends on DepartmentID
    Salary DECIMAL(10,2)
);
```

### Converting to 3NF

```sql
-- 3NF - remove transitive dependencies
CREATE TABLE Departments
(
    DepartmentID INT PRIMARY KEY,
    DepartmentName NVARCHAR(100),
    Location NVARCHAR(100)
);

CREATE TABLE Employees
(
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100),
    DepartmentID INT,
    Salary DECIMAL(10,2),
    FOREIGN KEY (DepartmentID) REFERENCES Departments(DepartmentID)
);
```

## Boyce-Codd Normal Form (BCNF)

### BCNF Requirements

A table is in BCNF if:
- It is in 3NF
- Every determinant is a candidate key
- No non-trivial functional dependencies exist where the determinant is not a candidate key

### BCNF Violation Example

```sql
-- NOT in BCNF - determinant is not a candidate key
CREATE TABLE CourseOfferings_Bad
(
    CourseID NVARCHAR(10),
    Semester NVARCHAR(20),
    ProfessorID INT,
    ProfessorName NVARCHAR(100),    -- Depends on ProfessorID
    RoomNumber NVARCHAR(10),        -- Depends on ProfessorID and Semester
    PRIMARY KEY (CourseID, Semester, ProfessorID)
);
-- Here, ProfessorID → ProfessorName is a violation
```

### Converting to BCNF

```sql
-- BCNF - ensure all determinants are candidate keys
CREATE TABLE Professors
(
    ProfessorID INT PRIMARY KEY,
    ProfessorName NVARCHAR(100)
);

CREATE TABLE CourseOfferings
(
    CourseID NVARCHAR(10),
    Semester NVARCHAR(20),
    ProfessorID INT,
    RoomNumber NVARCHAR(10),
    PRIMARY KEY (CourseID, Semester),
    FOREIGN KEY (ProfessorID) REFERENCES Professors(ProfessorID)
);
```

## Fourth Normal Form (4NF)

### 4NF Requirements

A table is in 4NF if:
- It is in BCNF
- No multi-valued dependencies exist
- Independent multi-valued facts are stored in separate tables

### 4NF Violation Example

```sql
-- NOT in 4NF - multi-valued dependency
CREATE TABLE StudentActivities_Bad
(
    StudentID INT,
    Activity NVARCHAR(50),
    Club NVARCHAR(50),
    PRIMARY KEY (StudentID, Activity, Club)
);

-- Violation: StudentID →→ Activity (independent of Club)
-- Violation: StudentID →→ Club (independent of Activity)
```

### Converting to 4NF

```sql
-- 4NF - eliminate multi-valued dependencies
CREATE TABLE StudentActivities
(
    StudentID INT,
    Activity NVARCHAR(50),
    PRIMARY KEY (StudentID, Activity)
);

CREATE TABLE StudentClubs
(
    StudentID INT,
    Club NVARCHAR(50),
    PRIMARY KEY (StudentID, Club)
);
```

## Fifth Normal Form (5NF)

### 5NF Requirements

A table is in 5NF if:
- It is in 4NF
- No join dependencies exist
- Tables cannot be decomposed into smaller tables without losing information

### 5NF Violation Example

```sql
-- NOT in 5NF - join dependency
CREATE TABLE ProjectAssignments_Bad
(
    EmployeeID INT,
    ProjectID INT,
    SkillID INT,
    PRIMARY KEY (EmployeeID, ProjectID, SkillID)
);

-- This might have a join dependency that can be decomposed
```

### Converting to 5NF

```sql
-- 5NF - eliminate join dependencies
CREATE TABLE EmployeeSkills
(
    EmployeeID INT,
    SkillID INT,
    PRIMARY KEY (EmployeeID, SkillID)
);

CREATE TABLE ProjectRequirements
(
    ProjectID INT,
    SkillID INT,
    PRIMARY KEY (ProjectID, SkillID)
);

CREATE TABLE Assignments
(
    EmployeeID INT,
    ProjectID INT,
    PRIMARY KEY (EmployeeID, ProjectID)
);
```

## Denormalization

### When to Denormalize

Denormalization may be appropriate when:
- Query performance is critical
- Read operations vastly outnumber writes
- Data is relatively static
- Hardware resources are limited

### Denormalization Techniques

```sql
-- Denormalized table for reporting
CREATE TABLE SalesSummary
(
    SaleID INT PRIMARY KEY,
    CustomerID INT,
    CustomerName NVARCHAR(100),        -- Denormalized
    ProductID INT,
    ProductName NVARCHAR(100),         -- Denormalized
    CategoryName NVARCHAR(50),         -- Denormalized
    SaleDate DATE,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    TotalAmount DECIMAL(10,2),
    SalespersonName NVARCHAR(100)      -- Denormalized
);

-- Maintain denormalized data with triggers
CREATE TRIGGER TR_UpdateSalesSummary
ON Sales
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Refresh materialized summary (simplified)
    TRUNCATE TABLE SalesSummary;

    INSERT INTO SalesSummary
    SELECT
        s.SaleID,
        s.CustomerID,
        c.CustomerName,
        s.ProductID,
        p.ProductName,
        cat.CategoryName,
        s.SaleDate,
        s.Quantity,
        s.UnitPrice,
        s.Quantity * s.UnitPrice AS TotalAmount,
        sp.SalespersonName
    FROM Sales s
    INNER JOIN Customers c ON s.CustomerID = c.CustomerID
    INNER JOIN Products p ON s.ProductID = p.ProductID
    INNER JOIN Categories cat ON p.CategoryID = cat.CategoryID
    INNER JOIN Salespersons sp ON s.SalespersonID = sp.SalespersonID;
END;
GO

-- Indexed views for denormalization
CREATE VIEW vw_ProductSales WITH SCHEMABINDING
AS
SELECT
    p.ProductID,
    p.ProductName,
    SUM(od.OrderQty * od.UnitPrice) AS TotalSales,
    SUM(od.OrderQty) AS TotalQuantity,
    COUNT_BIG(*) AS OrderCount
FROM Sales.SalesOrderDetail od
INNER JOIN Production.Product p ON od.ProductID = p.ProductID
GROUP BY p.ProductID, p.ProductName;

-- Create unique clustered index to materialize the view
CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSales
ON vw_ProductSales (ProductID);

-- Create additional indexes for performance
CREATE INDEX IX_vw_ProductSales_ProductName
ON vw_ProductSales (ProductName);
```

## Performance Considerations

### Normalization vs Performance

```sql
-- Normalized design (better for OLTP)
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    OrderDate DATETIME2,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

CREATE TABLE OrderDetails
(
    OrderID INT,
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    PRIMARY KEY (OrderID, ProductID),
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- Denormalized design (better for reporting)
CREATE TABLE OrderSummary
(
    OrderID INT PRIMARY KEY,
    CustomerName NVARCHAR(100),    -- Denormalized
    OrderDate DATETIME2,
    TotalAmount DECIMAL(10,2),     -- Computed
    ItemCount INT                  -- Computed
);
```

### Indexing Strategy for Normalized Databases

```sql
-- Foreign key indexes for performance
CREATE INDEX IX_Orders_CustomerID ON Orders (CustomerID);
CREATE INDEX IX_OrderDetails_OrderID ON OrderDetails (OrderID);
CREATE INDEX IX_OrderDetails_ProductID ON OrderDetails (ProductID);

-- Composite indexes for common queries
CREATE INDEX IX_OrderDetails_Order_Product
ON OrderDetails (OrderID, ProductID);

-- Covering indexes for performance
CREATE INDEX IX_OrderDetails_Covering
ON OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
INCLUDE (LineTotal);
```

### Query Optimization Techniques

```sql
-- Efficient normalized queries
SELECT
    o.OrderID,
    c.CustomerName,
    o.OrderDate,
    SUM(od.Quantity * od.UnitPrice) AS TotalAmount
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '2023-01-01'
GROUP BY o.OrderID, c.CustomerName, o.OrderDate;

-- Pre-computed aggregates
CREATE TABLE OrderTotals
(
    OrderID INT PRIMARY KEY,
    TotalAmount DECIMAL(10,2),
    ItemCount INT,
    LastModified DATETIME2 DEFAULT GETDATE()
);

-- Maintain totals with triggers
CREATE TRIGGER TR_MaintainOrderTotals
ON OrderDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE ot
    SET ot.TotalAmount = (
            SELECT SUM(od.Quantity * od.UnitPrice)
            FROM OrderDetails od
            WHERE od.OrderID = ot.OrderID
        ),
        ot.ItemCount = (
            SELECT COUNT(*)
            FROM OrderDetails od
            WHERE od.OrderID = ot.OrderID
        ),
        ot.LastModified = GETDATE()
    FROM OrderTotals ot
    WHERE ot.OrderID IN (
        SELECT DISTINCT OrderID FROM inserted
        UNION
        SELECT DISTINCT OrderID FROM deleted
    );
END;
GO
```

## SQL Server Tools

### Database Diagram Tool

```sql
-- SQL Server Management Studio (SSMS) can help with:
-- 1. Database diagrams
-- 2. Schema comparison
-- 3. Refactoring tools
-- 4. Dependency analysis

-- Generate database diagram programmatically
SELECT
    t.name AS TableName,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length,
    c.is_nullable,
    CASE WHEN pk.column_id IS NOT NULL THEN 'PK' ELSE '' END AS KeyType,
    CASE WHEN fk.parent_column_id IS NOT NULL THEN 'FK' ELSE '' END AS ForeignKey
FROM sys.tables t
INNER JOIN sys.columns c ON t.object_id = c.object_id
INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
LEFT JOIN (
    SELECT ic.object_id, ic.column_id
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    WHERE i.is_primary_key = 1
) pk ON t.object_id = pk.object_id AND c.column_id = pk.column_id
LEFT JOIN sys.foreign_key_columns fk ON t.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
ORDER BY t.name, c.column_id;
```

### Normalization Analysis Queries

```sql
-- Find functional dependencies
SELECT
    'Potential FD: ' + c1.name + ' -> ' + c2.name AS Dependency,
    COUNT(DISTINCT c1_value) AS DistinctValues,
    COUNT(*) AS TotalRows
FROM (
    SELECT
        CAST([Column1] AS NVARCHAR(MAX)) AS c1_value,
        CAST([Column2] AS NVARCHAR(MAX)) AS c2_value
    FROM YourTable
) AS deps
GROUP BY c1_value, c2_value
HAVING COUNT(DISTINCT c2_value) = 1
ORDER BY DistinctValues DESC;

-- Check for transitive dependencies
WITH ColumnStats AS (
    SELECT
        c.name AS ColumnName,
        COUNT(DISTINCT CAST(c.value AS NVARCHAR(MAX))) AS DistinctValues
    FROM YourTable
    CROSS APPLY (VALUES (Column1), (Column2), (Column3)) AS c(value)
    GROUP BY c.name
)
SELECT
    pk.ColumnName AS PrimaryKey,
    dep.ColumnName AS DependentColumn,
    cs.DistinctValues
FROM PrimaryKeyColumns pk
CROSS JOIN DependentColumns dep
INNER JOIN ColumnStats cs ON dep.ColumnName = cs.ColumnName
WHERE cs.DistinctValues < (SELECT COUNT(*) FROM YourTable);
```

### Extended Properties for Documentation

```sql
-- Add extended properties for documentation
EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Table normalized to 3NF to eliminate transitive dependencies',
    @level0type = N'SCHEMA',
    @level0name = N'dbo',
    @level1type = N'TABLE',
    @level1name = N'Employees';

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Normalized department information to eliminate transitive dependency',
    @level0type = N'SCHEMA',
    @level0name = N'dbo',
    @level1type = N'TABLE',
    @level1name = N'Departments';

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Foreign key relationship to Departments table',
    @level0type = N'SCHEMA',
    @level0name = N'dbo',
    @level1type = N'TABLE',
    @level1name = N'Employees',
    @level2type = N'COLUMN',
    @level2name = N'DepartmentID';
```

## Best Practices

### Normalization Guidelines

1. **Start with 3NF**: Most applications should target 3NF as a minimum
2. **Consider BCNF**: For complex schemas with multiple candidate keys
3. **Evaluate 4NF/5NF**: Only when multi-valued or join dependencies exist
4. **Balance with Performance**: Denormalize strategically when necessary
5. **Document Decisions**: Record why certain normal forms weren't applied

### Common Pitfalls

1. **Over-Normalization**: Don't normalize to extreme forms unnecessarily
2. **Under-Normalization**: Avoid excessive denormalization
3. **Premature Optimization**: Don't denormalize without performance justification
4. **Ignoring Business Rules**: Normalization should reflect business requirements

### Maintenance Considerations

1. **Regular Audits**: Periodically review normalization levels
2. **Performance Monitoring**: Watch for query performance degradation
3. **Change Management**: Plan for schema changes during normalization
4. **Testing**: Thoroughly test after normalization changes

This comprehensive guide provides the foundation for understanding and applying database normalization principles in SQL Server environments, balancing theoretical correctness with practical performance requirements.