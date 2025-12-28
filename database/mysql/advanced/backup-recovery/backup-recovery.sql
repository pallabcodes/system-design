-- =============================================
-- SQL Server Backup & Recovery Scripts
-- =============================================

-- 1. Full Backup
BACKUP DATABASE [YourDatabase]
TO DISK = 'C:\Backups\YourDatabase_Full.bak'
WITH FORMAT, COMPRESSION, STATS = 10;
GO

-- 2. Transaction Log Backup (Req. Full Recovery Model)
BACKUP LOG [YourDatabase]
TO DISK = 'C:\Backups\YourDatabase_Log.trn'
WITH COMPRESSION;
GO

-- 3. Differential Backup
BACKUP DATABASE [YourDatabase]
TO DISK = 'C:\Backups\YourDatabase_Diff.bak'
WITH DIFFERENTIAL, COMPRESSION;
GO

-- 4. Restore Sequence (Example)
-- Scenario: Recovering to a specific point in time

-- A. Restore Full Backup (NO RECOVERY = Wait for more backups)
RESTORE DATABASE [YourDatabase]
FROM DISK = 'C:\Backups\YourDatabase_Full.bak'
WITH NORECOVERY, REPLACE;

-- B. Restore Differential (If available)
RESTORE DATABASE [YourDatabase]
FROM DISK = 'C:\Backups\YourDatabase_Diff.bak'
WITH NORECOVERY;

-- C. Restore Log Backups
RESTORE LOG [YourDatabase]
FROM DISK = 'C:\Backups\YourDatabase_Log_1000.trn'
WITH NORECOVERY;

RESTORE LOG [YourDatabase]
FROM DISK = 'C:\Backups\YourDatabase_Log_1015.trn'
WITH NORECOVERY;

-- D. Recover Database (Bring online)
RESTORE DATABASE [YourDatabase] WITH RECOVERY;
GO

-- 5. Check Backup History
SELECT 
    s.database_name,
    m.physical_device_name,
    CAST(CAST(s.backup_size / 1000000 AS INT) AS VARCHAR(14)) + ' ' + 'MB' AS bkSize,
    CAST(DATEDIFF(second, s.backup_start_date, s.backup_finish_date) AS VARCHAR(4)) + ' ' + 'Seconds' AS TimeTaken,
    s.backup_start_date,
    CASE s.[type]
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Transaction Log'
    END AS BackupType
FROM msdb.dbo.backupset s
INNER JOIN msdb.dbo.backupmediafamily m ON s.media_set_id = m.media_set_id
ORDER BY s.backup_start_date DESC;
GO
