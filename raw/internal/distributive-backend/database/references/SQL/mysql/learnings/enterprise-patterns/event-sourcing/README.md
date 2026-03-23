# Event Sourcing & CQRS Patterns

Advanced event sourcing and Command Query Responsibility Segregation patterns used by companies like Netflix, Uber, and financial institutions.

## Event Store Implementation

### Event Table Structure
```sql
-- Event store table
CREATE TABLE events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    aggregate_id VARCHAR(36) NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_version INT NOT NULL,
    event_data JSON NOT NULL,
    metadata JSON,
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_aggregate (aggregate_id, aggregate_type),
    INDEX idx_event_type (event_type),
    INDEX idx_occurred (occurred_at)
);

-- Event snapshots for performance
CREATE TABLE event_snapshots (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    aggregate_id VARCHAR(36) NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    snapshot_data JSON NOT NULL,
    snapshot_version INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_aggregate_version (aggregate_id, aggregate_type, snapshot_version),
    INDEX idx_aggregate (aggregate_id, aggregate_type)
);
```

### Event Publishing
```sql
-- Event publishing procedure
DELIMITER $$
CREATE PROCEDURE publish_event(
    IN aggregate_id VARCHAR(36),
    IN aggregate_type VARCHAR(50),
    IN event_type VARCHAR(100),
    IN event_data JSON,
    IN metadata JSON
)
BEGIN
    DECLARE next_version INT;
    
    -- Get next version for aggregate
    SELECT COALESCE(MAX(event_version), 0) + 1 INTO next_version
    FROM events 
    WHERE aggregate_id = aggregate_id 
    AND aggregate_type = aggregate_type;
    
    -- Insert event
    INSERT INTO events (
        aggregate_id, 
        aggregate_type, 
        event_type, 
        event_version, 
        event_data, 
        metadata
    ) VALUES (
        aggregate_id,
        aggregate_type,
        event_type,
        next_version,
        event_data,
        metadata
    );
    
    -- Create snapshot every 100 events
    IF next_version % 100 = 0 THEN
        CALL create_snapshot(aggregate_id, aggregate_type, next_version);
    END IF;
END$$
DELIMITER ;
```

## CQRS Implementation

### Command Side (Write Model)
```sql
-- Command handlers table
CREATE TABLE command_handlers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    command_id VARCHAR(36) NOT NULL,
    command_type VARCHAR(100) NOT NULL,
    aggregate_id VARCHAR(36) NOT NULL,
    command_data JSON NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL,
    INDEX idx_status (status),
    INDEX idx_command_type (command_type),
    INDEX idx_aggregate (aggregate_id)
);

-- Command processing procedure
DELIMITER $$
CREATE PROCEDURE process_command(
    IN command_id VARCHAR(36)
)
BEGIN
    DECLARE command_type VARCHAR(100);
    DECLARE aggregate_id VARCHAR(36);
    DECLARE command_data JSON;
    
    -- Get command details
    SELECT ch.command_type, ch.aggregate_id, ch.command_data
    INTO command_type, aggregate_id, command_data
    FROM command_handlers ch
    WHERE ch.command_id = command_id
    AND ch.status = 'pending';
    
    -- Update status to processing
    UPDATE command_handlers 
    SET status = 'processing'
    WHERE command_id = command_id;
    
    -- Process based on command type
    CASE command_type
        WHEN 'CreateUser' THEN
            CALL handle_create_user(aggregate_id, command_data);
        WHEN 'UpdateUser' THEN
            CALL handle_update_user(aggregate_id, command_data);
        WHEN 'DeleteUser' THEN
            CALL handle_delete_user(aggregate_id, command_data);
        ELSE
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Unknown command type';
    END CASE;
    
    -- Mark as completed
    UPDATE command_handlers 
    SET status = 'completed', processed_at = NOW()
    WHERE command_id = command_id;
END$$
DELIMITER ;
```

### Query Side (Read Model)
```sql
-- Read model tables (denormalized for queries)
CREATE TABLE user_read_model (
    id VARCHAR(36) PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    status ENUM('active', 'inactive', 'deleted') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_status (status)
);

CREATE TABLE user_profile_read_model (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    bio TEXT,
    avatar_url VARCHAR(500),
    preferences JSON,
    last_login TIMESTAMP NULL,
    INDEX idx_user (user_id)
);

-- Query optimization views
CREATE VIEW active_users_summary AS
SELECT 
    COUNT(*) as total_active_users,
    COUNT(CASE WHEN last_login > DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 1 END) as recently_active,
    COUNT(CASE WHEN last_login > DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 END) as monthly_active
FROM user_read_model urm
LEFT JOIN user_profile_read_model uprm ON urm.id = uprm.user_id
WHERE urm.status = 'active';
```

## Event Replay & Projection Building

