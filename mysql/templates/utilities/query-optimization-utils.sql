-- MySQL Query Optimization Utilities
-- Collection of reusable query analysis and optimization functions
-- Adapted for MySQL with EXPLAIN analysis, query profiling, and optimization suggestions

DELIMITER ;;

-- ===========================================
-- QUERY ANALYSIS FUNCTIONS
-- =========================================--

-- Analyze query execution plan and provide recommendations
CREATE PROCEDURE analyze_query_plan(IN query_text LONGTEXT)
BEGIN
    DECLARE query_id VARCHAR(36) DEFAULT (UUID());
    DECLARE analysis_result JSON DEFAULT ('{"query_id": "", "analysis": {}, "recommendations": []}');

    -- Set query ID
    SET analysis_result = JSON_SET(analysis_result, '$.query_id', query_id);

    -- Create temporary table for EXPLAIN results
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_explain_result (
        id INT,
        select_type VARCHAR(20),
        table_name VARCHAR(64),
        partitions TEXT,
        type VARCHAR(10),
        possible_keys TEXT,
        key_name VARCHAR(64),
        key_len INT,
        ref TEXT,
        rows BIGINT,
        filtered DECIMAL(5,2),
        extra TEXT
    );

    -- Execute EXPLAIN and store results
    SET @explain_sql = CONCAT('EXPLAIN FORMAT=JSON ', query_text);
    SET @insert_sql = CONCAT('INSERT INTO temp_explain_result ', @explain_sql);

    -- This is a simplified version - in practice, you'd need to parse the JSON result
    PREPARE stmt FROM @insert_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    -- Analyze the results
    SELECT * FROM temp_explain_result;

    -- Provide recommendations based on EXPLAIN results
    SELECT
        CASE
            WHEN type = 'ALL' THEN 'FULL TABLE SCAN - Add appropriate indexes'
            WHEN type = 'index' THEN 'FULL INDEX SCAN - Consider covering indexes'
            WHEN possible_keys IS NOT NULL AND key_name IS NULL THEN 'Index exists but not used - Check query structure'
            WHEN rows > 10000 THEN 'High row estimate - Review query efficiency'
            ELSE 'Query execution appears efficient'
        END as recommendation,
        CONCAT('Table: ', table_name, ', Access: ', type, ', Rows: ', rows) as details
    FROM temp_explain_result;

    -- Cleanup
    DROP TEMPORARY TABLE temp_explain_result;

    -- Log analysis
    INSERT INTO query_analysis_log (query_id, query_text, analysis_result, analyzed_at)
    VALUES (query_id, query_text, analysis_result, NOW());
END;;

-- Analyze slow query log
CREATE PROCEDURE analyze_slow_queries(IN days_back INT)
BEGIN
    -- This assumes slow query log is enabled and accessible
    -- In practice, you'd read from the slow query log table

    SELECT
        sql_text,
        exec_count,
        avg_timer_wait / 1000000000 as avg_time_sec,
        total_latency / 1000000000 as total_time_sec,
        CASE
            WHEN avg_timer_wait / 1000000000 > 10 THEN 'CRITICAL - Immediate attention needed'
            WHEN avg_timer_wait / 1000000000 > 1 THEN 'HIGH - Performance optimization needed'
            WHEN avg_timer_wait / 1000000000 > 0.1 THEN 'MEDIUM - Monitor and optimize'
            ELSE 'LOW - Acceptable performance'
        END as priority_level,
        CASE
            WHEN sql_text LIKE '%SELECT % FROM % WHERE %' AND sql_text NOT LIKE '%ORDER BY%' THEN 'Consider adding ORDER BY for consistent results'
            WHEN sql_text LIKE '%SELECT *%' THEN 'Avoid SELECT * - specify needed columns'
            WHEN sql_text LIKE '%LIKE %%%' THEN 'Leading wildcard in LIKE - consider fulltext search'
            WHEN sql_text LIKE '%UNION%' THEN 'UNION can be expensive - consider UNION ALL if duplicates not needed'
            ELSE 'Review query structure and indexes'
        END as optimization_suggestion
    FROM performance_schema.events_statements_summary_by_digest
    WHERE digest_text IS NOT NULL
      AND last_seen >= DATE_SUB(NOW(), INTERVAL days_back DAY)
      AND avg_timer_wait > 100000000  -- More than 0.1 seconds average
    ORDER BY avg_timer_wait DESC
    LIMIT 50;
END;;

-- ===========================================
-- INDEX RECOMMENDATION ENGINE
-- =========================================--

