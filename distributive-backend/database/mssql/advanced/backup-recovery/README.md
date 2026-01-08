# SQL Server Backup and Recovery

## Overview

This guide covers comprehensive backup and recovery strategies for SQL Server databases, including full backups, differential backups, transaction log backups, and disaster recovery planning. Understanding these concepts is crucial for ensuring data durability and business continuity.

## Table of Contents

1. [Backup Types](#backup-types)
2. [Full Backups](#full-backups)
3. [Differential Backups](#differential-backups)
4. [Transaction Log Backups](#transaction-log-backups)
5. [Backup Strategies](#backup-strategies)
6. [Recovery Models](#recovery-models)
7. [Restore Procedures](#restore-procedures)
8. [Backup Automation](#backup-automation)
9. [Enterprise Patterns](#enterprise-patterns)

## Backup Types

### Full Backup

Complete backup of the entire database.

```sql
-- Full database backup
BACKUP DATABASE SalesDB
TO DISK = 'C:\Backups\SalesDB_Full.bak'
WITH FORMAT, INIT, NAME = 'SalesDB Full Backup', COMPRESSION;
```

### Differential Backup

Backs up only changes since the last full backup.

```sql
-- Differential backup
BACKUP DATABASE SalesDB
TO DISK = 'C:\Backups\SalesDB_Diff.bak'
WITH DIFFERENTIAL, NAME = 'SalesDB Differential Backup', COMPRESSION;
```

### Transaction Log Backup

Backs up transaction log for point-in-time recovery.

```sql
-- Transaction log backup
BACKUP LOG SalesDB
TO DISK = 'C:\Backups\SalesDB_Log.trn'
WITH NAME = 'SalesDB Transaction Log Backup';
```

### File and Filegroup Backups

Backup specific files or filegroups.

```sql
-- Filegroup backup
BACKUP DATABASE SalesDB
FILEGROUP = 'PRIMARY'
TO DISK = 'C:\Backups\SalesDB_Primary.bak';

-- Multiple filegroups
BACKUP DATABASE SalesDB
FILEGROUP = 'FG1', FILEGROUP = 'FG2'
TO DISK = 'C:\Backups\SalesDB_FG.bak';
```

## Full Backups

### Basic Full Backup

```sql
-- Simple full backup
BACKUP DATABASE SalesDB
TO DISK = 'C:\Backups\SalesDB.bak';
```

### Full Backup with Options

```sql
-- Full backup with compression and encryption
BACKUP DATABASE SalesDB
TO DISK = 'C:\Backups\SalesDB.bak'
WITH 
    COMPRESSION,
    ENCRYPTION (
        ALGORITHM = AES_256,
        SERVER CERTIFICATE = BackupCertificate
    ),
    FORMAT,
    INIT,
    NAME = 'SalesDB Full Backup',
    DESCRIPTION = 'Full backup with compression and encryption',
    STATS = 10;  -- Progress every 10%
```

### Backup to Multiple Files

```sql
-- Backup to multiple files (striping)
BACKUP DATABASE SalesDB
TO DISK = 'C:\Backups\SalesDB_Part1.bak',
     DISK = 'D:\Backups\SalesDB_Part2.bak',
     DISK = 'E:\Backups\SalesDB_Part3.bak'
WITH FORMAT, INIT;
```

## Differential Backups

### Differential Backup

```sql
-- Differential backup
BACKUP DATABASE SalesDB
TO DISK = 'C:\Backups\SalesDB_Diff.bak'
WITH DIFFERENTIAL, COMPRESSION;
```

### Differential Backup Strategy

```sql
-- Typical schedule:
-- Sunday: Full backup
-- Monday-Saturday: Differential backups
-- Every hour: Transaction log backups
```

## Transaction Log Backups

### Transaction Log Backup

```sql
-- Transaction log backup
BACKUP LOG SalesDB
TO DISK = 'C:\Backups\SalesDB_Log.trn'
WITH COMPRESSION;
```

### Tail Log Backup

```sql
-- Tail log backup (before restore)
BACKUP LOG SalesDB
TO DISK = 'C:\Backups\SalesDB_TailLog.trn'
WITH NO_TRUNCATE, NOFORMAT, NOINIT;
```

## Recovery Models

### Full Recovery Model

```sql
-- Set to full recovery model
ALTER DATABASE SalesDB
SET RECOVERY FULL;

-- Requires transaction log backups
-- Allows point-in-time recovery
```

### Simple Recovery Model

```sql
-- Set to simple recovery model
ALTER DATABASE SalesDB
SET RECOVERY SIMPLE;

-- No transaction log backups needed
-- No point-in-time recovery
```

### Bulk-Logged Recovery Model

```sql
-- Set to bulk-logged recovery model
ALTER DATABASE SalesDB
SET RECOVERY BULK_LOGGED;

-- Minimal logging for bulk operations
-- Point-in-time recovery with limitations
```

## Restore Procedures

### Full Restore

```sql
-- Restore full backup
RESTORE DATABASE SalesDB
FROM DISK = 'C:\Backups\SalesDB_Full.bak'
WITH REPLACE, NORECOVERY;
```

### Restore with Differential

```sql
-- Restore full backup
RESTORE DATABASE SalesDB
FROM DISK = 'C:\Backups\SalesDB_Full.bak'
WITH NORECOVERY;

-- Restore differential backup
RESTORE DATABASE SalesDB
FROM DISK = 'C:\Backups\SalesDB_Diff.bak'
WITH NORECOVERY;

-- Restore transaction logs
RESTORE LOG SalesDB
FROM DISK = 'C:\Backups\SalesDB_Log1.trn'
WITH NORECOVERY;

RESTORE LOG SalesDB
FROM DISK = 'C:\Backups\SalesDB_Log2.trn'
WITH RECOVERY;  -- Database ready
```

### Point-in-Time Recovery

```sql
-- Restore to specific point in time
RESTORE DATABASE SalesDB
FROM DISK = 'C:\Backups\SalesDB_Full.bak'
WITH NORECOVERY;

RESTORE LOG SalesDB
FROM DISK = 'C:\Backups\SalesDB_Log.trn'
WITH RECOVERY, STOPAT = '2024-01-15 14:30:00';
```

## Backup Automation

### Maintenance Plan

```sql
-- Create backup maintenance plan using SQL Server Agent
-- Or use T-SQL scripts scheduled via SQL Server Agent
```

### Backup Script

```sql
-- Automated backup script
DECLARE @BackupPath NVARCHAR(255) = 'C:\Backups\';
DECLARE @DatabaseName NVARCHAR(255) = 'SalesDB';
DECLARE @FileName NVARCHAR(255) = @BackupPath + @DatabaseName + '_' + 
    FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + '.bak';

BACKUP DATABASE @DatabaseName
TO DISK = @FileName
WITH COMPRESSION, FORMAT, INIT;
```

## Enterprise Patterns

### Backup Verification

```sql
-- Verify backup
RESTORE VERIFYONLY
FROM DISK = 'C:\Backups\SalesDB.bak'
WITH CHECKSUM;
```

### Backup History

```sql
-- View backup history
SELECT 
    database_name,
    backup_start_date,
    backup_finish_date,
    type,
    physical_device_name,
    backup_size / 1024 / 1024 AS BackupSizeMB
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE database_name = 'SalesDB'
ORDER BY backup_start_date DESC;
```

## Best Practices

1. **Use appropriate recovery model** for your requirements
2. **Schedule regular backups** (full, differential, log)
3. **Test restore procedures** regularly
4. **Store backups offsite** for disaster recovery
5. **Use backup compression** to save space
6. **Verify backups** after creation
7. **Document recovery procedures**
8. **Monitor backup success/failure**
9. **Retain backups** according to retention policy
10. **Encrypt backups** for sensitive data

This guide provides comprehensive SQL Server backup and recovery strategies for ensuring data protection and business continuity.

