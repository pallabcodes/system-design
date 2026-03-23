# Database Performance Hacks & Optimization Techniques

Advanced performance optimization techniques used by companies like Google, Facebook, Twitter, and Netflix to handle massive scale.

## Query Optimization Hacks

### Smart Indexing Strategies
```sql
-- Composite index optimization for common query patterns
CREATE INDEX idx_user_status_created ON users (status, created_at DESC);
CREATE INDEX idx_order_user_status ON orders (user_id, status, created_at DESC);
CREATE INDEX idx_product_category_price ON products (category_id, price, stock_quantity);

-- Partial indexes for filtered queries
CREATE INDEX idx_active_users_email ON users (email) WHERE status = 'active';
CREATE INDEX idx_recent_orders ON orders (user_id, created_at) WHERE created_at > DATE_SUB(NOW(), INTERVAL 30 DAY);

-- Covering indexes to avoid table lookups
CREATE INDEX idx_user_profile_covering ON users (id, email, name, status, created_at);

-- Functional indexes for computed columns
CREATE INDEX idx_user_email_domain ON users ((SUBSTRING_INDEX(email, '@', -1)));
CREATE INDEX idx_order_month ON orders ((DATE_FORMAT(created_at, '%Y-%m')));
```

### Query Rewriting Techniques
```sql
-- Optimize COUNT queries with EXISTS
-- Instead of: SELECT COUNT(*) FROM orders WHERE user_id = 123
-- Use: SELECT EXISTS(SELECT 1 FROM orders WHERE user_id = 123) as has_orders

-- Optimize pagination with keyset pagination
-- Instead of: SELECT * FROM orders ORDER BY created_at LIMIT 100 OFFSET 1000
-- Use: SELECT * FROM orders WHERE created_at > '2024-01-01' ORDER BY created_at LIMIT 100

-- Optimize IN clauses with JOINs
-- Instead of: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE status = 'completed')
-- Use: SELECT DISTINCT u.* FROM users u JOIN orders o ON u.id = o.user_id WHERE o.status = 'completed'
```

## Connection Pooling Hacks

### Advanced Connection Management
```sql
-- Connection pool monitoring
CREATE TABLE connection_pool_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    pool_name VARCHAR(50) NOT NULL,
    active_connections INT NOT NULL,
    idle_connections INT NOT NULL,
    total_connections INT NOT NULL,
    wait_count INT NOT NULL,
    wait_time_ms INT NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_pool_time (pool_name, recorded_at)
);

-- Connection leak detection
CREATE TABLE connection_audit (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    connection_id VARCHAR(36) NOT NULL,
    user_id BIGINT,
    query_text TEXT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    duration_ms INT NULL,
    INDEX idx_user_time (user_id, started_at),
    INDEX idx_duration (duration_ms)
);

-- Long-running query detection
DELIMITER $$
CREATE PROCEDURE detect_long_running_queries()
BEGIN
    SELECT 
        p.id as process_id,
        p.user as user,
        p.host as host,
        p.db as database_name,
        p.command as command,
        p.time as duration_seconds,
        p.state as state,
        p.info as query_text
    FROM information_schema.processlist p
    WHERE p.command != 'Sleep'
    AND p.time > 30  -- Queries running longer than 30 seconds
    ORDER BY p.time DESC;
END$$
DELIMITER ;
```

## Memory Optimization Techniques

### Buffer Pool Optimization
```sql
-- Buffer pool usage monitoring
CREATE VIEW buffer_pool_stats AS
SELECT 
    'buffer_pool_size' as metric,
    @@innodb_buffer_pool_size / (1024*1024*1024) as value_gb
UNION ALL
SELECT 
    'buffer_pool_pages_total',
    @@innodb_buffer_pool_pages_total
UNION ALL
SELECT 
    'buffer_pool_pages_free',
    @@innodb_buffer_pool_pages_free
UNION ALL
SELECT 
    'buffer_pool_pages_data',
    @@innodb_buffer_pool_pages_data
UNION ALL
SELECT 
    'buffer_pool_pages_dirty',
    @@innodb_buffer_pool_pages_dirty;

-- Buffer pool hit ratio calculation
DELIMITER $$
CREATE FUNCTION get_buffer_pool_hit_ratio() 
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE hit_ratio DECIMAL(5,2);
    
    SELECT 
        (1 - (VARIABLE_VALUE / (SELECT VARIABLE_VALUE 
                               FROM performance_schema.global_status 
                               WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'))) * 100
    INTO hit_ratio
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads';
    
    RETURN hit_ratio;
END$$
DELIMITER ;
```

