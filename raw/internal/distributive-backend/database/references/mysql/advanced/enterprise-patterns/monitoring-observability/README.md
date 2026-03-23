# Monitoring & Observability Patterns

Real-world monitoring, observability, and alerting patterns used by product engineers at Google, Netflix, Uber, and other high-scale companies to maintain system health and performance.

## 🚀 Query Performance Monitoring

### The "Slow Query Detection" Pattern
```sql
-- Slow query monitoring
CREATE TABLE slow_query_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    query_hash VARCHAR(64) NOT NULL,
    query_text TEXT NOT NULL,
    execution_time_ms INT NOT NULL,
    rows_examined BIGINT NOT NULL,
    rows_sent BIGINT NOT NULL,
    user_id BIGINT NULL,
    session_id VARCHAR(100) NULL,
    ip_address VARCHAR(45) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_query_hash (query_hash, created_at),
    INDEX idx_execution_time (execution_time_ms DESC, created_at),
    INDEX idx_user_time (user_id, created_at)
);

-- Slow query detection trigger
DELIMITER $$
CREATE TRIGGER detect_slow_queries()
AFTER SELECT ON users
FOR EACH ROW
BEGIN
    DECLARE execution_time_ms INT;
    DECLARE query_hash VARCHAR(64);
    
    -- Get execution time (this would be captured by application layer)
    SET execution_time_ms = @query_execution_time;
    
    -- Generate query hash
    SET query_hash = SHA2(@current_query_text, 256);
    
    -- Log if query is slow (> 1000ms)
    IF execution_time_ms > 1000 THEN
        INSERT INTO slow_query_log (query_hash, query_text, execution_time_ms, rows_examined, rows_sent, user_id, session_id, ip_address)
        VALUES (query_hash, @current_query_text, execution_time_ms, @rows_examined, @rows_sent, @current_user_id, @current_session_id, @current_ip_address);
    END IF;
END$$
DELIMITER ;

-- Slow query analysis
CREATE VIEW slow_query_analysis AS
SELECT 
    query_hash,
    COUNT(*) as occurrence_count,
    AVG(execution_time_ms) as avg_execution_time,
    MAX(execution_time_ms) as max_execution_time,
    MIN(execution_time_ms) as min_execution_time,
    SUM(rows_examined) as total_rows_examined,
    SUM(rows_sent) as total_rows_sent,
    MIN(created_at) as first_occurrence,
    MAX(created_at) as last_occurrence
FROM slow_query_log
WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY query_hash
ORDER BY avg_execution_time DESC;
```

### The "Query Plan Analysis" Pattern
```sql
-- Query plan storage
CREATE TABLE query_plans (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    query_hash VARCHAR(64) NOT NULL,
    query_text TEXT NOT NULL,
    execution_plan JSON NOT NULL,
    estimated_cost DECIMAL(10,2) NOT NULL,
    actual_execution_time_ms INT NOT NULL,
    rows_examined BIGINT NOT NULL,
    rows_sent BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_query_hash (query_hash, created_at),
    INDEX idx_cost (estimated_cost DESC, created_at),
    INDEX idx_execution_time (actual_execution_time_ms DESC, created_at)
);

-- Query plan analysis procedure
DELIMITER $$
CREATE PROCEDURE analyze_query_plans()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE query_hash VARCHAR(64);
    DECLARE query_text TEXT;
    DECLARE execution_plan JSON;
    
    DECLARE query_cursor CURSOR FOR
        SELECT DISTINCT qh.query_hash, qh.query_text
        FROM slow_query_log qh
        WHERE qh.created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
        AND NOT EXISTS (
            SELECT 1 FROM query_plans qp 
            WHERE qp.query_hash = qh.query_hash
        );
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN query_cursor;
    
    analyze_loop: LOOP
        FETCH query_cursor INTO query_hash, query_text;
        IF done THEN
            LEAVE analyze_loop;
        END IF;
        
        -- In a real implementation, this would capture the actual EXPLAIN plan
        -- For demo purposes, we'll simulate it
        SET execution_plan = JSON_OBJECT(
            'query_hash', query_hash,
            'estimated_cost', RAND() * 1000,
            'actual_time', (SELECT AVG(execution_time_ms) FROM slow_query_log WHERE query_hash = query_hash)
        );
        
        INSERT INTO query_plans (query_hash, query_text, execution_plan, estimated_cost, actual_execution_time_ms, rows_examined, rows_sent)
        VALUES (
            query_hash,
            query_text,
            execution_plan,
            JSON_EXTRACT(execution_plan, '$.estimated_cost'),
            JSON_EXTRACT(execution_plan, '$.actual_time'),
            0, 0
        );
    END LOOP;
    
    CLOSE query_cursor;
END$$
DELIMITER ;
```