-- Analyze queries and suggest indexes
CREATE PROCEDURE suggest_indexes(IN target_schema VARCHAR(64), IN days_back INT)
BEGIN
    -- Get queries that would benefit from indexes
    SELECT
        digest_text as query_pattern,
        exec_count,
        avg_timer_wait / 1000000000 as avg_time_sec,
        CASE
            WHEN digest_text LIKE '%WHERE % = %' AND digest_text NOT LIKE '%INDEX%' THEN 'Single column equality filter'
            WHEN digest_text LIKE '%WHERE % BETWEEN %' THEN 'Range query - consider composite index'
            WHEN digest_text LIKE '%ORDER BY %' THEN 'Sorting - index on ORDER BY columns'
            WHEN digest_text LIKE '%JOIN % ON %' THEN 'JOIN condition - ensure indexes on join columns'
            WHEN digest_text LIKE '%GROUP BY %' THEN 'Grouping - consider covering index'
            ELSE 'General query optimization needed'
        END as index_type,
        CASE
            WHEN avg_timer_wait / 1000000000 > 5 THEN 'URGENT'
            WHEN avg_timer_wait / 1000000000 > 1 THEN 'HIGH'
            WHEN avg_timer_wait / 1000000000 > 0.1 THEN 'MEDIUM'
            ELSE 'LOW'
        END as priority,
        CONCAT('CREATE INDEX idx_suggestion_', MD5(digest_text), ' ON table_name (column_name);') as suggested_index
    FROM performance_schema.events_statements_summary_by_digest
    WHERE schema_name = target_schema
      AND digest_text LIKE '%WHERE%'
      AND last_seen >= DATE_SUB(NOW(), INTERVAL days_back DAY)
      AND avg_timer_wait > 100000000  -- More than 0.1 seconds
    ORDER BY avg_timer_wait DESC, exec_count DESC
    LIMIT 20;
END;;

-- Check for missing foreign key indexes
CREATE PROCEDURE check_missing_fk_indexes(IN target_schema VARCHAR(64))
BEGIN
    SELECT
        kcu.TABLE_NAME as table_name,
        kcu.COLUMN_NAME as column_name,
        kcu.REFERENCED_TABLE_NAME as referenced_table,
        kcu.REFERENCED_COLUMN_NAME as referenced_column,
        CASE
            WHEN s.INDEX_NAME IS NULL THEN 'MISSING - Create index for foreign key performance'
            ELSE 'EXISTS - Index is present'
        END as index_status,
        CONCAT('CREATE INDEX idx_fk_', kcu.TABLE_NAME, '_', kcu.COLUMN_NAME,
               ' ON ', kcu.TABLE_SCHEMA, '.', kcu.TABLE_NAME, ' (', kcu.COLUMN_NAME, ');') as create_index_sql
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
    LEFT JOIN INFORMATION_SCHEMA.STATISTICS s ON (
        s.TABLE_SCHEMA = kcu.TABLE_SCHEMA
        AND s.TABLE_NAME = kcu.TABLE_NAME
        AND s.COLUMN_NAME = kcu.COLUMN_NAME
        AND s.INDEX_NAME != 'PRIMARY'
    )
    WHERE kcu.TABLE_SCHEMA = target_schema
      AND kcu.REFERENCED_TABLE_NAME IS NOT NULL
      AND kcu.CONSTRAINT_NAME != 'PRIMARY'
    GROUP BY kcu.TABLE_NAME, kcu.COLUMN_NAME, kcu.REFERENCED_TABLE_NAME, kcu.REFERENCED_COLUMN_NAME
    ORDER BY kcu.TABLE_NAME, kcu.COLUMN_NAME;
END;;

-- ===========================================
-- QUERY REWRITE SUGGESTIONS
-- =========================================--

