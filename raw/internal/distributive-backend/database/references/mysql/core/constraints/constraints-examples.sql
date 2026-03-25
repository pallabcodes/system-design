-- =============================================
-- SQL Server Constraints Examples
-- =============================================

-- 1. Table Creation with Constraints
CREATE TABLE dbo.Departments (
    DepartmentID INT PRIMARY KEY, -- PK Constraint
    DepartmentName VARCHAR(100) NOT NULL,
    Location VARCHAR(100) DEFAULT 'Headquarters', -- Default Constraint
    CONSTRAINT UQ_Departments_Name UNIQUE(DepartmentName) -- Named Unique Constraint
);
GO

CREATE TABLE dbo.Employees (
    EmployeeID INT IDENTITY(1,1),
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(100),
    DepartmentID INT,
    Salary DECIMAL(18,2),
    HireDate DATETIME DEFAULT GETDATE(),
    
    -- Primary Key Constraint (Named)
    CONSTRAINT PK_Employees PRIMARY KEY (EmployeeID),
    
    -- Foreign Key Constraint with Cascade Delete
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentID)
        REFERENCES dbo.Departments(DepartmentID)
        ON DELETE CASCADE,
        
    -- Check Constraint
    CONSTRAINT CK_Employees_Salary CHECK (Salary > 0),
    
    -- Unique Constraint
    CONSTRAINT UQ_Employees_Email UNIQUE (Email)
);
GO

-- 2. Adding Constraints to Existing Tables

-- Add a Check Constraint
ALTER TABLE dbo.Employees
ADD CONSTRAINT CK_Employees_HireDate 
CHECK (HireDate <= GETDATE());
GO

-- Add a Default Constraint
ALTER TABLE dbo.Employees
ADD CONSTRAINT DF_Employees_IsActive
DEFAULT 1 FOR IsActive; -- Assuming IsActive column exists
GO

-- 3. Disabling & Enabling Constraints (for Bulk Load)

-- Disable all constraints on a table
ALTER TABLE dbo.Employees NOCHECK CONSTRAINT ALL;

-- Enable and Validate (Trusted)
ALTER TABLE dbo.Employees WITH CHECK CHECK CONSTRAINT ALL;
GO

-- 4. Checking Trusted Constraints
-- If is_not_trusted = 1, the query optimizer won't use the constraint.
SELECT name, is_not_trusted 
FROM sys.check_constraints 
WHERE parent_object_id = OBJECT_ID('dbo.Employees');
GO
