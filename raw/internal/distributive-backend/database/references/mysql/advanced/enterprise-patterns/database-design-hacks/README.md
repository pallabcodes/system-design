# Database Design Hacks & God Mode Techniques

Real-world database design hacks, denormalization strategies, and optimization techniques used by product engineers to squeeze every bit of performance and maintainability.

## 🚀 Denormalization Strategies

### The "Read-Optimized Denormalization" Pattern
```sql
-- Denormalized user profile for fast reads
CREATE TABLE user_profiles_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(500),
    bio TEXT,
    location VARCHAR(200),
    website VARCHAR(255),
    company VARCHAR(200),
    job_title VARCHAR(200),
    skills JSON,  -- Denormalized skills array
    social_links JSON,  -- Denormalized social media links
    preferences JSON,  -- Denormalized user preferences
    stats JSON,  -- Denormalized user statistics
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_email (email),
    INDEX idx_name (name),
    INDEX idx_location (location),
    INDEX idx_company (company),
    INDEX idx_last_activity (last_activity),
    FULLTEXT INDEX idx_search (name, bio, company, job_title)
);

-- Denormalized post with engagement metrics
CREATE TABLE posts_denormalized (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    user_name VARCHAR(100) NOT NULL,  -- Denormalized
    user_avatar VARCHAR(500),  -- Denormalized
    content TEXT NOT NULL,
    image_urls JSON,  -- Denormalized image array
    tags JSON,  -- Denormalized tags
    like_count INT DEFAULT 0,  -- Denormalized
    comment_count INT DEFAULT 0,  -- Denormalized
    share_count INT DEFAULT 0,  -- Denormalized
    view_count INT DEFAULT 0,  -- Denormalized
    engagement_score DECIMAL(10,4) DEFAULT 0,  -- Computed field
    is_featured BOOLEAN DEFAULT FALSE,
    visibility ENUM('public', 'private', 'friends') DEFAULT 'public',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user_posts (user_id, created_at DESC),
    INDEX idx_engagement (engagement_score DESC, created_at DESC),
    INDEX idx_featured (is_featured, created_at DESC),
    INDEX idx_visibility (visibility, created_at DESC),
    FULLTEXT INDEX idx_content (content, tags)
);
```

### The "Aggregation Denormalization" Pattern
```sql
-- Denormalized order summary for fast analytics
CREATE TABLE order_summaries (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    user_email VARCHAR(255) NOT NULL,  -- Denormalized
    user_name VARCHAR(100) NOT NULL,  -- Denormalized
    total_orders INT DEFAULT 0,
    total_spent DECIMAL(15,2) DEFAULT 0,
    avg_order_value DECIMAL(10,2) DEFAULT 0,
    first_order_date DATE,
    last_order_date DATE,
    favorite_category VARCHAR(100),  -- Most ordered category
    order_frequency_days DECIMAL(5,2),  -- Average days between orders
    lifetime_value DECIMAL(15,2) DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_summary (user_id),
    INDEX idx_total_spent (total_spent DESC),
    INDEX idx_lifetime_value (lifetime_value DESC),
    INDEX idx_last_order (last_order_date DESC)
);

-- Denormalized product analytics
CREATE TABLE product_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    product_name VARCHAR(255) NOT NULL,  -- Denormalized
    category_id BIGINT NOT NULL,
    category_name VARCHAR(100) NOT NULL,  -- Denormalized
    brand_id BIGINT NOT NULL,
    brand_name VARCHAR(100) NOT NULL,  -- Denormalized
    total_sales INT DEFAULT 0,
    total_revenue DECIMAL(15,2) DEFAULT 0,
    avg_rating DECIMAL(3,2) DEFAULT 0,
    review_count INT DEFAULT 0,
    view_count INT DEFAULT 0,
    conversion_rate DECIMAL(5,4) DEFAULT 0,  -- Sales/Views
    stock_level INT DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_product_analytics (product_id),
    INDEX idx_category_sales (category_id, total_sales DESC),
    INDEX idx_brand_revenue (brand_id, total_revenue DESC),
    INDEX idx_rating (avg_rating DESC, review_count DESC),
    INDEX idx_conversion (conversion_rate DESC)
);
```

## 🎯 Soft Delete Patterns