-- Suggest query rewrites for better performance
CREATE PROCEDURE suggest_query_rewrites(IN target_schema VARCHAR(64))
BEGIN
    SELECT
        digest_text as original_query,
        exec_count,
        avg_timer_wait / 1000000000 as avg_time_sec,
        CASE
            WHEN digest_text LIKE '%SELECT % FROM % WHERE % IN (SELECT % FROM %)' THEN 'Consider JOIN instead of subquery'
            WHEN digest_text LIKE '%SELECT % FROM % WHERE % NOT IN (SELECT % FROM %)' THEN 'NOT IN with subquery - consider LEFT JOIN with IS NULL'
            WHEN digest_text LIKE '%SELECT COUNT(*) FROM %' THEN 'COUNT(*) can be slow - consider maintaining counters'
            WHEN digest_text LIKE '%SELECT DISTINCT %' THEN 'DISTINCT can be expensive - review if needed'
            WHEN digest_text LIKE '%ORDER BY RAND()%' THEN 'ORDER BY RAND() is slow - consider alternative approaches'
            WHEN digest_text LIKE '%LIKE %%%' THEN 'Leading wildcard in LIKE - consider fulltext search or trigram indexes'
            WHEN digest_text LIKE '%UNION%' AND digest_text NOT LIKE '%UNION ALL%' THEN 'UNION removes duplicates - use UNION ALL if duplicates not needed'
            ELSE 'Query structure appears reasonable'
        END as rewrite_suggestion,
        CASE
            WHEN digest_text LIKE '%SELECT % FROM % WHERE % IN (SELECT % FROM %)' THEN 'Rewrite as: SELECT t1.* FROM table1 t1 JOIN table2 t2 ON t1.id = t2.ref_id'
            WHEN digest_text LIKE '%ORDER BY RAND()%' THEN 'Consider: ORDER BY RAND() LIMIT N - but better to use application-side randomization'
            ELSE 'Review query for optimization opportunities'
        END as example_rewrite
    FROM performance_schema.events_statements_summary_by_digest
    WHERE schema_name = target_schema
      AND digest_text NOT LIKE '%EXPLAIN%'
      AND digest_text NOT LIKE '%SHOW%'
      AND last_seen >= DATE_SUB(NOW(), INTERVAL 7 DAY)
      AND avg_timer_wait > 100000000  -- More than 0.1 seconds
    ORDER BY avg_timer_wait DESC
    LIMIT 15;
END;;

-- ===========================================
-- PERFORMANCE MONITORING
-- =========================================--

-- Create query analysis log table
CREATE PROCEDURE setup_query_analysis()
BEGIN
    CREATE TABLE IF NOT EXISTS query_analysis_log (
        analysis_id BIGINT PRIMARY KEY AUTO_INCREMENT,
        query_id VARCHAR(36) NOT NULL,
        query_text LONGTEXT NOT NULL,
        analysis_result JSON,
        analyzed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

        INDEX idx_query_analysis_id (query_id),
        INDEX idx_query_analysis_time (analyzed_at),
        FULLTEXT INDEX ft_query_text (query_text)
    ) ENGINE = InnoDB;
END;;

-- Monitor query performance trends
CREATE PROCEDURE monitor_query_performance(IN hours_back INT)
BEGIN
    SELECT
        DATE_FORMAT(event_time, '%Y-%m-%d %H:00:00') as hour_bucket,
        COUNT(*) as query_count,
        AVG(timer_wait / 1000000000) as avg_query_time_sec,
        MAX(timer_wait / 1000000000) as max_query_time_sec,
        SUM(timer_wait / 1000000000) as total_time_sec,
        COUNT(CASE WHEN timer_wait / 1000000000 > 1 THEN 1 END) as slow_queries_over_1s,
        COUNT(CASE WHEN timer_wait / 1000000000 > 10 THEN 1 END) as slow_queries_over_10s
    FROM performance_schema.events_statements_history
    WHERE event_time >= DATE_SUB(NOW(), INTERVAL hours_back HOUR)
      AND sql_text IS NOT NULL
      AND sql_text NOT LIKE 'SELECT %'
    GROUP BY DATE_FORMAT(event_time, '%Y-%m-%d %H:00:00')
    ORDER BY hour_bucket DESC;
END;;

-- ===========================================
-- AUTOMATED OPTIMIZATION
-- =========================================--

-- Auto-create indexes for slow queries (CAUTION: Use carefully)
CREATE PROCEDURE auto_create_indexes(IN target_schema VARCHAR(64), IN min_exec_time DECIMAL(5,2))
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE query_text LONGTEXT;
    DECLARE table_name VARCHAR(64);
    DECLARE column_name VARCHAR(64);
    DECLARE cur CURSOR FOR
        SELECT
            sql_text,
            SUBSTRING_INDEX(SUBSTRING_INDEX(sql_text, 'FROM ', -1), ' ', 1) as table_name,
            CASE
                WHEN sql_text LIKE '%WHERE % = %' THEN SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(sql_text, 'WHERE ', -1), ' = ', 1), ' ', -1)
                WHEN sql_text LIKE '%WHERE % LIKE %' THEN SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(sql_text, 'WHERE ', -1), ' LIKE ', 1), ' ', -1)
                ELSE NULL
            END as column_name
        FROM performance_schema.events_statements_summary_by_digest
        WHERE schema_name = target_schema
          AND avg_timer_wait / 1000000000 > min_exec_time
          AND sql_text LIKE '%WHERE%'
          AND last_seen >= DATE_SUB(NOW(), INTERVAL 1 DAY);

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Setup logging
    CALL setup_query_analysis();

    OPEN cur;

    optimize_loop: LOOP
        FETCH cur INTO query_text, table_name, column_name;
        IF done THEN
            LEAVE optimize_loop;
        END IF;

        -- Check if index already exists
        IF column_name IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = target_schema
              AND TABLE_NAME = table_name
              AND COLUMN_NAME = column_name
              AND INDEX_NAME != 'PRIMARY'
        ) THEN
            BEGIN
                DECLARE index_sql TEXT;
                DECLARE index_name VARCHAR(64);

                SET index_name = CONCAT('idx_auto_', LOWER(table_name), '_', LOWER(column_name));
                SET index_sql = CONCAT('CREATE INDEX ', index_name, ' ON ', target_schema, '.', table_name, ' (', column_name, ')');

                -- Execute index creation
                SET @index_sql = index_sql;
                PREPARE stmt FROM @index_sql;
                EXECUTE stmt;
                DEALLOCATE PREPARE stmt;

                -- Log the action
                INSERT INTO query_analysis_log (query_id, query_text, analysis_result)
                VALUES (UUID(), query_text, JSON_OBJECT('action', 'auto_index_created', 'index_name', index_name, 'table', table_name, 'column', column_name));
            END;
        END IF;
    END LOOP;

    CLOSE cur;
