# PostgreSQL Backup and Recovery

## Overview

This guide covers comprehensive backup and recovery strategies for PostgreSQL databases, including physical backups, logical backups, continuous archiving, and disaster recovery planning. Understanding these concepts is crucial for ensuring data durability and business continuity.

## Table of Contents

1. [Backup Types and Strategies](#backup-types-and-strategies)
2. [Physical Backups](#physical-backups)
3. [Logical Backups](#logical-backups)
4. [Continuous Archiving (WAL)](#continuous-archiving-wal)
5. [Backup Automation](#backup-automation)
6. [Recovery Procedures](#recovery-procedures)
7. [Monitoring and Validation](#monitoring-and-validation)
8. [Disaster Recovery](#disaster-recovery)
9. [Enterprise Patterns](#enterprise-patterns)

## Backup Types and Strategies

### Understanding Backup Types

#### Physical vs Logical Backups

**Physical Backups:**
- Exact copies of database files
- Include all databases and tablespaces
- Faster to restore than logical backups
- Can only be restored to similar PostgreSQL versions
- Smaller backup size

**Logical Backups:**
- SQL statements to recreate database objects and data
- Human-readable and editable
- Can be restored to different PostgreSQL versions
- Can restore individual objects
- Larger backup size

#### Backup Strategies

```sql
-- Different backup strategies for different RTO/RPO requirements

-- Full Backup Strategy
-- Pros: Complete recovery, simple restoration
-- Cons: Large storage requirements, longer backup time
-- Use case: Small databases, regulatory requirements

-- Incremental Backup Strategy
-- Pros: Smaller backups, faster backup time
-- Cons: Complex recovery process
-- Use case: Large databases with high change rates

-- Differential Backup Strategy
-- Pros: Balance between full and incremental
-- Cons: Larger than incremental but simpler recovery
-- Use case: Medium-sized databases
```

## Physical Backups

### File System Level Backups

#### Using pg_basebackup

```bash
# Basic physical backup
pg_basebackup -h localhost -D /backup/base_backup -U postgres -v -P

# Compressed backup
pg_basebackup -h localhost -D /backup/base_backup -U postgres -Ft -z -Z 9

# Parallel backup for faster processing
pg_basebackup -h localhost -D /backup/base_backup -U postgres -Ft -z -Z 9 -j 4

# Backup with progress reporting
pg_basebackup -h localhost -D /backup/base_backup -U postgres -v -P --progress
```

#### Low-Level File System Backup

```bash
# Consistent backup procedure
# 1. Force checkpoint to ensure clean shutdown
psql -c "CHECKPOINT;"

# 2. Stop PostgreSQL (cold backup)
sudo systemctl stop postgresql

# 3. Backup data directory
tar -czf /backup/postgresql_backup_$(date +%Y%m%d_%H%M%S).tar.gz /var/lib/postgresql/data

# 4. Start PostgreSQL
sudo systemctl start postgresql

# For hot backup (online), use pg_start_backup and pg_stop_backup
psql -c "SELECT pg_start_backup('hot_backup_$(date +%Y%m%d_%H%M%S)');"
tar -czf /backup/hot_backup_$(date +%Y%m%d_%H%M%S).tar.gz /var/lib/postgresql/data
psql -c "SELECT pg_stop_backup();"
```

### Point-in-Time Recovery (PITR)

#### Setting Up WAL Archiving

```bash
# postgresql.conf configuration for PITR
wal_level = replica                    # or higher
archive_mode = on                      # enable archiving
archive_command = 'cp %p /archive/%f'  # archive command
archive_timeout = 60                   # force WAL switch every 60 seconds

# Create archive directory
mkdir -p /archive
chown postgres:postgres /archive

# Restart PostgreSQL
sudo systemctl restart postgresql
```

#### Base Backup for PITR

```bash
# Create base backup with WAL archiving
pg_basebackup -h localhost -D /backup/pitr_base -U postgres -Ft -z \
  -X stream -c fast --checkpoint=fast

# The -X stream option includes required WAL segments
# The -c fast option forces a fast checkpoint
```

## Logical Backups

### pg_dump Usage

#### Database-Level Backup

```bash
# Full database backup
pg_dump -h localhost -U postgres -d mydatabase > database_backup.sql

# Compressed backup
pg_dump -h localhost -U postgres -d mydatabase | gzip > database_backup.sql.gz

# Custom format (compressed and faster)
pg_dump -h localhost -U postgres -d mydatabase -Fc > database_backup.dump

# Directory format (parallel processing)
pg_dump -h localhost -U postgres -d mydatabase -Fd -j 4 -f /backup/database_backup_dir
```

#### Table-Level Backup

```bash
# Backup specific tables
pg_dump -h localhost -U postgres -d mydatabase -t users -t orders > tables_backup.sql

# Exclude specific tables
pg_dump -h localhost -U postgres -d mydatabase --exclude-table=audit_log > database_no_audit.sql

# Schema-only backup
pg_dump -h localhost -U postgres -d mydatabase -s > schema_only.sql

# Data-only backup
pg_dump -h localhost -U postgres -d mydatabase -a > data_only.sql
```

#### Advanced pg_dump Options

```bash
# Backup with progress and verbose output
pg_dump -h localhost -U postgres -d mydatabase -v --progress > backup.sql

# Include CREATE DATABASE statement
pg_dump -h localhost -U postgres -d mydatabase -C > backup_with_create.sql

# Use INSERT instead of COPY (slower but more compatible)
pg_dump -h localhost -U postgres -d mydatabase --inserts > backup_inserts.sql

# Backup large objects
pg_dump -h localhost -U postgres -d mydatabase -b > backup_with_blobs.sql

# Clean backup (include DROP statements)
pg_dump -h localhost -U postgres -d mydatabase --clean --if-exists > clean_backup.sql
```

### pg_restore Usage

#### Restoring Backups

```bash
# Restore from custom format
pg_restore -h localhost -U postgres -d mydatabase -v backup.dump

# Restore from directory format
pg_restore -h localhost -U postgres -d mydatabase -v /backup/database_backup_dir

# Restore specific tables
pg_restore -h localhost -U postgres -d mydatabase -t users -t orders backup.dump

# Restore with different owner
pg_restore -h localhost -U postgres -d mydatabase --no-owner backup.dump

# Restore with verbose output
pg_restore -h localhost -U postgres -d mydatabase -v backup.dump

# List contents of backup
pg_restore -l backup.dump
```

## Continuous Archiving (WAL)

### WAL Archiving Setup

#### Configuration

```ini
# postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'cp %p /archive/%f'
archive_timeout = 60

# For reliability, use more robust archive commands
archive_command = 'rsync -a %p /archive/%f && echo "Archive successful" >> /var/log/pg_archive.log'

# Or use archive_command with error handling
archive_command = 'if [ -f /archive/%f ]; then echo "Archive %f already exists" 1>&2; else cp %p /archive/%f; fi'
```

#### Monitoring WAL Archiving

```sql
-- Check WAL archiving status
SELECT * FROM pg_stat_archiver;

-- Check for failed archives
SELECT * FROM pg_stat_archiver
WHERE failed_count > 0;

-- Monitor WAL generation rate
SELECT
    now(),
    total_wal_size,
    wal_rate_mb_per_sec
FROM (
    SELECT
        pg_size_pretty(sum(size)) as total_wal_size,
        sum(size) / extract(epoch from (now() - min(modification))) / 1024 / 1024 as wal_rate_mb_per_sec
    FROM pg_ls_waldir()
) stats;
```

### WAL Backup Strategies

#### WAL Shipping

```bash
# Basic WAL shipping setup
# On primary server - configure recovery.conf for standby
standby_mode = 'on'
primary_conninfo = 'host=primary.example.com port=5432 user=replication password=replication_password'
trigger_file = '/tmp/postgresql.trigger.5432'

# WAL shipping with compression
archive_command = 'gzip < %p > /archive/%f.gz'
restore_command = 'gunzip < /archive/%f.gz > %p'
```

#### WAL Archiving Best Practices

```bash
# Multi-destination archiving
archive_command = '
    cp %p /archive/local/%f &&
    rsync -a %p backup1.example.com:/archive/%f &&
    rsync -a %p backup2.example.com:/archive/%f
'

# Archive command with verification
archive_command = '
    if cp %p /archive/%f && [ $(stat -c%s /archive/%f) -eq $(stat -c%s %p) ]; then
        echo "Archive successful: %f" >> /var/log/pg_archive.log
    else
        echo "Archive failed: %f" >> /var/log/pg_archive.log && exit 1
    fi
'
```

## Backup Automation

### Automated Backup Scripts

#### Bash Backup Script

```bash
#!/bin/bash
# PostgreSQL automated backup script

# Configuration
BACKUP_DIR="/backup"
RETENTION_DAYS=30
DATABASES=("mydb1" "mydb2")
HOST="localhost"
USER="postgres"

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Function to backup single database
backup_database() {
    local db=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${db}_backup_$timestamp.dump"

    echo "Backing up database: $db"

    # Create backup
    pg_dump -h $HOST -U $USER -d $db -Fc -v > $backup_file

    # Verify backup
    if [ $? -eq 0 ]; then
        echo "Backup successful: $backup_file"

        # Compress backup
        gzip $backup_file

        # Calculate checksum
        sha256sum ${backup_file}.gz > ${backup_file}.gz.sha256

        echo "Backup completed and compressed: ${backup_file}.gz"
    else
        echo "Backup failed for database: $db"
        exit 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    echo "Cleaning up backups older than $RETENTION_DAYS days"
    find $BACKUP_DIR -name "*.gz" -type f -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR -name "*.sha256" -type f -mtime +$RETENTION_DAYS -delete
}

# Main backup process
echo "Starting PostgreSQL backup at $(date)"

for db in "${DATABASES[@]}"; do
    backup_database $db
done

# Cleanup old backups
cleanup_old_backups

echo "Backup process completed at $(date)"
```

#### Cron-Based Automation

```bash
# Daily full backup at 2 AM
0 2 * * * /path/to/backup_script.sh

# Hourly WAL backup
0 * * * * /path/to/wal_backup_script.sh

# Weekly schema backup
0 3 * * 0 /path/to/schema_backup_script.sh
```

### pgBackRest Configuration

```ini
# pgBackRest configuration file
[global]
repo1-path=/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=6
log-level-console=info
log-level-file=debug

[my-stanza]
pg1-path=/var/lib/postgresql/data
pg1-port=5432
pg1-user=postgres
```

```bash
# Initialize stanza
pgbackrest --stanza=my-stanza --log-level-console=info stanza-create

# Full backup
pgbackrest --stanza=my-stanza --log-level-console=info backup

# Differential backup
pgbackrest --stanza=my-stanza --type=diff backup

# Incremental backup
pgbackrest --stanza=my-stanza --type=incr backup

# List backups
pgbackrest --stanza=my-stanza info
```

### Barman Configuration

```ini
# Barman configuration
[barman]
barman_home = /var/lib/barman
barman_user = barman
log_file = /var/log/barman/barman.log
compression = gzip

[pg]
description = "PostgreSQL Database"
conninfo = host=pg.example.com user=barman dbname=postgres
ssh_command = ssh postgres@pg.example.com
backup_method = rsync
reuse_backup = link
immediate_checkpoint = true
```

```bash
# Create backup
barman backup pg

# List backups
barman list-backup pg

# Show backup details
barman show-backup pg latest
```

## Recovery Procedures

### Point-in-Time Recovery

#### PITR Recovery Steps

```bash
# 1. Stop PostgreSQL
sudo systemctl stop postgresql

# 2. Backup current data directory (if needed)
mv /var/lib/postgresql/data /var/lib/postgresql/data_old

# 3. Restore base backup
tar -xzf /backup/base_backup.tar.gz -C /var/lib/postgresql/

# 4. Create recovery.conf
cat > /var/lib/postgresql/data/recovery.conf << EOF
restore_command = 'cp /archive/%f %p'
recovery_target_time = '2024-01-15 14:30:00'
recovery_target_action = 'promote'
EOF

# 5. Start PostgreSQL
sudo systemctl start postgresql

# Monitor recovery progress
tail -f /var/log/postgresql/postgresql.log
```

#### Recovery to Specific Point

```sql
-- Recover to specific transaction ID
recovery_target_xid = '123456'

-- Recover to specific timestamp
recovery_target_time = '2024-01-15 14:30:00 UTC'

-- Recover to specific named restore point
recovery_target_name = 'before_upgrade'

-- Recover to end of WAL
recovery_target = 'immediate'
```

### Database Object Recovery

#### Restoring Individual Tables

```bash
# Restore single table from logical backup
pg_restore -h localhost -U postgres -d mydatabase -t users backup.dump

# Restore table with dependencies
pg_restore -h localhost -U postgres -d mydatabase --table=users --table=user_roles backup.dump

# Restore to different schema
pg_restore -h localhost -U postgres -d mydatabase --table=users --schema=staging backup.dump
```

#### Partial Recovery

```sql
-- Restore only data (no schema changes)
pg_restore -h localhost -U postgres -d mydatabase -a backup.dump

-- Restore only schema (no data)
pg_restore -h localhost -U postgres -d mydatabase -s backup.dump

-- Selective restore using pg_restore list
pg_restore -l backup.dump | grep -E "(TABLE|INDEX)" > restore_list.txt
pg_restore -h localhost -U postgres -d mydatabase -L restore_list.txt backup.dump
```

## Monitoring and Validation

### Backup Validation

#### Automated Backup Testing

```bash
#!/bin/bash
# Backup validation script

validate_backup() {
    local backup_file=$1
    local db_name=$2

    echo "Validating backup: $backup_file"

    # Check if file exists and has content
    if [ ! -f "$backup_file" ] || [ ! -s "$backup_file" ]; then
        echo "ERROR: Backup file missing or empty"
        return 1
    fi

    # Check file integrity
    if ! gzip -t "$backup_file" 2>/dev/null; then
        echo "ERROR: Backup file corrupted"
        return 1
    fi

    # Test restore to temporary database
    local temp_db="backup_test_$(date +%s)"
    createdb "$temp_db"

    if pg_restore -d "$temp_db" "$backup_file" 2>/dev/null; then
        echo "SUCCESS: Backup restored successfully"

        # Run basic validation queries
        psql -d "$temp_db" -c "SELECT COUNT(*) FROM information_schema.tables;" > /dev/null

        if [ $? -eq 0 ]; then
            echo "SUCCESS: Database queries working"
        else
            echo "ERROR: Database queries failed"
            return 1
        fi
    else
        echo "ERROR: Backup restore failed"
        return 1
    fi

    # Clean up
    dropdb "$temp_db"

    return 0
}

# Usage
validate_backup "/backup/mydb_backup_20240115.dump.gz" "mydb"
```

#### Backup Metrics Monitoring

```sql
-- Backup performance monitoring
CREATE TABLE backup_metrics (
    backup_id SERIAL PRIMARY KEY,
    database_name VARCHAR(255),
    backup_type VARCHAR(50),  -- 'full', 'incremental', 'differential'
    backup_start TIMESTAMP,
    backup_end TIMESTAMP,
    backup_size_bytes BIGINT,
    compression_ratio DECIMAL(5,2),
    backup_status VARCHAR(20),
    error_message TEXT
);

-- Record backup metrics
INSERT INTO backup_metrics (
    database_name, backup_type, backup_start, backup_end,
    backup_size_bytes, compression_ratio, backup_status
) VALUES (
    'mydb', 'full', '2024-01-15 02:00:00', '2024-01-15 02:30:00',
    1073741824, 0.75, 'success'
);
```

### Recovery Testing

#### Disaster Recovery Drills

```bash
#!/bin/bash
# Disaster recovery testing script

# Simulate disaster
echo "Simulating database failure..."
sudo systemctl stop postgresql

# Backup current data
mv /var/lib/postgresql/data /var/lib/postgresql/data_backup

# Restore from backup
echo "Restoring from latest backup..."
pg_restore -h localhost -U postgres -d postgres -C latest_backup.dump

# Test application connectivity
echo "Testing application connectivity..."
if psql -h localhost -U app_user -d myapp -c "SELECT 1;" > /dev/null 2>&1; then
    echo "SUCCESS: Application can connect to restored database"
else
    echo "ERROR: Application cannot connect to restored database"
fi

# Measure recovery time
recovery_end=$(date +%s)
recovery_time=$((recovery_end - recovery_start))
echo "Recovery completed in $recovery_time seconds"

# Restore original data
mv /var/lib/postgresql/data_backup /var/lib/postgresql/data
sudo systemctl start postgresql
```

## Disaster Recovery

### Multi-Site Backup Strategy

#### Offsite Backup Replication

```bash
# Rsync to remote backup server
rsync -avz --delete /backup/ backup.example.com:/remote_backup/

# Cloud backup using AWS S3
aws s3 sync /backup/ s3://my-backup-bucket/postgres/

# Azure blob storage
az storage blob upload-batch --destination backup-container --source /backup/

# Google Cloud Storage
gsutil rsync -r /backup/ gs://my-backup-bucket/postgres/
```

#### Geographic Redundancy

```bash
# Multi-region backup strategy
#!/bin/bash

backup_to_regions() {
    local backup_file=$1

    # Primary region (local)
    cp $backup_file /backup/local/

    # Secondary region
    rsync $backup_file backup-us-west.example.com:/backup/

    # Tertiary region
    aws s3 cp $backup_file s3://backup-bucket-dr/postgres/

    # Archive region (long-term retention)
    aws s3 cp $backup_file s3://backup-archive-bucket/postgres/
}

# Usage
backup_to_regions "/backup/mydb_full_backup.dump.gz"
```

### Business Continuity Planning

#### Recovery Time Objective (RTO) and Recovery Point Objective (RPO)

```sql
-- RTO/RPO tracking and reporting
CREATE TABLE disaster_recovery_metrics (
    drill_id SERIAL PRIMARY KEY,
    drill_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scenario VARCHAR(100),  -- 'full_outage', 'data_corruption', 'site_failure'
    rto_target_minutes INTEGER,
    rto_actual_minutes INTEGER,
    rpo_target_minutes INTEGER,
    rpo_actual_minutes INTEGER,
    success BOOLEAN,
    lessons_learned TEXT
);

-- RTO/RPO calculation functions
CREATE OR REPLACE FUNCTION calculate_rto_compliance()
RETURNS TABLE (
    scenario VARCHAR(100),
    avg_rto_actual INTEGER,
    rto_target INTEGER,
    compliance_rate DECIMAL(5,2)
) AS $$
    SELECT
        scenario,
        AVG(rto_actual_minutes) as avg_rto_actual,
        AVG(rto_target_minutes) as rto_target,
        AVG(CASE WHEN rto_actual_minutes <= rto_target_minutes THEN 1 ELSE 0 END) as compliance_rate
    FROM disaster_recovery_metrics
    GROUP BY scenario;
$$ LANGUAGE SQL;
```

## Enterprise Patterns

### Backup Encryption

#### Encrypted Backups

```bash
# Encrypt backup with GPG
pg_dump -h localhost -U postgres mydb | gpg --encrypt --recipient backup@example.com > backup.sql.gpg

# Decrypt and restore
gpg --decrypt backup.sql.gpg | psql -h localhost -U postgres mydb

# Using pg_dump with built-in compression and encryption
pg_dump -h localhost -U postgres mydb -Fc | openssl enc -aes-256-cbc -salt -out backup.dump.enc

# Decrypt backup
openssl enc -d -aes-256-cbc -in backup.dump.enc | pg_restore -h localhost -U postgres -d mydb
```

### Automated Backup Verification

#### Comprehensive Backup Validation

```sql
-- Automated backup integrity checking
CREATE OR REPLACE FUNCTION verify_backup_integrity(backup_path TEXT)
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
DECLARE
    temp_db_name TEXT;
    table_count INTEGER;
    row_count BIGINT;
BEGIN
    -- Create temporary database for testing
    temp_db_name := 'backup_verify_' || extract(epoch from now())::text;
    EXECUTE format('CREATE DATABASE %I', temp_db_name);

    -- Attempt to restore backup
    BEGIN
        EXECUTE format('pg_restore -d %I %s', temp_db_name, backup_path);

        -- Basic integrity checks
        EXECUTE format('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ''public''', temp_db_name)
        INTO table_count;

        EXECUTE format('SELECT SUM(n_tup_ins) FROM pg_stat_user_tables', temp_db_name)
        INTO row_count;

        RETURN QUERY SELECT
            'table_count'::TEXT,
            'success'::TEXT,
            table_count::TEXT;

        RETURN QUERY SELECT
            'row_count'::TEXT,
            'success'::TEXT,
            row_count::TEXT;

    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'restore_test'::TEXT,
            'failed'::TEXT,
            SQLERRM;
    END;

    -- Cleanup
    EXECUTE format('DROP DATABASE %I', temp_db_name);

END;
$$ LANGUAGE plpgsql;
```

### Cloud-Native Backup Strategies

#### Kubernetes PostgreSQL Backup

```yaml
# Kubernetes CronJob for automated backups
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: postgres-backup
            image: postgres:13
            command:
            - /bin/bash
            - -c
            - |
              pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER $POSTGRES_DB | gzip > /backup/backup_$(date +%Y%m%d_%H%M%S).sql.gz
            env:
            - name: POSTGRES_HOST
              value: "postgres-service"
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
            - name: POSTGRES_DB
              value: "mydb"
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

#### Backup as a Service

```sql
-- Backup service integration
CREATE TABLE backup_service_jobs (
    job_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_provider VARCHAR(50),  -- 'aws_backup', 'azure_backup', 'gcp_backup'
    database_name VARCHAR(255),
    backup_type VARCHAR(20),
    scheduled_time TIMESTAMP,
    actual_start_time TIMESTAMP,
    completion_time TIMESTAMP,
    backup_location TEXT,
    backup_size_bytes BIGINT,
    status VARCHAR(20),
    error_message TEXT
);

-- Automated backup scheduling
CREATE OR REPLACE FUNCTION schedule_cloud_backup(
    database_name TEXT,
    backup_type TEXT DEFAULT 'full',
    retention_days INTEGER DEFAULT 30
)
RETURNS UUID AS $$
DECLARE
    job_id UUID;
BEGIN
    job_id := uuid_generate_v4();

    INSERT INTO backup_service_jobs (
        job_id, service_provider, database_name, backup_type,
        scheduled_time, status
    ) VALUES (
        job_id, 'aws_backup', database_name, backup_type,
        CURRENT_TIMESTAMP + INTERVAL '1 hour', 'scheduled'
    );

    -- Trigger cloud backup API call here
    -- Integration with AWS Backup, Azure Backup, etc.

    RETURN job_id;
END;
$$ LANGUAGE plpgsql;
```

This comprehensive backup and recovery guide covers all aspects of PostgreSQL data protection, from basic backup creation to enterprise disaster recovery planning, ensuring data durability and business continuity.
