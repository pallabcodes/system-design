-- =============================================
-- SQL Server Monitoring Scripts
-- =============================================

-- 1. Currently Running Requests
-- Who is doing what right now?
SELECT 
    r.session_id,
    r.status,
    r.start_time,
    r.command,
    DB_NAME(r.database_id) AS DatabaseName,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.total_elapsed_time,
    t.text AS QueryText,
    qp.query_plan
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) qp
WHERE r.session_id <> @@SPID;
GO

-- 2. Index Usage Stats
-- Find indexes that are not being used (Candidates for removal)
SELECT 
    OBJECT_NAME(ius.object_id) AS TableName,
    i.name AS IndexName,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates, -- High updates + Low reads = Bad Index
    ius.last_user_seek,
    ius.last_user_scan
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
AND i.type_desc <> 'HEAP'
ORDER BY (ius.user_seeks + ius.user_scans + ius.user_lookups) ASC;
GO

-- 3. Enable Query Store (if not already enabled)
-- ALTER DATABASE [YourDB] SET QUERY_STORE = ON;
-- GO

-- 4. Extended Events Session for Deadlocks
-- Checks if the system_health session (default) captures deadlocks
SELECT * 
FROM sys.dm_xe_sessions 
WHERE name = 'system_health';
GO

-- To read deadlock data from the ring buffer:
SELECT 
    CAST(target_data AS XML) AS TargetData
FROM sys.dm_xe_session_targets st
JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
WHERE s.name = 'system_health';
GO
