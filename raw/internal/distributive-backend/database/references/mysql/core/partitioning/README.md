# SQL Server Table Partitioning

## Overview

Table partitioning makes large tables more manageable and scalable by allowing you to access and manage subsets of data quickly and efficiently, while maintaining the integrity of a data collection. Partitioning allows subsets of data (partitions) to be spread across multiple filegroups, which can improve performance and manageability.

## Key Concepts

### 1. Partition Function
- Defines how the rows of a table or index are mapped to a set of partitions based on the values of a partitioning column (partition key).
- Defines the number of partitions and the boundaries.

### 2. Partition Scheme
- Maps the partitions of a partition function to a set of filegroups.
- Determines where the data physically resides.

### 3. Aligned Index
- An index built on the same partition scheme as its corresponding table.
- Essential for partition switching.

## Partitioning Strategies

### Range Partitioning (Left vs. Right)
- **RANGE LEFT**: The boundary value belongs to the partition on the *left* (lower values).
- **RANGE RIGHT**: The boundary value belongs to the partition on the *right* (higher values).
- **Standard Practice**: Use `RANGE RIGHT` for DateTime partitioning to easily manage new future partitions.

## Sliding Window Pattern

Common in data warehousing for maintaining a fixed window of time (e.g., keeping only the last 3 years of data).
1.  **Switch Out**: Switch the oldest partition out to an archive table (instant metadata operation).
2.  **Merge**: Merge the empty partition boundary.
3.  **Split**: specific new boundary for future data.
4.  **Switch In**: Switch new data in from a staging table.

## Best Practices

1.  **Partition Key**: Choose a key that is used in `WHERE` clauses (e.g., Date, Region) to enable Partition Elimination.
2.  **Filegroups**: Place different partitions on different physical disks (via filegroups) to spread I/O load.
3.  **Partition Switching**: Use for massive data loads or archives. It's a metadata-only operation (milliseconds) compared to DELETE/INSERT (hours).
4.  **Stats**: Remember that statistics are created at the table level (mostly) or partition level (newer versions), so ensure stats are updated.
