# Transactional Patterns & Isolation Levels


Advanced transactional patterns, isolation level techniques, and real-world concurrency control strategies used by product engineers at Atlassian, Monday.com, Linear, and other productivity platforms.

## 🔄 Advanced Transactional Patterns

### The "Optimistic Locking with Version Control" Pattern
```sql
-- Optimistic locking for concurrent task updates
CREATE TABLE tasks_with_versioning (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    task_id VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status ENUM('todo', 'in_progress', 'done') DEFAULT 'todo',
    assignee_id BIGINT NULL,
    version INT DEFAULT 1,  -- Optimistic locking version
    last_modified_by BIGINT NOT NULL,
    last_modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_task_version (task_id, version),
    INDEX idx_status_assignee (status, assignee_id),
    INDEX idx_last_modified (last_modified_at, last_modified_by)
);

-- Optimistic update procedure
DELIMITER //
CREATE PROCEDURE update_task_optimistic(
    IN p_task_id VARCHAR(50),
    IN p_title VARCHAR(255),
    IN p_description TEXT,
    IN p_status ENUM('todo', 'in_progress', 'done'),
    IN p_assignee_id BIGINT,
    IN p_expected_version INT,
    IN p_user_id BIGINT
)
BEGIN
    DECLARE current_version INT;
    DECLARE rows_affected INT;
    
    -- Start transaction with SERIALIZABLE isolation
    START TRANSACTION;
    
    -- Get current version with lock
    SELECT version INTO current_version 
    FROM tasks_with_versioning 
    WHERE task_id = p_task_id 
    FOR UPDATE;
    
    -- Check if version matches (optimistic lock)
    IF current_version = p_expected_version THEN
        -- Update with new version
        UPDATE tasks_with_versioning 
        SET title = p_title,
            description = p_description,
            status = p_status,
            assignee_id = p_assignee_id,
            version = version + 1,
            last_modified_by = p_user_id,
            last_modified_at = CURRENT_TIMESTAMP
        WHERE task_id = p_task_id 
        AND version = p_expected_version;
        
        SET rows_affected = ROW_COUNT();
        
        IF rows_affected > 0 THEN
            COMMIT;
            SELECT 'SUCCESS' as result, current_version + 1 as new_version;
        ELSE
            ROLLBACK;
            SELECT 'CONCURRENT_MODIFICATION' as result, current_version as current_version;
        END IF;
    ELSE
        ROLLBACK;
        SELECT 'VERSION_MISMATCH' as result, current_version as current_version;
    END IF;
END //
DELIMITER ;
```

### The "Distributed Transaction with Saga Pattern" Pattern
```sql
-- Saga pattern for distributed task operations
CREATE TABLE saga_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(100) UNIQUE NOT NULL,
    saga_type ENUM('task_creation', 'task_assignment', 'task_deletion', 'bulk_operation') NOT NULL,
    saga_status ENUM('pending', 'in_progress', 'completed', 'failed', 'compensating') DEFAULT 'pending',
    saga_data JSON NOT NULL,  -- Transaction data
    current_step INT DEFAULT 0,
    total_steps INT NOT NULL,
    compensation_data JSON,  -- Compensation actions
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_saga_status (saga_status, saga_type),
    INDEX idx_saga_created (created_at, saga_status)
);

-- Saga steps tracking
CREATE TABLE saga_steps (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(100) NOT NULL,
    step_number INT NOT NULL,
    step_name VARCHAR(100) NOT NULL,
    step_type ENUM('action', 'compensation') NOT NULL,
    step_status ENUM('pending', 'executing', 'completed', 'failed', 'compensated') DEFAULT 'pending',
    step_data JSON,  -- Step-specific data
    error_message TEXT,
    executed_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    
    UNIQUE KEY uk_saga_step (saga_id, step_number),
    INDEX idx_saga_steps (saga_id, step_status),
    INDEX idx_step_status (step_status, step_type)
);

-- Saga execution procedure
DELIMITER //
CREATE PROCEDURE execute_saga_step(
    IN p_saga_id VARCHAR(100),
    IN p_step_number INT
)
BEGIN
    DECLARE step_status_val ENUM('pending', 'executing', 'completed', 'failed', 'compensated');
    DECLARE saga_status_val ENUM('pending', 'in_progress', 'completed', 'failed', 'compensating');
    DECLARE step_data JSON;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        UPDATE saga_steps SET step_status = 'failed', error_message = 'Database error' WHERE saga_id = p_saga_id AND step_number = p_step_number;
        UPDATE saga_transactions SET saga_status = 'failed' WHERE saga_id = p_saga_id;
    END;
    
    START TRANSACTION;
    
    -- Get step data
    SELECT step_status, step_data INTO step_status_val, step_data
    FROM saga_steps 
    WHERE saga_id = p_saga_id AND step_number = p_step_number
    FOR UPDATE;
    
    IF step_status_val = 'pending' THEN
        -- Mark step as executing
        UPDATE saga_steps 
        SET step_status = 'executing', executed_at = CURRENT_TIMESTAMP
        WHERE saga_id = p_saga_id AND step_number = p_step_number;
        
        -- Update saga status
        UPDATE saga_transactions 
        SET saga_status = 'in_progress', current_step = p_step_number
        WHERE saga_id = p_saga_id;
        
        COMMIT;
        
        -- Execute step logic here (application level)
        -- If successful, mark as completed
        -- If failed, trigger compensation
        
    ELSE
        ROLLBACK;
        SELECT 'STEP_ALREADY_PROCESSED' as result;
    END IF;
END //
DELIMITER ;
```