### The "Soft Delete with History" Pattern
```sql
-- Soft delete implementation with history tracking
CREATE TABLE users_soft_delete (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    status ENUM('active', 'inactive', 'deleted') DEFAULT 'active',
    deleted_at TIMESTAMP NULL,
    deleted_by BIGINT NULL,
    deletion_reason VARCHAR(255) NULL,
    can_restore BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_status (status, deleted_at),
    INDEX idx_email (email),
    INDEX idx_deleted_by (deleted_by, deleted_at)
);

-- Soft delete history table
CREATE TABLE soft_delete_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id BIGINT NOT NULL,
    deleted_by BIGINT NOT NULL,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deletion_reason VARCHAR(255) NULL,
    record_data JSON NOT NULL,  -- Full record data before deletion
    restored_at TIMESTAMP NULL,
    restored_by BIGINT NULL,
    
    INDEX idx_table_record (table_name, record_id),
    INDEX idx_deleted_by (deleted_by, deleted_at),
    INDEX idx_restored (restored_at)
);

-- Soft delete procedures
DELIMITER $$
CREATE PROCEDURE soft_delete_user(
    IN user_id BIGINT,
    IN deleted_by BIGINT,
    IN deletion_reason VARCHAR(255)
)
BEGIN
    DECLARE user_data JSON;
    
    -- Get user data before deletion
    SELECT JSON_OBJECT(
        'id', id,
        'email', email,
        'name', name,
        'status', status,
        'created_at', created_at
    ) INTO user_data
    FROM users_soft_delete
    WHERE id = user_id;
    
    -- Soft delete the user
    UPDATE users_soft_delete 
    SET status = 'deleted',
        deleted_at = NOW(),
        deleted_by = deleted_by,
        deletion_reason = deletion_reason
    WHERE id = user_id;
    
    -- Record in history
    INSERT INTO soft_delete_history (table_name, record_id, deleted_by, deletion_reason, record_data)
    VALUES ('users_soft_delete', user_id, deleted_by, deletion_reason, user_data);
END$$

CREATE PROCEDURE restore_user(
    IN user_id BIGINT,
    IN restored_by BIGINT
)
BEGIN
    -- Restore the user
    UPDATE users_soft_delete 
    SET status = 'active',
        deleted_at = NULL,
        deleted_by = NULL,
        deletion_reason = NULL
    WHERE id = user_id;
    
    -- Update history
    UPDATE soft_delete_history 
    SET restored_at = NOW(),
        restored_by = restored_by
    WHERE table_name = 'users_soft_delete' 
    AND record_id = user_id
    AND restored_at IS NULL;
END$$
DELIMITER ;
```

## 🔄 Optimistic Locking Techniques

### The "Version-Based Optimistic Locking" Pattern
```sql
-- Optimistic locking with version control
CREATE TABLE products_optimistic (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    version INT DEFAULT 1,  -- Optimistic lock version
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_name (name),
    INDEX idx_price (price),
    INDEX idx_version (version)
);

-- Optimistic update procedure
DELIMITER $$
CREATE PROCEDURE update_product_optimistic(
    IN product_id BIGINT,
    IN new_name VARCHAR(255),
    IN new_price DECIMAL(10,2),
    IN new_stock INT,
    IN expected_version INT
)
BEGIN
    DECLARE affected_rows INT;
    
    -- Update with version check
    UPDATE products_optimistic 
    SET name = new_name,
        price = new_price,
        stock_quantity = new_stock,
        version = version + 1
    WHERE id = product_id 
    AND version = expected_version;
    
    SET affected_rows = ROW_COUNT();
    
    IF affected_rows = 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Concurrent modification detected. Please refresh and try again.';
    END IF;
END$$
DELIMITER ;
```

### The "Timestamp-Based Optimistic Locking" Pattern
```sql
-- Optimistic locking with timestamps
CREATE TABLE orders_optimistic (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'confirmed', 'shipped', 'delivered') DEFAULT 'pending',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user (user_id),
    INDEX idx_status (status),
    INDEX idx_updated (updated_at)
);

-- Timestamp-based optimistic update
DELIMITER $$
CREATE PROCEDURE update_order_optimistic(
    IN order_id BIGINT,
    IN new_status VARCHAR(20),
    IN expected_updated_at TIMESTAMP
)
BEGIN
    DECLARE affected_rows INT;
    
    -- Update with timestamp check
    UPDATE orders_optimistic 
    SET status = new_status,
        updated_at = NOW()
    WHERE id = order_id 
    AND updated_at = expected_updated_at;
    
    SET affected_rows = ROW_COUNT();
    
    IF affected_rows = 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Order was modified by another user. Please refresh and try again.';
    END IF;
END$$
DELIMITER ;
```

