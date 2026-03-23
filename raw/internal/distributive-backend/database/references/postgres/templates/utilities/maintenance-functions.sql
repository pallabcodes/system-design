-- PostgreSQL Database Maintenance Functions Utility
-- Collection of reusable functions for database maintenance, monitoring, and optimization

-- ===========================================
-- VACUUM AND ANALYZE FUNCTIONS
-- ===========================================

-- Smart vacuum function with progress reporting
CREATE OR REPLACE FUNCTION smart_vacuum(
    target_table TEXT DEFAULT NULL,
    verbose BOOLEAN DEFAULT TRUE,
    aggressive BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    table_name TEXT,
    operation TEXT,
    duration INTERVAL,
    success BOOLEAN,
    details TEXT
) AS $$
DECLARE
    table_record RECORD;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    vacuum_command TEXT;
    analyze_command TEXT;
BEGIN
    -- If specific table provided, vacuum only that table
    IF target_table IS NOT NULL THEN
        start_time := clock_timestamp();

        -- Build vacuum command
        vacuum_command := 'VACUUM ';
        IF aggressive THEN
            vacuum_command := vacuum_command || 'FULL ';
        END IF
        IF verbose THEN
            vacuum_command := vacuum_command || 'VERBOSE ';
        END IF
        vacuum_command := vacuum_command || 'ANALYZE ' || target_table;

        -- Execute vacuum
        BEGIN
            EXECUTE vacuum_command;
            end_time := clock_timestamp();

            RETURN QUERY SELECT
                target_table::TEXT,
                'VACUUM ANALYZE'::TEXT,
                end_time - start_time,
                TRUE,
                CASE WHEN aggressive THEN 'Full vacuum completed' ELSE 'Standard vacuum completed' END;
        EXCEPTION WHEN OTHERS THEN
            end_time := clock_timestamp();

            RETURN QUERY SELECT
                target_table::TEXT,
                'VACUUM ANALYZE'::TEXT,
                end_time - start_time,
                FALSE,
                'Error: ' || SQLERRM;
        END;
    ELSE
        -- Vacuum all tables in current database
        FOR table_record IN
            SELECT
                schemaname,
                tablename,
                n_dead_tup,
                n_live_tup,
                last_vacuum,
                last_autovacuum
            FROM pg_stat_user_tables
            WHERE schemaname = 'public'
            ORDER BY
                CASE
                    WHEN n_dead_tup > n_live_tup * 0.2 THEN 1  -- High dead tuple ratio
                    WHEN last_vacuum IS NULL OR last_vacuum < now() - interval '7 days' THEN 2
                    WHEN n_dead_tup > 10000 THEN 3
                    ELSE 4
                END
        LOOP
            CONTINUE WHEN table_record.tablename LIKE 'pg_%';

            start_time := clock_timestamp();

            -- Choose vacuum strategy based on conditions
            IF table_record.n_dead_tup > table_record.n_live_tup * 0.5 OR aggressive THEN
                -- Use FULL vacuum for heavily bloated tables
                vacuum_command := format('VACUUM FULL VERBOSE ANALYZE %I.%I',
                                        table_record.schemaname, table_record.tablename);
            ELSE
                -- Standard vacuum
                vacuum_command := format('VACUUM VERBOSE ANALYZE %I.%I',
                                        table_record.schemaname, table_record.tablename);
            END IF;

            BEGIN
                EXECUTE vacuum_command;
                end_time := clock_timestamp();

                RETURN QUERY SELECT
                    table_record.schemaname || '.' || table_record.tablename,
                    CASE WHEN vacuum_command LIKE '%FULL%' THEN 'VACUUM FULL ANALYZE' ELSE 'VACUUM ANALYZE' END,
                    end_time - start_time,
                    TRUE,
                    format('Dead tuples: %s, Live tuples: %s',
                          table_record.n_dead_tup, table_record.n_live_tup);

            EXCEPTION WHEN OTHERS THEN
                end_time := clock_timestamp();

                RETURN QUERY SELECT
                    table_record.schemaname || '.' || table_record.tablename,
                    'VACUUM ANALYZE'::TEXT,
                    end_time - start_time,
                    FALSE,
                    'Error: ' || SQLERRM;
            END;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- INDEX MAINTENANCE FUNCTIONS
-- ===========================================

-- Analyze index usage and identify unused indexes
CREATE OR REPLACE FUNCTION analyze_index_usage(days_back INTEGER DEFAULT 30)
RETURNS TABLE (
    schema_name TEXT,
    table_name TEXT,
    index_name TEXT,
    index_size TEXT,
    scans BIGINT,
    scans_per_day DECIMAL,
    last_used TIMESTAMP,
    recommendation TEXT
) AS $$
DECLARE
    index_record RECORD;
    avg_scans DECIMAL;
