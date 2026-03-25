-- 27. Trigger + Real-Time Quota Enforcement (SaaS: Enforce API Rate Limits)
-- Scenario: On API call log insert, block if user exceeds allowed quota in the last hour.

DELIMITER $$
CREATE TRIGGER enforce_api_quota
BEFORE INSERT ON api_call_logs
FOR EACH ROW
BEGIN
    DECLARE call_count INT;
    SELECT COUNT(*) INTO call_count FROM api_call_logs
    WHERE user_id = NEW.user_id AND call_time > NOW() - INTERVAL 1 HOUR;
    IF call_count >= (SELECT quota_per_hour FROM users WHERE id = NEW.user_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'API quota exceeded';
    END IF;
END$$
DELIMITER ;

-- 65. Trigger + Event + JSON (SaaS: Auto-Log and Escalate Failed Logins)
-- Scenario: On failed login insert, log as JSON. Nightly event escalates users with >5 failures in 24h to security team.

DELIMITER $$
CREATE TRIGGER log_failed_login_json
AFTER INSERT ON login_failures
FOR EACH ROW
BEGIN
    INSERT INTO login_failure_log (failure_json, created_at)
    VALUES (JSON_OBJECT('user_id', NEW.user_id, 'ip', NEW.ip_address, 'reason', NEW.reason, 'failure', NEW), NOW());
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT escalate_failed_logins
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    INSERT INTO security_escalations (user_id, escalation_type, escalated_at)
    SELECT user_id, 'excessive_login_failures', NOW()
    FROM login_failures
    WHERE failure_time > NOW() - INTERVAL 1 DAY
    GROUP BY user_id
    HAVING COUNT(*) > 5;
END$$
DELIMITER ;

-- Why it's advanced:
-- Combines triggers, events, and JSON for automated security escalation and audit.

-- 66. Trigger + Partitioned Table + Error Handling (E-commerce: Block and Log Oversized Cart Updates)
-- Scenario: On cart update, block if cart exceeds 100 items, log attempt in partitioned table.

DELIMITER $$
CREATE TRIGGER block_oversized_cart_update
BEFORE UPDATE ON carts
FOR EACH ROW
BEGIN
    IF NEW.item_count > 100 THEN
        INSERT INTO cart_oversize_log_partitioned (cart_id, user_id, item_count, attempted_at)
        VALUES (NEW.id, NEW.user_id, NEW.item_count, NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cart size exceeds allowed limit';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Real-time enforcement and partitioned logging for cart size limits.

-- 67. Event + Recursive CTE + Analytics (Transport: Auto-Close Inactive Driver Accounts and Sub-Accounts)
-- Scenario: Every month, recursively close driver accounts and sub-accounts inactive for 1 year.

DELIMITER $$
CREATE EVENT close_inactive_driver_accounts
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    WITH RECURSIVE inactive_drivers AS (
        SELECT id FROM drivers WHERE last_active < NOW() - INTERVAL 1 YEAR
        UNION ALL
        SELECT d.id FROM drivers d
        INNER JOIN inactive_drivers i ON d.parent_driver_id = i.id
    )
    UPDATE drivers SET status = 'CLOSED' WHERE id IN (SELECT id FROM inactive_drivers);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively closes inactive drivers and sub-accounts, keeping the fleet clean.

-- 68. Trigger + JSON + Error Handling (Finance: Block and Log Suspicious Account Creations)
-- Scenario: On account creation, block and log as JSON if email domain is blacklisted or IP is flagged.

DELIMITER $$
CREATE TRIGGER block_suspicious_account_creation
BEFORE INSERT ON accounts
FOR EACH ROW
BEGIN
    IF NEW.email LIKE '%@tempmail.com' OR NEW.ip_address IN (SELECT ip FROM flagged_ips) THEN
        INSERT INTO account_creation_fraud_log (account_json, detected_at)
        VALUES (JSON_OBJECT('email', NEW.email, 'ip', NEW.ip_address, 'account', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Suspicious account creation blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Prevents fraudulent signups and logs full context for audit and ML.

-- 69. Event + Dynamic SQL + Partitioning (E-commerce: Auto-Archive Abandoned Wishlists by Partition)
-- Scenario: Every quarter, archive wishlists not updated in 2 years, using dynamic SQL for partitioned tables.

DELIMITER $$
CREATE EVENT archive_abandoned_wishlists
ON SCHEDULE EVERY 3 MONTH
DO
BEGIN
    -- Example: Move to archive partition (pseudo-code, requires dynamic SQL)
    -- SET @sql = 'INSERT INTO wishlists_archive PARTITION (p' + DATE_FORMAT(NOW(), '%Y%m') + ') SELECT * FROM wishlists WHERE last_updated < NOW() - INTERVAL 2 YEAR';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- DELETE FROM wishlists WHERE last_updated < NOW() - INTERVAL 2 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Automates partitioned archiving of abandoned wishlists for compliance and cost savings.

-- 60. Trigger + Event + Partitioning (E-commerce: Auto-Expire Flash Sale Inventory and Notify Merchants)
-- Scenario: On flash sale order insert, decrement inventory. Nightly event expires unsold inventory and notifies merchants, partitioned by product.

DELIMITER $$
CREATE TRIGGER decrement_flash_sale_inventory
AFTER INSERT ON flash_sale_orders
FOR EACH ROW
BEGIN
    UPDATE flash_sale_inventory SET stock = stock - NEW.quantity WHERE product_id = NEW.product_id;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT expire_unsold_flash_inventory
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE flash_sale_inventory SET status = 'EXPIRED'
    WHERE stock > 0 AND sale_end < NOW();
    INSERT INTO merchant_notifications (merchant_id, message, created_at)
    SELECT merchant_id, CONCAT('Flash sale inventory expired for product ', product_id), NOW()
    FROM flash_sale_inventory WHERE status = 'EXPIRED' AND notified = 0;
    UPDATE flash_sale_inventory SET notified = 1 WHERE status = 'EXPIRED' AND notified = 0;
END$$
DELIMITER ;

-- Why it's advanced:
-- Automates inventory lifecycle and merchant notification with partitioning and events.

-- 61. Trigger + JSON + Error Handling (Transport: Block and Log Duplicate Ride Requests)
-- Scenario: On ride request insert, block if a similar request exists (same user, pickup, dropoff, and time window), and log as JSON.

DELIMITER $$
CREATE TRIGGER block_duplicate_ride_request
BEFORE INSERT ON ride_requests
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM ride_requests
        WHERE user_id = NEW.user_id AND pickup_location = NEW.pickup_location
        AND dropoff_location = NEW.dropoff_location
        AND request_time > NOW() - INTERVAL 10 MINUTE
    ) THEN
        INSERT INTO ride_request_duplicate_log (request_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'pickup', NEW.pickup_location, 'dropoff', NEW.dropoff_location, 'request', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate ride request blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Prevents duplicate ride requests and logs full context for audit and ML.

-- 62. Event + Recursive CTE + Partitioning (SaaS: Auto-Delete Orphaned Projects and Sub-Projects)
-- Scenario: Every month, recursively delete projects with no active users, including all sub-projects, partitioned by organization.

DELIMITER $$
CREATE EVENT cleanup_orphaned_projects
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    WITH RECURSIVE orphaned_projects AS (
        SELECT id FROM projects WHERE active_user_count = 0
        UNION ALL
        SELECT p.id FROM projects p
        INNER JOIN orphaned_projects o ON p.parent_project_id = o.id
    )
    DELETE FROM projects WHERE id IN (SELECT id FROM orphaned_projects);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively deletes orphaned projects and sub-projects, keeping the system lean and partitioned by org.

-- 63. Trigger + Window Function + Analytics (Finance: Auto-Flag High-Frequency Trading Accounts)
-- Scenario: On trade insert, flag account if trade count exceeds threshold in rolling 1-hour window, for compliance analytics.

DELIMITER $$
CREATE TRIGGER flag_high_frequency_trader
AFTER INSERT ON trades
FOR EACH ROW
BEGIN
    DECLARE trade_count INT;
    SELECT COUNT(*) INTO trade_count FROM trades
    WHERE account_id = NEW.account_id AND trade_time > NOW() - INTERVAL 1 HOUR;
    IF trade_count > 100 THEN
        UPDATE accounts SET flagged_hft = 1 WHERE id = NEW.account_id;
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Uses windowing to flag high-frequency trading for compliance and analytics.

-- 64. Event + Dynamic SQL + Analytics (E-commerce: Auto-Generate Sales Leaderboards by Category)
-- Scenario: Weekly event generates sales leaderboards for each category using dynamic SQL and stores results for BI.

DELIMITER $$
CREATE EVENT generate_category_leaderboards
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    -- Example: Dynamic SQL for each category (pseudo-code)
    -- DECLARE done INT DEFAULT FALSE;
    -- DECLARE cat_id INT;
    -- DECLARE cur CURSOR FOR SELECT id FROM categories;
    -- DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    -- OPEN cur;
    -- read_loop: LOOP
    --     FETCH cur INTO cat_id;
    --     IF done THEN LEAVE read_loop; END IF;
    --     SET @sql = CONCAT('REPLACE INTO category_leaderboard (category_id, product_id, sales) SELECT ', cat_id, ', product_id, SUM(quantity) FROM orders WHERE category_id = ', cat_id, ' GROUP BY product_id ORDER BY SUM(quantity) DESC LIMIT 10');
    --     PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- END LOOP;
    -- CLOSE cur;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates leaderboard generation for BI using dynamic SQL and analytics.

-- Why it's advanced:
-- Enforces per-user API quotas in real-time, directly in the DB.

-- 28. Trigger + Cascading Soft Deletes (E-commerce: Soft Delete Orders and Related Data)
-- Scenario: On order soft delete, mark all related order_items and shipments as deleted, but keep data for audit.

DELIMITER $$
CREATE TRIGGER cascade_soft_delete_order
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF NEW.deleted = 1 AND OLD.deleted = 0 THEN
        UPDATE order_items SET deleted = 1 WHERE order_id = NEW.id;
        UPDATE shipments SET deleted = 1 WHERE order_id = NEW.id;
    END IF;
END$$
DELIMITER ;



-- 41. Trigger + Event + Window Function (Marketplace: Auto-Blacklist Abusive Users)
-- Scenario: On user action insert, if user exceeds abuse threshold (windowed over 24h), auto-blacklist and log. Nightly event clears expired blacklists.

DELIMITER $$
CREATE TRIGGER auto_blacklist_abusive_user
AFTER INSERT ON user_actions
FOR EACH ROW
BEGIN
    DECLARE abuse_count INT;
    SELECT COUNT(*) INTO abuse_count FROM user_actions
    WHERE user_id = NEW.user_id AND action_type = 'ABUSE' AND action_time > NOW() - INTERVAL 1 DAY;
    IF abuse_count > 10 THEN
        INSERT IGNORE INTO user_blacklist (user_id, blacklisted_at, reason)
        VALUES (NEW.user_id, NOW(), 'Abuse threshold exceeded');
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT clear_expired_blacklists
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    DELETE FROM user_blacklist WHERE blacklisted_at < NOW() - INTERVAL 30 DAY;
END$$
DELIMITER ;

-- Why it's advanced:
-- Combines triggers, windowing, and events for automated, rolling abuse management.

-- 42. Trigger + JSON + Partitioning (Finance: Real-Time Transaction Tagging for AML)
-- Scenario: On transaction insert, tag suspicious transactions with JSON metadata and partition for AML review.

DELIMITER $$
CREATE TRIGGER tag_aml_suspicious_txn
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount > 20000 OR NEW.country IN ('IR', 'KP', 'SY') THEN
        UPDATE transactions SET aml_tag = JSON_OBJECT('flag', 'suspicious', 'reason', 'AML rule', 'ts', NOW())
        WHERE id = NEW.id;
        INSERT INTO aml_review_partition (txn_id, flagged_at)
        VALUES (NEW.id, NOW());
    END IF;
END$$
DELIMITER ;


-- 43. Event + Recursive CTE + Dynamic SQL (E-commerce: Auto-Delete Expired Promo Codes and Children)
-- 46. Trigger + Event + CTE (E-commerce: Auto-Expire Unused Coupons and Notify Users)
-- Scenario: On coupon usage, mark as used. Nightly event finds and expires unused coupons older than 30 days, and notifies users.

DELIMITER $$
CREATE TRIGGER mark_coupon_used
AFTER UPDATE ON coupons
FOR EACH ROW
BEGIN
    IF NEW.used = 1 AND OLD.used = 0 THEN
        UPDATE coupons SET used_at = NOW() WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT expire_unused_coupons
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH expired AS (
        SELECT id, user_id FROM coupons WHERE used = 0 AND created_at < NOW() - INTERVAL 30 DAY
    )
    UPDATE coupons SET status = 'EXPIRED' WHERE id IN (SELECT id FROM expired);
    INSERT INTO notifications (user_id, message, created_at)
    SELECT user_id, 'Your coupon has expired', NOW() FROM expired;
END$$
DELIMITER ;

-- Why it's advanced:
-- Automates coupon lifecycle and user notification with CTEs and events.

-- 47. Trigger + JSON + Error Handling (Finance: Block and Log Suspicious Withdrawals)
-- Scenario: On withdrawal insert, block and log as JSON if amount exceeds daily limit or from flagged country.

DELIMITER $$
CREATE TRIGGER block_and_log_suspicious_withdrawal
BEFORE INSERT ON withdrawals
FOR EACH ROW
BEGIN
    DECLARE total_today DECIMAL(10,2);
    SELECT SUM(amount) INTO total_today FROM withdrawals WHERE user_id = NEW.user_id AND withdrawal_time > CURDATE();
    IF NEW.amount > 5000 OR total_today + NEW.amount > 10000 OR NEW.country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO withdrawal_fraud_log (withdrawal_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.country, 'withdrawal', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Suspicious withdrawal blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Real-time fraud prevention and forensic logging using JSON and error signaling.

-- 48. Event + Partitioning + Analytics (Transport: Auto-Archive Old Trip Data by Region)
-- Scenario: Every month, archive trips older than 1 year by region partition for analytics and cost savings.

DELIMITER $$
DO
    DELETE FROM trips WHERE trip_date < NOW() - INTERVAL 1 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Region-partitioned archiving for scalable analytics and storage efficiency.

-- 49. Trigger + Recursive CTE (SaaS: Auto-Disable Orphaned Subscriptions)
-- Scenario: On user delete, recursively disable all dependent subscriptions and child accounts.

DELIMITER $$
CREATE TRIGGER disable_orphaned_subscriptions
AFTER DELETE ON users
    WITH RECURSIVE orphans AS (
        SELECT id FROM subscriptions WHERE user_id = OLD.id
        UNION ALL
        SELECT s.id FROM subscriptions s
        INNER JOIN orphans o ON s.parent_subscription_id = o.id
    )
    UPDATE subscriptions SET status = 'DISABLED' WHERE id IN (SELECT id FROM orphans);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively disables orphaned subscriptions, ensuring data integrity in multi-level SaaS hierarchies.

-- 50. Event + Dynamic SQL + CTE (E-commerce: Auto-Optimize Product Indexes Based on Query Stats)
-- Scenario: Weekly event analyzes query stats, adds/drops indexes dynamically for hot/cold product columns.

DELIMITER $$
CREATE EVENT optimize_product_indexes
BEGIN
    -- Example: Add index if query count high (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE products ADD INDEX idx_hot (hot_column)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if query count low (pseudo-code)
    -- SET @sql = 'ALTER TABLE products DROP INDEX idx_cold';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates index optimization using query stats, CTEs, and dynamic SQL for peak performance.
-- Scenario: Every week, recursively delete expired promo codes and all their dependent child codes using dynamic SQL.

DELIMITER $$
CREATE EVENT cleanup_expired_promo_codes
BEGIN
    WITH RECURSIVE expired_codes AS (
        SELECT id FROM promo_codes WHERE expires_at < NOW()
        UNION ALL
        SELECT c.id FROM promo_codes c
        INNER JOIN expired_codes e ON c.parent_code_id = e.id
    )
    DELETE FROM promo_codes WHERE id IN (SELECT id FROM expired_codes);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively and automatically cleans up expired and dependent promo codes, keeping the system lean.

-- 44. Trigger + Error Handling + Notification (Transport: Alert on Failed Payment Insert)
-- Scenario: On failed payment insert (e.g., constraint violation), log the error and notify admins instantly.
DELIMITER $$
CREATE TRIGGER log_failed_payment
BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    IF NEW.amount <= 0 THEN
        INSERT INTO payment_errors (user_id, amount, error_msg, created_at)
        VALUES (NEW.user_id, NEW.amount, 'Invalid payment amount', NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid payment amount';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Provides instant error logging and admin notification for payment issues, improving reliability.

-- 45. Event + Cross-Database + Analytics (SaaS: Sync Usage Stats to Analytics DB with Partition Awareness)
-- Scenario: Every hour, sync usage stats to analytics DB, partitioned by month, for BI/reporting.

DELIMITER $$
CREATE EVENT sync_usage_stats_to_analytics
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO analytics_db.usage_stats_partitioned (user_id, usage_count, stat_month, synced_at)
    SELECT user_id, COUNT(*), DATE_FORMAT(NOW(), '%Y-%m'), NOW()
    GROUP BY user_id;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables cross-DB, partition-aware analytics sync for scalable BI/reporting.

DELIMITER $$
CREATE EVENT invalidate_stale_driver_cache
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    DELETE FROM driver_location_cache
    WHERE driver_id IN (
        SELECT id FROM drivers WHERE last_location_update < NOW() - INTERVAL 30 MINUTE
    );
END$$
DELIMITER ;



-- 30. Trigger + Real-Time SLA Enforcement (Transport: Flag Late Rides)
-- Scenario: On ride update, if actual dropoff is later than promised, flag for SLA breach.

DELIMITER $$
CREATE TRIGGER flag_sla_breach
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    IF NEW.dropoff_time > NEW.promised_dropoff_time AND OLD.dropoff_time <= OLD.promised_dropoff_time THEN
        UPDATE rides SET sla_breached = 1 WHERE id = NEW.id;
        INSERT INTO sla_breach_log (ride_id, breached_at)
        VALUES (NEW.id, NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enforces SLAs in real-time, enabling proactive customer support and analytics.

-- 31. Event + Data Masking (Finance: Mask Sensitive Data for Analytics)
-- Scenario: Every night, mask PII in analytics tables while keeping raw data in production.

DELIMITER $$
CREATE EVENT mask_analytics_pii
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE analytics.transactions
    SET card_number = CONCAT('XXXX-XXXX-XXXX-', RIGHT(card_number, 4)),
        user_email = CONCAT(LEFT(user_email, 2), '***@***.com');
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures analytics teams never see raw PII, reducing compliance risk.

-- 32. Event + Dynamic Index Management (E-commerce: Auto-Add/Drop Indexes Based on Usage)
-- Scenario: Every week, analyze slow queries and auto-add/drop indexes for hot/cold columns.

DELIMITER $$
CREATE EVENT dynamic_index_management
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    -- Example: Add index if slow queries detected (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE orders ADD INDEX idx_status (status)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if unused (pseudo-code)
    -- SET @sql = 'ALTER TABLE orders DROP INDEX idx_old_unused';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's advanced:

-- 33. Event + Archiving (E-commerce: Move Old Orders to Archive Table)
-- Scenario: Every month, move orders older than 2 years to an archive table for cost savings and performance.

DELIMITER $$
CREATE EVENT archive_old_orders
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    INSERT INTO orders_archive SELECT * FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
    DELETE FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Keeps operational tables lean and fast, while preserving history for compliance.

-- 34. Trigger + Real-Time Escalation (Transport: Escalate Unassigned Rides)
-- Scenario: On ride insert, if not assigned to a driver within 2 minutes, auto-escalate to human dispatcher.

DELIMITER $$
CREATE TRIGGER escalate_unassigned_ride
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    IF NEW.driver_id IS NULL THEN
        INSERT INTO ride_escalations (ride_id, escalated_at)
        VALUES (NEW.id, NOW() + INTERVAL 2 MINUTE);
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures no ride is left unassigned, improving customer experience and reducing cancellations.

-- 35. Event + Adaptive Sharding (Finance: Rebalance Accounts Across Shards)
-- Scenario: Every week, move accounts with high activity to dedicated shards for load balancing.

DELIMITER $$
CREATE EVENT rebalance_account_shards
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    INSERT INTO accounts_hot_shard SELECT * FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
    DELETE FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
END$$
DELIMITER ;

-- Why it's advanced:
-- Dynamically rebalances hot accounts for optimal performance at scale.
DELIMITER $$
CREATE EVENT detect_transaction_spikes
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO anomaly_alerts (account_id, alert_type, detected_at)
    SELECT t.account_id, 'spike', NOW()
    FROM (
        SELECT account_id,
               COUNT(*) AS txn_count,
               (SELECT AVG(cnt) FROM (
                   SELECT COUNT(*) AS cnt FROM transactions
                   WHERE account_id = transactions.account_id
                   AND txn_time > NOW() - INTERVAL 7 DAY
                   GROUP BY DATE(txn_time)
               ) x) AS avg_daily
        FROM transactions
        WHERE txn_time > NOW() - INTERVAL 1 DAY
        GROUP BY account_id
    ) t
    WHERE t.txn_count > 5 * t.avg_daily;
END$$
DELIMITER ;


-- 36. Trigger + Event + Recursive CTE (SaaS: Automated Subscription Expiry and Grace Period Handling)
-- Scenario: On subscription expiry, auto-move user to grace period, and nightly event purges expired grace users recursively (including dependents).

DELIMITER $$
CREATE TRIGGER move_to_grace_period
AFTER UPDATE ON subscriptions
FOR EACH ROW
BEGIN
    IF NEW.status = 'EXPIRED' AND OLD.status != 'EXPIRED' THEN
        UPDATE users SET status = 'GRACE' WHERE id = NEW.user_id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT purge_expired_grace_users
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE expired_users AS (
        SELECT id FROM users WHERE status = 'GRACE' AND updated_at < NOW() - INTERVAL 14 DAY
        UNION ALL
        SELECT u.id FROM users u
        INNER JOIN expired_users e ON u.parent_id = e.id
    )
    DELETE FROM users WHERE id IN (SELECT id FROM expired_users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Combines triggers, events, and recursive CTEs for automated, multi-level subscription lifecycle management.

-- 37. Trigger + JSON + Error Handling (E-commerce: Real-Time Fraud Pattern Logging)
-- Scenario: On suspicious order insert, log full order as JSON in a fraud log table and block the insert.

DELIMITER $$
CREATE TRIGGER log_and_block_fraud_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.amount > 10000 OR NEW.shipping_country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO fraud_orders_log (order_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.shipping_country, 'order', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fraudulent order blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Instantly blocks and logs suspicious orders with full context for forensics, using JSON and custom error signaling.

-- 38. Event + Cross-Table Consistency (Transport: Auto-Heal Broken Foreign Keys)
-- Scenario: Every hour, scan for rides referencing missing drivers or users, and auto-fix or log for manual review.

DELIMITER $$
CREATE EVENT heal_broken_ride_fks
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    -- Log rides with missing drivers
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_driver', NOW() FROM rides WHERE driver_id NOT IN (SELECT id FROM drivers);
    -- Log rides with missing users
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_user', NOW() FROM rides WHERE user_id NOT IN (SELECT id FROM users);
    -- Optionally, set driver_id/user_id to NULL or a default value for orphaned rides
    UPDATE rides SET driver_id = NULL WHERE driver_id NOT IN (SELECT id FROM drivers);
    UPDATE rides SET user_id = NULL WHERE user_id NOT IN (SELECT id FROM users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Proactively detects and heals referential integrity issues, reducing data corruption risk at scale.

-- 39. Trigger + Partitioned Table + Dynamic SQL (Finance: Auto-Move Large Transactions to Audit Partition)
-- Scenario: On large transaction insert, move it to a special audit partition using dynamic SQL.

DELIMITER $$
CREATE TRIGGER move_large_txn_to_audit
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount > 50000 THEN
        SET @sql = CONCAT('INSERT INTO transactions_audit PARTITION (p', DATE_FORMAT(NOW(), '%Y%m'), ') SELECT * FROM transactions WHERE id = ', NEW.id, ';');
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        DELETE FROM transactions WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Uses dynamic SQL in a trigger to move sensitive data to a secure, partitioned audit table in real-time.

-- 40. Event + Predictive Analytics (E-commerce: Auto-Flag Products for Restock Based on ML Score)
-- Scenario: Every night, flag products for restock if ML-predicted demand score is high, using a precomputed ML table.

DELIMITER $$
CREATE EVENT flag_products_for_restock
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE products p
    JOIN product_demand_ml ml ON p.id = ml.product_id
    SET p.restock_flag = 1
    WHERE ml.predicted_demand > 0.8 AND p.stock < 20;
END$$
DELIMITER ;

-- Why it's advanced:
-- Integrates ML predictions into operational DB logic for proactive inventory management.

-- 22. Trigger + Multi-Tenant Data Isolation (SaaS: Enforce Tenant Boundaries)
-- Scenario: On insert/update, block cross-tenant data access by checking tenant_id.

DELIMITER $$
CREATE TRIGGER enforce_tenant_isolation
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF (SELECT tenant_id FROM users WHERE id = NEW.user_id) != NEW.tenant_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tenant data isolation violation';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enforces strict multi-tenant boundaries at the DB layer, preventing data leaks.


DELIMITER $$
CREATE EVENT enforce_sanctions
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE accounts
    SET status = 'FROZEN'
    WHERE id IN (
        SELECT DISTINCT account_id FROM transactions
        WHERE counterparty_id IN (SELECT entity_id FROM sanctioned_entities)
          AND txn_time > NOW() - INTERVAL 1 HOUR
    );
END$$
DELIMITER ;



-- 24. Trigger + Real-Time Deduplication (E-commerce: Prevent Duplicate Orders)
-- Scenario: On order insert, block if a similar order exists for the same user/product in the last 5 minutes.

DELIMITER $$
CREATE TRIGGER prevent_duplicate_orders
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM orders
        WHERE user_id = NEW.user_id
          AND product_id = NEW.product_id
          AND created_at > NOW() - INTERVAL 5 MINUTE
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate order detected';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time deduplication at the DB layer, preventing accidental or malicious double orders.

-- 25. Event + GDPR/PII Scrubbing (Compliance: Auto-Redact Old User Data)
-- Scenario: Every day, redact PII for users inactive for 3+ years, for GDPR compliance.

DELIMITER $$
CREATE EVENT redact_old_user_data
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE users
    SET email = NULL, phone = NULL, address = NULL
    WHERE last_active < NOW() - INTERVAL 3 YEAR;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates privacy compliance and reduces risk of data leaks.

-- 26. Trigger + Predictive Maintenance (Transport: Flag Vehicles for Service)
-- Scenario: On ride insert, if vehicle mileage exceeds threshold, flag for maintenance.

DELIMITER $$
CREATE TRIGGER flag_vehicle_maintenance
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE mileage INT;
    SELECT odometer INTO mileage FROM vehicles WHERE id = NEW.vehicle_id;
    IF mileage > 100000 THEN
        UPDATE vehicles SET needs_service = 1 WHERE id = NEW.vehicle_id;
        INSERT INTO maintenance_alerts (vehicle_id, alert_type, created_at)
        VALUES (NEW.vehicle_id, 'Mileage threshold exceeded', NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables predictive maintenance and reduces downtime, all in-SQL.

-- 11. Trigger + Error Handling + Notification (Finance: Alert on Failed Transaction Insert)
-- Scenario: If a transaction insert fails due to constraint violation, log the error and notify admins instantly.

-- Note: MySQL triggers cannot catch errors from the same statement that fires them, but you can use AFTER statements for logging or use SIGNAL for custom error handling.

-- 12. Event + Cross-Database Sync (E-commerce: Sync Inventory to Analytics DB)
-- Scenario: Every 10 minutes, sync new/updated inventory rows to a reporting/analytics database.

DELIMITER $$
CREATE EVENT sync_inventory_to_analytics
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO analytics_db.inventory_snapshot (product_id, stock, updated_at)
    SELECT id, stock, updated_at FROM main_db.products
    WHERE updated_at > NOW() - INTERVAL 10 MINUTE;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables near real-time cross-DB sync for analytics, without ETL pipeline overhead.

-- 13. Trigger + Time-Travel Auditing (Transport: Immutable Ride History)
-- Scenario: On any update to rides, store the old row in a history table for time-travel queries.

DELIMITER $$
CREATE TRIGGER audit_ride_history
BEFORE UPDATE ON rides
FOR EACH ROW
BEGIN
    INSERT INTO rides_history (ride_id, driver_id, user_id, status, fare, ride_time, archived_at)
    VALUES (OLD.id, OLD.driver_id, OLD.user_id, OLD.status, OLD.fare, OLD.ride_time, NOW());
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables time-travel queries and forensic analysis, critical for compliance and debugging.

-- 14. Event + Partition Management (Finance: Auto-Create Monthly Partitions)
-- Scenario: At the start of each month, auto-create a new partition for the transactions table.

DELIMITER $$
CREATE EVENT create_monthly_partition
ON SCHEDULE EVERY 1 MONTH STARTS '2025-08-01 00:00:00'
DO
BEGIN
    SET @sql = CONCAT('ALTER TABLE transactions ADD PARTITION (PARTITION p', DATE_FORMAT(NOW(), '%Y%m'), ' VALUES LESS THAN (TO_DAYS("', DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01'), '")))');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates partition management, keeping large tables performant with zero manual intervention.

-- 15. Trigger + Window Function + JSON (E-commerce: Real-Time Cart Abandonment Scoring)
-- Scenario: On cart update, calculate abandonment risk score using window function and store as JSON for ML/BI.

DELIMITER $$
CREATE TRIGGER score_cart_abandonment
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    DECLARE score_json JSON;
    SET score_json = (
        SELECT JSON_OBJECT('cart_id', NEW.id, 'risk_score',
            CASE WHEN COUNT(*) OVER (PARTITION BY user_id ORDER BY last_updated DESC) > 3 THEN 0.9 ELSE 0.2 END)
        FROM carts WHERE user_id = NEW.user_id AND last_updated > NOW() - INTERVAL 1 DAY LIMIT 1
    );
    UPDATE carts SET abandonment_score = score_json WHERE id = NEW.id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time, ML-ready scoring for cart abandonment, directly in the DB.

-- 6. Trigger + JSON + Window Function (Transport: Real-Time Surge Pricing by Zone)
-- Scenario: When a ride is inserted, recalculate surge multiplier for the zone using window function and store in a JSON column for analytics.

DELIMITER $$
CREATE TRIGGER update_surge_multiplier
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE surge JSON;
    SET surge = (
        SELECT JSON_OBJECT('zone', NEW.zone, 'multiplier',
            CASE WHEN COUNT(*) OVER (PARTITION BY zone ORDER BY ride_time RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING AND CURRENT ROW) > 50
                 THEN 1.5 ELSE 1.0 END)
        FROM rides WHERE zone = NEW.zone AND ride_time > NOW() - INTERVAL 10 MINUTE LIMIT 1
    );
    UPDATE zones SET surge_info = surge WHERE name = NEW.zone;
END$$
DELIMITER ;

-- Why it's advanced:
-- Uses window function and JSON for real-time, zone-based surge pricing analytics.

-- 7. Event + Recursive CTE + Partitioning (E-commerce: Clean Orphaned Categories)
-- Scenario: Nightly, recursively find and delete categories with no products, including all subcategories (using recursive CTE).

DELIMITER $$
CREATE EVENT cleanup_orphaned_categories
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE orphaned AS (
        SELECT id FROM categories WHERE id NOT IN (SELECT DISTINCT category_id FROM products)
        UNION ALL
        SELECT c.id FROM categories c
        INNER JOIN orphaned o ON c.parent_id = o.id
    )
    DELETE FROM categories WHERE id IN (SELECT id FROM orphaned);
END$$
DELIMITER ;

-- Why it's god-mode:
-- Recursively cleans up orphaned and nested categories, keeping taxonomy lean.

-- 8. Trigger + View + Partitioned Table (Finance: Real-Time Compliance Snapshot)
-- Scenario: After any transaction, update a compliance snapshot view and partitioned table for regulatory reporting.

CREATE OR REPLACE VIEW compliance_snapshot AS
SELECT account_id, SUM(amount) AS total, MAX(txn_time) AS last_txn
FROM transactions
GROUP BY account_id;

DELIMITER $$
CREATE TRIGGER update_compliance_partition
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    REPLACE INTO compliance_partitions (account_id, total, last_txn, partition_month)
    SELECT account_id, total, last_txn, DATE_FORMAT(NOW(), '%Y-%m')
    FROM compliance_snapshot WHERE account_id = NEW.account_id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Maintains regulatory snapshots in real-time, partitioned by month, using a view and trigger.

-- 9. Event + Window Function + JSON (Transport: Hourly Driver Utilization Analytics)
-- Scenario: Every hour, aggregate driver utilization stats using window functions and store as JSON for BI tools.

DELIMITER $$
CREATE EVENT hourly_driver_utilization
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO driver_utilization_analytics (driver_id, stats_json, created_at)
    SELECT driver_id,
           JSON_OBJECT('rides', COUNT(*), 'avg_rating', AVG(rating), 'rank', RANK() OVER (ORDER BY COUNT(*) DESC)),
           NOW()
    FROM rides
    WHERE ride_time > NOW() - INTERVAL 1 HOUR
    GROUP BY driver_id;
END$$
DELIMITER ;

-- Why it's ingenious:
-- Combines window functions, aggregation, and JSON for BI-ready analytics, all in an event.

-- 10. Trigger + Partitioned Table + Recursive CTE (E-commerce: Auto-Expire Stale Carts)
-- Scenario: When a cart is updated, recursively expire all items in the cart and sub-carts if last updated > 24h ago, using partitioning and recursive CTE.

DELIMITER $$
CREATE TRIGGER expire_stale_carts
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    WITH RECURSIVE stale_carts AS (
        SELECT id FROM carts WHERE id = NEW.id AND last_updated < NOW() - INTERVAL 24 HOUR
        UNION ALL
        SELECT c.id FROM carts c
        INNER JOIN stale_carts sc ON c.parent_cart_id = sc.id
    )
    UPDATE carts SET status = 'EXPIRED' WHERE id IN (SELECT id FROM stale_carts);
END$$
DELIMITER ;

-- Why it's god-mode:
-- Recursively expires stale carts and all their sub-carts, keeping the system clean and fast.

    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    salary DECIMAL(10,2) NOT NULL,
    designation VARCHAR(50) NOT NULL,
    dept_id VARCHAR(50) NOT NULL
);

-- Insert sample data
INSERT INTO employee_salary (first_name, last_name, salary, designation, dept_id) VALUES
('John', 'Doe', 75000.00, 'Software Engineer', 'Development'),
('Jane', 'Smith', 82000.00, 'Senior Developer', 'Development'),
('Alice', 'Johnson', 65000.00, 'QA Analyst', 'Quality Assurance'),
('Bob', 'Williams', 90000.00, 'Team Lead', 'Development'),
('Eve', 'Davis', 70000.00, 'Business Analyst', 'Business Intelligence'),
('Charlie', 'Brown', 68000.00, 'Support Engineer', 'Support'),
('Grace', 'Lee', 78000.00, 'UI/UX Designer', 'Design'),
-- Create table employee_demographics
CREATE TABLE employee_demographics (
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    dob DATE NOT NULL,
    gender ENUM('M', 'F', 'O') NOT NULL
);

-- Insert sample data for employee_demographics
INSERT INTO employee_demographics (employee_id, age, first_name, last_name, dob, gender) VALUES
(1, 28, 'John', 'Doe', '1997-03-15', 'M'),
(2, 32, 'Jane', 'Smith', '1993-11-22', 'F'),
(3, 26, 'Alice', 'Johnson', '1999-07-09', 'F'),
(4, 35, 'Bob', 'Williams', '1990-01-30', 'M'),
(7, 38, 'Diana', 'Evans', '1987-12-03', 'F'),
(10, 33, 'Henry', 'Clark', '1992-02-28', 'M');

-- Requirement: Mus update employee_demographics when a new employee is added to the employee_salary table

-- SOLUTION: Create a trigger to automatically insert into employee_demographics when a new employee is added to employee_salary

-- DELIMITER $$ helps to run multiple queries in a single execution block 
DELIMITER $$

CREATE TRIGGER after_employee_insert
AFTER INSERT ON employee_salary
FOR EACH ROW
BEGIN
    INSERT INTO employee_demographics (employee_id, first_name, last_name) VALUES (NEW.employee_id, NEW.first_name, NEW.last_name);
 END$$  

-- EVENTS: 

-- In MySQL, use events when you need to schedule and automate tasks to run at specific times or intervals, similar to cron jobs in Unix. Events are useful for:

-- Periodic data cleanup (e.g., deleting old records every night)
-- Regular backups or archiving
-- Automatically updating summary tables or statistics
-- Sending scheduled notifications or reports
-- Resetting counters or temporary data at set intervals
-- Events are best for time-based, recurring, or one-off scheduled operations that do not depend on a specific data change (unlike triggers, which react to table modifications).

-- If any row where age >= 60, then it will be automatically deleted from employee_demographics table
CREATE EVENT delete_retired_employees
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    DELETE FROM employee_demographics WHERE age > 60;
END;
-- This event will run every month and delete any employee from the employee_demographics table whose age is greater than or equal to 60.
DELIMITER;

SHOW VARIABLES LIKE 'event%;

-- 1. Finance (e.g., Amazon Payments)

-- Scenario:

-- Prevent negative balances on transactions.

Before updating account balance, block if result < 0.
After any update/delete on transactions, log old/new values to an audit table.
After insert on transactions, if amount > $10,000 or from flagged country, auto-flag account.

Event:

Nightly event to scan for accounts with >3 failed logins in 24h, auto-lock and notify security.

-- Block negative balances & Audit changes

-- Block negative balances
BEFORE UPDATE ON accounts
    IF NEW.balance < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Negative balance not allowed';
    END IF;
END$$
DELIMITER;

-- Audit changes
DELIMITER $$
CREATE TRIGGER audit_transactions
AFTER UPDATE ON transactions
FOR EACH ROW
    VALUES (OLD.id, OLD.amount, NEW.amount, NOW());

2. Transport/Logistics (e.g., Uber)
Scenario:

Auto-calculate driver ratings and bonuses.
Prevent double-booking of drivers.
Track suspicious ride patterns.
Triggers:

After insert on rides, update driver’s average rating and bonus eligibility.
Before insert on rides, block if driver is already assigned to another ride at the same time.
After insert on rides, if pickup/dropoff locations are the same, log for fraud review.
Event:

Every hour, event to find drivers with >10 rides in 1 hour (possible bot), flag for review.

CREATE TRIGGER prevent_double_booking
BEGIN
    IF EXISTS (
        SELECT 1 FROM rides
        WHERE driver_id = NEW.driver_id
          AND ride_time = NEW.ride_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Driver already booked for this time';
    END IF;
END$$
DELIMITER;

-- Auto-flag suspicious rides
DELIMITER $$
CREATE TRIGGER flag_suspicious_ride
AFTER INSERT ON rides
FOR EACH ROW
        INSERT INTO suspicious_rides (ride_id, reason, created_at)
END$$
DELIMITER;


3. E-commerce/Marketplace (e.g., Amazon, Airbnb)
Scenario:

Auto-update product stock and alert on low inventory.
Prevent duplicate bookings.
Dynamic pricing adjustments.
Triggers:

After update on orders, decrement product stock, if stock < threshold, insert alert into notifications.
Before insert on bookings, block if property is already booked for those dates.
After insert/update on reviews, recalculate product/property average rating.
Event:

Every 5 minutes, event to adjust prices based on demand (e.g., if >80% booked, increase price by 10%).

CREATE TRIGGER alert_low_stock
AFTER UPDATE ON products
FOR EACH ROW
BEGIN
    IF NEW.stock < 10 THEN
        INSERT INTO notifications (product_id, message, created_at)
        VALUES (NEW.id, 'Low stock alert', NOW());
    END IF;
END$$
DELIMITER;

-- Scheduled Event: Dynamic Pricing Adjustment

DELIMITER $$
CREATE EVENT adjust_dynamic_pricing
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    UPDATE properties
    SET price = price * 1.10
    WHERE bookings_last_week > 0.8 * total_capacity;
END$$
DELIMITER;

1. Event + Partitioning + Window Functions (E-commerce Flash Sale Cleanup)
Scenario:
Auto-expire the oldest orders in a flash sale table, but only keep the latest N per product (using window functions and partitions).

Event Example:

DELIMITER $$
CREATE EVENT cleanup_flash_sale_orders
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    DELETE FROM flash_sale_orders
    WHERE order_id IN (
        SELECT order_id FROM (
            SELECT order_id,
                   ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY created_at DESC) AS rn
            FROM flash_sale_orders
        ) t
        WHERE t.rn > 100
    );
END$$
DELIMITER ;

-- Why it's advanced:

-- Uses window functions and partitioning logic inside an event for efficient, rolling cleanup.

-- 2. Trigger + Recursive CTE (Transport: Auto-Update Ride Chains)
-- Scenario:

-- When a ride is updated, recursively update all dependent rides (e.g., chained bookings for carpooling).

-- Trigger Example:

DELIMITER $$
CREATE TRIGGER update_ride_chain
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    WITH RECURSIVE ride_chain AS (
        SELECT id, next_ride_id FROM rides WHERE id = NEW.id
        UNION ALL
        SELECT r.id, r.next_ride_id
        FROM rides r
        INNER JOIN ride_chain rc ON r.id = rc.next_ride_id
    )
    UPDATE rides
    SET status = NEW.status
    WHERE id IN (SELECT id FROM ride_chain);
END$$
DELIMITER;

-- Why it's ingenious:

-- Uses a recursive CTE inside a trigger to propagate changes through a chain of related records.


-- 3. Trigger + View + Window Function (Finance: Real-Time Leaderboard)
Scenario:

-- Maintain a real-time leaderboard of top accounts by transaction volume, using a view and a trigger to update a summary table.

-- View Example:

CREATE OR REPLACE VIEW account_leaderboard AS
SELECT account_id,
       SUM(amount) AS total_volume,
       RANK() OVER (ORDER BY SUM(amount) DESC) AS rank
FROM transactions
GROUP BY account_id;

DELIMITER $$
CREATE TRIGGER update_leaderboard
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    REPLACE INTO leaderboard_summary (account_id, total_volume, rank)
    SELECT account_id, total_volume, rank
    FROM account_leaderboard
    WHERE account_id = NEW.account_id;
END$$
DELIMITER ;

-- Why it's patchy/god-mode:

-- Combines a view with a window function and a trigger for near real-time analytics.


-- Scenario: Nightly, aggregate user activity by partition (e.g., region), using CTEs for complex logic, and store in a summary table.

DELIMITER $$
CREATE EVENT aggregate_user_activity
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH region_activity AS (
        SELECT region, COUNT(*) AS activity_count
        FROM user_events
        WHERE event_time >= CURDATE() - INTERVAL 1 DAY
        GROUP BY region
    )
    REPLACE INTO daily_region_activity (region, activity_count, activity_date)
    SELECT region, activity_count, CURDATE() FROM region_activity;
END$$
DELIMITER ;

-- Why it's advanced:

-- Uses CTEs and partitioning logic in an event for efficient, scalable aggregation.


-- 5. Trigger + Partitioned Table + Window Function (Finance: Auto-Archive Old Transactions)

-- Scenario: When a transaction is inserted, if the partition (e.g., month) exceeds a row limit, auto-archive the oldest rows using a window function.


DELIMITER $$
CREATE TRIGGER archive_old_transactions
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DELETE FROM transactions
    WHERE transaction_id IN (
        SELECT transaction_id FROM (
            SELECT transaction_id,
                   ROW_NUMBER() OVER (PARTITION BY YEAR(txn_time), MONTH(txn_time) ORDER BY txn_time ASC) AS rn
            FROM transactions
            WHERE YEAR(txn_time) = YEAR(NEW.txn_time)
              AND MONTH(txn_time) = MONTH(NEW.txn_time)
        ) t
        WHERE t.rn > 100000
    );
END$$
DELIMITER;


-- Why it's god-mode:

-- Keeps partitions lean, auto-archives, and uses window functions for precise control.

-- 46. Trigger + Event + CTE (E-commerce: Auto-Expire Unused Coupons and Notify Users)
-- Scenario: On coupon usage, mark as used. Nightly event finds and expires unused coupons older than 30 days, and notifies users.

DELIMITER $$
CREATE TRIGGER mark_coupon_used
AFTER UPDATE ON coupons
FOR EACH ROW
BEGIN
    IF NEW.used = 1 AND OLD.used = 0 THEN
        UPDATE coupons SET used_at = NOW() WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT expire_unused_coupons
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH expired AS (
        SELECT id, user_id FROM coupons WHERE used = 0 AND created_at < NOW() - INTERVAL 30 DAY
    )
    UPDATE coupons SET status = 'EXPIRED' WHERE id IN (SELECT id FROM expired);
    INSERT INTO notifications (user_id, message, created_at)
    SELECT user_id, 'Your coupon has expired', NOW() FROM expired;
END$$
DELIMITER ;

-- Why it's advanced:
-- Automates coupon lifecycle and user notification with CTEs and events.

-- 47. Trigger + JSON + Error Handling (Finance: Block and Log Suspicious Withdrawals)
-- Scenario: On withdrawal insert, block and log as JSON if amount exceeds daily limit or from flagged country.

DELIMITER $$
CREATE TRIGGER block_and_log_suspicious_withdrawal
BEFORE INSERT ON withdrawals
FOR EACH ROW
BEGIN
    DECLARE total_today DECIMAL(10,2);
    SELECT SUM(amount) INTO total_today FROM withdrawals WHERE user_id = NEW.user_id AND withdrawal_time > CURDATE();
    IF NEW.amount > 5000 OR total_today + NEW.amount > 10000 OR NEW.country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO withdrawal_fraud_log (withdrawal_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.country, 'withdrawal', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Suspicious withdrawal blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Real-time fraud prevention and forensic logging using JSON and error signaling.

-- 48. Event + Partitioning + Analytics (Transport: Auto-Archive Old Trip Data by Region)
-- Scenario: Every month, archive trips older than 1 year by region partition for analytics and cost savings.

DELIMITER $$
DO
    DELETE FROM trips WHERE trip_date < NOW() - INTERVAL 1 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Region-partitioned archiving for scalable analytics and storage efficiency.

-- 49. Trigger + Recursive CTE (SaaS: Auto-Disable Orphaned Subscriptions)
-- Scenario: On user delete, recursively disable all dependent subscriptions and child accounts.

DELIMITER $$
CREATE TRIGGER disable_orphaned_subscriptions
AFTER DELETE ON users
    WITH RECURSIVE orphans AS (
        SELECT id FROM subscriptions WHERE user_id = OLD.id
        UNION ALL
        SELECT s.id FROM subscriptions s
        INNER JOIN orphans o ON s.parent_subscription_id = o.id
    )
    UPDATE subscriptions SET status = 'DISABLED' WHERE id IN (SELECT id FROM orphans);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively disables orphaned subscriptions, ensuring data integrity in multi-level SaaS hierarchies.

-- 50. Event + Dynamic SQL + CTE (E-commerce: Auto-Optimize Product Indexes Based on Query Stats)
-- Scenario: Weekly event analyzes query stats, adds/drops indexes dynamically for hot/cold product columns.

DELIMITER $$
CREATE EVENT optimize_product_indexes
BEGIN
    -- Example: Add index if query count high (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE products ADD INDEX idx_hot (hot_column)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if query count low (pseudo-code)
    -- SET @sql = 'ALTER TABLE products DROP INDEX idx_cold';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates index optimization using query stats, CTEs, and dynamic SQL for peak performance.
-- Scenario: Every week, recursively delete expired promo codes and all their dependent child codes using dynamic SQL.

DELIMITER $$
CREATE EVENT cleanup_expired_promo_codes
BEGIN
    WITH RECURSIVE expired_codes AS (
        SELECT id FROM promo_codes WHERE expires_at < NOW()
        UNION ALL
        SELECT c.id FROM promo_codes c
        INNER JOIN expired_codes e ON c.parent_code_id = e.id
    )
    DELETE FROM promo_codes WHERE id IN (SELECT id FROM expired_codes);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively and automatically cleans up expired and dependent promo codes, keeping the system lean.

-- 44. Trigger + Error Handling + Notification (Transport: Alert on Failed Payment Insert)
-- Scenario: On failed payment insert (e.g., constraint violation), log the error and notify admins instantly.
DELIMITER $$
CREATE TRIGGER log_failed_payment
BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    IF NEW.amount <= 0 THEN
        INSERT INTO payment_errors (user_id, amount, error_msg, created_at)
        VALUES (NEW.user_id, NEW.amount, 'Invalid payment amount', NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid payment amount';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Provides instant error logging and admin notification for payment issues, improving reliability.

-- 45. Event + Cross-Database + Analytics (SaaS: Sync Usage Stats to Analytics DB with Partition Awareness)
-- Scenario: Every hour, sync usage stats to analytics DB, partitioned by month, for BI/reporting.

DELIMITER $$
CREATE EVENT sync_usage_stats_to_analytics
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO analytics_db.usage_stats_partitioned (user_id, usage_count, stat_month, synced_at)
    SELECT user_id, COUNT(*), DATE_FORMAT(NOW(), '%Y-%m'), NOW()
    GROUP BY user_id;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables cross-DB, partition-aware analytics sync for scalable BI/reporting.

DELIMITER $$
CREATE EVENT invalidate_stale_driver_cache
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    DELETE FROM driver_location_cache
    WHERE driver_id IN (
        SELECT id FROM drivers WHERE last_location_update < NOW() - INTERVAL 30 MINUTE
    );
END$$
DELIMITER ;



-- 30. Trigger + Real-Time SLA Enforcement (Transport: Flag Late Rides)
-- Scenario: On ride update, if actual dropoff is later than promised, flag for SLA breach.

DELIMITER $$
CREATE TRIGGER flag_sla_breach
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    IF NEW.dropoff_time > NEW.promised_dropoff_time AND OLD.dropoff_time <= OLD.promised_dropoff_time THEN
        UPDATE rides SET sla_breached = 1 WHERE id = NEW.id;
        INSERT INTO sla_breach_log (ride_id, breached_at)
        VALUES (NEW.id, NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enforces SLAs in real-time, enabling proactive customer support and analytics.

-- 31. Event + Data Masking (Finance: Mask Sensitive Data for Analytics)
-- Scenario: Every night, mask PII in analytics tables while keeping raw data in production.

DELIMITER $$
CREATE EVENT mask_analytics_pii
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE analytics.transactions
    SET card_number = CONCAT('XXXX-XXXX-XXXX-', RIGHT(card_number, 4)),
        user_email = CONCAT(LEFT(user_email, 2), '***@***.com');
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures analytics teams never see raw PII, reducing compliance risk.

-- 32. Event + Dynamic Index Management (E-commerce: Auto-Add/Drop Indexes Based on Usage)
-- Scenario: Every week, analyze slow queries and auto-add/drop indexes for hot/cold columns.

DELIMITER $$
CREATE EVENT dynamic_index_management
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    -- Example: Add index if slow queries detected (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE orders ADD INDEX idx_status (status)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if unused (pseudo-code)
    -- SET @sql = 'ALTER TABLE orders DROP INDEX idx_old_unused';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's advanced:

-- 33. Event + Archiving (E-commerce: Move Old Orders to Archive Table)
-- Scenario: Every month, move orders older than 2 years to an archive table for cost savings and performance.

DELIMITER $$
CREATE EVENT archive_old_orders
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    INSERT INTO orders_archive SELECT * FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
    DELETE FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Keeps operational tables lean and fast, while preserving history for compliance.

-- 34. Trigger + Real-Time Escalation (Transport: Escalate Unassigned Rides)
-- Scenario: On ride insert, if not assigned to a driver within 2 minutes, auto-escalate to human dispatcher.

DELIMITER $$
CREATE TRIGGER escalate_unassigned_ride
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    IF NEW.driver_id IS NULL THEN
        INSERT INTO ride_escalations (ride_id, escalated_at)
        VALUES (NEW.id, NOW() + INTERVAL 2 MINUTE);
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures no ride is left unassigned, improving customer experience and reducing cancellations.

-- 35. Event + Adaptive Sharding (Finance: Rebalance Accounts Across Shards)
-- Scenario: Every week, move accounts with high activity to dedicated shards for load balancing.

DELIMITER $$
CREATE EVENT rebalance_account_shards
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    INSERT INTO accounts_hot_shard SELECT * FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
    DELETE FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
END$$
DELIMITER ;

-- Why it's advanced:
-- Dynamically rebalances hot accounts for optimal performance at scale.
DELIMITER $$
CREATE EVENT detect_transaction_spikes
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO anomaly_alerts (account_id, alert_type, detected_at)
    SELECT t.account_id, 'spike', NOW()
    FROM (
        SELECT account_id,
               COUNT(*) AS txn_count,
               (SELECT AVG(cnt) FROM (
                   SELECT COUNT(*) AS cnt FROM transactions
                   WHERE account_id = transactions.account_id
                   AND txn_time > NOW() - INTERVAL 7 DAY
                   GROUP BY DATE(txn_time)
               ) x) AS avg_daily
        FROM transactions
        WHERE txn_time > NOW() - INTERVAL 1 DAY
        GROUP BY account_id
    ) t
    WHERE t.txn_count > 5 * t.avg_daily;
END$$
DELIMITER ;


-- 36. Trigger + Event + Recursive CTE (SaaS: Automated Subscription Expiry and Grace Period Handling)
-- Scenario: On subscription expiry, auto-move user to grace period, and nightly event purges expired grace users recursively (including dependents).

DELIMITER $$
CREATE TRIGGER move_to_grace_period
AFTER UPDATE ON subscriptions
FOR EACH ROW
BEGIN
    IF NEW.status = 'EXPIRED' AND OLD.status != 'EXPIRED' THEN
        UPDATE users SET status = 'GRACE' WHERE id = NEW.user_id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT purge_expired_grace_users
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE expired_users AS (
        SELECT id FROM users WHERE status = 'GRACE' AND updated_at < NOW() - INTERVAL 14 DAY
        UNION ALL
        SELECT u.id FROM users u
        INNER JOIN expired_users e ON u.parent_id = e.id
    )
    DELETE FROM users WHERE id IN (SELECT id FROM expired_users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Combines triggers, events, and recursive CTEs for automated, multi-level subscription lifecycle management.

-- 37. Trigger + JSON + Error Handling (E-commerce: Real-Time Fraud Pattern Logging)
-- Scenario: On suspicious order insert, log full order as JSON in a fraud log table and block the insert.

DELIMITER $$
CREATE TRIGGER log_and_block_fraud_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.amount > 10000 OR NEW.shipping_country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO fraud_orders_log (order_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.shipping_country, 'order', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fraudulent order blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Instantly blocks and logs suspicious orders with full context for forensics, using JSON and custom error signaling.

-- 38. Event + Cross-Table Consistency (Transport: Auto-Heal Broken Foreign Keys)
-- Scenario: Every hour, scan for rides referencing missing drivers or users, and auto-fix or log for manual review.

DELIMITER $$
CREATE EVENT heal_broken_ride_fks
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    -- Log rides with missing drivers
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_driver', NOW() FROM rides WHERE driver_id NOT IN (SELECT id FROM drivers);
    -- Log rides with missing users
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_user', NOW() FROM rides WHERE user_id NOT IN (SELECT id FROM users);
    -- Optionally, set driver_id/user_id to NULL or a default value for orphaned rides
    UPDATE rides SET driver_id = NULL WHERE driver_id NOT IN (SELECT id FROM drivers);
    UPDATE rides SET user_id = NULL WHERE user_id NOT IN (SELECT id FROM users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Proactively detects and heals referential integrity issues, reducing data corruption risk at scale.

-- 39. Trigger + Partitioned Table + Dynamic SQL (Finance: Auto-Move Large Transactions to Audit Partition)
-- Scenario: On large transaction insert, move it to a special audit partition using dynamic SQL.

DELIMITER $$
CREATE TRIGGER move_large_txn_to_audit
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount > 50000 THEN
        SET @sql = CONCAT('INSERT INTO transactions_audit PARTITION (p', DATE_FORMAT(NOW(), '%Y%m'), ') SELECT * FROM transactions WHERE id = ', NEW.id, ';');
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        DELETE FROM transactions WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Uses dynamic SQL in a trigger to move sensitive data to a secure, partitioned audit table in real-time.

-- 40. Event + Predictive Analytics (E-commerce: Auto-Flag Products for Restock Based on ML Score)
-- Scenario: Every night, flag products for restock if ML-predicted demand score is high, using a precomputed ML table.

DELIMITER $$
CREATE EVENT flag_products_for_restock
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE products p
    JOIN product_demand_ml ml ON p.id = ml.product_id
    SET p.restock_flag = 1
    WHERE ml.predicted_demand > 0.8 AND p.stock < 20;
END$$
DELIMITER ;

-- Why it's advanced:
-- Integrates ML predictions into operational DB logic for proactive inventory management.

-- 22. Trigger + Multi-Tenant Data Isolation (SaaS: Enforce Tenant Boundaries)
-- Scenario: On insert/update, block cross-tenant data access by checking tenant_id.

DELIMITER $$
CREATE TRIGGER enforce_tenant_isolation
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF (SELECT tenant_id FROM users WHERE id = NEW.user_id) != NEW.tenant_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tenant data isolation violation';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enforces strict multi-tenant boundaries at the DB layer, preventing data leaks.


DELIMITER $$
CREATE EVENT enforce_sanctions
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE accounts
    SET status = 'FROZEN'
    WHERE id IN (
        SELECT DISTINCT account_id FROM transactions
        WHERE counterparty_id IN (SELECT entity_id FROM sanctioned_entities)
          AND txn_time > NOW() - INTERVAL 1 HOUR
    );
END$$
DELIMITER ;



-- 24. Trigger + Real-Time Deduplication (E-commerce: Prevent Duplicate Orders)
-- Scenario: On order insert, block if a similar order exists for the same user/product in the last 5 minutes.

DELIMITER $$
CREATE TRIGGER prevent_duplicate_orders
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM orders
        WHERE user_id = NEW.user_id
          AND product_id = NEW.product_id
          AND created_at > NOW() - INTERVAL 5 MINUTE
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate order detected';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time deduplication at the DB layer, preventing accidental or malicious double orders.

-- 25. Event + GDPR/PII Scrubbing (Compliance: Auto-Redact Old User Data)
-- Scenario: Every day, redact PII for users inactive for 3+ years, for GDPR compliance.

DELIMITER $$
CREATE EVENT redact_old_user_data
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE users
    SET email = NULL, phone = NULL, address = NULL
    WHERE last_active < NOW() - INTERVAL 3 YEAR;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates privacy compliance and reduces risk of data leaks.

-- 26. Trigger + Predictive Maintenance (Transport: Flag Vehicles for Service)
-- Scenario: On ride insert, if vehicle mileage exceeds threshold, flag for maintenance.

DELIMITER $$
CREATE TRIGGER flag_vehicle_maintenance
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE mileage INT;
    SELECT odometer INTO mileage FROM vehicles WHERE id = NEW.vehicle_id;
    IF mileage > 100000 THEN
        UPDATE vehicles SET needs_service = 1 WHERE id = NEW.vehicle_id;
        INSERT INTO maintenance_alerts (vehicle_id, alert_type, created_at)
        VALUES (NEW.vehicle_id, 'Mileage threshold exceeded', NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables predictive maintenance and reduces downtime, all in-SQL.

-- 11. Trigger + Error Handling + Notification (Finance: Alert on Failed Transaction Insert)
-- Scenario: If a transaction insert fails due to constraint violation, log the error and notify admins instantly.

-- Note: MySQL triggers cannot catch errors from the same statement that fires them, but you can use AFTER statements for logging or use SIGNAL for custom error handling.

-- 12. Event + Cross-Database Sync (E-commerce: Sync Inventory to Analytics DB)
-- Scenario: Every 10 minutes, sync new/updated inventory rows to a reporting/analytics database.

DELIMITER $$
CREATE EVENT sync_inventory_to_analytics
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO analytics_db.inventory_snapshot (product_id, stock, updated_at)
    SELECT id, stock, updated_at FROM main_db.products
    WHERE updated_at > NOW() - INTERVAL 10 MINUTE;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables near real-time cross-DB sync for analytics, without ETL pipeline overhead.

-- 13. Trigger + Time-Travel Auditing (Transport: Immutable Ride History)
-- Scenario: On any update to rides, store the old row in a history table for time-travel queries.

DELIMITER $$
CREATE TRIGGER audit_ride_history
BEFORE UPDATE ON rides
FOR EACH ROW
BEGIN
    INSERT INTO rides_history (ride_id, driver_id, user_id, status, fare, ride_time, archived_at)
    VALUES (OLD.id, OLD.driver_id, OLD.user_id, OLD.status, OLD.fare, OLD.ride_time, NOW());
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables time-travel queries and forensic analysis, critical for compliance and debugging.

-- 14. Event + Partition Management (Finance: Auto-Create Monthly Partitions)
-- Scenario: At the start of each month, auto-create a new partition for the transactions table.

DELIMITER $$
CREATE EVENT create_monthly_partition
ON SCHEDULE EVERY 1 MONTH STARTS '2025-08-01 00:00:00'
DO
BEGIN
    SET @sql = CONCAT('ALTER TABLE transactions ADD PARTITION (PARTITION p', DATE_FORMAT(NOW(), '%Y%m'), ' VALUES LESS THAN (TO_DAYS("', DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01'), '")))');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates partition management, keeping large tables performant with zero manual intervention.

-- 15. Trigger + Window Function + JSON (E-commerce: Real-Time Cart Abandonment Scoring)
-- Scenario: On cart update, calculate abandonment risk score using window function and store as JSON for ML/BI.

DELIMITER $$
CREATE TRIGGER score_cart_abandonment
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    DECLARE score_json JSON;
    SET score_json = (
        SELECT JSON_OBJECT('cart_id', NEW.id, 'risk_score',
            CASE WHEN COUNT(*) OVER (PARTITION BY user_id ORDER BY last_updated DESC) > 3 THEN 0.9 ELSE 0.2 END)
        FROM carts WHERE user_id = NEW.user_id AND last_updated > NOW() - INTERVAL 1 DAY LIMIT 1
    );
    UPDATE carts SET abandonment_score = score_json WHERE id = NEW.id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time, ML-ready scoring for cart abandonment, directly in the DB.

-- 6. Trigger + JSON + Window Function (Transport: Real-Time Surge Pricing by Zone)
-- Scenario: When a ride is inserted, recalculate surge multiplier for the zone using window function and store in a JSON column for analytics.

DELIMITER $$
CREATE TRIGGER update_surge_multiplier
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE surge JSON;
    SET surge = (
        SELECT JSON_OBJECT('zone', NEW.zone, 'multiplier',
            CASE WHEN COUNT(*) OVER (PARTITION BY zone ORDER BY ride_time RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING AND CURRENT ROW) > 50
                 THEN 1.5 ELSE 1.0 END)
        FROM rides WHERE zone = NEW.zone AND ride_time > NOW() - INTERVAL 10 MINUTE LIMIT 1
    );
    UPDATE zones SET surge_info = surge WHERE name = NEW.zone;
END$$
DELIMITER ;

-- Why it's advanced:
-- Uses window function and JSON for real-time, zone-based surge pricing analytics.

-- 7. Event + Recursive CTE + Partitioning (E-commerce: Clean Orphaned Categories)
-- Scenario: Nightly, recursively find and delete categories with no products, including all subcategories (using recursive CTE).

DELIMITER $$
CREATE EVENT cleanup_orphaned_categories
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE orphaned AS (
        SELECT id FROM categories WHERE id NOT IN (SELECT DISTINCT category_id FROM products)
        UNION ALL
        SELECT c.id FROM categories c
        INNER JOIN orphaned o ON c.parent_id = o.id
    )
    DELETE FROM categories WHERE id IN (SELECT id FROM orphaned);
END$$
DELIMITER ;

-- Why it's god-mode:
-- Recursively cleans up orphaned and nested categories, keeping taxonomy lean.

-- 8. Trigger + View + Partitioned Table (Finance: Real-Time Compliance Snapshot)
-- Scenario: After any transaction, update a compliance snapshot view and partitioned table for regulatory reporting.

CREATE OR REPLACE VIEW compliance_snapshot AS
SELECT account_id, SUM(amount) AS total, MAX(txn_time) AS last_txn
FROM transactions
GROUP BY account_id;

DELIMITER $$
CREATE TRIGGER update_compliance_partition
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    REPLACE INTO compliance_partitions (account_id, total, last_txn, partition_month)
    SELECT account_id, total, last_txn, DATE_FORMAT(NOW(), '%Y-%m')
    FROM compliance_snapshot WHERE account_id = NEW.account_id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Maintains regulatory snapshots in real-time, partitioned by month, using a view and trigger.

-- 9. Event + Window Function + JSON (Transport: Hourly Driver Utilization Analytics)
-- Scenario: Every hour, aggregate driver utilization stats using window functions and store as JSON for BI tools.

DELIMITER $$
CREATE EVENT hourly_driver_utilization
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO driver_utilization_analytics (driver_id, stats_json, created_at)
    SELECT driver_id,
           JSON_OBJECT('rides', COUNT(*), 'avg_rating', AVG(rating), 'rank', RANK() OVER (ORDER BY COUNT(*) DESC)),
           NOW()
    FROM rides
    WHERE ride_time > NOW() - INTERVAL 1 HOUR
    GROUP BY driver_id;
END$$
DELIMITER ;

-- Why it's ingenious:
-- Combines window functions, aggregation, and JSON for BI-ready analytics, all in an event.

-- 10. Trigger + Partitioned Table + Recursive CTE (E-commerce: Auto-Expire Stale Carts)
-- Scenario: When a cart is updated, recursively expire all items in the cart and sub-carts if last updated > 24h ago, using partitioning and recursive CTE.

DELIMITER $$
CREATE TRIGGER expire_stale_carts
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    WITH RECURSIVE stale_carts AS (
        SELECT id FROM carts WHERE id = NEW.id AND last_updated < NOW() - INTERVAL 24 HOUR
        UNION ALL
        SELECT c.id FROM carts c
        INNER JOIN stale_carts sc ON c.parent_cart_id = sc.id
    )
    UPDATE carts SET status = 'EXPIRED' WHERE id IN (SELECT id FROM stale_carts);
END$$
DELIMITER ;

-- Why it's god-mode:
-- Recursively expires stale carts and all their sub-carts, keeping the system clean and fast.

    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    salary DECIMAL(10,2) NOT NULL,
    designation VARCHAR(50) NOT NULL,
    dept_id VARCHAR(50) NOT NULL
);

-- Insert sample data
INSERT INTO employee_salary (first_name, last_name, salary, designation, dept_id) VALUES
('John', 'Doe', 75000.00, 'Software Engineer', 'Development'),
('Jane', 'Smith', 82000.00, 'Senior Developer', 'Development'),
('Alice', 'Johnson', 65000.00, 'QA Analyst', 'Quality Assurance'),
('Bob', 'Williams', 90000.00, 'Team Lead', 'Development'),
('Eve', 'Davis', 70000.00, 'Business Analyst', 'Business Intelligence'),
('Charlie', 'Brown', 68000.00, 'Support Engineer', 'Support'),
('Grace', 'Lee', 78000.00, 'UI/UX Designer', 'Design'),
-- Create table employee_demographics
CREATE TABLE employee_demographics (
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    dob DATE NOT NULL,
    gender ENUM('M', 'F', 'O') NOT NULL
);

-- Insert sample data for employee_demographics
INSERT INTO employee_demographics (employee_id, age, first_name, last_name, dob, gender) VALUES
(1, 28, 'John', 'Doe', '1997-03-15', 'M'),
(2, 32, 'Jane', 'Smith', '1993-11-22', 'F'),
(3, 26, 'Alice', 'Johnson', '1999-07-09', 'F'),
(4, 35, 'Bob', 'Williams', '1990-01-30', 'M'),
(7, 38, 'Diana', 'Evans', '1987-12-03', 'F'),
(10, 33, 'Henry', 'Clark', '1992-02-28', 'M');

-- Requirement: Mus update employee_demographics when a new employee is added to the employee_salary table

-- SOLUTION: Create a trigger to automatically insert into employee_demographics when a new employee is added to employee_salary

-- DELIMITER $$ helps to run multiple queries in a single execution block 
DELIMITER $$

CREATE TRIGGER after_employee_insert
AFTER INSERT ON employee_salary
FOR EACH ROW
BEGIN
    INSERT INTO employee_demographics (employee_id, first_name, last_name) VALUES (NEW.employee_id, NEW.first_name, NEW.last_name);
 END$$  

-- EVENTS: 

-- In MySQL, use events when you need to schedule and automate tasks to run at specific times or intervals, similar to cron jobs in Unix. Events are useful for:

-- Periodic data cleanup (e.g., deleting old records every night)
-- Regular backups or archiving
-- Automatically updating summary tables or statistics
-- Sending scheduled notifications or reports
-- Resetting counters or temporary data at set intervals
-- Events are best for time-based, recurring, or one-off scheduled operations that do not depend on a specific data change (unlike triggers, which react to table modifications).

-- If any row where age >= 60, then it will be automatically deleted from employee_demographics table
CREATE EVENT delete_retired_employees
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    DELETE FROM employee_demographics WHERE age > 60;
END;
-- This event will run every month and delete any employee from the employee_demographics table whose age is greater than or equal to 60.
DELIMITER;

SHOW VARIABLES LIKE 'event%;

-- 1. Finance (e.g., Amazon Payments)

-- Scenario:

-- Prevent negative balances on transactions.

Before updating account balance, block if result < 0.
After any update/delete on transactions, log old/new values to an audit table.
After insert on transactions, if amount > $10,000 or from flagged country, auto-flag account.

Event:

Nightly event to scan for accounts with >3 failed logins in 24h, auto-lock and notify security.

-- Block negative balances & Audit changes

-- Block negative balances
BEFORE UPDATE ON accounts
    IF NEW.balance < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Negative balance not allowed';
    END IF;
END$$
DELIMITER;

-- Audit changes
DELIMITER $$
CREATE TRIGGER audit_transactions
AFTER UPDATE ON transactions
FOR EACH ROW
    VALUES (OLD.id, OLD.amount, NEW.amount, NOW());

2. Transport/Logistics (e.g., Uber)
Scenario:

Auto-calculate driver ratings and bonuses.
Prevent double-booking of drivers.
Track suspicious ride patterns.
Triggers:

After insert on rides, update driver’s average rating and bonus eligibility.
Before insert on rides, block if driver is already assigned to another ride at the same time.
After insert on rides, if pickup/dropoff locations are the same, log for fraud review.
Event:

Every hour, event to find drivers with >10 rides in 1 hour (possible bot), flag for review.

CREATE TRIGGER prevent_double_booking
BEGIN
    IF EXISTS (
        SELECT 1 FROM rides
        WHERE driver_id = NEW.driver_id
          AND ride_time = NEW.ride_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Driver already booked for this time';
    END IF;
END$$
DELIMITER;

-- Auto-flag suspicious rides
DELIMITER $$
CREATE TRIGGER flag_suspicious_ride
AFTER INSERT ON rides
FOR EACH ROW
        INSERT INTO suspicious_rides (ride_id, reason, created_at)
END$$
DELIMITER;


3. E-commerce/Marketplace (e.g., Amazon, Airbnb)
Scenario:

Auto-update product stock and alert on low inventory.
Prevent duplicate bookings.
Dynamic pricing adjustments.
Triggers:

After update on orders, decrement product stock, if stock < threshold, insert alert into notifications.
Before insert on bookings, block if property is already booked for those dates.
After insert/update on reviews, recalculate product/property average rating.
Event:

Every 5 minutes, event to adjust prices based on demand (e.g., if >80% booked, increase price by 10%).

CREATE TRIGGER alert_low_stock
AFTER UPDATE ON products
FOR EACH ROW
BEGIN
    IF NEW.stock < 10 THEN
        INSERT INTO notifications (product_id, message, created_at)
        VALUES (NEW.id, 'Low stock alert', NOW());
    END IF;
END$$
DELIMITER;

-- Scheduled Event: Dynamic Pricing Adjustment

DELIMITER $$
CREATE EVENT adjust_dynamic_pricing
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    UPDATE properties
    SET price = price * 1.10
    WHERE bookings_last_week > 0.8 * total_capacity;
END$$
DELIMITER;

1. Event + Partitioning + Window Functions (E-commerce Flash Sale Cleanup)
Scenario:
Auto-expire the oldest orders in a flash sale table, but only keep the latest N per product (using window functions and partitions).

Event Example:

DELIMITER $$
CREATE EVENT cleanup_flash_sale_orders
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    DELETE FROM flash_sale_orders
    WHERE order_id IN (
        SELECT order_id FROM (
            SELECT order_id,
                   ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY created_at DESC) AS rn
            FROM flash_sale_orders
        ) t
        WHERE t.rn > 100
    );
END$$
DELIMITER ;

-- Why it's advanced:

-- Uses window functions and partitioning logic inside an event for efficient, rolling cleanup.

-- 2. Trigger + Recursive CTE (Transport: Auto-Update Ride Chains)
-- Scenario:

-- When a ride is updated, recursively update all dependent rides (e.g., chained bookings for carpooling).

-- Trigger Example:

DELIMITER $$
CREATE TRIGGER update_ride_chain
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    WITH RECURSIVE ride_chain AS (
        SELECT id, next_ride_id FROM rides WHERE id = NEW.id
        UNION ALL
        SELECT r.id, r.next_ride_id
        FROM rides r
        INNER JOIN ride_chain rc ON r.id = rc.next_ride_id
    )
    UPDATE rides
    SET status = NEW.status
    WHERE id IN (SELECT id FROM ride_chain);
END$$
DELIMITER;

-- Why it's ingenious:

-- Uses a recursive CTE inside a trigger to propagate changes through a chain of related records.


-- 3. Trigger + View + Window Function (Finance: Real-Time Leaderboard)
Scenario:

-- Maintain a real-time leaderboard of top accounts by transaction volume, using a view and a trigger to update a summary table.

-- View Example:

CREATE OR REPLACE VIEW account_leaderboard AS
SELECT account_id,
       SUM(amount) AS total_volume,
       RANK() OVER (ORDER BY SUM(amount) DESC) AS rank
FROM transactions
GROUP BY account_id;

DELIMITER $$
CREATE TRIGGER update_leaderboard
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    REPLACE INTO leaderboard_summary (account_id, total_volume, rank)
    SELECT account_id, total_volume, rank
    FROM account_leaderboard
    WHERE account_id = NEW.account_id;
END$$
DELIMITER ;

-- Why it's patchy/god-mode:

-- Combines a view with a window function and a trigger for near real-time analytics.


-- Scenario: Nightly, aggregate user activity by partition (e.g., region), using CTEs for complex logic, and store in a summary table.

DELIMITER $$
CREATE EVENT aggregate_user_activity
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH region_activity AS (
        SELECT region, COUNT(*) AS activity_count
        FROM user_events
        WHERE event_time >= CURDATE() - INTERVAL 1 DAY
        GROUP BY region
    )
    REPLACE INTO daily_region_activity (region, activity_count, activity_date)
    SELECT region, activity_count, CURDATE() FROM region_activity;
END$$
DELIMITER ;

-- Why it's advanced:

-- Uses CTEs and partitioning logic in an event for efficient, scalable aggregation.


-- 5. Trigger + Partitioned Table + Window Function (Finance: Auto-Archive Old Transactions)

-- Scenario: When a transaction is inserted, if the partition (e.g., month) exceeds a row limit, auto-archive the oldest rows using a window function.


DELIMITER $$
CREATE TRIGGER archive_old_transactions
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DELETE FROM transactions
    WHERE transaction_id IN (
        SELECT transaction_id FROM (
            SELECT transaction_id,
                   ROW_NUMBER() OVER (PARTITION BY YEAR(txn_time), MONTH(txn_time) ORDER BY txn_time ASC) AS rn
            FROM transactions
            WHERE YEAR(txn_time) = YEAR(NEW.txn_time)
              AND MONTH(txn_time) = MONTH(NEW.txn_time)
        ) t
        WHERE t.rn > 100000
    );
END$$
DELIMITER;


-- Why it's god-mode:

-- Keeps partitions lean, auto-archives, and uses window functions for precise control.

-- 46. Trigger + Event + CTE (E-commerce: Auto-Expire Unused Coupons and Notify Users)
-- Scenario: On coupon usage, mark as used. Nightly event finds and expires unused coupons older than 30 days, and notifies users.

DELIMITER $$
CREATE TRIGGER mark_coupon_used
AFTER UPDATE ON coupons
FOR EACH ROW
BEGIN
    IF NEW.used = 1 AND OLD.used = 0 THEN
        UPDATE coupons SET used_at = NOW() WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT expire_unused_coupons
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH expired AS (
        SELECT id, user_id FROM coupons WHERE used = 0 AND created_at < NOW() - INTERVAL 30 DAY
    )
    UPDATE coupons SET status = 'EXPIRED' WHERE id IN (SELECT id FROM expired);
    INSERT INTO notifications (user_id, message, created_at)
    SELECT user_id, 'Your coupon has expired', NOW() FROM expired;
END$$
DELIMITER ;

-- Why it's advanced:
-- Automates coupon lifecycle and user notification with CTEs and events.

-- 47. Trigger + JSON + Error Handling (Finance: Block and Log Suspicious Withdrawals)
-- Scenario: On withdrawal insert, block and log as JSON if amount exceeds daily limit or from flagged country.

DELIMITER $$
CREATE TRIGGER block_and_log_suspicious_withdrawal
BEFORE INSERT ON withdrawals
FOR EACH ROW
BEGIN
    DECLARE total_today DECIMAL(10,2);
    SELECT SUM(amount) INTO total_today FROM withdrawals WHERE user_id = NEW.user_id AND withdrawal_time > CURDATE();
    IF NEW.amount > 5000 OR total_today + NEW.amount > 10000 OR NEW.country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO withdrawal_fraud_log (withdrawal_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.country, 'withdrawal', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Suspicious withdrawal blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Real-time fraud prevention and forensic logging using JSON and error signaling.

-- 48. Event + Partitioning + Analytics (Transport: Auto-Archive Old Trip Data by Region)
-- Scenario: Every month, archive trips older than 1 year by region partition for analytics and cost savings.

DELIMITER $$
DO
    DELETE FROM trips WHERE trip_date < NOW() - INTERVAL 1 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Region-partitioned archiving for scalable analytics and storage efficiency.

-- 49. Trigger + Recursive CTE (SaaS: Auto-Disable Orphaned Subscriptions)
-- Scenario: On user delete, recursively disable all dependent subscriptions and child accounts.

DELIMITER $$
CREATE TRIGGER disable_orphaned_subscriptions
AFTER DELETE ON users
    WITH RECURSIVE orphans AS (
        SELECT id FROM subscriptions WHERE user_id = OLD.id
        UNION ALL
        SELECT s.id FROM subscriptions s
        INNER JOIN orphans o ON s.parent_subscription_id = o.id
    )
    UPDATE subscriptions SET status = 'DISABLED' WHERE id IN (SELECT id FROM orphans);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively disables orphaned subscriptions, ensuring data integrity in multi-level SaaS hierarchies.

-- 50. Event + Dynamic SQL + CTE (E-commerce: Auto-Optimize Product Indexes Based on Query Stats)
-- Scenario: Weekly event analyzes query stats, adds/drops indexes dynamically for hot/cold product columns.

DELIMITER $$
CREATE EVENT optimize_product_indexes
BEGIN
    -- Example: Add index if query count high (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE products ADD INDEX idx_hot (hot_column)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if query count low (pseudo-code)
    -- SET @sql = 'ALTER TABLE products DROP INDEX idx_cold';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates index optimization using query stats, CTEs, and dynamic SQL for peak performance.
-- Scenario: Every week, recursively delete expired promo codes and all their dependent child codes using dynamic SQL.

DELIMITER $$
CREATE EVENT cleanup_expired_promo_codes
BEGIN
    WITH RECURSIVE expired_codes AS (
        SELECT id FROM promo_codes WHERE expires_at < NOW()
        UNION ALL
        SELECT c.id FROM promo_codes c
        INNER JOIN expired_codes e ON c.parent_code_id = e.id
    )
    DELETE FROM promo_codes WHERE id IN (SELECT id FROM expired_codes);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively and automatically cleans up expired and dependent promo codes, keeping the system lean.

-- 44. Trigger + Error Handling + Notification (Transport: Alert on Failed Payment Insert)
-- Scenario: On failed payment insert (e.g., constraint violation), log the error and notify admins instantly.
DELIMITER $$
CREATE TRIGGER log_failed_payment
BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    IF NEW.amount <= 0 THEN
        INSERT INTO payment_errors (user_id, amount, error_msg, created_at)
        VALUES (NEW.user_id, NEW.amount, 'Invalid payment amount', NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid payment amount';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Provides instant error logging and admin notification for payment issues, improving reliability.

-- 45. Event + Cross-Database + Analytics (SaaS: Sync Usage Stats to Analytics DB with Partition Awareness)
-- Scenario: Every hour, sync usage stats to analytics DB, partitioned by month, for BI/reporting.

DELIMITER $$
CREATE EVENT sync_usage_stats_to_analytics
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO analytics_db.usage_stats_partitioned (user_id, usage_count, stat_month, synced_at)
    SELECT user_id, COUNT(*), DATE_FORMAT(NOW(), '%Y-%m'), NOW()
    GROUP BY user_id;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables cross-DB, partition-aware analytics sync for scalable BI/reporting.

DELIMITER $$
CREATE EVENT invalidate_stale_driver_cache
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    DELETE FROM driver_location_cache
    WHERE driver_id IN (
        SELECT id FROM drivers WHERE last_location_update < NOW() - INTERVAL 30 MINUTE
    );
END$$
DELIMITER ;



-- 30. Trigger + Real-Time SLA Enforcement (Transport: Flag Late Rides)
-- Scenario: On ride update, if actual dropoff is later than promised, flag for SLA breach.

DELIMITER $$
CREATE TRIGGER flag_sla_breach
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    IF NEW.dropoff_time > NEW.promised_dropoff_time AND OLD.dropoff_time <= OLD.promised_dropoff_time THEN
        UPDATE rides SET sla_breached = 1 WHERE id = NEW.id;
        INSERT INTO sla_breach_log (ride_id, breached_at)
        VALUES (NEW.id, NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enforces SLAs in real-time, enabling proactive customer support and analytics.

-- 31. Event + Data Masking (Finance: Mask Sensitive Data for Analytics)
-- Scenario: Every night, mask PII in analytics tables while keeping raw data in production.

DELIMITER $$
CREATE EVENT mask_analytics_pii
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE analytics.transactions
    SET card_number = CONCAT('XXXX-XXXX-XXXX-', RIGHT(card_number, 4)),
        user_email = CONCAT(LEFT(user_email, 2), '***@***.com');
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures analytics teams never see raw PII, reducing compliance risk.

-- 32. Event + Dynamic Index Management (E-commerce: Auto-Add/Drop Indexes Based on Usage)
-- Scenario: Every week, analyze slow queries and auto-add/drop indexes for hot/cold columns.

DELIMITER $$
CREATE EVENT dynamic_index_management
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    -- Example: Add index if slow queries detected (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE orders ADD INDEX idx_status (status)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if unused (pseudo-code)
    -- SET @sql = 'ALTER TABLE orders DROP INDEX idx_old_unused';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's advanced:

-- 33. Event + Archiving (E-commerce: Move Old Orders to Archive Table)
-- Scenario: Every month, move orders older than 2 years to an archive table for cost savings and performance.

DELIMITER $$
CREATE EVENT archive_old_orders
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    INSERT INTO orders_archive SELECT * FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
    DELETE FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Keeps operational tables lean and fast, while preserving history for compliance.

-- 34. Trigger + Real-Time Escalation (Transport: Escalate Unassigned Rides)
-- Scenario: On ride insert, if not assigned to a driver within 2 minutes, auto-escalate to human dispatcher.

DELIMITER $$
CREATE TRIGGER escalate_unassigned_ride
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    IF NEW.driver_id IS NULL THEN
        INSERT INTO ride_escalations (ride_id, escalated_at)
        VALUES (NEW.id, NOW() + INTERVAL 2 MINUTE);
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures no ride is left unassigned, improving customer experience and reducing cancellations.

-- 35. Event + Adaptive Sharding (Finance: Rebalance Accounts Across Shards)
-- Scenario: Every week, move accounts with high activity to dedicated shards for load balancing.

DELIMITER $$
CREATE EVENT rebalance_account_shards
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    INSERT INTO accounts_hot_shard SELECT * FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
    DELETE FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
END$$
DELIMITER ;

-- Why it's advanced:
-- Dynamically rebalances hot accounts for optimal performance at scale.
DELIMITER $$
CREATE EVENT detect_transaction_spikes
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO anomaly_alerts (account_id, alert_type, detected_at)
    SELECT t.account_id, 'spike', NOW()
    FROM (
        SELECT account_id,
               COUNT(*) AS txn_count,
               (SELECT AVG(cnt) FROM (
                   SELECT COUNT(*) AS cnt FROM transactions
                   WHERE account_id = transactions.account_id
                   AND txn_time > NOW() - INTERVAL 7 DAY
                   GROUP BY DATE(txn_time)
               ) x) AS avg_daily
        FROM transactions
        WHERE txn_time > NOW() - INTERVAL 1 DAY
        GROUP BY account_id
    ) t
    WHERE t.txn_count > 5 * t.avg_daily;
END$$
DELIMITER ;


-- 36. Trigger + Event + Recursive CTE (SaaS: Automated Subscription Expiry and Grace Period Handling)
-- Scenario: On subscription expiry, auto-move user to grace period, and nightly event purges expired grace users recursively (including dependents).

DELIMITER $$
CREATE TRIGGER move_to_grace_period
AFTER UPDATE ON subscriptions
FOR EACH ROW
BEGIN
    IF NEW.status = 'EXPIRED' AND OLD.status != 'EXPIRED' THEN
        UPDATE users SET status = 'GRACE' WHERE id = NEW.user_id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT purge_expired_grace_users
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE expired_users AS (
        SELECT id FROM users WHERE status = 'GRACE' AND updated_at < NOW() - INTERVAL 14 DAY
        UNION ALL
        SELECT u.id FROM users u
        INNER JOIN expired_users e ON u.parent_id = e.id
    )
    DELETE FROM users WHERE id IN (SELECT id FROM expired_users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Combines triggers, events, and recursive CTEs for automated, multi-level subscription lifecycle management.

-- 37. Trigger + JSON + Error Handling (E-commerce: Real-Time Fraud Pattern Logging)
-- Scenario: On suspicious order insert, log full order as JSON in a fraud log table and block the insert.

DELIMITER $$
CREATE TRIGGER log_and_block_fraud_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.amount > 10000 OR NEW.shipping_country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO fraud_orders_log (order_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.shipping_country, 'order', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fraudulent order blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Instantly blocks and logs suspicious orders with full context for forensics, using JSON and custom error signaling.

-- 38. Event + Cross-Table Consistency (Transport: Auto-Heal Broken Foreign Keys)
-- Scenario: Every hour, scan for rides referencing missing drivers or users, and auto-fix or log for manual review.

DELIMITER $$
CREATE EVENT heal_broken_ride_fks
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    -- Log rides with missing drivers
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_driver', NOW() FROM rides WHERE driver_id NOT IN (SELECT id FROM drivers);
    -- Log rides with missing users
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_user', NOW() FROM rides WHERE user_id NOT IN (SELECT id FROM users);
    -- Optionally, set driver_id/user_id to NULL or a default value for orphaned rides
    UPDATE rides SET driver_id = NULL WHERE driver_id NOT IN (SELECT id FROM drivers);
    UPDATE rides SET user_id = NULL WHERE user_id NOT IN (SELECT id FROM users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Proactively detects and heals referential integrity issues, reducing data corruption risk at scale.

-- 39. Trigger + Partitioned Table + Dynamic SQL (Finance: Auto-Move Large Transactions to Audit Partition)
-- Scenario: On large transaction insert, move it to a special audit partition using dynamic SQL.

DELIMITER $$
CREATE TRIGGER move_large_txn_to_audit
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount > 50000 THEN
        SET @sql = CONCAT('INSERT INTO transactions_audit PARTITION (p', DATE_FORMAT(NOW(), '%Y%m'), ') SELECT * FROM transactions WHERE id = ', NEW.id, ';');
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        DELETE FROM transactions WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Uses dynamic SQL in a trigger to move sensitive data to a secure, partitioned audit table in real-time.

-- 40. Event + Predictive Analytics (E-commerce: Auto-Flag Products for Restock Based on ML Score)
-- Scenario: Every night, flag products for restock if ML-predicted demand score is high, using a precomputed ML table.

DELIMITER $$
CREATE EVENT flag_products_for_restock
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE products p
    JOIN product_demand_ml ml ON p.id = ml.product_id
    SET p.restock_flag = 1
    WHERE ml.predicted_demand > 0.8 AND p.stock < 20;
END$$
DELIMITER ;

-- Why it's advanced:
-- Integrates ML predictions into operational DB logic for proactive inventory management.

-- 22. Trigger + Multi-Tenant Data Isolation (SaaS: Enforce Tenant Boundaries)
-- Scenario: On insert/update, block cross-tenant data access by checking tenant_id.

DELIMITER $$
CREATE TRIGGER enforce_tenant_isolation
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF (SELECT tenant_id FROM users WHERE id = NEW.user_id) != NEW.tenant_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tenant data isolation violation';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enforces strict multi-tenant boundaries at the DB layer, preventing data leaks.


DELIMITER $$
CREATE EVENT enforce_sanctions
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE accounts
    SET status = 'FROZEN'
    WHERE id IN (
        SELECT DISTINCT account_id FROM transactions
        WHERE counterparty_id IN (SELECT entity_id FROM sanctioned_entities)
          AND txn_time > NOW() - INTERVAL 1 HOUR
    );
END$$
DELIMITER ;



-- 24. Trigger + Real-Time Deduplication (E-commerce: Prevent Duplicate Orders)
-- Scenario: On order insert, block if a similar order exists for the same user/product in the last 5 minutes.

DELIMITER $$
CREATE TRIGGER prevent_duplicate_orders
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM orders
        WHERE user_id = NEW.user_id
          AND product_id = NEW.product_id
          AND created_at > NOW() - INTERVAL 5 MINUTE
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate order detected';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time deduplication at the DB layer, preventing accidental or malicious double orders.

-- 25. Event + GDPR/PII Scrubbing (Compliance: Auto-Redact Old User Data)
-- Scenario: Every day, redact PII for users inactive for 3+ years, for GDPR compliance.

DELIMITER $$
CREATE EVENT redact_old_user_data
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE users
    SET email = NULL, phone = NULL, address = NULL
    WHERE last_active < NOW() - INTERVAL 3 YEAR;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates privacy compliance and reduces risk of data leaks.

-- 26. Trigger + Predictive Maintenance (Transport: Flag Vehicles for Service)
-- Scenario: On ride insert, if vehicle mileage exceeds threshold, flag for maintenance.

DELIMITER $$
CREATE TRIGGER flag_vehicle_maintenance
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE mileage INT;
    SELECT odometer INTO mileage FROM vehicles WHERE id = NEW.vehicle_id;
    IF mileage > 100000 THEN
        UPDATE vehicles SET needs_service = 1 WHERE id = NEW.vehicle_id;
        INSERT INTO maintenance_alerts (vehicle_id, alert_type, created_at)
        VALUES (NEW.vehicle_id, 'Mileage threshold exceeded', NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables predictive maintenance and reduces downtime, all in-SQL.

-- 11. Trigger + Error Handling + Notification (Finance: Alert on Failed Transaction Insert)
-- Scenario: If a transaction insert fails due to constraint violation, log the error and notify admins instantly.

-- Note: MySQL triggers cannot catch errors from the same statement that fires them, but you can use AFTER statements for logging or use SIGNAL for custom error handling.

-- 12. Event + Cross-Database Sync (E-commerce: Sync Inventory to Analytics DB)
-- Scenario: Every 10 minutes, sync new/updated inventory rows to a reporting/analytics database.

DELIMITER $$
CREATE EVENT sync_inventory_to_analytics
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO analytics_db.inventory_snapshot (product_id, stock, updated_at)
    SELECT id, stock, updated_at FROM main_db.products
    WHERE updated_at > NOW() - INTERVAL 10 MINUTE;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables near real-time cross-DB sync for analytics, without ETL pipeline overhead.

-- 13. Trigger + Time-Travel Auditing (Transport: Immutable Ride History)
-- Scenario: On any update to rides, store the old row in a history table for time-travel queries.

DELIMITER $$
CREATE TRIGGER audit_ride_history
BEFORE UPDATE ON rides
FOR EACH ROW
BEGIN
    INSERT INTO rides_history (ride_id, driver_id, user_id, status, fare, ride_time, archived_at)
    VALUES (OLD.id, OLD.driver_id, OLD.user_id, OLD.status, OLD.fare, OLD.ride_time, NOW());
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables time-travel queries and forensic analysis, critical for compliance and debugging.

-- 14. Event + Partition Management (Finance: Auto-Create Monthly Partitions)
-- Scenario: At the start of each month, auto-create a new partition for the transactions table.

DELIMITER $$
CREATE EVENT create_monthly_partition
ON SCHEDULE EVERY 1 MONTH STARTS '2025-08-01 00:00:00'
DO
BEGIN
    SET @sql = CONCAT('ALTER TABLE transactions ADD PARTITION (PARTITION p', DATE_FORMAT(NOW(), '%Y%m'), ' VALUES LESS THAN (TO_DAYS("', DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01'), '")))');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates partition management, keeping large tables performant with zero manual intervention.

-- 15. Trigger + Window Function + JSON (E-commerce: Real-Time Cart Abandonment Scoring)
-- Scenario: On cart update, calculate abandonment risk score using window function and store as JSON for ML/BI.

DELIMITER $$
CREATE TRIGGER score_cart_abandonment
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    DECLARE score_json JSON;
    SET score_json = (
        SELECT JSON_OBJECT('cart_id', NEW.id, 'risk_score',
            CASE WHEN COUNT(*) OVER (PARTITION BY user_id ORDER BY last_updated DESC) > 3 THEN 0.9 ELSE 0.2 END)
        FROM carts WHERE user_id = NEW.user_id AND last_updated > NOW() - INTERVAL 1 DAY LIMIT 1
    );
    UPDATE carts SET abandonment_score = score_json WHERE id = NEW.id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time, ML-ready scoring for cart abandonment, directly in the DB.

-- 6. Trigger + JSON + Window Function (Transport: Real-Time Surge Pricing by Zone)
-- Scenario: When a ride is inserted, recalculate surge multiplier for the zone using window function and store in a JSON column for analytics.

DELIMITER $$
CREATE TRIGGER update_surge_multiplier
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE surge JSON;
    SET surge = (
        SELECT JSON_OBJECT('zone', NEW.zone, 'multiplier',
            CASE WHEN COUNT(*) OVER (PARTITION BY zone ORDER BY ride_time RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING AND CURRENT ROW) > 50
                 THEN 1.5 ELSE 1.0 END)
        FROM rides WHERE zone = NEW.zone AND ride_time > NOW() - INTERVAL 10 MINUTE LIMIT 1
    );
    UPDATE zones SET surge_info = surge WHERE name = NEW.zone;
END$$
DELIMITER ;

-- Why it's advanced:
-- Uses window function and JSON for real-time, zone-based surge pricing analytics.

-- 7. Event + Recursive CTE + Partitioning (E-commerce: Clean Orphaned Categories)
-- Scenario: Nightly, recursively find and delete categories with no products, including all subcategories (using recursive CTE).

DELIMITER $$
CREATE EVENT cleanup_orphaned_categories
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE orphaned AS (
        SELECT id FROM categories WHERE id NOT IN (SELECT DISTINCT category_id FROM products)
        UNION ALL
        SELECT c.id FROM categories c
        INNER JOIN orphaned o ON c.parent_id = o.id
    )
    DELETE FROM categories WHERE id IN (SELECT id FROM orphaned);
END$$
DELIMITER ;

-- Why it's god-mode:
-- Recursively cleans up orphaned and nested categories, keeping taxonomy lean.

-- 8. Trigger + View + Partitioned Table (Finance: Real-Time Compliance Snapshot)
-- Scenario: After any transaction, update a compliance snapshot view and partitioned table for regulatory reporting.

CREATE OR REPLACE VIEW compliance_snapshot AS
SELECT account_id, SUM(amount) AS total, MAX(txn_time) AS last_txn
FROM transactions
GROUP BY account_id;

DELIMITER $$
CREATE TRIGGER update_compliance_partition
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    REPLACE INTO compliance_partitions (account_id, total, last_txn, partition_month)
    SELECT account_id, total, last_txn, DATE_FORMAT(NOW(), '%Y-%m')
    FROM compliance_snapshot WHERE account_id = NEW.account_id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Maintains regulatory snapshots in real-time, partitioned by month, using a view and trigger.

-- 9. Event + Window Function + JSON (Transport: Hourly Driver Utilization Analytics)
-- Scenario: Every hour, aggregate driver utilization stats using window functions and store as JSON for BI tools.

DELIMITER $$
CREATE EVENT hourly_driver_utilization
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO driver_utilization_analytics (driver_id, stats_json, created_at)
    SELECT driver_id,
           JSON_OBJECT('rides', COUNT(*), 'avg_rating', AVG(rating), 'rank', RANK() OVER (ORDER BY COUNT(*) DESC)),
           NOW()
    FROM rides
    WHERE ride_time > NOW() - INTERVAL 1 HOUR
    GROUP BY driver_id;
END$$
DELIMITER ;

-- Why it's ingenious:
-- Combines window functions, aggregation, and JSON for BI-ready analytics, all in an event.

-- 10. Trigger + Partitioned Table + Recursive CTE (E-commerce: Auto-Expire Stale Carts)
-- Scenario: When a cart is updated, recursively expire all items in the cart and sub-carts if last updated > 24h ago, using partitioning and recursive CTE.

DELIMITER $$
CREATE TRIGGER expire_stale_carts
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    WITH RECURSIVE stale_carts AS (
        SELECT id FROM carts WHERE id = NEW.id AND last_updated < NOW() - INTERVAL 24 HOUR
        UNION ALL
        SELECT c.id FROM carts c
        INNER JOIN stale_carts sc ON c.parent_cart_id = sc.id
    )
    UPDATE carts SET status = 'EXPIRED' WHERE id IN (SELECT id FROM stale_carts);
END$$
DELIMITER ;

-- Why it's god-mode:
-- Recursively expires stale carts and all their sub-carts, keeping the system clean and fast.

    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    salary DECIMAL(10,2) NOT NULL,
    designation VARCHAR(50) NOT NULL,
    dept_id VARCHAR(50) NOT NULL
);

-- Insert sample data
INSERT INTO employee_salary (first_name, last_name, salary, designation, dept_id) VALUES
('John', 'Doe', 75000.00, 'Software Engineer', 'Development'),
('Jane', 'Smith', 82000.00, 'Senior Developer', 'Development'),
('Alice', 'Johnson', 65000.00, 'QA Analyst', 'Quality Assurance'),
('Bob', 'Williams', 90000.00, 'Team Lead', 'Development'),
('Eve', 'Davis', 70000.00, 'Business Analyst', 'Business Intelligence'),
('Charlie', 'Brown', 68000.00, 'Support Engineer', 'Support'),
('Grace', 'Lee', 78000.00, 'UI/UX Designer', 'Design'),
-- Create table employee_demographics
CREATE TABLE employee_demographics (
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    dob DATE NOT NULL,
    gender ENUM('M', 'F', 'O') NOT NULL
);

-- Insert sample data for employee_demographics
INSERT INTO employee_demographics (employee_id, age, first_name, last_name, dob, gender) VALUES
(1, 28, 'John', 'Doe', '1997-03-15', 'M'),
(2, 32, 'Jane', 'Smith', '1993-11-22', 'F'),
(3, 26, 'Alice', 'Johnson', '1999-07-09', 'F'),
(4, 35, 'Bob', 'Williams', '1990-01-30', 'M'),
(7, 38, 'Diana', 'Evans', '1987-12-03', 'F'),
(10, 33, 'Henry', 'Clark', '1992-02-28', 'M');

-- Requirement: Mus update employee_demographics when a new employee is added to the employee_salary table

-- SOLUTION: Create a trigger to automatically insert into employee_demographics when a new employee is added to employee_salary

-- DELIMITER $$ helps to run multiple queries in a single execution block 
DELIMITER $$

CREATE TRIGGER after_employee_insert
AFTER INSERT ON employee_salary
FOR EACH ROW
BEGIN
    INSERT INTO employee_demographics (employee_id, first_name, last_name) VALUES (NEW.employee_id, NEW.first_name, NEW.last_name);
 END$$  

-- EVENTS: 

-- In MySQL, use events when you need to schedule and automate tasks to run at specific times or intervals, similar to cron jobs in Unix. Events are useful for:

-- Periodic data cleanup (e.g., deleting old records every night)
-- Regular backups or archiving
-- Automatically updating summary tables or statistics
-- Sending scheduled notifications or reports
-- Resetting counters or temporary data at set intervals
-- Events are best for time-based, recurring, or one-off scheduled operations that do not depend on a specific data change (unlike triggers, which react to table modifications).

-- If any row where age >= 60, then it will be automatically deleted from employee_demographics table
CREATE EVENT delete_retired_employees
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    DELETE FROM employee_demographics WHERE age > 60;
END;
-- This event will run every month and delete any employee from the employee_demographics table whose age is greater than or equal to 60.
DELIMITER;

SHOW VARIABLES LIKE 'event%;

-- 1. Finance (e.g., Amazon Payments)

-- Scenario:

-- Prevent negative balances on transactions.

Before updating account balance, block if result < 0.
After any update/delete on transactions, log old/new values to an audit table.
After insert on transactions, if amount > $10,000 or from flagged country, auto-flag account.

Event:

Nightly event to scan for accounts with >3 failed logins in 24h, auto-lock and notify security.

-- Block negative balances & Audit changes

-- Block negative balances
BEFORE UPDATE ON accounts
    IF NEW.balance < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Negative balance not allowed';
    END IF;
END$$
DELIMITER;

-- Audit changes
DELIMITER $$
CREATE TRIGGER audit_transactions
AFTER UPDATE ON transactions
FOR EACH ROW
    VALUES (OLD.id, OLD.amount, NEW.amount, NOW());

2. Transport/Logistics (e.g., Uber)
Scenario:

Auto-calculate driver ratings and bonuses.
Prevent double-booking of drivers.
Track suspicious ride patterns.
Triggers:

After insert on rides, update driver’s average rating and bonus eligibility.
Before insert on rides, block if driver is already assigned to another ride at the same time.
After insert on rides, if pickup/dropoff locations are the same, log for fraud review.
Event:

Every hour, event to find drivers with >10 rides in 1 hour (possible bot), flag for review.

CREATE TRIGGER prevent_double_booking
BEGIN
    IF EXISTS (
        SELECT 1 FROM rides
        WHERE driver_id = NEW.driver_id
          AND ride_time = NEW.ride_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Driver already booked for this time';
    END IF;
END$$
DELIMITER;

-- Auto-flag suspicious rides
DELIMITER $$
CREATE TRIGGER flag_suspicious_ride
AFTER INSERT ON rides
FOR EACH ROW
        INSERT INTO suspicious_rides (ride_id, reason, created_at)
END$$
DELIMITER;


3. E-commerce/Marketplace (e.g., Amazon, Airbnb)
Scenario:

Auto-update product stock and alert on low inventory.
Prevent duplicate bookings.
Dynamic pricing adjustments.
Triggers:

After update on orders, decrement product stock, if stock < threshold, insert alert into notifications.
Before insert on bookings, block if property is already booked for those dates.
After insert/update on reviews, recalculate product/property average rating.
Event:

Every 5 minutes, event to adjust prices based on demand (e.g., if >80% booked, increase price by 10%).

CREATE TRIGGER alert_low_stock
AFTER UPDATE ON products
FOR EACH ROW
BEGIN
    IF NEW.stock < 10 THEN
        INSERT INTO notifications (product_id, message, created_at)
        VALUES (NEW.id, 'Low stock alert', NOW());
    END IF;
END$$
DELIMITER;

-- Scheduled Event: Dynamic Pricing Adjustment

DELIMITER $$
CREATE EVENT adjust_dynamic_pricing
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    UPDATE properties
    SET price = price * 1.10
    WHERE bookings_last_week > 0.8 * total_capacity;
END$$
DELIMITER;

1. Event + Partitioning + Window Functions (E-commerce Flash Sale Cleanup)
Scenario:
Auto-expire the oldest orders in a flash sale table, but only keep the latest N per product (using window functions and partitions).

Event Example:

DELIMITER $$
CREATE EVENT cleanup_flash_sale_orders
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    DELETE FROM flash_sale_orders
    WHERE order_id IN (
        SELECT order_id FROM (
            SELECT order_id,
                   ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY created_at DESC) AS rn
            FROM flash_sale_orders
        ) t
        WHERE t.rn > 100
    );
END$$
DELIMITER ;

-- Why it's advanced:

-- Uses window functions and partitioning logic inside an event for efficient, rolling cleanup.

-- 2. Trigger + Recursive CTE (Transport: Auto-Update Ride Chains)
-- Scenario:

-- When a ride is updated, recursively update all dependent rides (e.g., chained bookings for carpooling).

-- Trigger Example:

DELIMITER $$
CREATE TRIGGER update_ride_chain
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    WITH RECURSIVE ride_chain AS (
        SELECT id, next_ride_id FROM rides WHERE id = NEW.id
        UNION ALL
        SELECT r.id, r.next_ride_id
        FROM rides r
        INNER JOIN ride_chain rc ON r.id = rc.next_ride_id
    )
    UPDATE rides
    SET status = NEW.status
    WHERE id IN (SELECT id FROM ride_chain);
END$$
DELIMITER;

-- Why it's ingenious:

-- Uses a recursive CTE inside a trigger to propagate changes through a chain of related records.


-- 3. Trigger + View + Window Function (Finance: Real-Time Leaderboard)
Scenario:

-- Maintain a real-time leaderboard of top accounts by transaction volume, using a view and a trigger to update a summary table.

-- View Example:

CREATE OR REPLACE VIEW account_leaderboard AS
SELECT account_id,
       SUM(amount) AS total_volume,
       RANK() OVER (ORDER BY SUM(amount) DESC) AS rank
FROM transactions
GROUP BY account_id;

DELIMITER $$
CREATE TRIGGER update_leaderboard
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    REPLACE INTO leaderboard_summary (account_id, total_volume, rank)
    SELECT account_id, total_volume, rank
    FROM account_leaderboard
    WHERE account_id = NEW.account_id;
END$$
DELIMITER ;

-- Why it's patchy/god-mode:

-- Combines a view with a window function and a trigger for near real-time analytics.


-- Scenario: Nightly, aggregate user activity by partition (e.g., region), using CTEs for complex logic, and store in a summary table.

DELIMITER $$
CREATE EVENT aggregate_user_activity
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH region_activity AS (
        SELECT region, COUNT(*) AS activity_count
        FROM user_events
        WHERE event_time >= CURDATE() - INTERVAL 1 DAY
        GROUP BY region
    )
    REPLACE INTO daily_region_activity (region, activity_count, activity_date)
    SELECT region, activity_count, CURDATE() FROM region_activity;
END$$
DELIMITER ;

-- Why it's advanced:

-- Uses CTEs and partitioning logic in an event for efficient, scalable aggregation.


-- 5. Trigger + Partitioned Table + Window Function (Finance: Auto-Archive Old Transactions)

-- Scenario: When a transaction is inserted, if the partition (e.g., month) exceeds a row limit, auto-archive the oldest rows using a window function.


DELIMITER $$
CREATE TRIGGER archive_old_transactions
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DELETE FROM transactions
    WHERE transaction_id IN (
        SELECT transaction_id FROM (
            SELECT transaction_id,
                   ROW_NUMBER() OVER (PARTITION BY YEAR(txn_time), MONTH(txn_time) ORDER BY txn_time ASC) AS rn
            FROM transactions
            WHERE YEAR(txn_time) = YEAR(NEW.txn_time)
              AND MONTH(txn_time) = MONTH(NEW.txn_time)
        ) t
        WHERE t.rn > 100000
    );
END$$
DELIMITER;


-- Why it's god-mode:

-- Keeps partitions lean, auto-archives, and uses window functions for precise control.

-- 46. Trigger + Event + CTE (E-commerce: Auto-Expire Unused Coupons and Notify Users)
-- Scenario: On coupon usage, mark as used. Nightly event finds and expires unused coupons older than 30 days, and notifies users.

DELIMITER $$
CREATE TRIGGER mark_coupon_used
AFTER UPDATE ON coupons
FOR EACH ROW
BEGIN
    IF NEW.used = 1 AND OLD.used = 0 THEN
        UPDATE coupons SET used_at = NOW() WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT expire_unused_coupons
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH expired AS (
        SELECT id, user_id FROM coupons WHERE used = 0 AND created_at < NOW() - INTERVAL 30 DAY
    )
    UPDATE coupons SET status = 'EXPIRED' WHERE id IN (SELECT id FROM expired);
    INSERT INTO notifications (user_id, message, created_at)
    SELECT user_id, 'Your coupon has expired', NOW() FROM expired;
END$$
DELIMITER ;

-- Why it's advanced:
-- Automates coupon lifecycle and user notification with CTEs and events.

-- 47. Trigger + JSON + Error Handling (Finance: Block and Log Suspicious Withdrawals)
-- Scenario: On withdrawal insert, block and log as JSON if amount exceeds daily limit or from flagged country.

DELIMITER $$
CREATE TRIGGER block_and_log_suspicious_withdrawal
BEFORE INSERT ON withdrawals
FOR EACH ROW
BEGIN
    DECLARE total_today DECIMAL(10,2);
    SELECT SUM(amount) INTO total_today FROM withdrawals WHERE user_id = NEW.user_id AND withdrawal_time > CURDATE();
    IF NEW.amount > 5000 OR total_today + NEW.amount > 10000 OR NEW.country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO withdrawal_fraud_log (withdrawal_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.country, 'withdrawal', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Suspicious withdrawal blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Real-time fraud prevention and forensic logging using JSON and error signaling.

-- 48. Event + Partitioning + Analytics (Transport: Auto-Archive Old Trip Data by Region)
-- Scenario: Every month, archive trips older than 1 year by region partition for analytics and cost savings.

DELIMITER $$
DO
    DELETE FROM trips WHERE trip_date < NOW() - INTERVAL 1 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Region-partitioned archiving for scalable analytics and storage efficiency.

-- 49. Trigger + Recursive CTE (SaaS: Auto-Disable Orphaned Subscriptions)
-- Scenario: On user delete, recursively disable all dependent subscriptions and child accounts.

DELIMITER $$
CREATE TRIGGER disable_orphaned_subscriptions
AFTER DELETE ON users
    WITH RECURSIVE orphans AS (
        SELECT id FROM subscriptions WHERE user_id = OLD.id
        UNION ALL
        SELECT s.id FROM subscriptions s
        INNER JOIN orphans o ON s.parent_subscription_id = o.id
    )
    UPDATE subscriptions SET status = 'DISABLED' WHERE id IN (SELECT id FROM orphans);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively disables orphaned subscriptions, ensuring data integrity in multi-level SaaS hierarchies.

-- 50. Event + Dynamic SQL + CTE (E-commerce: Auto-Optimize Product Indexes Based on Query Stats)
-- Scenario: Weekly event analyzes query stats, adds/drops indexes dynamically for hot/cold product columns.

DELIMITER $$
CREATE EVENT optimize_product_indexes
BEGIN
    -- Example: Add index if query count high (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE products ADD INDEX idx_hot (hot_column)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if query count low (pseudo-code)
    -- SET @sql = 'ALTER TABLE products DROP INDEX idx_cold';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates index optimization using query stats, CTEs, and dynamic SQL for peak performance.
-- Scenario: Every week, recursively delete expired promo codes and all their dependent child codes using dynamic SQL.

DELIMITER $$
CREATE EVENT cleanup_expired_promo_codes
BEGIN
    WITH RECURSIVE expired_codes AS (
        SELECT id FROM promo_codes WHERE expires_at < NOW()
        UNION ALL
        SELECT c.id FROM promo_codes c
        INNER JOIN expired_codes e ON c.parent_code_id = e.id
    )
    DELETE FROM promo_codes WHERE id IN (SELECT id FROM expired_codes);
END$$
DELIMITER ;

-- Why it's advanced:
-- Recursively and automatically cleans up expired and dependent promo codes, keeping the system lean.

-- 44. Trigger + Error Handling + Notification (Transport: Alert on Failed Payment Insert)
-- Scenario: On failed payment insert (e.g., constraint violation), log the error and notify admins instantly.
DELIMITER $$
CREATE TRIGGER log_failed_payment
BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    IF NEW.amount <= 0 THEN
        INSERT INTO payment_errors (user_id, amount, error_msg, created_at)
        VALUES (NEW.user_id, NEW.amount, 'Invalid payment amount', NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid payment amount';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Provides instant error logging and admin notification for payment issues, improving reliability.

-- 45. Event + Cross-Database + Analytics (SaaS: Sync Usage Stats to Analytics DB with Partition Awareness)
-- Scenario: Every hour, sync usage stats to analytics DB, partitioned by month, for BI/reporting.

DELIMITER $$
CREATE EVENT sync_usage_stats_to_analytics
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO analytics_db.usage_stats_partitioned (user_id, usage_count, stat_month, synced_at)
    SELECT user_id, COUNT(*), DATE_FORMAT(NOW(), '%Y-%m'), NOW()
    GROUP BY user_id;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables cross-DB, partition-aware analytics sync for scalable BI/reporting.

DELIMITER $$
CREATE EVENT invalidate_stale_driver_cache
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    DELETE FROM driver_location_cache
    WHERE driver_id IN (
        SELECT id FROM drivers WHERE last_location_update < NOW() - INTERVAL 30 MINUTE
    );
END$$
DELIMITER ;



-- 30. Trigger + Real-Time SLA Enforcement (Transport: Flag Late Rides)
-- Scenario: On ride update, if actual dropoff is later than promised, flag for SLA breach.

DELIMITER $$
CREATE TRIGGER flag_sla_breach
AFTER UPDATE ON rides
FOR EACH ROW
BEGIN
    IF NEW.dropoff_time > NEW.promised_dropoff_time AND OLD.dropoff_time <= OLD.promised_dropoff_time THEN
        UPDATE rides SET sla_breached = 1 WHERE id = NEW.id;
        INSERT INTO sla_breach_log (ride_id, breached_at)
        VALUES (NEW.id, NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enforces SLAs in real-time, enabling proactive customer support and analytics.

-- 31. Event + Data Masking (Finance: Mask Sensitive Data for Analytics)
-- Scenario: Every night, mask PII in analytics tables while keeping raw data in production.

DELIMITER $$
CREATE EVENT mask_analytics_pii
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE analytics.transactions
    SET card_number = CONCAT('XXXX-XXXX-XXXX-', RIGHT(card_number, 4)),
        user_email = CONCAT(LEFT(user_email, 2), '***@***.com');
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures analytics teams never see raw PII, reducing compliance risk.

-- 32. Event + Dynamic Index Management (E-commerce: Auto-Add/Drop Indexes Based on Usage)
-- Scenario: Every week, analyze slow queries and auto-add/drop indexes for hot/cold columns.

DELIMITER $$
CREATE EVENT dynamic_index_management
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    -- Example: Add index if slow queries detected (pseudo-code, requires query log analysis)
    -- SET @sql = 'ALTER TABLE orders ADD INDEX idx_status (status)';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    -- Example: Drop index if unused (pseudo-code)
    -- SET @sql = 'ALTER TABLE orders DROP INDEX idx_old_unused';
    -- PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's advanced:

-- 33. Event + Archiving (E-commerce: Move Old Orders to Archive Table)
-- Scenario: Every month, move orders older than 2 years to an archive table for cost savings and performance.

DELIMITER $$
CREATE EVENT archive_old_orders
ON SCHEDULE EVERY 1 MONTH
DO
BEGIN
    INSERT INTO orders_archive SELECT * FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
    DELETE FROM orders WHERE created_at < NOW() - INTERVAL 2 YEAR;
END$$
DELIMITER ;

-- Why it's advanced:
-- Keeps operational tables lean and fast, while preserving history for compliance.

-- 34. Trigger + Real-Time Escalation (Transport: Escalate Unassigned Rides)
-- Scenario: On ride insert, if not assigned to a driver within 2 minutes, auto-escalate to human dispatcher.

DELIMITER $$
CREATE TRIGGER escalate_unassigned_ride
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    IF NEW.driver_id IS NULL THEN
        INSERT INTO ride_escalations (ride_id, escalated_at)
        VALUES (NEW.id, NOW() + INTERVAL 2 MINUTE);
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Ensures no ride is left unassigned, improving customer experience and reducing cancellations.

-- 35. Event + Adaptive Sharding (Finance: Rebalance Accounts Across Shards)
-- Scenario: Every week, move accounts with high activity to dedicated shards for load balancing.

DELIMITER $$
CREATE EVENT rebalance_account_shards
ON SCHEDULE EVERY 1 WEEK
DO
BEGIN
    INSERT INTO accounts_hot_shard SELECT * FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
    DELETE FROM accounts WHERE last_activity > NOW() - INTERVAL 1 WEEK AND activity_score > 1000;
END$$
DELIMITER ;

-- Why it's advanced:
-- Dynamically rebalances hot accounts for optimal performance at scale.
DELIMITER $$
CREATE EVENT detect_transaction_spikes
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO anomaly_alerts (account_id, alert_type, detected_at)
    SELECT t.account_id, 'spike', NOW()
    FROM (
        SELECT account_id,
               COUNT(*) AS txn_count,
               (SELECT AVG(cnt) FROM (
                   SELECT COUNT(*) AS cnt FROM transactions
                   WHERE account_id = transactions.account_id
                   AND txn_time > NOW() - INTERVAL 7 DAY
                   GROUP BY DATE(txn_time)
               ) x) AS avg_daily
        FROM transactions
        WHERE txn_time > NOW() - INTERVAL 1 DAY
        GROUP BY account_id
    ) t
    WHERE t.txn_count > 5 * t.avg_daily;
END$$
DELIMITER ;


-- 36. Trigger + Event + Recursive CTE (SaaS: Automated Subscription Expiry and Grace Period Handling)
-- Scenario: On subscription expiry, auto-move user to grace period, and nightly event purges expired grace users recursively (including dependents).

DELIMITER $$
CREATE TRIGGER move_to_grace_period
AFTER UPDATE ON subscriptions
FOR EACH ROW
BEGIN
    IF NEW.status = 'EXPIRED' AND OLD.status != 'EXPIRED' THEN
        UPDATE users SET status = 'GRACE' WHERE id = NEW.user_id;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT purge_expired_grace_users
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    WITH RECURSIVE expired_users AS (
        SELECT id FROM users WHERE status = 'GRACE' AND updated_at < NOW() - INTERVAL 14 DAY
        UNION ALL
        SELECT u.id FROM users u
        INNER JOIN expired_users e ON u.parent_id = e.id
    )
    DELETE FROM users WHERE id IN (SELECT id FROM expired_users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Combines triggers, events, and recursive CTEs for automated, multi-level subscription lifecycle management.

-- 37. Trigger + JSON + Error Handling (E-commerce: Real-Time Fraud Pattern Logging)
-- Scenario: On suspicious order insert, log full order as JSON in a fraud log table and block the insert.

DELIMITER $$
CREATE TRIGGER log_and_block_fraud_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.amount > 10000 OR NEW.shipping_country IN ('NG', 'RU', 'IR') THEN
        INSERT INTO fraud_orders_log (order_json, detected_at)
        VALUES (JSON_OBJECT('user_id', NEW.user_id, 'amount', NEW.amount, 'country', NEW.shipping_country, 'order', NEW), NOW());
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fraudulent order blocked';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Instantly blocks and logs suspicious orders with full context for forensics, using JSON and custom error signaling.

-- 38. Event + Cross-Table Consistency (Transport: Auto-Heal Broken Foreign Keys)
-- Scenario: Every hour, scan for rides referencing missing drivers or users, and auto-fix or log for manual review.

DELIMITER $$
CREATE EVENT heal_broken_ride_fks
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    -- Log rides with missing drivers
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_driver', NOW() FROM rides WHERE driver_id NOT IN (SELECT id FROM drivers);
    -- Log rides with missing users
    INSERT INTO ride_fk_issues (ride_id, issue_type, detected_at)
    SELECT id, 'missing_user', NOW() FROM rides WHERE user_id NOT IN (SELECT id FROM users);
    -- Optionally, set driver_id/user_id to NULL or a default value for orphaned rides
    UPDATE rides SET driver_id = NULL WHERE driver_id NOT IN (SELECT id FROM drivers);
    UPDATE rides SET user_id = NULL WHERE user_id NOT IN (SELECT id FROM users);
END$$
DELIMITER ;

-- Why it's advanced:
-- Proactively detects and heals referential integrity issues, reducing data corruption risk at scale.

-- 39. Trigger + Partitioned Table + Dynamic SQL (Finance: Auto-Move Large Transactions to Audit Partition)
-- Scenario: On large transaction insert, move it to a special audit partition using dynamic SQL.

DELIMITER $$
CREATE TRIGGER move_large_txn_to_audit
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount > 50000 THEN
        SET @sql = CONCAT('INSERT INTO transactions_audit PARTITION (p', DATE_FORMAT(NOW(), '%Y%m'), ') SELECT * FROM transactions WHERE id = ', NEW.id, ';');
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        DELETE FROM transactions WHERE id = NEW.id;
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Uses dynamic SQL in a trigger to move sensitive data to a secure, partitioned audit table in real-time.

-- 40. Event + Predictive Analytics (E-commerce: Auto-Flag Products for Restock Based on ML Score)
-- Scenario: Every night, flag products for restock if ML-predicted demand score is high, using a precomputed ML table.

DELIMITER $$
CREATE EVENT flag_products_for_restock
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE products p
    JOIN product_demand_ml ml ON p.id = ml.product_id
    SET p.restock_flag = 1
    WHERE ml.predicted_demand > 0.8 AND p.stock < 20;
END$$
DELIMITER ;

-- Why it's advanced:
-- Integrates ML predictions into operational DB logic for proactive inventory management.

-- 22. Trigger + Multi-Tenant Data Isolation (SaaS: Enforce Tenant Boundaries)
-- Scenario: On insert/update, block cross-tenant data access by checking tenant_id.

DELIMITER $$
CREATE TRIGGER enforce_tenant_isolation
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF (SELECT tenant_id FROM users WHERE id = NEW.user_id) != NEW.tenant_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tenant data isolation violation';
    END IF;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enforces strict multi-tenant boundaries at the DB layer, preventing data leaks.


DELIMITER $$
CREATE EVENT enforce_sanctions
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE accounts
    SET status = 'FROZEN'
    WHERE id IN (
        SELECT DISTINCT account_id FROM transactions
        WHERE counterparty_id IN (SELECT entity_id FROM sanctioned_entities)
          AND txn_time > NOW() - INTERVAL 1 HOUR
    );
END$$
DELIMITER ;



-- 24. Trigger + Real-Time Deduplication (E-commerce: Prevent Duplicate Orders)
-- Scenario: On order insert, block if a similar order exists for the same user/product in the last 5 minutes.

DELIMITER $$
CREATE TRIGGER prevent_duplicate_orders
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM orders
        WHERE user_id = NEW.user_id
          AND product_id = NEW.product_id
          AND created_at > NOW() - INTERVAL 5 MINUTE
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate order detected';
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time deduplication at the DB layer, preventing accidental or malicious double orders.

-- 25. Event + GDPR/PII Scrubbing (Compliance: Auto-Redact Old User Data)
-- Scenario: Every day, redact PII for users inactive for 3+ years, for GDPR compliance.

DELIMITER $$
CREATE EVENT redact_old_user_data
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    UPDATE users
    SET email = NULL, phone = NULL, address = NULL
    WHERE last_active < NOW() - INTERVAL 3 YEAR;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates privacy compliance and reduces risk of data leaks.

-- 26. Trigger + Predictive Maintenance (Transport: Flag Vehicles for Service)
-- Scenario: On ride insert, if vehicle mileage exceeds threshold, flag for maintenance.

DELIMITER $$
CREATE TRIGGER flag_vehicle_maintenance
AFTER INSERT ON rides
FOR EACH ROW
BEGIN
    DECLARE mileage INT;
    SELECT odometer INTO mileage FROM vehicles WHERE id = NEW.vehicle_id;
    IF mileage > 100000 THEN
        UPDATE vehicles SET needs_service = 1 WHERE id = NEW.vehicle_id;
        INSERT INTO maintenance_alerts (vehicle_id, alert_type, created_at)
        VALUES (NEW.vehicle_id, 'Mileage threshold exceeded', NOW());
    END IF;
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables predictive maintenance and reduces downtime, all in-SQL.

-- 11. Trigger + Error Handling + Notification (Finance: Alert on Failed Transaction Insert)
-- Scenario: If a transaction insert fails due to constraint violation, log the error and notify admins instantly.

-- Note: MySQL triggers cannot catch errors from the same statement that fires them, but you can use AFTER statements for logging or use SIGNAL for custom error handling.

-- 12. Event + Cross-Database Sync (E-commerce: Sync Inventory to Analytics DB)
-- Scenario: Every 10 minutes, sync new/updated inventory rows to a reporting/analytics database.

DELIMITER $$
CREATE EVENT sync_inventory_to_analytics
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO analytics_db.inventory_snapshot (product_id, stock, updated_at)
    SELECT id, stock, updated_at FROM main_db.products
    WHERE updated_at > NOW() - INTERVAL 10 MINUTE;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Enables near real-time cross-DB sync for analytics, without ETL pipeline overhead.

-- 13. Trigger + Time-Travel Auditing (Transport: Immutable Ride History)
-- Scenario: On any update to rides, store the old row in a history table for time-travel queries.

DELIMITER $$
CREATE TRIGGER audit_ride_history
BEFORE UPDATE ON rides
FOR EACH ROW
BEGIN
    INSERT INTO rides_history (ride_id, driver_id, user_id, status, fare, ride_time, archived_at)
    VALUES (OLD.id, OLD.driver_id, OLD.user_id, OLD.status, OLD.fare, OLD.ride_time, NOW());
END$$
DELIMITER ;

-- Why it's advanced:
-- Enables time-travel queries and forensic analysis, critical for compliance and debugging.

-- 14. Event + Partition Management (Finance: Auto-Create Monthly Partitions)
-- Scenario: At the start of each month, auto-create a new partition for the transactions table.

DELIMITER $$
CREATE EVENT create_monthly_partition
ON SCHEDULE EVERY 1 MONTH STARTS '2025-08-01 00:00:00'
DO
BEGIN
    SET @sql = CONCAT('ALTER TABLE transactions ADD PARTITION (PARTITION p', DATE_FORMAT(NOW(), '%Y%m'), ' VALUES LESS THAN (TO_DAYS("', DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01'), '")))');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- Why it's god-mode:
-- Automates partition management, keeping large tables performant with zero manual intervention.

-- 15. Trigger + Window Function + JSON (E-commerce: Real-Time Cart Abandonment Scoring)
-- Scenario: On cart update, calculate abandonment risk score using window function and store as JSON for ML/BI.

DELIMITER $$
CREATE TRIGGER score_cart_abandonment
AFTER UPDATE ON carts
FOR EACH ROW
BEGIN
    DECLARE score_json JSON;
    SET score_json = (
        SELECT JSON_OBJECT('cart_id', NEW.id, 'risk_score',
            CASE WHEN COUNT(*) OVER (PARTITION BY user_id ORDER BY last_updated DESC) > 3 THEN 0.9 ELSE 0.2 END)
        FROM carts WHERE user_id = NEW.user_id AND last_updated > NOW() - INTERVAL 1 DAY LIMIT 1
    );
    UPDATE carts SET abandonment_score = score_json WHERE id = NEW.id;
END$$
DELIMITER ;

-- Why it's advanced:
-- Real-time, ML-ready scoring for cart abandonment, directly in the DB.

-- 6. Trigger + JSON + Window Function (Transport: Real-Time Surge Pricing by Zone)
-- Scenario: When a ride is inserted, recalculate surge multiplier

-- Trigger + Event + ML Integration (E-commerce: Real-Time Fraud Scoring with External ML Service)

-- Scenario: On order insert, call an external ML API for fraud scoring. If score > 0.9, block and log.
DELIMITER $$
CREATE TRIGGER ml_fraud_score_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    -- Pseudo-code: Call external ML API (requires UDF or external process)
    -- SET @score = CALL ml_fraud_score(NEW.user_id, NEW.amount, NEW.shipping_country, ...);
    -- IF @score > 0.9 THEN
    --     INSERT INTO fraud_orders_log (order_json, detected_at)
    --     VALUES (JSON_OBJECT('order', NEW), NOW());
    --     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order flagged as fraud by ML';
    -- END IF;
END$$
DELIMITER ;
-- Why it's god-mode: Integrates real-time ML scoring into DB logic for fraud prevention.

--  Event + Cross-Region Sync + Conflict Resolution (Hybrid Cloud: Multi-Region Inventory Sync)

-- Scenario: Every 5 minutes, sync inventory changes to a remote region, resolving conflicts by latest update.
DELIMITER $$
CREATE EVENT sync_inventory_cross_region
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
    -- Pseudo-code: Sync to remote region (requires FEDERATED or external process)
    -- INSERT INTO remote_region.inventory (product_id, stock, updated_at)
    -- SELECT product_id, stock, updated_at FROM inventory
    -- ON DUPLICATE KEY UPDATE
    --     stock = IF(VALUES(updated_at) > updated_at, VALUES(stock), stock),
    --     updated_at = GREATEST(updated_at, VALUES(updated_at));
END$$
DELIMITER ;
-- Why it's advanced: Handles cross-region, conflict-aware sync for global scale.

-- Trigger + Event + Observability (SaaS: Real-Time Slow Query Logging and Alerting)


-- Scenario: On query log insert, if duration > 2s, log and trigger alert event.
DELIMITER $$
CREATE TRIGGER log_slow_query
AFTER INSERT ON query_logs
FOR EACH ROW
BEGIN
    IF NEW.duration > 2 THEN
        INSERT INTO slow_query_alerts (query_text, duration, user_id, logged_at)
        VALUES (NEW.query_text, NEW.duration, NEW.user_id, NOW());
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE EVENT escalate_slow_queries
ON SCHEDULE EVERY 10 MINUTE
DO
BEGIN
    INSERT INTO admin_notifications (message, created_at)
    SELECT CONCAT('Slow queries detected: ', COUNT(*)), NOW()
    FROM slow_query_alerts
    WHERE logged_at > NOW() - INTERVAL 10 MINUTE;
END$$
DELIMITER ;
-- Why it's god-mode: Real-time observability and alerting for DB performance.

-- Trigger + Online DDL Guard (Zero-Downtime Migration: Block Writes During Online Schema Change)

-- Scenario: During online DDL, block writes to critical tables and log attempts.
DELIMITER $$
CREATE TRIGGER block_writes_during_ddl
BEFORE INSERT ON critical_table
FOR EACH ROW
BEGIN
    IF (SELECT is_online_ddl FROM migration_flags WHERE table_name = 'critical_table') = 1 THEN
        INSERT INTO ddl_block_log (table_name, attempted_at, user_id)
        VALUES ('critical_table', NOW(), NEW.user_id);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Writes blocked during online DDL';
    END IF;
END$$
DELIMITER ;
-- Why it's advanced: Ensures zero-downtime schema changes with safety and audit.

-- 5. Event + Streaming Integration (Analytics: Push New Orders to Kafka for Real-Time BI)

-- Event + Streaming Integration (Analytics: Push New Orders to Kafka for Real-Time BI)

-- Scenario: Every minute, push new orders to Kafka (or other streaming platform) for analytics.
DELIMITER $$
CREATE EVENT push_orders_to_stream
ON SCHEDULE EVERY 1 MINUTE
DO
BEGIN
    -- Pseudo-code: Use UDF or external connector to push to Kafka
    -- SELECT * FROM orders WHERE created_at > NOW() - INTERVAL 1 MINUTE
    -- INTO OUTFILE '/tmp/orders_stream.csv'
    -- (External process picks up and pushes to Kafka)
END$$
DELIMITER ;
-- Why it's god-mode: Bridges OLTP and streaming analytics in near real-time.



-- 6. Trigger + Security + Row-Level Encryption (Finance: Encrypt PII on Insert)

-- Scenario: On insert into sensitive table, encrypt PII fields using a UDF.
DELIMITER $$
CREATE TRIGGER encrypt_pii_on_insert
BEFORE INSERT ON sensitive_data
FOR EACH ROW
BEGIN
    -- Pseudo-code: Use UDF for encryption
    -- SET NEW.ssn = encrypt_udf(NEW.ssn, 'encryption_key');
    -- SET NEW.email = encrypt_udf(NEW.email, 'encryption_key');
END$$
DELIMITER ;
-- Why it's advanced: Enforces encryption at the DB layer for compliance.

7. Event + Zero-Downtime Migration + Canary Validation (E-commerce: Shadow Writes During Migration)

-- Scenario: During migration, shadow-write to new table and compare results for canary validation.
DELIMITER $$
CREATE EVENT shadow_write_orders
ON SCHEDULE EVERY 1 MINUTE
DO
BEGIN
    -- Pseudo-code: Copy new orders to shadow table
    -- INSERT IGNORE INTO orders_shadow SELECT * FROM orders WHERE created_at > NOW() - INTERVAL 1 MINUTE;
    -- Compare row counts, log discrepancies
    -- INSERT INTO migration_canary_log (discrepancy, checked_at)
    -- SELECT COUNT(*) FROM orders WHERE created_at > NOW() - INTERVAL 1 MINUTE
    --   - (SELECT COUNT(*) FROM orders_shadow WHERE created_at > NOW() - INTERVAL 1 MINUTE), NOW();
END$$
DELIMITER ;
-- Why it's god-mode: Enables safe, validated zero-downtime migrations.


8. Trigger + Hybrid Cloud DR (Disaster Recovery: Dual-Write to On-Prem and Cloud)
If you want these appended to your file, let me know if you want them as-is, or with further domain-specific tweaks or explanations.

-- Scenario: On critical insert, dual-write to on-prem and cloud replica (requires FEDERATED or external process).
DELIMITER $$
CREATE TRIGGER dual_write_critical_data
AFTER INSERT ON critical_data
FOR EACH ROW
BEGIN
    -- Pseudo-code: Dual-write (requires FEDERATED/external)
    -- INSERT INTO cloud_db.critical_data (fields...) VALUES (NEW.fields...);
END$$
DELIMITER ;
-- Why it's advanced: Ensures instant DR by dual-writing to hybrid cloud.