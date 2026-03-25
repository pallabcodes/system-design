-- MySQL Maintenance Functions Utility
-- Collection of reusable database maintenance and optimization functions
-- Adapted for MySQL with stored procedures for automated maintenance tasks

DELIMITER ;;

-- ===========================================
-- INDEX MAINTENANCE
-- =========================================--

-- Analyze and optimize table indexes
CREATE PROCEDURE analyze_table_indexes(IN target_table VARCHAR(64))
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE idx_name VARCHAR(64);
    DECLARE idx_type VARCHAR(16);
    DECLARE pages BIGINT;
    DECLARE cur CURSOR FOR
        SELECT INDEX_NAME, INDEX_TYPE, PAGES
        FROM INFORMATION_SCHEMA.STATISTICS s
        LEFT JOIN (
            SELECT INDEX_NAME, SUM(PAGE_COUNT) as PAGES
            FROM INFORMATION_SCHEMA.INNODB_INDEX_STATS
            WHERE TABLE_NAME = target_table
            GROUP BY INDEX_NAME
        ) stats ON s.INDEX_NAME = stats.INDEX_NAME
        WHERE s.TABLE_NAME = target_table
          AND s.INDEX_NAME != 'PRIMARY'
        ORDER BY PAGES DESC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Create results table
    CREATE TEMPORARY TABLE IF NOT EXISTS index_analysis (
        index_name VARCHAR(64),
        index_type VARCHAR(16),
        pages BIGINT DEFAULT 0,
        recommendation VARCHAR(255)
    );

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO idx_name, idx_type, pages;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Analyze index and provide recommendations
        IF pages > 10000 THEN
            INSERT INTO index_analysis VALUES (idx_name, idx_type, pages, 'Consider partitioning or archiving old data');
        ELSEIF pages > 1000 THEN
            INSERT INTO index_analysis VALUES (idx_name, idx_type, pages, 'Monitor usage and consider optimization');
        ELSE
            INSERT INTO index_analysis VALUES (idx_name, idx_type, pages, 'Index size is acceptable');
        END IF;
    END LOOP;

    CLOSE cur;

    -- Return analysis results
    SELECT * FROM index_analysis ORDER BY pages DESC;

    -- Cleanup
    DROP TEMPORARY TABLE index_analysis;
END;;