### The "Multi-Level Transaction Isolation" Pattern
```sql
-- Multi-level isolation for different operations
CREATE TABLE isolation_level_config (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    operation_type VARCHAR(100) NOT NULL,
    isolation_level ENUM('READ_UNCOMMITTED', 'READ_COMMITTED', 'REPEATABLE_READ', 'SERIALIZABLE') NOT NULL,
    timeout_seconds INT DEFAULT 30,
    retry_count INT DEFAULT 3,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_operation_isolation (operation_type),
    INDEX idx_active_config (is_active, operation_type)
);

-- Insert default configurations
INSERT INTO isolation_level_config (operation_type, isolation_level, timeout_seconds, retry_count) VALUES
('task_read', 'READ_COMMITTED', 10, 1),
('task_update', 'REPEATABLE_READ', 30, 3),
('task_delete', 'SERIALIZABLE', 60, 5),
('bulk_operation', 'SERIALIZABLE', 120, 3),
('analytics_query', 'READ_COMMITTED', 300, 1),
('report_generation', 'READ_COMMITTED', 600, 1);

-- Dynamic isolation level procedure
DELIMITER //
CREATE PROCEDURE execute_with_isolation(
    IN p_operation_type VARCHAR(100),
    IN p_sql_statement TEXT
)
BEGIN
    DECLARE isolation_level_val ENUM('READ_UNCOMMITTED', 'READ_COMMITTED', 'REPEATABLE_READ', 'SERIALIZABLE');
    DECLARE timeout_val INT;
    DECLARE retry_count_val INT;
    DECLARE current_retry INT DEFAULT 0;
    DECLARE success BOOLEAN DEFAULT FALSE;
    
    -- Get isolation configuration
    SELECT isolation_level, timeout_seconds, retry_count 
    INTO isolation_level_val, timeout_val, retry_count_val
    FROM isolation_level_config 
    WHERE operation_type = p_operation_type AND is_active = TRUE;
    
    -- Set session variables
    SET SESSION innodb_lock_wait_timeout = timeout_val;
    SET SESSION transaction_isolation = isolation_level_val;
    
    -- Retry loop
    WHILE current_retry < retry_count_val AND NOT success DO
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                SET current_retry = current_retry + 1;
                IF current_retry >= retry_count_val THEN
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Max retries exceeded';
                END IF;
            END;
            
            START TRANSACTION;
            -- Execute the dynamic SQL (application level)
            SET success = TRUE;
            COMMIT;
        END;
    END WHILE;
END //
DELIMITER ;
```

## 🔒 Advanced Concurrency Control

