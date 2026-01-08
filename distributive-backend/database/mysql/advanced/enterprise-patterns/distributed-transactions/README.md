# Distributed Transaction Patterns

Advanced distributed transaction patterns used by companies like PayPal, Stripe, and financial institutions to handle complex multi-service transactions.

## Saga Pattern Implementation

### Saga Orchestration
```sql
-- Saga definition table
CREATE TABLE saga_definitions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_name VARCHAR(100) NOT NULL,
    version INT DEFAULT 1,
    steps JSON NOT NULL, -- Array of step definitions
    compensation_strategy ENUM('backward', 'forward') DEFAULT 'backward',
    timeout_seconds INT DEFAULT 300,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_saga_version (saga_name, version)
);

-- Saga instance tracking
CREATE TABLE saga_instances (
    saga_id VARCHAR(36) PRIMARY KEY,
    saga_name VARCHAR(100) NOT NULL,
    saga_version INT NOT NULL,
    status ENUM('started', 'in_progress', 'completed', 'failed', 'compensated') DEFAULT 'started',
    current_step INT DEFAULT 0,
    saga_data JSON NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_status (status),
    INDEX idx_saga_name (saga_name)
);

-- Saga step execution tracking
CREATE TABLE saga_steps (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(36) NOT NULL,
    step_number INT NOT NULL,
    step_name VARCHAR(100) NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    status ENUM('pending', 'in_progress', 'completed', 'failed', 'compensated') DEFAULT 'pending',
    request_data JSON,
    response_data JSON,
    error_message TEXT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_saga_step (saga_id, step_number),
    INDEX idx_status (status)
);
```

### Saga Execution Engine
```sql
-- Saga execution procedure
DELIMITER $$
CREATE PROCEDURE execute_saga(
    IN saga_id VARCHAR(36)
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_step INT;
    DECLARE total_steps INT;
    DECLARE saga_status VARCHAR(20);
    DECLARE step_name VARCHAR(100);
    DECLARE service_name VARCHAR(100);
    DECLARE step_data JSON;
    
    -- Get saga details
    SELECT si.current_step, si.status, sd.steps
    INTO current_step, saga_status, step_data
    FROM saga_instances si
    JOIN saga_definitions sd ON si.saga_name = sd.saga_name AND si.saga_version = sd.version
    WHERE si.saga_id = saga_id;
    
    -- Get total steps
    SET total_steps = JSON_LENGTH(step_data);
    
    -- Execute steps
    WHILE current_step < total_steps AND saga_status = 'in_progress' DO
        -- Get step details
        SET step_name = JSON_UNQUOTE(JSON_EXTRACT(step_data, CONCAT('$[', current_step, '].name')));
        SET service_name = JSON_UNQUOTE(JSON_EXTRACT(step_data, CONCAT('$[', current_step, '].service')));
        
        -- Execute step
        CALL execute_saga_step(saga_id, current_step, step_name, service_name);
        
        -- Check step result
        SELECT status INTO saga_status
        FROM saga_steps
        WHERE saga_id = saga_id AND step_number = current_step;
        
        IF saga_status = 'failed' THEN
            -- Trigger compensation
            CALL compensate_saga(saga_id, current_step);
            SET saga_status = 'failed';
        ELSE
            SET current_step = current_step + 1;
            -- Update saga progress
            UPDATE saga_instances 
            SET current_step = current_step
            WHERE saga_id = saga_id;
        END IF;
    END WHILE;
    
    -- Update final status
    IF saga_status = 'in_progress' THEN
        UPDATE saga_instances 
        SET status = 'completed', completed_at = NOW()
        WHERE saga_id = saga_id;
    END IF;
END$$
DELIMITER ;
```

## Two-Phase Commit (2PC) Implementation

### Transaction Coordinator
```sql
-- 2PC transaction coordinator
CREATE TABLE distributed_transactions (
    transaction_id VARCHAR(36) PRIMARY KEY,
    status ENUM('preparing', 'prepared', 'committed', 'aborted') DEFAULT 'preparing',
    participants JSON NOT NULL, -- Array of participant services
    timeout_seconds INT DEFAULT 30,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    prepared_at TIMESTAMP NULL,
    committed_at TIMESTAMP NULL,
    INDEX idx_status (status)
);

-- Participant status tracking
CREATE TABLE transaction_participants (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(36) NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    service_url VARCHAR(500) NOT NULL,
    status ENUM('preparing', 'prepared', 'committed', 'aborted') DEFAULT 'preparing',
    prepared_at TIMESTAMP NULL,
    committed_at TIMESTAMP NULL,
    INDEX idx_transaction (transaction_id),
    INDEX idx_status (status)
);
```

