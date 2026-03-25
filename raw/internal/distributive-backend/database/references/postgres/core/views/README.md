# PostgreSQL Views

## Overview

Views in PostgreSQL are virtual tables that present data from one or more underlying tables. They provide a way to simplify complex queries, implement security policies, and create abstracted interfaces over your data. PostgreSQL supports regular views, materialized views, and updatable views.

## Table of Contents

1. [Regular Views](#regular-views)
2. [Materialized Views](#materialized-views)
3. [Updatable Views](#updatable-views)
4. [View Security](#view-security)
5. [Performance Considerations](#performance-considerations)
6. [Advanced View Patterns](#advanced-view-patterns)
7. [Enterprise Patterns](#enterprise-patterns)

## Regular Views

### Basic Views

```sql
-- Simple view for user profiles
CREATE VIEW user_profiles AS
SELECT
    u.user_id,
    u.first_name,
    u.last_name,
    u.email,
    p.bio,
    p.location,
    p.website,
    u.created_at
FROM users u
LEFT JOIN user_profiles_extended p ON u.user_id = p.user_id;

-- View with aggregations
CREATE VIEW product_sales_summary AS
SELECT
    p.product_id,
    p.name,
    p.price,
    COUNT(oi.order_id) AS total_orders,
    SUM(oi.quantity) AS total_quantity_sold,
    SUM(oi.quantity * oi.unit_price) AS total_revenue,
    AVG(oi.quantity * oi.unit_price) AS avg_order_value,
    MAX(o.order_date) AS last_sale_date
FROM products p
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id
GROUP BY p.product_id, p.name, p.price;

-- Query the view
SELECT * FROM user_profiles WHERE created_at >= '2024-01-01';
SELECT * FROM product_sales_summary WHERE total_revenue > 1000 ORDER BY total_revenue DESC;
```

### Views with Complex Logic

```sql
-- View with conditional logic and window functions
CREATE VIEW customer_segments AS
SELECT
    customer_id,
    first_name,
    last_name,
    email,
    total_orders,
    total_spent,
    avg_order_value,
    days_since_last_order,

    -- Customer segmentation logic
    CASE
        WHEN total_spent >= 10000 THEN 'Platinum'
        WHEN total_spent >= 5000 THEN 'Gold'
        WHEN total_spent >= 1000 THEN 'Silver'
        WHEN total_orders >= 5 THEN 'Active'
        ELSE 'Standard'
    END AS segment,

    -- RFM analysis components
    NTILE(5) OVER (ORDER BY total_orders DESC) AS rfm_recency_score,
    NTILE(5) OVER (ORDER BY total_orders DESC) AS rfm_frequency_score,
    NTILE(5) OVER (ORDER BY total_spent DESC) AS rfm_monetary_score

FROM (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        COUNT(o.order_id) AS total_orders,
        COALESCE(SUM(o.total_amount), 0) AS total_spent,
        COALESCE(AVG(o.total_amount), 0) AS avg_order_value,
        EXTRACT(DAY FROM CURRENT_DATE - MAX(o.order_date)) AS days_since_last_order
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status = 'completed'
    GROUP BY c.customer_id, c.first_name, c.last_name, c.email
) customer_stats;

-- View with hierarchical data
CREATE VIEW category_hierarchy AS
WITH RECURSIVE category_tree AS (
    -- Root categories
    SELECT
        category_id,
        name,
        parent_category_id,
        name AS path,
        1 AS level
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    -- Child categories
    SELECT
        c.category_id,
        c.name,
        c.parent_category_id,
        ct.path || ' > ' || c.name,
        ct.level + 1
    FROM categories c
    JOIN category_tree ct ON c.parent_category_id = ct.category_id
)
SELECT * FROM category_tree ORDER BY path;
```

### View Maintenance

```sql
-- Replace a view (drops and recreates)
CREATE OR REPLACE VIEW active_users AS
SELECT * FROM users WHERE active = true AND deleted_at IS NULL;

-- Alter view definition (PostgreSQL 9.4+)
-- Note: Limited ALTER VIEW support compared to CREATE OR REPLACE

-- Drop a view
DROP VIEW IF EXISTS active_users;

-- Drop view with cascade (drops dependent objects)
DROP VIEW active_users CASCADE;
```

## Materialized Views

### Basic Materialized Views

```sql
-- Materialized view for expensive aggregations
CREATE MATERIALIZED VIEW monthly_sales_summary AS
SELECT
    DATE_TRUNC('month', o.order_date) AS month,
    p.category_id,
    c.name AS category_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    SUM(oi.quantity * oi.unit_price) AS total_revenue,
    AVG(oi.quantity * oi.unit_price) AS avg_order_value,
    SUM(oi.quantity) AS total_items_sold
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN categories c ON p.category_id = c.category_id
WHERE o.status = 'completed'
  AND o.order_date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY DATE_TRUNC('month', o.order_date), p.category_id, c.name
ORDER BY month DESC, total_revenue DESC;

-- Create indexes on materialized view for performance
CREATE INDEX idx_monthly_sales_month ON monthly_sales_summary (month);
CREATE INDEX idx_monthly_sales_category ON monthly_sales_summary (category_id);
CREATE INDEX idx_monthly_sales_revenue ON monthly_sales_summary (total_revenue DESC);

-- Query materialized view
SELECT * FROM monthly_sales_summary
WHERE month >= '2024-01-01'
ORDER BY total_revenue DESC;
```

### Refreshing Materialized Views

```sql
-- Manual refresh (blocks concurrent reads)
REFRESH MATERIALIZED VIEW monthly_sales_summary;

-- Concurrent refresh (allows concurrent reads, PostgreSQL 9.4+)
REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_sales_summary;

-- Automated refresh with custom function
CREATE OR REPLACE FUNCTION refresh_sales_summary()
RETURNS VOID AS $$
BEGIN
    -- Refresh with error handling
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_sales_summary;
        RAISE NOTICE 'Successfully refreshed monthly_sales_summary';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to refresh monthly_sales_summary: %', SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- Schedule automated refresh (requires pg_cron)
-- SELECT cron.schedule('refresh-sales-summary', '0 */6 * * *', 'SELECT refresh_sales_summary()');

-- Conditional refresh based on data changes
CREATE OR REPLACE FUNCTION refresh_if_stale(view_name TEXT, max_age INTERVAL DEFAULT INTERVAL '1 hour')
RETURNS BOOLEAN AS $$
DECLARE
    last_refresh TIMESTAMP WITH TIME ZONE;
    should_refresh BOOLEAN := FALSE;
BEGIN
    -- Check when the view was last refreshed
    SELECT GREATEST(
        (SELECT last_refresh FROM pg_stat_user_tables WHERE relname = view_name),
        (SELECT last_analyze FROM pg_stat_user_tables WHERE relname = view_name)
    ) INTO last_refresh;

    -- Refresh if data is stale
    IF last_refresh IS NULL OR last_refresh < CURRENT_TIMESTAMP - max_age THEN
        EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %I', view_name);
        should_refresh := TRUE;
    END IF;

    RETURN should_refresh;
END;
$$ LANGUAGE plpgsql;
```

### Incremental Materialized Views

```sql
-- Incremental refresh pattern using staging tables
CREATE TABLE sales_summary_staging (
    month DATE,
    category_id INTEGER,
    category_name VARCHAR(100),
    total_orders BIGINT DEFAULT 0,
    unique_customers BIGINT DEFAULT 0,
    total_revenue DECIMAL(12,2) DEFAULT 0,
    avg_order_value DECIMAL(10,2) DEFAULT 0,
    total_items_sold BIGINT DEFAULT 0,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (month, category_id)
);

-- Function for incremental refresh
CREATE OR REPLACE FUNCTION incremental_refresh_sales_summary(
    start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    end_date DATE DEFAULT CURRENT_DATE
)
RETURNS VOID AS $$
BEGIN
    -- Insert or update staging data for the period
    INSERT INTO sales_summary_staging (
        month, category_id, category_name,
        total_orders, unique_customers, total_revenue,
        avg_order_value, total_items_sold, last_updated
    )
    SELECT
        DATE_TRUNC('month', o.order_date) AS month,
        p.category_id,
        c.name AS category_name,
        COUNT(DISTINCT o.order_id) AS total_orders,
        COUNT(DISTINCT o.customer_id) AS unique_customers,
        SUM(oi.quantity * oi.unit_price) AS total_revenue,
        AVG(oi.quantity * oi.unit_price) AS avg_order_value,
        SUM(oi.quantity) AS total_items_sold,
        CURRENT_TIMESTAMP
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    JOIN categories c ON p.category_id = c.category_id
    WHERE o.status = 'completed'
      AND o.order_date >= start_date
      AND o.order_date < end_date
    GROUP BY DATE_TRUNC('month', o.order_date), p.category_id, c.name
    ON CONFLICT (month, category_id)
    DO UPDATE SET
        total_orders = EXCLUDED.total_orders,
        unique_customers = EXCLUDED.unique_customers,
        total_revenue = EXCLUDED.total_revenue,
        avg_order_value = EXCLUDED.avg_order_value,
        total_items_sold = EXCLUDED.total_items_sold,
        last_updated = EXCLUDED.last_updated;

    -- Replace the materialized view data
    TRUNCATE monthly_sales_summary;

    INSERT INTO monthly_sales_summary
    SELECT * FROM sales_summary_staging;
END;
$$ LANGUAGE plpgsql;
```

## Updatable Views

### Simple Updatable Views

```sql
-- Simple updatable view
CREATE VIEW active_products AS
SELECT product_id, name, price, stock_quantity, category_id
FROM products
WHERE discontinued = false;

-- Update through view (works because it's a simple view)
UPDATE active_products
SET price = price * 1.1
WHERE category_id = 1;

-- Insert through view
INSERT INTO active_products (name, price, stock_quantity, category_id)
VALUES ('New Product', 29.99, 100, 1);
```

### INSTEAD OF Triggers for Complex Views

```sql
-- Complex view requiring INSTEAD OF triggers
CREATE VIEW order_details AS
SELECT
    o.order_id,
    o.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    o.order_date,
    o.status,
    oi.product_id,
    p.name AS product_name,
    oi.quantity,
    oi.unit_price,
    oi.quantity * oi.unit_price AS line_total
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id;

-- INSTEAD OF INSERT trigger
CREATE OR REPLACE FUNCTION order_details_insert()
RETURNS TRIGGER AS $$
DECLARE
    order_id_val INTEGER;
    customer_id_val INTEGER;
BEGIN
    -- Validate customer exists
    SELECT customer_id INTO customer_id_val
    FROM customers
    WHERE customer_id = NEW.customer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    -- Create order if it doesn't exist
    IF NEW.order_id IS NULL THEN
        INSERT INTO orders (customer_id, order_date, status)
        VALUES (NEW.customer_id, COALESCE(NEW.order_date, CURRENT_DATE), COALESCE(NEW.status, 'pending'))
        RETURNING order_id INTO order_id_val;
    ELSE
        order_id_val := NEW.order_id;
    END IF;

    -- Add order item
    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (order_id_val, NEW.product_id, NEW.quantity, NEW.unit_price);

    -- Return the inserted row
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_details_insert_trigger
    INSTEAD OF INSERT ON order_details
    FOR EACH ROW EXECUTE FUNCTION order_details_insert();

-- INSTEAD OF UPDATE trigger
CREATE OR REPLACE FUNCTION order_details_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Update order information
    UPDATE orders
    SET
        status = COALESCE(NEW.status, OLD.status),
        order_date = COALESCE(NEW.order_date, OLD.order_date)
    WHERE order_id = OLD.order_id;

    -- Update order item
    UPDATE order_items
    SET
        quantity = COALESCE(NEW.quantity, OLD.quantity),
        unit_price = COALESCE(NEW.unit_price, OLD.unit_price)
    WHERE order_id = OLD.order_id AND product_id = OLD.product_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_details_update_trigger
    INSTEAD OF UPDATE ON order_details
    FOR EACH ROW EXECUTE FUNCTION order_details_update();

-- INSTEAD OF DELETE trigger
CREATE OR REPLACE FUNCTION order_details_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Delete order item
    DELETE FROM order_items
    WHERE order_id = OLD.order_id AND product_id = OLD.product_id;

    -- If no more items, cancel the order
    IF NOT EXISTS (SELECT 1 FROM order_items WHERE order_id = OLD.order_id) THEN
        UPDATE orders SET status = 'cancelled' WHERE order_id = OLD.order_id;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_details_delete_trigger
    INSTEAD OF DELETE ON order_details
    FOR EACH ROW EXECUTE FUNCTION order_details_delete();
```

### Conditional Updatable Views

```sql
-- View with conditions for updatable rows
CREATE VIEW editable_orders AS
SELECT * FROM orders
WHERE status IN ('pending', 'confirmed')
  AND created_at > CURRENT_DATE - INTERVAL '30 days';

-- INSTEAD OF trigger to enforce business rules
CREATE OR REPLACE FUNCTION editable_orders_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Only allow updates to certain fields
    IF NEW.status NOT IN ('pending', 'confirmed', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid status transition';
    END IF;

    -- Only allow updates within time window
    IF NEW.created_at <= CURRENT_DATE - INTERVAL '30 days' THEN
        RAISE EXCEPTION 'Order is too old to edit';
    END IF;

    -- Update the underlying table
    UPDATE orders
    SET
        status = NEW.status,
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = NEW.order_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER editable_orders_update_trigger
    INSTEAD OF UPDATE ON editable_orders
    FOR EACH ROW EXECUTE FUNCTION editable_orders_update();
```

## View Security

### Row-Level Security with Views

```sql
-- Enable RLS on underlying tables
ALTER TABLE sensitive_data ENABLE ROW LEVEL SECURITY;

-- Create security policy
CREATE POLICY tenant_data_policy ON sensitive_data
    FOR ALL USING (tenant_id = current_setting('app.tenant_id')::INTEGER);

-- Create view that respects RLS
CREATE VIEW my_tenant_data AS
SELECT * FROM sensitive_data;

-- Users can only see their tenant's data through the view
SELECT * FROM my_tenant_data;  -- Automatically filtered by RLS
```

### Secure Views for Data Access

```sql
-- View that hides sensitive columns
CREATE VIEW customer_public_info AS
SELECT
    customer_id,
    first_name,
    last_name,
    email,
    created_at
FROM customers;

-- Grant access to public view only
GRANT SELECT ON customer_public_info TO public_user;
REVOKE SELECT ON customers FROM public_user;

-- View with aggregated data for reporting users
CREATE VIEW sales_reports AS
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(*) AS total_orders,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_order_value
FROM orders
WHERE order_date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY DATE_TRUNC('month', order_date);

GRANT SELECT ON sales_reports TO report_user;
```

### Dynamic Views with Security

```sql
-- Function to create user-specific views
CREATE OR REPLACE FUNCTION create_user_view(user_id_param INTEGER)
RETURNS TEXT AS $$
DECLARE
    view_name TEXT;
BEGIN
    view_name := 'user_' || user_id_param || '_data';

    EXECUTE format('
        CREATE OR REPLACE VIEW %I AS
        SELECT * FROM user_data
        WHERE user_id = %s OR created_by = %s
    ', view_name, user_id_param, user_id_param);

    RETURN view_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create personalized view for user
SELECT create_user_view(123);

-- User can now access their personalized view
SELECT * FROM user_123_data;
```

## Performance Considerations

### View Optimization

```sql
-- Use indexes that views can leverage
CREATE INDEX idx_orders_date_status ON orders (order_date, status);
CREATE INDEX idx_order_items_order_product ON order_items (order_id, product_id);

-- Views automatically use underlying table indexes
SELECT * FROM order_summary WHERE order_date >= '2024-01-01';
-- Uses idx_orders_date_status index

-- Materialized view indexes
CREATE MATERIALIZED VIEW product_performance AS
SELECT
    p.product_id,
    p.name,
    SUM(oi.quantity) AS total_sold,
    SUM(oi.quantity * oi.unit_price) AS total_revenue,
    AVG(oi.quantity * oi.unit_price) AS avg_sale_price
FROM products p
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status = 'completed'
GROUP BY p.product_id, p.name;

-- Create indexes on materialized view
CREATE INDEX idx_product_perf_revenue ON product_performance (total_revenue DESC);
CREATE INDEX idx_product_perf_sold ON product_performance (total_sold DESC);
```

### When to Use Views vs Materialized Views

```sql
-- Regular views for:
-- 1. Security and access control
-- 2. Simplifying complex joins
-- 3. Data abstraction
-- 4. Real-time data requirements

-- Materialized views for:
-- 1. Expensive aggregations
-- 2. Complex calculations
-- 3. Data that changes infrequently
-- 4. Performance-critical reports

-- Example: Real-time dashboard (use regular view)
CREATE VIEW realtime_dashboard AS
SELECT
    (SELECT COUNT(*) FROM orders WHERE DATE(order_date) = CURRENT_DATE) AS todays_orders,
    (SELECT SUM(total_amount) FROM orders WHERE DATE(order_date) = CURRENT_DATE) AS todays_revenue,
    (SELECT COUNT(*) FROM users WHERE DATE(created_at) = CURRENT_DATE) AS new_users_today;

-- Example: Monthly reports (use materialized view)
CREATE MATERIALIZED VIEW monthly_reports AS
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(*) AS total_orders,
    SUM(total_amount) AS total_revenue,
    COUNT(DISTINCT customer_id) AS unique_customers,
    AVG(total_amount) AS avg_order_value
FROM orders
WHERE order_date >= CURRENT_DATE - INTERVAL '2 years'
GROUP BY DATE_TRUNC('month', order_date);
```

### View Maintenance and Monitoring

```sql
-- View dependencies
SELECT
    dependent_ns.nspname AS dependent_schema,
    dependent_view.relname AS dependent_view,
    source_ns.nspname AS source_schema,
    source_table.relname AS source_table
FROM pg_depend
JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
JOIN pg_class dependent_view ON pg_rewrite.ev_class = dependent_view.oid
JOIN pg_class source_table ON pg_depend.refobjid = source_table.oid
JOIN pg_namespace dependent_ns ON dependent_view.relnamespace = dependent_ns.oid
JOIN pg_namespace source_ns ON source_table.relnamespace = source_ns.oid
WHERE dependent_view.relkind = 'v'  -- views only
  AND source_table.relname = 'your_table_name';

-- Materialized view freshness
CREATE VIEW mv_freshness AS
SELECT
    schemaname,
    matviewname,
    last_refresh,
    CASE
        WHEN last_refresh IS NULL THEN 'Never refreshed'
        WHEN last_refresh < CURRENT_TIMESTAMP - INTERVAL '1 day' THEN 'Stale'
        ELSE 'Fresh'
    END AS freshness_status,
    pg_size_pretty(pg_total_relation_size(matviewname::text)) AS size
FROM (
    SELECT
        schemaname,
        matviewname,
        GREATEST(last_vacuum, last_autovacuum, last_analyze, last_autoanalyze) AS last_refresh
    FROM pg_stat_user_tables
    WHERE matviewname IS NOT NULL
) mv_stats;
```

## Advanced View Patterns

### Recursive Views

```sql
-- View with recursive CTE for organizational hierarchy
CREATE RECURSIVE VIEW employee_hierarchy AS
SELECT
    employee_id,
    first_name || ' ' || last_name AS full_name,
    manager_id,
    1 AS level,
    ARRAY[employee_id] AS path
FROM employees
WHERE manager_id IS NULL

UNION ALL

SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name,
    e.manager_id,
    eh.level + 1,
    eh.path || e.employee_id
FROM employees e
JOIN employee_hierarchy eh ON e.manager_id = eh.employee_id;
```

### Polymorphic Views

```sql
-- View that combines different entity types
CREATE VIEW searchable_content AS
SELECT
    'product'::TEXT AS content_type,
    product_id::TEXT AS content_id,
    name AS title,
    description AS content,
    search_vector
FROM products

UNION ALL

SELECT
    'article'::TEXT AS content_type,
    article_id::TEXT AS content_id,
    title,
    content,
    search_vector
FROM articles

UNION ALL

SELECT
    'course'::TEXT AS content_type,
    course_id::TEXT AS content_id,
    title,
    description,
    search_vector
FROM courses;

-- Create GIN index for fast searching
CREATE INDEX idx_searchable_content_vector ON searchable_content USING GIN (search_vector);

-- Unified search across all content types
SELECT * FROM searchable_content
WHERE search_vector @@ to_tsquery('english', 'database & performance');
```

### Temporal Views

```sql
-- View for current data (hiding soft deletes)
CREATE VIEW active_users AS
SELECT * FROM users
WHERE deleted_at IS NULL;

-- View for historical data with temporal aspects
CREATE VIEW user_history AS
SELECT
    u.user_id,
    u.first_name,
    u.last_name,
    u.email,
    uh.changed_at,
    uh.old_values,
    uh.new_values,
    uh.change_type
FROM users u
JOIN user_history uh ON u.user_id = uh.user_id
WHERE u.deleted_at IS NULL
ORDER BY u.user_id, uh.changed_at DESC;

-- Point-in-time view (requires temporal table extensions)
CREATE VIEW users_as_of_yesterday AS
SELECT * FROM users
FOR SYSTEM_TIME AS OF CURRENT_TIMESTAMP - INTERVAL '1 day';
```

## Enterprise Patterns

### API Response Views

```sql
-- Views designed for API responses
CREATE VIEW user_api_response AS
SELECT
    u.user_id,
    u.first_name,
    u.last_name,
    u.email,
    u.created_at,
    JSON_BUILD_OBJECT(
        'total_orders', COALESCE(us.total_orders, 0),
        'total_spent', COALESCE(us.total_spent, 0.00),
        'last_order_date', us.last_order_date,
        'loyalty_tier', CASE
            WHEN us.total_spent >= 1000 THEN 'Gold'
            WHEN us.total_spent >= 500 THEN 'Silver'
            ELSE 'Bronze'
        END
    ) AS stats,
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'order_id', o.order_id,
            'order_date', o.order_date,
            'total_amount', o.total_amount,
            'status', o.status
        )
    ) FILTER (WHERE o.order_id IS NOT NULL) AS recent_orders
FROM users u
LEFT JOIN user_stats us ON u.user_id = us.user_id
LEFT JOIN (
    SELECT
        customer_id,
        order_id,
        order_date,
        total_amount,
        status,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
    FROM orders
    WHERE status IN ('completed', 'shipped')
) o ON u.user_id = o.customer_id AND o.rn <= 5
GROUP BY u.user_id, u.first_name, u.last_name, u.email, u.created_at, us.total_orders, us.total_spent, us.last_order_date;

-- API can now get complete user data with one query
SELECT * FROM user_api_response WHERE user_id = 123;
```

### Reporting Views with Complex Aggregations

```sql
-- Comprehensive business intelligence view
CREATE MATERIALIZED VIEW business_intelligence AS
WITH
    customer_metrics AS (
        SELECT
            customer_id,
            COUNT(*) AS total_orders,
            SUM(total_amount) AS total_spent,
            AVG(total_amount) AS avg_order_value,
            MAX(order_date) AS last_order_date,
            MIN(order_date) AS first_order_date,
            EXTRACT(EPOCH FROM (MAX(order_date) - MIN(order_date))) / 86400 / COUNT(*) AS avg_days_between_orders
        FROM orders
        WHERE status = 'completed'
        GROUP BY customer_id
    ),
    product_metrics AS (
        SELECT
            p.product_id,
            p.name,
            p.category_id,
            COUNT(oi.order_id) AS total_orders,
            SUM(oi.quantity) AS total_quantity_sold,
            SUM(oi.quantity * oi.unit_price) AS total_revenue,
            AVG(oi.unit_price) AS avg_selling_price,
            COUNT(DISTINCT o.customer_id) AS unique_customers,
            MAX(o.order_date) AS last_sale_date
        FROM products p
        LEFT JOIN order_items oi ON p.product_id = oi.product_id
        LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status = 'completed'
        GROUP BY p.product_id, p.name, p.category_id
    ),
    category_metrics AS (
        SELECT
            c.category_id,
            c.name AS category_name,
            COUNT(DISTINCT p.product_id) AS total_products,
            COUNT(DISTINCT o.order_id) AS total_orders,
            SUM(oi.quantity * oi.unit_price) AS total_revenue,
            AVG(oi.quantity * oi.unit_price) AS avg_order_value
        FROM categories c
        LEFT JOIN products p ON c.category_id = p.category_id
        LEFT JOIN order_items oi ON p.product_id = oi.product_id
        LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status = 'completed'
        GROUP BY c.category_id, c.name
    )
SELECT
    -- Customer insights
    cm.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    cm.total_orders,
    cm.total_spent,
    cm.avg_order_value,
    cm.last_order_date,
    EXTRACT(DAY FROM CURRENT_DATE - cm.last_order_date) AS days_since_last_order,

    -- Customer segmentation
    CASE
        WHEN cm.total_spent >= 10000 THEN 'VIP'
        WHEN cm.total_spent >= 5000 THEN 'High Value'
        WHEN cm.total_spent >= 1000 THEN 'Medium Value'
        WHEN cm.total_orders >= 5 THEN 'Loyal'
        ELSE 'Standard'
    END AS customer_segment,

    -- Product insights
    pm.product_id,
    pm.name AS product_name,
    cat.category_name,
    pm.total_orders AS product_total_orders,
    pm.total_quantity_sold,
    pm.total_revenue AS product_total_revenue,
    pm.avg_selling_price,
    pm.unique_customers AS product_unique_customers,

    -- Category insights
    cm_cat.category_name AS customer_top_category,
    cm_cat.total_revenue AS customer_category_spend

FROM customer_metrics cm
JOIN customers c ON cm.customer_id = c.customer_id
LEFT JOIN (
    SELECT
        o.customer_id,
        p.category_id,
        SUM(oi.quantity * oi.unit_price) AS total_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id, p.category_id
) customer_category_spend ON cm.customer_id = customer_category_spend.customer_id
LEFT JOIN category_metrics cm_cat ON customer_category_spend.category_id = cm_cat.category_id
CROSS JOIN LATERAL (
    SELECT * FROM product_metrics
    ORDER BY total_revenue DESC
    LIMIT 10
) pm
JOIN categories cat ON pm.category_id = cat.category_id
ORDER BY cm.total_spent DESC, pm.total_revenue DESC;

-- Refresh weekly
REFRESH MATERIALIZED VIEW CONCURRENTLY business_intelligence;
```

### Data Warehouse Views

```sql
-- Star schema views for data warehouse
CREATE VIEW fact_sales AS
SELECT
    o.order_id,
    DATE(o.order_date) AS order_date,
    o.customer_id,
    oi.product_id,
    s.store_id,
    oi.quantity,
    oi.unit_price,
    oi.quantity * oi.unit_price AS line_total,
    o.total_amount,
    o.discount_amount,
    o.tax_amount,
    o.shipping_amount,
    o.status
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
LEFT JOIN stores s ON o.store_id = s.store_id
WHERE o.status = 'completed';

CREATE VIEW dim_customers AS
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.phone,
    c.date_of_birth,
    EXTRACT(YEAR FROM AGE(c.date_of_birth)) AS age,
    c.gender,
    a.street_address,
    a.city,
    a.state,
    a.postal_code,
    a.country,
    c.created_at,
    c.last_login_at,
    CASE
        WHEN c.last_login_at >= CURRENT_DATE - INTERVAL '30 days' THEN 'Active'
        WHEN c.last_login_at >= CURRENT_DATE - INTERVAL '90 days' THEN 'Recent'
        ELSE 'Inactive'
    END AS activity_status
FROM customers c
LEFT JOIN addresses a ON c.customer_id = a.customer_id AND a.is_primary = TRUE;

CREATE VIEW dim_products AS
SELECT
    p.product_id,
    p.sku,
    p.name,
    p.description,
    c.category_id,
    c.name AS category_name,
    p.brand,
    p.price,
    p.cost,
    p.price - p.cost AS margin,
    (p.price - p.cost) / p.price AS margin_percentage,
    p.weight,
    p.dimensions,
    p.created_at,
    CASE
        WHEN p.discontinued = TRUE THEN 'Discontinued'
        WHEN p.stock_quantity = 0 THEN 'Out of Stock'
        WHEN p.stock_quantity <= 10 THEN 'Low Stock'
        ELSE 'In Stock'
    END AS stock_status
FROM products p
LEFT JOIN categories c ON p.category_id = c.category_id;
```

This comprehensive guide covers PostgreSQL views in depth, including regular views, materialized views, updatable views, security considerations, performance optimization, and enterprise-level patterns used by major tech companies for data abstraction and reporting.