### The "Row-Level Locking with Deadlock Prevention" Pattern
```sql
-- Row-level locking for concurrent task operations
CREATE TABLE task_locks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    task_id BIGINT NOT NULL,
    lock_type ENUM('read', 'write', 'exclusive') NOT NULL,
    lock_owner VARCHAR(100) NOT NULL,  -- Session ID or user ID
    lock_acquired_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    lock_expires_at TIMESTAMP NOT NULL,
    lock_context JSON,  -- Additional context
    
    UNIQUE KEY uk_task_lock (task_id, lock_type),
    INDEX idx_lock_expiry (lock_expires_at),
    INDEX idx_lock_owner (lock_owner, lock_type)
);

-- Deadlock prevention procedure
DELIMITER //
CREATE PROCEDURE acquire_task_lock(
    IN p_task_id BIGINT,
    IN p_lock_type ENUM('read', 'write', 'exclusive'),
    IN p_lock_owner VARCHAR(100),
    IN p_timeout_seconds INT DEFAULT 30
)
BEGIN
    DECLARE lock_exists BOOLEAN DEFAULT FALSE;
    DECLARE lock_expires TIMESTAMP;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'LOCK_ACQUISITION_FAILED' as result;
    END;
    
    START TRANSACTION;
    
    -- Check for existing locks with deadlock prevention
    SELECT EXISTS(
        SELECT 1 FROM task_locks 
        WHERE task_id = p_task_id 
        AND lock_expires_at > CURRENT_TIMESTAMP
        AND (
            (p_lock_type = 'read' AND lock_type IN ('write', 'exclusive')) OR
            (p_lock_type = 'write' AND lock_type IN ('read', 'write', 'exclusive')) OR
            (p_lock_type = 'exclusive' AND lock_type IN ('read', 'write', 'exclusive'))
        )
    ) INTO lock_exists;
    
    IF NOT lock_exists THEN
        -- Clean expired locks
        DELETE FROM task_locks 
        WHERE task_id = p_task_id 
        AND lock_expires_at <= CURRENT_TIMESTAMP;
        
        -- Acquire new lock
        INSERT INTO task_locks (task_id, lock_type, lock_owner, lock_expires_at)
        VALUES (p_task_id, p_lock_type, p_lock_owner, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL p_timeout_seconds SECOND));
        
        COMMIT;
        SELECT 'LOCK_ACQUIRED' as result;
    ELSE
        ROLLBACK;
        SELECT 'LOCK_CONFLICT' as result;
    END IF;
END //
DELIMITER ;
```

### The "Optimistic Concurrency Control with Conflict Resolution" Pattern
```sql
-- Optimistic concurrency control for collaborative editing
CREATE TABLE collaborative_documents (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_id VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    content LONGTEXT,
    version INT DEFAULT 1,
    last_modified_by BIGINT NOT NULL,
    last_modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    conflict_resolution_strategy ENUM('last_write_wins', 'manual_resolution', 'merge_strategy') DEFAULT 'last_write_wins',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_document_version (document_id, version),
    INDEX idx_last_modified (last_modified_at, last_modified_by)
);

-- Conflict resolution table
CREATE TABLE document_conflicts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_id VARCHAR(50) NOT NULL,
    conflict_id VARCHAR(100) UNIQUE NOT NULL,
    base_version INT NOT NULL,
    conflicting_version INT NOT NULL,
    conflict_type ENUM('content_conflict', 'metadata_conflict', 'permission_conflict') NOT NULL,
    conflict_data JSON NOT NULL,  -- Details of the conflict
    resolution_status ENUM('pending', 'resolved', 'ignored') DEFAULT 'pending',
    resolved_by BIGINT NULL,
    resolved_at TIMESTAMP NULL,
    resolution_data JSON,  -- How the conflict was resolved
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_document_conflicts (document_id, resolution_status),
    INDEX idx_conflict_type (conflict_type, resolution_status)
);

-- Conflict detection and resolution procedure
DELIMITER //
CREATE PROCEDURE update_document_with_conflict_detection(
    IN p_document_id VARCHAR(50),
    IN p_content LONGTEXT,
    IN p_expected_version INT,
    IN p_user_id BIGINT
)
BEGIN
    DECLARE current_version INT;
    DECLARE conflict_exists BOOLEAN DEFAULT FALSE;
    DECLARE conflict_id_val VARCHAR(100);
    
    START TRANSACTION;
    
    -- Get current version
    SELECT version INTO current_version 
    FROM collaborative_documents 
    WHERE document_id = p_document_id 
    FOR UPDATE;
    
    IF current_version = p_expected_version THEN
        -- No conflict, update normally
        UPDATE collaborative_documents 
        SET content = p_content,
            version = version + 1,
            last_modified_by = p_user_id,
            last_modified_at = CURRENT_TIMESTAMP
        WHERE document_id = p_document_id;
        
        COMMIT;
        SELECT 'UPDATE_SUCCESS' as result, current_version + 1 as new_version;
    ELSE
        -- Conflict detected
        SET conflict_id_val = CONCAT(p_document_id, '_', UNIX_TIMESTAMP(), '_', p_user_id);
        
        INSERT INTO document_conflicts (
            document_id, conflict_id, base_version, conflicting_version, 
            conflict_type, conflict_data
        ) VALUES (
            p_document_id, conflict_id_val, current_version, p_expected_version,
            'content_conflict', JSON_OBJECT(
                'expected_content', p_content,
                'current_content', (SELECT content FROM collaborative_documents WHERE document_id = p_document_id),
                'user_id', p_user_id
            )
        );
        
        COMMIT;
        SELECT 'CONFLICT_DETECTED' as result, conflict_id_val as conflict_id, current_version as current_version;
    END IF;
END //
DELIMITER ;
```

