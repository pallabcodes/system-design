# Advanced Indexing Strategies & God Mode Optimizations

Real-world indexing hacks, patches, and ingenious techniques used by product engineers at Google, Facebook, Uber, and other Silicon Valley companies to squeeze every bit of performance.

## 🚀 Covering Index Mastery

### Smart Covering Index Patterns
```sql
-- The "God Mode" covering index for user queries
CREATE INDEX idx_user_ultimate_covering ON users (
    status, 
    created_at DESC, 
    id
) INCLUDE (
    email, 
    name, 
    avatar_url, 
    last_login, 
    preferences
);

-- E-commerce product covering index (handles 90% of queries)
CREATE INDEX idx_product_search_covering ON products (
    category_id,
    price,
    rating DESC,
    stock_quantity
) INCLUDE (
    name,
    description,
    image_url,
    brand_id,
    created_at
);

-- Social media feed covering index (handles timeline queries)
CREATE INDEX idx_post_feed_covering ON posts (
    user_id,
    created_at DESC,
    visibility
) INCLUDE (
    content,
    image_urls,
    like_count,
    comment_count,
    share_count
);
```

### Partial Covering Indexes (The Hack)
```sql
-- Only index active users (saves 80% space)
CREATE INDEX idx_active_users_covering ON users (
    status,
    last_login DESC
) INCLUDE (
    email,
    name,
    avatar_url
) WHERE status = 'active';

-- Hot products only (recent + high stock)
CREATE INDEX idx_hot_products_covering ON products (
    category_id,
    stock_quantity DESC,
    created_at DESC
) INCLUDE (
    name,
    price,
    image_url
) WHERE stock_quantity > 10 AND created_at > DATE_SUB(NOW(), INTERVAL 30 DAY);
```

## 🎯 Functional Index Hacks

### Computed Column Indexes
```sql
-- Email domain index (for email marketing)
CREATE INDEX idx_email_domain ON users ((SUBSTRING_INDEX(email, '@', -1)));

-- Date-based indexes (for time-series queries)
CREATE INDEX idx_order_month ON orders ((DATE_FORMAT(created_at, '%Y-%m')));
CREATE INDEX idx_user_age ON users ((YEAR(NOW()) - YEAR(birth_date)));

-- JSON path indexes (for flexible schemas)
CREATE INDEX idx_user_preferences ON users ((JSON_EXTRACT(preferences, '$.theme')));
CREATE INDEX idx_product_attributes ON products ((JSON_EXTRACT(attributes, '$.color')));

-- Composite functional indexes
CREATE INDEX idx_user_location ON users (
    (ROUND(latitude, 2)),
    (ROUND(longitude, 2)),
    status
);
```

### Expression-Based Indexes
```sql
-- Phone number normalization index
CREATE INDEX idx_phone_normalized ON users ((REGEXP_REPLACE(phone, '[^0-9]', '')));

-- URL domain extraction index
CREATE INDEX idx_url_domain ON links ((SUBSTRING_INDEX(SUBSTRING_INDEX(url, '://', -1), '/', 1)));

-- Case-insensitive search index
CREATE INDEX idx_name_ci ON users ((LOWER(name)));

-- Hash-based distribution index
CREATE INDEX idx_user_hash ON users ((CRC32(email) % 100));
```

## 🔥 Composite Index Optimization

### The "Perfect" Composite Index Strategy
```sql
-- Multi-dimensional user search (handles 15 different query patterns)
CREATE INDEX idx_user_multi_search ON users (
    status,           -- High cardinality filter
    country_code,     -- Medium cardinality filter  
    age_group,        -- Low cardinality filter
    created_at DESC,  -- Sorting
    id               -- Uniqueness
);

-- E-commerce product discovery (handles category browsing, filtering, sorting)
CREATE INDEX idx_product_discovery ON products (
    category_id,      -- Primary filter
    brand_id,         -- Secondary filter
    price,            -- Range filter
    rating DESC,      -- Sort order
    stock_quantity,   -- Availability filter
    id               -- Uniqueness
);

-- Social media post discovery (handles feed, search, trending)
CREATE INDEX idx_post_discovery ON posts (
    user_id,          -- User's posts
    visibility,       -- Public/private
    created_at DESC,  -- Chronological
    engagement_score, -- Trending (computed)
    id               -- Uniqueness
);
```

