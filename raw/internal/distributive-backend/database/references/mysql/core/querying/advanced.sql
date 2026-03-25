-- # Ultimate Advanced Subquery Pattern Library
-- Each pattern includes: scenario, code, and explanation. For MySQL/PostgreSQL unless noted.

---

-- 1. Scalar Subquery in SELECT (Inline Maximum)
-- Scenario: Show each category with the max price for a specific category inline.
SELECT name, (SELECT MAX(list_price) FROM products WHERE category_id = 1) AS max_price
FROM categories;
-- Explanation: Scalar subquery returns a single value for each row.

---

-- 2. Scalar Subquery in WHERE (Dynamic Filter)
-- Scenario: Find all cities in the same country as 'United States'.
SELECT city
FROM city
WHERE country_id = (
    SELECT country_id FROM country WHERE country = 'United States'
);
-- Explanation: Subquery returns a single value for filtering.

---

-- 3. Subquery in FROM (Derived Table)
-- Scenario: Aggregate sales by month, then filter months with high sales.
SELECT month, total_sales
FROM (
    SELECT DATE_TRUNC('month', sale_date) AS month, SUM(amount) AS total_sales
    FROM sales
    GROUP BY month
) AS monthly_sales
WHERE total_sales > 10000;
-- Explanation: Subquery in FROM acts as a temporary table.

---

-- 4. Correlated Subquery in WHERE
-- Scenario: Find films longer than the average for their rating.
SELECT film_id, title, length, rating
FROM film f
WHERE length > (
    SELECT AVG(length) FROM film WHERE rating = f.rating
);
-- Explanation: Subquery references outer query columns (correlated).

---

-- 5. EXISTS Subquery
-- Scenario: Find users who have placed at least one order.
SELECT name FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
);
-- Explanation: EXISTS returns true if subquery returns any rows.

---

-- 6. NOT EXISTS Subquery
-- Scenario: Find users who have never placed an order.
SELECT name FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
);
-- Explanation: NOT EXISTS returns true if subquery returns no rows.

---

-- 7. IN Subquery
-- Scenario: Find products in categories with more than 10 products.
SELECT name FROM products
WHERE category_id IN (
    SELECT category_id FROM products GROUP BY category_id HAVING COUNT(*) > 10
);
-- Explanation: IN matches any value returned by the subquery.

---

-- 8. ANY/ALL Subquery (Comparison)
-- Scenario: Find employees with a salary higher than any manager.
SELECT * FROM employees
WHERE salary > ANY (SELECT salary FROM managers);
-- Explanation: ANY/ALL compare a value to a set returned by a subquery.

---

-- 9. Subquery in SELECT (Correlated Count)
-- Scenario: Show each user and their order count.
SELECT name, (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count
FROM users u;
-- Explanation: Scalar correlated subquery for per-row aggregation.

---

-- 10. Subquery in CASE Expression
-- Scenario: Label users as 'VIP' if they have >5 orders.
SELECT name,
       CASE WHEN (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) > 5 THEN 'VIP' ELSE 'Regular' END AS user_type
FROM users u;
-- Explanation: Subquery used as a condition in CASE.

---

-- 11. Subquery in UPDATE
-- Scenario: Set user status to 'inactive' if no orders in last year.
UPDATE users u
SET status = 'inactive'
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.created_at > NOW() - INTERVAL '1 year'
);
-- Explanation: Subqueries can be used in DML statements.

---

-- 12. Subquery in DELETE
-- Scenario: Delete products not ordered in the last year.
DELETE FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.product_id = p.id AND o.created_at > NOW() - INTERVAL '1 year'
);
-- Explanation: Subqueries in DELETE for conditional removal.

---

-- 13. Subquery in INSERT (INSERT ... SELECT)
-- Scenario: Archive old orders to a history table.
INSERT INTO orders_history (id, user_id, amount, created_at)
SELECT id, user_id, amount, created_at
FROM orders
WHERE created_at < NOW() - INTERVAL '2 years';
-- Explanation: Subquery as data source for INSERT.

---

-- 14. Lateral Subquery (PostgreSQL)
-- Scenario: For each user, get their most recent order.
SELECT u.id, u.name, o.id AS last_order_id, o.created_at
FROM users u
LEFT JOIN LATERAL (
    SELECT id, created_at FROM orders o WHERE o.user_id = u.id ORDER BY created_at DESC LIMIT 1
) o ON TRUE;
-- Explanation: LATERAL allows subquery to reference outer row (PostgreSQL).

---

-- 15. Anti-Pattern: Subquery in SELECT vs. JOIN
-- Scenario: Show total order amount per user (inefficient subquery).
SELECT u.id, u.name, (SELECT SUM(amount) FROM orders o WHERE o.user_id = u.id) AS total_amount
FROM users u;
-- Explanation: For large data, prefer JOIN+GROUP BY for performance.

---

-- 16. Subquery with Window Function
-- Scenario: Rank users by their order count using a subquery.
SELECT id, name, order_count,
       RANK() OVER (ORDER BY order_count DESC) AS order_rank
FROM (
    SELECT u.id, u.name, COUNT(o.id) AS order_count
    FROM users u LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.name
) ranked;
-- Explanation: Subquery provides input for window function.

---

-- 17. Subquery with ARRAY_AGG (PostgreSQL)
-- Scenario: List all product names ordered by each user.
SELECT u.id, u.name, ARRAY(
    SELECT p.name FROM orders o JOIN products p ON o.product_id = p.id WHERE o.user_id = u.id
) AS products
FROM users u;
-- Explanation: Subquery returns an array per row (PostgreSQL).

---

-- 18. Subquery with JSON_AGG (PostgreSQL)
-- Scenario: Aggregate all order details as JSON for each user.
SELECT u.id, u.name, (
    SELECT JSON_AGG(ROW_TO_JSON(o)) FROM orders o WHERE o.user_id = u.id
) AS orders_json
FROM users u;
-- Explanation: Subquery returns JSON array per row (PostgreSQL).

---

-- 19. Subquery with DISTINCT
-- Scenario: Find users who have ordered from more than 3 unique categories.
SELECT u.id, u.name
FROM users u
WHERE (
    SELECT COUNT(DISTINCT p.category_id)
    FROM orders o JOIN products p ON o.product_id = p.id
    WHERE o.user_id = u.id
) > 3;
-- Explanation: Subquery with DISTINCT for unique counts.

---

-- 20. Subquery with LIMIT/OFFSET (PostgreSQL)
-- Scenario: For each user, get their second most recent order.
SELECT u.id, u.name, (
    SELECT id FROM orders o WHERE o.user_id = u.id ORDER BY created_at DESC OFFSET 1 LIMIT 1
) AS second_order_id
FROM users u;
-- Explanation: Subquery with OFFSET/LIMIT for Nth value (PostgreSQL).

---

