# Database Sharding Patterns

Advanced sharding techniques used by companies like Google, Facebook, and Twitter to handle massive scale.

## Horizontal Sharding Strategies

### 1. **Hash-Based Sharding**
```sql
-- Consistent hashing for user data
CREATE TABLE users_shard_0 LIKE users;
CREATE TABLE users_shard_1 LIKE users;
-- ... up to N shards

-- Shard selection function
DELIMITER $$
CREATE FUNCTION get_user_shard(user_id BIGINT) 
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN user_id % 16; -- 16 shards
END$$
DELIMITER ;
```

### 2. **Range-Based Sharding**
```sql
-- Shard by date ranges
CREATE TABLE orders_2024_01 (
    id BIGINT PRIMARY KEY,
    order_date DATE,
    user_id BIGINT,
    amount DECIMAL(10,2)
) PARTITION BY RANGE (YEAR(order_date) * 100 + MONTH(order_date)) (
    PARTITION p202401 VALUES LESS THAN (202402),
    PARTITION p202402 VALUES LESS THAN (202403),
    -- ... more partitions
);
```

### 3. **Directory-Based Sharding**
```sql
-- Shard mapping table
CREATE TABLE shard_mapping (
    entity_id BIGINT PRIMARY KEY,
    shard_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_shard_id (shard_id)
);

-- Shard lookup function
DELIMITER $$
CREATE FUNCTION get_shard_for_entity(entity_id BIGINT) 
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE shard_id INT;
    SELECT shard_id INTO shard_id 
    FROM shard_mapping 
    WHERE entity_id = entity_id;
    RETURN COALESCE(shard_id, 0);
END$$
DELIMITER ;
```

## Cross-Shard Transactions

### Saga Pattern Implementation
```sql
-- Saga state tracking
CREATE TABLE saga_steps (
    saga_id VARCHAR(36) PRIMARY KEY,
    step_id INT NOT NULL,
    service_name VARCHAR(50) NOT NULL,
    status ENUM('pending', 'completed', 'failed', 'compensated') DEFAULT 'pending',
    payload JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_saga_step (saga_id, step_id),
    INDEX idx_status (status)
);

-- Compensation actions table
CREATE TABLE compensation_actions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    saga_id VARCHAR(36) NOT NULL,
    step_id INT NOT NULL,
    action_type VARCHAR(50) NOT NULL,
    action_data JSON,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_saga (saga_id)
);
```

## Shard Rebalancing

### Live Migration Strategy
```sql
-- Migration tracking
CREATE TABLE shard_migrations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source_shard INT NOT NULL,
    target_shard INT NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    start_id BIGINT NOT NULL,
    end_id BIGINT NOT NULL,
    status ENUM('pending', 'in_progress', 'completed', 'failed') DEFAULT 'pending',
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_status (status),
    INDEX idx_source (source_shard, entity_type)
);

-- Migration procedure
DELIMITER $$
CREATE PROCEDURE migrate_shard_data(
    IN source_shard INT,
    IN target_shard INT,
    IN entity_type VARCHAR(50),
    IN batch_size INT
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_id BIGINT;
    DECLARE end_id BIGINT;
    
    -- Get migration range
    SELECT start_id, end_id INTO current_id, end_id
    FROM shard_migrations 
    WHERE source_shard = source_shard 
    AND target_shard = target_shard 
    AND entity_type = entity_type
    AND status = 'in_progress'
    LIMIT 1;
    
    -- Process in batches
    WHILE current_id <= end_id DO
        -- Copy data to target shard
        SET @sql = CONCAT(
            'INSERT INTO ', entity_type, '_shard_', target_shard,
            ' SELECT * FROM ', entity_type, '_shard_', source_shard,
            ' WHERE id >= ', current_id, ' AND id < ', current_id + batch_size
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        
        SET current_id = current_id + batch_size;
    END WHILE;
END$$
DELIMITER ;
```

## Consistent Hashing Implementation

```sql
-- Virtual nodes for consistent hashing
CREATE TABLE virtual_nodes (
    node_id INT PRIMARY KEY,
    physical_shard INT NOT NULL,
    hash_value BIGINT NOT NULL,
    INDEX idx_hash (hash_value)
);

-- Hash ring lookup
DELIMITER $$
CREATE FUNCTION find_shard_for_key(key_hash BIGINT) 
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE shard_id INT;
    
    SELECT physical_shard INTO shard_id
    FROM virtual_nodes 
    WHERE hash_value >= key_hash
    ORDER BY hash_value ASC
    LIMIT 1;
    
    -- If no node found, wrap around to first node
    IF shard_id IS NULL THEN
        SELECT physical_shard INTO shard_id
        FROM virtual_nodes 
        ORDER BY hash_value ASC
        LIMIT 1;
    END IF;
    
    RETURN shard_id;
END$$
DELIMITER ;
```

## Monitoring Shard Health

```sql
-- Shard health monitoring
CREATE TABLE shard_health (
    shard_id INT PRIMARY KEY,
    total_rows BIGINT DEFAULT 0,
    avg_query_time DECIMAL(10,4) DEFAULT 0,
    error_rate DECIMAL(5,4) DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Health check procedure
DELIMITER $$
CREATE PROCEDURE check_shard_health(IN shard_id INT)
BEGIN
    DECLARE row_count BIGINT;
    DECLARE avg_time DECIMAL(10,4);
    
    -- Count rows in shard
    SET @sql = CONCAT('SELECT COUNT(*) INTO @row_count FROM users_shard_', shard_id);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    -- Update health metrics
    UPDATE shard_health 
    SET total_rows = @row_count,
        last_updated = CURRENT_TIMESTAMP
    WHERE shard_id = shard_id;
END$$
DELIMITER ;
```