## 🔄 Advanced Transaction Patterns

### The "Two-Phase Commit with Compensation" Pattern
```sql
-- Two-phase commit for distributed operations
CREATE TABLE two_phase_commit (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE NOT NULL,
    coordinator_id VARCHAR(100) NOT NULL,
    transaction_status ENUM('preparing', 'prepared', 'committing', 'committed', 'aborting', 'aborted') DEFAULT 'preparing',
    participants JSON NOT NULL,  -- List of participant services
    prepare_timeout INT DEFAULT 30,
    commit_timeout INT DEFAULT 30,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_transaction_status (transaction_status, coordinator_id),
    INDEX idx_created_at (created_at, transaction_status)
);

-- Participant status tracking
CREATE TABLE transaction_participants (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) NOT NULL,
    participant_id VARCHAR(100) NOT NULL,
    participant_status ENUM('preparing', 'prepared', 'committed', 'aborted', 'failed') DEFAULT 'preparing',
    prepare_response JSON,  -- Response from prepare phase
    commit_response JSON,   -- Response from commit phase
    compensation_data JSON, -- Data needed for compensation
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_transaction_participant (transaction_id, participant_id),
    INDEX idx_participant_status (participant_status, participant_id)
);

-- Two-phase commit coordinator procedure
DELIMITER //
CREATE PROCEDURE execute_two_phase_commit(
    IN p_transaction_id VARCHAR(100),
    IN p_coordinator_id VARCHAR(100),
    IN p_participants JSON
)
BEGIN
    DECLARE all_prepared BOOLEAN DEFAULT TRUE;
    DECLARE participant_count INT DEFAULT 0;
    DECLARE prepared_count INT DEFAULT 0;
    
    START TRANSACTION;
    
    -- Initialize transaction
    INSERT INTO two_phase_commit (transaction_id, coordinator_id, participants)
    VALUES (p_transaction_id, p_coordinator_id, p_participants);
    
    -- Initialize participants
    INSERT INTO transaction_participants (transaction_id, participant_id)
    SELECT p_transaction_id, JSON_UNQUOTE(JSON_EXTRACT(participant, '$'))
    FROM JSON_TABLE(p_participants, '$[*]' COLUMNS (participant VARCHAR(100) PATH '$')) AS participants;
    
    -- Update status to preparing
    UPDATE two_phase_commit 
    SET transaction_status = 'preparing' 
    WHERE transaction_id = p_transaction_id;
    
    COMMIT;
    
    -- Phase 1: Prepare (application level)
    -- Send prepare messages to all participants
    -- Wait for responses
    
    -- Phase 2: Commit or Abort (application level)
    -- If all prepared, send commit messages
    -- If any failed, send abort messages
    
    -- This is a simplified version - actual implementation would involve
    -- application-level coordination with external services
END //
DELIMITER ;
```

