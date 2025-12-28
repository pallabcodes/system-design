-- =============================================
-- SQL Server Functions Examples
-- =============================================

-- 1. Scalar Function
-- Returns a formatted full name
CREATE FUNCTION dbo.fn_GetFullName 
(
    @FirstName VARCHAR(50),
    @LastName VARCHAR(50)
)
RETURNS VARCHAR(101)
WITH SCHEMABINDING
AS
BEGIN
    RETURN @FirstName + ' ' + @LastName;
END;
GO

-- Usage
SELECT dbo.fn_GetFullName('John', 'Doe');
GO

-- 2. Inline Table-Valued Function (iTVF)
-- Recommended over Multi-Statement TVF for performance.
CREATE FUNCTION dbo.fn_GetOrdersByCustomer 
(
    @CustomerID INT
)
RETURNS TABLE
AS
RETURN 
(
    SELECT OrderID, OrderDate, TotalAmount
    FROM Sales.Orders
    WHERE CustomerID = @CustomerID
);
GO

-- Usage (Treated like a table)
SELECT * FROM dbo.fn_GetOrdersByCustomer(101);
GO

-- 3. Multi-Statement Table-Valued Function (mstVF)
-- Use only when logic is too complex for a single SELECT.
CREATE FUNCTION dbo.fn_GetHighValueCustomers 
(
    @Threshold DECIMAL(18,2)
)
RETURNS @CustomerTable TABLE 
(
    CustomerID INT, 
    TotalSpend DECIMAL(18,2),
    Category VARCHAR(20)
)
AS
BEGIN
    INSERT INTO @CustomerTable (CustomerID, TotalSpend)
    SELECT CustomerID, SUM(TotalAmount)
    FROM Sales.Orders
    GROUP BY CustomerID
    HAVING SUM(TotalAmount) > @Threshold;

    UPDATE @CustomerTable
    SET Category = CASE 
        WHEN TotalSpend > 10000 THEN 'Platinum'
        ELSE 'Gold'
    END;

    RETURN;
END;
GO

-- Usage
SELECT * FROM dbo.fn_GetHighValueCustomers(5000.00);
GO

-- 4. Cross Apply with TVF
-- Calculate logic per row from the outer table.
SELECT c.CustomerName, o.TotalSpend, o.Category
FROM Sales.Customers c
CROSS APPLY dbo.fn_GetHighValueCustomers(5000.00) o
WHERE c.CustomerID = o.CustomerID;
GO