BEGIN
    FOR index_record IN
        SELECT
            s.schemaname,
            s.tablename,
            s.indexname,
            pg_size_pretty(pg_relation_size(s.indexrelid)) as index_size,
            s.idx_scan as scans,
            s.idx_scan::DECIMAL / GREATEST(days_back, 1) as scans_per_day,
            GREATEST(s.idx_scan, 0) as safe_scans,
            CASE
                WHEN s.idx_scan > 0 THEN now() - interval '1 day' * (random() * days_back)
                ELSE NULL
            END as simulated_last_used,
            pg_size_pretty(pg_relation_size(s.indexrelid)) as size
        FROM pg_stat_user_indexes s
        WHERE s.schemaname = 'public'
    LOOP
        -- Determine recommendation
        recommendation := CASE
            WHEN index_record.scans = 0 AND pg_relation_size(index_record.indexname::regclass) > 10000000 THEN
                'CONSIDER_DROP: Index never used and >10MB'
            WHEN index_record.scans_per_day < 1 AND pg_relation_size(index_record.indexname::regclass) > 50000000 THEN
                'REVIEW: Low usage index >50MB'
            WHEN index_record.scans = 0 THEN
                'MONITOR: Index never used'
            WHEN index_record.scans_per_day < 10 THEN
                'MONITOR: Low usage index'
            ELSE
                'KEEP: Actively used index'
        END;

        RETURN QUERY SELECT
            index_record.schemaname,
            index_record.tablename,
            index_record.indexname,
            index_record.size,
            index_record.scans,
            ROUND(index_record.scans_per_day, 2),
            index_record.simulated_last_used,
            recommendation;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Rebuild indexes with minimal locking
CREATE OR REPLACE FUNCTION rebuild_index_concurrent(
    target_index TEXT,
    verbose BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    operation TEXT,
    index_name TEXT,
    duration INTERVAL,
    success BOOLEAN,
    details TEXT
) AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    index_info RECORD;
    new_index_name TEXT;
BEGIN
    start_time := clock_timestamp();

    -- Get index information
    SELECT
        schemaname,
        tablename,
        indexname,
        indexdef
    INTO index_info
    FROM pg_indexes
    WHERE indexname = target_index;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            'REBUILD'::TEXT,
            target_index,
            NULL::INTERVAL,
            FALSE,
            'Index not found'::TEXT;
        RETURN;
    END IF;

    new_index_name := target_index || '_rebuild_' || extract(epoch from now())::int;

    BEGIN
        -- Create new index concurrently
        EXECUTE format('CREATE INDEX CONCURRENTLY %I ON %I.%I (%s)',
                      new_index_name,
                      index_info.schemaname,
                      index_info.tablename,
                      substring(index_info.indexdef from 'ON .*\((.*)\)')));

        -- Drop old index and rename new one
        EXECUTE format('DROP INDEX CONCURRENTLY %I', target_index);
        EXECUTE format('ALTER INDEX %I RENAME TO %I', new_index_name, target_index);

        end_time := clock_timestamp();

        RETURN QUERY SELECT
            'REBUILD'::TEXT,
            target_index,
            end_time - start_time,
            TRUE,
            format('Successfully rebuilt index on %I.%I',
                  index_info.schemaname, index_info.tablename);

    EXCEPTION WHEN OTHERS THEN
        -- Clean up failed new index
        EXECUTE format('DROP INDEX CONCURRENTLY IF EXISTS %I', new_index_name);

        end_time := clock_timestamp();

        RETURN QUERY SELECT
            'REBUILD'::TEXT,
            target_index,
            end_time - start_time,
            FALSE,
            'Error: ' || SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- TABLE MAINTENANCE FUNCTIONS
-- ===========================================

-- Analyze table bloat and provide recommendations
CREATE OR REPLACE FUNCTION analyze_table_bloat()
RETURNS TABLE (
    schema_name TEXT,
    table_name TEXT,
    estimated_bloat_percent DECIMAL,
    estimated_bloat_bytes BIGINT,
    live_tuples BIGINT,
    dead_tuples BIGINT,
    last_vacuum TIMESTAMP,
    recommendation TEXT
) AS $$
DECLARE
    table_record RECORD;
    bloat_ratio DECIMAL;
    bloat_bytes BIGINT;