## 🔍 Deadlock Detection & Prevention

### The "Deadlock Monitoring" Pattern
```sql
-- Deadlock monitoring
CREATE TABLE deadlock_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    deadlock_id VARCHAR(100) NOT NULL,
    deadlock_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deadlock_details JSON NOT NULL,
    affected_tables JSON NOT NULL,
    involved_queries JSON NOT NULL,
    resolution_time_ms INT NULL,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolution_method VARCHAR(50) NULL,
    
    INDEX idx_deadlock_time (deadlock_time),
    INDEX idx_resolved (is_resolved, deadlock_time),
    INDEX idx_tables ((CAST(affected_tables->>'$.tables' AS CHAR(255))))
);

-- Deadlock detection procedure
DELIMITER $$
CREATE PROCEDURE detect_deadlocks()
BEGIN
    DECLARE deadlock_count INT;
    
    -- Check for deadlocks in the last hour
    SELECT COUNT(*) INTO deadlock_count
    FROM information_schema.innodb_metrics
    WHERE name = 'lock_deadlocks'
    AND count > 0;
    
    IF deadlock_count > 0 THEN
        -- Log deadlock information
        INSERT INTO deadlock_log (deadlock_id, deadlock_details, affected_tables, involved_queries)
        VALUES (
            UUID(),
            JSON_OBJECT(
                'deadlock_count', deadlock_count,
                'detection_time', NOW()
            ),
            JSON_ARRAY('users', 'orders', 'products'),
            JSON_ARRAY(
                'UPDATE users SET status = "active" WHERE id = 123',
                'UPDATE orders SET status = "confirmed" WHERE user_id = 123'
            )
        );
    END IF;
END$$
DELIMITER ;
```

### The "Lock Timeout Monitoring" Pattern
```sql
-- Lock timeout monitoring
CREATE TABLE lock_timeouts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    lock_type VARCHAR(50) NOT NULL,
    lock_mode VARCHAR(20) NOT NULL,
    wait_time_ms INT NOT NULL,
    timeout_threshold_ms INT DEFAULT 5000,
    user_id BIGINT NULL,
    session_id VARCHAR(100) NULL,
    query_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_table_timeout (table_name, wait_time_ms, created_at),
    INDEX idx_lock_type (lock_type, wait_time_ms),
    INDEX idx_user_timeout (user_id, created_at)
);

-- Lock timeout detection
DELIMITER $$
CREATE PROCEDURE monitor_lock_timeouts()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE table_name VARCHAR(100);
    DECLARE lock_type VARCHAR(50);
    DECLARE wait_time_ms INT;
    
    DECLARE lock_cursor CURSOR FOR
        SELECT 
            object_schema as table_name,
            lock_type,
            lock_duration as wait_time_ms
        FROM performance_schema.metadata_locks
        WHERE lock_duration > 5000;  -- 5 seconds threshold
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN lock_cursor;
    
    lock_loop: LOOP
        FETCH lock_cursor INTO table_name, lock_type, wait_time_ms;
        IF done THEN
            LEAVE lock_loop;
        END IF;
        
        -- Log lock timeout
        INSERT INTO lock_timeouts (table_name, lock_type, lock_mode, wait_time_ms)
        VALUES (table_name, lock_type, 'EXCLUSIVE', wait_time_ms);
    END LOOP;
    
    CLOSE lock_cursor;
END$$
DELIMITER ;
```

## 📊 Resource Utilization Tracking

### The "Database Resource Monitoring" Pattern
```sql
-- Database resource metrics
CREATE TABLE database_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(15,2) NOT NULL,
    metric_unit VARCHAR(20) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_metric_time (metric_name, recorded_at),
    INDEX idx_value (metric_value DESC, recorded_at)
);

-- Resource monitoring procedure
DELIMITER $$
CREATE PROCEDURE collect_database_metrics()
BEGIN
    -- CPU usage
    INSERT INTO database_metrics (metric_name, metric_value, metric_unit)
    SELECT 'cpu_usage_percent', VARIABLE_VALUE, 'percent'
    FROM performance_schema.global_status
    WHERE VARIABLE_NAME = 'Threads_connected';
    
    -- Memory usage
    INSERT INTO database_metrics (metric_name, metric_value, metric_unit)
    SELECT 'memory_usage_mb', VARIABLE_VALUE / 1024 / 1024, 'MB'
    FROM performance_schema.global_status
    WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data';
    
    -- Connection count
    INSERT INTO database_metrics (metric_name, metric_value, metric_unit)
    SELECT 'active_connections', VARIABLE_VALUE, 'count'
    FROM performance_schema.global_status
    WHERE VARIABLE_NAME = 'Threads_connected';
    
    -- Buffer pool hit ratio
    INSERT INTO database_metrics (metric_name, metric_value, metric_unit)
    SELECT 
        'buffer_pool_hit_ratio',
        (1 - (VARIABLE_VALUE / (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'))) * 100,
        'percent'
    FROM performance_schema.global_status
    WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads';
    
    -- Query cache hit ratio
    INSERT INTO database_metrics (metric_name, metric_value, metric_unit)
    SELECT 
        'query_cache_hit_ratio',
        (VARIABLE_VALUE * 100.0 / (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Qcache_inserts' + VARIABLE_VALUE)),
        'percent'
    FROM performance_schema.global_status
    WHERE VARIABLE_NAME = 'Qcache_hits';
END$$
DELIMITER ;
```

