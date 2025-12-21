# PostgreSQL Performance Tuning

## Overview

Performance tuning in PostgreSQL involves optimizing database configuration, query execution, indexing strategies, and hardware utilization. This guide covers comprehensive performance optimization techniques for enterprise PostgreSQL deployments.

## Table of Contents

1. [System Configuration](#system-configuration)
2. [Memory Configuration](#memory-configuration)
3. [Storage Optimization](#storage-optimization)
4. [Query Optimization](#query-optimization)
5. [Index Optimization](#index-optimization)
6. [Connection Management](#connection-management)
7. [Monitoring and Diagnostics](#monitoring-and-diagnostics)
8. [Enterprise Patterns](#enterprise-patterns)

## System Configuration

### Kernel Parameters

```bash
# /etc/sysctl.conf optimizations for PostgreSQL

# Increase shared memory limits
kernel.shmmax = 68719476736  # 64GB
kernel.shmall = 16777216     # Support for shmmax

# Network tuning
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog = 65536

# Virtual memory
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.swappiness = 10

# File system
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500

# Apply changes
sudo sysctl -p
```

### PostgreSQL Configuration File

```ini
# postgresql.conf - Enterprise tuning example

# Memory Settings
shared_buffers = 8GB                    # 25% of RAM for dedicated server
effective_cache_size = 24GB             # 75% of total RAM
work_mem = 64MB                         # Per-connection sort memory
maintenance_work_mem = 2GB              # For maintenance operations
wal_buffers = 16MB                      # WAL buffer size

# Checkpoint Settings
checkpoint_completion_target = 0.9      # Spread checkpoint I/O
checkpoint_timeout = 30min              # Checkpoint frequency
max_wal_size = 4GB                      # WAL size limit
min_wal_size = 1GB                      # Minimum WAL size

# Connection Settings
max_connections = 200                   # Maximum concurrent connections
shared_preload_libraries = 'pg_stat_statements, auto_explain'

# Logging
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'ddl'
log_duration = on
log_min_duration_statement = 1000       # Log queries > 1 second

# Autovacuum Settings
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 20s
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.02
autovacuum_analyze_scale_factor = 0.01

# Parallel Query Settings
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4

# JIT Compilation
jit = on
jit_above_cost = 100000
jit_inline_above_cost = 500000
jit_optimize_above_cost = 500000
```

## Memory Configuration

### Memory Allocation Strategy

```sql
-- Calculate optimal memory settings
SELECT
    pg_size_pretty(physical_memory_bytes * 0.25) AS shared_buffers,
    pg_size_pretty(physical_memory_bytes * 0.75) AS effective_cache_size,
    pg_size_pretty((physical_memory_bytes * 0.25) / max_connections / 10) AS work_mem
FROM (
    SELECT
        (setting::bigint * 1024) AS physical_memory_bytes,
        current_setting('max_connections')::bigint AS max_connections
    FROM pg_settings
    WHERE name = 'shared_buffers'
) AS config;

-- Monitor memory usage
SELECT
    name,
    setting,
    unit,
    context
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'effective_cache_size',
    'work_mem',
    'maintenance_work_mem',
    'wal_buffers'
);
```

### Work Memory Tuning

```sql
-- Monitor work memory usage
SELECT
    datname,
    usename,
    pid,
    query,
    state,
    pg_size_pretty((pg_stat_get_backend_work_mem(pid))) AS work_mem_used
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND state = 'active'
ORDER BY pg_stat_get_backend_work_mem(pid) DESC;

-- Estimate optimal work_mem
SELECT
    (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') AS active_connections,
    pg_size_pretty((
        SELECT setting::bigint * 1024 * 1024
        FROM pg_settings
        WHERE name = 'shared_buffers'
    ) / (
        SELECT GREATEST(count(*), 1)
        FROM pg_stat_activity
        WHERE state = 'active'
    ) / 20) AS suggested_work_mem; -- 5% of shared_buffers per connection
```

## Storage Optimization

### Table Storage Parameters

```sql
-- Optimize table storage for different workloads
ALTER TABLE large_fact_table SET (
    autovacuum_vacuum_scale_factor = 0.1,
    autovacuum_analyze_scale_factor = 0.05,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_threshold = 500
);

-- High-frequency insert table
ALTER TABLE event_log SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_analyze_scale_factor = 0.005,
    fillfactor = 80
);

-- Read-heavy table
ALTER TABLE lookup_table SET (
    autovacuum_vacuum_scale_factor = 0.4,
    autovacuum_analyze_scale_factor = 0.2,
    fillfactor = 100
);

-- Archive table
ALTER TABLE archive_data SET (
    autovacuum_enabled = false,
    fillfactor = 100
);
```

### Partitioning Strategy

```sql
-- Range partitioning for time-series data
CREATE TABLE sensor_readings (
    sensor_id INTEGER,
    reading_time TIMESTAMP WITH TIME ZONE,
    value DECIMAL(10,4),
    quality_score INTEGER
) PARTITION BY RANGE (reading_time);

-- Create partitions
CREATE TABLE sensor_readings_2024_01 PARTITION OF sensor_readings
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE sensor_readings_2024_02 PARTITION OF sensor_readings
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Hash partitioning for large tables
CREATE TABLE user_sessions (
    session_id UUID PRIMARY KEY,
    user_id INTEGER,
    start_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE,
    data JSONB
) PARTITION BY HASH (user_id);

-- Create hash partitions
CREATE TABLE user_sessions_0 PARTITION OF user_sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE user_sessions_1 PARTITION OF user_sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

-- List partitioning for categorical data
CREATE TABLE orders (
    order_id SERIAL,
    customer_id INTEGER,
    region VARCHAR(50),
    order_date DATE,
    total_amount DECIMAL(10,2)
) PARTITION BY LIST (region);

CREATE TABLE orders_north PARTITION OF orders
    FOR VALUES IN ('North', 'Northeast');

CREATE TABLE orders_south PARTITION OF orders
    FOR VALUES IN ('South', 'Southeast');
```

### Tablespace Optimization

```sql
-- Create tablespaces for different storage types
CREATE TABLESPACE fast_ssd LOCATION '/ssd/postgres';
CREATE TABLESPACE slow_hdd LOCATION '/hdd/postgres';

-- Assign tables to appropriate storage
ALTER TABLE hot_data SET TABLESPACE fast_ssd;
ALTER TABLE indexes SET TABLESPACE fast_ssd;
ALTER TABLE archive_data SET TABLESPACE slow_hdd;

-- Monitor tablespace usage
SELECT
    spcname AS tablespace,
    pg_size_pretty(pg_tablespace_size(oid)) AS size,
    pg_size_pretty(sum(pg_relation_size(inhoid))) AS used_by_tables
FROM pg_tablespace
LEFT JOIN pg_inherits ON inhrelid = 0
LEFT JOIN pg_class ON reltablespace = pg_tablespace.oid
WHERE relkind = 'r'
GROUP BY spcname, oid
ORDER BY pg_tablespace_size(oid) DESC;
```

## Query Optimization

### Query Analysis

```sql
-- Enable query analysis
CREATE EXTENSION pg_stat_statements;

-- Find slowest queries
SELECT
    query,
    calls,
    total_time,
    mean_time,
    rows,
    temp_blks_written,
    pg_size_pretty(temp_blks_written * 8192) AS temp_space_used
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Analyze specific query
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM large_table
WHERE date_column >= '2024-01-01'
  AND status = 'active'
ORDER BY date_column DESC
LIMIT 100;
```

### Query Rewriting

```sql
-- Use CTEs for complex queries
WITH ranked_orders AS (
    SELECT
        customer_id,
        order_id,
        total_amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
    FROM orders
    WHERE order_date >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT customer_id, order_id, total_amount
FROM ranked_orders
WHERE rn <= 3;

-- Optimize window functions
SELECT
    department,
    employee_id,
    salary,
    AVG(salary) OVER (PARTITION BY department) AS dept_avg,
    salary - AVG(salary) OVER (PARTITION BY department) AS diff_from_avg
FROM employees;

-- Use LATERAL for correlated subqueries
SELECT u.username, o.order_count, o.total_spent
FROM users u
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS order_count,
        SUM(total_amount) AS total_spent
    FROM orders
    WHERE customer_id = u.user_id
      AND order_date >= CURRENT_DATE - INTERVAL '1 year'
) o ON true;
```

### Parallel Query Optimization

```sql
-- Enable parallel queries for large tables
ALTER TABLE large_table SET (parallel_workers = 4);

-- Force parallel execution for testing
SET max_parallel_workers_per_gather = 4;
SET parallel_tuple_cost = 0.01;
SET parallel_setup_cost = 1000;

-- Monitor parallel query usage
SELECT
    pid,
    query,
    leader_pid,
    CASE WHEN leader_pid = pid THEN 'leader' ELSE 'worker' END AS role
FROM pg_stat_activity
WHERE query LIKE '%SELECT%'
  AND pid <> pg_backend_pid()
ORDER BY leader_pid, pid;
```

## Index Optimization

### Index Usage Analysis

```sql
-- Find unused indexes
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(indexrelid) DESC;

-- Index hit ratio
SELECT
    'index hit rate' AS metric,
    (sum(idx_blks_hit)) / nullif(sum(idx_blks_hit + idx_blks_read), 0) AS ratio
FROM pg_statio_user_indexes;

-- Redundant indexes
SELECT
    i1.schemaname,
    i1.tablename,
    i1.indexname AS index1,
    i2.indexname AS index2,
    pg_size_pretty(pg_relation_size(i1.indexrelid)) AS size1,
    pg_size_pretty(pg_relation_size(i2.indexrelid)) AS size2
FROM pg_stat_user_indexes i1
JOIN pg_stat_user_indexes i2 ON i1.tablename = i2.tablename
    AND i1.indexname < i2.indexname
WHERE i1.idx_scan = 0 OR i2.idx_scan = 0;
```

### Index Maintenance

```sql
-- Rebuild bloated indexes
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Concurrent index rebuild
CREATE INDEX CONCURRENTLY temp_idx_orders_customer_id
ON orders (customer_id);

DROP INDEX CONCURRENTLY idx_orders_customer_id;
ALTER INDEX temp_idx_orders_customer_id RENAME TO idx_orders_customer_id;

-- Index defragmentation
REINDEX INDEX idx_large_table_date;
REINDEX TABLE large_table;

-- Update index statistics
ANALYZE large_table;
```

## Connection Management

### Connection Pooling

```sql
-- pgBouncer configuration example
[databases]
mydb = host=localhost port=5432 dbname=mydb

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 10
max_db_connections = 100
max_user_connections = 50
```

### Connection Monitoring

```sql
-- Monitor connection states
SELECT
    state,
    count(*) AS count,
    round(count(*) * 100.0 / sum(count(*)) over (), 2) AS percentage
FROM pg_stat_activity
GROUP BY state
ORDER BY count(*) DESC;

-- Long-running connections
SELECT
    pid,
    usename,
    datname,
    client_addr,
    application_name,
    state,
    state_change,
    now() - state_change AS duration
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - state_change > interval '1 minute'
ORDER BY duration DESC;

-- Connection age analysis
SELECT
    CASE
        WHEN backend_start < now() - interval '1 hour' THEN 'old'
        WHEN backend_start < now() - interval '10 minutes' THEN 'medium'
        ELSE 'new'
    END AS age_category,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY age_category
ORDER BY age_category;
```

## Monitoring and Diagnostics

### Performance Metrics

```sql
-- System performance overview
SELECT
    now() AS timestamp,
    (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') AS active_connections,
    (SELECT sum(blks_hit) * 100.0 / (sum(blks_hit) + sum(blks_read)) FROM pg_stat_database) AS cache_hit_ratio,
    (SELECT sum(xact_commit) FROM pg_stat_database) AS total_commits,
    (SELECT sum(xact_rollback) FROM pg_stat_database) AS total_rollbacks,
    (SELECT sum(temp_bytes) FROM pg_stat_database) AS temp_file_usage,
    pg_size_pretty((SELECT sum(pg_database_size(datname)) FROM pg_database)) AS total_db_size;

-- Table-level performance
SELECT
    schemaname,
    tablename,
    seq_scan,
    idx_scan,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC
LIMIT 10;
```

### Automated Monitoring

```sql
-- Create monitoring function
CREATE OR REPLACE FUNCTION get_performance_metrics()
RETURNS TABLE (
    metric_name TEXT,
    metric_value TEXT,
    status TEXT
) AS $$
BEGIN
    -- Connection status
    RETURN QUERY
    SELECT 'active_connections'::TEXT,
           count(*)::TEXT,
           CASE WHEN count(*) > 80 THEN 'warning' ELSE 'ok' END
    FROM pg_stat_activity WHERE state = 'active';

    -- Cache hit ratio
    RETURN QUERY
    SELECT 'cache_hit_ratio'::TEXT,
           round((sum(blks_hit) * 100.0 / (sum(blks_hit) + sum(blks_read))), 2)::TEXT,
           CASE WHEN (sum(blks_hit) * 100.0 / (sum(blks_hit) + sum(blks_read))) < 95 THEN 'warning' ELSE 'ok' END
    FROM pg_stat_database;

    -- Database size
    RETURN QUERY
    SELECT 'database_size'::TEXT,
           pg_size_pretty(sum(pg_database_size(datname)))::TEXT,
           'info'::TEXT
    FROM pg_database;

    -- Long-running queries
    RETURN QUERY
    SELECT 'long_running_queries'::TEXT,
           count(*)::TEXT,
           CASE WHEN count(*) > 5 THEN 'warning' ELSE 'ok' END
    FROM pg_stat_activity
    WHERE state = 'active'
      AND now() - query_start > interval '5 minutes';
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT * FROM get_performance_metrics();
```

### Alert System

```sql
-- Create alerting function
CREATE OR REPLACE FUNCTION check_performance_alerts()
RETURNS TABLE (
    alert_level TEXT,
    alert_message TEXT,
    recommendation TEXT
) AS $$
DECLARE
    active_conn_count INTEGER;
    cache_hit_ratio DECIMAL;
    long_query_count INTEGER;
BEGIN
    -- Check active connections
    SELECT count(*) INTO active_conn_count
    FROM pg_stat_activity WHERE state = 'active';

    IF active_conn_count > 150 THEN
        RETURN QUERY SELECT 'CRITICAL'::TEXT,
                              format('High connection count: %s', active_conn_count),
                              'Consider increasing connection pool size or optimizing queries'::TEXT;
    ELSIF active_conn_count > 100 THEN
        RETURN QUERY SELECT 'WARNING'::TEXT,
                              format('Elevated connection count: %s', active_conn_count),
                              'Monitor connection usage patterns'::TEXT;
    END IF;

    -- Check cache hit ratio
    SELECT sum(blks_hit) * 100.0 / (sum(blks_hit) + sum(blks_read)) INTO cache_hit_ratio
    FROM pg_stat_database;

    IF cache_hit_ratio < 90 THEN
        RETURN QUERY SELECT 'WARNING'::TEXT,
                              format('Low cache hit ratio: %s%%', round(cache_hit_ratio, 2)),
                              'Consider increasing shared_buffers or effective_cache_size'::TEXT;
    END IF;

    -- Check for long-running queries
    SELECT count(*) INTO long_query_count
    FROM pg_stat_activity
    WHERE state = 'active'
      AND now() - query_start > interval '10 minutes';

    IF long_query_count > 0 THEN
        RETURN QUERY SELECT 'WARNING'::TEXT,
                              format('%s long-running queries detected', long_query_count),
                              'Check pg_stat_activity for details and optimize slow queries'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Schedule regular checks
-- Using pg_cron extension
SELECT cron.schedule('performance-check', '*/5 * * * *', 'SELECT * FROM check_performance_alerts();');
```

## Enterprise Patterns

### High Availability Performance Tuning

```sql
-- Streaming replication tuning
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET wal_keep_segments = 64;
ALTER SYSTEM SET synchronous_commit = 'off';  -- For async replication
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (standby1)';

-- Replication slot monitoring
SELECT
    slot_name,
    slot_type,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
FROM pg_replication_slots;

-- Connection pooling for HA
-- Configure multiple pgBouncer instances
-- Load balancer configuration for read/write splitting
```

### Data Warehousing Optimization

```sql
-- Column-oriented storage with cstore extension
CREATE EXTENSION cstore_fdw;

CREATE FOREIGN TABLE fact_sales_cstore (
    sale_id INTEGER,
    product_id INTEGER,
    customer_id INTEGER,
    sale_date DATE,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2)
) SERVER cstore_server
OPTIONS (filename '/data/cstore/fact_sales.cstore');

-- Partitioning for large fact tables
CREATE TABLE fact_sales (
    sale_id SERIAL,
    product_id INTEGER,
    customer_id INTEGER,
    sale_date DATE,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2)
) PARTITION BY RANGE (sale_date);

-- Create monthly partitions
DO $$
DECLARE
    start_date DATE := '2020-01-01';
    end_date DATE;
    partition_name TEXT;
BEGIN
    WHILE start_date < '2025-01-01' LOOP
        end_date := start_date + INTERVAL '1 month';
        partition_name := 'fact_sales_' || to_char(start_date, 'YYYY_MM');

        EXECUTE format('
            CREATE TABLE %I PARTITION OF fact_sales
            FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );

        start_date := end_date;
    END LOOP;
END $$;
```

### Real-Time Analytics Optimization

```sql
-- TimescaleDB for time-series optimization
CREATE EXTENSION timescaledb;

-- Convert table to hypertable
SELECT create_hypertable('sensor_readings', 'timestamp', chunk_time_interval => INTERVAL '1 day');

-- Continuous aggregates for real-time analytics
CREATE MATERIALIZED VIEW hourly_sensor_summary
WITH (timescaledb.continuous) AS
SELECT
    sensor_id,
    time_bucket('1 hour', timestamp) AS hour,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    COUNT(*) AS reading_count
FROM sensor_readings
GROUP BY sensor_id, hour
WITH NO DATA;

-- Real-time aggregation policy
SELECT add_continuous_aggregate_policy('hourly_sensor_summary',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- Optimize for real-time queries
ALTER TABLE sensor_readings SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',
    timescaledb.compress_orderby = 'timestamp DESC'
);
```

### Microservices Database Optimization

```sql
-- Database-per-service architecture
-- Each service has its own database optimized for its workload

-- User service database - Read-heavy
ALTER DATABASE user_service_db SET
    effective_cache_size = '8GB';
ALTER DATABASE user_service_db SET
    shared_buffers = '2GB';

-- Order service database - Write-heavy
ALTER DATABASE order_service_db SET
    wal_buffers = '32MB';
ALTER DATABASE order_service_db SET
    checkpoint_timeout = '15min';
ALTER DATABASE order_service_db SET
    synchronous_commit = 'off';

-- Analytics service database - Complex queries
ALTER DATABASE analytics_db SET
    work_mem = '128MB';
ALTER DATABASE analytics_db SET
    max_parallel_workers_per_gather = 8;
ALTER DATABASE analytics_db SET
    jit = on;
```

### Automated Performance Management

```sql
-- Automated index creation for slow queries
CREATE OR REPLACE FUNCTION auto_create_indexes()
RETURNS VOID AS $$
DECLARE
    query_record RECORD;
    index_name TEXT;
    index_sql TEXT;
BEGIN
    FOR query_record IN
        SELECT
            query,
            total_time / calls AS avg_time,
            substring(query from 'FROM\s+(\w+)') AS table_name,
            substring(query from 'WHERE\s+([^ORDER|GROUP|LIMIT]+)') AS where_clause
        FROM pg_stat_statements
        WHERE calls > 100
          AND total_time / calls > 1000  -- > 1 second average
          AND query LIKE 'SELECT%'
          AND query NOT LIKE '%pg_stat%'
        LIMIT 5
    LOOP
        -- Generate potential index (simplified)
        index_name := 'auto_idx_' || md5(query_record.query);

        -- Check if index might help
        IF query_record.where_clause IS NOT NULL THEN
            index_sql := format('CREATE INDEX CONCURRENTLY %I ON %I (%s)',
                               index_name,
                               query_record.table_name,
                               regexp_replace(query_record.where_clause, '\s*=\s*[^,\s]+', '', 'g'));

            -- Log the suggestion (don't auto-create in production)
            RAISE NOTICE 'Suggested index: %', index_sql;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Automated table optimization
CREATE OR REPLACE FUNCTION auto_optimize_tables()
RETURNS VOID AS $$
DECLARE
    table_record RECORD;
BEGIN
    FOR table_record IN
        SELECT
            schemaname,
            tablename,
            n_dead_tup,
            n_live_tup,
            last_vacuum,
            last_autovacuum
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND n_dead_tup > n_live_tup * 0.2  -- > 20% dead tuples
          AND (last_vacuum IS NULL OR last_vacuum < now() - interval '1 day')
    LOOP
        -- Force vacuum on bloated tables
        EXECUTE format('VACUUM ANALYZE %I.%I', table_record.schemaname, table_record.tablename);
        RAISE NOTICE 'Optimized table: %', table_record.tablename;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Schedule automated maintenance
-- SELECT cron.schedule('auto-optimize', '0 2 * * *', 'SELECT auto_optimize_tables();');
```

This comprehensive performance tuning guide covers system configuration, memory management, storage optimization, query tuning, and enterprise-level monitoring and automation strategies for PostgreSQL databases.
