# PostgreSQL Indexing

## Overview

Indexes in PostgreSQL are data structures that improve the speed of data retrieval operations on database tables. They work by providing quick access to data without having to scan every row in a table. Understanding different index types and their appropriate use cases is crucial for database performance optimization.

## Table of Contents

1. [Index Fundamentals](#index-fundamentals)
2. [B-Tree Indexes](#b-tree-indexes)
3. [Hash Indexes](#hash-indexes)
4. [GIN Indexes](#gin-indexes)
5. [GiST Indexes](#gist-indexes)
6. [SP-GiST Indexes](#sp-gist-indexes)
7. [BRIN Indexes](#brin-indexes)
8. [Partial and Expression Indexes](#partial-and-expression-indexes)
9. [Index Maintenance](#index-maintenance)
10. [Index Monitoring](#index-monitoring)
11. [Enterprise Patterns](#enterprise-patterns)

## Index Fundamentals

### What is an Index?

An index is a data structure that improves the speed of data retrieval operations. It works like an index in a book - instead of scanning every page, you can quickly find the information you need.

### Index Types Overview

- **B-Tree**: Default index type, good for equality and range queries
- **Hash**: Best for simple equality comparisons
- **GIN**: Generalized Inverted Index, excellent for arrays, full-text search, and JSON
- **GiST**: Generalized Search Tree, good for geometric data and custom operators
- **SP-GiST**: Space-Partitioned GiST, efficient for certain kinds of clustered data
- **BRIN**: Block Range Index, efficient for large tables with naturally ordered data

### Basic Index Operations

```sql
-- Create index
CREATE INDEX idx_table_column ON table_name (column_name);

-- Create unique index
CREATE UNIQUE INDEX idx_unique_email ON users (email);

-- Create index with specific name
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date);

-- Drop index
DROP INDEX idx_table_column;

-- Drop index if exists
DROP INDEX IF EXISTS idx_table_column;

-- Check index usage
SELECT * FROM pg_stat_user_indexes WHERE relname = 'table_name';
```

## B-Tree Indexes

### B-Tree Index Characteristics

B-Tree indexes are the default and most commonly used index type in PostgreSQL. They are suitable for:

- Equality comparisons (=)
- Range queries (<, >, <=, >=, BETWEEN)
- Prefix matching (LIKE 'prefix%')
- ORDER BY operations
- NULL value handling

### Creating B-Tree Indexes

```sql
-- Single column B-Tree index (default)
CREATE INDEX idx_users_email ON users (email);

-- Multi-column index
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date);

-- Unique B-Tree index
CREATE UNIQUE INDEX idx_unique_product_sku ON products (sku);

-- Descending index
CREATE INDEX idx_posts_created_desc ON posts (created_at DESC);

-- NULLS FIRST/LAST
CREATE INDEX idx_nullable_column_nulls_first ON table_name (column_name NULLS FIRST);
CREATE INDEX idx_nullable_column_nulls_last ON table_name (column_name NULLS LAST);

-- Index with fill factor
CREATE INDEX idx_table_column ON table_name (column_name) WITH (fillfactor = 70);
```

### B-Tree Index Best Practices

```sql
-- Index foreign keys for JOIN performance
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);

-- Index for common WHERE clauses
CREATE INDEX idx_users_status_active ON users (status) WHERE is_active = true;

-- Index for sorting
CREATE INDEX idx_products_price_category ON products (category_id, price DESC);

-- Covering index (includes all columns needed for a query)
CREATE INDEX idx_users_covering ON users (last_name, first_name, email, phone);

-- Partial index for selective conditions
CREATE INDEX idx_high_value_orders ON orders (total_amount)
WHERE total_amount > 1000 AND status = 'completed';
```

### Multi-Column Index Considerations

```sql
-- Index column order matters for query performance
CREATE INDEX idx_orders_compound ON orders (customer_id, status, order_date);

-- This index can be used for:
SELECT * FROM orders WHERE customer_id = 123;                           -- Yes
SELECT * FROM orders WHERE customer_id = 123 AND status = 'pending';   -- Yes
SELECT * FROM orders WHERE customer_id = 123 AND status = 'pending' AND order_date > '2024-01-01'; -- Yes

-- But NOT for these queries:
SELECT * FROM orders WHERE status = 'pending';                         -- No
SELECT * FROM orders WHERE order_date > '2024-01-01';                  -- No

-- For different query patterns, consider separate indexes
CREATE INDEX idx_orders_status ON orders (status);
CREATE INDEX idx_orders_date ON orders (order_date);
```

## Hash Indexes

### Hash Index Characteristics

Hash indexes are optimized for simple equality comparisons and are generally faster than B-Tree for this specific use case.

```sql
-- Create hash index
CREATE INDEX idx_users_email_hash ON users USING hash (email);

-- Hash indexes are good for:
SELECT * FROM users WHERE email = 'user@example.com';

-- But not good for:
SELECT * FROM users WHERE email LIKE 'user%';
SELECT * FROM users WHERE email > 'm';
SELECT * FROM users ORDER BY email;
```

### Hash Index Limitations

```sql
-- Hash indexes don't support:
-- Range queries
-- Pattern matching with LIKE
-- Sorting operations
-- Multi-column indexes
-- Unique constraints (use unique hash index instead)

-- Hash indexes are not WAL-logged before PostgreSQL 10
-- They need to be rebuilt after a crash
```

## GIN Indexes

### GIN Index Characteristics

Generalized Inverted Index (GIN) is perfect for:

- Array columns
- Full-text search
- JSONB operations
- hstore operations
- Multiple values per row

### Array Indexing with GIN

```sql
-- Create table with array column
CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255),
    tags TEXT[],
    keywords TEXT[]
);

-- Create GIN index for arrays
CREATE INDEX idx_articles_tags ON articles USING gin (tags);
CREATE INDEX idx_articles_keywords ON articles USING gin (keywords);

-- Queries that benefit from GIN index
SELECT * FROM articles WHERE 'postgresql' = ANY (tags);
SELECT * FROM articles WHERE tags && ARRAY['postgresql', 'database'];
SELECT * FROM articles WHERE tags @> ARRAY['postgresql'];
SELECT * FROM articles WHERE tags <@ ARRAY['postgresql', 'sql'];

-- Multi-array search
SELECT * FROM articles
WHERE tags && ARRAY['postgresql', 'performance']
   OR keywords && ARRAY['optimization', 'indexing'];
```

### Full-Text Search with GIN

```sql
-- Create table for documents
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255),
    content TEXT,
    search_vector TSVECTOR
);

-- Create GIN index for full-text search
CREATE INDEX idx_documents_search ON documents USING gin (search_vector);

-- Update search vector (can be done with trigger)
UPDATE documents SET search_vector = to_tsvector('english', title || ' ' || content);

-- Full-text search queries
SELECT * FROM documents WHERE search_vector @@ to_tsquery('english', 'database & performance');
SELECT * FROM documents WHERE search_vector @@ plainto_tsquery('english', 'postgresql indexing');

-- Ranked search results
SELECT id, title,
       ts_rank(search_vector, to_tsquery('english', 'database performance')) AS rank
FROM documents
WHERE search_vector @@ to_tsquery('english', 'database performance')
ORDER BY rank DESC;
```

### JSONB Indexing with GIN

```sql
-- Create table with JSONB column
CREATE TABLE user_profiles (
    user_id INTEGER PRIMARY KEY,
    profile_data JSONB
);

-- Create GIN index for JSONB
CREATE INDEX idx_user_profiles_gin ON user_profiles USING gin (profile_data);

-- JSONB queries that use the index
SELECT * FROM user_profiles WHERE profile_data ? 'email';
SELECT * FROM user_profiles WHERE profile_data ?| ARRAY['email', 'phone'];
SELECT * FROM user_profiles WHERE profile_data ?& ARRAY['first_name', 'last_name'];
SELECT * FROM user_profiles WHERE profile_data @> '{"city": "New York"}';
SELECT * FROM user_profiles WHERE profile_data <@ '{"city": "New York", "state": "NY"}';

-- JSONB path operations
SELECT * FROM user_profiles WHERE profile_data #> '{address,city}' = '"New York"';
SELECT * FROM user_profiles WHERE profile_data #>> '{address,city}' = 'New York';

-- Expression indexes for specific JSON paths
CREATE INDEX idx_user_profiles_city ON user_profiles ((profile_data ->> 'city'));
CREATE INDEX idx_user_profiles_age ON user_profiles ((profile_data ->> 'age')::INTEGER);
```

## GiST Indexes

### GiST Index Characteristics

Generalized Search Tree (GiST) is suitable for:

- Geometric data types
- Range types
- Full-text search (alternative to GIN)
- Custom data types with operators

### Geometric Data Indexing

```sql
-- Create extension for geometric types
CREATE EXTENSION postgis;

-- Create table with geometric data
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    coordinates GEOMETRY(Point, 4326)
);

-- Create GiST index for geometric data
CREATE INDEX idx_locations_coordinates ON locations USING gist (coordinates);

-- Geometric queries
SELECT * FROM locations WHERE ST_DWithin(coordinates, ST_Point(-122.4194, 37.7749), 1000);
SELECT * FROM locations ORDER BY coordinates <-> ST_Point(-122.4194, 37.7749) LIMIT 10;

-- Range queries with GiST
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255),
    event_period TSRANGE
);

CREATE INDEX idx_events_period ON events USING gist (event_period);

-- Range queries
SELECT * FROM events WHERE event_period && '[2024-01-01, 2024-12-31]'::TSRANGE;
SELECT * FROM events WHERE event_period &< '[2024-06-01, 2024-06-30]'::TSRANGE;
```

### Full-Text Search with GiST

```sql
-- GiST for full-text search (alternative to GIN)
CREATE INDEX idx_documents_search_gist ON documents USING gist (search_vector);

-- GiST is often faster for highly dynamic data
-- GIN is generally better for static data
```

### Custom Operator Classes

```sql
-- GiST supports custom operator classes for specialized indexing
-- Example: trigram matching for fuzzy string search
CREATE EXTENSION pg_trgm;

CREATE INDEX idx_products_name_trgm ON products USING gist (name gist_trgm_ops);

-- Fuzzy search queries
SELECT * FROM products WHERE name % 'postgres';  -- Similarity search
SELECT * FROM products WHERE name LIKE '%database%';  -- Uses trigram index
```

## SP-GiST Indexes

### SP-GiST Characteristics

Space-Partitioned GiST is efficient for:

- Non-balanced search trees
- Clustered data (network addresses, phone numbers)
- Text search with different operator classes

```sql
-- SP-GiST for quad-tree like structures
CREATE INDEX idx_points_quad ON points USING spgist (point);

-- Network address indexing
CREATE TABLE network_hosts (
    id SERIAL PRIMARY KEY,
    ip_address INET,
    hostname VARCHAR(255)
);

CREATE INDEX idx_network_hosts_ip ON network_hosts USING spgist (ip_address);

-- IP address queries
SELECT * FROM network_hosts WHERE ip_address << '192.168.1.0/24';
SELECT * FROM network_hosts WHERE ip_address >>= '192.168.1.1';
```

## BRIN Indexes

### BRIN Index Characteristics

Block Range Index (BRIN) is efficient for:

- Large tables with naturally ordered data
- Time-series data
- Sequential data access patterns
- When you need smaller index size

```sql
-- BRIN index for time-series data
CREATE TABLE sensor_readings (
    sensor_id INTEGER,
    reading_time TIMESTAMP WITH TIME ZONE,
    temperature DECIMAL(5,2),
    humidity DECIMAL(5,2)
) PARTITION BY RANGE (reading_time);

CREATE INDEX idx_sensor_readings_time ON sensor_readings USING brin (reading_time);

-- BRIN works well with partitioning
-- Much smaller than B-Tree for large datasets
-- Efficient for range queries on ordered data

-- BRIN index with pages per range
CREATE INDEX idx_sensor_readings_time_brin ON sensor_readings USING brin (reading_time) WITH (pages_per_range = 128);
```

### BRIN vs B-Tree Comparison

```sql
-- B-Tree: Precise, good for random access, larger storage
-- BRIN: Approximate, good for sequential access, smaller storage

-- BRIN is ideal for:
-- Tables larger than RAM
-- Data that is naturally ordered
-- Range queries on the indexed column
-- When index maintenance cost is a concern
```

## Partial and Expression Indexes

### Partial Indexes

```sql
-- Index only specific rows to reduce size and improve performance
CREATE INDEX idx_active_users_email ON users (email) WHERE is_active = true;

-- Multiple partial indexes for different statuses
CREATE INDEX idx_pending_orders ON orders (order_date) WHERE status = 'pending';
CREATE INDEX idx_completed_orders ON orders (order_date) WHERE status = 'completed';

-- Partial index for NULL values
CREATE INDEX idx_users_phone_not_null ON users (phone) WHERE phone IS NOT NULL;

-- Complex conditions
CREATE INDEX idx_high_value_recent_orders ON orders (customer_id, total_amount)
WHERE total_amount > 500 AND order_date > CURRENT_DATE - INTERVAL '30 days';
```

### Expression Indexes

```sql
-- Index on computed expressions
CREATE INDEX idx_users_full_name ON users ((first_name || ' ' || last_name));

-- Case-insensitive index
CREATE INDEX idx_products_name_lower ON products (lower(name));

-- Date truncation index
CREATE INDEX idx_orders_month ON orders (date_trunc('month', order_date));

-- JSON path expression index
CREATE INDEX idx_profiles_city ON user_profiles ((profile_data ->> 'city'));

-- Mathematical expression index
CREATE INDEX idx_products_taxed_price ON products ((price * 1.08));

-- Array length index
CREATE INDEX idx_posts_tag_count ON posts (array_length(tags, 1));

-- Query using expression index
SELECT * FROM users WHERE lower(first_name || ' ' || last_name) LIKE 'john%';
SELECT * FROM orders WHERE date_trunc('month', order_date) = '2024-01-01';
```

### Functional Indexes

```sql
-- Index on function results
CREATE INDEX idx_users_age ON users (extract(year from age(birth_date)));

-- Custom function index
CREATE OR REPLACE FUNCTION calculate_order_priority(order_row orders)
RETURNS INTEGER AS $$
BEGIN
    RETURN CASE
        WHEN order_row.total_amount > 1000 THEN 1
        WHEN order_row.total_amount > 100 THEN 2
        ELSE 3
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE INDEX idx_orders_priority ON orders (calculate_order_priority(orders.*));

-- Usage
SELECT * FROM orders ORDER BY calculate_order_priority(orders.*);
```

## Index Maintenance

### Index Statistics and Analysis

```sql
-- View index usage statistics
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Index size information
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;

-- Unused indexes (be careful with dropping)
SELECT
    indexrelname,
    tablename,
    idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Index Rebuilding and Maintenance

```sql
-- Rebuild index (for B-Tree corruption)
REINDEX INDEX idx_table_column;

-- Rebuild all indexes on a table
REINDEX TABLE table_name;

-- Concurrent rebuild (doesn't block reads/writes)
CREATE INDEX CONCURRENTLY new_idx_name ON table_name (column_name);
DROP INDEX CONCURRENTLY old_idx_name;
ALTER INDEX new_idx_name RENAME TO old_idx_name;

-- Update index statistics
ANALYZE table_name;

-- Vacuum for index maintenance
VACUUM ANALYZE table_name;

-- Reindex with different fill factor
CREATE INDEX idx_new ON table_name (column_name) WITH (fillfactor = 80);
DROP INDEX idx_old;
ALTER INDEX idx_new RENAME TO idx_old;
```

### Index Storage Parameters

```sql
-- Fill factor for B-Tree indexes
CREATE INDEX idx_table_column ON table_name (column_name) WITH (fillfactor = 80);

-- Autovacuum settings for indexes
ALTER INDEX idx_table_column SET (autovacuum_vacuum_scale_factor = 0.1);
ALTER INDEX idx_table_column SET (autovacuum_analyze_scale_factor = 0.05);

-- Buffering strategy for GIN indexes
CREATE INDEX idx_array_column ON table_name USING gin (array_column) WITH (gin_pending_list_limit = 4096);
```

## Index Monitoring

### Query Performance Analysis

```sql
-- Explain query execution plan
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE email = 'test@example.com';

-- Check if index is being used
EXPLAIN SELECT * FROM orders WHERE customer_id = 123 AND order_date > '2024-01-01';

-- Index usage in complex queries
EXPLAIN SELECT u.name, COUNT(o.id)
FROM users u
LEFT JOIN orders o ON u.id = o.customer_id
WHERE u.created_at > '2024-01-01'
GROUP BY u.id, u.name
HAVING COUNT(o.id) > 5;
```

### Index Effectiveness Metrics

```sql
-- Calculate index hit ratio
SELECT
    sum(idx_blks_hit) / (sum(idx_blks_hit) + sum(idx_blks_read))::float AS index_hit_ratio
FROM pg_statio_user_indexes;

-- Most used indexes
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC
LIMIT 20;

-- Index bloat estimation
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Automated Index Recommendations

```sql
-- Create extension for index recommendations
CREATE EXTENSION pg_stat_statements;

-- Query for slow queries that might benefit from indexes
SELECT
    query,
    calls,
    total_time / calls AS avg_time,
    rows / calls AS avg_rows
FROM pg_stat_statements
WHERE query LIKE '%SELECT%'
  AND total_time / calls > 100  -- Slow queries
ORDER BY total_time DESC
LIMIT 10;

-- Missing index suggestions (requires analysis of query patterns)
-- Look for sequential scans on large tables
SELECT
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch
FROM pg_stat_user_tables
WHERE seq_scan > idx_scan * 10  -- Many more sequential than index scans
ORDER BY seq_tup_read DESC;
```

## Enterprise Patterns

### Composite Index Strategies

```sql
-- E-commerce index strategy
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL,
    order_date TIMESTAMP WITH TIME ZONE NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    shipping_address_id INTEGER,
    billing_address_id INTEGER
);

-- Primary access patterns
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date DESC);
CREATE INDEX idx_orders_status_date ON orders (status, order_date DESC);
CREATE INDEX idx_orders_date_total ON orders (order_date DESC, total_amount DESC);

-- Covering indexes for common queries
CREATE INDEX idx_orders_customer_covering ON orders (customer_id, status, order_date, total_amount);
CREATE INDEX idx_orders_status_covering ON orders (status, customer_id, order_date);

-- Partial indexes for active data
CREATE INDEX idx_active_orders ON orders (customer_id, order_date DESC, total_amount)
WHERE status NOT IN ('cancelled', 'delivered');
```

### Time-Series Index Patterns

```sql
-- Time-series table with proper indexing
CREATE TABLE sensor_data (
    sensor_id INTEGER NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    value DECIMAL(10,4) NOT NULL,
    quality_score INTEGER CHECK (quality_score BETWEEN 0 AND 100),
    metadata JSONB
) PARTITION BY RANGE (timestamp);

-- Primary time-series index
CREATE INDEX idx_sensor_data_time ON sensor_data (sensor_id, timestamp DESC);

-- Additional indexes for different query patterns
CREATE INDEX idx_sensor_data_value ON sensor_data (sensor_id, value) WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '30 days';
CREATE INDEX idx_sensor_data_quality ON sensor_data (quality_score) WHERE quality_score < 80;

-- BRIN index for historical data (older partitions)
CREATE INDEX idx_sensor_data_time_brin ON sensor_data USING brin (timestamp) WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '1 year';

-- GIN index for metadata searches
CREATE INDEX idx_sensor_data_metadata ON sensor_data USING gin (metadata) WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '90 days';
```

### Multi-Tenant Index Patterns

```sql
-- Multi-tenant application indexing
CREATE TABLE tenant_data (
    tenant_id INTEGER NOT NULL,
    record_id UUID NOT NULL DEFAULT gen_random_uuid(),
    data_type VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    data JSONB NOT NULL,
    PRIMARY KEY (tenant_id, record_id)
);

-- Tenant-isolated indexes
CREATE INDEX idx_tenant_data_type_created ON tenant_data (tenant_id, data_type, created_at DESC);
CREATE INDEX idx_tenant_data_updated ON tenant_data (tenant_id, updated_at DESC);

-- Global indexes (careful with performance)
CREATE INDEX idx_tenant_data_global_type ON tenant_data (data_type, tenant_id) WHERE data_type IN ('user', 'account');

-- Partial indexes for active tenants
CREATE INDEX idx_active_tenant_data ON tenant_data (tenant_id, data_type, updated_at DESC)
WHERE tenant_id IN (SELECT id FROM tenants WHERE is_active = true);
```

### Search Engine Index Patterns

```sql
-- Advanced search indexing
CREATE TABLE content (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT,
    tags TEXT[],
    categories VARCHAR(100)[],
    published_at TIMESTAMP WITH TIME ZONE,
    author_id INTEGER,
    metadata JSONB,
    search_vector TSVECTOR
);

-- Full-text search index
CREATE INDEX idx_content_search ON content USING gin (search_vector);

-- Tag and category indexes
CREATE INDEX idx_content_tags ON content USING gin (tags);
CREATE INDEX idx_content_categories ON content USING gin (categories);

-- Metadata index
CREATE INDEX idx_content_metadata ON content USING gin (metadata);

-- Composite search index
CREATE INDEX idx_content_composite ON content (published_at DESC, author_id)
WHERE published_at IS NOT NULL;

-- Expression indexes for computed fields
CREATE INDEX idx_content_word_count ON content (array_length(regexp_split_to_array(content, '\s+'), 1));
CREATE INDEX idx_content_reading_time ON content ((array_length(regexp_split_to_array(content, '\s+'), 1) / 200)); -- 200 words per minute

-- Update search vector function
CREATE OR REPLACE FUNCTION update_content_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
                        setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'B') ||
                        setweight(to_tsvector('english', array_to_string(NEW.tags, ' ')), 'C');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_content_search_vector
    BEFORE INSERT OR UPDATE ON content
    FOR EACH ROW EXECUTE FUNCTION update_content_search_vector();
```

### Index Maintenance Automation

```sql
-- Automated index maintenance function
CREATE OR REPLACE FUNCTION maintain_table_indexes(table_name_param TEXT)
RETURNS TABLE (
    index_name TEXT,
    action_taken TEXT,
    details TEXT
) AS $$
DECLARE
    index_record RECORD;
    index_size BIGINT;
    table_size BIGINT;
    bloat_ratio FLOAT;
BEGIN
    -- Get table size
    SELECT pg_relation_size(table_name_param::regclass) INTO table_size;

    FOR index_record IN
        SELECT
            schemaname,
            indexname,
            indexrelname,
            idx_scan,
            pg_relation_size(indexrelid) AS index_size
        FROM pg_stat_user_indexes
        WHERE tablename = table_name_param
    LOOP
        index_size := index_record.index_size;

        -- Check for unused indexes
        IF index_record.idx_scan = 0 AND index_size > 10000000 THEN -- 10MB
            -- Consider dropping unused large indexes
            RETURN QUERY SELECT
                index_record.indexname,
                'CONSIDER_DROP'::TEXT,
                format('Unused index, size: %s', pg_size_pretty(index_size));

        -- Check for bloated indexes (simplified check)
        ELSIF index_size > table_size * 2 THEN
            RETURN QUERY SELECT
                index_record.indexname,
                'REINDEX'::TEXT,
                format('Index size %s vs table size %s',
                      pg_size_pretty(index_size), pg_size_pretty(table_size));
        ELSE
            RETURN QUERY SELECT
                index_record.indexname,
                'OK'::TEXT,
                format('Index size: %s, scans: %s',
                      pg_size_pretty(index_size), index_record.idx_scan);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT * FROM maintain_table_indexes('large_table');
```

This comprehensive guide covers PostgreSQL indexing from basic concepts to advanced enterprise patterns, including different index types, maintenance strategies, and performance optimization techniques.