### The "Storage Monitoring" Pattern
```sql
-- Storage monitoring
CREATE TABLE storage_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    table_size_mb DECIMAL(10,2) NOT NULL,
    index_size_mb DECIMAL(10,2) NOT NULL,
    total_size_mb DECIMAL(10,2) NOT NULL,
    row_count BIGINT NOT NULL,
    avg_row_length INT NOT NULL,
    data_free_mb DECIMAL(10,2) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_table_size (table_name, total_size_mb DESC),
    INDEX idx_recorded (recorded_at DESC)
);

-- Storage monitoring procedure
DELIMITER $$
CREATE PROCEDURE collect_storage_metrics()
BEGIN
    INSERT INTO storage_metrics (
        table_name, table_size_mb, index_size_mb, total_size_mb, 
        row_count, avg_row_length, data_free_mb
    )
    SELECT 
        table_name,
        ROUND(data_length / 1024 / 1024, 2) as table_size_mb,
        ROUND(index_length / 1024 / 1024, 2) as index_size_mb,
        ROUND((data_length + index_length) / 1024 / 1024, 2) as total_size_mb,
        table_rows as row_count,
        avg_row_length,
        ROUND(data_free / 1024 / 1024, 2) as data_free_mb
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
    AND table_type = 'BASE TABLE';
END$$
DELIMITER ;
```

## 🚨 Alerting & Incident Response

### The "Performance Alerting" Pattern
```sql
-- Performance alerts
CREATE TABLE performance_alerts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,  -- 'slow_query', 'deadlock', 'high_cpu', 'low_memory'
    alert_message TEXT NOT NULL,
    severity ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    metric_name VARCHAR(100) NULL,
    metric_value DECIMAL(15,2) NULL,
    threshold_value DECIMAL(15,2) NULL,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP NULL,
    resolved_by VARCHAR(100) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_alert_type (alert_type, is_resolved),
    INDEX idx_severity (severity, created_at),
    INDEX idx_metric (metric_name, created_at)
);

-- Alerting procedure
DELIMITER $$
CREATE PROCEDURE check_performance_alerts()
BEGIN
    DECLARE slow_query_count INT;
    DECLARE deadlock_count INT;
    DECLARE cpu_usage DECIMAL(5,2);
    DECLARE memory_usage DECIMAL(5,2);
    
    -- Check for slow queries
    SELECT COUNT(*) INTO slow_query_count
    FROM slow_query_log
    WHERE created_at > DATE_SUB(NOW(), INTERVAL 5 MINUTE)
    AND execution_time_ms > 5000;
    
    IF slow_query_count > 10 THEN
        INSERT INTO performance_alerts (alert_type, alert_message, severity, metric_name, metric_value, threshold_value)
        VALUES ('slow_query', CONCAT('High number of slow queries: ', slow_query_count), 'high', 'slow_queries', slow_query_count, 10);
    END IF;
    
    -- Check for deadlocks
    SELECT COUNT(*) INTO deadlock_count
    FROM deadlock_log
    WHERE created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
    AND is_resolved = FALSE;
    
    IF deadlock_count > 5 THEN
        INSERT INTO performance_alerts (alert_type, alert_message, severity, metric_name, metric_value, threshold_value)
        VALUES ('deadlock', CONCAT('High number of deadlocks: ', deadlock_count), 'critical', 'deadlocks', deadlock_count, 5);
    END IF;
    
    -- Check CPU usage
    SELECT metric_value INTO cpu_usage
    FROM database_metrics
    WHERE metric_name = 'cpu_usage_percent'
    AND recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)
    ORDER BY recorded_at DESC
    LIMIT 1;
    
    IF cpu_usage > 80 THEN
        INSERT INTO performance_alerts (alert_type, alert_message, severity, metric_name, metric_value, threshold_value)
        VALUES ('high_cpu', CONCAT('High CPU usage: ', cpu_usage, '%'), 'high', 'cpu_usage_percent', cpu_usage, 80);
    END IF;
    
    -- Check memory usage
    SELECT metric_value INTO memory_usage
    FROM database_metrics
    WHERE metric_name = 'memory_usage_mb'
    AND recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)
    ORDER BY recorded_at DESC
    LIMIT 1;
    
    IF memory_usage > 1000 THEN  -- 1GB threshold
        INSERT INTO performance_alerts (alert_type, alert_message, severity, metric_name, metric_value, threshold_value)
        VALUES ('high_memory', CONCAT('High memory usage: ', memory_usage, 'MB'), 'medium', 'memory_usage_mb', memory_usage, 1000);
    END IF;
END$$
DELIMITER ;
```

