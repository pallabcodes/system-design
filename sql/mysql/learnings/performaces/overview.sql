-- Prefixing with `explain` allows us to see the execution plan of a query e.g. EXPLAIN SELECT * FROM users; OR EXPLAIN format=json SELECT * FROM users WHERE id = 1;

-- SHOW TABLES; SHOW COLUMNS FROM users; SHOW CREATE TABLE users; EXPLAIN SELECT * FROM users WHERE name='John' \G;

-- Prefixing with analyze after explain provides additional details on the execution plan e.g. EXPLAIN ANALYZE SELECT * FROM users;