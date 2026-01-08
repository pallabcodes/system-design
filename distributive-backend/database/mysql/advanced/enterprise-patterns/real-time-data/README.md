# Real-Time Data Patterns & Streaming Techniques

Real-time data processing patterns, change data capture (CDC), and streaming techniques used by product engineers at Uber, Netflix, Twitter, and other real-time platforms.

## 🚀 Change Data Capture (CDC) Patterns

### The "Binlog-Based CDC" Pattern
```sql
-- CDC event tracking table
CREATE TABLE cdc_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    record_id BIGINT NOT NULL,
    old_data JSON NULL,  -- Previous state for UPDATE/DELETE
    new_data JSON NULL,  -- New state for INSERT/UPDATE
    binlog_position VARCHAR(100) NOT NULL,
    transaction_id VARCHAR(100) NOT NULL,
    event_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed BOOLEAN DEFAULT FALSE,
    processed_at TIMESTAMP NULL,
    
    INDEX idx_table_operation (table_name, operation, event_timestamp),
    INDEX idx_record (table_name, record_id, event_timestamp),
    INDEX idx_processed (processed, event_timestamp),
    INDEX idx_binlog (binlog_position)
);

-- CDC event generation trigger
DELIMITER $$
CREATE TRIGGER cdc_users_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO cdc_events (table_name, operation, record_id, new_data, binlog_position, transaction_id)
    VALUES (
        'users',
        'INSERT',
        NEW.id,
        JSON_OBJECT(
            'id', NEW.id,
            'email', NEW.email,
            'name', NEW.name,
            'status', NEW.status,
            'created_at', NEW.created_at
        ),
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Binlog_position'),
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Binlog_transaction_id')
    );
END$$

CREATE TRIGGER cdc_users_update
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    INSERT INTO cdc_events (table_name, operation, record_id, old_data, new_data, binlog_position, transaction_id)
    VALUES (
        'users',
        'UPDATE',
        NEW.id,
        JSON_OBJECT(
            'id', OLD.id,
            'email', OLD.email,
            'name', OLD.name,
            'status', OLD.status,
            'updated_at', OLD.updated_at
        ),
        JSON_OBJECT(
            'id', NEW.id,
            'email', NEW.email,
            'name', NEW.name,
            'status', NEW.status,
            'updated_at', NEW.updated_at
        ),
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Binlog_position'),
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Binlog_transaction_id')
    );
END$$

CREATE TRIGGER cdc_users_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO cdc_events (table_name, operation, record_id, old_data, binlog_position, transaction_id)
    VALUES (
        'users',
        'DELETE',
        OLD.id,
        JSON_OBJECT(
            'id', OLD.id,
            'email', OLD.email,
            'name', OLD.name,
            'status', OLD.status,
            'deleted_at', NOW()
        ),
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Binlog_position'),
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Binlog_transaction_id')
    );
END$$
DELIMITER ;
```

### The "CDC Event Processing" Pattern
```sql
-- CDC event processor
DELIMITER $$
CREATE PROCEDURE process_cdc_events()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE event_id BIGINT;
    DECLARE table_name VARCHAR(100);
    DECLARE operation VARCHAR(20);
    DECLARE record_id BIGINT;
    DECLARE old_data JSON;
    DECLARE new_data JSON;
    
    DECLARE event_cursor CURSOR FOR
        SELECT id, table_name, operation, record_id, old_data, new_data
        FROM cdc_events
        WHERE processed = FALSE
        ORDER BY event_timestamp ASC
        LIMIT 100;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN event_cursor;
    
    process_loop: LOOP
        FETCH event_cursor INTO event_id, table_name, operation, record_id, old_data, new_data;
        IF done THEN
            LEAVE process_loop;
        END IF;
        
        -- Process based on operation type
        CASE operation
            WHEN 'INSERT' THEN
                CALL handle_cdc_insert(table_name, record_id, new_data);
            WHEN 'UPDATE' THEN
                CALL handle_cdc_update(table_name, record_id, old_data, new_data);
            WHEN 'DELETE' THEN
                CALL handle_cdc_delete(table_name, record_id, old_data);
        END CASE;
        
        -- Mark as processed
        UPDATE cdc_events 
        SET processed = TRUE, processed_at = NOW()
        WHERE id = event_id;
    END LOOP;
    
    CLOSE event_cursor;
END$$
DELIMITER ;
```

## 🎯 Real-Time Analytics Patterns