END;;

-- ===========================================
-- QUERY COST ANALYSIS
-- =========================================--

-- Estimate query cost and resource usage
CREATE PROCEDURE estimate_query_cost(IN query_text LONGTEXT)
BEGIN
    DECLARE estimated_rows BIGINT;
    DECLARE estimated_cost DECIMAL(10,4);

    -- Create temporary table to capture EXPLAIN results
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_query_cost (
        id INT,
        select_type VARCHAR(20),
        table_name VARCHAR(64),
        type VARCHAR(10),
        possible_keys TEXT,
        rows BIGINT,
        filtered DECIMAL(5,2),
        cost DECIMAL(10,4)
    );

    -- Get EXPLAIN cost
    SET @explain_query = CONCAT('EXPLAIN ', query_text);
    SET @insert_explain = CONCAT('INSERT INTO temp_query_cost ', @explain_query);

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SELECT 'Unable to analyze query cost - check query syntax' as error;
        END;

        PREPARE stmt FROM @insert_explain;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END;

    -- Calculate total cost and provide analysis
    SELECT
        SUM(rows) as total_estimated_rows,
        SUM(cost) as total_estimated_cost,
        AVG(filtered) as avg_selectivity,
        CASE
            WHEN SUM(rows) > 1000000 THEN 'VERY HIGH - Consider query optimization or pagination'
            WHEN SUM(rows) > 100000 THEN 'HIGH - May need index optimization'
            WHEN SUM(rows) > 10000 THEN 'MEDIUM - Monitor performance'
            ELSE 'LOW - Query should perform well'
        END as cost_assessment,
        CASE
            WHEN SUM(cost) > 10000 THEN 'Very expensive query'
            WHEN SUM(cost) > 1000 THEN 'Moderately expensive'
            ELSE 'Reasonably priced'
        END as cost_description
    FROM temp_query_cost;

    -- Show detailed breakdown
    SELECT * FROM temp_query_cost ORDER BY cost DESC;

    -- Cleanup
    DROP TEMPORARY TABLE temp_query_cost;
END;;

DELIMITER ;

/*
USAGE EXAMPLES:

-- Analyze a specific query
CALL analyze_query_plan('SELECT * FROM users WHERE email = "user@example.com"');

-- Analyze slow queries from last 7 days
CALL analyze_slow_queries(7);

-- Get index suggestions
CALL suggest_indexes('your_database', 30);

-- Check missing foreign key indexes
CALL check_missing_fk_indexes('your_database');

-- Get query rewrite suggestions
CALL suggest_query_rewrites('your_database');

-- Monitor query performance trends
CALL monitor_query_performance(24);

-- Estimate query cost
CALL estimate_query_cost('SELECT COUNT(*) FROM large_table WHERE created_at > "2024-01-01"');

-- Auto-create indexes for slow queries (USE WITH CAUTION)
CALL auto_create_indexes('your_database', 1.0);

This utility provides comprehensive query optimization for MySQL databases including:
- Query execution plan analysis
- Slow query identification and analysis
- Index recommendation engine
- Query rewrite suggestions
- Performance monitoring and trending
- Automated optimization (with caution)
- Query cost estimation

Key features:
1. Integration with performance_schema for real query analysis
2. Automated index suggestions based on slow queries
3. Query cost estimation using EXPLAIN
4. Comprehensive logging and monitoring
5. Safe automated optimization options

Adapt and extend based on your specific query optimization requirements!
*/