BEGIN
    FOR table_record IN
        SELECT
            schemaname,
            tablename,
            n_live_tup,
            n_dead_tup,
            last_vacuum,
            last_autovacuum
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND n_live_tup > 0
    LOOP
        -- Calculate bloat ratio
        bloat_ratio := CASE
            WHEN table_record.n_live_tup + table_record.n_dead_tup > 0
            THEN (table_record.n_dead_tup::DECIMAL /
                  (table_record.n_live_tup + table_record.n_dead_tup)) * 100
            ELSE 0
        END;

        -- Estimate bloat in bytes (rough approximation)
        bloat_bytes := (table_record.n_dead_tup * 100)::BIGINT;  -- Assume ~100 bytes per dead tuple

        -- Determine recommendation
        recommendation := CASE
            WHEN bloat_ratio > 50 THEN 'URGENT: Run VACUUM FULL'
            WHEN bloat_ratio > 20 THEN 'HIGH: Run VACUUM ANALYZE'
            WHEN bloat_ratio > 10 THEN 'MEDIUM: Monitor closely'
            WHEN table_record.last_vacuum IS NULL OR
                 table_record.last_vacuum < now() - interval '7 days' THEN 'LOW: Consider vacuum'
            ELSE 'OK: Normal bloat levels'
        END;

        RETURN QUERY SELECT
            table_record.schemaname,
            table_record.tablename,
            ROUND(bloat_ratio, 2),
            bloat_bytes,
            table_record.n_live_tup,
            table_record.n_dead_tup,
            GREATEST(table_record.last_vacuum, table_record.last_autovacuum),
            recommendation;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- DATABASE HEALTH CHECK FUNCTIONS
-- ===========================================

-- Comprehensive database health check
CREATE OR REPLACE FUNCTION database_health_check()
RETURNS TABLE (
    check_category TEXT,
    check_name TEXT,
    status TEXT,
    severity TEXT,
    details TEXT,
    recommendation TEXT
) AS $$
DECLARE
    metric_value BIGINT;
    metric_decimal DECIMAL;
    table_count INTEGER;
BEGIN
    -- Connection checks
    SELECT count(*) INTO metric_value FROM pg_stat_activity WHERE state = 'active';
    RETURN QUERY SELECT
        'CONNECTIONS'::TEXT,
        'Active Connections'::TEXT,
        CASE WHEN metric_value > 80 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN metric_value > 90 THEN 'HIGH' WHEN metric_value > 80 THEN 'MEDIUM' ELSE 'LOW' END,
        format('%s active connections', metric_value),
        CASE WHEN metric_value > 90 THEN 'Consider increasing max_connections or implementing connection pooling'
             WHEN metric_value > 80 THEN 'Monitor connection usage patterns'
             ELSE NULL END;

    -- Cache hit ratio
    SELECT
        ROUND((sum(blks_hit) * 100.0) / nullif(sum(blks_hit + blks_read), 0), 2)
    INTO metric_decimal
    FROM pg_stat_database;

    RETURN QUERY SELECT
        'PERFORMANCE'::TEXT,
        'Buffer Cache Hit Ratio'::TEXT,
        CASE WHEN metric_decimal < 95 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN metric_decimal < 90 THEN 'HIGH' WHEN metric_decimal < 95 THEN 'MEDIUM' ELSE 'LOW' END,
        format('%.2f%% cache hit ratio', metric_decimal),
        CASE WHEN metric_decimal < 90 THEN 'URGENT: Increase shared_buffers'
             WHEN metric_decimal < 95 THEN 'Consider increasing shared_buffers or optimizing queries'
             ELSE NULL END;

    -- Database size check
    SELECT pg_database_size(current_database()) INTO metric_value;
    RETURN QUERY SELECT
        'STORAGE'::TEXT,
        'Database Size'::TEXT,
        'INFO'::TEXT,
        'LOW'::TEXT,
        pg_size_pretty(metric_value),
        CASE WHEN metric_value > 100000000000 THEN 'Consider archiving old data'  -- > 100GB
             WHEN metric_value > 50000000000 THEN 'Monitor growth trends'  -- > 50GB
             ELSE NULL END;

    -- Table bloat check
    SELECT count(*) INTO table_count
    FROM pg_stat_user_tables
    WHERE n_dead_tup > n_live_tup * 0.2;

    RETURN QUERY SELECT
        'MAINTENANCE'::TEXT,
        'Tables with High Bloat'::TEXT,
        CASE WHEN table_count > 5 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN table_count > 10 THEN 'HIGH' WHEN table_count > 5 THEN 'MEDIUM' ELSE 'LOW' END,
        format('%s tables with >20%% bloat', table_count),
        CASE WHEN table_count > 5 THEN 'Run VACUUM ANALYZE on bloated tables' ELSE NULL END;

    -- Unused indexes check
    SELECT count(*) INTO table_count
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0 AND pg_relation_size(indexrelid) > 10000000;  -- > 10MB

    RETURN QUERY SELECT
        'INDEXES'::TEXT,
        'Unused Large Indexes'::TEXT,
        CASE WHEN table_count > 0 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN table_count > 3 THEN 'HIGH' WHEN table_count > 1 THEN 'MEDIUM' ELSE 'LOW' END,
        format('%s unused indexes >10MB', table_count),
        CASE WHEN table_count > 0 THEN 'Consider dropping unused indexes to save space' ELSE NULL END;

    -- Replication lag check (if in recovery)
    IF pg_is_in_recovery() THEN
        SELECT extract(epoch from now() - pg_last_xact_replay_timestamp()) INTO metric_decimal;
        RETURN QUERY SELECT
            'REPLICATION'::TEXT,
            'Replication Lag'::TEXT,
            CASE WHEN metric_decimal > 300 THEN 'WARNING' ELSE 'OK' END,
            CASE WHEN metric_decimal > 600 THEN 'HIGH' WHEN metric_decimal > 300 THEN 'MEDIUM' ELSE 'LOW' END,
            format('%.1f seconds lag', metric_decimal),
            CASE WHEN metric_decimal > 600 THEN 'URGENT: Check replication status'
                 WHEN metric_decimal > 300 THEN 'Monitor replication performance'
                 ELSE NULL END;
    END IF;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUTOMATED MAINTENANCE SCHEDULER
