# Data Migration & Versioning Patterns

Advanced data migration and schema evolution techniques used by companies like Google, Netflix, and financial institutions to handle zero-downtime deployments.

## Zero-Downtime Migration Strategies

### Blue-Green Deployment Pattern
```sql
-- Migration tracking table
CREATE TABLE schema_migrations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    migration_name VARCHAR(255) NOT NULL,
    version VARCHAR(50) NOT NULL,
    status ENUM('pending', 'in_progress', 'completed', 'failed', 'rolled_back') DEFAULT 'pending',
    migration_type ENUM('schema', 'data', 'both') NOT NULL,
    blue_schema VARCHAR(100) NOT NULL,
    green_schema VARCHAR(100) NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    rollback_script TEXT,
    INDEX idx_status (status),
    INDEX idx_version (version)
);

-- Blue-green schema management
CREATE TABLE schema_environments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    environment_name VARCHAR(50) NOT NULL,
    schema_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT FALSE,
    is_production BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMP NULL,
    UNIQUE KEY uk_environment (environment_name)
);

-- Migration execution procedure
DELIMITER $$
CREATE PROCEDURE execute_blue_green_migration(
    IN migration_name VARCHAR(255),
    IN version VARCHAR(50),
    IN migration_script TEXT
)
BEGIN
    DECLARE blue_schema VARCHAR(100);
    DECLARE green_schema VARCHAR(100);
    DECLARE migration_id BIGINT;
    
    -- Get current blue and green schemas
    SELECT 
        MAX(CASE WHEN is_active = TRUE THEN schema_name END) as active_schema,
        MAX(CASE WHEN is_active = FALSE THEN schema_name END) as inactive_schema
    INTO blue_schema, green_schema
    FROM schema_environments
    WHERE is_production = TRUE;
    
    -- Create migration record
    INSERT INTO schema_migrations (migration_name, version, migration_type, blue_schema, green_schema)
    VALUES (migration_name, version, 'schema', blue_schema, green_schema);
    
    SET migration_id = LAST_INSERT_ID();
    
    -- Update status to in_progress
    UPDATE schema_migrations SET status = 'in_progress' WHERE id = migration_id;
    
    -- Apply migration to inactive schema (green)
    SET @sql = CONCAT('USE ', green_schema, '; ', migration_script);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    -- Switch traffic to green schema
    UPDATE schema_environments SET is_active = FALSE WHERE schema_name = blue_schema;
    UPDATE schema_environments SET is_active = TRUE, activated_at = NOW() WHERE schema_name = green_schema;
    
    -- Mark migration as completed
    UPDATE schema_migrations 
    SET status = 'completed', completed_at = NOW()
    WHERE id = migration_id;
    
    -- Clean up old blue schema (optional)
    -- DROP SCHEMA blue_schema;
END$$
DELIMITER ;
```

## Feature Flag-Based Data Migration

### Feature Flag Management
```sql
-- Feature flags table
CREATE TABLE feature_flags (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    flag_name VARCHAR(100) NOT NULL,
    flag_type ENUM('boolean', 'percentage', 'user_list') NOT NULL,
    flag_value JSON NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_flag_name (flag_name)
);

-- Feature flag evaluation
CREATE TABLE feature_flag_evaluations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    flag_name VARCHAR(100) NOT NULL,
    user_id BIGINT,
    session_id VARCHAR(36),
    evaluated_value BOOLEAN NOT NULL,
    evaluated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_flag_user (flag_name, user_id),
    INDEX idx_flag_session (flag_name, session_id)
);

-- Feature flag evaluation function
DELIMITER $$
CREATE FUNCTION evaluate_feature_flag(
    flag_name VARCHAR(100),
    user_id BIGINT,
    session_id VARCHAR(36)
) 
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE flag_type VARCHAR(20);
    DECLARE flag_value JSON;
    DECLARE result BOOLEAN DEFAULT FALSE;
    
    -- Get flag details
    SELECT ff.flag_type, ff.flag_value
    INTO flag_type, flag_value
    FROM feature_flags ff
    WHERE ff.flag_name = flag_name
    AND ff.is_active = TRUE;
    
    IF flag_type IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Evaluate based on flag type
    CASE flag_type
        WHEN 'boolean' THEN
            SET result = JSON_UNQUOTE(JSON_EXTRACT(flag_value, '$.enabled')) = 'true';
            
        WHEN 'percentage' THEN
            SET result = (user_id % 100) < JSON_UNQUOTE(JSON_EXTRACT(flag_value, '$.percentage'));
            
        WHEN 'user_list' THEN
            SET result = JSON_CONTAINS(flag_value, CAST(user_id AS JSON), '$.user_ids');
            
        ELSE
            SET result = FALSE;
    END CASE;
    
    -- Log evaluation
    INSERT INTO feature_flag_evaluations (flag_name, user_id, session_id, evaluated_value)
    VALUES (flag_name, user_id, session_id, result);
    
    RETURN result;
END$$
DELIMITER ;
```