-- 21. Subquery with GROUP BY in WHERE
-- Scenario: Find products ordered more than 10 times.
SELECT name FROM products p
WHERE (
    SELECT COUNT(*) FROM orders o WHERE o.product_id = p.id
) > 10;
-- Explanation: Subquery with aggregation for filtering.

---

-- 22. Subquery with HAVING
-- Scenario: Find categories with at least one expensive product.
SELECT category_id
FROM products
GROUP BY category_id
HAVING MAX(list_price) > (
    SELECT AVG(list_price) FROM products
);
-- Explanation: Subquery in HAVING for group-level filtering.

---

-- 23. Subquery in SELECT with EXISTS
-- Scenario: Show if each user has placed any orders.
SELECT name, EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
) AS has_orders
FROM users u;
-- Explanation: EXISTS as a boolean column in SELECT.

---

-- 24. Subquery with NOT IN (NULL-safe)
-- Scenario: Find products never ordered (NULL-safe).
SELECT name FROM products
WHERE id NOT IN (
    SELECT product_id FROM orders WHERE product_id IS NOT NULL
);
-- Explanation: NOT IN with NULL handling to avoid missing rows.

---

-- 25. Subquery with UNION/UNION ALL
-- Scenario: Find all users who are either customers or suppliers.
SELECT name FROM customers
UNION
SELECT name FROM suppliers;
-- Explanation: Subqueries combined with UNION for set logic.

---

-- 26. Subquery with INTERSECT/EXCEPT (PostgreSQL)
-- Scenario: Find users who are both customers and suppliers.
SELECT name FROM customers
INTERSECT
SELECT name FROM suppliers;
-- Explanation: INTERSECT/EXCEPT for set operations (PostgreSQL).

---

-- 27. Subquery with ARRAY (PostgreSQL)
-- Scenario: List all order IDs for each user as an array.
SELECT u.id, u.name, ARRAY(
    SELECT o.id FROM orders o WHERE o.user_id = u.id
) AS order_ids
FROM users u;
-- Explanation: Subquery returns array per row (PostgreSQL).

---

-- 28. Subquery with JSON_OBJECTAGG (PostgreSQL)
-- Scenario: Aggregate product sales as JSON per category.
SELECT c.id, c.name, (
    SELECT JSON_OBJECT_AGG(p.name, s.total) FROM (
        SELECT p.name, SUM(o.amount) AS total
        FROM products p JOIN orders o ON p.id = o.product_id
        WHERE p.category_id = c.id
        GROUP BY p.name
    ) s
) AS sales_json
FROM categories c;
-- Explanation: Subquery returns JSON object per row (PostgreSQL).

---

-- 29. Subquery with Windowed Aggregate in WHERE
-- Scenario: Find users whose order count is above the average.
SELECT id, name
FROM (
    SELECT u.id, u.name, COUNT(o.id) AS order_count
    FROM users u LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.name
) ranked
WHERE order_count > (
    SELECT AVG(order_count) FROM (
        SELECT COUNT(*) AS order_count FROM orders GROUP BY user_id
    ) t
);
-- Explanation: Subquery with windowed aggregate for advanced filtering.

---

-- 30. Subquery with Recursive CTE (PostgreSQL)
-- Scenario: Find all descendants in a category tree.
WITH RECURSIVE category_tree AS (
    SELECT id, parent_id FROM categories WHERE id = 1
    UNION ALL
    SELECT c.id, c.parent_id FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree;
-- Explanation: Recursive CTE as an advanced subquery pattern.

---

-- 31. Subquery with CROSS APPLY (SQL Server/Oracle)
-- Scenario: For each user, get their latest order (SQL Server syntax).
SELECT u.id, u.name, o.id AS last_order_id
FROM users u
CROSS APPLY (
    SELECT TOP 1 id FROM orders o WHERE o.user_id = u.id ORDER BY created_at DESC
) o;
-- Explanation: CROSS APPLY is like LATERAL JOIN in PostgreSQL.

---

-- 32. Subquery with Anti-Join (NOT EXISTS)
-- Scenario: Find users who have never placed an order (anti-join).
SELECT u.id, u.name
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
);
-- Explanation: Anti-join pattern using NOT EXISTS.

---

-- 33. Subquery with Multiple Correlations
-- Scenario: Find orders where the amount is above the user's average.
SELECT o.id, o.user_id, o.amount
FROM orders o
WHERE o.amount > (
    SELECT AVG(amount) FROM orders WHERE user_id = o.user_id
);
-- Explanation: Correlated subquery with multiple references.

---

-- 34. Subquery with LATERAL JOIN and Aggregation (PostgreSQL)
-- Scenario: For each user, get their top 3 most expensive orders.
SELECT u.id, u.name, o.id AS order_id, o.amount
FROM users u
JOIN LATERAL (
    SELECT id, amount FROM orders o WHERE o.user_id = u.id ORDER BY amount DESC LIMIT 3
) o ON TRUE;
-- Explanation: LATERAL JOIN for per-row aggregation (PostgreSQL).

---

-- 35. Subquery with FILTER (PostgreSQL)
-- Scenario: Count only completed orders per user.
SELECT u.id, u.name, (
    SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id AND o.status = 'completed'
) AS completed_orders
FROM users u;
-- Explanation: Subquery with filter condition for aggregation.

---

-- 36. Subquery with Windowed Percentile (PostgreSQL)
-- Scenario: Find users in the top 10% by order count.
SELECT id, name, order_count
FROM (
    SELECT u.id, u.name, COUNT(o.id) AS order_count,
           PERCENT_RANK() OVER (ORDER BY COUNT(o.id) DESC) AS pct_rank
    FROM users u LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.name
) ranked
WHERE pct_rank <= 0.1;
-- Explanation: Subquery with windowed percentile for advanced analytics.

---

-- 37. Subquery with ARRAY_AGG and FILTER (PostgreSQL)
-- Scenario: List all failed order IDs for each user.
SELECT u.id, u.name, ARRAY(
    SELECT o.id FROM orders o WHERE o.user_id = u.id AND o.status = 'failed'
) AS failed_orders
FROM users u;
-- Explanation: Subquery with array aggregation and filter.

---

-- 38. Subquery with JSONB_AGG and Condition (PostgreSQL)
-- Scenario: Aggregate all shipped orders as JSONB for each user.
SELECT u.id, u.name, (
    SELECT JSONB_AGG(ROW_TO_JSON(o)) FROM orders o WHERE o.user_id = u.id AND o.status = 'shipped'
) AS shipped_orders_jsonb
FROM users u;
-- Explanation: Subquery with JSONB aggregation and condition.

---

-- 39. Subquery with Anti-Pattern: N+1 Query
-- Scenario: For each user, fetch their orders (inefficient pattern).
SELECT u.id, u.name, (
    SELECT ARRAY_AGG(id) FROM orders o WHERE o.user_id = u.id
) AS order_ids
FROM users u;
-- Explanation: N+1 query anti-pattern; prefer JOIN+GROUP BY for large data.

---