-- Rebuild fragmented indexes
CREATE PROCEDURE rebuild_fragmented_indexes(IN target_schema VARCHAR(64))
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE tbl_name VARCHAR(64);
    DECLARE idx_name VARCHAR(64);
    DECLARE cur CURSOR FOR
        SELECT TABLE_NAME, INDEX_NAME
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = target_schema
          AND INDEX_NAME != 'PRIMARY'
          AND TABLE_NAME NOT LIKE 'mysql.%'
          AND TABLE_NAME NOT LIKE 'information_schema.%'
          AND TABLE_NAME NOT LIKE 'performance_schema.%';

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    CREATE TEMPORARY TABLE IF NOT EXISTS rebuild_log (
        table_name VARCHAR(64),
        index_name VARCHAR(64),
        action_taken VARCHAR(255),
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    OPEN cur;

    rebuild_loop: LOOP
        FETCH cur INTO tbl_name, idx_name;
        IF done THEN
            LEAVE rebuild_loop;
        END IF;

        -- Rebuild index (this forces a rebuild in InnoDB)
        BEGIN
            DECLARE rebuild_sql TEXT;
            SET rebuild_sql = CONCAT('ALTER TABLE `', target_schema, '`.`', tbl_name, '` DROP INDEX `', idx_name, '`, ADD INDEX `', idx_name, '` (', get_index_columns(target_schema, tbl_name, idx_name), ')');

            SET @rebuild_sql = rebuild_sql;
            PREPARE stmt FROM @rebuild_sql;
            EXECUTE stmt;
            DEALLOCATE PREPARE stmt;

            INSERT INTO rebuild_log VALUES (tbl_name, idx_name, 'Rebuilt successfully', NOW());
        END;
    END LOOP;

    CLOSE cur;

    SELECT * FROM rebuild_log;
    DROP TEMPORARY TABLE rebuild_log;
END;;

-- Helper function to get index column definition
CREATE FUNCTION get_index_columns(target_schema VARCHAR(64), target_table VARCHAR(64), target_index VARCHAR(64))
RETURNS TEXT
DETERMINISTIC
BEGIN
    DECLARE col_list TEXT DEFAULT '';
    DECLARE done INT DEFAULT FALSE;
    DECLARE col_name VARCHAR(64);
    DECLARE sub_part INT;

    DECLARE cur CURSOR FOR
        SELECT COLUMN_NAME, SUB_PART
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = target_schema
          AND TABLE_NAME = target_table
          AND INDEX_NAME = target_index
        ORDER BY SEQ_IN_INDEX;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO col_name, sub_part;
        IF done THEN
            LEAVE read_loop;
        END IF;

        IF LENGTH(col_list) > 0 THEN
            SET col_list = CONCAT(col_list, ', ');
        END IF;

        IF sub_part IS NOT NULL THEN
            SET col_list = CONCAT(col_list, '`', col_name, '`(',
                CASE
                    WHEN sub_part = -1 THEN '255'  -- TEXT/BLOB prefix
                    ELSE CAST(sub_part AS CHAR)
                END, ')');
        ELSE
            SET col_list = CONCAT(col_list, '`', col_name, '`');
        END IF;
    END LOOP;

    CLOSE cur;

    RETURN col_list;
END;;

-- ===========================================
-- TABLE MAINTENANCE
-- =========================================--

-- Analyze table statistics and provide recommendations
CREATE PROCEDURE analyze_table_health(IN target_schema VARCHAR(64), IN target_table VARCHAR(64))
BEGIN
    DECLARE table_size DECIMAL(10,2);
    DECLARE index_size DECIMAL(10,2);
    DECLARE data_free BIGINT;
    DECLARE avg_row_length INT;
    DECLARE row_count BIGINT;

    -- Get table statistics
    SELECT
        ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as total_size_mb,
        ROUND(DATA_LENGTH / 1024 / 1024, 2) as data_size_mb,
        ROUND(INDEX_LENGTH / 1024 / 1024, 2) as index_size_mb,
        DATA_FREE / 1024 / 1024 as free_space_mb,
        AVG_ROW_LENGTH,
        TABLE_ROWS
    INTO table_size, @data_size, index_size, data_free, avg_row_length, row_count
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = target_schema
      AND TABLE_NAME = target_table;

    -- Generate recommendations
    SELECT
        target_table as table_name,
        table_size as total_size_mb,
        index_size as index_size_mb,
        data_free as free_space_mb,
        row_count as row_count,
        CASE
            WHEN data_free > table_size * 0.2 THEN 'HIGH - Consider OPTIMIZE TABLE'
            WHEN data_free > table_size * 0.1 THEN 'MEDIUM - Monitor fragmentation'
            ELSE 'LOW - Fragmentation acceptable'
        END as fragmentation_level,
        CASE
            WHEN index_size > table_size * 2 THEN 'Indexes too large - review and consolidate'
            WHEN index_size > table_size THEN 'Index size reasonable'
            ELSE 'Consider additional indexes if needed'
        END as index_recommendation,
        CASE
            WHEN avg_row_length > 10000 THEN 'Large rows - consider vertical partitioning'
            WHEN avg_row_length > 1000 THEN 'Medium rows - acceptable'
            ELSE 'Small rows - good for performance'
        END as row_size_analysis;
END;;

-- Optimize table (rebuild and defragment)
CREATE PROCEDURE optimize_table(IN target_schema VARCHAR(64), IN target_table VARCHAR(64))
BEGIN
    DECLARE optimize_sql TEXT;

    -- Log optimization start
    INSERT INTO maintenance_log (operation_type, target_schema, target_table, details, start_time)
    VALUES ('OPTIMIZE', target_schema, target_table, 'Starting table optimization', NOW());

    -- Perform optimization
    SET optimize_sql = CONCAT('OPTIMIZE TABLE `', target_schema, '`.`', target_table, '`');
    SET @optimize_sql = optimize_sql;

    PREPARE stmt FROM @optimize_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    -- Log completion
    UPDATE maintenance_log
    SET end_time = NOW(), status = 'COMPLETED', details = 'Table optimization completed'
    WHERE operation_type = 'OPTIMIZE'
      AND target_schema = target_schema
      AND target_table = target_table
      AND end_time IS NULL;
END;;

-- ===========================================
-- DATABASE-WIDE MAINTENANCE
-- =========================================--

-- Analyze entire database health
CREATE PROCEDURE analyze_database_health(IN target_schema VARCHAR(64))
BEGIN
    -- Create summary table
    CREATE TEMPORARY TABLE IF NOT EXISTS db_health_summary (
        table_name VARCHAR(64),
        total_size_mb DECIMAL(10,2),
        data_size_mb DECIMAL(10,2),
        index_size_mb DECIMAL(10,2),
        free_space_mb DECIMAL(10,2),
        row_count BIGINT,
        fragmentation_level VARCHAR(20),
        recommendations TEXT
    );

    -- Analyze each table
    INSERT INTO db_health_summary
    SELECT
        TABLE_NAME,
        ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2),
        ROUND(DATA_LENGTH / 1024 / 1024, 2),
        ROUND(INDEX_LENGTH / 1024 / 1024, 2),
        ROUND(DATA_FREE / 1024 / 1024, 2),
        TABLE_ROWS,
        CASE
            WHEN DATA_FREE / (DATA_LENGTH + INDEX_LENGTH + 1) > 0.2 THEN 'HIGH'
            WHEN DATA_FREE / (DATA_LENGTH + INDEX_LENGTH + 1) > 0.1 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        CONCAT(
            CASE WHEN INDEX_LENGTH > DATA_LENGTH * 2 THEN 'Reduce index count; ' ELSE '' END,
            CASE WHEN DATA_FREE > (DATA_LENGTH + INDEX_LENGTH) * 0.15 THEN 'Optimize table; ' ELSE '' END,
            CASE WHEN TABLE_ROWS > 1000000 THEN 'Consider partitioning; ' ELSE '' END,
            'Analyze query patterns'
        )
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = target_schema
      AND TABLE_TYPE = 'BASE TABLE'
    ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC;

    -- Return summary
    SELECT * FROM db_health_summary;

    -- Overall database statistics
    SELECT
        COUNT(*) as total_tables,
        SUM(total_size_mb) as total_size_mb,
        SUM(data_size_mb) as total_data_mb,
        SUM(index_size_mb) as total_index_mb,
        SUM(free_space_mb) as total_free_mb,
        SUM(row_count) as total_rows,
        COUNT(CASE WHEN fragmentation_level = 'HIGH' THEN 1 END) as highly_fragmented_tables,
        COUNT(CASE WHEN fragmentation_level = 'MEDIUM' THEN 1 END) as medium_fragmented_tables
    FROM db_health_summary;

    DROP TEMPORARY TABLE db_health_summary;
