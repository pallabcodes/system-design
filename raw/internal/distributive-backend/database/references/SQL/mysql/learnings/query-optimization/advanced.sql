-- Query Optimization & Analysis
-- EXPLAIN Usage
EXPLAIN SELECT * FROM orders WHERE user_id = 123;
-- Slow Query Log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1; -- 1 second
SHOW VARIABLES LIKE 'slow_query_log%';
-- Profiling
SET PROFILING = 1;
SELECT * FROM orders WHERE user_id = 123;
SHOW PROFILES;
-- ...add more scenarios as needed...