### The "Real-Time Metrics" Pattern
```sql
-- Real-time metrics aggregation
CREATE TABLE real_time_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(15,2) NOT NULL,
    aggregation_window ENUM('minute', 'hour', 'day') NOT NULL,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    record_count INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_metric_window (metric_name, aggregation_window, window_start),
    INDEX idx_metric_time (metric_name, window_start),
    INDEX idx_window (aggregation_window, window_start)
);

-- Real-time user activity metrics
CREATE TABLE user_activity_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    activity_type VARCHAR(50) NOT NULL,  -- 'login', 'post', 'like', 'comment'
    activity_count INT DEFAULT 1,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_activity (user_id, activity_type),
    INDEX idx_activity_type (activity_type, last_activity),
    INDEX idx_user_time (user_id, last_activity)
);

-- Real-time aggregation procedure
DELIMITER $$
CREATE PROCEDURE aggregate_real_time_metrics()
BEGIN
    -- Aggregate user activity by minute
    INSERT INTO real_time_metrics (metric_name, metric_value, aggregation_window, window_start, window_end, record_count)
    SELECT 
        CONCAT('user_', activity_type, '_per_minute'),
        COUNT(*) as metric_value,
        'minute' as aggregation_window,
        DATE_FORMAT(last_activity, '%Y-%m-%d %H:%i:00') as window_start,
        DATE_FORMAT(last_activity, '%Y-%m-%d %H:%i:59') as window_end,
        COUNT(*) as record_count
    FROM user_activity_metrics
    WHERE last_activity >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    GROUP BY activity_type, DATE_FORMAT(last_activity, '%Y-%m-%d %H:%i:00')
    ON DUPLICATE KEY UPDATE
        metric_value = VALUES(metric_value),
        record_count = VALUES(record_count);
    
    -- Aggregate by hour
    INSERT INTO real_time_metrics (metric_name, metric_value, aggregation_window, window_start, window_end, record_count)
    SELECT 
        CONCAT('user_', activity_type, '_per_hour'),
        COUNT(*) as metric_value,
        'hour' as aggregation_window,
        DATE_FORMAT(last_activity, '%Y-%m-%d %H:00:00') as window_start,
        DATE_FORMAT(last_activity, '%Y-%m-%d %H:59:59') as window_end,
        COUNT(*) as record_count
    FROM user_activity_metrics
    WHERE last_activity >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    GROUP BY activity_type, DATE_FORMAT(last_activity, '%Y-%m-%d %H:00:00')
    ON DUPLICATE KEY UPDATE
        metric_value = VALUES(metric_value),
        record_count = VALUES(record_count);
END$$
DELIMITER ;
```

### The "Real-Time Dashboard" Pattern
```sql
-- Real-time dashboard metrics
CREATE VIEW real_time_dashboard AS
SELECT 
    'active_users' as metric,
    COUNT(DISTINCT user_id) as value,
    'Current active users' as description
FROM user_activity_metrics
WHERE last_activity > DATE_SUB(NOW(), INTERVAL 5 MINUTE)

UNION ALL

SELECT 
    'posts_per_minute',
    COALESCE(SUM(CASE WHEN activity_type = 'post' THEN activity_count ELSE 0 END), 0),
    'Posts created in last minute'
FROM user_activity_metrics
WHERE last_activity > DATE_SUB(NOW(), INTERVAL 1 MINUTE)

UNION ALL

SELECT 
    'likes_per_minute',
    COALESCE(SUM(CASE WHEN activity_type = 'like' THEN activity_count ELSE 0 END), 0),
    'Likes in last minute'
FROM user_activity_metrics
WHERE last_activity > DATE_SUB(NOW(), INTERVAL 1 MINUTE)

UNION ALL

SELECT 
    'comments_per_minute',
    COALESCE(SUM(CASE WHEN activity_type = 'comment' THEN activity_count ELSE 0 END), 0),
    'Comments in last minute'
FROM user_activity_metrics
WHERE last_activity > DATE_SUB(NOW(), INTERVAL 1 MINUTE);
```

## 🔥 Streaming Data Processing

### The "Event Stream" Pattern
```sql
-- Event stream for real-time processing
CREATE TABLE event_stream (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    event_data JSON NOT NULL,
    source_system VARCHAR(50) NOT NULL,
    priority INT DEFAULT 5,  -- 1=high, 10=low
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL,
    
    INDEX idx_event_type (event_type, status, created_at),
    INDEX idx_priority (priority, status, created_at),
    INDEX idx_source (source_system, created_at)
);

-- Event stream processor
DELIMITER $$
CREATE PROCEDURE process_event_stream()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE event_id BIGINT;
    DECLARE event_type VARCHAR(100);
    DECLARE event_data JSON;
    DECLARE retry_count INT;
    DECLARE max_retries INT;
    
    DECLARE event_cursor CURSOR FOR
        SELECT id, event_type, event_data, retry_count, max_retries
        FROM event_stream
        WHERE status = 'pending'
        ORDER BY priority ASC, created_at ASC
        LIMIT 100;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN event_cursor;
    
    process_loop: LOOP
        FETCH event_cursor INTO event_id, event_type, event_data, retry_count, max_retries;
        IF done THEN
            LEAVE process_loop;
        END IF;
        
        -- Mark as processing
        UPDATE event_stream SET status = 'processing' WHERE id = event_id;
        
        -- Process based on event type
        CASE event_type
            WHEN 'user_registered' THEN
                CALL handle_user_registered(event_data);
            WHEN 'user_login' THEN
                CALL handle_user_login(event_data);
            WHEN 'post_created' THEN
                CALL handle_post_created(event_data);
            WHEN 'like_added' THEN
                CALL handle_like_added(event_data);
            WHEN 'comment_added' THEN
                CALL handle_comment_added(event_data);
            ELSE
                -- Unknown event type
                UPDATE event_stream 
                SET status = 'failed', processed_at = NOW()
                WHERE id = event_id;
        END CASE;
        
        -- Mark as completed if successful
        IF (SELECT status FROM event_stream WHERE id = event_id) = 'processing' THEN
            UPDATE event_stream 
            SET status = 'completed', processed_at = NOW()
            WHERE id = event_id;
        END IF;
    END LOOP;
    
    CLOSE event_cursor;
END$$
DELIMITER ;
```

