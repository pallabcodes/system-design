# Query Optimization Hacks & God Mode Techniques

Real-world query optimization hacks, patches, and ingenious techniques used by product engineers to squeeze every bit of performance from MySQL.

## 🚀 The "Query Rewrite" Mastery

### COUNT(*) Optimization Hacks
```sql
-- Instead of expensive COUNT(*) queries
-- BAD: SELECT COUNT(*) FROM orders WHERE user_id = 123 AND status = 'completed'
-- GOOD: Use EXISTS for boolean checks
SELECT EXISTS(SELECT 1 FROM orders WHERE user_id = 123 AND status = 'completed') as has_orders;

-- For pagination, use LIMIT with offset
-- BAD: SELECT COUNT(*) FROM posts WHERE user_id = 123
-- GOOD: Use LIMIT to check if more data exists
SELECT 1 FROM posts WHERE user_id = 123 LIMIT 1;

-- For approximate counts, use table statistics
-- BAD: SELECT COUNT(*) FROM users WHERE status = 'active'
-- GOOD: Use table statistics (approximate but fast)
SELECT TABLE_ROWS as approximate_count 
FROM information_schema.tables 
WHERE table_schema = DATABASE() 
AND table_name = 'users';
```

### IN vs JOIN Optimization
```sql
-- BAD: Large IN clause
-- SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE status = 'completed')
-- This can be slow with large subqueries

-- GOOD: Use JOIN instead
SELECT DISTINCT u.* 
FROM users u 
JOIN orders o ON u.id = o.user_id 
WHERE o.status = 'completed';

-- BAD: Multiple OR conditions
-- SELECT * FROM users WHERE email = 'user@example.com' OR phone = '1234567890'

-- GOOD: Use UNION for better index usage
SELECT * FROM users WHERE email = 'user@example.com'
UNION
SELECT * FROM users WHERE phone = '1234567890';

-- For small IN lists, use FIND_IN_SET
-- SELECT * FROM users WHERE id IN (1,2,3,4,5)
-- GOOD: Use FIND_IN_SET for small lists
SELECT * FROM users WHERE FIND_IN_SET(id, '1,2,3,4,5');
```

## 🎯 The "Index Hint" Mastery

### Force Index Usage
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

-- Force index for JOIN
SELECT /*+ INDEX(u, idx_users_status) INDEX(o, idx_orders_user) */ 
    u.*, o.* 
FROM users u 
JOIN orders o ON u.id = o.user_id 
WHERE u.status = 'active';
```

### The "Index Merge" Hack
```sql
-- Create separate indexes for OR conditions
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_phone ON users (phone);
CREATE INDEX idx_users_username ON users (username);

-- MySQL will merge indexes for OR
SELECT * FROM users 
WHERE email = 'user@example.com' 
OR phone = '1234567890' 
OR username = 'user123';

-- Force index merge
SELECT /*+ INDEX_MERGE(users, idx_users_email, idx_users_phone) */ 
    * FROM users 
WHERE email = 'user@example.com' 
OR phone = '1234567890';
```

## 🔥 The "Pagination" Optimization

### Keyset Pagination (The God Mode)
```sql
-- BAD: Offset pagination (gets slower with large offsets)
-- SELECT * FROM posts ORDER BY created_at DESC LIMIT 20 OFFSET 1000

-- GOOD: Keyset pagination (constant performance)
-- First page
SELECT * FROM posts 
ORDER BY created_at DESC, id DESC 
LIMIT 20;