### The "Event Sourcing with Transactional Events" Pattern
```sql
-- Event sourcing with transactional guarantees
CREATE TABLE event_store (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id VARCHAR(100) UNIQUE NOT NULL,
    aggregate_id VARCHAR(100) NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_version INT NOT NULL,
    event_data JSON NOT NULL,
    event_metadata JSON,  -- Additional metadata
    transaction_id VARCHAR(100) NULL,  -- For transaction correlation
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_aggregate_events (aggregate_id, aggregate_type, event_version),
    INDEX idx_event_type (event_type, occurred_at),
    INDEX idx_transaction_events (transaction_id, occurred_at)
);

-- Event processing status
CREATE TABLE event_processing_status (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id VARCHAR(100) NOT NULL,
    processor_id VARCHAR(100) NOT NULL,
    processing_status ENUM('pending', 'processing', 'completed', 'failed', 'retry') DEFAULT 'pending',
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    error_message TEXT,
    processed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_event_processor (event_id, processor_id),
    INDEX idx_processing_status (processing_status, processor_id),
    INDEX idx_retry_events (retry_count, max_retries, processing_status)
);

-- Transactional event publishing procedure
DELIMITER //
CREATE PROCEDURE publish_event_transactional(
    IN p_event_id VARCHAR(100),
    IN p_aggregate_id VARCHAR(100),
    IN p_aggregate_type VARCHAR(50),
    IN p_event_type VARCHAR(100),
    IN p_event_version INT,
    IN p_event_data JSON,
    IN p_transaction_id VARCHAR(100),
    IN p_processors JSON  -- List of processors to notify
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Event publishing failed';
    END;
    
    START TRANSACTION;
    
    -- Insert event into event store
    INSERT INTO event_store (
        event_id, aggregate_id, aggregate_type, event_type, 
        event_version, event_data, transaction_id
    ) VALUES (
        p_event_id, p_aggregate_id, p_aggregate_type, p_event_type,
        p_event_version, p_event_data, p_transaction_id
    );
    
    -- Initialize processing status for all processors
    INSERT INTO event_processing_status (event_id, processor_id)
    SELECT p_event_id, JSON_UNQUOTE(JSON_EXTRACT(processor, '$'))
    FROM JSON_TABLE(p_processors, '$[*]' COLUMNS (processor VARCHAR(100) PATH '$')) AS processors;
    
    COMMIT;
    
    SELECT 'EVENT_PUBLISHED' as result, p_event_id as event_id;
END //
DELIMITER ;
```

## 🔧 Advanced Isolation Level Techniques