### The "Real-Time Notifications" Pattern
```sql
-- Real-time notification system
CREATE TABLE real_time_notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    notification_type VARCHAR(50) NOT NULL,  -- 'like', 'comment', 'follow', 'mention'
    notification_data JSON NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    is_sent BOOLEAN DEFAULT FALSE,
    priority INT DEFAULT 5,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP NULL,
    read_at TIMESTAMP NULL,
    
    INDEX idx_user_notifications (user_id, is_read, created_at),
    INDEX idx_notification_type (notification_type, created_at),
    INDEX idx_priority (priority, is_sent, created_at)
);

-- Real-time notification processor
DELIMITER $$
CREATE PROCEDURE process_real_time_notifications()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE notification_id BIGINT;
    DECLARE user_id BIGINT;
    DECLARE notification_type VARCHAR(50);
    DECLARE notification_data JSON;
    
    DECLARE notification_cursor CURSOR FOR
        SELECT id, user_id, notification_type, notification_data
        FROM real_time_notifications
        WHERE is_sent = FALSE
        ORDER BY priority ASC, created_at ASC
        LIMIT 50;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN notification_cursor;
    
    process_loop: LOOP
        FETCH notification_cursor INTO notification_id, user_id, notification_type, notification_data;
        IF done THEN
            LEAVE process_loop;
        END IF;
        
        -- Send notification (this would integrate with WebSocket, push notification, etc.)
        CALL send_notification(user_id, notification_type, notification_data);
        
        -- Mark as sent
        UPDATE real_time_notifications 
        SET is_sent = TRUE, sent_at = NOW()
        WHERE id = notification_id;
    END LOOP;
    
    CLOSE notification_cursor;
END$$
DELIMITER ;
```

## 🎪 WebSocket Data Synchronization

### The "WebSocket Session Management" Pattern
```sql
-- WebSocket session tracking
CREATE TABLE websocket_sessions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(100) UNIQUE NOT NULL,
    user_id BIGINT NOT NULL,
    connection_id VARCHAR(100) NOT NULL,
    client_type VARCHAR(50) NOT NULL,  -- 'web', 'mobile', 'desktop'
    is_active BOOLEAN DEFAULT TRUE,
    last_heartbeat TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    disconnected_at TIMESTAMP NULL,
    
    INDEX idx_user_sessions (user_id, is_active),
    INDEX idx_connection (connection_id),
    INDEX idx_heartbeat (last_heartbeat)
);

-- WebSocket message queue
CREATE TABLE websocket_messages (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(100) NOT NULL,
    message_type VARCHAR(50) NOT NULL,  -- 'notification', 'update', 'sync'
    message_data JSON NOT NULL,
    priority INT DEFAULT 5,
    is_delivered BOOLEAN DEFAULT FALSE,
    delivery_attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMP NULL,
    
    INDEX idx_session_messages (session_id, is_delivered, created_at),
    INDEX idx_message_type (message_type, created_at),
    INDEX idx_priority (priority, is_delivered, created_at)
);

-- WebSocket message processor
DELIMITER $$
CREATE PROCEDURE process_websocket_messages()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE message_id BIGINT;
    DECLARE session_id VARCHAR(100);
    DECLARE message_type VARCHAR(50);
    DECLARE message_data JSON;
    DECLARE delivery_attempts INT;
    DECLARE max_attempts INT;
    
    DECLARE message_cursor CURSOR FOR
        SELECT id, session_id, message_type, message_data, delivery_attempts, max_attempts
        FROM websocket_messages
        WHERE is_delivered = FALSE
        AND delivery_attempts < max_attempts
        ORDER BY priority ASC, created_at ASC
        LIMIT 100;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN message_cursor;
    
    process_loop: LOOP
        FETCH message_cursor INTO message_id, session_id, message_type, message_data, delivery_attempts, max_attempts;
        IF done THEN
            LEAVE process_loop;
        END IF;
        
        -- Check if session is still active
        IF EXISTS (
            SELECT 1 FROM websocket_sessions 
            WHERE session_id = session_id AND is_active = TRUE
        ) THEN
            -- Send message via WebSocket (this would integrate with actual WebSocket server)
            CALL send_websocket_message(session_id, message_type, message_data);
            
            -- Mark as delivered
            UPDATE websocket_messages 
            SET is_delivered = TRUE, delivered_at = NOW()
            WHERE id = message_id;
        ELSE
            -- Increment delivery attempts
            UPDATE websocket_messages 
            SET delivery_attempts = delivery_attempts + 1
            WHERE id = message_id;
        END IF;
    END LOOP;
    
    CLOSE message_cursor;
END$$
DELIMITER ;
```