END;;

-- ===========================================
-- AUTOMATED MAINTENANCE SCHEDULER
-- =========================================--

-- Create maintenance log table if it doesn't exist
CREATE PROCEDURE setup_maintenance_logging()
BEGIN
    CREATE TABLE IF NOT EXISTS maintenance_log (
        log_id BIGINT PRIMARY KEY AUTO_INCREMENT,
        operation_type VARCHAR(50) NOT NULL,
        target_schema VARCHAR(64),
        target_table VARCHAR(64),
        details TEXT,
        start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        end_time TIMESTAMP NULL,
        status VARCHAR(20) DEFAULT 'RUNNING',
        error_message TEXT,

        INDEX idx_maintenance_log_type (operation_type),
        INDEX idx_maintenance_log_status (status),
        INDEX idx_maintenance_log_start (start_time)
    ) ENGINE = InnoDB;
END;;

-- Automated maintenance procedure
CREATE PROCEDURE run_automated_maintenance(IN target_schema VARCHAR(64))
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE tbl_name VARCHAR(64);
    DECLARE cur CURSOR FOR
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = target_schema
          AND TABLE_TYPE = 'BASE TABLE'
          AND TABLE_NAME NOT LIKE 'mysql.%'
          AND TABLE_NAME NOT LIKE 'information_schema.%'
          AND TABLE_NAME NOT LIKE 'performance_schema.%';

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @sqlstate = RETURNED_SQLSTATE, @errno = MYSQL_ERRNO, @text = MESSAGE_TEXT;
        INSERT INTO maintenance_log (operation_type, target_schema, details, status, error_message)
        VALUES ('MAINTENANCE', target_schema, 'Automated maintenance failed', 'FAILED', CONCAT('SQLSTATE: ', @sqlstate, ', ERRNO: ', @errno, ', MESSAGE: ', @text));
    END;

    -- Setup logging
    CALL setup_maintenance_logging();

    -- Log maintenance start
    INSERT INTO maintenance_log (operation_type, target_schema, details)
    VALUES ('MAINTENANCE', target_schema, 'Starting automated maintenance');

    OPEN cur;

    maintenance_loop: LOOP
        FETCH cur INTO tbl_name;
        IF done THEN
            LEAVE maintenance_loop;
        END IF;

        -- Analyze table indexes
        BEGIN
            CALL analyze_table_indexes(tbl_name);
        END;

        -- Check table health and optimize if needed
        BEGIN
            DECLARE free_mb DECIMAL(10,2);
            SELECT DATA_FREE / 1024 / 1024 INTO free_mb
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = target_schema AND TABLE_NAME = tbl_name;

            IF free_mb > 100 THEN  -- More than 100MB free space
                CALL optimize_table(target_schema, tbl_name);
            END IF;
        END;

    END LOOP;

    CLOSE cur;

    -- Update maintenance log
    UPDATE maintenance_log
    SET end_time = NOW(), status = 'COMPLETED', details = 'Automated maintenance completed successfully'
    WHERE operation_type = 'MAINTENANCE'
      AND target_schema = target_schema
      AND end_time IS NULL;

END;;

-- ===========================================
-- CLEANUP AND ARCHIVAL
-- =========================================--