### 2PC Execution
```sql
-- 2PC prepare phase
DELIMITER $$
CREATE PROCEDURE prepare_transaction(
    IN transaction_id VARCHAR(36)
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE service_name VARCHAR(100);
    DECLARE service_url VARCHAR(500);
    DECLARE participant_id BIGINT;
    
    DECLARE participant_cursor CURSOR FOR
        SELECT id, service_name, service_url
        FROM transaction_participants
        WHERE transaction_id = transaction_id;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- Update transaction status
    UPDATE distributed_transactions 
    SET status = 'preparing'
    WHERE transaction_id = transaction_id;
    
    OPEN participant_cursor;
    
    prepare_loop: LOOP
        FETCH participant_cursor INTO participant_id, service_name, service_url;
        IF done THEN
            LEAVE prepare_loop;
        END IF;
        
        -- Send prepare request to participant
        -- This would typically be done via HTTP/RPC call
        -- For demo, we'll simulate success
        UPDATE transaction_participants 
        SET status = 'prepared', prepared_at = NOW()
        WHERE id = participant_id;
    END LOOP;
    
    CLOSE participant_cursor;
    
    -- Check if all participants prepared successfully
    IF NOT EXISTS (
        SELECT 1 FROM transaction_participants 
        WHERE transaction_id = transaction_id 
        AND status != 'prepared'
    ) THEN
        UPDATE distributed_transactions 
        SET status = 'prepared', prepared_at = NOW()
        WHERE transaction_id = transaction_id;
    ELSE
        -- Abort transaction
        CALL abort_transaction(transaction_id);
    END IF;
END$$
DELIMITER ;
```

## Outbox Pattern Implementation

### Outbox Table Structure
```sql
-- Outbox table for reliable message publishing
CREATE TABLE outbox (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    aggregate_id VARCHAR(36) NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSON NOT NULL,
    status ENUM('pending', 'published', 'failed') DEFAULT 'pending',
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    next_retry_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP NULL,
    INDEX idx_status (status),
    INDEX idx_next_retry (next_retry_at),
    INDEX idx_aggregate (aggregate_id, aggregate_type)
);

-- Outbox processing procedure
DELIMITER $$
CREATE PROCEDURE process_outbox()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE outbox_id BIGINT;
    DECLARE event_type VARCHAR(100);
    DECLARE event_data JSON;
    DECLARE retry_count INT;
    DECLARE max_retries INT;
    
    DECLARE outbox_cursor CURSOR FOR
        SELECT id, event_type, event_data, retry_count, max_retries
        FROM outbox
        WHERE status = 'pending'
        AND (next_retry_at IS NULL OR next_retry_at <= NOW())
        ORDER BY created_at ASC
        LIMIT 100;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN outbox_cursor;
    
    process_loop: LOOP
        FETCH outbox_cursor INTO outbox_id, event_type, event_data, retry_count, max_retries;
        IF done THEN
            LEAVE process_loop;
        END IF;
        
        -- Attempt to publish event
        -- This would typically be done via message broker (Kafka, RabbitMQ, etc.)
        -- For demo, we'll simulate success/failure
        
        IF RAND() > 0.1 THEN -- 90% success rate
            -- Success
            UPDATE outbox 
            SET status = 'published', published_at = NOW()
            WHERE id = outbox_id;
        ELSE
            -- Failure
            SET retry_count = retry_count + 1;
            
            IF retry_count >= max_retries THEN
                UPDATE outbox 
                SET status = 'failed'
                WHERE id = outbox_id;
            ELSE
                UPDATE outbox 
                SET retry_count = retry_count,
                    next_retry_at = DATE_ADD(NOW(), INTERVAL POWER(2, retry_count) MINUTE)
                WHERE id = outbox_id;
            END IF;
        END IF;
    END LOOP;
    
    CLOSE outbox_cursor;
END$$
DELIMITER ;
```

## Inbox Pattern Implementation