### Index Intersection Hacks
```sql
-- Use multiple single-column indexes for complex queries
CREATE INDEX idx_users_status ON users (status);
CREATE INDEX idx_users_country ON users (country_code);
CREATE INDEX idx_users_age ON users (age);

-- Query: SELECT * FROM users WHERE status = 'active' AND country_code = 'US' AND age > 25
-- MySQL will use index intersection (status + country + age)

-- For OR queries, create separate indexes
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_phone ON users (phone);

-- Query: SELECT * FROM users WHERE email = 'user@example.com' OR phone = '1234567890'
-- MySQL will use UNION of both indexes
```

## 🎪 Inheritance Pattern Indexes

### Polymorphic Association Indexes
```sql
-- Generic comment system (comments on posts, photos, videos, etc.)
CREATE INDEX idx_comments_polymorphic ON comments (
    commentable_type,
    commentable_id,
    created_at DESC
);

-- Generic like system
CREATE INDEX idx_likes_polymorphic ON likes (
    likeable_type,
    likeable_id,
    user_id,
    created_at
);

-- Generic notification system
CREATE INDEX idx_notifications_polymorphic ON notifications (
    notifiable_type,
    notifiable_id,
    user_id,
    read_at,
    created_at DESC
);
```

### Single Table Inheritance Indexes
```sql
-- User types in single table (admin, customer, vendor, etc.)
CREATE INDEX idx_users_type_covering ON users (
    user_type,
    status,
    created_at DESC
) INCLUDE (
    email,
    name,
    permissions
);

-- Product types in single table (physical, digital, service)
CREATE INDEX idx_products_type_covering ON products (
    product_type,
    category_id,
    price
) INCLUDE (
    name,
    description,
    delivery_type
);
```

## 🚀 Performance Hacks & Patches

### The "Skip Scan" Hack
```sql
-- Force skip scan for low-cardinality columns
CREATE INDEX idx_orders_gender_date ON orders (
    gender,           -- Low cardinality (M/F)
    order_date,       -- High cardinality
    amount
);

-- Query: SELECT * FROM orders WHERE order_date = '2024-01-15' AND amount > 100
-- MySQL will skip scan through gender values

-- Force index hint for complex queries
SELECT /*+ INDEX(users, idx_users_multi_search) */ 
    * FROM users 
WHERE status = 'active' 
AND country_code = 'US' 
AND age > 25;
```

### The "Index Condition Pushdown" Hack
```sql
-- Enable ICP for complex conditions
CREATE INDEX idx_products_search ON products (
    category_id,
    price,
    brand_id
);

-- Query with ICP: MySQL pushes conditions down to storage engine
SELECT * FROM products 
WHERE category_id = 1 
AND price BETWEEN 10 AND 100 
AND brand_id IN (1, 2, 3)
AND name LIKE '%phone%';  -- This gets pushed down
```

### The "Index Merge" Hack
```sql
-- Create separate indexes for OR conditions
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_phone ON users (phone);
CREATE INDEX idx_users_username ON users (username);

-- Query: MySQL merges indexes for OR
SELECT * FROM users 
WHERE email = 'user@example.com' 
OR phone = '1234567890' 
OR username = 'user123';
```

## 🎯 Real-World Optimization Patterns

### The "Hot Data" Pattern
```sql
-- Separate indexes for hot vs cold data
CREATE INDEX idx_orders_recent ON orders (
    user_id,
    created_at DESC
) WHERE created_at > DATE_SUB(NOW(), INTERVAL 30 DAY);

CREATE INDEX idx_orders_historical ON orders (
    user_id,
    created_at DESC
) WHERE created_at <= DATE_SUB(NOW(), INTERVAL 30 DAY);
```

### The "Time-Series" Pattern
```sql
-- Partitioned indexes for time-series data
CREATE INDEX idx_events_time ON events (
    event_date,
    event_type,
    user_id
) PARTITION BY RANGE (YEAR(event_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);
```

### The "Geospatial" Pattern
```sql
-- Spatial indexes for location-based queries
CREATE INDEX idx_users_location ON users (
    (ST_X(location)),
    (ST_Y(location)),
    status
);

-- Proximity search optimization
CREATE INDEX idx_places_proximity ON places (
    (ROUND(latitude, 3)),
    (ROUND(longitude, 3)),
    category_id
);
```

## 🔧 Index Maintenance Hacks

