# SQL Server Indexing Strategies

## Overview

Indexing is critical for query performance in SQL Server. This guide covers the various types of indexes available in SQL Server, their use cases, and best practices for implementation and maintenance.

## Index Types

### 1. Clustered Indexes
- **Description**: Sorts and stores the data rows in the table or view based on their key values. There can be only one clustered index per table.
- **Use Case**: Columns frequently used in `ORDER BY`, `GROUP BY`, and range queries. Usually the Primary Key.
- **Structure**: B-Tree structure where the leaf nodes contain the actual data pages.

### 2. Non-Clustered Indexes
- **Description**: A structure separate from the data rows. Contains the key values and a pointer to the data row (either a RID for heaps or a Clustered Index Key).
- **Use Case**: Queries that filter or join on columns not present in the clustered index.
- **Features**:
  - **Include Columns (`INCLUDE`)**: Adds non-key columns to the leaf level to cover queries (Index Intersection/Covering Index).
  - **Filtered Indexes**: Non-clustered index with a `WHERE` clause.

### 3. Columnstore Indexes
- **Description**: Stores data by column rather than by row. Uses high compression.
- **Use Case**: Data warehousing, large analytical queries (OLAP).
- **Types**:
  - **Clustered Columnstore**: The primary storage for the entire table.
  - **Non-Clustered Columnstore**: Used on top of a rowstore table for real-time operational analytics (HTAP).

### 4. XML and Spatial Indexes
- **XML**: For efficient querying of standard XML data type columns.
- **Spatial**: For querying geometry and geography data types.

## Best Practices

1.  **Index Selectivity**: Index columns with high selectivity (many unique values).
2.  **Covering Indexes**: Use `INCLUDE` to create covering indexes that satisfy a query without looking up the base table (Key Lookup).
3.  **Write Overhead**: Avoid over-indexing OLTP tables as every index adds overhead to `INSERT`, `UPDATE`, and `DELETE` operations.
4.  **Maintenance**: Regularly rebuild or reorganize indexes to reduce fragmentation.
5.  **Filtered Indexes**: Use for columns with many NULLs or skewed data distributions to save space and improve performance.

## Index Maintenance

Fragmentation occurs when indexes have pages in which the logical ordering, based on the key value, does not match the physical ordering inside the data file.

- **Reorganize**: Defragment the leaf level of the index (Online operation).
- **Rebuild**: Drops and recreates the index (Can be offline or online in Enterprise edition).

## Common Anti-Patterns

- **Duplicate Indexes**: Indexes on the same columns in the same order.
- **Unused Indexes**: Indexes that are maintained but never read.
- **Wide Keys**: Large index keys reduce the number of keys per page and increase I/O.
