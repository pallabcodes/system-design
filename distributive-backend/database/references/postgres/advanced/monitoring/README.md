# PostgreSQL Monitoring and Alerting

## Overview

Comprehensive monitoring is essential for maintaining PostgreSQL database performance, availability, and reliability. This guide covers monitoring strategies, tools, key metrics, alerting systems, and proactive maintenance for enterprise PostgreSQL deployments.

## Table of Contents

1. [Monitoring Architecture](#monitoring-architecture)
2. [Key Metrics and KPIs](#key-metrics-and-kpis)
3. [PostgreSQL Built-in Monitoring](#postgresql-built-in-monitoring)
4. [External Monitoring Tools](#external-monitoring-tools)
5. [Alerting Systems](#alerting-systems)
6. [Performance Baselines](#performance-baselines)
7. [Capacity Planning](#capacity-planning)
8. [Enterprise Monitoring Patterns](#enterprise-monitoring-patterns)

## Monitoring Architecture

### Monitoring Stack Components

```
┌─────────────────────────────────────────────────┐
│               APPLICATION LAYER                 │
│  • Query Performance Monitoring                 │
│  • Business Metrics                            │
│  • User Experience Monitoring                   │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│            DATABASE LAYER                       │
│  • PostgreSQL Statistics                        │
│  • System Resource Monitoring                   │
│  • Query Analysis                               │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│           INFRASTRUCTURE LAYER                  │
│  • Server Metrics (CPU, Memory, I/O)           │
│  • Network Monitoring                           │
│  • Storage Performance                          │
└─────────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────────┐
│           MONITORING PLATFORM                   │
│  • Data Collection (Telegraf, Prometheus)       │
│  • Time-Series Database (InfluxDB, VictoriaMetrics)
│  • Visualization (Grafana)                      │
│  • Alerting (Alertmanager)                      │
└─────────────────────────────────────────────────┘
```

### Monitoring Data Flow

1. **Data Collection**: Agents and exporters gather metrics
2. **Data Processing**: Metrics are processed and enriched
3. **Data Storage**: Time-series data is stored efficiently
4. **Visualization**: Dashboards provide insights
5. **Alerting**: Automated notifications for issues
6. **Automation**: Self-healing and scaling actions

## Key Metrics and KPIs

### Database Health Metrics

#### Connection Metrics

```sql
-- Active connections monitoring
SELECT
    count(*) as total_connections,
    count(*) filter (where state = 'active') as active_connections,
    count(*) filter (where state = 'idle') as idle_connections,
    count(*) filter (where state = 'idle in transaction') as idle_in_transaction
FROM pg_stat_activity
WHERE datname = current_database();
```

#### Performance Metrics

```sql
-- Query performance indicators
SELECT
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
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

#### Cache Efficiency

```sql
-- Buffer cache hit ratio
SELECT
    'buffer_cache_hit_ratio' as metric,
    round(
        (sum(blks_hit) * 100.0) / nullif(sum(blks_hit + blks_read), 0),
        2
    ) as value
FROM pg_stat_database;

-- Index hit ratio
SELECT
    'index_hit_ratio' as metric,
    round(
        sum(idx_blks_hit) * 100.0 / nullif(sum(idx_blks_hit + idx_blks_read), 0),
        2
    ) as value
FROM pg_statio_user_indexes;
```

#### Transaction Metrics

```sql
-- Transaction rate and conflict monitoring
SELECT
    datname,
    xact_commit,
    xact_rollback,
    conflicts,
    temp_files,
    temp_bytes,
    deadlocks
FROM pg_stat_database
WHERE datname = current_database();
```

### System Resource Metrics

#### CPU and Memory Usage

```bash
# System resource monitoring
# CPU usage per process
ps aux --sort=-%cpu | head -10

# Memory usage
free -h

# PostgreSQL memory usage
ps -o pid,ppid,cmd,%mem,%cpu --sort=-%mem | grep postgres
```

#### Disk I/O Performance

```bash
# Disk I/O statistics
iostat -x 1 5

# PostgreSQL data directory I/O
iotop -o -b -n 5 | grep postgres

# Disk space monitoring
df -h /var/lib/postgresql/data
du -sh /var/lib/postgresql/data/*
```

#### Network Performance

```bash
# Network interface statistics
ip -s link

# PostgreSQL network connections
netstat -antp | grep postgres | wc -l

# Connection states
ss -ant | grep :5432 | awk '{print $1}' | sort | uniq -c
```

## PostgreSQL Built-in Monitoring

### Statistics Collector

#### Enabling Statistics Collection

```sql
-- Check if statistics collection is enabled
SHOW track_activities;
SHOW track_counts;
SHOW track_functions;
SHOW track_io_timing;

-- Enable comprehensive statistics collection
ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET track_functions = 'all';
ALTER SYSTEM SET track_io_timing = on;
ALTER SYSTEM SET track_wal_io_timing = on;

-- Restart PostgreSQL for changes to take effect
SELECT pg_reload_conf();
```

#### Statistics Views

```sql
-- Database-level statistics
SELECT * FROM pg_stat_database;

-- Table-level statistics
SELECT * FROM pg_stat_user_tables;

-- Index usage statistics
SELECT * FROM pg_stat_user_indexes;

-- Function call statistics
SELECT * FROM pg_stat_user_functions;

-- WAL statistics
SELECT * FROM pg_stat_wal;

-- Replication statistics
SELECT * FROM pg_stat_replication;
```

### pg_stat_statements Extension

#### Installation and Configuration

```sql
-- Install pg_stat_statements
CREATE EXTENSION pg_stat_statements;

-- Configure pg_stat_statements
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET pg_stat_statements.max = 10000;
ALTER SYSTEM SET pg_stat_statements.track = 'all';
ALTER SYSTEM SET pg_stat_statements.track_utility = on;
ALTER SYSTEM SET pg_stat_statements.save = on;

-- Restart required for shared_preload_libraries changes
```

#### Query Performance Analysis

```sql
-- Top queries by execution time
SELECT
    query,
    calls,
    total_time,
    mean_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    temp_blks_written
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Queries with high I/O
SELECT
    query,
    calls,
    total_time,
    shared_blks_hit + shared_blks_read as total_blocks,
    temp_blks_written,
    (shared_blks_hit::float / nullif(shared_blks_hit + shared_blks_read, 0)) * 100 as cache_hit_ratio
FROM pg_stat_statements
WHERE shared_blks_hit + shared_blks_read > 0
ORDER BY shared_blks_hit + shared_blks_read DESC
LIMIT 10;
```

### Auto-Explain Extension

#### Setup for Query Plan Logging

```sql
-- Install auto_explain
CREATE EXTENSION auto_explain;

-- Configure auto_explain
ALTER SYSTEM SET shared_preload_libraries = 'auto_explain';
ALTER SYSTEM SET auto_explain.log_min_duration = '1000ms';  -- Log queries > 1 second
ALTER SYSTEM SET auto_explain.log_analyze = on;
ALTER SYSTEM SET auto_explain.log_verbose = on;
ALTER SYSTEM SET auto_explain.log_buffers = on;
ALTER SYSTEM SET auto_explain.log_timing = on;
ALTER SYSTEM SET auto_explain.log_triggers = on;

-- Log specific query plans to file
ALTER SYSTEM SET auto_explain.log_nested_statements = on;
```

## External Monitoring Tools

### Prometheus + Grafana Stack

#### PostgreSQL Exporter Setup

```bash
# Install postgres_exporter
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.11.1/postgres_exporter-0.11.1.linux-amd64.tar.gz
tar -xzf postgres_exporter-*.tar.gz
cd postgres_exporter-*

# Create database user for monitoring
psql -c "CREATE USER postgres_exporter PASSWORD 'secure_password';"
psql -c "GRANT pg_monitor TO postgres_exporter;"

# Run exporter
./postgres_exporter --extend.query-path=queries.yaml \
  --web.listen-address=:9187 \
  --web.telemetry-path=/metrics
```

#### Prometheus Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']
    scrape_interval: 15s

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
```

#### Grafana Dashboard

```sql
-- Example Grafana queries for PostgreSQL dashboard

-- Active Connections
SELECT
  $__timeGroup(created_at, '5m'),
  count(*) as active_connections
FROM pg_stat_activity
WHERE state = 'active'
GROUP BY time
ORDER BY time

-- Cache Hit Ratio
SELECT
  $__timeGroup(now(), '5m'),
  (sum(blks_hit) / (sum(blks_hit) + sum(blks_read))) * 100 as cache_hit_ratio
FROM pg_stat_database
GROUP BY time

-- Top Queries by Time
SELECT
  left(query, 50) as query_preview,
  total_time / calls as avg_time,
  calls
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10
```

### pgMonitor Setup

```bash
# Install pgMonitor
git clone https://github.com/pgmonitor/pgmonitor.git
cd pgmonitor

# Deploy monitoring schema
psql -d postgres -f pgmonitor.sql

# Configure metric collection
psql -d postgres -f metric_store.sql

# Set up retention policies
psql -d postgres -c "SELECT metric_store.create_retention_policy('1 year');"
```

### pgBadger for Log Analysis

```bash
# Install pgBadger
wget https://github.com/darold/pgbadger/archive/v11.8.tar.gz
tar -xzf pgbadger-*.tar.gz
cd pgbadger-*

# Generate HTML report from PostgreSQL logs
./pgbadger /var/log/postgresql/postgresql.log \
  --outfile /var/www/html/pgbadger_report.html \
  --top 20 \
  --title "PostgreSQL Performance Report"

# Incremental reports
./pgbadger --outdir /var/www/html/reports/ \
  --incremental \
  /var/log/postgresql/postgresql.log
```

## Alerting Systems

### Alertmanager Configuration

```yaml
# alertmanager.yml
global:
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'password'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'database-team'
  routes:
  - match:
      severity: critical
    receiver: 'database-oncall'

receivers:
- name: 'database-team'
  email_configs:
  - to: 'db-team@example.com'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/...'

- name: 'database-oncall'
  pagerduty_configs:
  - service_key: 'pagerduty_integration_key'
```

### Critical Alert Definitions

#### Database Availability Alerts

```yaml
# PostgreSQL Down Alert
groups:
- name: postgresql
  rules:
  - alert: PostgreSQLDown
    expr: up{job="postgres"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "PostgreSQL is down"
      description: "PostgreSQL has been down for more than 1 minute."

  - alert: PostgreSQLConnectionsHigh
    expr: pg_stat_activity_count{state="active"} > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High active connections"
      description: "Active connections are above 80% of max_connections."

  - alert: PostgreSQLCacheHitRatioLow
    expr: pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read) < 0.95
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Low cache hit ratio"
      description: "Buffer cache hit ratio is below 95%."
```

#### Performance Alert Rules

```yaml
  - alert: PostgreSQLSlowQueries
    expr: increase(pg_stat_statements_total_time[5m]) / increase(pg_stat_statements_calls[5m]) > 1000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Slow query performance"
      description: "Average query time exceeds 1 second."

  - alert: PostgreSQLDeadlocks
    expr: increase(pg_stat_database_deadlocks[5m]) > 0
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "Database deadlocks detected"
      description: "Deadlocks have occurred in the last 5 minutes."

  - alert: PostgreSQLReplicationLag
    expr: pg_replication_lag > 300
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High replication lag"
      description: "Replication lag exceeds 5 minutes."
```

### Automated Alert Response

#### Alert Response Scripts

```bash
#!/bin/bash
# Automated alert response script

ALERT_NAME=$1
INSTANCE=$2

case $ALERT_NAME in
    "PostgreSQLConnectionsHigh")
        # Scale up connection pool
        echo "Scaling up connection pool for $INSTANCE"
        # Implement connection pool scaling logic
        ;;

    "PostgreSQLCacheHitRatioLow")
        # Increase shared_buffers
        echo "Increasing shared_buffers for $INSTANCE"
        # Implement memory scaling logic
        ;;

    "PostgreSQLSlowQueries")
        # Enable auto_explain for query analysis
        echo "Enabling query plan logging for $INSTANCE"
        psql -h $INSTANCE -c "ALTER SYSTEM SET auto_explain.log_min_duration = '500ms';"
        psql -h $INSTANCE -c "SELECT pg_reload_conf();"
        ;;
esac
```

## Performance Baselines

### Establishing Baselines

#### Baseline Collection Script

```sql
-- Create baseline metrics table
CREATE TABLE performance_baselines (
    baseline_id SERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(15,4),
    collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    environment VARCHAR(50) DEFAULT 'production',
    load_level VARCHAR(20) DEFAULT 'normal'  -- 'low', 'normal', 'high', 'peak'
);

-- Collect comprehensive baseline
CREATE OR REPLACE FUNCTION collect_performance_baseline(load_level TEXT DEFAULT 'normal')
RETURNS VOID AS $$
DECLARE
    metric_record RECORD;
BEGIN
    -- Connection metrics
    INSERT INTO performance_baselines (metric_name, metric_value, load_level)
    SELECT 'active_connections', count(*), load_level
    FROM pg_stat_activity WHERE state = 'active';

    -- Cache metrics
    INSERT INTO performance_baselines (metric_name, metric_value, load_level)
    SELECT 'cache_hit_ratio',
           (sum(blks_hit) * 100.0) / nullif(sum(blks_hit + blks_read), 0),
           load_level
    FROM pg_stat_database;

    -- Query performance
    INSERT INTO performance_baselines (metric_name, metric_value, load_level)
    SELECT 'avg_query_time',
           avg(total_time / calls),
           load_level
    FROM pg_stat_statements
    WHERE calls > 10;

    -- System metrics (would be collected from external monitoring)
    -- CPU, Memory, I/O metrics would be added here

END;
$$ LANGUAGE plpgsql;

-- Schedule baseline collection
SELECT cron.schedule('baseline-collection', '0 */4 * * *', 'SELECT collect_performance_baseline(''normal'');');
```

#### Baseline Analysis

```sql
-- Compare current performance to baseline
CREATE OR REPLACE FUNCTION analyze_performance_vs_baseline(
    metric_name TEXT,
    current_value DECIMAL,
    load_level TEXT DEFAULT 'normal'
)
RETURNS TABLE (
    deviation_percent DECIMAL,
    status TEXT,
    recommendation TEXT
) AS $$
DECLARE
    baseline_avg DECIMAL;
    baseline_stddev DECIMAL;
    z_score DECIMAL;
BEGIN
    -- Calculate baseline statistics
    SELECT
        avg(metric_value),
        stddev(metric_value)
    INTO baseline_avg, baseline_stddev
    FROM performance_baselines
    WHERE metric_name = analyze_performance_vs_baseline.metric_name
      AND load_level = analyze_performance_vs_baseline.load_level
      AND collected_at >= CURRENT_TIMESTAMP - INTERVAL '30 days';

    -- Calculate deviation
    z_score := (current_value - baseline_avg) / nullif(baseline_stddev, 0);
    deviation_percent := ((current_value - baseline_avg) / nullif(baseline_avg, 0)) * 100;

    -- Determine status and recommendation
    CASE
        WHEN abs(z_score) > 3 THEN
            RETURN QUERY SELECT
                deviation_percent,
                'CRITICAL'::TEXT,
                'Immediate investigation required - performance significantly deviated from baseline'::TEXT;
        WHEN abs(z_score) > 2 THEN
            RETURN QUERY SELECT
                deviation_percent,
                'WARNING'::TEXT,
                'Performance deviation detected - monitor closely'::TEXT;
        WHEN abs(z_score) > 1 THEN
            RETURN QUERY SELECT
                deviation_percent,
                'INFO'::TEXT,
                'Minor performance change observed'::TEXT;
        ELSE
            RETURN QUERY SELECT
                deviation_percent,
                'NORMAL'::TEXT,
                'Performance within normal baseline range'::TEXT;
    END CASE;

END;
$$ LANGUAGE plpgsql;
```

## Capacity Planning

### Resource Usage Forecasting

#### Trend Analysis

```sql
-- Analyze resource usage trends
CREATE OR REPLACE FUNCTION analyze_resource_trends(days_back INTEGER DEFAULT 30)
RETURNS TABLE (
    metric_name TEXT,
    current_value DECIMAL,
    trend_direction TEXT,
    growth_rate DECIMAL,
    projected_30day DECIMAL,
    recommendation TEXT
) AS $$
DECLARE
    metric_record RECORD;
    slope DECIMAL;
    intercept DECIMAL;
    correlation DECIMAL;
BEGIN
    FOR metric_record IN
        SELECT DISTINCT metric_name FROM performance_baselines
        WHERE collected_at >= CURRENT_TIMESTAMP - (days_back || ' days')::INTERVAL
    LOOP
        -- Calculate linear regression for trend analysis
        SELECT
            regr_slope(metric_value, extract(epoch from collected_at)) as slope,
            regr_intercept(metric_value, extract(epoch from collected_at)) as intercept,
            corr(metric_value, extract(epoch from collected_at)) as correlation
        INTO slope, intercept, correlation
        FROM performance_baselines
        WHERE metric_name = metric_record.metric_name
          AND collected_at >= CURRENT_TIMESTAMP - (days_back || ' days')::INTERVAL;

        -- Current value
        SELECT metric_value INTO current_value
        FROM performance_baselines
        WHERE metric_name = metric_record.metric_name
        ORDER BY collected_at DESC
        LIMIT 1;

        -- Determine trend direction
        trend_direction := CASE
            WHEN correlation > 0.7 AND slope > 0 THEN 'INCREASING'
            WHEN correlation > 0.7 AND slope < 0 THEN 'DECREASING'
            WHEN correlation > 0.5 THEN 'SLIGHTLY_INCREASING'
            ELSE 'STABLE'
        END;

        -- Growth rate (daily)
        growth_rate := slope * 86400;  -- Convert to daily rate

        -- 30-day projection
        projected_30day := current_value + (growth_rate * 30);

        -- Generate recommendations
        recommendation := CASE
            WHEN metric_record.metric_name = 'active_connections' AND projected_30day > 80 THEN
                'Consider increasing max_connections or implementing connection pooling'
            WHEN metric_record.metric_name = 'cache_hit_ratio' AND current_value < 95 THEN
                'Consider increasing shared_buffers or optimizing queries'
            WHEN metric_record.metric_name = 'avg_query_time' AND growth_rate > 0 THEN
                'Monitor query performance - consider query optimization'
            ELSE 'Monitor trend - no immediate action required'
        END;

        RETURN QUERY SELECT
            metric_record.metric_name,
            current_value,
            trend_direction,
            growth_rate,
            projected_30day,
            recommendation;
    END LOOP;

END;
$$ LANGUAGE plpgsql;
```

#### Capacity Planning Dashboard

```sql
-- Capacity planning view
CREATE VIEW capacity_planning_dashboard AS
SELECT
    'CPU_Usage' as resource_type,
    avg(cpu_usage_percent) as current_usage,
    max(cpu_usage_percent) as peak_usage,
    stddev(cpu_usage_percent) as usage_variance
FROM system_metrics
WHERE collected_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'

UNION ALL

SELECT
    'Memory_Usage' as resource_type,
    avg(memory_usage_percent) as current_usage,
    max(memory_usage_percent) as peak_usage,
    stddev(memory_usage_percent) as usage_variance
FROM system_metrics
WHERE collected_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'

UNION ALL

SELECT
    'Disk_IOPS' as resource_type,
    avg(disk_iops) as current_usage,
    max(disk_iops) as peak_usage,
    stddev(disk_iops) as usage_variance
FROM system_metrics
WHERE collected_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'

UNION ALL

SELECT
    'Network_Throughput' as resource_type,
    avg(network_mbps) as current_usage,
    max(network_mbps) as peak_usage,
    stddev(network_mbps) as usage_variance
FROM system_metrics
WHERE collected_at >= CURRENT_TIMESTAMP - INTERVAL '30 days';
```

## Enterprise Monitoring Patterns

### Multi-Database Monitoring

#### Centralized Monitoring Architecture

```sql
-- Centralized monitoring database schema
CREATE TABLE monitored_databases (
    database_id SERIAL PRIMARY KEY,
    connection_string TEXT NOT NULL,
    database_name VARCHAR(255),
    environment VARCHAR(50),  -- 'production', 'staging', 'development'
    business_unit VARCHAR(100),
    monitoring_enabled BOOLEAN DEFAULT TRUE,
    last_checked TIMESTAMP,
    status VARCHAR(20) DEFAULT 'unknown'
);

-- Collect metrics from multiple databases
CREATE OR REPLACE FUNCTION collect_multi_database_metrics()
RETURNS VOID AS $$
DECLARE
    db_record RECORD;
    conn_string TEXT;
    metric_value DECIMAL;
BEGIN
    FOR db_record IN SELECT * FROM monitored_databases WHERE monitoring_enabled = TRUE
    LOOP
        conn_string := db_record.connection_string;

        -- Collect active connections
        SELECT count(*) INTO metric_value
        FROM dblink(conn_string, 'SELECT count(*) FROM pg_stat_activity WHERE state = ''active''') AS t(count BIGINT);

        INSERT INTO database_metrics (database_id, metric_name, metric_value, collected_at)
        VALUES (db_record.database_id, 'active_connections', metric_value, CURRENT_TIMESTAMP);

        -- Update last checked
        UPDATE monitored_databases SET last_checked = CURRENT_TIMESTAMP WHERE database_id = db_record.database_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### Predictive Monitoring

#### Anomaly Detection

```sql
-- Simple anomaly detection using statistical methods
CREATE OR REPLACE FUNCTION detect_metric_anomalies(
    metric_name TEXT,
    current_value DECIMAL,
    lookback_days INTEGER DEFAULT 7
)
RETURNS TABLE (
    is_anomaly BOOLEAN,
    deviation_zscore DECIMAL,
    expected_range TEXT,
    confidence DECIMAL
) AS $$
DECLARE
    mean_val DECIMAL;
    stddev_val DECIMAL;
    zscore DECIMAL;
    lower_bound DECIMAL;
    upper_bound DECIMAL;
BEGIN
    -- Calculate baseline statistics
    SELECT
        avg(metric_value),
        stddev(metric_value)
    INTO mean_val, stddev_val
    FROM database_metrics
    WHERE metric_name = detect_metric_anomalies.metric_name
      AND collected_at >= CURRENT_TIMESTAMP - (lookback_days || ' days')::INTERVAL;

    -- Calculate z-score
    zscore := (current_value - mean_val) / nullif(stddev_val, 0);

    -- Define normal range (3-sigma rule)
    lower_bound := mean_val - (3 * stddev_val);
    upper_bound := mean_val + (3 * stddev_val);

    -- Determine if anomaly
    is_anomaly := current_value < lower_bound OR current_value > upper_bound;

    -- Confidence based on z-score
    confidence := CASE
        WHEN abs(zscore) > 3 THEN 0.997
        WHEN abs(zscore) > 2 THEN 0.95
        WHEN abs(zscore) > 1 THEN 0.68
        ELSE 0.5
    END;

    RETURN QUERY SELECT
        is_anomaly,
        zscore,
        format('[%s, %s]', round(lower_bound, 2), round(upper_bound, 2)),
        confidence;
END;
$$ LANGUAGE plpgsql;
```

### Automated Remediation

#### Self-Healing Actions

```sql
-- Automated remediation system
CREATE TABLE remediation_actions (
    action_id SERIAL PRIMARY KEY,
    alert_name VARCHAR(255) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    action_type VARCHAR(50) NOT NULL,  -- 'query_kill', 'connection_limit', 'cache_clear', 'restart_service'
    action_command TEXT NOT NULL,
    max_frequency_minutes INTEGER DEFAULT 60,
    last_executed TIMESTAMP,
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    enabled BOOLEAN DEFAULT TRUE
);

-- Execute remediation action
CREATE OR REPLACE FUNCTION execute_remediation_action(alert_name TEXT, severity TEXT)
RETURNS TABLE (
    action_taken BOOLEAN,
    action_result TEXT,
    execution_time INTERVAL
) AS $$
DECLARE
    action_record remediation_actions%ROWTYPE;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result_text TEXT;
BEGIN
    start_time := clock_timestamp();

    -- Find appropriate action
    SELECT * INTO action_record
    FROM remediation_actions
    WHERE alert_name = execute_remediation_action.alert_name
      AND severity = execute_remediation_action.severity
      AND enabled = TRUE
      AND (last_executed IS NULL OR last_executed < CURRENT_TIMESTAMP - (max_frequency_minutes || ' minutes')::INTERVAL)
    ORDER BY severity DESC, success_count DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'No suitable remediation action found', NULL::INTERVAL;
        RETURN;
    END IF;

    -- Execute action
    BEGIN
        EXECUTE action_record.action_command;
        result_text := 'Action executed successfully';
        UPDATE remediation_actions SET
            success_count = success_count + 1,
            last_executed = CURRENT_TIMESTAMP
        WHERE action_id = action_record.action_id;

    EXCEPTION WHEN OTHERS THEN
        result_text := 'Action failed: ' || SQLERRM;
        UPDATE remediation_actions SET
            failure_count = failure_count + 1,
            last_executed = CURRENT_TIMESTAMP
        WHERE action_id = action_record.action_id;
    END;

    end_time := clock_timestamp();

    RETURN QUERY SELECT TRUE, result_text, end_time - start_time;
END;
$$ LANGUAGE plpgsql;

-- Sample remediation actions
INSERT INTO remediation_actions (alert_name, severity, action_type, action_command) VALUES
('PostgreSQLConnectionsHigh', 'warning', 'connection_limit',
 'ALTER SYSTEM SET max_connections = current_setting(''max_connections'')::int * 0.9; SELECT pg_reload_conf();'),
('PostgreSQLSlowQueries', 'warning', 'query_kill',
 'SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE state = ''active'' AND now() - query_start > interval ''5 minutes'';'),
('PostgreSQLCacheHitRatioLow', 'warning', 'cache_adjust',
 'ALTER SYSTEM SET shared_buffers = pg_size_pretty(current_setting(''shared_buffers'')::bigint * 1.2); SELECT pg_reload_conf();');
```

### Compliance Monitoring

#### Audit Trail Monitoring

```sql
-- Monitor audit compliance
CREATE OR REPLACE FUNCTION check_audit_compliance(hours_back INTEGER DEFAULT 24)
RETURNS TABLE (
    compliance_status TEXT,
    audit_records_count BIGINT,
    expected_records BIGINT,
    compliance_percentage DECIMAL,
    issues TEXT[]
) AS $$
DECLARE
    actual_count BIGINT;
    expected_count BIGINT;
    compliance_pct DECIMAL;
    issues_list TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Count actual audit records
    SELECT count(*) INTO actual_count
    FROM audit_log
    WHERE changed_at >= CURRENT_TIMESTAMP - (hours_back || ' hours')::INTERVAL;

    -- Calculate expected records (estimate based on activity)
    SELECT
        (sum(n_tup_ins + n_tup_upd + n_tup_del) * 0.1)::BIGINT  -- Assume 10% of changes are audited
    INTO expected_count
    FROM pg_stat_user_tables;

    -- Calculate compliance
    compliance_pct := CASE
        WHEN expected_count = 0 THEN 100
        ELSE (actual_count::DECIMAL / expected_count) * 100
    END;

    -- Check for issues
    IF compliance_pct < 80 THEN
        issues_list := issues_list || 'Low audit record count';
    END IF;

    IF actual_count = 0 THEN
        issues_list := issues_list || 'No audit records found';
    END IF;

    -- Check for gaps in audit trail
    IF EXISTS (
        SELECT 1 FROM generate_series(
            CURRENT_TIMESTAMP - (hours_back || ' hours')::INTERVAL,
            CURRENT_TIMESTAMP,
            '1 hour'::INTERVAL
        ) AS hour_series
        LEFT JOIN audit_log ON date_trunc('hour', changed_at) = hour_series
        GROUP BY hour_series
        HAVING count(*) = 0
    ) THEN
        issues_list := issues_list || 'Gaps detected in audit trail';
    END IF;

    -- Determine status
    compliance_status := CASE
        WHEN compliance_pct >= 95 THEN 'COMPLIANT'
        WHEN compliance_pct >= 80 THEN 'WARNING'
        ELSE 'NON_COMPLIANT'
    END;

    RETURN QUERY SELECT
        compliance_status,
        actual_count,
        expected_count,
        round(compliance_pct, 2),
        issues_list;
END;
$$ LANGUAGE plpgsql;
```

This comprehensive monitoring and alerting guide provides enterprise-level strategies for PostgreSQL database monitoring, covering everything from basic metric collection to advanced predictive analytics and automated remediation systems.
