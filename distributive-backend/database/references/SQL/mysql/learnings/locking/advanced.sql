-- Locking, Concurrency, Deadlocks
-- Detecting Locks
SHOW ENGINE INNODB STATUS;
SELECT * FROM information_schema.innodb_locks;
-- Deadlock Example
-- Simulate deadlock with two sessions updating rows in reverse order
-- Resolving Deadlocks
SHOW ENGINE INNODB STATUS; -- Deadlock info
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Simulate Deadlock (Two Sessions)
-- Session 1:
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
-- Session 2:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- Session 1:
UPDATE accounts SET balance = balance - 100 WHERE id = 2;
-- Session 2:
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
-- One session will hit a deadlock and roll back.

-- Detecting Lock Waits
SELECT * FROM performance_schema.data_locks;
SELECT * FROM performance_schema.data_lock_waits;

-- Best Practices
-- 1. Keep transactions short and commit quickly.
-- 2. Always access rows in the same order in all transactions.
-- 3. Use proper isolation levels for your workload.
-- 4. Monitor SHOW ENGINE INNODB STATUS for deadlocks and lock waits.

-- Advanced Troubleshooting
-- Analyze Deadlock Section in SHOW ENGINE INNODB STATUS
-- Example output:
--
-- LATEST DETECTED DEADLOCK
-- ------------------------
-- 2025-07-19 10:00:00
-- *** (1) TRANSACTION:
-- ...
-- *** (2) TRANSACTION:
-- ...
-- Deadlock found when trying to get lock; try restarting transaction

-- Edge Case: Gap Locks (InnoDB, REPEATABLE READ)
-- Prevents phantom reads, can block inserts in a range
START TRANSACTION;
SELECT * FROM orders WHERE amount BETWEEN 100 AND 200 FOR UPDATE;
-- In another session, try:
INSERT INTO orders (amount) VALUES (150); -- Will be blocked by gap lock
COMMIT;

-- Edge Case: Phantom Reads
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT COUNT(*) FROM orders WHERE status = 'pending';
-- In another session, insert a new 'pending' order
-- Original session may not see the new row until commit
COMMIT;

-- Edge Case: Metadata Locks
-- DDL (ALTER, DROP) will wait for active transactions on the table
START TRANSACTION;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- In another session:
ALTER TABLE accounts ADD COLUMN last_login DATETIME; -- Will wait for transaction to finish
COMMIT;

-- Lock Contention in High-Throughput Systems
-- Monitor lock waits and contention
SELECT * FROM performance_schema.data_lock_waits ORDER BY TIME_WAITED DESC LIMIT 10;

-- Advanced: Monitor innodb_status for lock heap, row lock waits
SHOW ENGINE INNODB STATUS;

-- Edge Case: Intentionally Large Transaction
START TRANSACTION;
UPDATE orders SET status = 'archived' WHERE created_at < '2022-01-01'; -- May cause lock contention
COMMIT;

-- Real-World Deadlock Analysis
-- 1. Identify conflicting queries from SHOW ENGINE INNODB STATUS
-- 2. Check application logic for out-of-order row access
-- 3. Use retry logic in application for deadlock errors (SQLSTATE 40001)
-- 4. Log and alert on frequent deadlocks

-- Example: Retry Logic (pseudo-code)
-- try {
--   execute transaction
-- } catch (SQLSTATE 40001) {
--   retry transaction
-- }

-- Application-Level Strategies
-- Idempotency: Ensure repeated transactions do not cause unintended effects
-- Example: Use unique keys, idempotency tokens, or UPSERT (INSERT ... ON DUPLICATE KEY UPDATE)
INSERT INTO payments (id, user_id, amount) VALUES (123, 1, 100)
ON DUPLICATE KEY UPDATE amount = VALUES(amount);

-- Distributed Locking: Use external systems for cross-service locks (e.g., Redis, ZooKeeper)
-- Example: Acquire lock in Redis before starting transaction
-- SETNX lock:order:123 1
-- If acquired, proceed; else, retry or fail gracefully

-- Monitoring & Alerting Integration
-- Log lock waits, deadlocks, and transaction retries to monitoring system (Prometheus, Grafana, ELK)
-- Example: Application logs
-- [WARN] Deadlock detected, retrying transaction (order_id=123)
-- [INFO] Lock wait exceeded threshold (user_id=1)