### Query Cache Optimization
```sql
-- Query cache hit ratio monitoring
CREATE VIEW query_cache_stats AS
SELECT 
    'query_cache_size' as metric,
    @@query_cache_size / (1024*1024) as value_mb
UNION ALL
SELECT 
    'query_cache_type',
    @@query_cache_type
UNION ALL
SELECT 
    'Qcache_hits',
    VARIABLE_VALUE
FROM performance_schema.global_status 
WHERE VARIABLE_NAME = 'Qcache_hits'
UNION ALL
SELECT 
    'Qcache_inserts',
    VARIABLE_VALUE
FROM performance_schema.global_status 
WHERE VARIABLE_NAME = 'Qcache_inserts';

-- Query cache efficiency calculation
DELIMITER $$
CREATE FUNCTION get_query_cache_hit_ratio() 
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE hits BIGINT;
    DECLARE inserts BIGINT;
    DECLARE hit_ratio DECIMAL(5,2);
    
    SELECT VARIABLE_VALUE INTO hits
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Qcache_hits';
    
    SELECT VARIABLE_VALUE INTO inserts
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Qcache_inserts';
    
    IF (hits + inserts) > 0 THEN
        SET hit_ratio = (hits * 100.0) / (hits + inserts);
    ELSE
        SET hit_ratio = 0;
    END IF;
    
    RETURN hit_ratio;
END$$
DELIMITER ;
```

## I/O Optimization Hacks

### Disk I/O Monitoring
```sql
-- I/O performance monitoring
CREATE TABLE io_performance_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(50) NOT NULL,
    metric_value BIGINT NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_metric_time (metric_name, recorded_at)
);

-- I/O statistics collection
DELIMITER $$
CREATE PROCEDURE collect_io_stats()
BEGIN
    INSERT INTO io_performance_log (metric_name, metric_value)
    SELECT 'Innodb_data_reads', VARIABLE_VALUE
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_data_reads'
    
    UNION ALL
    
    SELECT 'Innodb_data_writes', VARIABLE_VALUE
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_data_writes'
    
    UNION ALL
    
    SELECT 'Innodb_data_fsyncs', VARIABLE_VALUE
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_data_fsyncs'
    
    UNION ALL
    
    SELECT 'Innodb_log_writes', VARIABLE_VALUE
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_log_writes';
END$$
DELIMITER ;
```

### Table Partitioning Hacks
```sql
-- Time-based partitioning for large tables
CREATE TABLE orders_partitioned (
    id BIGINT AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'completed', 'cancelled') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date) * 100 + MONTH(order_date)) (
    PARTITION p202301 VALUES LESS THAN (202302),
    PARTITION p202302 VALUES LESS THAN (202303),
    PARTITION p202303 VALUES LESS THAN (202304),
    -- ... more partitions
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Hash partitioning for even distribution
CREATE TABLE user_sessions (
    id BIGINT AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    session_token VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 16;

-- List partitioning for categorical data
CREATE TABLE products_partitioned (
    id BIGINT AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, category)
) PARTITION BY LIST COLUMNS(category) (
    PARTITION p_electronics VALUES IN ('laptop', 'phone', 'tablet'),
    PARTITION p_clothing VALUES IN ('shirt', 'pants', 'shoes'),
    PARTITION p_books VALUES IN ('fiction', 'non-fiction', 'technical'),
    PARTITION p_other VALUES IN (DEFAULT)
);
```

## Lock Optimization Techniques

### Deadlock Prevention
```sql
-- Lock timeout monitoring
CREATE TABLE lock_timeouts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    lock_type VARCHAR(20) NOT NULL,
    wait_time_ms INT NOT NULL,
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_table_time (table_name, occurred_at)
);

-- Deadlock detection and logging
DELIMITER $$
CREATE PROCEDURE log_deadlocks()
BEGIN
    INSERT INTO lock_timeouts (table_name, lock_type, wait_time_ms)
    SELECT 
        object_schema as table_name,
        lock_type,
        lock_duration
    FROM performance_schema.metadata_locks
    WHERE lock_duration > 5000; -- Log locks held for more than 5 seconds
END$$
DELIMITER ;

-- Optimistic locking implementation
CREATE TABLE products_optimistic (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    version INT DEFAULT 1,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_version (version)
);

-- Optimistic update procedure
DELIMITER $$
CREATE PROCEDURE update_product_optimistic(
    IN product_id BIGINT,
    IN new_price DECIMAL(10,2),
    IN expected_version INT
)
BEGIN
    DECLARE affected_rows INT;
    
    UPDATE products_optimistic 
    SET price = new_price, version = version + 1
    WHERE id = product_id AND version = expected_version;
    
    SET affected_rows = ROW_COUNT();
    
    IF affected_rows = 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Concurrent modification detected';
    END IF;
END$$
DELIMITER ;
```