### Projection Rebuilder
```sql
DELIMITER $$
CREATE PROCEDURE rebuild_user_projection(
    IN from_event_id BIGINT DEFAULT 0
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE event_id BIGINT;
    DECLARE aggregate_id VARCHAR(36);
    DECLARE event_type VARCHAR(100);
    DECLARE event_data JSON;
    
    DECLARE event_cursor CURSOR FOR
        SELECT id, aggregate_id, event_type, event_data
        FROM events 
        WHERE id > from_event_id
        AND aggregate_type = 'User'
        ORDER BY id ASC;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- Clear existing projection
    TRUNCATE TABLE user_read_model;
    TRUNCATE TABLE user_profile_read_model;
    
    OPEN event_cursor;
    
    read_loop: LOOP
        FETCH event_cursor INTO event_id, aggregate_id, event_type, event_data;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Apply event to projection
        CASE event_type
            WHEN 'UserCreated' THEN
                INSERT INTO user_read_model (id, email, name, status)
                VALUES (
                    aggregate_id,
                    JSON_UNQUOTE(JSON_EXTRACT(event_data, '$.email')),
                    JSON_UNQUOTE(JSON_EXTRACT(event_data, '$.name')),
                    'active'
                );
                
            WHEN 'UserUpdated' THEN
                UPDATE user_read_model 
                SET 
                    email = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(event_data, '$.email')), email),
                    name = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(event_data, '$.name')), name),
                    updated_at = NOW()
                WHERE id = aggregate_id;
                
            WHEN 'UserDeleted' THEN
                UPDATE user_read_model 
                SET status = 'deleted', updated_at = NOW()
                WHERE id = aggregate_id;
                
            WHEN 'ProfileUpdated' THEN
                INSERT INTO user_profile_read_model (id, user_id, bio, avatar_url, preferences)
                VALUES (
                    UUID(),
                    aggregate_id,
                    JSON_UNQUOTE(JSON_EXTRACT(event_data, '$.bio')),
                    JSON_UNQUOTE(JSON_EXTRACT(event_data, '$.avatar_url')),
                    JSON_EXTRACT(event_data, '$.preferences')
                )
                ON DUPLICATE KEY UPDATE
                    bio = VALUES(bio),
                    avatar_url = VALUES(avatar_url),
                    preferences = VALUES(preferences);
        END CASE;
    END LOOP;
    
    CLOSE event_cursor;
END$$
DELIMITER ;
```

## Snapshot Management

### Snapshot Creation
```sql
DELIMITER $$
CREATE PROCEDURE create_snapshot(
    IN aggregate_id VARCHAR(36),
    IN aggregate_type VARCHAR(50),
    IN version INT
)
BEGIN
    DECLARE snapshot_data JSON;
    
    -- Build snapshot from current state
    CASE aggregate_type
        WHEN 'User' THEN
            SELECT JSON_OBJECT(
                'id', urm.id,
                'email', urm.email,
                'name', urm.name,
                'status', urm.status,
                'profile', (
                    SELECT JSON_OBJECT(
                        'bio', uprm.bio,
                        'avatar_url', uprm.avatar_url,
                        'preferences', uprm.preferences
                    )
                    FROM user_profile_read_model uprm
                    WHERE uprm.user_id = urm.id
                )
            ) INTO snapshot_data
            FROM user_read_model urm
            WHERE urm.id = aggregate_id;
            
        ELSE
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Unknown aggregate type for snapshot';
    END CASE;
    
    -- Insert snapshot
    INSERT INTO event_snapshots (aggregate_id, aggregate_type, snapshot_version, snapshot_data)
    VALUES (aggregate_id, aggregate_type, version, snapshot_data)
    ON DUPLICATE KEY UPDATE
        snapshot_data = VALUES(snapshot_data);
END$$
DELIMITER ;
```

## Event Versioning & Migration

### Event Schema Versioning
```sql
-- Event schema versions
CREATE TABLE event_schemas (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    schema_version INT NOT NULL,
    schema_definition JSON NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_event_version (event_type, schema_version)
);

-- Event migration tracking
CREATE TABLE event_migrations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id BIGINT NOT NULL,
    from_version INT NOT NULL,
    to_version INT NOT NULL,
    migration_applied BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_event (event_id),
    INDEX idx_migration (from_version, to_version)
);

-- Event migration procedure
DELIMITER $$
CREATE PROCEDURE migrate_event_schema(
    IN event_type VARCHAR(100),
    IN from_version INT,
    IN to_version INT
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE event_id BIGINT;
    DECLARE old_data JSON;
    DECLARE new_data JSON;
    
    DECLARE event_cursor CURSOR FOR
        SELECT id, event_data
        FROM events 
        WHERE event_type = event_type
        AND event_version = from_version;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN event_cursor;
    
    read_loop: LOOP
        FETCH event_cursor INTO event_id, old_data;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Apply migration logic based on event type
        CASE event_type
            WHEN 'UserCreated' THEN
                -- Example: Add new field with default value
                SET new_data = JSON_SET(old_data, '$.verified', FALSE);
                
            WHEN 'UserUpdated' THEN
                -- Example: Rename field
                SET new_data = JSON_REMOVE(
                    JSON_SET(old_data, '$.full_name', JSON_EXTRACT(old_data, '$.name')),
                    '$.name'
                );
                
            ELSE
                SET new_data = old_data;
        END CASE;
        
        -- Update event data
        UPDATE events 
        SET event_data = new_data, event_version = to_version
        WHERE id = event_id;
        
        -- Record migration
        INSERT INTO event_migrations (event_id, from_version, to_version, migration_applied)
        VALUES (event_id, from_version, to_version, TRUE);
    END LOOP;
    
    CLOSE event_cursor;
END$$
DELIMITER ;
```

## Performance Optimizations

### Event Indexing Strategy
```sql
-- Composite indexes for common query patterns
CREATE INDEX idx_aggregate_version ON events (aggregate_id, aggregate_type, event_version);
CREATE INDEX idx_type_occurred ON events (event_type, occurred_at);
CREATE INDEX idx_aggregate_occurred ON events (aggregate_id, occurred_at);

-- Partitioning by date for large event stores
ALTER TABLE events PARTITION BY RANGE (YEAR(occurred_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Event archiving procedure
DELIMITER $$
CREATE PROCEDURE archive_old_events(
    IN days_to_keep INT DEFAULT 365
)
BEGIN
    -- Archive events older than specified days
    INSERT INTO events_archive 
    SELECT * FROM events 
    WHERE occurred_at < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    
    -- Delete archived events
    DELETE FROM events 
    WHERE occurred_at < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
END$$
DELIMITER ;
```