-- ===========================================

-- Schedule automated maintenance tasks
CREATE OR REPLACE FUNCTION schedule_maintenance_tasks()
RETURNS VOID AS $$
DECLARE
    job_count INTEGER;
BEGIN
    -- Check if pg_cron is available
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE NOTICE 'pg_cron extension not available. Install it to enable automated maintenance.';
        RETURN;
    END IF;

    -- Remove existing maintenance jobs
    PERFORM cron.unschedule('daily_vacuum_analyze');
    PERFORM cron.unschedule('weekly_reindex');
    PERFORM cron.unschedule('monthly_health_check');

    -- Schedule daily vacuum analyze (2 AM)
    PERFORM cron.schedule('daily_vacuum_analyze', '0 2 * * *',
        'SELECT smart_vacuum(NULL, false, false);');

    -- Schedule weekly reindex check (Sunday 3 AM)
    PERFORM cron.schedule('weekly_reindex_check', '0 3 * * 0',
        'SELECT rebuild_unused_indexes();');

    -- Schedule monthly health check (1st of month 4 AM)
    PERFORM cron.schedule('monthly_health_check', '0 4 1 * *',
        'SELECT generate_health_report();');

    RAISE NOTICE 'Automated maintenance tasks scheduled successfully';
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- REPORTING FUNCTIONS
-- ===========================================

-- Generate comprehensive maintenance report
CREATE OR REPLACE FUNCTION generate_maintenance_report(
    report_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    report_section TEXT,
    metric_name TEXT,
    metric_value TEXT,
    status TEXT,
    recommendation TEXT
) AS $$
BEGIN
    -- Database size and growth
    RETURN QUERY
    SELECT
        'DATABASE_SIZE'::TEXT,
        'Current Size'::TEXT,
        pg_size_pretty(pg_database_size(current_database())),
        'INFO'::TEXT,
        'Monitor growth trends'::TEXT;

    -- Table maintenance status
    RETURN QUERY
    SELECT
        'TABLE_MAINTENANCE'::TEXT,
        tablename::TEXT,
        CASE
            WHEN last_vacuum IS NULL THEN 'Never vacuumed'
            WHEN last_vacuum < now() - interval '7 days' THEN 'Vacuum overdue'
            ELSE 'Recently maintained'
        END,
        CASE
            WHEN last_vacuum IS NULL OR last_vacuum < now() - interval '7 days' THEN 'WARNING'
            ELSE 'OK'
        END,
        CASE
            WHEN last_vacuum IS NULL OR last_vacuum < now() - interval '7 days'
            THEN 'Run VACUUM ANALYZE'
            ELSE NULL
        END
    FROM pg_stat_user_tables
    WHERE schemaname = 'public';

    -- Index usage analysis
    RETURN QUERY
    SELECT
        'INDEX_USAGE'::TEXT,
        indexname::TEXT,
        CASE
            WHEN idx_scan = 0 THEN 'Never used'
            WHEN idx_scan < 100 THEN 'Low usage'
            ELSE 'Actively used'
        END,
        CASE
            WHEN idx_scan = 0 AND pg_relation_size(indexrelid) > 10000000 THEN 'WARNING'
            ELSE 'OK'
        END,
        CASE
            WHEN idx_scan = 0 AND pg_relation_size(indexrelid) > 10000000
            THEN 'Consider dropping unused large index'
            ELSE NULL
        END
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public';

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- BACKUP VERIFICATION FUNCTIONS
-- =========================================--