## 🆔 UUID vs Auto-Increment Strategies

### The "Hybrid ID Strategy" Pattern
```sql
-- Hybrid ID system (auto-increment for internal, UUID for external)
CREATE TABLE users_hybrid_id (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,  -- Internal ID (fast joins)
    external_id CHAR(36) UNIQUE NOT NULL,  -- UUID for external APIs
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_external_id (external_id),
    INDEX idx_email (email)
);

-- UUID generation function
DELIMITER $$
CREATE FUNCTION generate_uuid() 
RETURNS CHAR(36)
DETERMINISTIC
BEGIN
    RETURN UUID();
END$$
DELIMITER ;

-- Insert with hybrid ID
DELIMITER $$
CREATE PROCEDURE insert_user_hybrid(
    IN user_email VARCHAR(255),
    IN user_name VARCHAR(100)
)
BEGIN
    INSERT INTO users_hybrid_id (external_id, email, name)
    VALUES (generate_uuid(), user_email, user_name);
    
    SELECT 
        id as internal_id,
        external_id,
        email,
        name,
        created_at
    FROM users_hybrid_id
    WHERE id = LAST_INSERT_ID();
END$$
DELIMITER ;
```

### The "Shard-Aware ID Strategy" Pattern
```sql
-- Shard-aware ID generation
CREATE TABLE users_shard_id (
    id BIGINT PRIMARY KEY,  -- Custom generated ID
    shard_id TINYINT NOT NULL,  -- Shard identifier
    sequence_id BIGINT NOT NULL,  -- Sequence within shard
    email VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_shard_sequence (shard_id, sequence_id),
    INDEX idx_email (email)
);

-- Shard-aware ID generation
DELIMITER $$
CREATE FUNCTION generate_shard_id(
    shard_id TINYINT,
    sequence_id BIGINT
) 
RETURNS BIGINT
DETERMINISTIC
BEGIN
    -- Format: shard_id (8 bits) + timestamp (32 bits) + sequence (24 bits)
    RETURN (shard_id << 56) | 
           ((UNIX_TIMESTAMP() & 0xFFFFFFFF) << 24) | 
           (sequence_id & 0xFFFFFF);
END$$
DELIMITER ;
```

## 🎪 Database Design Hacks

### The "Polymorphic Association Hack" Pattern
```sql
-- Polymorphic associations with type safety
CREATE TABLE polymorphic_entities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id BIGINT NOT NULL,
    entity_data JSON NOT NULL,  -- Flexible data storage
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_entity (entity_type, entity_id),
    INDEX idx_entity_type (entity_type, created_at),
    INDEX idx_entity_data ((CAST(entity_data->>'$.status' AS CHAR(20))))
);

-- Type-safe polymorphic queries
CREATE VIEW users_polymorphic AS
SELECT 
    id,
    entity_id as user_id,
    JSON_UNQUOTE(entity_data->>'$.email') as email,
    JSON_UNQUOTE(entity_data->>'$.name') as name,
    JSON_UNQUOTE(entity_data->>'$.status') as status,
    created_at
FROM polymorphic_entities
WHERE entity_type = 'User';

CREATE VIEW products_polymorphic AS
SELECT 
    id,
    entity_id as product_id,
    JSON_UNQUOTE(entity_data->>'$.name') as name,
    JSON_UNQUOTE(entity_data->>'$.price') as price,
    JSON_UNQUOTE(entity_data->>'$.category') as category,
    created_at
FROM polymorphic_entities
WHERE entity_type = 'Product';
```