### Inbox Table Structure
```sql
-- Inbox table for idempotent message processing
CREATE TABLE inbox (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    message_id VARCHAR(36) NOT NULL,
    aggregate_id VARCHAR(36) NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSON NOT NULL,
    status ENUM('pending', 'processed', 'failed') DEFAULT 'pending',
    processed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_message (message_id),
    INDEX idx_status (status),
    INDEX idx_aggregate (aggregate_id, aggregate_type)
);

-- Idempotent message processing
DELIMITER $$
CREATE PROCEDURE process_inbox_message(
    IN message_id VARCHAR(36),
    IN aggregate_id VARCHAR(36),
    IN aggregate_type VARCHAR(50),
    IN event_type VARCHAR(100),
    IN event_data JSON
)
BEGIN
    DECLARE existing_status VARCHAR(20);
    
    -- Check if message already processed
    SELECT status INTO existing_status
    FROM inbox
    WHERE message_id = message_id;
    
    IF existing_status IS NULL THEN
        -- New message - insert and process
        INSERT INTO inbox (message_id, aggregate_id, aggregate_type, event_type, event_data)
        VALUES (message_id, aggregate_id, aggregate_type, event_type, event_data);
        
        -- Process the message
        CALL handle_event(aggregate_id, aggregate_type, event_type, event_data);
        
        -- Mark as processed
        UPDATE inbox 
        SET status = 'processed', processed_at = NOW()
        WHERE message_id = message_id;
        
    ELSEIF existing_status = 'pending' THEN
        -- Message exists but not processed - process it
        CALL handle_event(aggregate_id, aggregate_type, event_type, event_data);
        
        UPDATE inbox 
        SET status = 'processed', processed_at = NOW()
        WHERE message_id = message_id;
        
    ELSE
        -- Message already processed - skip (idempotency)
        SELECT 'Message already processed' as result;
    END IF;
END$$
DELIMITER ;
```

## Compensation Strategies

### Backward Recovery
```sql
-- Compensation actions table
CREATE TABLE compensation_actions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(36) NOT NULL,
    step_number INT NOT NULL,
    action_type VARCHAR(100) NOT NULL,
    action_data JSON NOT NULL,
    status ENUM('pending', 'executed', 'failed') DEFAULT 'pending',
    executed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_saga_step (saga_id, step_number),
    INDEX idx_status (status)
);

-- Compensation execution
DELIMITER $$
CREATE PROCEDURE compensate_saga(
    IN saga_id VARCHAR(36),
    IN failed_step INT
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE step_number INT;
    DECLARE action_type VARCHAR(100);
    DECLARE action_data JSON;
    
    DECLARE compensation_cursor CURSOR FOR
        SELECT step_number, action_type, action_data
        FROM compensation_actions
        WHERE saga_id = saga_id
        AND step_number <= failed_step
        AND status = 'pending'
        ORDER BY step_number DESC;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN compensation_cursor;
    
    compensate_loop: LOOP
        FETCH compensation_cursor INTO step_number, action_type, action_data;
        IF done THEN
            LEAVE compensate_loop;
        END IF;
        
        -- Execute compensation action
        CALL execute_compensation_action(saga_id, step_number, action_type, action_data);
        
        -- Mark as executed
        UPDATE compensation_actions 
        SET status = 'executed', executed_at = NOW()
        WHERE saga_id = saga_id AND step_number = step_number;
    END LOOP;
    
    CLOSE compensation_cursor;
    
    -- Update saga status
    UPDATE saga_instances 
    SET status = 'compensated', completed_at = NOW()
    WHERE saga_id = saga_id;
END$$
DELIMITER ;
```

## Monitoring & Observability

### Transaction Monitoring
```sql
-- Transaction metrics
CREATE TABLE transaction_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    duration_ms INT NOT NULL,
    participant_count INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_type_status (transaction_type, status),
    INDEX idx_created (created_at)
);

-- Performance monitoring view
CREATE VIEW transaction_performance AS
SELECT 
    transaction_type,
    status,
    COUNT(*) as count,
    AVG(duration_ms) as avg_duration,
    MAX(duration_ms) as max_duration,
    MIN(duration_ms) as min_duration,
    STDDEV(duration_ms) as std_duration
FROM transaction_metrics
WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY transaction_type, status;

-- Failure rate monitoring
CREATE VIEW transaction_failure_rates AS
SELECT 
    transaction_type,
    DATE(created_at) as date,
    COUNT(*) as total_transactions,
    COUNT(CASE WHEN status IN ('failed', 'aborted', 'compensated') THEN 1 END) as failed_transactions,
    (COUNT(CASE WHEN status IN ('failed', 'aborted', 'compensated') THEN 1 END) * 100.0 / COUNT(*)) as failure_rate
FROM transaction_metrics
WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY transaction_type, DATE(created_at)
ORDER BY date DESC, failure_rate DESC;
```
