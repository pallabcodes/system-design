# SQL Server Monitoring

## Overview

Comprehensive monitoring is essential for maintaining SQL Server database performance, availability, and reliability. This guide covers monitoring strategies, tools, key metrics, alerting systems, and proactive maintenance.

## Table of Contents

1. [Key Metrics](#key-metrics)
2. [Performance Monitoring](#performance-monitoring)
3. [System Health](#system-health)
4. [Query Performance](#query-performance)
5. [Resource Monitoring](#resource-monitoring)
6. [Alerting](#alerting)
7. [Enterprise Patterns](#enterprise-patterns)

## Key Metrics

### Performance Metrics

* **CPU Usage**: Processor utilization
* **Memory Usage**: Buffer pool, plan cache
* **Disk I/O**: Read/write operations, latency
* **Network I/O**: Bandwidth usage
* **Wait Statistics**: Resource waits

### Database Metrics

* **Transaction Rate**: Transactions per second
* **Batch Requests**: Batch requests per second
* **Page Life Expectancy**: Buffer pool efficiency
* **Checkpoint Pages**: Checkpoint activity
* **Log Growth**: Transaction log size

## Performance Monitoring

### Dynamic Management Views (DMVs)

```sql
-- Server performance summary
SELECT 
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'Batch Requests/sec') AS BatchRequestsPerSec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'SQL Compilations/sec') AS CompilationsPerSec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'SQL Re-Compilations/sec') AS RecompilationsPerSec;

-- Top queries by CPU
SELECT TOP 10
    qs.total_worker_time / qs.execution_count AS avg_cpu_time,
    qs.execution_count,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2)+1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_worker_time DESC;
```

### Wait Statistics

```sql
-- Top wait types
SELECT TOP 10
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    wait_time_ms / waiting_tasks_count AS avg_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;
```

## System Health

### Database Health

```sql
-- Database file sizes and growth
SELECT 
    name AS DatabaseName,
    size * 8 / 1024 AS SizeMB,
    FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024 AS UsedMB,
    size * 8 / 1024 - FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024 AS FreeMB
FROM sys.database_files;

-- Database integrity
DBCC CHECKDB('SalesDB') WITH NO_INFOMSGS;
```

### Connection Monitoring

```sql
-- Active connections
SELECT 
    session_id,
    login_name,
    host_name,
    program_name,
    status,
    cpu_time,
    memory_usage,
    reads,
    writes,
    logical_reads
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
ORDER BY cpu_time DESC;
```

## Query Performance

### Slow Queries

```sql
-- Find slow queries
SELECT TOP 10
    qs.execution_count,
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_time,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    qt.text AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;
```

### Missing Indexes

```sql
-- Missing index recommendations
SELECT 
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE INDEX [missing_index_' + CONVERT(VARCHAR, mig.index_group_handle) + '_' + 
    CONVERT(VARCHAR, mid.index_handle) + '_' + LEFT(PARSENAME(mid.statement, 1), 32) + ']' +
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns, '') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL 
         THEN ',' ELSE '' END + ISNULL(mid.inequality_columns, '') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC;
```

## Resource Monitoring

### Memory Usage

```sql
-- Buffer pool usage
SELECT 
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'Page life expectancy') AS PageLifeExpectancy,
    (SELECT cntr_value FROM sys.dm_os_performance_counters 
     WHERE counter_name = 'Buffer cache hit ratio') AS BufferCacheHitRatio;

-- Memory grants
SELECT 
    session_id,
    requested_memory_kb,
    granted_memory_kb,
    used_memory_kb
FROM sys.dm_exec_query_memory_grants
WHERE granted_memory_kb > 0;
```

### Disk I/O

```sql
-- Disk I/O statistics
SELECT 
    DB_NAME(database_id) AS DatabaseName,
    file_id,
    io_stall_read_ms,
    io_stall_write_ms,
    num_of_reads,
    num_of_writes
FROM sys.dm_io_virtual_file_stats(NULL, NULL)
ORDER BY io_stall_read_ms + io_stall_write_ms DESC;
```

## Alerting

### SQL Server Agent Alerts

```sql
-- Create alert for high CPU
EXEC msdb.dbo.sp_add_alert
    @name = N'High CPU Usage',
    @enabled = 1,
    @delay_between_responses = 60,
    @performance_condition = N'SQLServer:Resource Pool Stats|CPU usage %|default|>|80';

-- Create alert for low page life expectancy
EXEC msdb.dbo.sp_add_alert
    @name = N'Low Page Life Expectancy',
    @enabled = 1,
    @delay_between_responses = 300,
    @performance_condition = N'SQLServer:Buffer Manager|Page life expectancy||<|300';
```

## Enterprise Patterns

### Health Check Script

```sql
-- Comprehensive health check
DECLARE @HealthStatus TABLE (
    CheckName NVARCHAR(255),
    Status NVARCHAR(50),
    Details NVARCHAR(MAX)
);

-- Check page life expectancy
INSERT INTO @HealthStatus
SELECT 
    'Page Life Expectancy',
    CASE WHEN cntr_value < 300 THEN 'WARNING' ELSE 'OK' END,
    CAST(cntr_value AS NVARCHAR(50)) + ' seconds'
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy';

-- Check database file growth
INSERT INTO @HealthStatus
SELECT 
    'Database File Growth',
    CASE WHEN (size - FILEPROPERTY(name, 'SpaceUsed')) * 8 / 1024 < 100 THEN 'WARNING' ELSE 'OK' END,
    DB_NAME() + ' - ' + name + ': ' + 
    CAST((size - FILEPROPERTY(name, 'SpaceUsed')) * 8 / 1024 AS NVARCHAR(50)) + ' MB free'
FROM sys.database_files;

SELECT * FROM @HealthStatus;
```

## Best Practices

1. **Monitor key metrics** continuously
2. **Set up alerts** for critical thresholds
3. **Use DMVs** for performance monitoring
4. **Track wait statistics** to identify bottlenecks
5. **Monitor query performance** regularly
6. **Check index usage** and missing indexes
7. **Monitor resource usage** (CPU, memory, disk)
8. **Review error logs** regularly
9. **Document monitoring procedures**
10. **Automate health checks** where possible

This guide provides comprehensive SQL Server monitoring strategies for maintaining optimal database performance and availability.

