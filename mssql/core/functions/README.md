# SQL Server Functions

## Overview

User-Defined Functions (UDFs) in SQL Server are routines that accept parameters, perform an action (such as a complex calculation), and return the result of that action as a value. The return value can be either a single scalar value or a result set equivalent to a table.

## Types of Functions

### 1. Scalar Functions
- **Description**: Returns a single value (string, integer, date, etc.).
- **Usage**: Can be used in SELECT lists, WHERE clauses, and expressions.
- **Performance**: Historically slow due to row-by-row execution, but newer SQL Server versions include "Scalar UDF Inlining" optimization.

### 2. Table-Valued Functions (TVFs)
- **Inline TVF (iTVF)**:
  - Returns a table variable based on a single SELECT statement.
  - **Performance**: High performance (treated like a parameterized view). The query optimizer can fold it into the main query.
- **Multi-Statement TVF (mstVF)**:
  - Returns a table variable populated by multiple statements.
  - **Performance**: Generally poorer performance than iTVFs due to lack of accurate statistics.

### 3. System Functions
- Built-in functions available in SQL Server (e.g., `GETDATE()`, `SUBSTRING()`, `OBJECT_ID()`).

## Deterministic vs. Nondeterministic

- **Deterministic**: Always returns the same result for the same input (e.g., `LEN('abc')`). Required for indexing computed columns.
- **Nondeterministic**: Returns different results for the same input (e.g., `GETDATE()`).

## Best Practices

1.  **Prefer Inline TVFs**: Use Inline Table-Valued Functions over Multi-Statement TVFs or Scalar functions whenever possible for better performance.
2.  **Schema Binding**: Use `WITH SCHEMABINDING` to prevent changes to underlying objects that would break the function.
3.  **Cross Apply**: Use `CROSS APPLY` to invoke a TVF for each row of the outer query.
4.  **Avoid in WHERE**: Avoid using non-inlineable scalar functions in WHERE clauses on large datasets, as it forces a table scan (sargability issue).
