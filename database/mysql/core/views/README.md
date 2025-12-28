# SQL Server Views

## Overview

A view is a virtual table whose contents are defined by a query. Like a table, a view consists of a set of named columns and rows of data. Unless defined as an indexed view, a view does not exist as a stored set of data values in a database.

## Types of Views

### 1. Standard Views
- **Description**: A saved query that acts as a virtual table.
- **Benefits**:
  - Security (restricting access to specific columns/rows).
  - Abstraction (hiding complex joins).
  - Simplicity (presenting data in a specific format).

### 2. Indexed (Materialized) Views
- **Description**: A view that has a unique clustered index created on it. The result set is physically stored in the database.
- **Benefits**: Dramatic performance improvement for aggregations and joins on large datasets.
- **Requirements**: `SCHEMABINDING`, `COUNT_BIG(*)`, and specific SET options.

### 3. Partitioned Views
- **Description**: data is stored horizontally across multiple tables (possibly on different servers) and joined via `UNION ALL`.

## Best Practices

1.  **Schema Binding**: Use `WITH SCHEMABINDING` to protect the view from changes to underlying tables.
2.  **Avoid nesting**: Avoid creating views that reference other views (nested views) as it complicates performance tuning and dependency management.
3.  **Indexed Views**: Use them sparingly for specific performance bottlenecks (aggregations), as they add maintenance overhead to DML operations on the base tables.
4.  **Security**: Use views to grant access to data subsets without giving access to the underlying table.