### The "Index Health" Monitor
```sql
-- Monitor index usage and health
CREATE TABLE index_health (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    index_name VARCHAR(100) NOT NULL,
    cardinality BIGINT,
    size_mb DECIMAL(10,2),
    usage_count BIGINT DEFAULT 0,
    last_used TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_table_index (table_name, index_name)
);

-- Index usage tracking procedure
DELIMITER $$
CREATE PROCEDURE track_index_usage()
BEGIN
    INSERT INTO index_health (table_name, index_name, cardinality, size_mb)
    SELECT 
        table_name,
        index_name,
        cardinality,
        ROUND(index_length / 1024 / 1024, 2) as size_mb
    FROM information_schema.statistics
    WHERE table_schema = DATABASE();
END$$
DELIMITER ;
```

### The "Index Cleanup" Hack
```sql
-- Find unused indexes
SELECT 
    table_name,
    index_name,
    cardinality,
    ROUND(index_length / 1024 / 1024, 2) as size_mb
FROM information_schema.statistics
WHERE table_schema = DATABASE()
AND index_name != 'PRIMARY'
AND cardinality < 1000  -- Low cardinality indexes
ORDER BY size_mb DESC;

-- Find duplicate indexes
SELECT 
    table_name,
    GROUP_CONCAT(index_name) as duplicate_indexes,
    COUNT(*) as count
FROM information_schema.statistics
WHERE table_schema = DATABASE()
AND index_name != 'PRIMARY'
GROUP BY table_name, column_name
HAVING COUNT(*) > 1;
```

## 🎪 Advanced Inheritance Patterns

### The "Discriminator" Pattern
```sql
-- Single table with discriminator column
CREATE TABLE content_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    content_type ENUM('post', 'photo', 'video', 'story') NOT NULL,
    user_id BIGINT NOT NULL,
    title VARCHAR(255),
    content TEXT,
    media_url VARCHAR(500),
    duration INT,  -- For videos
    filter_type VARCHAR(50),  -- For photos
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Type-specific indexes
    INDEX idx_content_type_user (content_type, user_id, created_at DESC),
    INDEX idx_content_type_media (content_type, media_url),
    INDEX idx_content_type_duration (content_type, duration) WHERE content_type = 'video'
);
```

### The "Class Table Inheritance" Pattern
```sql
-- Base table
CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type ENUM('customer', 'admin', 'vendor') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_type (user_type, created_at)
);

-- Customer-specific table
CREATE TABLE customers (
    user_id BIGINT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    shipping_address JSON,
    FOREIGN KEY (user_id) REFERENCES users(id),
    INDEX idx_customer_name (last_name, first_name),
    INDEX idx_customer_phone (phone)
);

-- Admin-specific table
CREATE TABLE admins (
    user_id BIGINT PRIMARY KEY,
    role VARCHAR(50) NOT NULL,
    permissions JSON,
    last_login TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    INDEX idx_admin_role (role, last_login)
);
```

### The "Concrete Table Inheritance" Pattern
```sql
-- Each type gets its own table
CREATE TABLE customers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_customer_email (email),
    INDEX idx_customer_name (last_name, first_name)
);

CREATE TABLE admins (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    permissions JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin_email (email),
    INDEX idx_admin_role (role)
);
```

## 🚀 The "God Mode" Query Optimization

### The "Index Hints" Mastery
```sql
-- Force specific index usage
SELECT /*+ INDEX(users, idx_users_status_country) */ 
    * FROM users 
WHERE status = 'active' 
AND country_code = 'US';

-- Ignore specific indexes
SELECT /*+ IGNORE_INDEX(users, idx_users_email) */ 
    * FROM users 
WHERE email = 'user@example.com';

-- Use index for ORDER BY
SELECT /*+ INDEX(users, idx_users_created_desc) */ 
    * FROM users 
ORDER BY created_at DESC 
LIMIT 100;
```

### The "Query Rewrite" Hacks
```sql
-- Rewrite COUNT(*) to EXISTS for better performance
-- Instead of: SELECT COUNT(*) FROM orders WHERE user_id = 123
SELECT EXISTS(SELECT 1 FROM orders WHERE user_id = 123) as has_orders;

-- Rewrite IN to JOIN for large lists
-- Instead of: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE status = 'completed')
SELECT DISTINCT u.* 
FROM users u 
JOIN orders o ON u.id = o.user_id 
WHERE o.status = 'completed';

-- Rewrite OR to UNION for better index usage
-- Instead of: SELECT * FROM users WHERE email = 'user@example.com' OR phone = '1234567890'
SELECT * FROM users WHERE email = 'user@example.com'
UNION
SELECT * FROM users WHERE phone = '1234567890';
```

This covers the real-world, hacky, ingenious indexing techniques that product engineers actually use to get that extra performance boost! 🚀