-- 40. Subquery with Anti-Pattern: Scalar Subquery in WHERE for Large Sets
-- Scenario: Find products in categories with >1000 products (inefficient).
SELECT name FROM products
WHERE category_id = (
    SELECT category_id FROM products GROUP BY category_id HAVING COUNT(*) > 1000
);
-- Explanation: Scalar subquery in WHERE can be slow for large sets; prefer IN or JOIN.

---

-- 41. Subquery with Multi-Level Correlation
-- Scenario: Find orders where the amount is above the average for the user's region.
SELECT o.id, o.user_id, o.amount
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.amount > (
    SELECT AVG(amount) FROM orders o2
    JOIN users u2 ON o2.user_id = u2.id
    WHERE u2.region = u.region
);
-- Explanation: Multi-level correlated subquery for advanced analytics.

---

-- 42. Subquery with EXISTS and JOIN
-- Scenario: Find users who have ordered a product in a specific category.
SELECT DISTINCT u.id, u.name
FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o
    JOIN products p ON o.product_id = p.id
    WHERE o.user_id = u.id AND p.category_id = 5
);
-- Explanation: EXISTS with JOIN for complex membership checks.

---

-- 43. Subquery with NOT EXISTS and Anti-Join
-- Scenario: Find products never ordered by VIP users.
SELECT p.id, p.name
FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM orders o
    JOIN users u ON o.user_id = u.id
    WHERE o.product_id = p.id AND u.is_vip = TRUE
);
-- Explanation: Anti-join with NOT EXISTS and JOIN.

---

-- 44. Subquery with Window Function in Subquery
-- Scenario: Find users whose latest order is above the average order amount.
SELECT u.id, u.name
FROM users u
WHERE (
    SELECT amount FROM orders o WHERE o.user_id = u.id ORDER BY created_at DESC LIMIT 1
) > (
    SELECT AVG(amount) FROM orders
);
-- Explanation: Subquery with window logic for advanced filtering.

---

-- 45. Subquery with GROUPING SETS (PostgreSQL)
-- Scenario: Aggregate sales by region and by product.
SELECT region, product_id, SUM(amount) AS total_sales
FROM sales
GROUP BY GROUPING SETS ((region), (product_id));
-- Explanation: GROUPING SETS as a subquery alternative for multi-level aggregation.

---

-- 46. Subquery with CTE and Correlation
-- Scenario: Find users whose order count is above the average for their cohort.
WITH cohort_avg AS (
    SELECT cohort, AVG(order_count) AS avg_orders
    FROM (
        SELECT u.cohort, COUNT(o.id) AS order_count
        FROM users u LEFT JOIN orders o ON u.id = o.user_id
        GROUP BY u.id, u.cohort
    ) t
    GROUP BY cohort
)
SELECT u.id, u.name
FROM users u
WHERE (
    SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id
) > (
    SELECT avg_orders FROM cohort_avg WHERE cohort = u.cohort
);
-- Explanation: CTE with correlated subquery for advanced cohort analysis.

---

-- 47. Subquery with ARRAY_CONTAINS (PostgreSQL)
-- Scenario: Find users who have ordered any product in a target set.
SELECT u.id, u.name
FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.user_id = u.id AND o.product_id = ANY(ARRAY[1,2,3,4])
);
-- Explanation: ANY/ARRAY for set membership in subqueries.

---

-- 48. Subquery with JSONB Path Query (PostgreSQL)
-- Scenario: Find users whose profile JSON contains a specific nested value.
SELECT id, name
FROM users
WHERE profile_json #> '{settings,notifications,email}' IS NOT NULL;
-- Explanation: JSONB path query as a subquery filter.

---

-- 49. Subquery with LATERAL and Aggregation (PostgreSQL)
-- Scenario: For each user, get the sum of their last 5 orders.
SELECT u.id, u.name, o.total_last5
FROM users u
LEFT JOIN LATERAL (
    SELECT SUM(amount) AS total_last5
    FROM orders o WHERE o.user_id = u.id ORDER BY created_at DESC LIMIT 5
) o ON TRUE;
-- Explanation: LATERAL subquery for per-row rolling aggregation.

---

-- 50. Subquery with Anti-Pattern: Deeply Nested Subqueries
-- Scenario: Find users with a deeply nested subquery (hard to maintain).
SELECT id, name
FROM users
WHERE id IN (
    SELECT user_id FROM orders WHERE product_id IN (
        SELECT id FROM products WHERE category_id IN (
            SELECT id FROM categories WHERE parent_id = 1
        )
    )
);
-- Explanation: Deep nesting is hard to debug; flatten with JOINs/CTEs when possible.

---

-- 51. Subquery with Windowed SUM in WHERE
-- Scenario: Find users whose total order amount is above the 90th percentile.
SELECT id, name
FROM (
    SELECT u.id, u.name, SUM(o.amount) AS total_amount,
           PERCENT_RANK() OVER (ORDER BY SUM(o.amount)) AS pct_rank
    FROM users u LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.name
) ranked
WHERE pct_rank > 0.9;
-- Explanation: Subquery with windowed SUM and percentile.

---

-- 52. Subquery with ARRAY_AGG and HAVING (PostgreSQL)
-- Scenario: Find users who have ordered all products in a set.
SELECT u.id, u.name
FROM users u
WHERE ARRAY(
    SELECT DISTINCT o.product_id FROM orders o WHERE o.user_id = u.id
) @> ARRAY[1,2,3];
-- Explanation: ARRAY_AGG and array containment for set coverage.

---

-- 53. Subquery with JSONB Array Length (PostgreSQL)
-- Scenario: Find users with more than 3 addresses in their profile JSON.
SELECT id, name
FROM users
WHERE jsonb_array_length(profile_json->'addresses') > 3;
-- Explanation: JSONB array length as a subquery filter.

---

-- 54. Subquery with Anti-Pattern: Scalar Subquery in SELECT for Large Data
-- Scenario: Show each user's most recent order amount (inefficient for large data).
SELECT u.id, u.name, (
    SELECT amount FROM orders o WHERE o.user_id = u.id ORDER BY created_at DESC LIMIT 1
) AS last_order_amount
FROM users u;
-- Explanation: For large data, prefer window functions or JOIN LATERAL.

---

-- 55. Subquery with NOT IN and NULLs (Anti-Pattern)
-- Scenario: Find products never ordered, but NOT IN fails if NULL present.
SELECT name FROM products
WHERE id NOT IN (
    SELECT product_id FROM orders
);
-- Explanation: NOT IN returns no rows if subquery returns NULL; use NOT EXISTS instead.

---

-- 56. Subquery with EXISTS and Aggregation
-- Scenario: Find users who have placed more than 5 orders.
SELECT id, name
FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
    GROUP BY o.user_id HAVING COUNT(*) > 5
);
-- Explanation: EXISTS with aggregation for threshold checks.

---

