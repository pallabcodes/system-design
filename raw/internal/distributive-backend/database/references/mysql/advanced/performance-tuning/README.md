# SQL Server Performance Tuning

## Overview

Performance tuning is the process of optimizing SQL Server performance by analyzing the database workload and query execution. It involves identifying bottlenecks, optimizing T-SQL queries, and configuring the database engine.

## Key Concepts

### 1. Execution Plans
- **Description**: The roadmap SQL Server uses to execute a query.
- **Analysis**: Look for high-cost operators (Table Scans, Sorts), implicit conversions, and key lookups.
- **Cached Plans**: Reusing plans saves compilation time.

### 2. Indexes and Statistics
- **Missing Indexes**: Identify queries that would benefit from new indexes.
- **Outdated Statistics**: Ensure statistics are up-to-date so the optimizer can make good decisions.

### 3. Wait Statistics
- **Description**: Detailed tracking of what SQL Server is waiting for (e.g., Disk I/O, Locks, CPU).
- **Common Waits**:
  - `PAGEIOLATCH`: Disk I/O pressure (waiting to read pages into memory).
  - `LCK_M_*`: Blocking/Locking issues.
  - `CXPACKET`: Parallelism issues (often mingled with `SOS_SCHEDULER_YIELD`).

### 4. Query Store
- **Description**: A "flight data recorder" for your database.
- **Usage**: Automatically captures history of queries, plans, and runtime statistics. Perfect for detecting plan regression.

## Optimization Techniques

1.  **SARGability**: Ensure that predicates in the `WHERE` clause are **S**earch **ARG**ument **able** (e.g., avoid functions on columns: `WHERE YEAR(dateCol) = 2023`).
2.  **Indexing**: Create specialized indexes for heavy queries.
3.  **Parameter Sniffing**: Be aware that reusing a plan compiled for one value might be terrible for another value. Use `OPTION (RECOMPILE)` or `OPTIMIZE FOR` if needed.
4.  **TempDB**: Check for contention.
5.  **Memory Grant Issues**: Look for `RESOURCE_SEMAPHORE` waits indicating insufficient memory for queries.

## Tools
- **Dynamic Management Views (DMVs)**: Query internal system state.
- **Extended Events**: Lightweight tracing.
- **Database Engine Tuning Advisor**: Automated recommendations.
