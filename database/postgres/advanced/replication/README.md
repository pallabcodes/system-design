# PostgreSQL Replication

## Overview

PostgreSQL replication is a powerful feature that allows you to create and maintain multiple copies of the same database for high availability, load balancing, and disaster recovery. This guide covers all major replication methods available in PostgreSQL.

## Table of Contents

1. [Replication Types](#replication-types)
2. [Streaming Replication](#streaming-replication)
3. [Logical Replication](#logical-replication)
4. [Synchronous vs Asynchronous](#synchronous-vs-asynchronous)
5. [Replication Slots](#replication-slots)
6. [Cascading Replication](#cascading-replication)
7. [Monitoring Replication](#monitoring-replication)
8. [Failover and Switchover](#failover-and-switchover)
9. [Replication Topologies](#replication-topologies)
10. [Enterprise Replication Patterns](#enterprise-replication-patterns)

## Replication Types

### Overview of Replication Methods

PostgreSQL supports several replication methods:

1. **Streaming Replication**: Physical replication using WAL streaming
2. **Logical Replication**: Replicates changes at the table level
3. **File-based Log Shipping**: Basic WAL file shipping
4. **Trigger-based Replication**: Custom replication solutions
5. **Third-party Tools**: pglogical, Bucardo, Slony-I

### Comparison of Replication Types

| Feature | Streaming Replication | Logical Replication | File-based Log Shipping |
|---------|---------------------|-------------------|----------------------|
| Data Type | Physical | Logical | Physical |
| Granularity | Database | Table | Database |
| Version Compatibility | Same major version | Different versions | Same major version |
| DDL Replication | Automatic | Manual configuration | Automatic |
| Conflict Resolution | None | Built-in | None |
| Performance Impact | Low | Medium | High |
| Use Cases | HA, DR | Data integration, upgrades | Basic HA |

## Streaming Replication

### Master-Slave Setup

#### Primary Server Configuration

```ini
# postgresql.conf on primary
wal_level = replica
max_wal_senders = 10
wal_keep_segments = 64
archive_mode = on
archive_command = 'cp %p /archive/%f'
listen_addresses = '*'

# pg_hba.conf on primary
host replication replica_user 192.168.1.0/24 scram-sha-256
```

#### Replica Server Configuration

```bash
# Create replication user on primary
psql -c "CREATE USER replica_user REPLICATION ENCRYPTED PASSWORD 'secure_password';"

# Take base backup
pg_basebackup -h primary.example.com -D /var/lib/postgresql/data -U replica_user -v -P -X stream

# Create standby.signal file
touch /var/lib/postgresql/data/standby.signal

# Configure recovery.conf (PostgreSQL 12+) or postgresql.conf (older versions)
cat > /var/lib/postgresql/data/postgresql.conf << EOF
primary_conninfo = 'host=primary.example.com port=5432 user=replica_user password=secure_password application_name=replica1'
recovery_target_timeline = 'latest'
restore_command = 'cp /archive/%f %p'
EOF
```

### Hot Standby Configuration

```ini
# postgresql.conf on replica
hot_standby = on
max_standby_archive_delay = 30s
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
hot_standby_feedback = on
```

### Read-Only Queries on Replicas

```sql
-- Enable read-only queries on hot standby
ALTER SYSTEM SET hot_standby = on;

-- Check if replica is in recovery mode
SELECT pg_is_in_recovery();

-- Monitor read-only query performance
SELECT
    datname,
    usename,
    application_name,
    client_addr,
    state,
    wait_event_type,
    wait_event,
    now() - query_start AS duration
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY query_start;
```

## Logical Replication

### Publication and Subscription Setup

#### Create Publication on Primary

```sql
-- Create publication for specific tables
CREATE PUBLICATION sales_pub
    FOR TABLE sales, customers, products;

-- Create publication for all tables
CREATE PUBLICATION all_tables_pub
    FOR ALL TABLES;

-- Create publication with row filtering
CREATE PUBLICATION active_customers_pub
    FOR TABLE customers
    WHERE (active = true);

-- Create publication with column filtering
CREATE PUBLICATION customer_names_pub
    FOR TABLE customers (customer_id, first_name, last_name, email);
```

#### Create Subscription on Replica

```sql
-- Create subscription
CREATE SUBSCRIPTION sales_sub
    CONNECTION 'host=primary.example.com port=5432 user=replication_user dbname=sales_db'
    PUBLICATION sales_pub;

-- Create subscription with custom options
CREATE SUBSCRIPTION sales_sub
    CONNECTION 'host=primary.example.com port=5432 user=replication_user dbname=sales_db'
    PUBLICATION sales_pub
    WITH (
        copy_data = false,
        enabled = false,
        create_slot = false,
        slot_name = 'custom_slot'
    );

-- Enable subscription
ALTER SUBSCRIPTION sales_sub ENABLE;
```

### Logical Replication Monitoring

```sql
-- Check subscription status
SELECT
    subname,
    subenabled,
    subslotname,
    subpublications,
    subconninfo
FROM pg_subscription;

-- Monitor replication lag
SELECT
    slot_name,
    slot_type,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_type = 'logical';

-- Check publication status
SELECT
    pubname,
    puballtables,
    pubinsert,
    pubupdate,
    pubdelete
FROM pg_publication;
```

### Conflict Resolution

```sql
-- Handle conflicts in logical replication
-- Conflicts occur when the same row is modified on both publisher and subscriber

-- Conflict resolution strategies:
-- 1. Last update wins (default)
-- 2. Custom conflict resolution functions
-- 3. Skip conflicting transactions

-- Example: Custom conflict resolver
CREATE OR REPLACE FUNCTION resolve_inventory_conflict()
RETURNS TRIGGER AS $$
BEGIN
    -- If conflict, keep the higher quantity
    IF OLD.quantity != NEW.quantity THEN
        NEW.quantity := GREATEST(OLD.quantity, NEW.quantity);
        RAISE NOTICE 'Resolved inventory conflict: kept higher quantity %', NEW.quantity;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Skip conflicting transaction
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Apply to replicated tables
CREATE TRIGGER resolve_inventory_conflicts
    BEFORE INSERT OR UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION resolve_inventory_conflict();
```

## Synchronous vs Asynchronous

### Asynchronous Replication

#### Configuration
```ini
# postgresql.conf
synchronous_standby_names = ''  # Empty for async (default)
```

#### Characteristics
- **Performance**: High throughput, low latency impact on primary
- **Durability**: Potential data loss in case of primary failure
- **Use Cases**: High-performance applications, read scaling
- **Recovery**: May lose transactions not yet replicated

### Synchronous Replication

#### Configuration
```ini
# postgresql.conf
synchronous_standby_names = 'FIRST 1 (standby1)'
# or
synchronous_standby_names = 'ANY 2 (standby1, standby2)'
```

#### Characteristics
- **Performance**: Lower throughput, higher latency on primary
- **Durability**: Zero data loss guarantee
- **Use Cases**: Financial systems, critical applications
- **Recovery**: Guaranteed consistency

### Semi-Synchronous Replication

```ini
# Priority-based synchronous replication
synchronous_standby_names = 'FIRST 2 (standby1, standby2, standby3)'

# ANY synchronous replication (PostgreSQL 9.6+)
synchronous_standby_names = 'ANY 2 (standby1, standby2, standby3)'
```

## Replication Slots

### Physical Replication Slots

```sql
-- Create physical replication slot
SELECT pg_create_physical_replication_slot('standby_slot');

-- Monitor replication slots
SELECT
    slot_name,
    slot_type,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag,
    wal_status
FROM pg_replication_slots;

-- Drop unused replication slot
SELECT pg_drop_replication_slot('old_slot');
```

### Logical Replication Slots

```sql
-- Create logical replication slot
SELECT pg_create_logical_replication_slot('sales_slot', 'pgoutput');

-- Create publication using existing slot
CREATE PUBLICATION sales_pub
    FOR TABLE sales
    WITH (connect = false);  -- Don't connect immediately

-- Create subscription with existing slot
CREATE SUBSCRIPTION sales_sub
    CONNECTION 'conninfo'
    PUBLICATION sales_pub
    WITH (create_slot = false, slot_name = 'sales_slot');
```

### Replication Slot Management

```sql
-- Monitor slot disk usage
SELECT
    slot_name,
    slot_type,
    pg_size_pretty(pg_wal_slot_advance(slot_name)) AS slot_size
FROM pg_replication_slots;

-- Advance replication slot (careful!)
SELECT pg_replication_slot_advance('slot_name', '0/12345678');

-- Clean up old replication slots
CREATE OR REPLACE FUNCTION cleanup_old_replication_slots(max_age_days INTEGER DEFAULT 7)
RETURNS VOID AS $$
DECLARE
    slot_record RECORD;
BEGIN
    FOR slot_record IN
        SELECT slot_name
        FROM pg_replication_slots
        WHERE NOT active
          AND slot_type = 'physical'
          AND pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 0
    LOOP
        RAISE NOTICE 'Dropping inactive replication slot: %', slot_record.slot_name;
        PERFORM pg_drop_replication_slot(slot_record.slot_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## Cascading Replication

### Multi-Level Replication Setup

```
Primary (pg1)
├── Standby1 (pg2) - Direct replica
│   └── Standby1-1 (pg4) - Cascading replica
├── Standby2 (pg3) - Direct replica
│   ├── Standby2-1 (pg5) - Cascading replica
│   └── Standby2-2 (pg6) - Cascading replica
```

#### Cascading Replica Configuration

```ini
# postgresql.conf on cascading replica (pg4)
primary_conninfo = 'host=pg2 port=5432 user=replication_user application_name=cascading_replica'
recovery_target_timeline = 'latest'
restore_command = 'cp /archive/%f %p'
```

### Benefits and Considerations

```sql
-- Monitor cascading replication chain
WITH RECURSIVE replication_chain AS (
    -- Base case: direct standbys
    SELECT
        application_name,
        client_addr,
        state,
        sync_state,
        1 as level,
        application_name as path
    FROM pg_stat_replication
    WHERE client_addr IS NOT NULL

    UNION ALL

    -- Recursive case: cascading standbys
    SELECT
        r.application_name,
        r.client_addr,
        r.state,
        r.sync_state,
        rc.level + 1,
        rc.path || ' -> ' || r.application_name
    FROM pg_stat_replication r
    JOIN replication_chain rc ON r.client_addr = rc.client_addr
)
SELECT * FROM replication_chain ORDER BY level, application_name;
```

## Monitoring Replication

### Replication Lag Monitoring

```sql
-- Physical replication lag
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)) AS write_lag,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn)) AS flush_lag,
    pg_size_pretty(pg_wal_lsn_diff(flush_lsn, replay_lsn)) AS replay_lag,
    now() - write_lag AS time_lag
FROM pg_stat_replication;
```

### Logical Replication Monitoring

```sql
-- Logical replication lag
SELECT
    slot_name,
    slot_type,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

### Comprehensive Replication Health Check

```sql
CREATE OR REPLACE FUNCTION check_replication_health()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    recommendation TEXT
) AS $$
DECLARE
    replica_count INTEGER;
    lag_threshold INTERVAL := '5 minutes';
    max_lag INTERVAL;
BEGIN
    -- Check if we have replicas
    SELECT count(*) INTO replica_count FROM pg_stat_replication;

    IF replica_count = 0 THEN
        RETURN QUERY SELECT
            'replica_count'::TEXT,
            'WARNING'::TEXT,
            'No active replicas found'::TEXT,
            'Consider setting up replication for high availability'::TEXT;
    END IF;

    -- Check replication lag
    SELECT max(now() - replay_lag) INTO max_lag
    FROM (
        SELECT application_name,
               now() - pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) * interval '1 microsecond' as replay_lag
        FROM pg_stat_replication
    ) lag_check;

    IF max_lag > lag_threshold THEN
        RETURN QUERY SELECT
            'replication_lag'::TEXT,
            'CRITICAL'::TEXT,
            format('Maximum replication lag: %s', max_lag),
            'Check network connectivity and replica performance'::TEXT;
    END IF;

    -- Check WAL sender status
    IF EXISTS (SELECT 1 FROM pg_stat_replication WHERE state != 'streaming') THEN
        RETURN QUERY SELECT
            'wal_sender_status'::TEXT,
            'WARNING'::TEXT,
            'Some replicas are not in streaming state'::TEXT,
            'Investigate replica connectivity and configuration'::TEXT;
    END IF;

    -- Check replication slots
    IF EXISTS (
        SELECT 1 FROM pg_replication_slots
        WHERE active = false
          AND pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 1000000
    ) THEN
        RETURN QUERY SELECT
            'inactive_slots'::TEXT,
            'WARNING'::TEXT,
            'Inactive replication slots consuming WAL'::TEXT,
            'Drop unused replication slots'::TEXT;
    END IF;

    -- All checks passed
    RETURN QUERY SELECT
        'overall_health'::TEXT,
        'HEALTHY'::TEXT,
        format('%s active replicas', replica_count),
        'Replication is functioning normally'::TEXT;

END;
$$ LANGUAGE plpgsql;
```

## Failover and Switchover

### Planned Switchover (Switchover)

```bash
#!/bin/bash
# Planned switchover script

PRIMARY_HOST="pg-primary"
STANDBY_HOST="pg-standby"
REPLICATION_USER="replication_user"

echo "Starting planned switchover..."

# Check if standby is ready
ssh $STANDBY_HOST "psql -c 'SELECT pg_is_in_recovery();'" | grep -q "f"
if [ $? -ne 0 ]; then
    echo "ERROR: Standby is not ready for switchover"
    exit 1
fi

# Promote standby to primary
ssh $STANDBY_HOST "psql -c 'SELECT pg_promote();'"

# Wait for promotion to complete
sleep 10

# Update application configuration to point to new primary
echo "Switching application to new primary: $STANDBY_HOST"

# Reconfigure old primary as new standby
ssh $PRIMARY_HOST "psql -c 'SELECT pg_start_backup(''switchover_backup'');'"
ssh $PRIMARY_HOST "systemctl stop postgresql"

# Copy data from new primary to old primary
rsync -av --delete $STANDBY_HOST:/var/lib/postgresql/data/ /var/lib/postgresql/data/

# Configure old primary as standby
ssh $PRIMARY_HOST "touch /var/lib/postgresql/data/standby.signal"
ssh $PRIMARY_HOST "cat > /var/lib/postgresql/data/postgresql.conf << EOF
primary_conninfo = 'host=$STANDBY_HOST port=5432 user=$REPLICATION_USER'
recovery_target_timeline = 'latest'
EOF"

# Start old primary as new standby
ssh $PRIMARY_HOST "systemctl start postgresql"

echo "Switchover completed successfully"
```

### Automatic Failover

#### Using repmgr

```bash
# Install repmgr
sudo apt-get install postgresql-13-repmgr

# Configure repmgr
cat > /etc/repmgr.conf << EOF
node_id=1
node_name=pg-primary
conninfo='host=pg-primary port=5432 user=repmgr dbname=repmgr'
pg_bindir=/usr/lib/postgresql/13/bin
data_directory=/var/lib/postgresql/data
failover=automatic
promote_command='/usr/bin/repmgr standby promote'
follow_command='/usr/bin/repmgr standby follow'
EOF

# Register primary
repmgr primary register

# Register standby
repmgr standby register

# Monitor and automatic failover
repmgr daemon
```

#### Using Patroni

```yaml
# patroni.yml
scope: postgres-cluster
name: postgresql0
restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.0.1:8008
etcd:
  host: 127.0.0.1:2379
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
  initdb:
  - encoding: UTF8
  - data-checksums
  pg_hba:
  - host replication replicator 0.0.0.0/0 md5
  - host all all 0.0.0.0/0 md5
postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.0.0.1:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: rep-pass
    superuser:
      username: postgres
      password: zalando
  parameters:
    unix_socket_directories: '.'
```

## Replication Topologies

### Single Primary, Multiple Standbys

```
Primary
├── Standby1 (sync)
├── Standby2 (async)
└── Standby3 (async)
```

#### Configuration
```ini
# Synchronous standby
synchronous_standby_names = 'FIRST 1 (standby1)'

# Asynchronous standbys
# standby2 and standby3 use default async replication
```

### Multi-Primary (Bidirectional)

```sql
-- Using logical replication for multi-master
-- Publisher 1
CREATE PUBLICATION pub1 FOR TABLE users, orders;
CREATE SUBSCRIPTION sub1
    CONNECTION 'host=server2 port=5432 user=replication dbname=mydb'
    PUBLICATION pub2;

-- Publisher 2
CREATE PUBLICATION pub2 FOR TABLE users, orders;
CREATE SUBSCRIPTION sub2
    CONNECTION 'host=server1 port=5432 user=replication dbname=mydb'
    PUBLICATION pub1;
```

### Star Topology

```
Central Hub
├── Branch1
├── Branch2
└── Branch3
```

### Ring Topology

```
Server1 → Server2 → Server3 → Server1
```

## Enterprise Replication Patterns

### Geographic Replication

#### Cross-Region Replication Setup

```bash
# AWS cross-region replication
# Primary in us-east-1, replica in eu-west-1

# Configure primary
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (eu-west-1-standby)';

# Configure replica
primary_conninfo = 'host=primary-endpoint.us-east-1.rds.amazonaws.com port=5432 user=replication'
```

### Read Replica Scaling

#### Load Balancing Configuration

```bash
# Configure pgpool-II for load balancing
# pgpool.conf
listen_addresses = '*'
port = 9999

backend_hostname0 = 'primary.example.com'
backend_port0 = 5432
backend_weight0 = 0

backend_hostname1 = 'replica1.example.com'
backend_port1 = 5432
backend_weight1 = 1

backend_hostname2 = 'replica2.example.com'
backend_port2 = 5432
backend_weight2 = 1

load_balance_mode = on
```

#### Application-Level Load Balancing

```python
# Python application with read/write splitting
import psycopg2
from psycopg2 import extras

class DatabaseConnection:
    def __init__(self):
        self.primary_conn = psycopg2.connect("host=primary dbname=mydb")
        self.replica_conns = [
            psycopg2.connect("host=replica1 dbname=mydb"),
            psycopg2.connect("host=replica2 dbname=mydb")
        ]
        self.replica_index = 0

    def get_connection(self, read_only=False):
        if read_only:
            conn = self.replica_conns[self.replica_index]
            self.replica_index = (self.replica_index + 1) % len(self.replica_conns)
            return conn
        else:
            return self.primary_conn

# Usage
db = DatabaseConnection()

# Write operations use primary
with db.get_connection(read_only=False) as conn:
    # INSERT, UPDATE, DELETE operations

# Read operations use replicas
with db.get_connection(read_only=True) as conn:
    # SELECT operations
```

### Disaster Recovery with Replication

#### Multi-Site DR Setup

```bash
# Three-site disaster recovery
# Site A: Primary production
# Site B: Hot standby (synchronous)
# Site C: Warm standby (asynchronous, different region)

# Site A configuration
synchronous_standby_names = 'FIRST 1 (site_b_standby)'

# Site B configuration
primary_conninfo = 'host=site_a_primary application_name=site_b_hot_standby'
# synchronous replication

# Site C configuration
primary_conninfo = 'host=site_a_primary application_name=site_c_warm_standby'
# asynchronous replication

# Automated failover script
#!/bin/bash
PRIMARY_SITE="site_a"
BACKUP_SITE="site_b"
DR_SITE="site_c"

# Check if primary is accessible
if ! nc -z $PRIMARY_SITE 5432; then
    echo "Primary site unreachable, initiating failover..."

    # Promote hot standby to primary
    ssh $BACKUP_SITE "psql -c 'SELECT pg_promote();'"

    # Update DNS/application configuration
    update_dns_records $BACKUP_SITE

    # Reconfigure DR site to follow new primary
    ssh $DR_SITE "psql -c \"ALTER SYSTEM SET primary_conninfo = 'host=$BACKUP_SITE';\""
    ssh $DR_SITE "psql -c 'SELECT pg_reload_conf();'"
fi
```

### Replication for Analytics

#### OLTP to OLAP Replication

```sql
-- Logical replication from OLTP to analytics database
-- Publisher (OLTP system)
CREATE PUBLICATION analytics_pub
    FOR TABLE sales, customers, products, inventory;

-- Subscriber (Analytics system)
CREATE SUBSCRIPTION analytics_sub
    CONNECTION 'host=oltp-server port=5432 user=analytics_user dbname=production'
    PUBLICATION analytics_pub;

-- Create analytics views on subscriber
CREATE MATERIALIZED VIEW sales_summary AS
SELECT
    date_trunc('month', sale_date) as month,
    product_category,
    SUM(quantity) as total_quantity,
    SUM(total_amount) as total_revenue,
    COUNT(DISTINCT customer_id) as unique_customers
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY date_trunc('month', sale_date), product_category;

-- Refresh analytics data
REFRESH MATERIALIZED VIEW CONCURRENTLY sales_summary;
```

### Compliance and Auditing with Replication

#### Audit Trail Replication

```sql
-- Replicate audit logs to separate audit database
-- Publisher
CREATE PUBLICATION audit_pub FOR TABLE audit_log, security_events;

-- Subscriber (Audit database)
CREATE SUBSCRIPTION audit_sub
    CONNECTION 'host=production-db port=5432 user=audit_user dbname=production'
    PUBLICATION audit_pub;

-- Compliance reporting on audit database
CREATE OR REPLACE FUNCTION generate_compliance_report(start_date DATE, end_date DATE)
RETURNS TABLE (
    report_date DATE,
    total_events BIGINT,
    security_incidents BIGINT,
    compliance_violations BIGINT,
    audit_coverage DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        current_date,
        COUNT(*) as total_events,
        COUNT(CASE WHEN event_type = 'security' THEN 1 END) as security_incidents,
        COUNT(CASE WHEN event_type = 'violation' THEN 1 END) as compliance_violations,
        (COUNT(*)::DECIMAL / expected_daily_events) * 100 as audit_coverage
    FROM audit_log
    WHERE event_date BETWEEN start_date AND end_date;
END;
$$ LANGUAGE plpgsql;
```

This comprehensive replication guide covers all major PostgreSQL replication methods, from basic streaming replication to advanced enterprise topologies, with practical examples for monitoring, failover, and disaster recovery scenarios.
