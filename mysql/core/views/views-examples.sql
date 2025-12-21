-- =============================================
-- SQL Server Views Examples
-- =============================================

-- 1. Standard View (Security & Abstraction)
-- Hides the 'Salary' column and limits rows to Active employees.
CREATE VIEW dbo.vw_ActiveEmployees
AS
SELECT 
    EmployeeID,
    FirstName,
    LastName,
    DepartmentID,
    HireDate
FROM dbo.Employees
WHERE IsActive = 1;
GO

-- 2. Indexed View (Materialized View)
-- Optimizes an aggregation query.

CREATE VIEW dbo.vw_SalesSummary_Indexed
WITH SCHEMABINDING -- Required for Indexed View
AS
SELECT 
    d.DepartmentName,
    COUNT_BIG(*) AS OrderCount, -- COUNT_BIG is required
    SUM(o.TotalAmount) AS TotalRevenue
FROM Sales.Orders o
JOIN dbo.Departments d ON o.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName;
GO

-- Create the Unique Clustered Index to materialize it
CREATE UNIQUE CLUSTERED INDEX IX_SalesSummary_DepartmentName
ON dbo.vw_SalesSummary_Indexed (DepartmentName);
GO

-- Now, queries matching this aggregation will read from the View automatically
-- (Enterprise Edition feature, or use NOEXPAND hint)
SELECT * FROM dbo.vw_SalesSummary_Indexed;
GO

-- 3. Updateable View
-- You can update underlying tables via a view if it affects only one table.
UPDATE dbo.vw_ActiveEmployees
SET LastName = 'Smith'
WHERE EmployeeID = 101;
GO

-- 4. Check View Definition
SELECT definition 
FROM sys.sql_modules 
WHERE object_id = OBJECT_ID('dbo.vw_ActiveEmployees');
GO
