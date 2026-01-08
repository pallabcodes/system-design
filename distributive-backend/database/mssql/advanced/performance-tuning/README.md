# SQL Server Performance Tuning

## Overview

Performance tuning in SQL Server involves optimizing database configuration, query execution, indexing strategies, and hardware utilization. This guide covers comprehensive performance optimization techniques.

## Table of Contents

1. [Server Configuration](#server-configuration)
2. [Memory Configuration](#memory-configuration)
3. [Query Optimization](#query-optimization)
4. [Index Optimization](#index-optimization)
5. [Statistics Management](#statistics-management)
6. [Execution Plans](#execution-plans)
7. [Enterprise Patterns](#enterprise-patterns)

## Server Configuration

### Max Degree of Parallelism (MAXDOP)

```sql
-- Set MAXDOP (typically CPU cores / 2)
EXEC sp_configure 'max degree of parallelism', 4;
RECONFIGURE;

-- Check current setting
SELECT value_in_use FROM sys.configurations 
WHERE name = 'max degree of parallelism';
```

### Cost Threshold for Parallelism

```sql
-- Set cost threshold (default 5)
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
```

## Memory Configuration

### Max Server Memory

```sql
-- Set max server memory (leave 4GB for OS)
EXEC sp_configure 'max server memory', 12288;  -- 12GB
RECONFIGURE;

-- Check current setting
SELECT value_in_use FROM sys.configurations 
WHERE name = 'max server memory (MB)';
```

### Min Server Memory

```sql
-- Set min server memory
EXEC sp_configure 'min server memory', 4096;  -- 4GB
RECONFIGURE;
```

## Query Optimization

### Query Hints

```sql
-- Force index usage
SELECT * FROM Orders WITH (INDEX(IX_Orders_UserID))
WHERE UserID = 'user-guid';

-- Force join order
SELECT * FROM Orders o
INNER LOOP JOIN Users u ON o.UserID = u.UserID;

-- Force query plan
SELECT * FROM Orders
WHERE UserID = 'user-guid'
OPTION (USE PLAN N'...');
```

### Query Rewriting

```sql
-- Avoid functions in WHERE clause
-- Bad:
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2024;

-- Good:
SELECT * FROM Orders 
WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01';
```

## Index Optimization

### Index Maintenance

```sql
-- Rebuild index
ALTER INDEX IX_Orders_UserID ON Orders REBUILD;

-- Reorganize index
ALTER INDEX IX_Orders_UserID ON Orders REORGANIZE;

-- Update statistics
UPDATE STATISTICS Orders WITH FULLSCAN;
```

### Missing Indexes

```sql
-- Find missing indexes (see monitoring guide)
-- Create recommended indexes
CREATE INDEX IX_Orders_UserID_OrderDate 
ON Orders(UserID, OrderDate DESC)
INCLUDE (TotalAmount, Status);
```

## Statistics Management

### Auto Statistics

```sql
-- Enable auto create statistics
ALTER DATABASE SalesDB SET AUTO_CREATE_STATISTICS ON;

-- Enable auto update statistics
ALTER DATABASE SalesDB SET AUTO_UPDATE_STATISTICS ON;

-- Enable async auto update statistics
ALTER DATABASE SalesDB SET AUTO_UPDATE_STATISTICS_ASYNC ON;
```

### Manual Statistics Update

```sql
-- Update statistics with full scan
UPDATE STATISTICS Orders WITH FULLSCAN;

-- Update statistics with sample
UPDATE STATISTICS Orders WITH SAMPLE 50 PERCENT;
```

## Execution Plans

### View Execution Plan

```sql
-- Include actual execution plan
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM Orders WHERE UserID = 'user-guid';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

### Analyze Execution Plan

```sql
-- Check for:
-- 1. Table scans (should use indexes)
-- 2. Key lookups (consider covering indexes)
-- 3. Sort operations (consider indexes)
-- 4. Hash joins (may need better statistics)
-- 5. Parallelism (may need MAXDOP adjustment)
```

## Enterprise Patterns

### Performance Baseline

```sql
-- Create performance baseline
SELECT 
    GETDATE() AS CaptureDate,
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'Batch Requests/sec') AS BatchRequestsPerSec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'Page life expectancy') AS PageLifeExpectancy,
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'Buffer cache hit ratio') AS BufferCacheHitRatio
INTO PerformanceBaseline;
```

### Query Store

```sql
-- Enable Query Store
ALTER DATABASE SalesDB SET QUERY_STORE = ON;

-- Configure Query Store
ALTER DATABASE SalesDB SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 60
);

-- View top queries
SELECT TOP 10
    q.query_id,
    qt.query_sql_text,
    rs.avg_duration,
    rs.count_executions
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC;
```

## Best Practices

1. **Configure memory** appropriately for your workload
2. **Set MAXDOP** based on CPU cores
3. **Maintain indexes** regularly
4. **Update statistics** frequently
5. **Use Query Store** for query performance tracking
6. **Monitor execution plans** for optimization opportunities
7. **Avoid functions** in WHERE clauses
8. **Use appropriate indexes** for query patterns
9. **Test performance changes** in development first
10. **Document performance tuning** decisions

This guide provides comprehensive SQL Server performance tuning techniques for optimal database performance.

