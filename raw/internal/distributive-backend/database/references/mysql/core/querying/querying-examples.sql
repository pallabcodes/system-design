-- MySQL Querying Examples and Best Practices
-- Comprehensive examples of SELECT statements, JOINs, subqueries, CTEs, and optimization techniques
-- Adapted for MySQL with proper indexing strategies and performance considerations

-- ===========================================
-- BASIC SELECT QUERIES
-- =========================================--

-- Simple SELECT with WHERE clause
SELECT
    customer_id,
    customer_name,
    customer_email,
    created_at
FROM customers
WHERE is_active = TRUE
ORDER BY created_at DESC
LIMIT 10;

-- SELECT with calculated columns
SELECT
    product_id,
    product_name,
    unit_price,
    unit_price * 1.08 as price_with_tax,
    CASE
        WHEN unit_price < 50 THEN 'Budget'
        WHEN unit_price < 200 THEN 'Mid-range'
        ELSE 'Premium'
    END as price_category,
    stock_quantity,
    CASE
        WHEN stock_quantity = 0 THEN 'Out of Stock'
        WHEN stock_quantity < 10 THEN 'Low Stock'
        ELSE 'In Stock'
    END as stock_status
FROM products
WHERE is_active = TRUE;

-- ===========================================
-- JOIN OPERATIONS
-- =========================================--

-- INNER JOIN - Get orders with customer information
SELECT
    o.order_id,
    o.order_date,
    o.total_amount,
    o.order_status,
    c.customer_name,
    c.customer_email,
    CONCAT(a.street_address, ', ', a.city, ', ', a.state_province, ' ', a.postal_code) as shipping_address
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN addresses a ON o.shipping_address_id = a.address_id
WHERE o.order_date >= '2024-01-01'
ORDER BY o.order_date DESC;