## Schema Evolution Strategies

### Backward-Compatible Schema Changes
```sql
-- Schema version tracking
CREATE TABLE schema_versions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    version_number INT NOT NULL,
    change_type ENUM('add_column', 'drop_column', 'modify_column', 'add_index', 'drop_index', 'add_table', 'drop_table') NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    column_name VARCHAR(100) NULL,
    old_definition TEXT NULL,
    new_definition TEXT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_version (version_number),
    INDEX idx_table (table_name)
);

-- Safe column addition
DELIMITER $$
CREATE PROCEDURE add_column_safely(
    IN table_name VARCHAR(100),
    IN column_name VARCHAR(100),
    IN column_definition TEXT,
    IN default_value TEXT
)
BEGIN
    DECLARE column_exists INT;
    
    -- Check if column already exists
    SELECT COUNT(*) INTO column_exists
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
    AND table_name = table_name
    AND column_name = column_name;
    
    IF column_exists = 0 THEN
        -- Add column with default value
        SET @sql = CONCAT('ALTER TABLE ', table_name, ' ADD COLUMN ', column_name, ' ', column_definition);
        
        IF default_value IS NOT NULL THEN
            SET @sql = CONCAT(@sql, ' DEFAULT ', default_value);
        END IF;
        
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        
        -- Record schema change
        INSERT INTO schema_versions (version_number, change_type, table_name, column_name, new_definition)
        VALUES (
            (SELECT COALESCE(MAX(version_number), 0) + 1 FROM schema_versions),
            'add_column',
            table_name,
            column_name,
            column_definition
        );
    END IF;
END$$
DELIMITER ;
```

## Data Backfilling Techniques

### Batch Data Processing
```sql
-- Batch processing tracking
CREATE TABLE batch_jobs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_name VARCHAR(100) NOT NULL,
    batch_size INT DEFAULT 1000,
    total_records BIGINT NOT NULL,
    processed_records BIGINT DEFAULT 0,
    failed_records BIGINT DEFAULT 0,
    status ENUM('pending', 'running', 'completed', 'failed', 'paused') DEFAULT 'pending',
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    error_message TEXT,
    INDEX idx_status (status),
    INDEX idx_job_name (job_name)
);

-- Batch processing procedure
DELIMITER $$
CREATE PROCEDURE process_batch_job(
    IN job_name VARCHAR(100),
    IN batch_size INT DEFAULT 1000
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_offset BIGINT DEFAULT 0;
    DECLARE total_records BIGINT;
    DECLARE job_id BIGINT;
    
    -- Create job record
    SELECT COUNT(*) INTO total_records FROM users WHERE status = 'active';
    
    INSERT INTO batch_jobs (job_name, batch_size, total_records)
    VALUES (job_name, batch_size, total_records);
    
    SET job_id = LAST_INSERT_ID();
    
    -- Update status to running
    UPDATE batch_jobs SET status = 'running' WHERE id = job_id;
    
    -- Process in batches
    WHILE current_offset < total_records DO
        -- Process batch
        UPDATE users 
        SET last_updated = NOW()
        WHERE status = 'active'
        LIMIT batch_size OFFSET current_offset;
        
        -- Update progress
        UPDATE batch_jobs 
        SET processed_records = processed_records + ROW_COUNT()
        WHERE id = job_id;
        
        SET current_offset = current_offset + batch_size;
        
        -- Add delay to prevent overwhelming the database
        DO SLEEP(0.1);
    END WHILE;
    
    -- Mark as completed
    UPDATE batch_jobs 
    SET status = 'completed', completed_at = NOW()
    WHERE id = job_id;
END$$
DELIMITER ;
```

## Data Validation & Consistency

