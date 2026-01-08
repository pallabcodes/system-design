-- Cassandra Examples and Patterns
-- Comprehensive Cassandra CQL implementations for time-series, analytics, and high-write workloads

-- ===========================================
-- KEYSPACE AND TABLE CREATION
-- ===========================================

-- Create keyspace with replication strategy
CREATE KEYSPACE ecommerce
WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3,
    'datacenter2': 3
} AND DURABLE_WRITES = true;

-- Use keyspace
USE ecommerce;

-- Create table with primary key
CREATE TABLE products (
    product_id UUID,
    category TEXT,
    name TEXT,
    price DECIMAL,
    description TEXT,
    tags SET<TEXT>,
    attributes MAP<TEXT, TEXT>,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    PRIMARY KEY (product_id)
);

-- Create table with composite partition key
CREATE TABLE orders (
    customer_id UUID,
    order_id UUID,
    order_date DATE,
    status TEXT,
    total_amount DECIMAL,
    items LIST<FROZEN<order_item>>,
    shipping_address FROZEN<address>,
    billing_address FROZEN<address>,
    created_at TIMESTAMP,
    PRIMARY KEY ((customer_id, order_date), order_id)
) WITH CLUSTERING ORDER BY (order_id DESC);

-- Create table for time-series data
CREATE TABLE sensor_readings (
    sensor_id UUID,
    date DATE,
    timestamp TIMESTAMP,
    temperature DOUBLE,
    humidity DOUBLE,
    pressure DOUBLE,
    location TEXT,
    metadata MAP<TEXT, TEXT>,
    PRIMARY KEY ((sensor_id, date), timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);

-- User-defined types
CREATE TYPE address (
    street TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,
    country TEXT
);

CREATE TYPE order_item (
    product_id UUID,
    product_name TEXT,
    quantity INT,
    unit_price DECIMAL,
    total_price DECIMAL
);

-- ===========================================
-- DATA MANIPULATION
-- ===========================================

-- Insert data
INSERT INTO products (product_id, category, name, price, description, tags, attributes, created_at)
VALUES (
    uuid(),
    'electronics',
    'Wireless Headphones',
    199.99,
    'High-quality wireless headphones with noise cancellation',
    {'wireless', 'bluetooth', 'noise-cancelling'},
    {'brand': 'AudioTech', 'color': 'black', 'warranty': '2 years'},
    toTimestamp(now())
);

-- Insert with TTL (Time To Live)
INSERT INTO products (product_id, category, name, price, created_at)
VALUES (uuid(), 'temp', 'Temporary Product', 9.99, toTimestamp(now()))
USING TTL 3600; -- Expires in 1 hour

-- Insert into orders table
INSERT INTO orders (
    customer_id, order_id, order_date, status, total_amount,
    items, shipping_address, created_at
) VALUES (
    uuid(), uuid(), '2024-01-15',
    'confirmed', 299.97,
    [
        {
            product_id: uuid(),
            product_name: 'Wireless Headphones',
            quantity: 1,
            unit_price: 199.99,
            total_price: 199.99
        },
        {
            product_id: uuid(),
            product_name: 'Phone Case',
            quantity: 1,
            unit_price: 99.98,
            total_price: 99.98
        }
    ],
    {
        street: '123 Main St',
        city: 'Springfield',
        state: 'IL',
        zip_code: '62701',
        country: 'USA'
    },
    toTimestamp(now())
);

-- Insert time-series data
INSERT INTO sensor_readings (sensor_id, date, timestamp, temperature, humidity, pressure, location)
VALUES (
    uuid(),
    '2024-01-15',
    toTimestamp(now()),
    23.5,
    65.2,
    1013.25,
    'warehouse-a'
);

-- ===========================================
-- DATA RETRIEVAL
-- ===========================================

-- Select all products
SELECT * FROM products;

-- Select specific columns
SELECT product_id, name, price FROM products WHERE product_id = ?;

-- Select with filtering
SELECT * FROM products WHERE category = 'electronics' ALLOW FILTERING;

-- Select orders for a customer on a specific date
SELECT * FROM orders
WHERE customer_id = ?
AND order_date = '2024-01-15';

-- Select recent orders for a customer (uses clustering order)
SELECT * FROM orders
WHERE customer_id = ?
LIMIT 10;

-- Select sensor readings for a date range
SELECT * FROM sensor_readings
WHERE sensor_id = ?
AND date = '2024-01-15'
AND timestamp >= '2024-01-15 00:00:00'
AND timestamp <= '2024-01-15 23:59:59';

-- ===========================================
-- ADVANCED QUERIES AND PATTERNS
-- ===========================================

-- Batch operations
BEGIN BATCH
    INSERT INTO products (product_id, category, name, price, created_at)
    VALUES (uuid(), 'books', 'Cassandra Guide', 49.99, toTimestamp(now()));

    UPDATE products SET price = 179.99 WHERE product_id = ?;

    DELETE FROM products WHERE product_id = ?;
APPLY BATCH;

-- Conditional updates (lightweight transactions)
UPDATE products
SET price = 189.99
WHERE product_id = ?
IF price = 199.99;

-- Counters for analytics
CREATE TABLE page_views (
    page_id TEXT,
    date DATE,
    views COUNTER,
    PRIMARY KEY (page_id, date)
);

UPDATE page_views SET views = views + 1 WHERE page_id = '/products' AND date = '2024-01-15';

SELECT * FROM page_views WHERE page_id = '/products';

-- ===========================================
-- INDEXING AND PERFORMANCE
-- ===========================================

-- Create secondary index
CREATE INDEX idx_products_category ON products (category);

-- Create custom index for collections
CREATE INDEX idx_products_tags ON products (tags);

-- Materialized view for different query patterns
CREATE MATERIALIZED VIEW products_by_category AS
    SELECT product_id, category, name, price, created_at
    FROM products
    WHERE category IS NOT NULL AND product_id IS NOT NULL
    PRIMARY KEY (category, product_id);

-- Query using materialized view
SELECT * FROM products_by_category WHERE category = 'electronics';

-- ===========================================
-- ANALYTICS AND AGGREGATIONS
-- ===========================================

-- Create table for analytics
CREATE TABLE sales_analytics (
    date DATE,
    category TEXT,
    product_id UUID,
    total_sales DECIMAL,
    units_sold INT,
    avg_price DECIMAL,
    PRIMARY KEY ((date, category), product_id)
);

-- Aggregate sales data (would typically be done by application or Spark)
INSERT INTO sales_analytics (date, category, product_id, total_sales, units_sold, avg_price)
VALUES ('2024-01-15', 'electronics', uuid(), 1999.90, 10, 199.99);

-- Time-series analytics queries
SELECT date, SUM(total_sales), SUM(units_sold)
FROM sales_analytics
WHERE date >= '2024-01-01' AND date <= '2024-01-15'
GROUP BY date;

-- ===========================================
-- TIME-SERIES PATTERNS
-- ===========================================

-- IoT sensor data pattern
CREATE TABLE iot_readings (
    device_id UUID,
    bucket TEXT,  -- e.g., '2024-01-15-10' for hourly buckets
    timestamp TIMESTAMP,
    sensor_type TEXT,
    value DOUBLE,
    unit TEXT,
    metadata MAP<TEXT, TEXT>,
    PRIMARY KEY ((device_id, bucket), timestamp, sensor_type)
) WITH CLUSTERING ORDER BY (timestamp DESC, sensor_type ASC);

-- Insert sensor readings with bucketing
INSERT INTO iot_readings (device_id, bucket, timestamp, sensor_type, value, unit)
VALUES (
    uuid(),
    '2024-01-15-10',
    toTimestamp(now()),
    'temperature',
    23.5,
    'celsius'
);

-- Query recent readings for a device
SELECT * FROM iot_readings
WHERE device_id = ?
AND bucket = '2024-01-15-10'
LIMIT 100;

-- ===========================================
-- SOCIAL MEDIA PATTERNS
-- ===========================================

-- User timeline pattern
CREATE TABLE user_timeline (
    user_id UUID,
    tweet_id UUID,
    author_id UUID,
    content TEXT,
    hashtags SET<TEXT>,
    mentions SET<TEXT>,
    created_at TIMESTAMP,
    likes COUNTER,
    retweets COUNTER,
    PRIMARY KEY (user_id, created_at, tweet_id)
) WITH CLUSTERING ORDER BY (created_at DESC, tweet_id DESC);

-- Insert tweet
INSERT INTO user_timeline (user_id, tweet_id, author_id, content, hashtags, created_at)
VALUES (
    uuid(),
    uuid(),
    uuid(),
    'Learning Cassandra is awesome! #nosql #database',
    {'nosql', 'database'},
    toTimestamp(now())
);

-- Get user's timeline
SELECT * FROM user_timeline WHERE user_id = ? LIMIT 50;

-- User feed pattern (fan-out on write)
CREATE TABLE user_feed (
    user_id UUID,
    tweet_id UUID,
    author_id UUID,
    author_username TEXT,
    content TEXT,
    created_at TIMESTAMP,
    PRIMARY KEY (user_id, created_at, tweet_id)
) WITH CLUSTERING ORDER BY (created_at DESC, tweet_id DESC);

-- When user A follows user B, copy B's recent tweets to A's feed
-- This would be handled by application logic

-- ===========================================
-- E-COMMERCE PATTERNS
-- ===========================================

-- Product catalog with variants
CREATE TABLE product_catalog (
    product_id UUID,
    variant_id UUID,
    sku TEXT,
    name TEXT,
    description TEXT,
    category TEXT,
    price DECIMAL,
    inventory_quantity INT,
    attributes MAP<TEXT, TEXT>,
    images LIST<TEXT>,
    PRIMARY KEY (product_id, variant_id)
);

-- Shopping cart
CREATE TABLE shopping_cart (
    user_id UUID,
    product_id UUID,
    variant_id UUID,
    quantity INT,
    added_at TIMESTAMP,
    PRIMARY KEY (user_id, product_id, variant_id)
);

-- Inventory management
CREATE TABLE inventory (
    product_id UUID,
    warehouse_id UUID,
    quantity INT,
    reserved_quantity INT,
    last_updated TIMESTAMP,
    PRIMARY KEY ((product_id, warehouse_id))
);

-- Update inventory with conditional write
UPDATE inventory
SET quantity = quantity - 5, last_updated = toTimestamp(now())
WHERE product_id = ? AND warehouse_id = ?
IF quantity >= 5;

-- ===========================================
-- LOGGING AND AUDIT PATTERNS
-- ===========================================

-- Application logs
CREATE TABLE application_logs (
    application_id TEXT,
    date DATE,
    timestamp TIMESTAMP,
    level TEXT,
    message TEXT,
    thread_id TEXT,
    user_id UUID,
    session_id UUID,
    metadata MAP<TEXT, TEXT>,
    PRIMARY KEY ((application_id, date), timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);

-- Insert log entry
INSERT INTO application_logs (
    application_id, date, timestamp, level, message, thread_id, user_id, metadata
) VALUES (
    'ecommerce-api',
    '2024-01-15',
    toTimestamp(now()),
    'INFO',
    'User logged in successfully',
    'thread-123',
    uuid(),
    {'ip_address': '192.168.1.1', 'user_agent': 'Mozilla/5.0...'}
);

-- Query logs by date range
SELECT * FROM application_logs
WHERE application_id = 'ecommerce-api'
AND date = '2024-01-15'
AND timestamp >= '2024-01-15 09:00:00'
AND timestamp <= '2024-01-15 17:00:00';

-- ===========================================
-- DATA MODELING PATTERNS
-- ===========================================

-- Wide row pattern for user preferences
CREATE TABLE user_preferences (
    user_id UUID,
    preference_type TEXT,
    preference_key TEXT,
    preference_value TEXT,
    updated_at TIMESTAMP,
    PRIMARY KEY (user_id, preference_type, preference_key)
);

-- Store multiple preferences per user
INSERT INTO user_preferences (user_id, preference_type, preference_key, preference_value, updated_at)
VALUES (uuid(), 'notifications', 'email_marketing', 'true', toTimestamp(now()));

INSERT INTO user_preferences (user_id, preference_type, preference_key, preference_value, updated_at)
VALUES (uuid(), 'display', 'theme', 'dark', toTimestamp(now()));

-- Query all preferences for a user
SELECT * FROM user_preferences WHERE user_id = ?;

-- Time bucket pattern for high-volume data
CREATE TABLE events_by_minute (
    event_type TEXT,
    year INT,
    month INT,
    day INT,
    hour INT,
    minute INT,
    event_id UUID,
    event_data TEXT,
    timestamp TIMESTAMP,
    PRIMARY KEY ((event_type, year, month, day, hour, minute), timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);

-- Insert event with time bucketing
INSERT INTO events_by_minute (
    event_type, year, month, day, hour, minute, event_id, event_data, timestamp
) VALUES (
    'user_action',
    2024, 1, 15, 14, 30,
    uuid(),
    '{"action": "login", "user_id": "123"}',
    toTimestamp(now())
);

-- ===========================================
-- MONITORING AND MAINTENANCE
-- ===========================================

-- Check table statistics
SELECT * FROM system.size_estimates WHERE keyspace_name = 'ecommerce';

-- Check compaction status
SELECT * FROM system.compaction_history LIMIT 10;

-- Check query performance
TRACING ON;
SELECT * FROM products WHERE category = 'electronics' LIMIT 10;
TRACING OFF;

-- Create backup (nodetool snapshot)
-- nodetool snapshot ecommerce

-- Repair data
-- nodetool repair ecommerce

-- ===========================================
-- ADVANCED FEATURES
-- ===========================================

-- User-defined functions (UDFs)
CREATE FUNCTION calculate_distance (lat1 double, lon1 double, lat2 double, lon2 double)
    RETURNS double
    LANGUAGE java
    AS $$
        double earthRadius = 6371; // kilometers
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                   Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                   Math.sin(dLon/2) * Math.sin(dLon/2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        return earthRadius * c;
    $$;

-- User-defined aggregates
CREATE FUNCTION state_group (state tuple<text, int>, val int)
    RETURNS tuple<text, int>
    LANGUAGE java
    AS $$
        return tuple.new(state.get(0, String.class), state.get(1, Integer.class) + val);
    $$;

CREATE AGGREGATE sum_by_category (int)
    SFUNC state_group
    STYPE tuple<text, int>
    INITCOND (null, 0);

-- ===========================================
-- DATA MIGRATION PATTERNS
-- ===========================================

-- Create new table with different structure
CREATE TABLE products_v2 (
    product_id UUID,
    category TEXT,
    name TEXT,
    price DECIMAL,
    description TEXT,
    tags SET<TEXT>,
    attributes MAP<TEXT, TEXT>,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    version INT,  -- New field
    PRIMARY KEY ((category), product_id)
);

-- Migrate data (would typically be done with application or ETL)
INSERT INTO products_v2 (product_id, category, name, price, description, tags, attributes, created_at, updated_at, version)
SELECT product_id, category, name, price, description, tags, attributes, created_at, updated_at, 1
FROM products;

-- ===========================================
-- BEST PRACTICES
-- ===========================================

-- Avoid hot spots with good partition key distribution
-- Use time-based bucketing for time-series data
-- Design for your query patterns (query-first design)
-- Use appropriate data types (avoid text for frequently queried fields)
-- Monitor and tune compaction strategies
-- Use appropriate consistency levels for your use case
-- Consider denormalization for read-heavy workloads
-- Use materialized views for alternative query patterns

/*
CASSANDRA DESIGN PRINCIPLES:

1. **Query-First Design**: Design tables based on query patterns, not relationships
2. **Denormalization**: Duplicate data to optimize reads
3. **Partition Key Distribution**: Ensure even data distribution
4. **Clustering Columns**: Use for sorting and range queries
5. **Time Bucketing**: Use for high-volume time-series data
6. **Appropriate Consistency**: Choose consistency levels based on requirements

CASSANDRA IS IDEAL FOR:
- Time-series data (IoT, logs, metrics)
- High-write workloads (event logging, user activity)
- Analytics and reporting
- Content management systems
- Social media platforms
- E-commerce catalogs
- Real-time messaging

TYPICAL USE CASES:
- IoT sensor data storage
- User activity tracking
- Product catalogs
- Social media timelines
- Event logging and analytics
- Messaging systems
- Content delivery networks
*/