-- LEFT JOIN - Get all customers with their order counts
SELECT
    c.customer_id,
    c.customer_name,
    c.customer_email,
    COUNT(o.order_id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    MAX(o.order_date) as last_order_date
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status != 'cancelled'
GROUP BY c.customer_id, c.customer_name, c.customer_email
ORDER BY total_spent DESC;

-- Multiple JOINs with complex relationships
SELECT
    p.product_name,
    p.sku,
    cat.category_name,
    sup.supplier_name,
    p.unit_price,
    pi.quantity_available,
    pi.last_inventory_count
FROM products p
INNER JOIN categories cat ON p.category_id = cat.category_id
LEFT JOIN suppliers sup ON p.supplier_id = sup.supplier_id
LEFT JOIN product_inventory pi ON p.product_id = pi.product_id
WHERE p.is_active = TRUE
ORDER BY cat.category_name, p.product_name;

-- ===========================================
-- SUBQUERIES
-- =========================================--

-- Subquery in WHERE clause - Find customers who haven't ordered in 6 months
SELECT
    customer_id,
    customer_name,
    customer_email,
    last_order_date
FROM (
    SELECT
        c.customer_id,
        c.customer_name,
        c.customer_email,
        MAX(o.order_date) as last_order_date
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_id, c.customer_name, c.customer_email
) as customer_orders
WHERE last_order_date < DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
   OR last_order_date IS NULL;

-- Subquery in SELECT - Get order with customer total orders
SELECT
    o.order_id,
    o.order_date,
    o.total_amount,
    c.customer_name,
    (
        SELECT COUNT(*)
        FROM orders o2
        WHERE o2.customer_id = c.customer_id
          AND o2.order_status != 'cancelled'
    ) as customer_total_orders
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2024-01-01'
ORDER BY o.order_date DESC;

-- Correlated subquery - Find products with above-average sales
SELECT
    p.product_id,
    p.product_name,
    p.unit_price,
    sales.total_sold
FROM products p
INNER JOIN (
    SELECT
        oi.product_id,
        SUM(oi.quantity) as total_sold
    FROM order_items oi
    INNER JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date >= '2024-01-01'
    GROUP BY oi.product_id
) sales ON p.product_id = sales.product_id
WHERE sales.total_sold > (
    SELECT AVG(total_sold)
    FROM (
        SELECT SUM(oi2.quantity) as total_sold
        FROM order_items oi2
        INNER JOIN orders o2 ON oi2.order_id = o2.order_id
        WHERE o2.order_date >= '2024-01-01'
        GROUP BY oi2.product_id
    ) avg_sales
);

-- ===========================================
-- COMMON TABLE EXPRESSIONS (CTEs)
-- =========================================--

-- Recursive CTE - Get category hierarchy
WITH RECURSIVE category_hierarchy AS (
    -- Base case: root categories
    SELECT
        category_id,
        category_name,
        parent_category_id,
        0 as level,
        CAST(category_name AS CHAR(1000)) as path
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    -- Recursive case: child categories
    SELECT
        c.category_id,
        c.category_name,
        c.parent_category_id,
        ch.level + 1,
        CONCAT(ch.path, ' > ', c.category_name)
    FROM categories c
    INNER JOIN category_hierarchy ch ON c.parent_category_id = ch.category_id
)
SELECT * FROM category_hierarchy
ORDER BY path;

-- Multiple CTEs - Customer order analysis
WITH customer_orders AS (
    SELECT
        c.customer_id,
        c.customer_name,
        COUNT(o.order_id) as order_count,
        SUM(o.total_amount) as total_spent,
        AVG(o.total_amount) as avg_order_value
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status != 'cancelled'
    GROUP BY c.customer_id, c.customer_name
),
customer_segments AS (
    SELECT
        customer_id,
        customer_name,
        order_count,
        total_spent,
        CASE
            WHEN total_spent >= 10000 THEN 'VIP'
            WHEN total_spent >= 1000 THEN 'Gold'
            WHEN total_spent >= 100 THEN 'Silver'
            ELSE 'Bronze'
        END as customer_segment
    FROM customer_orders
)
SELECT
    cs.customer_segment,
    COUNT(*) as customer_count,
    AVG(cs.order_count) as avg_orders_per_customer,
    SUM(cs.total_spent) as total_segment_revenue,
    AVG(cs.total_spent) as avg_spent_per_customer
FROM customer_segments cs
GROUP BY cs.customer_segment
ORDER BY total_segment_revenue DESC;

-- ===========================================
-- WINDOW FUNCTIONS
-- =========================================--

-- ROW_NUMBER, RANK, DENSE_RANK
SELECT
    product_id,
    product_name,
    category_name,
    unit_price,
    ROW_NUMBER() OVER (PARTITION BY category_name ORDER BY unit_price DESC) as price_rank_in_category,
    RANK() OVER (PARTITION BY category_name ORDER BY unit_price DESC) as rank_in_category,
    DENSE_RANK() OVER (PARTITION BY category_name ORDER BY unit_price DESC) as dense_rank_in_category
FROM products p
INNER JOIN categories c ON p.category_id = c.category_id
WHERE p.is_active = TRUE
ORDER BY c.category_name, unit_price DESC;

-- Running totals and moving averages
SELECT
    order_date,
    COUNT(*) as daily_orders,
    SUM(total_amount) as daily_revenue,
    SUM(SUM(total_amount)) OVER (ORDER BY order_date) as running_revenue,
    AVG(SUM(total_amount)) OVER (ORDER BY order_date ROWS 6 PRECEDING) as weekly_avg_revenue,
    SUM(COUNT(*)) OVER (ORDER BY order_date ROWS 29 PRECEDING) as monthly_running_orders
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY order_date
ORDER BY order_date;

-- LAG and LEAD functions
SELECT
    product_id,
    product_name,
    month,
    monthly_sales,
    LAG(monthly_sales) OVER (PARTITION BY product_id ORDER BY month) as prev_month_sales,
    LEAD(monthly_sales) OVER (PARTITION BY product_id ORDER BY month) as next_month_sales,
    (monthly_sales - LAG(monthly_sales) OVER (PARTITION BY product_id ORDER BY month)) /
    NULLIF(LAG(monthly_sales) OVER (PARTITION BY product_id ORDER BY month), 0) * 100 as sales_growth_pct
FROM (
    SELECT
        oi.product_id,
        p.product_name,
        DATE_FORMAT(o.order_date, '%Y-%m') as month,
        SUM(oi.quantity * oi.unit_price) as monthly_sales
    FROM order_items oi
    INNER JOIN orders o ON oi.order_id = o.order_id
    INNER JOIN products p ON oi.product_id = p.product_id
    WHERE o.order_date >= '2024-01-01'
    GROUP BY oi.product_id, p.product_name, DATE_FORMAT(o.order_date, '%Y-%m')
) sales_data
ORDER BY product_id, month;

-- ===========================================
-- AGGREGATION AND GROUPING
-- =========================================--

-- Basic aggregation with ROLLUP
SELECT
    YEAR(order_date) as order_year,
    MONTH(order_date) as order_month,
    COUNT(*) as total_orders,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value,
    MIN(total_amount) as min_order_value,
    MAX(total_amount) as max_order_value
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY YEAR(order_date), MONTH(order_date) WITH ROLLUP
ORDER BY order_year, order_month;

-- Advanced aggregation with CUBE
SELECT
    c.category_name,
    YEAR(o.order_date) as order_year,
    COUNT(DISTINCT p.product_id) as products_sold,
    SUM(oi.quantity) as total_quantity,
    SUM(oi.quantity * oi.unit_price) as total_revenue
FROM categories c
INNER JOIN products p ON c.category_id = p.category_id
INNER JOIN order_items oi ON p.product_id = oi.product_id
INNER JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_date >= '2024-01-01'
GROUP BY c.category_name, YEAR(o.order_date) WITH ROLLUP;

-- HAVING clause with subquery
SELECT
    customer_id,
    customer_name,
    total_orders,
    total_spent
FROM (
    SELECT
        c.customer_id,
        c.customer_name,
        COUNT(o.order_id) as total_orders,
        SUM(o.total_amount) as total_spent
    FROM customers c
    INNER JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status != 'cancelled'
    GROUP BY c.customer_id, c.customer_name
) customer_summary
HAVING total_spent > (
    SELECT AVG(total_spent) * 1.5
    FROM (
        SELECT SUM(o2.total_amount) as total_spent
        FROM customers c2
        INNER JOIN orders o2 ON c2.customer_id = o2.customer_id
        WHERE o2.order_status != 'cancelled'
        GROUP BY c2.customer_id
    ) all_customers
);

-- ===========================================
-- SET OPERATIONS
-- =========================================--

-- UNION - Combine results from different queries
SELECT
    'Active Customers' as customer_type,
    customer_id,
    customer_name,
    customer_email,
    created_at
FROM customers
WHERE is_active = TRUE
  AND created_at >= '2024-01-01'

UNION

SELECT
    'Inactive Customers' as customer_type,
    customer_id,
    customer_name,
    customer_email,
    created_at
FROM customers
WHERE is_active = FALSE
  AND updated_at >= '2024-01-01'
ORDER BY created_at DESC;

-- INTERSECT - Find common results (MySQL 8.0.31+)
SELECT customer_id FROM orders WHERE order_date >= '2024-01-01'
INTERSECT
SELECT customer_id FROM customer_preferences WHERE preference_type = 'category';

-- EXCEPT/MINUS - Find differences
SELECT DISTINCT customer_id FROM customers
WHERE customer_id NOT IN (
    SELECT DISTINCT customer_id FROM orders WHERE order_date >= '2024-01-01'
);

-- ===========================================
-- STRING AND TEXT FUNCTIONS
-- =========================================--

-- Text search and manipulation
SELECT
    product_id,
    product_name,
    LEFT(description, 100) as short_description,
    LENGTH(description) as description_length,
    LOCATE('laptop', LOWER(description)) as laptop_mention_position,
    REPLACE(description, 'old_brand', 'new_brand') as updated_description,
    CONCAT(product_name, ' - ', sku) as full_product_name
FROM products
WHERE MATCH(product_name, description) AGAINST('laptop wireless' IN NATURAL LANGUAGE MODE)
ORDER BY MATCH(product_name, description) AGAINST('laptop wireless' IN NATURAL LANGUAGE MODE) DESC;

-- Regular expressions
SELECT
    customer_id,
    customer_name,
    customer_email,
    customer_phone
FROM customers
WHERE customer_email REGEXP '^[a-zA-Z0-9._%+-]+@(gmail|outlook|hotmail|yahoo)\\.com$'
   OR customer_phone REGEXP '^\\+1-[0-9]{3}-[0-9]{3}-[0-9]{4}$';

-- ===========================================
-- DATE AND TIME FUNCTIONS
-- =========================================--

-- Date calculations and formatting
SELECT
    order_id,
    order_date,
    DATE_FORMAT(order_date, '%M %d, %Y') as formatted_date,
    DAYOFWEEK(order_date) as day_of_week,
    DAYNAME(order_date) as day_name,
    WEEK(order_date) as week_number,
    MONTHNAME(order_date) as month_name,
    QUARTER(order_date) as quarter,
    YEAR(order_date) as year,

    -- Date arithmetic
    DATE_ADD(order_date, INTERVAL 30 DAY) as payment_due_date,
    DATEDIFF(CURDATE(), order_date) as days_since_order,
    TIMESTAMPDIFF(HOUR, order_date, NOW()) as hours_since_order,

    -- Business day calculations
    CASE
        WHEN DAYOFWEEK(order_date) IN (1,7) THEN 'Weekend'
        ELSE 'Weekday'
    END as day_type
FROM orders
WHERE order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
ORDER BY order_date DESC;

-- ===========================================
-- PERFORMANCE OPTIMIZATION TECHNIQUES
-- =========================================--

-- Force index usage (use with caution)
SELECT /*+ INDEX(orders, idx_orders_date_status) */
    order_id, customer_id, order_date, total_amount
FROM orders
WHERE order_date >= '2024-01-01'
  AND order_status = 'completed';

-- Optimize with STRAIGHT_JOIN for specific join order
SELECT STRAIGHT_JOIN
    c.customer_name,
    COUNT(o.order_id) as order_count,
    SUM(o.total_amount) as total_spent
FROM customers c
STRAIGHT_JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_date >= '2024-01-01'
GROUP BY c.customer_id, c.customer_name
ORDER BY total_spent DESC;

-- Use covering indexes effectively
SELECT /*+ INDEX(order_items, idx_order_items_product_quantity) */
    product_id,
    SUM(quantity) as total_sold,
    AVG(unit_price) as avg_price,
    COUNT(DISTINCT order_id) as order_count
FROM order_items
WHERE product_id IN (1, 2, 3, 4, 5)
GROUP BY product_id;

-- ===========================================
-- STORED PROCEDURES FOR COMPLEX QUERIES
-- =========================================--

DELIMITER ;;

-- Comprehensive customer analysis
CREATE PROCEDURE analyze_customer_behavior(
    IN start_date DATE,
    IN end_date DATE,
    IN min_orders INT
)
BEGIN
    -- Customer segmentation and analysis
    SELECT
        c.customer_id,
        c.customer_name,
        c.customer_email,
        c.created_at as registration_date,

        -- Order metrics
        COUNT(o.order_id) as total_orders,
        SUM(o.total_amount) as total_spent,
        AVG(o.total_amount) as avg_order_value,
        MIN(o.order_date) as first_order_date,
        MAX(o.order_date) as last_order_date,
        DATEDIFF(MAX(o.order_date), MIN(o.order_date)) as customer_lifetime_days,

        -- Product preferences
        GROUP_CONCAT(DISTINCT cat.category_name) as preferred_categories,
        COUNT(DISTINCT p.product_id) as unique_products_purchased,

        -- Behavioral scores
        CASE
            WHEN COUNT(o.order_id) >= 10 AND SUM(o.total_amount) >= 1000 THEN 'High Value'
            WHEN COUNT(o.order_id) >= 5 AND SUM(o.total_amount) >= 500 THEN 'Medium Value'
            WHEN COUNT(o.order_id) >= 1 THEN 'Low Value'
            ELSE 'Prospect'
        END as customer_segment,

        -- Recency, Frequency, Monetary (RFM) score
        CASE
            WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 30 THEN 5
            WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 90 THEN 4
            WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 180 THEN 3
            WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 365 THEN 2
            ELSE 1
        END as recency_score,

        CASE
            WHEN COUNT(o.order_id) >= 10 THEN 5
            WHEN COUNT(o.order_id) >= 7 THEN 4
            WHEN COUNT(o.order_id) >= 4 THEN 3
            WHEN COUNT(o.order_id) >= 2 THEN 2
            ELSE 1
        END as frequency_score,

        CASE
            WHEN SUM(o.total_amount) >= 1000 THEN 5
            WHEN SUM(o.total_amount) >= 500 THEN 4
            WHEN SUM(o.total_amount) >= 200 THEN 3
            WHEN SUM(o.total_amount) >= 50 THEN 2
            ELSE 1
        END as monetary_score

    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
        AND o.order_date BETWEEN start_date AND end_date
        AND o.order_status != 'cancelled'
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    LEFT JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN categories cat ON p.category_id = cat.category_id
    GROUP BY c.customer_id, c.customer_name, c.customer_email, c.created_at
    HAVING COUNT(o.order_id) >= min_orders
    ORDER BY total_spent DESC, total_orders DESC;
END;;

-- Product performance analysis
CREATE PROCEDURE analyze_product_performance(
    IN analysis_period_months INT
)
BEGIN
    DECLARE start_date DATE;
    SET start_date = DATE_SUB(CURDATE(), INTERVAL analysis_period_months MONTH);

    SELECT
        p.product_id,
        p.product_name,
        p.sku,
        cat.category_name,
        p.unit_price,

        -- Sales metrics
        COALESCE(SUM(oi.quantity), 0) as total_units_sold,
        COALESCE(SUM(oi.quantity * oi.unit_price), 0) as total_revenue,
        COALESCE(AVG(oi.unit_price), 0) as avg_selling_price,
        COUNT(DISTINCT o.order_id) as orders_containing_product,

        -- Inventory metrics
        COALESCE(pi.quantity_available, 0) as current_stock,
        COALESCE(pi.quantity_on_hand - pi.quantity_available, 0) as reserved_stock,

        -- Performance indicators
        CASE
            WHEN SUM(oi.quantity * oi.unit_price) >= 10000 THEN 'Top Performer'
            WHEN SUM(oi.quantity * oi.unit_price) >= 5000 THEN 'Good Performer'
            WHEN SUM(oi.quantity * oi.unit_price) >= 1000 THEN 'Moderate Performer'
            WHEN SUM(oi.quantity * oi.unit_price) > 0 THEN 'Low Performer'
            ELSE 'No Sales'
        END as performance_rating,

        -- Stock status
        CASE
            WHEN pi.quantity_available = 0 THEN 'Out of Stock'
            WHEN pi.quantity_available < 10 THEN 'Low Stock'
            WHEN pi.quantity_available < 50 THEN 'Medium Stock'
            ELSE 'Well Stocked'
        END as stock_status,

        -- Trend analysis
        ROUND(
            (SUM(oi.quantity * oi.unit_price) / NULLIF(analysis_period_months, 0)), 2
        ) as avg_monthly_revenue,

        -- Profitability (if cost data available)
        CASE
            WHEN p.cost_price IS NOT NULL AND p.unit_price > p.cost_price
            THEN ROUND(((p.unit_price - p.cost_price) / p.unit_price) * 100, 2)
            ELSE NULL
        END as profit_margin_pct

    FROM products p
    LEFT JOIN categories cat ON p.category_id = cat.category_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id
        AND o.order_date >= start_date
        AND o.order_status != 'cancelled'
    LEFT JOIN product_inventory pi ON p.product_id = pi.product_id
    WHERE p.is_active = TRUE
    GROUP BY p.product_id, p.product_name, p.sku, cat.category_name, p.unit_price,
             pi.quantity_available, pi.quantity_on_hand, p.cost_price
    ORDER BY total_revenue DESC;
END;;

DELIMITER ;

-- ===========================================
-- QUERY OPTIMIZATION BEST PRACTICES
-- =========================================--

/*
INDEXING STRATEGIES:
1. Index foreign keys automatically
2. Use composite indexes for WHERE clauses with multiple conditions
3. Consider covering indexes for frequent queries
4. Use partial indexes for selective conditions

QUERY OPTIMIZATION:
1. Avoid SELECT * - specify needed columns
2. Use LIMIT for large result sets
3. Prefer INNER JOIN over OUTER JOIN when possible
4. Use UNION ALL instead of UNION when duplicates aren't needed
5. Consider denormalization for read-heavy workloads

PERFORMANCE MONITORING:
1. Use EXPLAIN to analyze query execution
2. Monitor slow query log
3. Check performance_schema for query statistics
4. Use SHOW PROCESSLIST for active queries

COMMON PITFALLS TO AVOID:
1. Functions on indexed columns in WHERE clauses
2. Implicit type conversions
3. Correlated subqueries in large datasets
4. Missing indexes on JOIN conditions
5. Overuse of DISTINCT without need
*/

-- ===========================================
-- EXAMPLE USAGE
-- =========================================--

/*
-- Basic customer order query
SELECT * FROM customers WHERE customer_email = 'john@example.com';

-- Complex analytical query
CALL analyze_customer_behavior('2024-01-01', '2024-12-31', 1);

-- Product performance analysis
CALL analyze_product_performance(6);

-- CTE for hierarchical data
WITH RECURSIVE category_tree AS (
    SELECT category_id, category_name, 0 as level
    FROM categories WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, ct.level + 1
    FROM categories c
    JOIN category_tree ct ON c.parent_category_id = ct.category_id
)
SELECT * FROM category_tree ORDER BY level, category_name;

This comprehensive querying guide demonstrates:
- Basic to advanced SELECT statements
- Various JOIN techniques and best practices
- Subqueries, CTEs, and window functions
- Aggregation and grouping operations
- Set operations and string functions
- Date/time manipulation
- Performance optimization techniques
- Stored procedures for complex queries

Always consider indexing strategies and EXPLAIN plans for query optimization.
*/