### Data Integrity Checks
```sql
-- Data validation rules
CREATE TABLE validation_rules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    column_name VARCHAR(100) NULL,
    rule_type ENUM('not_null', 'unique', 'range', 'format', 'custom') NOT NULL,
    rule_definition JSON NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Validation results
CREATE TABLE validation_results (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    rule_id BIGINT NOT NULL,
    validation_date DATE NOT NULL,
    total_records BIGINT NOT NULL,
    valid_records BIGINT NOT NULL,
    invalid_records BIGINT NOT NULL,
    error_details JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_rule_date (rule_id, validation_date)
);

-- Data validation procedure
DELIMITER $$
CREATE PROCEDURE validate_data_integrity()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE rule_id BIGINT;
    DECLARE rule_name VARCHAR(100);
    DECLARE table_name VARCHAR(100);
    DECLARE column_name VARCHAR(100);
    DECLARE rule_type VARCHAR(20);
    DECLARE rule_definition JSON;
    
    DECLARE rule_cursor CURSOR FOR
        SELECT id, rule_name, table_name, column_name, rule_type, rule_definition
        FROM validation_rules
        WHERE is_active = TRUE;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN rule_cursor;
    
    validate_loop: LOOP
        FETCH rule_cursor INTO rule_id, rule_name, table_name, column_name, rule_type, rule_definition;
        IF done THEN
            LEAVE validate_loop;
        END IF;
        
        -- Execute validation based on rule type
        CASE rule_type
            WHEN 'not_null' THEN
                CALL validate_not_null(rule_id, table_name, column_name);
                
            WHEN 'unique' THEN
                CALL validate_unique(rule_id, table_name, column_name);
                
            WHEN 'range' THEN
                CALL validate_range(rule_id, table_name, column_name, rule_definition);
                
            WHEN 'format' THEN
                CALL validate_format(rule_id, table_name, column_name, rule_definition);
                
            ELSE
                -- Custom validation
                CALL execute_custom_validation(rule_id, table_name, rule_definition);
        END CASE;
    END LOOP;
    
    CLOSE rule_cursor;
END$$
DELIMITER ;
```

## Rollback Strategies

### Migration Rollback
```sql
-- Rollback procedures
CREATE TABLE rollback_scripts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    migration_id BIGINT NOT NULL,
    rollback_script TEXT NOT NULL,
    rollback_type ENUM('schema', 'data', 'both') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_migration (migration_id)
);

-- Rollback execution
DELIMITER $$
CREATE PROCEDURE rollback_migration(
    IN migration_id BIGINT
)
BEGIN
    DECLARE rollback_script TEXT;
    DECLARE rollback_type VARCHAR(20);
    
    -- Get rollback script
    SELECT rs.rollback_script, rs.rollback_type
    INTO rollback_script, rollback_type
    FROM rollback_scripts rs
    WHERE rs.migration_id = migration_id;
    
    IF rollback_script IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'No rollback script found for this migration';
    END IF;
    
    -- Execute rollback
    PREPARE stmt FROM rollback_script;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    -- Update migration status
    UPDATE schema_migrations 
    SET status = 'rolled_back'
    WHERE id = migration_id;
    
    -- Log rollback
    INSERT INTO migration_logs (migration_id, action, details)
    VALUES (migration_id, 'rollback', CONCAT('Rolled back migration type: ', rollback_type));
END$$
DELIMITER ;
```

## Monitoring & Alerting

### Migration Monitoring
```sql
-- Migration monitoring dashboard
CREATE VIEW migration_dashboard AS
SELECT 
    'pending_migrations' as metric,
    COUNT(*) as value
FROM schema_migrations
WHERE status = 'pending'

UNION ALL

SELECT 
    'running_migrations',
    COUNT(*)
FROM schema_migrations
WHERE status = 'in_progress'

UNION ALL

SELECT 
    'failed_migrations',
    COUNT(*)
FROM schema_migrations
WHERE status = 'failed'

UNION ALL

SELECT 
    'completed_migrations_today',
    COUNT(*)
FROM schema_migrations
WHERE status = 'completed'
AND DATE(completed_at) = CURDATE();

-- Migration alerting
DELIMITER $$
CREATE PROCEDURE check_migration_alerts()
BEGIN
    DECLARE failed_count INT;
    DECLARE running_count INT;
    
    -- Check for failed migrations
    SELECT COUNT(*) INTO failed_count
    FROM schema_migrations
    WHERE status = 'failed'
    AND completed_at > DATE_SUB(NOW(), INTERVAL 1 HOUR);
    
    IF failed_count > 0 THEN
        INSERT INTO alerts (alert_type, message, severity)
        VALUES ('migration_failure', CONCAT('Found ', failed_count, ' failed migrations in the last hour'), 'critical');
    END IF;
    
    -- Check for long-running migrations
    SELECT COUNT(*) INTO running_count
    FROM schema_migrations
    WHERE status = 'in_progress'
    AND started_at < DATE_SUB(NOW(), INTERVAL 30 MINUTE);
    
    IF running_count > 0 THEN
        INSERT INTO alerts (alert_type, message, severity)
        VALUES ('migration_timeout', CONCAT('Found ', running_count, ' migrations running for more than 30 minutes'), 'warning');
    END IF;
END$$
DELIMITER ;
```
