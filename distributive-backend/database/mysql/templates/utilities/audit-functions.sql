-- MySQL Audit Functions Utility
-- Collection of reusable audit and logging functions for MySQL databases
-- Adapted for MySQL with stored procedures, triggers, and MySQL-specific features

DELIMITER ;;

-- ===========================================
-- AUDIT TABLE CREATION
-- ===========================================

-- Create audit table if it doesn't exist
CREATE PROCEDURE create_audit_table(
    IN target_schema VARCHAR(64),
    IN target_table VARCHAR(64)
)
BEGIN
    DECLARE audit_table_name VARCHAR(128);
    DECLARE create_sql TEXT;

    -- If no specific table, create generic audit table
    IF target_table IS NULL THEN
        SET audit_table_name = 'audit_log';
    ELSE
        SET audit_table_name = CONCAT(target_table, '_audit');
    END IF;

    -- Create audit table
    SET @create_sql = CONCAT('
        CREATE TABLE IF NOT EXISTS `', target_schema, '`.`', audit_table_name, '` (
            audit_id BIGINT PRIMARY KEY AUTO_INCREMENT,
            table_name VARCHAR(100) NOT NULL,
            record_id VARCHAR(36),
            operation ENUM(\'INSERT\', \'UPDATE\', \'DELETE\') NOT NULL,
            old_values JSON,
            new_values JSON,
            changed_by VARCHAR(255),
            changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            client_ip VARCHAR(45),
            connection_id INT DEFAULT CONNECTION_ID(),
            transaction_id VARCHAR(100) DEFAULT @@session.tx_isolation,

            INDEX idx_audit_table_record (table_name, record_id),
            INDEX idx_audit_changed_at (changed_at DESC),
            INDEX idx_audit_operation (operation),
            INDEX idx_audit_changed_by (changed_by)
        ) ENGINE = InnoDB');

    PREPARE stmt FROM @create_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    -- Log the creation
    INSERT INTO audit_log (table_name, operation, new_values, changed_by)
    VALUES (audit_table_name, 'CREATE', JSON_OBJECT('action', 'audit_table_created', 'target_schema', target_schema), USER())
    ON DUPLICATE KEY UPDATE table_name = table_name; -- Handle case where audit_log doesn't exist yet
END;;

-- ===========================================
-- GENERIC AUDIT TRIGGER CREATOR
-- =========================================--

-- Create audit trigger for a table
CREATE PROCEDURE create_audit_trigger(
    IN target_schema VARCHAR(64),
    IN target_table VARCHAR(64)
)
BEGIN
    DECLARE audit_table_name VARCHAR(128);
    DECLARE trigger_name VARCHAR(128);
    DECLARE create_trigger_sql TEXT;

    SET audit_table_name = CONCAT(target_table, '_audit');
    SET trigger_name = CONCAT('trg_audit_', target_table);

    -- First ensure audit table exists
    CALL create_audit_table(target_schema, target_table);

    -- Create INSERT trigger
    SET @insert_trigger = CONCAT('
        CREATE TRIGGER ', trigger_name, '_insert
            AFTER INSERT ON `', target_schema, '`.`', target_table, '`
            FOR EACH ROW
        BEGIN
            INSERT INTO `', target_schema, '`.`', audit_table_name, '`
                (table_name, record_id, operation, new_values, changed_by, client_ip)
            VALUES
                (\'', target_table, '\', NEW.id, \'INSERT\', JSON_OBJECT(
                    ', get_column_list(target_schema, target_table), '
                ), USER(), SUBSTRING_INDEX(USER(), \'@\', -1));
        END');

    -- Create UPDATE trigger
    SET @update_trigger = CONCAT('
        CREATE TRIGGER ', trigger_name, '_update
            AFTER UPDATE ON `', target_schema, '`.`', target_table, '`
            FOR EACH ROW
        BEGIN
            INSERT INTO `', target_schema, '`.`', audit_table_name, '`
                (table_name, record_id, operation, old_values, new_values, changed_by, client_ip)
            VALUES
                (\'', target_table, '\', NEW.id, \'UPDATE\', JSON_OBJECT(
                    ', get_column_list_old(target_schema, target_table), '
                ), JSON_OBJECT(
                    ', get_column_list(target_schema, target_table), '
                ), USER(), SUBSTRING_INDEX(USER(), \'@\', -1));
        END');

    -- Create DELETE trigger
    SET @delete_trigger = CONCAT('
        CREATE TRIGGER ', trigger_name, '_delete
            AFTER DELETE ON `', target_schema, '`.`', target_table, '`
            FOR EACH ROW
        BEGIN
            INSERT INTO `', target_schema, '`.`', audit_table_name, '`
                (table_name, record_id, operation, old_values, changed_by, client_ip)
            VALUES
                (\'', target_table, '\', OLD.id, \'DELETE\', JSON_OBJECT(
                    ', get_column_list_old(target_schema, target_table), '
                ), USER(), SUBSTRING_INDEX(USER(), \'@\', -1));
        END');

    -- Execute triggers
    PREPARE stmt1 FROM @insert_trigger;
    EXECUTE stmt1;
    DEALLOCATE PREPARE stmt1;

    PREPARE stmt2 FROM @update_trigger;
    EXECUTE stmt2;
    DEALLOCATE PREPARE stmt2;

    PREPARE stmt3 FROM @delete_trigger;
    EXECUTE stmt3;
    DEALLOCATE PREPARE stmt3;
END;;

-- Helper function to get column list for NEW. prefix
CREATE FUNCTION get_column_list(target_schema VARCHAR(64), target_table VARCHAR(64))
RETURNS TEXT
DETERMINISTIC
BEGIN
    DECLARE col_list TEXT DEFAULT '';
    DECLARE done INT DEFAULT FALSE;
    DECLARE col_name VARCHAR(64);

    DECLARE cur CURSOR FOR
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = target_schema
          AND TABLE_NAME = target_table
          AND COLUMN_NAME != 'id'  -- Skip primary key as it's the record_id
        ORDER BY ORDINAL_POSITION;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO col_name;
        IF done THEN
            LEAVE read_loop;
        END IF;

        IF LENGTH(col_list) > 0 THEN
            SET col_list = CONCAT(col_list, ', ');
        END IF;
        SET col_list = CONCAT(col_list, '\'', col_name, '\', NEW.', col_name);
    END LOOP;

    CLOSE cur;

    RETURN col_list;
END;;

-- Helper function to get column list for OLD. prefix
CREATE FUNCTION get_column_list_old(target_schema VARCHAR(64), target_table VARCHAR(64))
RETURNS TEXT
DETERMINISTIC
BEGIN
    DECLARE col_list TEXT DEFAULT '';
    DECLARE done INT DEFAULT FALSE;
    DECLARE col_name VARCHAR(64);

    DECLARE cur CURSOR FOR
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = target_schema
          AND TABLE_NAME = target_table
          AND COLUMN_NAME != 'id'
        ORDER BY ORDINAL_POSITION;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO col_name;
        IF done THEN
            LEAVE read_loop;
        END IF;

        IF LENGTH(col_list) > 0 THEN
            SET col_list = CONCAT(col_list, ', ');
        END IF;
        SET col_list = CONCAT(col_list, '\'', col_name, '\', OLD.', col_name);
    END LOOP;

    CLOSE cur;

    RETURN col_list;
END;;

-- ===========================================
-- AUDIT REPORTING FUNCTIONS
-- =========================================--

-- Get audit trail for a specific record
CREATE PROCEDURE get_audit_trail(
    IN target_table VARCHAR(64),
    IN record_id VARCHAR(36),
    IN limit_rows INT
)
BEGIN
    SET @audit_table = CONCAT(target_table, '_audit');

    SET @sql = CONCAT('
        SELECT * FROM `', @audit_table, '`
        WHERE table_name = ? AND record_id = ?
        ORDER BY changed_at DESC
        LIMIT ?');

    PREPARE stmt FROM @sql;
    SET @table_param = target_table;
    SET @record_param = record_id;
    SET @limit_param = limit_rows;
    EXECUTE stmt USING @table_param, @record_param, @limit_param;
    DEALLOCATE PREPARE stmt;
END;;

-- Get audit summary for a table
CREATE PROCEDURE get_audit_summary(
    IN target_table VARCHAR(64),
    IN days_back INT
)
BEGIN
    SET @audit_table = CONCAT(target_table, '_audit');

    SET @sql = CONCAT('
        SELECT
            operation,
            DATE(changed_at) as change_date,
            COUNT(*) as change_count,
            GROUP_CONCAT(DISTINCT changed_by) as users
        FROM `', @audit_table, '`
        WHERE table_name = ?
          AND changed_at >= DATE_SUB(CURRENT_DATE, INTERVAL ? DAY)
        GROUP BY operation, DATE(changed_at)
        ORDER BY change_date DESC, operation');

    PREPARE stmt FROM @sql;
    SET @table_param = target_table;
    SET @days_param = days_back;
    EXECUTE stmt USING @table_param, @days_param;
    DEALLOCATE PREPARE stmt;
END;;

-- ===========================================
-- AUDIT CLEANUP FUNCTIONS
-- =========================================--

-- Archive old audit records
CREATE PROCEDURE archive_old_audit_records(
    IN target_table VARCHAR(64),
    IN days_to_keep INT
)
BEGIN
    DECLARE archive_table VARCHAR(128);
    DECLARE archive_count INT DEFAULT 0;

    SET archive_table = CONCAT(target_table, '_audit_archive');

    -- Create archive table if it doesn't exist
    SET @create_archive = CONCAT('
        CREATE TABLE IF NOT EXISTS `', archive_table, '` LIKE `', target_table, '_audit`');

    PREPARE stmt1 FROM @create_archive;
    EXECUTE stmt1;
    DEALLOCATE PREPARE stmt1;

    -- Move old records to archive
    SET @archive_sql = CONCAT('
        INSERT INTO `', archive_table, '`
        SELECT * FROM `', target_table, '_audit`
        WHERE changed_at < DATE_SUB(CURRENT_DATE, INTERVAL ', days_to_keep, ' DAY)');

    PREPARE stmt2 FROM @archive_sql;
    EXECUTE stmt2;
    SET archive_count = ROW_COUNT();
    DEALLOCATE PREPARE stmt2;

    -- Delete archived records
    SET @delete_sql = CONCAT('
        DELETE FROM `', target_table, '_audit`
        WHERE changed_at < DATE_SUB(CURRENT_DATE, INTERVAL ', days_to_keep, ' DAY)');

    PREPARE stmt3 FROM @delete_sql;
    EXECUTE stmt3;
    DEALLOCATE PREPARE stmt3;

    -- Log the operation
    INSERT INTO audit_log (table_name, operation, new_values, changed_by)
    VALUES (target_table, 'ARCHIVE', JSON_OBJECT('archived_count', archive_count, 'days_kept', days_to_keep), USER());
END;;

-- ===========================================
-- AUDIT MONITORING FUNCTIONS
-- =========================================--

-- Get audit statistics
CREATE PROCEDURE get_audit_stats(
    IN target_schema VARCHAR(64)
)
BEGIN
    SELECT
        table_name,
        COUNT(*) as total_audits,
        COUNT(DISTINCT record_id) as records_audited,
        COUNT(DISTINCT changed_by) as unique_users,
        MIN(changed_at) as first_audit,
        MAX(changed_at) as last_audit,
        AVG(JSON_DEPTH(new_values)) as avg_changes
    FROM audit_log
    WHERE table_name IN (
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = target_schema
          AND TABLE_NAME LIKE '%_audit'
    )
    GROUP BY table_name
    ORDER BY total_audits DESC;
END;;

-- Check for suspicious audit patterns
CREATE PROCEDURE detect_audit_anomalies(
    IN target_schema VARCHAR(64),
    IN hours_window INT
)
BEGIN
    SELECT
        table_name,
        changed_by,
        client_ip,
        operation,
        COUNT(*) as operation_count,
        MIN(changed_at) as first_operation,
        MAX(changed_at) as last_operation
    FROM audit_log
    WHERE changed_at >= DATE_SUB(NOW(), INTERVAL hours_window HOUR)
      AND table_name IN (
          SELECT TABLE_NAME
          FROM INFORMATION_SCHEMA.TABLES
          WHERE TABLE_SCHEMA = target_schema
      )
    GROUP BY table_name, changed_by, client_ip, operation
    HAVING COUNT(*) > 100  -- More than 100 operations in time window
    ORDER BY operation_count DESC;
END;;

DELIMITER ;

/*
USAGE EXAMPLES:

-- Create audit table for users table
CALL create_audit_table('your_database', 'users');

-- Create audit triggers for users table
CALL create_audit_trigger('your_database', 'users');

-- Get audit trail for a specific user
CALL get_audit_trail('users', 'user-uuid-here', 50);

-- Get audit summary for users table (last 30 days)
CALL get_audit_summary('users', 30);

-- Archive audit records older than 90 days
CALL archive_old_audit_records('users', 90);

-- Get audit statistics for entire database
CALL get_audit_stats('your_database');

-- Detect suspicious activity (last 24 hours)
CALL detect_audit_anomalies('your_database', 24);

This utility provides comprehensive audit functionality for MySQL databases including:
- Automatic audit table creation
- Trigger-based change logging
- Audit trail queries and reporting
- Data archival and cleanup
- Anomaly detection and monitoring
- Performance-optimized indexing

Key features:
1. Automatic schema discovery for dynamic column handling
2. JSON-based change tracking for detailed before/after values
3. Configurable retention policies
4. Performance monitoring and anomaly detection
5. Easy integration with existing applications

Adapt and extend based on your specific audit and compliance requirements!
*/
