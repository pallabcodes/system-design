# Advanced Querying in PostgreSQL

## Overview

This guide covers advanced querying techniques in PostgreSQL, including Common Table Expressions (CTEs), window functions, recursive queries, full-text search, and performance optimization strategies used by major tech companies.

## Table of Contents

1. [Common Table Expressions (CTEs)](#common-table-expressions-ctes)
2. [Window Functions](#window-functions)
3. [Recursive Queries](#recursive-queries)
4. [Full-Text Search](#full-text-search)
5. [JSON and JSONB Querying](#json-and-jsonb-querying)
6. [Array Operations](#array-operations)
7. [Advanced JOIN Techniques](#advanced-join-techniques)
8. [Query Optimization](#query-optimization)
9. [Enterprise Query Patterns](#enterprise-query-patterns)

## Common Table Expressions (CTEs)

### Basic CTEs

```sql
-- Basic CTE for readability and reusability
WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_date) AS month,
        SUM(total_amount) AS total_sales,
        COUNT(*) AS order_count
    FROM orders
    WHERE order_date >= '2024-01-01'
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT
    month,
    total_sales,
    order_count,
    AVG(total_sales) OVER () AS avg_monthly_sales,
    total_sales - LAG(total_sales) OVER (ORDER BY month) AS sales_growth
FROM monthly_sales
ORDER BY month;
```

### Recursive CTEs

```sql
-- Organization hierarchy with recursive CTE
WITH RECURSIVE employee_hierarchy AS (
    -- Base case: top-level employees (no manager)
    SELECT
        employee_id,
        first_name || ' ' || last_name AS full_name,
        department_id,
        manager_id,
        0 AS hierarchy_level,
        ARRAY[employee_id] AS path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive case: employees with managers
    SELECT
        e.employee_id,
        e.first_name || ' ' || e.last_name,
        e.department_id,
        e.manager_id,
        eh.hierarchy_level + 1,
        eh.path || e.employee_id
    FROM employees e
    JOIN employee_hierarchy eh ON e.manager_id = eh.employee_id
)
SELECT
    employee_id,
    full_name,
    hierarchy_level,
    ARRAY_TO_STRING(path, ' -> ') AS hierarchy_path
FROM employee_hierarchy
ORDER BY path;
```

### Advanced CTE Patterns

```sql
-- Multiple CTEs with data modification
WITH
    -- Calculate customer lifetime value
    customer_ltv AS (
        SELECT
            customer_id,
            SUM(total_amount) AS lifetime_value,
            COUNT(*) AS total_orders,
            MAX(order_date) AS last_order_date
        FROM orders
        GROUP BY customer_id
    ),
    -- Segment customers based on LTV
    customer_segments AS (
        SELECT
            customer_id,
            lifetime_value,
            CASE
                WHEN lifetime_value >= 10000 THEN 'Platinum'
                WHEN lifetime_value >= 5000 THEN 'Gold'
                WHEN lifetime_value >= 1000 THEN 'Silver'
                ELSE 'Bronze'
            END AS segment
        FROM customer_ltv
    ),
    -- Update customer records
    updated_customers AS (
        UPDATE customers
        SET
            segment = cs.segment,
            updated_at = CURRENT_TIMESTAMP
        FROM customer_segments cs
        WHERE customers.customer_id = cs.customer_id
        RETURNING customers.customer_id, customers.segment
    )
SELECT
    uc.customer_id,
    c.first_name,
    c.last_name,
    uc.segment,
    cl.lifetime_value
FROM updated_customers uc
JOIN customers c ON uc.customer_id = c.customer_id
JOIN customer_ltv cl ON uc.customer_id = cl.customer_id
ORDER BY cl.lifetime_value DESC;
```

## Window Functions

### Ranking Functions

```sql
-- ROW_NUMBER, RANK, DENSE_RANK
SELECT
    product_name,
    category_name,
    total_sales,
    ROW_NUMBER() OVER (ORDER BY total_sales DESC) AS sales_rank,
    RANK() OVER (ORDER BY total_sales DESC) AS rank_with_ties,
    DENSE_RANK() OVER (ORDER BY total_sales DESC) AS dense_rank,
    PERCENT_RANK() OVER (ORDER BY total_sales DESC) AS percent_rank
FROM (
    SELECT
        p.name AS product_name,
        c.name AS category_name,
        SUM(oi.quantity * oi.unit_price) AS total_sales
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN order_items oi ON p.product_id = oi.product_id
    GROUP BY p.product_id, p.name, c.name
) product_sales
ORDER BY total_sales DESC;
```

### Aggregate Window Functions

```sql
-- Running totals and moving averages
SELECT
    order_date,
    daily_sales,
    SUM(daily_sales) OVER (ORDER BY order_date) AS running_total,
    AVG(daily_sales) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS weekly_moving_avg,
    SUM(daily_sales) OVER (ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sales
FROM (
    SELECT
        DATE(order_date) AS order_date,
        SUM(total_amount) AS daily_sales
    FROM orders
    WHERE order_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY DATE(order_date)
) daily_sales
ORDER BY order_date;
```

### Frame Clauses

```sql
-- Advanced frame specifications
SELECT
    employee_id,
    department_name,
    salary,
    -- Department average
    AVG(salary) OVER (PARTITION BY department_name) AS dept_avg_salary,
    -- Cumulative salary by department
    SUM(salary) OVER (PARTITION BY department_name ORDER BY salary) AS cumulative_salary,
    -- Rolling average (current + 2 preceding + 2 following)
    AVG(salary) OVER (PARTITION BY department_name ORDER BY salary ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS rolling_avg,
    -- Percentage of department total
    ROUND(100.0 * salary / SUM(salary) OVER (PARTITION BY department_name), 2) AS pct_of_dept_total
FROM employees e
JOIN departments d ON e.department_id = d.department_id
ORDER BY department_name, salary;
```

### FIRST_VALUE, LAST_VALUE, NTH_VALUE

```sql
-- First, last, and nth values in groups
SELECT
    product_id,
    product_name,
    order_date,
    quantity,
    -- First order date for each product
    FIRST_VALUE(order_date) OVER (PARTITION BY product_id ORDER BY order_date) AS first_order_date,
    -- Last order date for each product
    LAST_VALUE(order_date) OVER (PARTITION BY product_id ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_order_date,
    -- Most recent order quantity
    LAST_VALUE(quantity) OVER (PARTITION BY product_id ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS latest_quantity,
    -- Third most recent order
    NTH_VALUE(order_date, 3) OVER (PARTITION BY product_id ORDER BY order_date DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS third_latest_order
FROM (
    SELECT
        p.product_id,
        p.name AS product_name,
        o.order_date,
        oi.quantity
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date >= CURRENT_DATE - INTERVAL '90 days'
) product_orders
ORDER BY product_id, order_date DESC;
```

## Recursive Queries

### Tree Structures

```sql
-- Category hierarchy with recursive query
WITH RECURSIVE category_tree AS (
    -- Base case: root categories
    SELECT
        category_id,
        name,
        parent_category_id,
        1 AS level,
        ARRAY[category_id] AS path,
        name AS path_string
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    -- Recursive case: child categories
    SELECT
        c.category_id,
        c.name,
        c.parent_category_id,
        ct.level + 1,
        ct.path || c.category_id,
        ct.path_string || ' > ' || c.name
    FROM categories c
    JOIN category_tree ct ON c.parent_category_id = ct.category_id
)
SELECT
    category_id,
    name,
    level,
    path_string,
    ARRAY_LENGTH(path, 1) AS depth
FROM category_tree
ORDER BY path;
```

### Graph Traversal

```sql
-- Find all paths between two nodes (social network connections)
WITH RECURSIVE friend_paths AS (
    -- Direct connections
    SELECT
        user_id_1,
        user_id_2,
        1 AS path_length,
        ARRAY[user_id_1, user_id_2] AS path,
        ARRAY[user_id_2] AS visited
    FROM friendships
    WHERE user_id_1 = 1  -- Starting user

    UNION ALL

    -- Extend paths through mutual friends
    SELECT
        fp.user_id_1,
        f.user_id_2,
        fp.path_length + 1,
        fp.path || f.user_id_2,
        fp.visited || f.user_id_2
    FROM friend_paths fp
    JOIN friendships f ON fp.user_id_2 = f.user_id_1
    WHERE f.user_id_2 != ALL(fp.visited)  -- Avoid cycles
    AND fp.path_length < 4  -- Limit path length
)
SELECT
    user_id_1 AS from_user,
    user_id_2 AS to_user,
    path_length,
    ARRAY_TO_STRING(path, ' -> ') AS connection_path
FROM friend_paths
WHERE user_id_2 = 100  -- Target user
ORDER BY path_length;
```

### Bill of Materials (BOM)

```sql
-- Manufacturing BOM with recursive CTE
WITH RECURSIVE bom_explosion AS (
    -- Base case: top-level assemblies
    SELECT
        assembly_id,
        component_id,
        quantity,
        1 AS level,
        ARRAY[component_id] AS component_path,
        quantity AS total_quantity
    FROM bill_of_materials
    WHERE assembly_id = 1001  -- Root assembly

    UNION ALL

    -- Recursive case: sub-assemblies
    SELECT
        bom.assembly_id,
        bom.component_id,
        bom.quantity,
        be.level + 1,
        be.component_path || bom.component_id,
        be.total_quantity * bom.quantity
    FROM bill_of_materials bom
    JOIN bom_explosion be ON bom.assembly_id = be.component_id
    WHERE be.level < 10  -- Prevent infinite recursion
)
SELECT
    assembly_id,
    component_id,
    p.name AS component_name,
    level,
    total_quantity,
    ARRAY_TO_STRING(component_path, ' -> ') AS assembly_path
FROM bom_explosion be
JOIN products p ON be.component_id = p.product_id
ORDER BY component_path, level;
```

## Full-Text Search

### Basic Full-Text Search

```sql
-- Create FTS index on articles
CREATE TABLE articles (
    article_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    author_id INTEGER REFERENCES authors(author_id),
    published_at TIMESTAMP WITH TIME ZONE,
    tags TEXT[]
);

-- Add generated column for search vector
ALTER TABLE articles
ADD COLUMN search_vector TSVECTOR
GENERATED ALWAYS AS (
    to_tsvector('english',
        title || ' ' ||
        content || ' ' ||
        COALESCE(array_to_string(tags, ' '), '')
    )
) STORED;

-- Create GIN index for fast searching
CREATE INDEX idx_articles_search ON articles USING GIN (search_vector);

-- Basic search query
SELECT
    article_id,
    title,
    ts_rank(search_vector, query) AS relevance,
    ts_headline('english', content, query, 'StartSel=<mark>, StopSel=</mark>') AS excerpt
FROM articles, to_tsquery('english', 'database performance') query
WHERE search_vector @@ query
ORDER BY relevance DESC
LIMIT 10;
```

### Advanced FTS Features

```sql
-- Weighted search across multiple columns
ALTER TABLE articles
ADD COLUMN search_vector_weighted TSVECTOR
GENERATED ALWAYS AS (
    setweight(to_tsvector('english', title), 'A') ||
    setweight(to_tsvector('english', content), 'B') ||
    setweight(to_tsvector('english', array_to_string(tags, ' ')), 'C')
) STORED;

-- Search with ranking and filtering
SELECT
    article_id,
    title,
    published_at,
    ts_rank(search_vector_weighted, query, 32) AS rank,  -- 32 = rank normalization
    ts_headline('english', title, query) AS title_highlight,
    ts_headline('english', content, query, 'MaxFragments=2, FragmentDelimiter=...') AS content_snippet
FROM articles, to_tsquery('english', 'postgresql & performance & optimization') query
WHERE search_vector_weighted @@ query
AND published_at >= CURRENT_DATE - INTERVAL '1 year'
ORDER BY rank DESC, published_at DESC
LIMIT 20;
```

### Fuzzy Search and Suggestions

```sql
-- Create trigram extension for fuzzy matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Add trigram indexes
CREATE INDEX idx_articles_title_trgm ON articles USING GIN (title gin_trgm_ops);
CREATE INDEX idx_articles_content_trgm ON articles USING GIN (content gin_trgm_ops);

-- Fuzzy search with similarity
SELECT
    title,
    similarity(title, 'databse performnce') AS title_similarity,
    similarity(content, 'databse performnce') AS content_similarity
FROM articles
WHERE title % 'databse performnce'  -- Similarity threshold
   OR content % 'databse performnce'
ORDER BY GREATEST(title_similarity, content_similarity) DESC
LIMIT 5;

-- Auto-complete suggestions
SELECT DISTINCT
    word,
    similarity(word, 'datab') AS sim
FROM (
    SELECT unnest(string_to_array(lower(title), ' ')) AS word
    FROM articles
    WHERE title ILIKE '%datab%'
) words
WHERE word % 'datab'
ORDER BY sim DESC
LIMIT 10;
```

## JSON and JSONB Querying

### JSONB Operations

```sql
-- Product specifications as JSONB
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    specifications JSONB,
    metadata JSONB DEFAULT '{}'
);

-- Insert JSONB data
INSERT INTO products (name, specifications, metadata) VALUES
('Laptop', '{
    "cpu": {"brand": "Intel", "model": "i7-11800H", "cores": 8},
    "ram": {"size_gb": 16, "type": "DDR4", "speed_mhz": 3200},
    "storage": [
        {"type": "SSD", "size_gb": 512, "interface": "NVMe"},
        {"type": "HDD", "size_gb": 1000, "interface": "SATA"}
    ],
    "display": {"size_inches": 15.6, "resolution": "1920x1080", "type": "IPS"}
}', '{"category": "electronics", "tags": ["laptop", "gaming"]}');

-- Query JSONB data
SELECT
    name,
    specifications->>'cpu'->>'model' AS cpu_model,
    specifications->'ram'->>'size_gb' AS ram_gb,
    specifications->'storage' AS storage_array,
    jsonb_array_length(specifications->'storage') AS storage_count
FROM products
WHERE specifications->'cpu'->>'brand' = 'Intel';

-- Complex JSONB queries
SELECT
    name,
    jsonb_object_keys(specifications) AS spec_keys
FROM products
WHERE specifications ? 'cpu'  -- Contains key
  AND specifications->'ram'->>'size_gb' >= '16';

-- JSONB aggregation
SELECT
    specifications->>'cpu'->>'brand' AS cpu_brand,
    COUNT(*) AS product_count,
    AVG((specifications->'ram'->>'size_gb')::INTEGER) AS avg_ram_gb,
    jsonb_agg(specifications->'display'->>'resolution') AS resolutions
FROM products
WHERE specifications ? 'cpu'
GROUP BY specifications->>'cpu'->>'brand';
```

### JSONB Indexes

```sql
-- GIN index for JSONB operations
CREATE INDEX idx_products_specs ON products USING GIN (specifications);

-- B-tree index on specific paths
CREATE INDEX idx_products_cpu_brand ON products ((specifications->'cpu'->>'brand'));
CREATE INDEX idx_products_ram_size ON products (((specifications->'ram'->>'size_gb')::INTEGER));

-- Partial index for specific conditions
CREATE INDEX idx_gaming_laptops ON products USING GIN (specifications)
WHERE metadata->>'category' = 'electronics'
  AND 'gaming' = ANY(ARRAY(SELECT jsonb_array_elements_text(metadata->'tags')));

-- Query using indexes
SELECT * FROM products
WHERE specifications @> '{"cpu": {"brand": "Intel"}}'  -- Contained by
  AND specifications->'ram'->>'size_gb' >= '16';
```

## Array Operations

### Array Querying

```sql
-- Product with multiple categories and tags
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    categories INTEGER[] DEFAULT '{}',
    tags TEXT[] DEFAULT '{}',
    images VARCHAR(500)[] DEFAULT '{}'
);

-- Query array data
SELECT
    name,
    categories,
    array_length(categories, 1) AS category_count,
    tags
FROM products
WHERE 'electronics' = ANY(tags)
   OR 1 = ANY(categories);  -- Category ID 1

-- Array aggregation
SELECT
    c.name AS category_name,
    COUNT(p.*) AS product_count,
    array_agg(p.name ORDER BY p.name) AS products,
    array_agg(DISTINCT tag ORDER BY tag) AS all_tags
FROM categories c
LEFT JOIN products p ON c.category_id = ANY(p.categories)
LEFT JOIN LATERAL unnest(p.tags) AS tag ON true
GROUP BY c.category_id, c.name;

-- Array operations
SELECT
    name,
    tags,
    array_append(tags, 'new_tag') AS with_new_tag,
    array_remove(tags, 'old_tag') AS without_old_tag,
    array_cat(tags, ARRAY['additional', 'tags']) AS combined_tags
FROM products
WHERE array_length(tags, 1) > 0;

-- Array intersection and union
SELECT
    p1.name AS product1,
    p2.name AS product2,
    p1.tags & p2.tags AS common_tags,  -- Intersection
    p1.tags | p2.tags AS all_tags      -- Union
FROM products p1
JOIN products p2 ON p1.product_id < p2.product_id
WHERE p1.tags && p2.tags;  -- Overlap (non-empty intersection)
```

## Advanced JOIN Techniques

### LATERAL Joins

```sql
-- LATERAL join for correlated subqueries
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    recent_orders.order_date,
    recent_orders.total_amount
FROM customers c
LEFT JOIN LATERAL (
    SELECT order_date, total_amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY order_date DESC
    LIMIT 3
) recent_orders ON true
ORDER BY c.customer_id, recent_orders.order_date DESC;

-- LATERAL with aggregation
SELECT
    p.product_id,
    p.name,
    monthly_stats.month,
    monthly_stats.total_sold,
    monthly_stats.revenue
FROM products p
LEFT JOIN LATERAL (
    SELECT
        DATE_TRUNC('month', o.order_date) AS month,
        SUM(oi.quantity) AS total_sold,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE oi.product_id = p.product_id
      AND o.order_date >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY DATE_TRUNC('month', o.order_date)
    ORDER BY month DESC
    LIMIT 6
) monthly_stats ON true
ORDER BY p.product_id, monthly_stats.month DESC;
```

### FULL OUTER JOIN with COALESCE

```sql
-- Compare current vs previous month sales
WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_date) AS month,
        SUM(total_amount) AS total_sales
    FROM orders
    WHERE order_date >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT
    COALESCE(curr.month, prev.month + INTERVAL '1 month') AS month,
    curr.total_sales AS current_month,
    prev.total_sales AS previous_month,
    ROUND(
        100.0 * (curr.total_sales - prev.total_sales) / NULLIF(prev.total_sales, 0),
        2
    ) AS growth_percentage
FROM monthly_sales curr
FULL OUTER JOIN monthly_sales prev ON curr.month = prev.month + INTERVAL '1 month'
ORDER BY month;
```

## Query Optimization

### EXPLAIN and Query Planning

```sql
-- Analyze query execution plan
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    c.name AS customer_name,
    p.name AS product_name,
    SUM(oi.quantity * oi.unit_price) AS total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.order_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY c.customer_id, c.name, p.product_id, p.name
HAVING SUM(oi.quantity * oi.unit_price) > 1000
ORDER BY total_spent DESC;

-- Use CTE for complex query optimization
WITH customer_product_totals AS (
    SELECT
        c.customer_id,
        c.name AS customer_name,
        p.product_id,
        p.name AS product_name,
        SUM(oi.quantity * oi.unit_price) AS total_spent
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.order_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY c.customer_id, c.name, p.product_id, p.name
)
SELECT
    customer_name,
    product_name,
    total_spent
FROM customer_product_totals
WHERE total_spent > 1000
ORDER BY total_spent DESC;
```

### Index-Only Scans and Covering Indexes

```sql
-- Covering index for common queries
CREATE INDEX idx_orders_customer_date_covering
ON orders (customer_id, order_date)
INCLUDE (total_amount, status);

-- Query that can use index-only scan
SELECT
    customer_id,
    order_date,
    total_amount,
    status
FROM orders
WHERE customer_id = 12345
  AND order_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY order_date DESC;

-- Partial index for active orders
CREATE INDEX idx_active_orders_customer
ON orders (customer_id, order_date)
WHERE status NOT IN ('delivered', 'cancelled');
```

### Common Table Expression Optimization

```sql
-- Optimize complex queries with CTEs
WITH
    -- Pre-filter and aggregate recent orders
    recent_orders AS (
        SELECT
            customer_id,
            COUNT(*) AS order_count,
            SUM(total_amount) AS total_spent,
            MAX(order_date) AS last_order_date
        FROM orders
        WHERE order_date >= CURRENT_DATE - INTERVAL '90 days'
        GROUP BY customer_id
    ),
    -- Calculate customer segments
    customer_segments AS (
        SELECT
            customer_id,
            CASE
                WHEN total_spent >= 5000 THEN 'High Value'
                WHEN total_spent >= 1000 THEN 'Medium Value'
                WHEN order_count >= 5 THEN 'Frequent'
                ELSE 'Standard'
            END AS segment
        FROM recent_orders
    )
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    cs.segment,
    ro.total_spent,
    ro.order_count,
    ro.last_order_date
FROM customers c
JOIN customer_segments cs ON c.customer_id = cs.customer_id
JOIN recent_orders ro ON c.customer_id = ro.customer_id
ORDER BY ro.total_spent DESC;
```

## Enterprise Query Patterns

### Pagination with Total Count

```sql
-- Efficient pagination with total count
CREATE OR REPLACE FUNCTION get_paginated_products(
    page_size INTEGER DEFAULT 20,
    page_number INTEGER DEFAULT 1,
    search_term TEXT DEFAULT '',
    category_filter INTEGER DEFAULT NULL
)
RETURNS TABLE (
    product_id INTEGER,
    name VARCHAR(255),
    price DECIMAL(10,2),
    category_name VARCHAR(100),
    total_count BIGINT
) AS $$
DECLARE
    offset_val INTEGER := (page_number - 1) * page_size;
BEGIN
    RETURN QUERY
    WITH filtered_products AS (
        SELECT
            p.product_id,
            p.name,
            p.price,
            c.name AS category_name,
            COUNT(*) OVER () AS total_count
        FROM products p
        JOIN categories c ON p.category_id = c.category_id
        WHERE (search_term = '' OR p.name ILIKE '%' || search_term || '%')
          AND (category_filter IS NULL OR p.category_id = category_filter)
    )
    SELECT
        fp.product_id,
        fp.name,
        fp.price,
        fp.category_name,
        fp.total_count
    FROM filtered_products fp
    ORDER BY fp.name
    LIMIT page_size
    OFFSET offset_val;
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT * FROM get_paginated_products(10, 2, 'laptop', 1);
```

### Real-time Analytics Dashboard

```sql
-- Real-time sales analytics
CREATE OR REPLACE VIEW sales_analytics AS
WITH hourly_sales AS (
    SELECT
        DATE_TRUNC('hour', order_date) AS hour,
        SUM(total_amount) AS hourly_revenue,
        COUNT(*) AS order_count,
        COUNT(DISTINCT customer_id) AS unique_customers
    FROM orders
    WHERE order_date >= CURRENT_DATE
    GROUP BY DATE_TRUNC('hour', order_date)
),
daily_stats AS (
    SELECT
        CURRENT_DATE AS date,
        SUM(total_amount) AS daily_revenue,
        COUNT(*) AS daily_orders,
        COUNT(DISTINCT customer_id) AS daily_customers,
        AVG(total_amount) AS avg_order_value
    FROM orders
    WHERE DATE(order_date) = CURRENT_DATE
),
weekly_comparison AS (
    SELECT
        SUM(CASE WHEN DATE(order_date) = CURRENT_DATE THEN total_amount END) AS today_revenue,
        SUM(CASE WHEN DATE(order_date) = CURRENT_DATE - 1 THEN total_amount END) AS yesterday_revenue,
        SUM(CASE WHEN DATE(order_date) >= CURRENT_DATE - 7 THEN total_amount END) AS weekly_revenue,
        ROUND(
            100.0 * (
                SUM(CASE WHEN DATE(order_date) = CURRENT_DATE THEN total_amount END) -
                SUM(CASE WHEN DATE(order_date) = CURRENT_DATE - 1 THEN total_amount END)
            ) / NULLIF(SUM(CASE WHEN DATE(order_date) = CURRENT_DATE - 1 THEN total_amount END), 0),
            2
        ) AS day_over_day_growth
    FROM orders
    WHERE order_date >= CURRENT_DATE - 8
)
SELECT
    ds.date,
    ds.daily_revenue,
    ds.daily_orders,
    ds.daily_customers,
    ds.avg_order_value,
    wc.day_over_day_growth,
    wc.weekly_revenue,
    ARRAY_AGG(
        JSON_BUILD_OBJECT(
            'hour', hs.hour,
            'revenue', hs.hourly_revenue,
            'orders', hs.order_count,
            'customers', hs.unique_customers
        ) ORDER BY hs.hour
    ) AS hourly_breakdown
FROM daily_stats ds
CROSS JOIN weekly_comparison wc
LEFT JOIN hourly_sales hs ON true
GROUP BY ds.date, ds.daily_revenue, ds.daily_orders, ds.daily_customers,
         ds.avg_order_value, wc.day_over_day_growth, wc.weekly_revenue;

-- Query the analytics view
SELECT * FROM sales_analytics;
```

### Complex Reporting Query

```sql
-- Multi-dimensional product performance report
WITH product_metrics AS (
    SELECT
        p.product_id,
        p.name,
        p.price,
        c.name AS category_name,
        COALESCE(SUM(oi.quantity), 0) AS total_sold,
        COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_revenue,
        COALESCE(AVG(r.rating), 0) AS avg_rating,
        COUNT(DISTINCT r.review_id) AS review_count,
        COUNT(DISTINCT o.customer_id) AS unique_customers,
        MAX(o.order_date) AS last_sale_date,
        MIN(o.order_date) AS first_sale_date
    FROM products p
    LEFT JOIN categories c ON p.category_id = c.category_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status = 'delivered'
    LEFT JOIN reviews r ON p.product_id = r.product_id
    GROUP BY p.product_id, p.name, p.price, c.name
),
category_stats AS (
    SELECT
        category_name,
        COUNT(*) AS product_count,
        SUM(total_sold) AS category_total_sold,
        SUM(total_revenue) AS category_total_revenue,
        AVG(avg_rating) AS category_avg_rating
    FROM product_metrics
    GROUP BY category_name
)
SELECT
    pm.product_id,
    pm.name,
    pm.price,
    pm.category_name,
    pm.total_sold,
    pm.total_revenue,
    pm.avg_rating,
    pm.review_count,
    pm.unique_customers,
    pm.last_sale_date,
    pm.first_sale_date,
    -- Category rankings
    RANK() OVER (PARTITION BY pm.category_name ORDER BY pm.total_revenue DESC) AS category_revenue_rank,
    RANK() OVER (PARTITION BY pm.category_name ORDER BY pm.avg_rating DESC) AS category_rating_rank,
    -- Overall rankings
    RANK() OVER (ORDER BY pm.total_revenue DESC) AS overall_revenue_rank,
    RANK() OVER (ORDER BY pm.total_sold DESC) AS overall_sales_rank,
    -- Category context
    cs.product_count AS category_product_count,
    ROUND(100.0 * pm.total_revenue / NULLIF(cs.category_total_revenue, 0), 2) AS pct_of_category_revenue,
    pm.avg_rating - cs.category_avg_rating AS rating_vs_category_avg
FROM product_metrics pm
JOIN category_stats cs ON pm.category_name = cs.category_name
WHERE pm.total_sold > 0  -- Only products that have sold
ORDER BY pm.total_revenue DESC
LIMIT 100;
```

This comprehensive guide covers advanced querying techniques in PostgreSQL, including CTEs, window functions, recursive queries, full-text search, JSON operations, and enterprise-level query patterns used by major tech companies.
