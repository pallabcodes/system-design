-- =============================================
-- SQL Server Performance Tuning Scripts
-- =============================================

-- 1. Identify Top 10 CPU Consuming Queries
SELECT TOP 10
    qs.total_worker_time AS TotalCPU,
    qs.execution_count,
    qs.total_worker_time / qs.execution_count AS AvgCPU,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 
        ((CASE qs.statement_end_offset
          WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset
         END - qs.statement_start_offset)/2) + 1) AS QueryText,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY qs.total_worker_time DESC;
GO

-- 2. Identify Top Wait Types (Server Level)
-- Helps understand the main bottleneck (I/O, CPU, Locking)
SELECT TOP 10
    wait_type,
    wait_time_ms / 1000.0 AS WaitS,
    (wait_time_ms - signal_wait_time_ms) / 1000.0 AS ResourceS,
    signal_wait_time_ms / 1000.0 AS SignalS,
    waiting_tasks_count,
    100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS Pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'CLASSPAD', 'OS_WAIT_STATS', 'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 
    'WAITFOR', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'CHECKPOINT_QUEUE', 
    'MASTER_REQUEST', 'HADR_CLUSAPI_CALL', 'SE_REPL_SCHEMA_BOUND_VIEWS', 
    'SERVER_IDLE_CHECK', 'ONDEMAND_TASK_QUEUE', 'LOGMGR_QUEUE_CHECKPOINT', 
    'GOVERNOR_IDLE', 'DIRTY_PAGE_POLL', 'REQUEST_FOR_DEADLOCK_SEARCH'
)
ORDER BY wait_time_ms DESC;
GO

-- 3. Find Missing Indexes
SELECT 
    migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS Score,
    db_name(mid.database_id) as DatabaseName,
    OBJECT_NAME(mid.object_id, mid.database_id) as TableName,
    'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id, mid.database_id) + '_'
    + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''),', ','_'),'[',''),']','') 
    + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN '_' ELSE '' END
    + REPLACE(REPLACE(REPLACE(ISNULL(mid.inequality_columns,''),', ','_'),'[',''),']','')
    + ']'
    + ' ON ' + mid.statement
    + ' (' + ISNULL (mid.equality_columns,'')
    + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END
    + ISNULL (mid.inequality_columns, '')
    + ')'
    + ISNULL (' INCLUDE (' + mid.included_columns + ')', '') AS CreateIndexStatement
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
ORDER BY Score DESC;
GO

-- 4. Check for Blocking
SELECT 
    session_id, 
    blocking_session_id, 
    wait_type, 
    wait_time, 
    wait_resource, 
    status 
FROM sys.dm_exec_requests 
WHERE blocking_session_id <> 0;
GO
