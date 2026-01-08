# SQL Server Database Normalization

## Overview

Database normalization is the process of organizing data in a database to eliminate redundancy and improve data integrity. This guide covers normalization principles from 1NF through 5NF with SQL Server-specific implementations.

## Normalization Forms

### First Normal Form (1NF)

**Rules**:
1. All attributes must be atomic (no repeating groups)
2. All attributes must contain only single values
3. Each record must be uniquely identifiable

**Example**:

```sql
-- BAD: Violates 1NF (repeating groups, multivalued attributes)
CREATE TABLE CustomerOrders
(
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(255),
    Order1ID INT,
    Order1Date DATE,
    Order2ID INT,
    Order2Date DATE,
    PreferredCategories NVARCHAR(MAX)  -- Comma-separated values
);

-- GOOD: 1NF compliant
CREATE TABLE Customers
(
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(255) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL
);

CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

CREATE TABLE CustomerPreferences
(
    PreferenceID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    Category NVARCHAR(100) NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);
```

### Second Normal Form (2NF)

**Rules**:
1. Must be in 1NF
2. All non-key attributes must be fully functionally dependent on the primary key

**Example**:

```sql
-- BAD: Violates 2NF (partial dependency)
CREATE TABLE OrderItems
(
    OrderItemID INT PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    ProductName NVARCHAR(255),  -- Depends on ProductID, not OrderItemID
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL
);

-- GOOD: 2NF compliant
CREATE TABLE OrderItems
(
    OrderItemID INT PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

CREATE TABLE Products
(
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(255) NOT NULL,
    CategoryID INT NOT NULL
);
```

### Third Normal Form (3NF)

**Rules**:
1. Must be in 2NF
2. No transitive dependencies (non-key attributes must not depend on other non-key attributes)

**Example**:

```sql
-- BAD: Violates 3NF (transitive dependency)
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(255),  -- Depends on CustomerID
    CustomerEmail NVARCHAR(255), -- Depends on CustomerID
    OrderDate DATE NOT NULL
);

-- GOOD: 3NF compliant
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

CREATE TABLE Customers
(
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(255) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL
);
```

### Boyce-Codd Normal Form (BCNF)

**Rules**:
1. Must be in 3NF
2. Every determinant must be a candidate key

**Example**:

```sql
-- BAD: Violates BCNF
CREATE TABLE CourseInstructors
(
    CourseID INT,
    InstructorID INT,
    RoomID INT,
    PRIMARY KEY (CourseID, InstructorID),
    -- Assumption: Each course has one room, but instructor can teach multiple courses
    -- RoomID depends on CourseID, but CourseID is not a candidate key
);

-- GOOD: BCNF compliant
CREATE TABLE Courses
(
    CourseID INT PRIMARY KEY,
    RoomID INT NOT NULL,
    FOREIGN KEY (RoomID) REFERENCES Rooms(RoomID)
);

CREATE TABLE CourseInstructors
(
    CourseID INT NOT NULL,
    InstructorID INT NOT NULL,
    PRIMARY KEY (CourseID, InstructorID),
    FOREIGN KEY (CourseID) REFERENCES Courses(CourseID),
    FOREIGN KEY (InstructorID) REFERENCES Instructors(InstructorID)
);
```

### Fourth Normal Form (4NF)

**Rules**:
1. Must be in BCNF
2. No multi-valued dependencies

**Example**:

```sql
-- BAD: Violates 4NF (multi-valued dependency)
CREATE TABLE EmployeeSkills
(
    EmployeeID INT,
    Skill NVARCHAR(100),
    Language NVARCHAR(50),
    PRIMARY KEY (EmployeeID, Skill, Language)
    -- Skills and Languages are independent multi-valued attributes
);

-- GOOD: 4NF compliant
CREATE TABLE EmployeeSkills
(
    EmployeeID INT NOT NULL,
    Skill NVARCHAR(100) NOT NULL,
    PRIMARY KEY (EmployeeID, Skill),
    FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID)
);

CREATE TABLE EmployeeLanguages
(
    EmployeeID INT NOT NULL,
    Language NVARCHAR(50) NOT NULL,
    PRIMARY KEY (EmployeeID, Language),
    FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID)
);
```

### Fifth Normal Form (5NF)

**Rules**:
1. Must be in 4NF
2. No join dependencies

**Example**:

```sql
-- BAD: Violates 5NF (join dependency)
CREATE TABLE ProjectEmployeeSkill
(
    ProjectID INT,
    EmployeeID INT,
    Skill NVARCHAR(100),
    PRIMARY KEY (ProjectID, EmployeeID, Skill)
    -- Can be decomposed into three binary relationships
);

-- GOOD: 5NF compliant
CREATE TABLE ProjectEmployees
(
    ProjectID INT NOT NULL,
    EmployeeID INT NOT NULL,
    PRIMARY KEY (ProjectID, EmployeeID)
);

CREATE TABLE EmployeeSkills
(
    EmployeeID INT NOT NULL,
    Skill NVARCHAR(100) NOT NULL,
    PRIMARY KEY (EmployeeID, Skill)
);

CREATE TABLE ProjectSkills
(
    ProjectID INT NOT NULL,
    Skill NVARCHAR(100) NOT NULL,
    PRIMARY KEY (ProjectID, Skill)
);
```

## Denormalization Strategies

### When to Denormalize

- **Read Performance**: Frequent reads, infrequent writes
- **Reporting**: Complex analytical queries
- **Data Warehousing**: Star schema designs
- **Caching**: Frequently accessed computed values

### Common Denormalization Patterns

#### 1. Redundant Columns

```sql
-- Denormalized: Store computed values
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(255),  -- Denormalized from Customers table
    OrderTotal DECIMAL(10,2),
    ItemCount INT,  -- Denormalized count
    LastItemAddedDate DATETIME2  -- Denormalized for quick access
);
```

#### 2. Summary Tables

```sql
-- Denormalized summary table
CREATE TABLE CustomerOrderSummary
(
    CustomerID INT PRIMARY KEY,
    TotalOrders INT NOT NULL,
    TotalSpent DECIMAL(10,2) NOT NULL,
    AverageOrderValue DECIMAL(10,2) NOT NULL,
    LastOrderDate DATETIME2,
    LastUpdated DATETIME2 DEFAULT GETUTCDATE()
);
```

#### 3. Flattened Hierarchies

```sql
-- Denormalized: Store hierarchy path
CREATE TABLE Categories
(
    CategoryID INT PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    ParentCategoryID INT NULL,
    CategoryPath NVARCHAR(500),  -- Denormalized: "/1/2/3"
    CategoryLevel INT,  -- Denormalized level
    FOREIGN KEY (ParentCategoryID) REFERENCES Categories(CategoryID)
);
```

## Best Practices

### 1. Normalize First

- Start with normalized design
- Denormalize only when performance requires it
- Document denormalization decisions

### 2. Balance Normalization and Performance

- Higher normalization = better data integrity, more joins
- Lower normalization = better performance, potential redundancy
- Find the right balance for your use case

### 3. Use Computed Columns

```sql
-- Use computed columns for denormalized values
CREATE TABLE Orders
(
    OrderID INT PRIMARY KEY,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    TotalAmount AS (Quantity * UnitPrice) PERSISTED
);
```

### 4. Maintain Denormalized Data

- Use triggers to maintain denormalized columns
- Use stored procedures for updates
- Consider Change Data Capture (CDC) for synchronization

This comprehensive guide provides enterprise-grade normalization patterns for SQL Server with practical examples and denormalization strategies where appropriate.