-- Next page (using last record's values)
SELECT * FROM posts 
WHERE (created_at, id) < ('2024-01-15 10:30:00', 12345)
ORDER BY created_at DESC, id DESC 
LIMIT 20;

-- Previous page (using first record's values)
SELECT * FROM posts 
WHERE (created_at, id) > ('2024-01-15 10:30:00', 12345)
ORDER BY created_at ASC, id ASC 
LIMIT 20;
```

### The "Window Function" Hack
```sql
-- Use window functions for efficient pagination
SELECT * FROM (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY created_at DESC, id DESC) as rn
    FROM posts
    WHERE user_id = 123
) ranked_posts
WHERE rn BETWEEN 21 AND 40;
```

## 🎪 The "Subquery" Optimization

### Correlated Subquery Hacks
```sql
-- BAD: Correlated subquery
-- SELECT u.*, (SELECT COUNT(*) FROM orders WHERE user_id = u.id) as order_count FROM users u

-- GOOD: Use JOIN with GROUP BY
SELECT u.*, COUNT(o.id) as order_count 
FROM users u 
LEFT JOIN orders o ON u.id = o.user_id 
GROUP BY u.id;

-- GOOD: Use window function
SELECT 
    u.*,
    COUNT(o.id) OVER (PARTITION BY u.id) as order_count
FROM users u 
LEFT JOIN orders o ON u.id = o.user_id;

-- For EXISTS, use JOIN with LIMIT
-- BAD: SELECT * FROM users WHERE EXISTS (SELECT 1 FROM orders WHERE user_id = users.id)
-- GOOD: Use JOIN
SELECT DISTINCT u.* 
FROM users u 
JOIN orders o ON u.id = o.user_id;
```

### The "Derived Table" Hack
```sql
-- Use derived tables for complex aggregations
SELECT 
    u.name,
    recent_orders.order_count,
    recent_orders.total_amount
FROM users u
JOIN (
    SELECT 
        user_id,
        COUNT(*) as order_count,
        SUM(amount) as total_amount
    FROM orders 
    WHERE created_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY user_id
) recent_orders ON u.id = recent_orders.user_id;
```

## 🚀 The "JOIN" Optimization Mastery

### The "Join Order" Hack
```sql
-- Force join order for optimal performance
SELECT /*+ JOIN_ORDER(users, orders, products) */ 
    u.name, o.order_date, p.name as product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE u.status = 'active';

-- Use STRAIGHT_JOIN to force join order
SELECT STRAIGHT_JOIN 
    u.name, o.order_date, p.name as product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE u.status = 'active';
```

### The "Join Buffer" Optimization
```sql
-- Optimize join buffer size for large joins
SET SESSION join_buffer_size = 268435456; -- 256MB

-- Use BNL (Block Nested Loop) for large tables
SELECT /*+ BNL(users, orders) */ 
    u.name, COUNT(o.id) as order_count
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.id;
```

## 🎯 The "Aggregation" Optimization

### The "Rollup" Hack
```sql
-- Use ROLLUP for hierarchical aggregations
SELECT 
    category_id,
    brand_id,
    COUNT(*) as product_count,
    AVG(price) as avg_price
FROM products
GROUP BY category_id, brand_id WITH ROLLUP;

-- Use CUBE for multi-dimensional analysis
SELECT 
    category_id,
    brand_id,
    status,
    COUNT(*) as count
FROM products
GROUP BY CUBE(category_id, brand_id, status);
```

### The "Window Function" Mastery
```sql
-- Use window functions for complex aggregations
SELECT 
    user_id,
    order_date,
    amount,
    SUM(amount) OVER (PARTITION BY user_id ORDER BY order_date) as running_total,
    AVG(amount) OVER (PARTITION BY user_id ORDER BY order_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as moving_avg,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY amount DESC) as rank_by_amount
FROM orders
WHERE user_id = 123;
```

## 🔧 The "Temporary Table" Hack

### The "Materialized" Query Pattern
```sql
-- Use temporary tables for complex queries
CREATE TEMPORARY TABLE temp_user_stats AS
SELECT 
    user_id,
    COUNT(*) as order_count,
    SUM(amount) as total_amount,
    MAX(order_date) as last_order
FROM orders
WHERE created_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY user_id;

-- Use the temporary table
SELECT 
    u.name,
    t.order_count,
    t.total_amount,
    t.last_order
FROM users u
JOIN temp_user_stats t ON u.id = t.user_id
WHERE t.order_count > 5;

DROP TEMPORARY TABLE IF EXISTS temp_user_stats;
```

### The "Common Table Expression" Hack
```sql
-- Use CTEs for complex queries
WITH user_stats AS (
    SELECT 
        user_id,
        COUNT(*) as order_count,
        SUM(amount) as total_amount
    FROM orders
    WHERE created_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY user_id
),
active_users AS (
    SELECT id, name, email
    FROM users
    WHERE status = 'active'
)
SELECT 
    au.name,
    us.order_count,
    us.total_amount
FROM active_users au
JOIN user_stats us ON au.id = us.user_id
WHERE us.order_count > 5;
```

## 🎪 The "Full-Text Search" Optimization

### The "Boolean Mode" Hack
```sql
-- Use boolean mode for complex searches
SELECT 
    title,
    content,
    MATCH(title, content) AGAINST('+mysql +optimization -slow' IN BOOLEAN MODE) as relevance
FROM posts
WHERE MATCH(title, content) AGAINST('+mysql +optimization -slow' IN BOOLEAN MODE)
ORDER BY relevance DESC;

-- Use query expansion for better results
SELECT 
    title,
    content
FROM posts
WHERE MATCH(title, content) AGAINST('mysql optimization' WITH QUERY EXPANSION);
```

### The "Search Vector" Pattern
```sql
-- Create search vectors for better performance
CREATE TABLE posts_search (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    post_id BIGINT NOT NULL,
    search_vector TEXT GENERATED ALWAYS AS (
        CONCAT_WS(' ', title, content, tags)
    ) STORED,
    FULLTEXT INDEX idx_search_vector (search_vector),
    INDEX idx_post_id (post_id)
);

-- Use the search vector
SELECT 
    p.title,
    p.content,
    MATCH(ps.search_vector) AGAINST('search term') as relevance
FROM posts p
JOIN posts_search ps ON p.id = ps.post_id
WHERE MATCH(ps.search_vector) AGAINST('search term')
ORDER BY relevance DESC;
```

## 🚀 The "Partition" Optimization

### The "Partition Pruning" Hack
```sql
-- Use partition pruning for better performance
CREATE TABLE orders_partitioned (
    id BIGINT AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);

-- Query will only scan relevant partitions
SELECT * FROM orders_partitioned 
WHERE order_date >= '2024-01-01' 
AND order_date < '2024-02-01';
```

## 🔥 The "Query Cache" Hacks

### The "Application-Level Cache" Pattern
```sql
-- Use application-level caching for expensive queries
CREATE TABLE query_cache (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value JSON NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_expires (expires_at)
);

-- Cache expensive query results
INSERT INTO query_cache (cache_key, cache_value, expires_at) VALUES
('user_stats_123', '{"order_count": 15, "total_amount": 1250.50}', DATE_ADD(NOW(), INTERVAL 1 HOUR));

-- Use cached results
SELECT 
    CASE 
        WHEN expires_at > NOW() THEN cache_value
        ELSE NULL
    END as cached_result
FROM query_cache 
WHERE cache_key = 'user_stats_123';
```

## 🎯 The "Query Plan" Analysis

### The "EXPLAIN" Mastery
```sql
-- Analyze query plans
EXPLAIN FORMAT=JSON
SELECT u.name, COUNT(o.id) as order_count
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 'active'
GROUP BY u.id;

-- Use EXPLAIN ANALYZE for detailed analysis
EXPLAIN ANALYZE
SELECT u.name, COUNT(o.id) as order_count
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 'active'
GROUP BY u.id;
```

### The "Query Plan" Optimization
```sql
-- Force specific query plans
SELECT /*+ NO_INDEX(users) */ 
    * FROM users 
WHERE email = 'user@example.com';

-- Use specific join algorithms
SELECT /*+ BNL(users, orders) */ 
    u.name, o.order_date
FROM users u
JOIN orders o ON u.id = o.user_id;
```

These are the real-world query optimization hacks that product engineers use to get that extra performance boost! 🚀
