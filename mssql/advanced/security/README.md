# SQL Server Security

## Overview

SQL Server security architecture is hierarchical, consisting of the server instance, the database, and the objects within the database. It includes authentication, authorization, and data protection mechanisms.

## Authentication vs. Authorization

- **Authentication ("Who are you?")**: The process of verifying the identity of a user.
  - **Windows Authentication**: Uses Active Directory. Preferred for internal applications.
  - **SQL Server Authentication**: Uses username/password stored in SQL Server.

- **Authorization ("What can you do?")**: The process of assigning permissions to a user or role.
  - **Principals**: Entities requesting access (Logins, Users, Roles).
  - **Securables**: Resources to be accessed (Tables, Schemas, Databases).
  - **Permissions**: Granting access (SELECT, UPDATE, EXECUTE).

## Data Protection Features

### 1. Row-Level Security (RLS)
- **Description**: Fine-grained access control over rows in a table.
- **Mechanism**: A predicate function filters rows based on the user's context.
- **Application**: Multi-tenant applications where tenants share the same table.

### 2. Dynamic Data Masking (DDM)
- **Description**: Limits sensitive data exposure by masking it to non-privileged users.
- **Mechanism**: Data is masked in the result set but remains unencrypted in the database.
- **Application**: Hiding PII (Email, Phone) from support staff.

### 3. Transparent Data Encryption (TDE)
- **Description**: Encrypts database files at rest (data and log files).
- **Mechanism**: Real-time I/O encryption/decryption using a Database Encryption Key (DEK).

### 4. Always Encrypted
- **Description**: Encrypts data inside the client application. SQL Server never sees the plaintext.
- **Mechanism**: Keys are managed on the client side.

## Best Practices

1.  **Least Privilege**: Grant only the minimum permissions required.
2.  **Role-Based Access Control (RBAC)**: Assign permissions to Roles, not users. Add users to Roles.
3.  **Schema Ownership**: segment objects into schemas (e.g., `Sales`, `HR`) and grant permissions on the schema level.
4.  **Audit**: Enable SQL Server Audit to track failed logins and access to sensitive tables.
