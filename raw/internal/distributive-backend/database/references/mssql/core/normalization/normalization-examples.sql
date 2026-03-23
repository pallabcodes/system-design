-- SQL Server Database Normalization Examples
-- Comprehensive examples of 1NF, 2NF, 3NF, BCNF, 4NF, and 5NF normalization
-- With practical examples and denormalization strategies where appropriate

-- ===========================================
-- UNNORMALIZED DATA (0NF) - PROBLEMATIC
-- ===========================================

-- Bad: Everything in one table with repeating groups and multivalued attributes
CREATE TABLE CustomerOrdersDenormalized
(
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(255),
    CustomerEmail NVARCHAR(255),
    CustomerPhone NVARCHAR(20),
    
    -- Order information (repeating group)
    Order1ID INT,
    Order1Date DATE,
    Order1Total DECIMAL(10,2),
    Order1Item1Name NVARCHAR(255),
    Order1Item1Quantity INT,
    Order1Item1Price DECIMAL(8,2),
    Order1Item2Name NVARCHAR(255),
    Order1Item2Quantity INT,
    Order1Item2Price DECIMAL(8,2),
    
    Order2ID INT,
    Order2Date DATE,
    Order2Total DECIMAL(10,2),
    
    -- Customer preferences (multivalued)
    PreferredCategories NVARCHAR(MAX),  -- Comma-separated: "electronics,books,clothing"
    PreferredBrands NVARCHAR(MAX),     -- Comma-separated: "apple,samsung,nike"
    NotificationMethods NVARCHAR(500),  -- Comma-separated: "email,sms,push"
    
    -- Address information (composite attribute)
    HomeAddressStreet NVARCHAR(255),
    HomeAddressCity NVARCHAR(100),
    HomeAddressState NVARCHAR(50),
    HomeAddressZip NVARCHAR(20),
    WorkAddressStreet NVARCHAR(255),
    WorkAddressCity NVARCHAR(100),
    WorkAddressState NVARCHAR(50),
    WorkAddressZip NVARCHAR(20)
);

-- ===========================================
-- FIRST NORMAL FORM (1NF)
-- ===========================================
-- Rules:
-- 1. All attributes must be atomic (no repeating groups)
-- 2. All attributes must contain only single values
-- 3. Each record must be uniquely identifiable

-- Good: Separate tables for customers, orders, and order items
CREATE TABLE Customers1NF
(
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(255) NOT NULL,
    CustomerEmail NVARCHAR(255) UNIQUE NOT NULL,
    CustomerPhone NVARCHAR(20),
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE Orders1NF
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    OrderTotal DECIMAL(10,2) NOT NULL,
    OrderStatus NVARCHAR(20) DEFAULT 'Pending'
        CHECK (OrderStatus IN ('Pending', 'Processing', 'Shipped', 'Delivered')),
    
    FOREIGN KEY (CustomerID) REFERENCES Customers1NF(CustomerID),
    
    INDEX IX_Orders_Customer (CustomerID),
    INDEX IX_Orders_Date (OrderDate),
    INDEX IX_Orders_Status (OrderStatus)
);

CREATE TABLE OrderItems1NF
(
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ItemName NVARCHAR(255) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(8,2) NOT NULL,
    
    FOREIGN KEY (OrderID) REFERENCES Orders1NF(OrderID) ON DELETE CASCADE,
    
    INDEX IX_OrderItems_Order (OrderID)
);

-- ===========================================
-- SECOND NORMAL FORM (2NF)
-- ===========================================
-- Rules:
-- 1. Must be in 1NF
-- 2. All non-key attributes must be fully functionally dependent on the primary key
--    (No partial dependencies)

-- Bad: Violates 2NF (partial dependency)
-- OrderItemID determines Quantity and UnitPrice
-- But ProductName depends on ProductID, not OrderItemID
CREATE TABLE OrderItems2NF_Bad
(
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    ProductName NVARCHAR(255),  -- Partial dependency: depends on ProductID
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(8,2) NOT NULL,
    
    FOREIGN KEY (OrderID) REFERENCES Orders1NF(OrderID)
);

-- Good: 2NF compliant
CREATE TABLE Products2NF
(
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(255) NOT NULL,
    CategoryID INT NOT NULL,
    BasePrice DECIMAL(8,2) NOT NULL
);

