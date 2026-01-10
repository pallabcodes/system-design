# SQL Server Security

## Overview

SQL Server provides comprehensive security features for protecting sensitive data, controlling access, and ensuring compliance. This guide covers authentication, authorization, encryption, auditing, and compliance features.

## Table of Contents

1. [Authentication](#authentication)
2. [Authorization](#authorization)
3. [Encryption](#encryption)
4. [Row-Level Security](#row-level-security)
5. [Auditing](#auditing)
6. [Compliance](#compliance)
7. [Enterprise Patterns](#enterprise-patterns)

## Authentication

### SQL Server Authentication

```sql
-- Create SQL Server login
CREATE LOGIN AppUser WITH PASSWORD = 'StrongPassword123!';

-- Create Windows login
CREATE LOGIN [DOMAIN\AppUser] FROM WINDOWS;
```

### Database Users

```sql
-- Create database user
CREATE USER AppUser FOR LOGIN AppUser;

-- Create user with default schema
CREATE USER AppUser FOR LOGIN AppUser
WITH DEFAULT_SCHEMA = dbo;
```

## Authorization

### Roles

```sql
-- Create database role
CREATE ROLE OrderManager;

-- Grant permissions to role
GRANT SELECT, INSERT, UPDATE ON Orders TO OrderManager;

-- Add user to role
ALTER ROLE OrderManager ADD MEMBER AppUser;
```

### Permissions

```sql
-- Grant table permissions
GRANT SELECT, INSERT, UPDATE ON Orders TO AppUser;

-- Grant schema permissions
GRANT SELECT ON SCHEMA::Sales TO AppUser;

-- Grant execute permission
GRANT EXECUTE ON dbo.GetOrders TO AppUser;
```

## Encryption

### Transparent Data Encryption (TDE)

```sql
-- Create master key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'MasterKeyPassword123!';

-- Create certificate
CREATE CERTIFICATE TDE_Certificate
WITH SUBJECT = 'TDE Certificate';

-- Enable TDE
ALTER DATABASE SalesDB
SET ENCRYPTION ON;
```

### Always Encrypted

```sql
-- Always Encrypted requires application-level configuration
-- Column-level encryption for sensitive data
```

## Row-Level Security

### Enable Row-Level Security

```sql
-- Create security policy
CREATE SECURITY POLICY OrderSecurityPolicy
ADD FILTER PREDICATE dbo.fn_security_predicate(UserID) ON Orders
WITH (STATE = ON);

-- Create security function
CREATE FUNCTION dbo.fn_security_predicate(@UserID UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE @UserID = CAST(SESSION_CONTEXT(N'UserID') AS UNIQUEIDENTIFIER);
```

## Auditing

### SQL Server Audit

```sql
-- Create server audit
CREATE SERVER AUDIT SalesAudit
TO FILE (
    FILEPATH = 'C:\Audits\',
    MAXSIZE = 1 GB,
    MAX_ROLLOVER_FILES = 10
)
WITH (
    QUEUE_DELAY = 1000,
    ON_FAILURE = CONTINUE
);

-- Enable audit
ALTER SERVER AUDIT SalesAudit WITH (STATE = ON);

-- Create database audit specification
CREATE DATABASE AUDIT SPECIFICATION SalesDBAudit
FOR SERVER AUDIT SalesAudit
ADD (SELECT, INSERT, UPDATE, DELETE ON Orders BY dbo)
WITH (STATE = ON);
```

## Compliance

### Data Classification

```sql
-- Add sensitivity classification
ADD SENSITIVITY CLASSIFICATION TO
    Orders.TotalAmount
WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Financial');
```

## Enterprise Patterns

### Multi-Tenant Security

```sql
-- Row-level security for multi-tenant
CREATE FUNCTION dbo.fn_tenant_security_predicate(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT);
```

## Best Practices

1. **Use Windows Authentication** when possible
2. **Follow principle of least privilege**
3. **Encrypt sensitive data** at rest and in transit
4. **Enable auditing** for compliance
5. **Use row-level security** for multi-tenant scenarios
6. **Regular security audits**
7. **Keep SQL Server updated** with security patches
8. **Use strong passwords** for SQL logins
9. **Monitor failed login attempts**
10. **Document security policies**

This guide provides comprehensive SQL Server security practices for protecting data and ensuring compliance.