### The "Incident Response" Pattern
```sql
-- Incident tracking
CREATE TABLE incidents (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    incident_id VARCHAR(100) UNIQUE NOT NULL,
    alert_id BIGINT NOT NULL,
    incident_type VARCHAR(50) NOT NULL,
    severity ENUM('low', 'medium', 'high', 'critical') NOT NULL,
    status ENUM('open', 'investigating', 'mitigating', 'resolved', 'closed') DEFAULT 'open',
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    root_cause TEXT NULL,
    resolution TEXT NULL,
    assigned_to VARCHAR(100) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    closed_at TIMESTAMP NULL,
    
    INDEX idx_incident_type (incident_type, status),
    INDEX idx_severity (severity, status),
    INDEX idx_assigned (assigned_to, status),
    INDEX idx_status (status, created_at)
);

-- Incident response procedure
DELIMITER $$
CREATE PROCEDURE create_incident_from_alert(
    IN alert_id BIGINT
)
BEGIN
    DECLARE alert_type VARCHAR(50);
    DECLARE alert_message TEXT;
    DECLARE alert_severity VARCHAR(20);
    
    -- Get alert details
    SELECT pa.alert_type, pa.alert_message, pa.severity
    INTO alert_type, alert_message, alert_severity
    FROM performance_alerts pa
    WHERE pa.id = alert_id;
    
    -- Create incident
    INSERT INTO incidents (incident_id, alert_id, incident_type, severity, title, description)
    VALUES (
        UUID(),
        alert_id,
        alert_type,
        alert_severity,
        CONCAT('Database Performance Issue: ', alert_type),
        alert_message
    );
END$$
DELIMITER ;
```

## 📈 Observability Dashboards

### The "Performance Dashboard" Pattern
```sql
-- Performance dashboard view
CREATE VIEW performance_dashboard AS
SELECT 
    'slow_queries' as metric,
    COUNT(*) as value,
    'Slow queries in last hour' as description
FROM slow_query_log
WHERE created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)

UNION ALL

SELECT 
    'deadlocks',
    COUNT(*),
    'Deadlocks in last hour'
FROM deadlock_log
WHERE created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)

UNION ALL

SELECT 
    'active_connections',
    COALESCE(metric_value, 0),
    'Current active connections'
FROM database_metrics
WHERE metric_name = 'active_connections'
AND recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)
ORDER BY recorded_at DESC
LIMIT 1

UNION ALL

SELECT 
    'buffer_pool_hit_ratio',
    COALESCE(metric_value, 0),
    'Buffer pool hit ratio (%)'
FROM database_metrics
WHERE metric_name = 'buffer_pool_hit_ratio'
AND recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)
ORDER BY recorded_at DESC
LIMIT 1

UNION ALL

SELECT 
    'open_alerts',
    COUNT(*),
    'Open performance alerts'
FROM performance_alerts
WHERE is_resolved = FALSE

UNION ALL

SELECT 
    'open_incidents',
    COUNT(*),
    'Open incidents'
FROM incidents
WHERE status IN ('open', 'investigating', 'mitigating');
```

### The "Trend Analysis" Pattern
```sql
-- Performance trends
CREATE VIEW performance_trends AS
SELECT 
    DATE(recorded_at) as date,
    metric_name,
    AVG(metric_value) as avg_value,
    MAX(metric_value) as max_value,
    MIN(metric_value) as min_value,
    COUNT(*) as data_points
FROM database_metrics
WHERE recorded_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(recorded_at), metric_name
ORDER BY date DESC, metric_name;

-- Slow query trends
CREATE VIEW slow_query_trends AS
SELECT 
    DATE(created_at) as date,
    COUNT(*) as slow_query_count,
    AVG(execution_time_ms) as avg_execution_time,
    MAX(execution_time_ms) as max_execution_time,
    COUNT(DISTINCT user_id) as affected_users
FROM slow_query_log
WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

These monitoring and observability patterns show the real-world techniques that product engineers use to maintain system health and performance! 🚀