### The "Dynamic Isolation Level Switching" Pattern
```sql
-- Dynamic isolation level management
CREATE TABLE isolation_level_rules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    operation_type ENUM('SELECT', 'INSERT', 'UPDATE', 'DELETE') NOT NULL,
    isolation_level ENUM('READ_UNCOMMITTED', 'READ_COMMITTED', 'REPEATABLE_READ', 'SERIALIZABLE') NOT NULL,
    conditions JSON,  -- When to apply this rule
    priority INT DEFAULT 0,  -- Higher priority rules apply first
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_table_operation (table_name, operation_type, priority),
    INDEX idx_active_rules (is_active, priority)
);

-- Insert isolation rules
INSERT INTO isolation_level_rules (rule_name, table_name, operation_type, isolation_level, conditions, priority) VALUES
('high_priority_updates', 'tasks', 'UPDATE', 'SERIALIZABLE', '{"priority": "high", "status": "in_progress"}', 10),
('bulk_operations', 'tasks', 'UPDATE', 'SERIALIZABLE', '{"bulk_operation": true}', 9),
('read_analytics', 'tasks', 'SELECT', 'READ_COMMITTED', '{"analytics_query": true}', 5),
('normal_reads', 'tasks', 'SELECT', 'READ_COMMITTED', '{}', 1);

-- Dynamic isolation level procedure
DELIMITER //
CREATE PROCEDURE execute_with_dynamic_isolation(
    IN p_table_name VARCHAR(100),
    IN p_operation_type ENUM('SELECT', 'INSERT', 'UPDATE', 'DELETE'),
    IN p_context JSON,  -- Context for rule matching
    IN p_sql_statement TEXT
)
BEGIN
    DECLARE isolation_level_val ENUM('READ_UNCOMMITTED', 'READ_COMMITTED', 'REPEATABLE_READ', 'SERIALIZABLE');
    DECLARE rule_found BOOLEAN DEFAULT FALSE;
    
    -- Find applicable isolation rule
    SELECT isolation_level INTO isolation_level_val
    FROM isolation_level_rules 
    WHERE table_name = p_table_name 
    AND operation_type = p_operation_type 
    AND is_active = TRUE
    AND JSON_CONTAINS(p_context, conditions)
    ORDER BY priority DESC
    LIMIT 1;
    
    IF isolation_level_val IS NOT NULL THEN
        SET rule_found = TRUE;
    ELSE
        -- Default isolation level
        SET isolation_level_val = 'READ_COMMITTED';
    END IF;
    
    -- Set session isolation level
    SET SESSION transaction_isolation = isolation_level_val;
    
    -- Execute the statement (application level)
    -- The actual SQL execution would happen at application level
    
    SELECT 'EXECUTED' as result, isolation_level_val as isolation_level, rule_found as rule_applied;
END //
DELIMITER ;
```

### The "Deadlock Detection and Resolution" Pattern
```sql
-- Deadlock detection and resolution
CREATE TABLE deadlock_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    deadlock_id VARCHAR(100) UNIQUE NOT NULL,
    deadlock_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deadlock_details JSON NOT NULL,  -- Detailed deadlock information
    resolution_action ENUM('victim_killed', 'timeout', 'manual_resolution') NOT NULL,
    victim_transaction_id VARCHAR(100),
    resolution_time_ms INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_deadlock_timestamp (deadlock_timestamp),
    INDEX idx_resolution_action (resolution_action, deadlock_timestamp)
);

-- Deadlock prevention rules
CREATE TABLE deadlock_prevention_rules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,  -- 'table', 'row', 'index'
    resource_name VARCHAR(100) NOT NULL,
    access_order JSON NOT NULL,  -- Required access order
    timeout_seconds INT DEFAULT 30,
    retry_count INT DEFAULT 3,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_resource_rules (resource_type, resource_name, is_active)
);

-- Deadlock detection procedure
DELIMITER //
CREATE PROCEDURE detect_and_resolve_deadlocks()
BEGIN
    DECLARE deadlock_count INT DEFAULT 0;
    
    -- Check for deadlocks in information_schema
    SELECT COUNT(*) INTO deadlock_count
    FROM information_schema.INNODB_TRX t1
    JOIN information_schema.INNODB_TRX t2 
    ON t1.trx_id != t2.trx_id
    WHERE t1.trx_state = 'LOCK WAIT' 
    AND t2.trx_state = 'LOCK WAIT';
    
    IF deadlock_count > 0 THEN
        -- Log deadlock detection
        INSERT INTO deadlock_logs (deadlock_id, deadlock_details, resolution_action)
        VALUES (
            CONCAT('DEADLOCK_', UNIX_TIMESTAMP()),
            JSON_OBJECT(
                'detected_at', CURRENT_TIMESTAMP,
                'deadlock_count', deadlock_count,
                'active_transactions', (
                    SELECT JSON_ARRAYAGG(trx_id) 
                    FROM information_schema.INNODB_TRX 
                    WHERE trx_state = 'LOCK WAIT'
                )
            ),
            'victim_killed'
        );
        
        -- Kill the oldest transaction (victim selection)
        -- This would be implemented at application level
        SELECT 'DEADLOCK_DETECTED' as result, deadlock_count as count;
    ELSE
        SELECT 'NO_DEADLOCKS' as result;
    END IF;
END //
DELIMITER ;
```

These transactional patterns show the real-world techniques that productivity platform engineers use to handle complex concurrency scenarios, distributed transactions, and advanced isolation level management! 🚀
