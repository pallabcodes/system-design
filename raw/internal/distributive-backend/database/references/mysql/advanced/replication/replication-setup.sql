-- =============================================
-- SQL Server Replication Setup (Conceptual)
-- =============================================
-- Note: Replication is usually configured via SSMS Wizards or complex T-SQL scripts involving
-- SQL Agent jobs and file shares. This script outlines the T-SQL approach.

-- 1. Enable Distribution (On Distributor Server)
/*
USE master;
EXEC sp_adddistributor @distributor = 'ServerName', @password = 'StrongPass!';
EXEC sp_adddistributiondb @database = 'distribution', @security_mode = 1;
GO
*/

-- 2. Create Publication (On Publisher)
-- Check if table has a PK (Required for Transactional)
SELECT name, object_id 
FROM sys.tables 
WHERE object_id NOT IN (
    SELECT parent_object_id 
    FROM sys.key_constraints 
    WHERE type = 'PK'
);
GO

-- 3. Check Replication Status (On Distributor)
-- View distribution agents status
/*
USE distribution;
SELECT 
    a.name as AgentName,
    s.time,
    s.comments,
    s.delivery_rate,
    s.delivery_latency
FROM MSdistribution_history s
JOIN MSdistribution_agents a ON s.agent_id = a.id
ORDER BY s.time DESC;
*/

-- 4. Troubleshooting: Mark Transaction Log for Replication
-- If the log is full and waiting for replication:
SELECT name, log_reuse_wait_desc 
FROM sys.databases 
WHERE name = 'YourDatabase';
-- If 'REPLICATION', ensure the Log Reader Agent is running.
GO

-- 5. Remove Replication (Cleanup)
-- EXEC sp_removedbreplication 'YourDatabase';
GO