-- Best Practices for Backend Engineers
-- 1. Use exponential backoff for retries to avoid thundering herd
-- 2. Prefer optimistic concurrency for high-contention workloads
-- 3. Integrate lock/transaction metrics into dashboards
-- 4. Alert on spikes in deadlocks or lock waits

-- Real-World Distributed Locking (Redis Example)
-- Lua script for atomic lock with expiry
-- EVAL "if redis.call('setnx', KEYS[1], ARGV[1]) == 1 then return redis.call('expire', KEYS[1], ARGV[2]) else return 0 end" 1 lock:order:123 1 30
-- Release lock: DEL lock:order:123

-- ZooKeeper Distributed Lock (Java/Python)
-- Create ephemeral znode for lock, delete on release or disconnect
-- /locks/order_123

-- Advanced Idempotency Pattern
-- Use UUID or idempotency key in API requests, store processed keys in DB
-- Example table:
-- CREATE TABLE idempotency_keys (key VARCHAR(64) PRIMARY KEY, processed_at DATETIME);
-- On request, check if key exists before processing

-- Monitoring Integration (Prometheus/Grafana)
-- Export metrics: deadlocks_total, lock_waits_total, transaction_retries_total
-- Example Prometheus metric:
-- deadlocks_total{db="main", table="orders"} 5

-- Alerting Example (Prometheus Alertmanager)
-- Alert if deadlocks_total > threshold for 5m
-- expr: deadlocks_total > 10
-- for: 5m
-- labels: {severity="critical"}
-- annotations: {summary="High deadlock rate detected"}

-- Advanced Database Session Management & Transactions
-- Session Variables: Impact on Transaction Behavior
SET SESSION autocommit = 0; -- Manual transaction control
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION wait_timeout = 600; -- Session timeout in seconds

-- View Session Variables
SHOW SESSION VARIABLES LIKE 'autocommit';
SHOW SESSION VARIABLES LIKE 'transaction_isolation';
SHOW SESSION STATUS WHERE Variable_name LIKE 'Threads%';

-- Connection Pooling & Session Isolation
-- Use connection pools (e.g., ProxySQL, HikariCP) to manage sessions efficiently
-- Each session/connection has its own transaction context and variables

-- Transaction Boundaries & Session State
START TRANSACTION;
-- Session state (variables, temp tables) persists until COMMIT/ROLLBACK or disconnect
COMMIT;

-- Session-Level Locks
-- Explicitly lock tables for session
LOCK TABLES accounts WRITE;
-- ... perform operations ...
UNLOCK TABLES;

-- Troubleshooting Session Issues
-- Find active sessions and their transactions
SELECT * FROM information_schema.processlist WHERE COMMAND = 'Query';
SELECT * FROM information_schema.innodb_trx;

-- Session Timeout & Cleanup
-- Long idle sessions can hold locks and block others
-- Use wait_timeout, interactive_timeout, and connection pool settings to manage

-- Best Practices
-- 1. Always set session variables explicitly for critical workloads
-- 2. Monitor session status and active transactions
-- 3. Use connection pooling for scalability
-- 4. Clean up idle sessions to avoid lock contention

-- Advanced Session Transaction Patterns
-- Savepoints: Fine-grained rollback within a session
START TRANSACTION;
SAVEPOINT before_update;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK TO SAVEPOINT before_update;
COMMIT;

-- Multi-Session Coordination
-- Example: Coordinating distributed transactions across sessions
-- Use external transaction manager or two-phase commit (XA)
XA START 'xid';
-- ... perform operations in multiple sessions ...
XA END 'xid';
XA PREPARE 'xid';
XA COMMIT 'xid';

-- Session-Level Temporary Tables
CREATE TEMPORARY TABLE session_temp (id INT, value VARCHAR(100));
INSERT INTO session_temp VALUES (1, 'foo');
SELECT * FROM session_temp;
-- Temp tables are visible only to the session and dropped on disconnect

-- Session Security & Auditing
-- Set session user, track session activity
SELECT CURRENT_USER();
SHOW PROCESSLIST;
-- Audit session changes and access for compliance

-- Google-Scale Best Practices
-- 1. Use savepoints for complex transaction logic
-- 2. Prefer stateless session design for horizontal scaling
-- 3. Use XA or SAGA for distributed transactions
-- 4. Audit and monitor session activity for security and compliance