### The "Materialized View Hack" Pattern
```sql
-- Materialized view implementation using tables
CREATE TABLE materialized_user_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL,
    total_posts INT DEFAULT 0,
    total_likes INT DEFAULT 0,
    total_comments INT DEFAULT 0,
    engagement_score DECIMAL(10,4) DEFAULT 0,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    refreshed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_engagement (engagement_score DESC),
    INDEX idx_activity (last_activity DESC)
);

-- Materialized view refresh procedure
DELIMITER $$
CREATE PROCEDURE refresh_user_stats()
BEGIN
    INSERT INTO materialized_user_stats (user_id, total_posts, total_likes, total_comments, engagement_score, last_activity)
    SELECT 
        u.id as user_id,
        COUNT(DISTINCT p.id) as total_posts,
        COUNT(DISTINCT l.id) as total_likes,
        COUNT(DISTINCT c.id) as total_comments,
        (COUNT(DISTINCT l.id) * 1 + COUNT(DISTINCT c.id) * 2) as engagement_score,
        GREATEST(
            COALESCE(MAX(p.created_at), '1970-01-01'),
            COALESCE(MAX(l.created_at), '1970-01-01'),
            COALESCE(MAX(c.created_at), '1970-01-01')
        ) as last_activity
    FROM users u
    LEFT JOIN posts p ON u.id = p.user_id
    LEFT JOIN likes l ON u.id = l.user_id
    LEFT JOIN comments c ON u.id = c.user_id
    GROUP BY u.id
    ON DUPLICATE KEY UPDATE
        total_posts = VALUES(total_posts),
        total_likes = VALUES(total_likes),
        total_comments = VALUES(total_comments),
        engagement_score = VALUES(engagement_score),
        last_activity = VALUES(last_activity),
        refreshed_at = NOW();
END$$
DELIMITER ;
```

## 🔧 Performance Optimization Hacks

### The "Query Result Caching" Pattern
```sql
-- Query result cache
CREATE TABLE query_cache (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cache_key VARCHAR(255) UNIQUE NOT NULL,
    query_hash VARCHAR(64) NOT NULL,
    result_data JSON NOT NULL,
    result_size_bytes INT DEFAULT 0,
    hit_count INT DEFAULT 0,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_query_hash (query_hash),
    INDEX idx_expires (expires_at),
    INDEX idx_last_accessed (last_accessed)
);

-- Query cache management
DELIMITER $$
CREATE PROCEDURE cache_query_result(
    IN query_hash VARCHAR(64),
    IN result_data JSON,
    IN ttl_minutes INT DEFAULT 60
)
BEGIN
    DECLARE cache_key VARCHAR(255);
    DECLARE result_size INT;
    
    SET cache_key = CONCAT('query:', query_hash);
    SET result_size = JSON_LENGTH(result_data);
    
    INSERT INTO query_cache (cache_key, query_hash, result_data, result_size_bytes, expires_at)
    VALUES (cache_key, query_hash, result_data, result_size, DATE_ADD(NOW(), INTERVAL ttl_minutes MINUTE))
    ON DUPLICATE KEY UPDATE
        result_data = VALUES(result_data),
        result_size_bytes = VALUES(result_size_bytes),
        expires_at = VALUES(expires_at),
        hit_count = hit_count + 1,
        last_accessed = NOW();
END$$

CREATE PROCEDURE get_cached_query(
    IN query_hash VARCHAR(64)
)
BEGIN
    SELECT 
        result_data,
        hit_count,
        last_accessed
    FROM query_cache
    WHERE query_hash = query_hash
    AND expires_at > NOW();
    
    -- Update hit count
    UPDATE query_cache 
    SET hit_count = hit_count + 1,
        last_accessed = NOW()
    WHERE query_hash = query_hash
    AND expires_at > NOW();
END$$
DELIMITER ;
```

### The "Connection Pool Optimization" Pattern
```sql
-- Connection pool monitoring
CREATE TABLE connection_pool_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    pool_name VARCHAR(50) NOT NULL,
    active_connections INT NOT NULL,
    idle_connections INT NOT NULL,
    total_connections INT NOT NULL,
    wait_count INT NOT NULL,
    wait_time_ms INT NOT NULL,
    connection_creation_time_ms INT NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_pool_time (pool_name, recorded_at),
    INDEX idx_metrics (active_connections, idle_connections, recorded_at)
);

-- Connection pool health check
CREATE VIEW connection_pool_health AS
SELECT 
    pool_name,
    AVG(active_connections) as avg_active,
    AVG(idle_connections) as avg_idle,
    AVG(wait_time_ms) as avg_wait_time,
    MAX(wait_count) as max_wait_count,
    CASE 
        WHEN AVG(wait_time_ms) > 1000 THEN 'critical'
        WHEN AVG(wait_time_ms) > 500 THEN 'warning'
        ELSE 'healthy'
    END as health_status
FROM connection_pool_metrics
WHERE recorded_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
GROUP BY pool_name;
```

These database design hacks show the real-world techniques that product engineers use to optimize database performance and maintainability! 🚀
