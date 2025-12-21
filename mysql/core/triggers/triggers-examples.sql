-- =============================================
-- SQL Server Triggers Examples
-- =============================================

-- 1. AFTER UPDATE Trigger (Audit Pattern)
-- Logs changes to the 'Salary' column in Employees table.

CREATE TABLE dbo.EmployeeAudit (
    AuditID INT IDENTITY(1,1),
    EmployeeID INT,
    OldSalary DECIMAL(18,2),
    NewSalary DECIMAL(18,2),
    ChangedBy VARCHAR(100),
    ChangeDate DATETIME DEFAULT GETDATE()
);
GO

CREATE TRIGGER TR_Employees_AuditSalary
ON dbo.Employees
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only insert audit if Salary actually changed
    IF UPDATE(Salary)
    BEGIN
        INSERT INTO dbo.EmployeeAudit (EmployeeID, OldSalary, NewSalary, ChangedBy)
        SELECT 
            i.EmployeeID,
            d.Salary,
            i.Salary,
            SYSTEM_USER
        FROM inserted i
        JOIN deleted d ON i.EmployeeID = d.EmployeeID;
    END
END;
GO

-- 2. INSTEAD OF Trigger
-- Allows updates on a view that joins multiple tables.

CREATE VIEW dbo.vw_EmployeeDepartments AS
SELECT e.EmployeeID, e.FirstName, e.LastName, d.DepartmentName
FROM dbo.Employees e
JOIN dbo.Departments d ON e.DepartmentID = d.DepartmentID;
GO

CREATE TRIGGER TR_vw_EmployeeDepartments_Insert
ON dbo.vw_EmployeeDepartments
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Logic to insert into underlying tables
    -- Note: This is simplified; usually requires error handling and transaction
    INSERT INTO dbo.Employees (FirstName, LastName)
    SELECT FirstName, LastName FROM inserted;
    -- (Logic to handle Department mapping would go here)
END;
GO

-- 3. DDL Trigger (Safety Net)
-- Prevents accidental table drops in Production.

CREATE TRIGGER TR_Safety_PreventTableDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    PRINT 'You must disable the "TR_Safety_PreventTableDrop" trigger to drop tables!'
    ROLLBACK; -- Undo the DROP TABLE command
END;
GO

-- To actually drop a table:
-- DISABLE TRIGGER TR_Safety_PreventTableDrop ON DATABASE;
-- DROP TABLE dbo.OldTable;
-- ENABLE TRIGGER TR_Safety_PreventTableDrop ON DATABASE;