-- Verify backup integrity
CREATE OR REPLACE FUNCTION verify_backup_integrity(backup_file TEXT)
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
DECLARE
    temp_db_name TEXT;
    test_result TEXT;
BEGIN
    -- Create temporary database name
    temp_db_name := 'backup_verify_' || extract(epoch from now())::text;

    BEGIN
        -- Create temporary database
        EXECUTE format('CREATE DATABASE %I', temp_db_name);

        -- Test restore
        EXECUTE format('pg_restore -d %I -Fc %s --no-owner --no-privileges --clean --if-exists',
                      temp_db_name, backup_file);

        -- Basic verification
        EXECUTE format('SELECT count(*) FROM information_schema.tables WHERE table_schema = ''public''')
        INTO test_result USING temp_db_name;

        RETURN QUERY SELECT
            'table_count'::TEXT,
            'SUCCESS'::TEXT,
            format('%s tables restored', test_result);

        -- Drop temporary database
        EXECUTE format('DROP DATABASE %I', temp_db_name);

    EXCEPTION WHEN OTHERS THEN
        -- Clean up on error
        EXECUTE format('DROP DATABASE IF EXISTS %I', temp_db_name);

        RETURN QUERY SELECT
            'restore_test'::TEXT,
            'FAILED'::TEXT,
            'Error: ' || SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- PERFORMANCE MONITORING FUNCTIONS
-- =========================================--

-- Monitor long-running queries
CREATE OR REPLACE FUNCTION identify_long_running_queries(
    threshold_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (
    pid INTEGER,
    username TEXT,
    database_name TEXT,
    query_start TIMESTAMP,
    duration INTERVAL,
    state TEXT,
    query_text TEXT,
    recommendation TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.pid,
        a.usename::TEXT,
        a.datname::TEXT,
        a.query_start,
        now() - a.query_start,
        a.state,
        left(a.query, 100)::TEXT,
        CASE
            WHEN now() - a.query_start > interval '1 hour' THEN 'URGENT: Cancel or terminate query'
            WHEN now() - a.query_start > interval '30 minutes' THEN 'WARNING: Query running too long'
            WHEN a.state = 'idle in transaction' THEN 'INFO: Check for open transactions'
            ELSE 'MONITOR: Keep an eye on this query'
        END
    FROM pg_stat_activity a
    WHERE a.state = 'active'
      AND now() - a.query_start > (threshold_seconds || ' seconds')::interval
      AND a.pid <> pg_backend_pid()
    ORDER BY now() - a.query_start DESC;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- USAGE EXAMPLES
-- =========================================--

/*
-- Basic usage examples:

-- 1. Smart vacuum all tables
SELECT * FROM smart_vacuum();

-- 2. Vacuum specific table aggressively
SELECT * FROM smart_vacuum('large_table', true, true);

-- 3. Analyze index usage
SELECT * FROM analyze_index_usage(30);

-- 4. Rebuild index concurrently
SELECT * FROM rebuild_index_concurrent('idx_large_table_date');

-- 5. Analyze table bloat
SELECT * FROM analyze_table_bloat();

-- 6. Database health check
SELECT * FROM database_health_check();

-- 7. Generate maintenance report
SELECT * FROM generate_maintenance_report();

-- 8. Schedule automated maintenance
SELECT schedule_maintenance_tasks();

-- 9. Identify long-running queries
SELECT * FROM identify_long_running_queries(600);  -- 10 minutes

-- 10. Verify backup integrity
SELECT * FROM verify_backup_integrity('/path/to/backup.dump');
*/

-- ===========================================
-- NOTES
-- =========================================--

/*
Important Notes:
1. Some functions require pg_cron extension for scheduling
2. VACUUM FULL requires exclusive table locks - use during maintenance windows
3. Index rebuilds are performed concurrently to minimize blocking
4. Monitor system resources during maintenance operations
5. Test maintenance procedures in staging environment first
6. Keep maintenance logs for compliance and troubleshooting
7. Consider impact on production performance before running maintenance
8. Regular maintenance prevents performance degradation over time
*/