## Caching Strategies

### Application-Level Caching
```sql
-- Cache invalidation tracking
CREATE TABLE cache_invalidations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cache_key VARCHAR(255) NOT NULL,
    invalidation_reason VARCHAR(100) NOT NULL,
    invalidated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cache_key (cache_key),
    INDEX idx_invalidated (invalidated_at)
);

-- Cache hit/miss tracking
CREATE TABLE cache_performance (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cache_name VARCHAR(50) NOT NULL,
    hits BIGINT DEFAULT 0,
    misses BIGINT DEFAULT 0,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cache_time (cache_name, recorded_at)
);

-- Cache warming procedure
DELIMITER $$
CREATE PROCEDURE warm_user_cache()
BEGIN
    -- Pre-load frequently accessed user data
    INSERT INTO cache_performance (cache_name, hits, misses)
    SELECT 
        'user_profile',
        COUNT(*) as hits,
        0 as misses
    FROM users u
    WHERE u.last_login > DATE_SUB(NOW(), INTERVAL 7 DAY)
    AND u.status = 'active';
END$$
DELIMITER ;
```

## Query Plan Optimization

### Query Plan Analysis
```sql
-- Query plan storage
CREATE TABLE query_plans (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    query_hash VARCHAR(64) NOT NULL,
    query_text TEXT NOT NULL,
    execution_plan JSON,
    avg_execution_time_ms DECIMAL(10,2),
    execution_count BIGINT DEFAULT 0,
    last_executed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_query_hash (query_hash),
    INDEX idx_execution_time (avg_execution_time_ms)
);

-- Slow query detection
DELIMITER $$
CREATE PROCEDURE detect_slow_queries()
BEGIN
    SELECT 
        digest_text as query_pattern,
        count_star as execution_count,
        avg_timer_wait / 1000000000 as avg_time_ms,
        max_timer_wait / 1000000000 as max_time_ms,
        sum_timer_wait / 1000000000 as total_time_ms
    FROM performance_schema.events_statements_summary_by_digest
    WHERE avg_timer_wait > 1000000000  -- Queries taking more than 1 second on average
    ORDER BY avg_timer_wait DESC
    LIMIT 20;
END$$
DELIMITER ;
```

## Performance Monitoring Dashboard

### Real-time Performance Metrics
```sql
-- Performance dashboard view
CREATE VIEW performance_dashboard AS
SELECT 
    'connections' as metric,
    COUNT(*) as current_value,
    'active connections' as description
FROM information_schema.processlist
WHERE command != 'Sleep'

UNION ALL

SELECT 
    'buffer_pool_hit_ratio',
    get_buffer_pool_hit_ratio(),
    'buffer pool hit ratio (%)'

UNION ALL

SELECT 
    'query_cache_hit_ratio',
    get_query_cache_hit_ratio(),
    'query cache hit ratio (%)'

UNION ALL

SELECT 
    'slow_queries',
    COUNT(*),
    'queries > 1 second in last hour'
FROM performance_schema.events_statements_summary_by_digest
WHERE avg_timer_wait > 1000000000;

-- Performance alerting
DELIMITER $$
CREATE PROCEDURE check_performance_alerts()
BEGIN
    DECLARE buffer_hit_ratio DECIMAL(5,2);
    DECLARE slow_query_count INT;
    
    -- Check buffer pool hit ratio
    SELECT get_buffer_pool_hit_ratio() INTO buffer_hit_ratio;
    IF buffer_hit_ratio < 90 THEN
        INSERT INTO performance_alerts (alert_type, message, severity)
        VALUES ('buffer_pool', CONCAT('Buffer pool hit ratio is low: ', buffer_hit_ratio, '%'), 'warning');
    END IF;
    
    -- Check slow queries
    SELECT COUNT(*) INTO slow_query_count
    FROM performance_schema.events_statements_summary_by_digest
    WHERE avg_timer_wait > 1000000000;
    
    IF slow_query_count > 10 THEN
        INSERT INTO performance_alerts (alert_type, message, severity)
        VALUES ('slow_queries', CONCAT('High number of slow queries: ', slow_query_count), 'warning');
    END IF;
END$$
DELIMITER ;
```