## 🔧 Real-Time Monitoring & Alerting

### The "Real-Time Health Monitoring" Pattern
```sql
-- Real-time system health metrics
CREATE TABLE real_time_health (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(15,2) NOT NULL,
    threshold_value DECIMAL(15,2) NOT NULL,
    severity ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    is_alerting BOOLEAN DEFAULT FALSE,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_metric_time (metric_name, recorded_at),
    INDEX idx_alerting (is_alerting, severity, recorded_at)
);

-- Real-time health monitoring procedure
DELIMITER $$
CREATE PROCEDURE monitor_real_time_health()
BEGIN
    DECLARE active_users_count INT;
    DECLARE response_time_avg DECIMAL(10,2);
    DECLARE error_rate DECIMAL(5,2);
    
    -- Monitor active users
    SELECT COUNT(DISTINCT user_id) INTO active_users_count
    FROM user_activity_metrics
    WHERE last_activity > DATE_SUB(NOW(), INTERVAL 5 MINUTE);
    
    INSERT INTO real_time_health (metric_name, metric_value, threshold_value, severity)
    VALUES ('active_users', active_users_count, 1000, 'medium');
    
    -- Monitor response time
    SELECT AVG(response_time_ms) INTO response_time_avg
    FROM cache_metrics
    WHERE recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE);
    
    INSERT INTO real_time_health (metric_name, metric_value, threshold_value, severity)
    VALUES ('avg_response_time', response_time_avg, 100, 'high');
    
    -- Monitor error rate
    SELECT (COUNT(CASE WHEN status = 'failed' THEN 1 END) * 100.0 / COUNT(*)) INTO error_rate
    FROM event_stream
    WHERE created_at > DATE_SUB(NOW(), INTERVAL 5 MINUTE);
    
    INSERT INTO real_time_health (metric_name, metric_value, threshold_value, severity)
    VALUES ('error_rate', error_rate, 5, 'critical');
    
    -- Check for alerts
    UPDATE real_time_health 
    SET is_alerting = TRUE
    WHERE metric_value > threshold_value
    AND recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE);
END$$
DELIMITER ;
```

### The "Real-Time Alerting" Pattern
```sql
-- Real-time alerts
CREATE TABLE real_time_alerts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    current_value DECIMAL(15,2) NOT NULL,
    threshold_value DECIMAL(15,2) NOT NULL,
    severity ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    alert_message TEXT NOT NULL,
    is_resolved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    
    INDEX idx_alert_type (alert_type, is_resolved),
    INDEX idx_severity (severity, created_at)
);

-- Real-time alerting procedure
DELIMITER $$
CREATE PROCEDURE check_real_time_alerts()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE metric_name VARCHAR(100);
    DECLARE metric_value DECIMAL(15,2);
    DECLARE threshold_value DECIMAL(15,2);
    DECLARE severity VARCHAR(20);
    
    DECLARE alert_cursor CURSOR FOR
        SELECT metric_name, metric_value, threshold_value, severity
        FROM real_time_health
        WHERE is_alerting = TRUE
        AND recorded_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE);
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN alert_cursor;
    
    alert_loop: LOOP
        FETCH alert_cursor INTO metric_name, metric_value, threshold_value, severity;
        IF done THEN
            LEAVE alert_loop;
        END IF;
        
        -- Create alert if not already exists
        INSERT IGNORE INTO real_time_alerts (alert_type, metric_name, current_value, threshold_value, severity, alert_message)
        VALUES (
            'threshold_exceeded',
            metric_name,
            metric_value,
            threshold_value,
            severity,
            CONCAT('Metric ', metric_name, ' exceeded threshold: ', metric_value, ' > ', threshold_value)
        );
    END LOOP;
    
    CLOSE alert_cursor;
END$$
DELIMITER ;
```

These real-time data patterns show the techniques that product engineers use to build high-performance, real-time systems! 🚀
