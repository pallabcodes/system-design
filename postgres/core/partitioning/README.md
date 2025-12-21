# PostgreSQL Table Partitioning

## Overview

Table partitioning is a PostgreSQL feature that allows you to divide large tables into smaller, more manageable pieces called partitions. Each partition is a separate table that can be stored, indexed, and queried independently, while appearing as a single logical table to applications.

## Table of Contents

1. [Partitioning Fundamentals](#partitioning-fundamentals)
2. [Range Partitioning](#range-partitioning)
3. [Hash Partitioning](#hash-partitioning)
4. [List Partitioning](#list-partitioning)
5. [Advanced Partitioning Techniques](#advanced-partitioning-techniques)
6. [Partition Management](#partition-management)
7. [Performance Considerations](#performance-considerations)
8. [Enterprise Patterns](#enterprise-patterns)

## Partitioning Fundamentals

### Why Partition?

- **Performance**: Queries can scan only relevant partitions
- **Maintenance**: Easier to manage smaller tables
- **Archival**: Old data can be archived separately
- **Storage**: Different partitions can use different storage
- **Parallel Processing**: Partitions can be processed in parallel

### Partitioning Types

1. **Range Partitioning**: Based on a range of values (dates, numbers)
2. **Hash Partitioning**: Based on hash of partition key
3. **List Partitioning**: Based on discrete values in a list

### Partition Key Selection

Choose partition keys that:
- Are frequently used in WHERE clauses
- Have high cardinality
- Are immutable or rarely change
- Align with data access patterns

## Range Partitioning

### Basic Range Partitioning

```sql
-- Create a partitioned table for sales data
CREATE TABLE sales (
    sale_id SERIAL,
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    sale_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    region VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (sale_date);

-- Create partitions for each quarter
CREATE TABLE sales_2024_q1 PARTITION OF sales
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE sales_2024_q2 PARTITION OF sales
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE sales_2024_q3 PARTITION OF sales
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE sales_2024_q4 PARTITION OF sales
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

-- Default partition for any data outside defined ranges
CREATE TABLE sales_default PARTITION OF sales DEFAULT;

-- Insert sample data
INSERT INTO sales (customer_id, product_id, sale_date, amount, quantity, region) VALUES
(1, 101, '2024-01-15', 299.99, 1, 'North'),
(2, 102, '2024-02-20', 149.50, 2, 'South'),
(3, 103, '2024-06-10', 79.99, 1, 'East'),
(4, 104, '2024-11-05', 399.99, 1, 'West');
```

### Multi-Level Range Partitioning

```sql
-- Two-level partitioning: first by year, then by quarter
CREATE TABLE sales_yearly (
    sale_id SERIAL,
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    sale_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    region VARCHAR(50)
) PARTITION BY RANGE (EXTRACT(YEAR FROM sale_date));

-- Create yearly partitions
CREATE TABLE sales_2023 PARTITION OF sales_yearly
    FOR VALUES FROM (2023) TO (2024)
    PARTITION BY RANGE (EXTRACT(QUARTER FROM sale_date));

CREATE TABLE sales_2024 PARTITION OF sales_yearly
    FOR VALUES FROM (2024) TO (2025)
    PARTITION BY RANGE (EXTRACT(QUARTER FROM sale_date));

-- Create quarterly partitions within each year
CREATE TABLE sales_2023_q1 PARTITION OF sales_2023
    FOR VALUES FROM (1) TO (2);

CREATE TABLE sales_2023_q2 PARTITION OF sales_2023
    FOR VALUES FROM (2) TO (3);

CREATE TABLE sales_2024_q1 PARTITION OF sales_2024
    FOR VALUES FROM (1) TO (2);

CREATE TABLE sales_2024_q2 PARTITION OF sales_2024
    FOR VALUES FROM (2) TO (3);
```

### Automated Partition Creation

```sql
-- Function to create monthly partitions automatically
CREATE OR REPLACE FUNCTION create_monthly_partitions(
    table_name TEXT,
    start_date DATE,
    end_date DATE
)
RETURNS VOID AS $$
DECLARE
    current_date DATE := start_date;
    partition_name TEXT;
BEGIN
    WHILE current_date < end_date LOOP
        partition_name := table_name || '_y' || TO_CHAR(current_date, 'YYYY') || '_m' || TO_CHAR(current_date, 'MM');

        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
            partition_name, table_name, current_date, current_date + INTERVAL '1 month');

        current_date := current_date + INTERVAL '1 month';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Usage: Create partitions for the next 12 months
SELECT create_monthly_partitions('sales', CURRENT_DATE, CURRENT_DATE + INTERVAL '12 months');
```

## Hash Partitioning

### Basic Hash Partitioning

```sql
-- Hash partitioning for even data distribution
CREATE TABLE user_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    ip_address INET,
    user_agent TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    data JSONB
) PARTITION BY HASH (user_id);

-- Create 8 hash partitions for even distribution
CREATE TABLE user_sessions_0 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 0);
CREATE TABLE user_sessions_1 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 1);
CREATE TABLE user_sessions_2 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 2);
CREATE TABLE user_sessions_3 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 3);
CREATE TABLE user_sessions_4 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 4);
CREATE TABLE user_sessions_5 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 5);
CREATE TABLE user_sessions_6 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 6);
CREATE TABLE user_sessions_7 PARTITION OF user_sessions FOR VALUES WITH (MODULUS 8, REMAINDER 7);
```

### Hash Partitioning with Custom Distribution

```sql
-- Hash partitioning with custom modulus for specific needs
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    category_id INTEGER,
    price DECIMAL(10,2),
    stock_quantity INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY HASH (category_id);

-- Create partitions based on expected category distribution
-- Assuming we have categories 1-100, create 16 partitions
DO $$
DECLARE
    i INTEGER;
    partition_name TEXT;
BEGIN
    FOR i IN 0..15 LOOP
        partition_name := 'products_part_' || i;
        EXECUTE format('CREATE TABLE %I PARTITION OF products FOR VALUES WITH (MODULUS 16, REMAINDER %s)', partition_name, i);
    END LOOP;
END $$;
```

## List Partitioning

### Basic List Partitioning

```sql
-- List partitioning for categorical data
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    region VARCHAR(50) NOT NULL,
    order_date DATE NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    shipping_address JSONB
) PARTITION BY LIST (region);

-- Create partitions by region
CREATE TABLE orders_north PARTITION OF orders FOR VALUES IN ('North', 'Northeast');
CREATE TABLE orders_south PARTITION OF orders FOR VALUES IN ('South', 'Southeast');
CREATE TABLE orders_east PARTITION OF orders FOR VALUES IN ('East');
CREATE TABLE orders_west PARTITION OF orders FOR VALUES IN ('West', 'Southwest', 'Northwest');

-- Default partition for unexpected values
CREATE TABLE orders_other PARTITION OF orders DEFAULT;
```

### Status-Based List Partitioning

```sql
-- List partitioning by order status for different processing
CREATE TABLE order_events (
    event_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY LIST (event_type);

-- Create partitions for different event types
CREATE TABLE order_events_created PARTITION OF order_events FOR VALUES IN ('order_created');
CREATE TABLE order_events_payment PARTITION OF order_events FOR VALUES IN ('payment_received', 'payment_failed');
CREATE TABLE order_events_shipping PARTITION OF order_events FOR VALUES IN ('shipped', 'delivered');
CREATE TABLE order_events_returns PARTITION OF order_events FOR VALUES IN ('return_requested', 'return_processed');
CREATE TABLE order_events_other PARTITION OF order_events DEFAULT;
```

## Advanced Partitioning Techniques

### Composite Partitioning

```sql
-- Partition by multiple columns (available in PostgreSQL 13+)
CREATE TABLE sensor_data (
    sensor_id INTEGER NOT NULL,
    reading_date DATE NOT NULL,
    reading_time TIME NOT NULL,
    temperature DECIMAL(5,2),
    humidity DECIMAL(5,2),
    pressure DECIMAL(7,2)
) PARTITION BY RANGE (reading_date), LIST (sensor_id);

-- Note: Composite partitioning syntax may vary by PostgreSQL version
-- For older versions, use sub-partitioning as shown earlier
```

### Partitioning with Inheritance

```sql
-- Using inheritance for partitioning (legacy approach)
CREATE TABLE measurements (
    sensor_id INTEGER,
    measured_at TIMESTAMP WITH TIME ZONE,
    temperature DECIMAL(5,2),
    humidity DECIMAL(5,2)
);

-- Create child tables for each sensor
CREATE TABLE measurements_sensor_1 () INHERITS (measurements);
CREATE TABLE measurements_sensor_2 () INHERITS (measurements);

-- Add constraints to child tables
ALTER TABLE measurements_sensor_1 ADD CONSTRAINT ck_sensor_1 CHECK (sensor_id = 1);
ALTER TABLE measurements_sensor_2 ADD CONSTRAINT ck_sensor_2 CHECK (sensor_id = 2);

-- Create indexes on child tables
CREATE INDEX idx_measurements_sensor_1_time ON measurements_sensor_1 (measured_at);
CREATE INDEX idx_measurements_sensor_2_time ON measurements_sensor_2 (measured_at);

-- Insert data into appropriate partitions
INSERT INTO measurements_sensor_1 (sensor_id, measured_at, temperature, humidity)
VALUES (1, '2024-01-01 10:00:00+00', 22.5, 65.0);
```

### Dynamic Partition Creation

```sql
-- Function to create partitions dynamically based on data patterns
CREATE OR REPLACE FUNCTION create_partition_if_not_exists(
    parent_table TEXT,
    partition_name TEXT,
    partition_type TEXT,
    partition_value TEXT
)
RETURNS VOID AS $$
DECLARE
    check_query TEXT;
    create_query TEXT;
BEGIN
    -- Check if partition exists
    check_query := format('SELECT 1 FROM pg_inherits i JOIN pg_class c ON i.inhrelid = c.oid WHERE c.relname = %L', partition_name);

    IF NOT EXISTS (EXECUTE check_query) THEN
        -- Create partition based on type
        CASE partition_type
            WHEN 'RANGE' THEN
                create_query := format('CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%s) TO (%s)',
                    partition_name, parent_table, partition_value, partition_value || ' + INTERVAL ''1 month''');
            WHEN 'LIST' THEN
                create_query := format('CREATE TABLE %I PARTITION OF %I FOR VALUES IN (%s)',
                    partition_name, parent_table, partition_value);
            ELSE
                RAISE EXCEPTION 'Unsupported partition type: %', partition_type;
        END CASE;

        EXECUTE create_query;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

## Partition Management

### Partition Maintenance

```sql
-- Function to drop old partitions
CREATE OR REPLACE FUNCTION drop_old_partitions(
    table_name TEXT,
    retention_period INTERVAL DEFAULT '1 year'
)
RETURNS INTEGER AS $$
DECLARE
    partition_record RECORD;
    dropped_count INTEGER := 0;
BEGIN
    FOR partition_record IN
        SELECT
            c.relname AS partition_name,
            pg_get_expr(p.partdef, p.partrelid) AS partition_def
        FROM pg_inherits i
        JOIN pg_class c ON i.inhrelid = c.oid
        JOIN pg_partitioned_table p ON i.inhparent = p.partrelid
        WHERE p.partrelid = (SELECT oid FROM pg_class WHERE relname = table_name)
          AND c.relname LIKE table_name || '_%'
    LOOP
        -- Extract date from partition definition and check if it's old enough
        IF partition_record.partition_def ~ 'FOR VALUES FROM \(''(\d{4}-\d{2}-\d{2})''' THEN
            IF (CURRENT_DATE - retention_period) > partition_record.partition_def::DATE THEN
                EXECUTE format('DROP TABLE %I', partition_record.partition_name);
                dropped_count := dropped_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN dropped_count;
END;
$$ LANGUAGE plpgsql;

-- Archive old partitions instead of dropping
CREATE OR REPLACE FUNCTION archive_partition(
    partition_name TEXT,
    archive_schema TEXT DEFAULT 'archive'
)
RETURNS VOID AS $$
BEGIN
    -- Create archive schema if it doesn't exist
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', archive_schema);

    -- Move partition to archive schema
    EXECUTE format('ALTER TABLE %I SET SCHEMA %I', partition_name, archive_schema);

    -- Add archival metadata
    EXECUTE format('COMMENT ON TABLE %I.%I IS ''Archived on %s''',
        archive_schema, partition_name, CURRENT_TIMESTAMP);
END;
$$ LANGUAGE plpgsql;
```

### Partition Statistics and Monitoring

```sql
-- View for partition information
CREATE VIEW partition_info AS
SELECT
    nmsp_parent.nspname AS parent_schema,
    parent.relname AS parent_table,
    nmsp_child.nspname AS partition_schema,
    child.relname AS partition_name,
    pg_size_pretty(pg_total_relation_size(child.oid)) AS size,
    pg_get_expr(partdef, partrelid) AS partition_definition,
    CASE
        WHEN partstrat = 'r' THEN 'RANGE'
        WHEN partstrat = 'l' THEN 'LIST'
        WHEN partstrat = 'h' THEN 'HASH'
    END AS partition_type
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace
JOIN pg_namespace nmsp_child ON nmsp_child.oid = child.relnamespace
LEFT JOIN pg_partitioned_table ON partrelid = parent.oid;

-- Query partition statistics
SELECT
    partition_name,
    size,
    partition_definition,
    partition_type
FROM partition_info
WHERE parent_table = 'sales'
ORDER BY partition_name;

-- Monitor partition growth
CREATE VIEW partition_growth AS
SELECT
    schemaname,
    tablename,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_del AS deletes,
    n_live_tup AS live_rows,
    n_dead_tup AS dead_rows,
    last_autoanalyze,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND tablename LIKE 'sales_%'
ORDER BY last_analyze DESC;
```

### Rebalancing Partitions

```sql
-- Function to rebalance hash partitions (complex operation)
CREATE OR REPLACE FUNCTION rebalance_hash_partitions(
    table_name TEXT,
    new_modulus INTEGER
)
RETURNS VOID AS $$
DECLARE
    partition_record RECORD;
    partition_name TEXT;
    remainder INTEGER;
BEGIN
    -- This is a simplified example - actual rebalancing is complex
    -- and may require data movement between partitions

    -- Drop existing partitions
    FOR partition_record IN
        SELECT c.relname
        FROM pg_inherits i
        JOIN pg_class c ON i.inhrelid = c.oid
        WHERE i.inhparent = (SELECT oid FROM pg_class WHERE relname = table_name)
    LOOP
        EXECUTE format('DROP TABLE %I', partition_record.relname);
    END LOOP;

    -- Create new partitions with new modulus
    FOR remainder IN 0..(new_modulus - 1) LOOP
        partition_name := table_name || '_' || remainder;
        EXECUTE format('CREATE TABLE %I PARTITION OF %I FOR VALUES WITH (MODULUS %s, REMAINDER %s)',
            partition_name, table_name, new_modulus, remainder);
    END LOOP;

    RAISE NOTICE 'Rebalancing completed. Data redistribution required.';
END;
$$ LANGUAGE plpgsql;
```

## Performance Considerations

### Partition Pruning

```sql
-- Examples of queries that benefit from partition pruning
-- Range partitioning pruning
SELECT * FROM sales
WHERE sale_date >= '2024-01-01' AND sale_date < '2024-02-01';
-- Only scans sales_2024_q1 partition

-- List partitioning pruning
SELECT * FROM orders
WHERE region IN ('North', 'Northeast');
-- Only scans orders_north partition

-- Hash partitioning pruning
SELECT * FROM user_sessions
WHERE user_id = 12345;
-- Only scans the partition where hash(user_id) % modulus = remainder
```

### Indexing Strategies

```sql
-- Local indexes on partitions (recommended for most cases)
CREATE INDEX idx_sales_customer_date ON sales_2024_q1 (customer_id, sale_date);
CREATE INDEX idx_sales_product ON sales_2024_q1 (product_id);

-- Global indexes (use sparingly, can cause performance issues)
-- CREATE INDEX idx_sales_global_customer ON sales (customer_id);

-- Partial indexes on partitions
CREATE INDEX idx_orders_pending ON orders (order_date)
WHERE status = 'pending';

-- Expression indexes
CREATE INDEX idx_sales_month ON sales (EXTRACT(MONTH FROM sale_date));
```

### Query Optimization

```sql
-- Force partition pruning with explicit constraints
SELECT *
FROM sales
WHERE sale_date >= '2024-01-01'::DATE
  AND sale_date < '2024-04-01'::DATE;  -- Explicit range

-- Use partition-wise joins (PostgreSQL 11+)
SET enable_partitionwise_join = on;

SELECT s.customer_id, s.amount, c.name
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
WHERE s.sale_date >= '2024-01-01';

-- Optimize for partition-wise aggregation
SELECT
    DATE_TRUNC('month', sale_date) AS month,
    SUM(amount) AS monthly_total,
    COUNT(*) AS transaction_count
FROM sales
WHERE sale_date >= '2024-01-01'
GROUP BY DATE_TRUNC('month', sale_date)
ORDER BY month;
```

### Storage Optimization

```sql
-- Different tablespaces for different partitions
CREATE TABLESPACE fast_ssd LOCATION '/ssd/postgres/data';
CREATE TABLESPACE slow_hdd LOCATION '/hdd/postgres/data';

-- Assign partitions to different storage
ALTER TABLE sales_2024_q1 SET TABLESPACE fast_ssd;
ALTER TABLE sales_2023_q1 SET TABLESPACE slow_hdd;

-- Compression for older partitions
ALTER TABLE sales_2023_q1 SET (autovacuum_enabled = false);
ALTER TABLE sales_2023_q1 SET (fillfactor = 100);

-- Different fillfactor for different access patterns
ALTER TABLE sales_2024_q1 SET (fillfactor = 70);  -- Frequent updates
ALTER TABLE sales_2023_q1 SET (fillfactor = 100); -- Read-only archive
```

## Enterprise Patterns

### Time-Series Data Partitioning

```sql
-- Optimized time-series partitioning with automated management
CREATE TABLE sensor_readings (
    sensor_id INTEGER NOT NULL,
    reading_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    temperature DECIMAL(5,2),
    humidity DECIMAL(5,2),
    pressure DECIMAL(7,2),
    battery_level DECIMAL(5,2),
    signal_strength INTEGER
) PARTITION BY RANGE (reading_timestamp);

-- Create initial partitions
SELECT create_monthly_partitions('sensor_readings', '2024-01-01', '2025-01-01');

-- Automated partition maintenance
CREATE OR REPLACE FUNCTION maintain_sensor_partitions()
RETURNS VOID AS $$
BEGIN
    -- Create future partitions (next 3 months)
    PERFORM create_monthly_partitions(
        'sensor_readings',
        CURRENT_DATE + INTERVAL '1 month',
        CURRENT_DATE + INTERVAL '4 months'
    );

    -- Archive old partitions (older than 1 year)
    PERFORM drop_old_partitions('sensor_readings', INTERVAL '1 year');
END;
$$ LANGUAGE plpgsql;

-- Schedule maintenance (requires pg_cron extension)
-- SELECT cron.schedule('maintain-sensor-partitions', '0 2 * * *', 'SELECT maintain_sensor_partitions()');
```

### Multi-Tenant Partitioning

```sql
-- Multi-tenant partitioning with tenant isolation
CREATE TABLE tenant_data (
    tenant_id INTEGER NOT NULL,
    data_id SERIAL,
    data_type VARCHAR(50) NOT NULL,
    data_content JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, data_id)
) PARTITION BY HASH (tenant_id);

-- Create tenant-specific partitions
CREATE TABLE tenant_data_00 PARTITION OF tenant_data FOR VALUES WITH (MODULUS 100, REMAINDER 0);
CREATE TABLE tenant_data_01 PARTITION OF tenant_data FOR VALUES WITH (MODULUS 100, REMAINDER 1);
-- ... create 98 more partitions ...

-- Tenant-specific constraints and indexes
CREATE OR REPLACE FUNCTION create_tenant_partition_constraints(partition_name TEXT)
RETURNS VOID AS $$
BEGIN
    -- Add check constraints and indexes for each partition
    EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_data_type ON %I (data_type)', partition_name, partition_name);
    EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_created_at ON %I (created_at)', partition_name, partition_name);
END;
$$ LANGUAGE plpgsql;
```

### Audit Log Partitioning

```sql
-- High-volume audit log partitioning
CREATE TABLE audit_log (
    audit_id SERIAL,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(user_id),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT
) PARTITION BY RANGE (changed_at);

-- Daily partitions for audit logs (high volume)
CREATE OR REPLACE FUNCTION create_daily_audit_partitions(days_ahead INTEGER DEFAULT 30)
RETURNS VOID AS $$
DECLARE
    partition_date DATE := CURRENT_DATE;
    partition_name TEXT;
BEGIN
    FOR i IN 0..days_ahead-1 LOOP
        partition_name := 'audit_log_' || TO_CHAR(partition_date, 'YYYY_MM_DD');
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_log FOR VALUES FROM (%L) TO (%L)',
            partition_name, partition_date, partition_date + INTERVAL '1 day');
        partition_date := partition_date + INTERVAL '1 day';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create initial audit partitions
SELECT create_daily_audit_partitions(90);

-- Automated cleanup for audit logs (keep 2 years)
CREATE OR REPLACE FUNCTION cleanup_audit_logs()
RETURNS INTEGER AS $$
DECLARE
    deleted_partitions INTEGER := 0;
    partition_record RECORD;
BEGIN
    FOR partition_record IN
        SELECT c.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class c ON i.inhrelid = c.oid
        WHERE i.inhparent = (SELECT oid FROM pg_class WHERE relname = 'audit_log')
          AND c.relname LIKE 'audit_log_%'
          AND TO_DATE(SUBSTRING(c.relname FROM 'audit_log_(\d{4}_\d{2}_\d{2})'), 'YYYY_MM_DD') < CURRENT_DATE - INTERVAL '2 years'
    LOOP
        EXECUTE format('DROP TABLE %I', partition_record.partition_name);
        deleted_partitions := deleted_partitions + 1;
    END LOOP;

    RETURN deleted_partitions;
END;
$$ LANGUAGE plpgsql;
```

### Rolling Window Partitioning

```sql
-- Rolling window for recent data (e.g., last 30 days)
CREATE TABLE recent_events (
    event_id SERIAL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB,
    occurred_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (occurred_at);

-- Create rolling partitions
CREATE OR REPLACE FUNCTION maintain_rolling_partitions()
RETURNS VOID AS $$
DECLARE
    partition_date DATE;
    partition_name TEXT;
BEGIN
    -- Drop partitions older than 30 days
    FOR partition_date IN
        SELECT TO_DATE(SUBSTRING(c.relname FROM 'recent_events_(\d{4}_\d{2}_\d{2})'), 'YYYY_MM_DD')
        FROM pg_inherits i
        JOIN pg_class c ON i.inhrelid = c.oid
        WHERE i.inhparent = (SELECT oid FROM pg_class WHERE relname = 'recent_events')
          AND TO_DATE(SUBSTRING(c.relname FROM 'recent_events_(\d{4}_\d{2}_\d{2})'), 'YYYY_MM_DD') < CURRENT_DATE - INTERVAL '30 days'
    LOOP
        partition_name := 'recent_events_' || TO_CHAR(partition_date, 'YYYY_MM_DD');
        EXECUTE format('DROP TABLE IF EXISTS %I', partition_name);
    END LOOP;

    -- Create partitions for next 7 days
    FOR i IN 0..6 LOOP
        partition_date := CURRENT_DATE + i;
        partition_name := 'recent_events_' || TO_CHAR(partition_date, 'YYYY_MM_DD');

        IF NOT EXISTS (
            SELECT 1 FROM pg_inherits i
            JOIN pg_class c ON i.inhrelid = c.oid
            WHERE c.relname = partition_name
        ) THEN
            EXECUTE format('CREATE TABLE %I PARTITION OF recent_events FOR VALUES FROM (%L) TO (%L)',
                partition_name, partition_date, partition_date + INTERVAL '1 day');
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

This comprehensive partitioning guide covers all major partitioning strategies in PostgreSQL, with practical examples, performance considerations, and enterprise-level patterns used by major tech companies for handling large-scale data systems.