-- 57. Subquery with Windowed AVG in WHERE
-- Scenario: Find products with price above the average for their category.
SELECT id, name, list_price
FROM products p
WHERE list_price > (
    SELECT AVG(list_price) FROM products WHERE category_id = p.category_id
);
-- Explanation: Correlated subquery for per-group average comparison.

---

-- 58. Subquery with ARRAY_AGG and ORDER BY (PostgreSQL)
-- Scenario: List all order IDs for each user, ordered by date.
SELECT u.id, u.name, ARRAY(
    SELECT o.id FROM orders o WHERE o.user_id = u.id ORDER BY o.created_at
) AS ordered_order_ids
FROM users u;
-- Explanation: ARRAY_AGG with ORDER BY for ordered arrays.

---

-- 59. Subquery with JSONB_AGG and Filtering (PostgreSQL)
-- Scenario: Aggregate all failed orders as JSONB for each user.
SELECT u.id, u.name, (
    SELECT JSONB_AGG(ROW_TO_JSON(o)) FROM orders o WHERE o.user_id = u.id AND o.status = 'failed'
) AS failed_orders_jsonb
FROM users u;
-- Explanation: JSONB_AGG with filter for error analytics.

---

-- 60. Subquery with Recursive CTE for Graph Traversal (PostgreSQL)
-- Scenario: Find all users connected in a social graph.
WITH RECURSIVE connections AS (
    SELECT user_id, friend_id FROM friendships WHERE user_id = 1
    UNION ALL
    SELECT f.user_id, f.friend_id FROM friendships f
    JOIN connections c ON f.user_id = c.friend_id
)
SELECT DISTINCT friend_id FROM connections;
-- Explanation: Recursive CTE for graph traversal as a subquery pattern.

---