CREATE TABLE OrderItems2NF
(
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(8,2) NOT NULL,  -- Price at time of order
    
    FOREIGN KEY (OrderID) REFERENCES Orders1NF(OrderID) ON DELETE CASCADE,
    FOREIGN KEY (ProductID) REFERENCES Products2NF(ProductID),
    
    INDEX IX_OrderItems_Order (OrderID),
    INDEX IX_OrderItems_Product (ProductID)
);

-- ===========================================
-- THIRD NORMAL FORM (3NF)
-- ===========================================
-- Rules:
-- 1. Must be in 2NF
-- 2. No transitive dependencies (non-key attributes must not depend on other non-key attributes)

-- Bad: Violates 3NF (transitive dependency)
-- OrderID determines CustomerID
-- CustomerID determines CustomerName and CustomerEmail
-- Therefore, CustomerName and CustomerEmail transitively depend on OrderID
CREATE TABLE Orders3NF_Bad
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(255),  -- Transitive dependency
    CustomerEmail NVARCHAR(255), -- Transitive dependency
    OrderDate DATE NOT NULL,
    OrderTotal DECIMAL(10,2) NOT NULL
);

-- Good: 3NF compliant
CREATE TABLE Customers3NF
(
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(255) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    Phone NVARCHAR(20),
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE Orders3NF
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    OrderTotal DECIMAL(10,2) NOT NULL,
    
    FOREIGN KEY (CustomerID) REFERENCES Customers3NF(CustomerID),
    
    INDEX IX_Orders_Customer (CustomerID),
    INDEX IX_Orders_Date (OrderDate)
);

-- ===========================================
-- BOYCE-CODD NORMAL FORM (BCNF)
-- ===========================================
-- Rules:
-- 1. Must be in 3NF
-- 2. Every determinant must be a candidate key

-- Bad: Violates BCNF
-- CourseID + InstructorID determines RoomID
-- But CourseID alone determines RoomID (each course has one room)
-- CourseID is a determinant but not a candidate key
CREATE TABLE CourseInstructorsBCNF_Bad
(
    CourseID INT,
    InstructorID INT,
    RoomID INT,
    PRIMARY KEY (CourseID, InstructorID)
    -- Assumption: Each course has one room, but instructor can teach multiple courses
    -- RoomID depends on CourseID, but CourseID is not a candidate key
);

-- Good: BCNF compliant
CREATE TABLE RoomsBCNF
(
    RoomID INT IDENTITY(1,1) PRIMARY KEY,
    RoomNumber NVARCHAR(20) UNIQUE NOT NULL,
    Capacity INT NOT NULL
);

CREATE TABLE CoursesBCNF
(
    CourseID INT IDENTITY(1,1) PRIMARY KEY,
    CourseName NVARCHAR(255) NOT NULL,
    RoomID INT NOT NULL,
    FOREIGN KEY (RoomID) REFERENCES RoomsBCNF(RoomID)
);

CREATE TABLE InstructorsBCNF
(
    InstructorID INT IDENTITY(1,1) PRIMARY KEY,
    InstructorName NVARCHAR(255) NOT NULL,
    DepartmentID INT NOT NULL
);

CREATE TABLE CourseInstructorsBCNF
(
    CourseID INT NOT NULL,
    InstructorID INT NOT NULL,
    PRIMARY KEY (CourseID, InstructorID),
    FOREIGN KEY (CourseID) REFERENCES CoursesBCNF(CourseID),
    FOREIGN KEY (InstructorID) REFERENCES InstructorsBCNF(InstructorID)
);

-- ===========================================
-- FOURTH NORMAL FORM (4NF)
-- ===========================================
-- Rules:
-- 1. Must be in BCNF
-- 2. No multi-valued dependencies

-- Bad: Violates 4NF (multi-valued dependency)
-- EmployeeID ->-> Skill (multi-valued)
-- EmployeeID ->-> Language (multi-valued)
-- Skills and Languages are independent
CREATE TABLE EmployeeSkills4NF_Bad
(
    EmployeeID INT,
    Skill NVARCHAR(100),
    Language NVARCHAR(50),
    PRIMARY KEY (EmployeeID, Skill, Language)
    -- Skills and Languages are independent multi-valued attributes
);

-- Good: 4NF compliant
CREATE TABLE Employees4NF
(
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeName NVARCHAR(255) NOT NULL,
    DepartmentID INT NOT NULL
);

CREATE TABLE EmployeeSkills4NF
(
    EmployeeID INT NOT NULL,
    Skill NVARCHAR(100) NOT NULL,
    ProficiencyLevel INT CHECK (ProficiencyLevel BETWEEN 1 AND 5),
    PRIMARY KEY (EmployeeID, Skill),
    FOREIGN KEY (EmployeeID) REFERENCES Employees4NF(EmployeeID)
);

