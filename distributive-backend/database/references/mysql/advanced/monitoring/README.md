# SQL Server Monitoring

## Overview

Effective monitoring is essential for maintaining the health, performance, and availability of SQL Server instances.

## Monitoring Tools

### 1. Dynamic Management Views (DMVs)
- **Description**: Internal views and functions that return server state information.
- **Usage**: Used to monitor health, diagnose problems, and tune performance.
- **Key DMVs**: `sys.dm_exec_requests`, `sys.dm_os_wait_stats`, `sys.dm_db_index_usage_stats`.

### 2. Extended Events (XEvents)
- **Description**: A lightweight performance monitoring system that enables users to collect data needed to monitor and troubleshoot problems in SQL Server.
- **Usage**: Replaces SQL Server Profiler. Trace deadlocks, long-running queries, and error events with minimal overhead.

### 3. Query Store
- **Description**: Automatically captures a history of queries, plans, and runtime statistics, and retains these for your review.
- **Usage**: Fixing performance regressions caused by plan changes (parameter sniffing, statistics updates).

### 4. SQL Server Audit
- **Description**: Tracks and logs events to the Windows Security log, Application log, or a file.
- **Usage**: Compliance and security auditing (e.g., failed logins, schema changes).

### 5. Performance Monitor (PerfMon)
- **Description**: Windows tool to monitor system resources (CPU, Memory, Disk, Network).
- **Key Counters**:
  - `SQLServer:Buffer Manager\Page life expectancy`: How long pages stay in memory (higher is better).
  - `SQLServer:SQL Statistics\Batch Requests/sec`: throughput.

## Best Practices

1.  **Baseline**: Establish a performance baseline to know what "normal" looks like.
2.  **Alerting**: Set up alerts for critical errors (Severity 19-25) and resource exhaustion (Disk space, blocked processes).
3.  **Low Impact**: Use lightweight tools like Extended Events and DMVs instead of Profiler.
4.  **Regular Review**: Regularly review heavy queries in Query Store and unused indexes.