-- Archive old data
CREATE PROCEDURE archive_old_data(
    IN target_table VARCHAR(64),
    IN date_column VARCHAR(64),
    IN archive_days INT
)
BEGIN
    DECLARE archive_table VARCHAR(128);
    DECLARE archive_count INT DEFAULT 0;

    SET archive_table = CONCAT(target_table, '_archive_', DATE_FORMAT(NOW(), '%Y%m'));

    -- Create archive table
    SET @create_archive = CONCAT('CREATE TABLE IF NOT EXISTS `', archive_table, '` LIKE `', target_table, '`');
    PREPARE stmt1 FROM @create_archive;
    EXECUTE stmt1;
    DEALLOCATE PREPARE stmt1;

    -- Move old data
    SET @archive_sql = CONCAT('INSERT INTO `', archive_table, '` SELECT * FROM `', target_table, '` WHERE `', date_column, '` < DATE_SUB(NOW(), INTERVAL ', archive_days, ' DAY)');
    PREPARE stmt2 FROM @archive_sql;
    EXECUTE stmt2;
    SET archive_count = ROW_COUNT();
    DEALLOCATE PREPARE stmt2;

    -- Delete archived data
    SET @delete_sql = CONCAT('DELETE FROM `', target_table, '` WHERE `', date_column, '` < DATE_SUB(NOW(), INTERVAL ', archive_days, ' DAY)');
    PREPARE stmt3 FROM @delete_sql;
    EXECUTE stmt3;
    DEALLOCATE PREPARE stmt3;

    -- Log the operation
    INSERT INTO maintenance_log (operation_type, target_schema, target_table, details, status)
    VALUES ('ARCHIVE', DATABASE(), target_table, CONCAT('Archived ', archive_count, ' records older than ', archive_days, ' days'), 'COMPLETED');
END;;

-- ===========================================
-- MONITORING AND ALERTING
-- =========================================--

-- Check for maintenance alerts
CREATE PROCEDURE check_maintenance_alerts(IN target_schema VARCHAR(64))
BEGIN
    -- Tables with high fragmentation
    SELECT
        'HIGH_FRAGMENTATION' as alert_type,
        TABLE_NAME as table_name,
        ROUND(DATA_FREE / 1024 / 1024, 2) as free_space_mb,
        'Consider running OPTIMIZE TABLE' as recommendation
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = target_schema
      AND DATA_FREE > (DATA_LENGTH + INDEX_LENGTH) * 0.15
      AND DATA_LENGTH > 0

    UNION ALL

    -- Tables without primary keys
    SELECT
        'NO_PRIMARY_KEY' as alert_type,
        TABLE_NAME as table_name,
        NULL as free_space_mb,
        'Consider adding a primary key for performance' as recommendation
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE TABLE_SCHEMA = target_schema
      AND TABLE_TYPE = 'BASE TABLE'
      AND NOT EXISTS (
          SELECT 1 FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE k
          WHERE k.TABLE_SCHEMA = t.TABLE_SCHEMA
            AND k.TABLE_NAME = t.TABLE_NAME
            AND k.CONSTRAINT_NAME = 'PRIMARY'
      )

    UNION ALL

    -- Large tables without partitioning
    SELECT
        'LARGE_UNPARTITIONED' as alert_type,
        TABLE_NAME as table_name,
        ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as size_mb,
        'Consider partitioning for better performance' as recommendation
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = target_schema
      AND (DATA_LENGTH + INDEX_LENGTH) > 1024 * 1024 * 1024  -- > 1GB
      AND CREATE_OPTIONS NOT LIKE '%partitioned%'

    ORDER BY alert_type, table_name;
END;;

DELIMITER ;

/*
USAGE EXAMPLES:

-- Analyze indexes for a specific table
CALL analyze_table_indexes('users');

-- Rebuild fragmented indexes across database
CALL rebuild_fragmented_indexes('your_database');

-- Analyze table health
CALL analyze_table_health('your_database', 'users');

-- Optimize a table
CALL optimize_table('your_database', 'large_table');

-- Analyze entire database health
CALL analyze_database_health('your_database');

-- Run automated maintenance
CALL run_automated_maintenance('your_database');

-- Archive old data (older than 365 days)
CALL archive_old_data('logs', 'created_at', 365);

-- Check for maintenance alerts
CALL check_maintenance_alerts('your_database');

This utility provides comprehensive database maintenance for MySQL including:
- Index analysis and rebuilding
- Table optimization and defragmentation
- Database-wide health monitoring
- Automated maintenance scheduling
- Data archival and cleanup
- Maintenance alerting and monitoring

Key features:
1. Automated index and table maintenance
2. Health monitoring and recommendations
3. Comprehensive logging of maintenance operations
4. Configurable archival policies
5. Alert system for maintenance issues

Adapt and extend based on your specific maintenance and performance requirements!
*/