-- 61. Recursive Subquery for Hierarchical Aggregation
-- Scenario: Aggregate sales up a product category tree using recursive subqueries.
WITH RECURSIVE category_tree AS (
  SELECT id, parent_id, name FROM categories WHERE id = 1
  UNION ALL
  SELECT c.id, c.parent_id, c.name FROM categories c
  JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT ct.name, SUM(s.amount) AS total_sales
FROM category_tree ct
JOIN sales s ON s.category_id = ct.id
GROUP BY ct.name;
-- Aggregates sales for a category and all its descendants.

---

-- 62. Subquery for Dynamic Pivoting (Vendor-Specific)
-- Scenario: Pivot sales by month using subqueries (PostgreSQL example).
SELECT product_id,
  (SELECT SUM(amount) FROM sales WHERE product_id = p.product_id AND month = '2025-01') AS jan,
  (SELECT SUM(amount) FROM sales WHERE product_id = p.product_id AND month = '2025-02') AS feb,
  (SELECT SUM(amount) FROM sales WHERE product_id = p.product_id AND month = '2025-03') AS mar
FROM (SELECT DISTINCT product_id FROM sales) p;
-- Dynamically pivots sales by month using scalar subqueries.

---

-- 63. Subquery for GDPR/Privacy Filtering
-- Scenario: Filter out users who have opted out of tracking using a subquery.
SELECT * FROM user_activity ua
WHERE ua.user_id NOT IN (SELECT user_id FROM privacy_opt_outs);
-- Ensures privacy compliance by excluding opted-out users.

---

-- 64. Subquery for Streaming Data Consistency Check
-- Scenario: Find events in the stream that have not been processed by downstream jobs.
SELECT e.event_id FROM events_stream e
WHERE NOT EXISTS (
  SELECT 1 FROM processed_events p WHERE p.event_id = e.event_id
);
-- Detects lag or missing processing in streaming pipelines.

---

-- 65. Subquery for Feature Flag Rollout Analysis
-- Scenario: Analyze users exposed to a feature flag using a subquery.
SELECT u.user_id, u.email
FROM users u
WHERE EXISTS (
  SELECT 1 FROM user_feature_flags f WHERE f.user_id = u.user_id AND f.feature_name = 'new_checkout' AND f.enabled = 1
);
-- Identifies users in a feature rollout cohort.

---

-- 66. Subquery for LLM/AI Model Usage Tracking
-- Scenario: Find all users who have used a specific LLM model version.
SELECT DISTINCT user_id
FROM ai_usage
WHERE model_version = (
  SELECT version FROM llm_models WHERE name = 'gpt-5' AND active = 1
);
-- Tracks usage of a specific AI model version.

---

-- 67. Subquery for Data Mesh Domain Isolation
-- Scenario: Ensure queries only access data within the user's assigned data domain.
SELECT * FROM orders o
WHERE o.domain_id = (
  SELECT domain_id FROM user_domains WHERE user_id = 123
);
-- Enforces data mesh domain boundaries.

---

-- 68. Subquery for Cost/Performance Optimization (Anti-Pattern)
-- Scenario: Using a subquery in SELECT for row-by-row lookup (anti-pattern).
SELECT o.order_id, (
  SELECT SUM(amount) FROM payments p WHERE p.order_id = o.order_id
) AS total_paid
FROM orders o;
-- Anti-pattern: Can cause N+1 query performance issues. Prefer JOIN + GROUP BY.

---

-- 69. Subquery for Blue/Green Deployment Validation
-- Scenario: Compare user counts between blue and green environments using subqueries.
SELECT (
  SELECT COUNT(*) FROM users WHERE env = 'blue'
) AS blue_count,
(
  SELECT COUNT(*) FROM users WHERE env = 'green'
) AS green_count;
-- Validates parity between deployment environments.

---

-- 70. Subquery for Chaos Engineering (Random Sampling)
-- Scenario: Randomly select users for chaos testing using a subquery.
SELECT * FROM users
WHERE user_id IN (
  SELECT user_id FROM (
    SELECT user_id FROM users ORDER BY RAND() LIMIT 100
  ) chaos_sample
);
-- Randomly samples users for chaos experiments.

---

-- 71. Subquery for Observability/Drift Detection
-- Scenario: Detect drift in feature flag state using subqueries.
SELECT feature_name FROM feature_flags f
WHERE f.enabled <> (
  SELECT expected_state FROM feature_flag_drift WHERE feature_name = f.feature_name
);
-- Finds flags where actual and expected state differ.

---

-- 72. Subquery for Serverless/Edge Data Partitioning
-- Scenario: Route queries to the correct edge partition using a subquery.
SELECT * FROM edge_data
WHERE partition_id = (
  SELECT partition_id FROM edge_partitions WHERE location = 'us-west-1'
);
-- Ensures data locality in edge/serverless DBs.

---

-- 73. Subquery for Real-Time Analytics (Materialized View Validation)
-- Scenario: Find discrepancies between source and materialized view using subqueries.
SELECT id FROM source_table
WHERE value <> (
  SELECT value FROM materialized_view WHERE id = source_table.id
);
-- Detects lag or errors in real-time analytics pipelines.

---

-- 74. Subquery for GitOps/Flag-as-Code Drift
-- Scenario: Detect feature flags that differ between DB and code repo.
SELECT feature_name FROM feature_flags f
WHERE f.enabled <> (
  SELECT state_in_code FROM feature_flag_as_code WHERE feature_name = f.feature_name
);
-- Ensures DB and code repo flag state are in sync.

---

-- 75. Subquery for Multi-Cloud Consistency
-- Scenario: Find features enabled in one cloud but not another using subqueries.
SELECT feature_name FROM cloud_feature_flags
WHERE cloud_provider = 'aws' AND enabled = 1
AND feature_name NOT IN (
  SELECT feature_name FROM cloud_feature_flags WHERE cloud_provider = 'gcp' AND enabled = 1
);
-- Detects cross-cloud flag drift.

---

-- 76. Subquery for Privacy/Compliance (Data Residency)
-- Scenario: Find users whose data is stored outside their residency region.
SELECT user_id FROM user_data u
WHERE u.region <> (
  SELECT residency_region FROM feature_flag_data_residency WHERE feature_name = 'user_data' AND enforced_at IS NOT NULL
);
-- Ensures data residency compliance.

---

-- 77. Subquery for Automated Rollback Detection
-- Scenario: Find features that were rolled back in the last 24 hours using a subquery.
SELECT feature_name FROM feature_flag_rollbacks
WHERE rolled_back_at >= NOW() - INTERVAL 1 DAY;
-- Identifies recent rollbacks for audit.

---

-- 78. Subquery for SLO/SLA Breach Detection
-- Scenario: Find features auto-disabled due to SLO/SLA breach using a subquery.
SELECT feature_name FROM flag_slo_breach_auto_disable
WHERE slo_breached = 1;
-- Surfaces features disabled for reliability reasons.

---

-- 79. Subquery for AI/ML Feature Flag Recommendation
-- Scenario: Find features where AI recommends a different state than current.
SELECT feature_name FROM ai_flag_recommendations r
JOIN feature_flags f ON r.feature_name = f.feature_name
WHERE r.recommended_state <> f.enabled;
-- Surfaces AI-driven flag recommendations.

---

-- 80. Subquery for Data Lineage/Traceability
-- Scenario: Trace all tables affected by a feature flag using subqueries.
SELECT DISTINCT source_table, target_table FROM feature_flag_lineage
WHERE feature_name = 'new_etl_pipeline';
-- Enables data lineage tracking for compliance.

---

-- 81. Subquery for Multi-Level Recursive Permission Checks
-- Scenario: Check if a user has access via direct or inherited group membership.
WITH RECURSIVE user_groups AS (
  SELECT group_id FROM user_group_map WHERE user_id = 123
  UNION ALL
  SELECT g.parent_group_id FROM groups g
  JOIN user_groups ug ON g.group_id = ug.group_id
)
SELECT * FROM resources r
WHERE r.group_id IN (SELECT group_id FROM user_groups);
-- Handles deep, recursive permission inheritance.

---

-- 82. Subquery for Data Versioning/Temporal Queries
-- Scenario: Fetch the latest version of each record using a subquery.
SELECT * FROM data_versions dv
WHERE dv.version = (
  SELECT MAX(version) FROM data_versions WHERE record_id = dv.record_id
);
-- Ensures only the latest version per record is returned.

---

-- 83. Subquery for Real-Time Fraud Detection
-- Scenario: Flag transactions with no matching user session in the last 5 minutes.
SELECT t.* FROM transactions t
WHERE NOT EXISTS (
  SELECT 1 FROM user_sessions s WHERE s.user_id = t.user_id AND s.last_active >= NOW() - INTERVAL 5 MINUTE
);
-- Detects potentially fraudulent activity.

---

-- 84. Subquery for Data Masking Based on Feature Flag
-- Scenario: Mask sensitive data if a feature flag is enabled (using subquery in SELECT).
SELECT user_id,
  CASE WHEN (
    SELECT mask_enabled FROM feature_flag_data_masking WHERE feature_name = 'ssn_masking'
  ) = 1 THEN '***MASKED***' ELSE ssn END AS ssn
FROM users;
-- Dynamically masks data based on flag state.

---

-- 85. Subquery for Vector Similarity Search (AI/ML)
-- Scenario: Retrieve top-N similar items using a subquery (PostgreSQL/pgvector example).
SELECT * FROM items
WHERE id IN (
  SELECT id FROM (
    SELECT id, embedding <#> '[0.1,0.2,0.3]' AS distance FROM items ORDER BY distance ASC LIMIT 10
  ) v
);
-- Finds top-N most similar vectors.

---

-- 86. Subquery for Edge/IoT Data Isolation
-- Scenario: Query only data from the current edge location using a subquery.
SELECT * FROM sensor_data
WHERE edge_location = (
  SELECT edge_location FROM edge_feature_flags WHERE feature_name = 'sensor_data' AND enabled = 1
);
-- Ensures edge-local data access.

---

-- 87. Subquery for Streaming Watermark Validation
-- Scenario: Find records lagging behind the current stream watermark.
SELECT * FROM events e
WHERE e.event_time < (
  SELECT MAX(watermark) FROM stream_watermarks WHERE stream_id = e.stream_id
);
-- Detects lagging events in streaming pipelines.

---

-- 88. Subquery for Data Quality/Validation Checks
-- Scenario: Find records failing validation rules using a subquery.
SELECT * FROM orders o
WHERE NOT EXISTS (
  SELECT 1 FROM feature_flag_data_validation v WHERE v.feature_name = 'order_validation' AND v.validation_enabled = 1
);
-- Surfaces records when validation is disabled.

---

-- 89. Subquery for Canary/Shadow Table Comparison
-- Scenario: Compare row counts between canary and prod tables using subqueries.
SELECT (
  SELECT COUNT(*) FROM orders_canary
) AS canary_count,
(
  SELECT COUNT(*) FROM orders_prod
) AS prod_count;
-- Validates canary vs. prod data.

---

-- 90. Subquery for Automated Data Remediation
-- Scenario: Find records eligible for auto-remediation based on a flag.
SELECT * FROM data_issues di
WHERE EXISTS (
  SELECT 1 FROM feature_flag_data_quality fq WHERE fq.feature_name = 'auto_remediate' AND fq.quality_checks_enabled = 1
);
-- Enables automated remediation when flag is on.

---

-- 91. Subquery for Cross-Region Data Consistency
-- Scenario: Find records present in one region but missing in another.
SELECT id FROM data_us_east
WHERE id NOT IN (
  SELECT id FROM data_eu_west
);
-- Detects cross-region data drift.

---

-- 92. Subquery for Feature Flag-Driven Data Partitioning
-- Scenario: Route queries to the correct partition based on a flag.
SELECT * FROM partitioned_data
WHERE partition_id = (
  SELECT partitioning_enabled FROM feature_flag_data_partitioning WHERE feature_name = 'partitioned_data'
);
-- Dynamically routes based on flag state.

---

-- 93. Subquery for LLM/AI Prompt Usage Analytics
-- Scenario: Find users who used a specific LLM prompt version.
SELECT DISTINCT user_id FROM llm_usage
WHERE prompt_version = (
  SELECT prompt_version FROM llm_prompt_version_flags WHERE feature_name = 'summarization' AND enabled = 1
);
-- Tracks prompt version adoption.

---

-- 94. Subquery for Data Mesh Federated Querying
-- Scenario: Aggregate data across mesh domains using subqueries.
SELECT domain_name, (
  SELECT COUNT(*) FROM orders o WHERE o.domain_name = d.domain_name
) AS order_count
FROM data_mesh_domains d;
-- Federated aggregation across domains.

---

-- 95. Subquery for Cost/Performance Analytics
-- Scenario: Find queries exceeding cost thresholds using subqueries.
SELECT query_id FROM query_costs qc
WHERE qc.cost > (
  SELECT cost_threshold FROM cost_settings WHERE environment = 'prod'
);
-- Surfaces expensive queries for review.

---

-- 96. Subquery for Automated Data Expiry/Retention
-- Scenario: Find data eligible for expiry based on retention flag.
SELECT * FROM user_data ud
WHERE ud.created_at < NOW() - INTERVAL (
  SELECT retention_days FROM feature_flag_data_retention WHERE feature_name = 'user_data'
) DAY;
-- Enforces retention policies via flag.

---

-- 97. Subquery for Real-Time Alerting/Monitoring
-- Scenario: Find active alerts for features with alerting enabled.
SELECT * FROM alerts a
WHERE EXISTS (
  SELECT 1 FROM feature_flag_data_alerting fa WHERE fa.feature_name = a.feature_name AND fa.alerting_enabled = 1
);
-- Surfaces only alerts for enabled features.

---

-- 98. Subquery for Data Quota Enforcement
-- Scenario: Find users exceeding data quota using subqueries.
SELECT user_id FROM user_storage us
WHERE us.usage_gb > (
  SELECT quota_enabled FROM feature_flag_data_quota WHERE feature_name = 'user_storage'
);
-- Enforces quotas via feature flag.

---

-- 99. Subquery for Automated Backup/Restore Validation
-- Scenario: Find backups/restores performed when flag was enabled.
SELECT * FROM backups b
WHERE EXISTS (
  SELECT 1 FROM feature_flag_data_backup fb WHERE fb.feature_name = b.feature_name AND fb.backup_enabled = 1
);
-- Validates backup/restore compliance.

---

-- 100. Subquery for Advanced Data Lineage/Traceability
-- Scenario: Trace all downstream tables affected by a feature flag using subqueries.
SELECT DISTINCT target_table FROM feature_flag_lineage
WHERE feature_name = 'new_data_pipeline';
-- Enables advanced data lineage for compliance.

---

-- 101. Subquery for Recursive Permissions with Path Enumeration
-- Scenario: Check if a user has access to a resource, directly or through group hierarchy.
WITH RECURSIVE group_hierarchy AS (
  SELECT group_id, parent_id FROM groups WHERE group_id = 10
  UNION ALL
  SELECT g.group_id, g.parent_id FROM groups g
  JOIN group_hierarchy gh ON g.parent_id = gh.group_id
)
SELECT r.* FROM resources r
JOIN group_hierarchy gh ON r.group_id = gh.group_id;
-- Recursively fetches all groups a user belongs to, directly or indirectly.

---

-- 102. Subquery for Temporal Data Consistency
-- Scenario: Ensure all records in a time series have corresponding metadata entries.
SELECT e.* FROM events e
WHERE NOT EXISTS (
  SELECT 1 FROM event_metadata em WHERE em.event_id = e.id
);
-- Ensures no event is missing metadata.

---

-- 103. Subquery for Anomaly Detection in Time Series
-- Scenario: Detect sudden spikes in event counts.
SELECT e1.event_time, COUNT(*) AS event_count
FROM events e1
JOIN events e2 ON e1.event_id = e2.event_id AND e1.event_time <> e2.event_time
GROUP BY e1.event_time
HAVING COUNT(*) > (
  SELECT AVG(event_count) FROM (
    SELECT COUNT(*) AS event_count
    FROM events
    GROUP BY event_time
  ) daily_counts
);
-- Detects timestamps with abnormal event counts.

---

-- 104. Subquery for Hierarchical Data Aggregation
-- Scenario: Aggregate sales data up a category hierarchy.
WITH RECURSIVE category_path AS (
  SELECT id, parent_id, name FROM categories WHERE id = 1
  UNION ALL
  SELECT c.id, c.parent_id, c.name FROM categories c
  JOIN category_path cp ON c.parent_id = cp.id
)
SELECT cp.name, SUM(s.amount) AS total_sales
FROM category_path cp
JOIN sales s ON s.category_id = cp.id
GROUP BY cp.name;
-- Aggregates sales for a category and all its ancestor categories.

---

-- 105. Subquery for Conditional Data Masking
-- Scenario: Mask email addresses in user profiles based on a feature flag.
SELECT id, name,
  CASE WHEN (
    SELECT flag_value FROM feature_flags WHERE flag_name = 'mask_email'
  ) = 'Y' THEN '***MASKED***' ELSE email END AS email
FROM users;
-- Conditionally masks email data based on feature flag.

---

-- 106. Subquery for Vector Search with Distance Calculation
-- Scenario: Find items similar to a target item using vector distance.
SELECT id, embedding <#> '[0.1,0.2,0.3]' AS distance
FROM items
ORDER BY distance
LIMIT 10;
-- Retrieves top 10 items with the smallest distance to the target vector.

---

-- 107. Subquery for Edge Device Data Aggregation
-- Scenario: Aggregate data from IoT devices at the edge.
SELECT device_id, AVG(temperature) AS avg_temperature
FROM device_data
WHERE edge_node = (
  SELECT id FROM edge_nodes WHERE location = 'warehouse_1'
)
GROUP BY device_id;
-- Aggregates temperature data from devices connected to a specific edge node.

---

-- 108. Subquery for Streaming Data Quality Check
-- Scenario: Identify late-arriving data in a streaming pipeline.
SELECT *
FROM stream_data s
WHERE s.event_time < (
  SELECT MAX(event_time) - INTERVAL '5 minutes' FROM stream_data
);
-- Flags records that are older than the latest event by more than 5 minutes.

---

-- 109. Subquery for Canary Release Validation
-- Scenario: Compare metrics between canary and stable releases.
SELECT (
  SELECT AVG(response_time) FROM service_metrics WHERE version = 'canary'
) AS canary_response_time,
(
  SELECT AVG(response_time) FROM service_metrics WHERE version = 'stable'
) AS stable_response_time;
-- Compares average response times between canary and stable versions.

---

-- 110. Subquery for Automated Remediation Actions
-- Scenario: Find resources that need remediation based on policy violations.
SELECT r.*
FROM resources r
WHERE EXISTS (
  SELECT 1 FROM remediation_policies rp
  WHERE rp.resource_type = r.type AND rp.is_active = 1
);
-- Identifies resources that are out of compliance with active remediation policies.

---

-- 111. Subquery for Cross-Region Replication Lag
-- Scenario: Monitor replication lag between primary and replica databases.
SELECT *
FROM replication_status r
WHERE r.region = 'us-west'
AND r.lag_seconds > (
  SELECT MAX(lag_seconds) FROM replication_status WHERE region = 'us-east'
);
-- Detects if the replication lag in one region exceeds the maximum lag in another region.

---

-- 112. Subquery for Partitioned Table Maintenance
-- Scenario: Identify old partitions that can be archived or dropped.
SELECT *
FROM information_schema.partitions p
WHERE p.table_name = 'user_data'
AND p.partition_ordinal_position < (
  SELECT MIN(partition_ordinal_position) + 12 FROM information_schema.partitions
  WHERE table_name = 'user_data'
);
-- Finds partitions older than a certain threshold for maintenance.

---

-- 113. Subquery for LLM Model Performance Tracking
-- Scenario: Track performance metrics for different LLM model versions.
SELECT model_version, AVG(response_time) AS avg_response_time
FROM llm_usage
GROUP BY model_version
HAVING model_version = (
  SELECT model_version FROM llm_models WHERE name = 'gpt-5' AND active = 1
);
-- Monitors response time for the active version of a specific LLM model.

---

-- 114. Subquery for Data Mesh Access Control
-- Scenario: Ensure users can only query data in their assigned mesh domains.
SELECT *
FROM orders o
WHERE o.domain_id IN (
  SELECT domain_id FROM user_domains WHERE user_id = 123
);
-- Enforces data access policies in a data mesh architecture.

---

-- 115. Subquery for Cost Optimization Insights
-- Scenario: Identify high-cost queries for optimization.
SELECT query_id, total_cost
FROM query_costs
WHERE total_cost > (
  SELECT AVG(total_cost) FROM query_costs
);
-- Flags queries that are above average cost for review.

---

-- 116. Subquery for Retention Policy Enforcement
-- Scenario: Find data eligible for deletion based on retention policies.
SELECT *
FROM user_data ud
WHERE ud.created_at < NOW() - INTERVAL (
  SELECT retention_period FROM data_retention_policies WHERE policy_id = 'default'
) DAY;
-- Enforces data retention policies by identifying old data.

---

-- 117. Subquery for Real-Time Feature Flag Evaluation
-- Scenario: Dynamically evaluate feature flags in real-time queries.
SELECT u.id, u.name,
  CASE WHEN (
    SELECT flag_value FROM feature_flags WHERE flag_name = 'new_feature' AND user_id = u.id
  ) = 'Y' THEN 'Enabled' ELSE 'Disabled' END AS feature_status
FROM users u;
-- Real-time evaluation of feature flags for individual users.

---

-- 118. Subquery for Quota Management
-- Scenario: Find users who have exceeded their data quota.
SELECT user_id, used_space, quota_limit
FROM user_storage
WHERE used_space > (
  SELECT quota_limit FROM user_plans WHERE plan_id = 'premium'
);
-- Identifies users who have exceeded their allocated storage quota.

---

-- 119. Subquery for Backup Verification
-- Scenario: Ensure all critical tables have recent backups.
SELECT table_name
FROM information_schema.tables t
WHERE t.table_schema = 'public'
AND NOT EXISTS (
  SELECT 1 FROM backups b WHERE b.table_name = t.table_name AND b.backup_time > NOW() - INTERVAL '1 day'
);
-- Flags tables that have not been backed up recently.

---

-- 120. Subquery for Advanced Data Lineage/Traceability
-- Scenario: Trace all downstream tables affected by a feature flag using subqueries.
SELECT DISTINCT target_table FROM feature_flag_lineage
WHERE feature_name = 'new_data_pipeline';
-- Enables advanced data lineage for compliance.

---

-- 121. MongoDB Aggregation Pipeline Subquery (Polyglot)
-- Scenario: Find users with >3 orders using $lookup and $group.
db.users.aggregate([
  { $lookup: { from: 'orders', localField: '_id', foreignField: 'user_id', as: 'orders' } },
  { $addFields: { order_count: { $size: '$orders' } } },
  { $match: { order_count: { $gt: 3 } } }
]);
-- Polyglot: Subquery via aggregation pipeline and $lookup.

---

-- 122. MongoDB Graph Traversal with $graphLookup
-- Scenario: Find all descendants in an org chart.
db.employees.aggregate([
  { $match: { _id: ObjectId('...') } },
  { $graphLookup: {
      from: 'employees',
      startWith: '$_id',
      connectFromField: '_id',
      connectToField: 'manager_id',
      as: 'descendants'
    }
  }
]);
-- Polyglot: Recursive subquery using $graphLookup.

---

-- 123. Cassandra CQL Subquery Pattern (Polyglot)
-- Scenario: Find all orders for a user (partition key pattern).
SELECT * FROM orders WHERE user_id = ?;
-- CQL does not support subqueries; use denormalization and partitioning.

---

-- 124. DynamoDB Single-Table Design with Filter Expression
-- Scenario: Query all items for a user and filter by type.
aws dynamodb query --table-name app_table \
  --key-condition-expression "PK = :user" \
  --filter-expression "item_type = :order"
-- Polyglot: Subquery analog via filter expressions.

---

-- 125. Gremlin Graph Traversal Subquery (Polyglot)
-- Scenario: Find all friends-of-friends for a user.
g.V().has('user', 'id', 123).out('friend').out('friend').dedup();
-- Polyglot: Subquery via graph traversal.

---

-- 126. Cypher Graph Traversal Subquery (Polyglot)
-- Scenario: Find all direct and indirect reports for a manager.
MATCH (m:Employee {id: 1})-[:MANAGES*]->(e:Employee)
RETURN e;
-- Polyglot: Recursive subquery in Cypher.

---

-- 127. Spanner Interleaved Table Subquery (Cloud-Native)
-- Scenario: Query child rows in an interleaved table.
SELECT * FROM Orders@{FORCE_INDEX=Parent} WHERE CustomerId = 'C123';
-- Cloud-native: Spanner interleaved table query.

---

-- 128. BigQuery ARRAY/STRUCT Subquery (Cloud-Native)
-- Scenario: Unnest and filter nested arrays.
SELECT user_id, order
FROM users, UNNEST(orders) AS order
WHERE order.amount > 100;
-- Cloud-native: Subquery via UNNEST and ARRAY/STRUCT.

---

-- 129. Redshift/Snowflake Semi-Structured Data Subquery
-- Scenario: Query JSON fields in a semi-structured column.
SELECT data:orderId::STRING AS order_id
FROM events
WHERE data:amount::FLOAT > 100;
-- Cloud-native: Subquery on semi-structured data.

---

-- 130. Row-Level Security Subquery (Advanced Security)
-- Scenario: Enforce row-level security for tenant isolation.
CREATE POLICY tenant_isolation_policy ON orders
  USING (tenant_id = current_setting('app.tenant_id'));
-- Advanced security: Row-level security subquery.

---

-- 131. Dynamic Data Masking Subquery (Advanced Security)
-- Scenario: Mask sensitive columns for non-privileged users.
SELECT id, name,
  CASE WHEN current_user <> 'admin' THEN '***MASKED***' ELSE ssn END AS ssn
FROM users;
-- Advanced security: Dynamic masking via subquery.

---

-- 132. Column-Level Encryption Subquery (Advanced Security)
-- Scenario: Decrypt column only for authorized users.
SELECT id, name,
  CASE WHEN current_user = 'admin' THEN PGP_SYM_DECRYPT(ssn_enc, 'key') ELSE NULL END AS ssn
FROM users;
-- Advanced security: Column-level encryption/decryption.

---

-- 133. Audit Subquery for Sensitive Access (Advanced Security)
-- Scenario: Log all access to sensitive data via subquery.
INSERT INTO audit_log (user_id, action, accessed_at)
SELECT current_user, 'read_ssn', NOW()
FROM users WHERE id = 123;
-- Advanced security: Audit via subquery.

---

-- 134. Multi-Tenant Isolation Subquery
-- Scenario: Ensure queries only access data for the current tenant.
SELECT * FROM orders WHERE tenant_id = current_setting('app.tenant_id');
-- Multi-tenant: Tenant isolation enforced in subquery.

---

-- 135. Cross-Region Consistency Subquery
-- Scenario: Compare row counts between regions for consistency.
SELECT (
  SELECT COUNT(*) FROM orders_us
) AS us_count,
(
  SELECT COUNT(*) FROM orders_eu
) AS eu_count;
-- Multi-region: Validates cross-region consistency.

---

-- 136. Global Table Query (Multi-Region)
-- Scenario: Query global table for all regions.
SELECT * FROM global_orders WHERE region IN ('us', 'eu', 'apac');
-- Multi-region: Global table subquery.

---

-- 137. Failover Pattern Subquery (Multi-Region)
-- Scenario: Route queries to replica if primary is unavailable.
SELECT * FROM orders
WHERE region = COALESCE(
  (SELECT region FROM replicas WHERE status = 'active' LIMIT 1),
  'primary'
);
-- Multi-region: Failover via subquery.

---

-- 138. Hybrid OLTP/OLAP Real-Time Analytics Subquery
-- Scenario: Aggregate real-time and historical data in one query.
SELECT user_id, SUM(amount) AS total_amount
FROM (
  SELECT user_id, amount FROM realtime_orders
  UNION ALL
  SELECT user_id, amount FROM historical_orders
) all_orders
GROUP BY user_id;
-- Hybrid OLTP/OLAP: Federated analytics subquery.

---

-- 139. Data Mesh Productization Subquery
-- Scenario: Query data products with contract validation.
SELECT * FROM data_products dp
WHERE EXISTS (
  SELECT 1 FROM contracts c WHERE c.product_id = dp.id AND c.status = 'active'
);
-- Data mesh: Productization and contract validation.

---

-- 140. AI/ML Feature Store Point-in-Time Join Subquery
-- Scenario: Join features as of a specific timestamp.
SELECT f.user_id, f.feature_value
FROM features f
WHERE f.timestamp = (
  SELECT MAX(timestamp) FROM features WHERE user_id = f.user_id AND timestamp <= '2025-07-13'
);
-- AI/ML: Point-in-time join for feature store.

---

-- 141. Feature Lineage Subquery (AI/ML)
-- Scenario: Trace all upstream features for a model.
SELECT DISTINCT source_feature FROM feature_lineage
WHERE model_id = 'model_123';
-- AI/ML: Feature lineage tracking.

---

-- 142. Vector DB Similarity Search Subquery (AI/ML)
-- Scenario: Find top-N similar vectors using ANN index.
SELECT id FROM vectors
ORDER BY embedding <#> '[0.1,0.2,0.3]'
LIMIT 10;
-- AI/ML: Vector DB similarity search.

---

-- 143. Retry Logic Subquery (Advanced Error Handling)
-- Scenario: Retry failed jobs up to N times.
SELECT * FROM jobs
WHERE status = 'failed' AND retry_count < 3;
-- Error handling: Retry pattern via subquery.

---

-- 144. Transactional Guarantee Subquery (Advanced Error Handling)
-- Scenario: Ensure all steps in a transaction succeeded.
SELECT transaction_id
FROM transaction_steps
GROUP BY transaction_id
HAVING COUNT(*) = (
  SELECT COUNT(*) FROM transaction_templates WHERE template_id = transaction_steps.template_id
);
-- Error handling: Transactional completeness check.

---

-- 145. Compensation Pattern Subquery (Advanced Error Handling)
-- Scenario: Find failed operations needing compensation.
SELECT * FROM operations
WHERE status = 'failed' AND NOT EXISTS (
  SELECT 1 FROM compensations c WHERE c.operation_id = operations.id
);
-- Error handling: Compensation subquery.

---

-- 146. Query Plan Introspection Subquery (Performance/Observability)
-- Scenario: Analyze query plans for slow queries.
EXPLAIN ANALYZE SELECT * FROM orders WHERE amount > 1000;
-- Performance: Query plan introspection.

---

-- 147. Lock Contention Subquery (Performance/Observability)
-- Scenario: Find sessions waiting on locks.
SELECT blocked_pid, blocking_pid, wait_event_type
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.granted = false;
-- Performance: Lock contention analysis.

---

-- 148. Live Query Monitoring Subquery (Performance/Observability)
-- Scenario: Monitor currently running queries.
SELECT pid, query, state, start_time
FROM pg_stat_activity
WHERE state = 'active';
-- Performance: Live query monitoring.

---

-- 149. Edge Analytics Subquery (Edge/IoT/Streaming)
-- Scenario: Aggregate sensor data at the edge.
SELECT edge_id, AVG(temperature) AS avg_temp
FROM sensor_data
WHERE edge_id = 'edge-1'
GROUP BY edge_id;
-- Edge/IoT: Edge analytics subquery.

---

-- 150. Time-Windowed Join Subquery (Edge/IoT/Streaming)
-- Scenario: Join events within a 5-minute window.
SELECT a.*, b.*
FROM events a
JOIN events b ON a.device_id = b.device_id
AND ABS(TIMESTAMPDIFF(MINUTE, a.event_time, b.event_time)) <= 5;
-- Edge/IoT: Time-windowed join subquery.

---

-- 151. Watermarking Subquery (Edge/IoT/Streaming)
-- Scenario: Find events lagging behind the current watermark.
SELECT * FROM stream_events se
WHERE se.event_time < (
  SELECT MAX(watermark) FROM stream_watermarks WHERE stream_id = se.stream_id
);
-- Edge/IoT: Watermarking for streaming data.

---
