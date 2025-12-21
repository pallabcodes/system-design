-- =============================================
-- SQL Server Security Examples
-- =============================================

-- 1. Create Login and User
-- Login is Server-level, User is Database-level.
CREATE LOGIN [AppUser] WITH PASSWORD = 'StrongPassword!123';
GO

CREATE USER [AppUser] FOR LOGIN [AppUser];
GO

-- 2. Role-Based Access Control (RBAC)
-- Create a custom role and assign permissions
CREATE ROLE [SalesReadRole];
GRANT SELECT ON SCHEMA::Sales TO [SalesReadRole];

-- Add user to role
ALTER ROLE [SalesReadRole] ADD MEMBER [AppUser];
GO

-- 3. Dynamic Data Masking (DDM)
-- Mask email addresses so only approved users see them.
CREATE TABLE dbo.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullName VARCHAR(100),
    Email VARCHAR(100) MASKED WITH (FUNCTION = 'email()'),
    CreditCard VARCHAR(20) MASKED WITH (FUNCTION = 'partial(0, "xxxx-xxxx-xxxx-xxxx", 4)')
);

INSERT INTO dbo.Customers (FullName, Email, CreditCard)
VALUES ('John Doe', 'john.doe@example.com', '1234-5678-9012-3456');

-- AppUser will see masked data
EXECUTE AS USER = 'AppUser';
SELECT * FROM dbo.Customers;
REVERT;
GO

-- 4. Row-Level Security (RLS)
-- Step 1: Create the Security Predicate Function
CREATE SCHEMA Security;
GO

CREATE FUNCTION Security.fn_securitypredicate(@TenantID AS INT)
    RETURNS TABLE
WITH SCHEMABINDING
AS
    RETURN SELECT 1 AS fn_securitypredicate_result
    WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT);
GO

-- Step 2: Bind the function to the table using a Security Policy
-- Assuming Sales.Orders has a TenantID column
CREATE SECURITY POLICY Security.SalesFilter
ADD FILTER PREDICATE Security.fn_securitypredicate(TenantID)
ON Sales.Orders
WITH (STATE = ON);
GO

-- Usage: Application sets the TenantID in Session Context
EXEC sp_set_session_context 'TenantID', 1;
SELECT * FROM Sales.Orders; -- Returns only Tenant 1's orders
GO
