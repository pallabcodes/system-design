# SQL Server Constraints

## Overview

Constraints are rules enforced on data columns on a table. These are used to limit the type of data that can go into a table. This ensures the accuracy and reliability of the data in the database.

## Types of Constraints

### 1. Primary Key
- **Description**: Uniquely identifies each record in a database table.
- **Rules**: Must contain unique values and cannot contain NULL values. A table can have only one primary key.
- **Index**: Automatically creates a unique clustered index (by default) or non-clustered index.

### 2. Foreign Key
- **Description**: A field (or collection of fields) in one table that refers to the `PRIMARY KEY` in another table.
- **Purpose**: Enforces referential integrity.
- **Actions**: `ON DELETE` and `ON UPDATE` actions (NO ACTION, CASCADE, SET NULL, SET DEFAULT).

### 3. Unique Constraint
- **Description**: Ensures that all values in a column are different.
- **Rules**: Can accept one NULL value (unlike Primary Key).
- **Index**: Automatically creates a unique non-clustered index.

### 4. Check Constraint
- **Description**: Limits the value range that can be placed in a column.
- **Usage**: Enforces domain integrity (e.g., Age >= 18).

### 5. Default Constraint
- **Description**: Provides a default value for a column when none is specified.
- **Usage**: Populates audit fields like `CreatedDate` automatically.

### 6. Not Null Constraint
- **Description**: Enforces that a column cannot accept NULL values.

## Best Practices

1.  **Naming Conventions**: explicit naming (e.g., `PK_TableName`, `FK_Source_Target`) allows for easier maintenance and error debugging.
2.  **Foreign Key Indexing**: Always index FK columns to improve JOIN performance and avoid table locks during deletes on the parent table.
3.  **Trusted Constraints**: Ensure constraints are "Trusted" after bulk data loads so the optimizer can use them for query plans.
4.  **Disabled Constraints**: Useful during large data loads to improve performance, but must be re-enabled and checked afterwards.