CREATE TABLE EmployeeLanguages4NF
(
    EmployeeID INT NOT NULL,
    Language NVARCHAR(50) NOT NULL,
    FluencyLevel NVARCHAR(20) CHECK (FluencyLevel IN ('Basic', 'Intermediate', 'Advanced', 'Native')),
    PRIMARY KEY (EmployeeID, Language),
    FOREIGN KEY (EmployeeID) REFERENCES Employees4NF(EmployeeID)
);

-- ===========================================
-- FIFTH NORMAL FORM (5NF)
-- ===========================================
-- Rules:
-- 1. Must be in 4NF
-- 2. No join dependencies

-- Bad: Violates 5NF (join dependency)
-- Can be decomposed into three binary relationships:
-- Project-Employee, Employee-Skill, Project-Skill
CREATE TABLE ProjectEmployeeSkill5NF_Bad
(
    ProjectID INT,
    EmployeeID INT,
    Skill NVARCHAR(100),
    PRIMARY KEY (ProjectID, EmployeeID, Skill)
    -- Can be decomposed into three binary relationships
);

-- Good: 5NF compliant
CREATE TABLE Projects5NF
(
    ProjectID INT IDENTITY(1,1) PRIMARY KEY,
    ProjectName NVARCHAR(255) NOT NULL,
    StartDate DATE,
    EndDate DATE
);

CREATE TABLE ProjectEmployees5NF
(
    ProjectID INT NOT NULL,
    EmployeeID INT NOT NULL,
    Role NVARCHAR(50),
    PRIMARY KEY (ProjectID, EmployeeID),
    FOREIGN KEY (ProjectID) REFERENCES Projects5NF(ProjectID),
    FOREIGN KEY (EmployeeID) REFERENCES Employees4NF(EmployeeID)
);

CREATE TABLE EmployeeSkills5NF
(
    EmployeeID INT NOT NULL,
    Skill NVARCHAR(100) NOT NULL,
    PRIMARY KEY (EmployeeID, Skill),
    FOREIGN KEY (EmployeeID) REFERENCES Employees4NF(EmployeeID)
);

CREATE TABLE ProjectSkills5NF
(
    ProjectID INT NOT NULL,
    Skill NVARCHAR(100) NOT NULL,
    RequiredLevel INT,
    PRIMARY KEY (ProjectID, Skill),
    FOREIGN KEY (ProjectID) REFERENCES Projects5NF(ProjectID)
);

-- ===========================================
-- DENORMALIZATION EXAMPLES
-- ===========================================

-- Denormalized: Store computed and redundant values for performance
CREATE TABLE OrdersDenormalized
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(255),  -- Denormalized from Customers table
    OrderDate DATE NOT NULL,
    OrderTotal DECIMAL(10,2),
    ItemCount INT,  -- Denormalized count
    LastItemAddedDate DATETIME2,  -- Denormalized for quick access
    CustomerTotalOrders INT,  -- Denormalized aggregate
    CustomerTotalSpent DECIMAL(10,2)  -- Denormalized aggregate
);

-- Denormalized summary table
CREATE TABLE CustomerOrderSummary
(
    CustomerID INT PRIMARY KEY,
    TotalOrders INT NOT NULL DEFAULT 0,
    TotalSpent DECIMAL(10,2) NOT NULL DEFAULT 0,
    AverageOrderValue AS (CASE WHEN TotalOrders > 0 THEN TotalSpent / TotalOrders ELSE 0 END) PERSISTED,
    LastOrderDate DATETIME2,
    LastUpdated DATETIME2 DEFAULT GETUTCDATE()
);

-- Denormalized: Flattened hierarchy
CREATE TABLE CategoriesDenormalized
(
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    ParentCategoryID INT NULL,
    CategoryPath NVARCHAR(500),  -- Denormalized: "/1/2/3"
    CategoryLevel INT,  -- Denormalized level
    RootCategoryID INT,  -- Denormalized root category
    FOREIGN KEY (ParentCategoryID) REFERENCES CategoriesDenormalized(CategoryID)
);

/*
This comprehensive SQL Server normalization examples file provides:
- Complete walkthrough from 0NF to 5NF
- Practical examples showing violations and solutions
- Denormalization strategies for performance
- SQL Server-specific syntax and features
- Best practices for balancing normalization and performance

All examples use proper T-SQL syntax and SQL Server-specific features like IDENTITY, CHECK constraints, and computed columns.
*/

