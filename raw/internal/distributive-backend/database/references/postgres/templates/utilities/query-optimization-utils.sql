-- PostgreSQL Query Optimization Utilities
-- Collection of functions and utilities for query performance analysis and optimization

-- ===========================================
-- QUERY PERFORMANCE ANALYSIS
-- ===========================================

-- Function to analyze query execution plan
CREATE OR REPLACE FUNCTION analyze_query_plan(
    query_text TEXT,
    analyze_query BOOLEAN DEFAULT TRUE,
    verbose_output BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    query_plan TEXT,
    execution_time INTERVAL,
    planning_time INTERVAL,
    total_cost NUMERIC,
    actual_rows BIGINT,
    actual_loops BIGINT,
    actual_time_per_call NUMERIC
) AS $$
DECLARE
    plan_result JSONB;
    explain_command TEXT;
BEGIN
    -- Build EXPLAIN command
    explain_command := 'EXPLAIN (FORMAT JSON';
    IF analyze_query THEN
        explain_command := explain_command || ', ANALYZE TRUE';
    END IF;
    IF verbose_output THEN
        explain_command := explain_command || ', VERBOSE TRUE';
    END IF;
    explain_command := explain_command || ') ' || query_text;

    -- Execute and parse the plan
    EXECUTE explain_command INTO plan_result;

    -- Extract key metrics from the plan
    RETURN QUERY
    SELECT
        plan_result::TEXT as query_plan,
        CASE WHEN analyze_query THEN
            make_interval(secs => (plan_result->0->'Execution Time')::NUMERIC / 1000)
        ELSE NULL END as execution_time,
        CASE WHEN analyze_query THEN
            make_interval(secs => (plan_result->0->'Planning Time')::NUMERIC / 1000)
        ELSE NULL END as planning_time,
        (plan_result->0->'Plan'->'Total Cost')::NUMERIC as total_cost,
        CASE WHEN analyze_query THEN
            (plan_result->0->'Plan'->'Actual Rows')::BIGINT
        ELSE NULL END as actual_rows,
        CASE WHEN analyze_query THEN
            (plan_result->0->'Plan'->'Actual Loops')::BIGINT
        ELSE NULL END as actual_loops,
        CASE WHEN analyze_query THEN
            (plan_result->0->'Plan'->'Actual Total Time')::NUMERIC /
            NULLIF((plan_result->0->'Plan'->'Actual Loops')::NUMERIC, 0)
        ELSE NULL END as actual_time_per_call;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- INDEX RECOMMENDATION SYSTEM
-- ===========================================

-- Function to analyze missing indexes based on query patterns
CREATE OR REPLACE FUNCTION analyze_missing_indexes(
    analysis_window_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    table_name TEXT,
    column_name TEXT,
    index_type TEXT,
    estimated_benefit INTEGER,
    query_count BIGINT,
    recommendation TEXT
) AS $$
DECLARE
    query_record RECORD;
    index_suggestion RECORD;
BEGIN
    -- Analyze pg_stat_user_tables for sequential scans on large tables
    FOR query_record IN
        SELECT
            schemaname,
            tablename,
            seq_scan,
            n_tup_ins + n_tup_upd + n_tup_del as total_writes,
            n_live_tup
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND seq_scan > 0
          AND n_live_tup > 10000
          AND seq_scan > (n_tup_ins + n_tup_upd + n_tup_del) * 0.1  -- More reads than writes
    LOOP
        -- Check for potential WHERE clause columns
        FOR index_suggestion IN
            EXECUTE format('
                SELECT
                    a.attname as column_name,
                    ''btree'' as index_type,
                    %s::INTEGER as estimated_benefit,
                    %s::BIGINT as query_count,
                    ''Consider adding index on '' || a.attname || '' for better query performance'' as recommendation
                FROM pg_attribute a
                JOIN pg_class c ON a.attrelid = c.oid
                JOIN pg_namespace n ON c.relnamespace = n.oid
                LEFT JOIN pg_index i ON c.oid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE n.nspname = $1
                  AND c.relname = $2
                  AND a.attnum > 0
                  AND NOT a.attisdropped
                  AND i.indisprimary IS NOT TRUE
                  AND i.indisunique IS NOT TRUE
                  AND i.indexrelid IS NULL
                  AND a.attname NOT IN (''created_at'', ''updated_at'', ''id'')
                ORDER BY a.attnum
                LIMIT 5
            ', query_record.seq_scan, query_record.seq_scan)
        USING query_record.schemaname, query_record.tablename
        LOOP
            RETURN QUERY SELECT
                query_record.tablename,
                index_suggestion.column_name,
                index_suggestion.index_type,
                index_suggestion.estimated_benefit,
                index_suggestion.query_count,
                index_suggestion.recommendation;
        END LOOP;
    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- QUERY PATTERN ANALYSIS
-- ===========================================

-- Function to identify slow queries and their patterns
CREATE OR REPLACE FUNCTION analyze_slow_queries(
    min_execution_time_ms INTEGER DEFAULT 1000,
    analysis_window_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    query_pattern TEXT,
    total_executions BIGINT,
    avg_execution_time INTERVAL,
    max_execution_time INTERVAL,
    total_execution_time INTERVAL,
    most_common_table TEXT,
    suggested_optimization TEXT
) AS $$
DECLARE
    query_group RECORD;
BEGIN
    -- Group similar queries and analyze patterns
    FOR query_group IN
        EXECUTE format('
            SELECT
                regexp_replace(query, ''\$\d+'', ''?'', ''g'') as query_pattern,
                count(*) as total_executions,
                avg(total_time / 1000) as avg_time_ms,
                max(total_time / 1000) as max_time_ms,
                sum(total_time / 1000) as total_time_ms,
                mode() WITHIN GROUP (ORDER BY query) FILTER (WHERE query LIKE ''%%FROM%%'') as sample_query
            FROM pg_stat_statements
            WHERE total_time > %s
              AND query_start > now() - interval ''%s hours''
              AND query NOT LIKE ''%%pg_stat%%''
            GROUP BY regexp_replace(query, ''\$\d+'', ''?'', ''g'')
            HAVING count(*) > 1
            ORDER BY sum(total_time) DESC
            LIMIT 20
        ', min_execution_time_ms, analysis_window_hours)
    LOOP
        RETURN QUERY
        SELECT
            query_group.query_pattern,
            query_group.total_executions,
            make_interval(secs => query_group.avg_time_ms / 1000),
            make_interval(secs => query_group.max_time_ms / 1000),
            make_interval(secs => query_group.total_time_ms / 1000),
            substring(query_group.sample_query from 'FROM\s+(\w+)') as most_common_table,
            CASE
                WHEN query_group.query_pattern LIKE '%WHERE%' AND query_group.query_pattern NOT LIKE '%INDEX%'
                THEN 'Consider adding appropriate indexes for WHERE conditions'
                WHEN query_group.query_pattern LIKE '%JOIN%' AND query_group.total_executions > 10
                THEN 'Review JOIN conditions and consider composite indexes'
                WHEN query_group.query_pattern LIKE '%ORDER BY%' AND query_group.total_executions > 5
                THEN 'Consider covering indexes for ORDER BY clauses'
                WHEN query_group.query_pattern LIKE '%COUNT(*)%'
                THEN 'Consider maintaining counts in separate tables or using approximations'
                ELSE 'Review query structure and consider query rewriting'
            END as suggested_optimization;
    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- TABLE STATISTICS ANALYSIS
-- ===========================================

-- Function to analyze table statistics freshness
CREATE OR REPLACE FUNCTION analyze_table_statistics()
RETURNS TABLE (
    schema_name TEXT,
    table_name TEXT,
    last_analyze TIMESTAMP,
    last_autoanalyze TIMESTAMP,
    n_live_tup BIGINT,
    n_dead_tup BIGINT,
    dead_tuple_ratio DECIMAL,
    statistics_status TEXT,
    recommendation TEXT
) AS $$
DECLARE
    table_record RECORD;
    days_since_analyze INTEGER;
    dead_ratio DECIMAL;
BEGIN
    FOR table_record IN
        SELECT
            schemaname,
            tablename,
            last_analyze,
            last_autoanalyze,
            n_live_tup,
            n_dead_tup,
            GREATEST(last_analyze, last_autoanalyze) as last_stats_update
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND n_live_tup > 0
    LOOP
        days_since_analyze := EXTRACT(EPOCH FROM (now() - table_record.last_stats_update)) / 86400;
        dead_ratio := CASE
            WHEN table_record.n_live_tup + table_record.n_dead_tup > 0
            THEN (table_record.n_dead_tup::DECIMAL /
                  (table_record.n_live_tup + table_record.n_dead_tup)) * 100
            ELSE 0
        END;

        RETURN QUERY
        SELECT
            table_record.schemaname,
            table_record.tablename,
            table_record.last_analyze,
            table_record.last_autoanalyze,
            table_record.n_live_tup,
            table_record.n_dead_tup,
            ROUND(dead_ratio, 2),
            CASE
                WHEN days_since_analyze > 7 THEN 'OUTDATED'
                WHEN days_since_analyze > 1 THEN 'STALE'
                WHEN dead_ratio > 20 THEN 'HIGH_DEAD_TUPLES'
                ELSE 'CURRENT'
            END,
            CASE
                WHEN days_since_analyze > 7 THEN 'Run ANALYZE on table to update statistics'
                WHEN dead_ratio > 20 THEN 'Consider VACUUM to clean up dead tuples'
                WHEN days_since_analyze > 1 THEN 'Statistics are slightly stale'
                ELSE 'Statistics are current'
            END;

    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- CONNECTION AND POOLING ANALYSIS
-- ===========================================

-- Function to analyze connection patterns
CREATE OR REPLACE FUNCTION analyze_connection_patterns(
    analysis_window_minutes INTEGER DEFAULT 60
)
RETURNS TABLE (
    metric_name TEXT,
    current_value INTEGER,
    average_value DECIMAL,
    peak_value INTEGER,
    trend TEXT,
    recommendation TEXT
) AS $$
DECLARE
    current_connections INTEGER;
    avg_connections DECIMAL;
    max_connections INTEGER;
    connection_trend TEXT;
BEGIN
    -- Current active connections
    SELECT count(*) INTO current_connections
    FROM pg_stat_activity
    WHERE state = 'active';

    -- Average connections over time window
    SELECT avg(connection_count) INTO avg_connections
    FROM (
        SELECT count(*) as connection_count
        FROM pg_stat_activity
        WHERE query_start > now() - make_interval(mins => analysis_window_minutes)
        GROUP BY extract(minute from query_start)
    ) conn_counts;

    -- Peak connections
    SELECT max(connection_count) INTO max_connections
    FROM (
        SELECT count(*) as connection_count
        FROM pg_stat_activity
        WHERE query_start > now() - make_interval(mins => analysis_window_minutes)
        GROUP BY extract(minute from query_start)
    ) conn_counts;

    -- Determine trend
    connection_trend := CASE
        WHEN current_connections > avg_connections * 1.2 THEN 'INCREASING'
        WHEN current_connections < avg_connections * 0.8 THEN 'DECREASING'
        ELSE 'STABLE'
    END;

    -- Return metrics
    RETURN QUERY
    SELECT
        'active_connections'::TEXT,
        current_connections,
        ROUND(avg_connections, 1),
        max_connections,
        connection_trend,
        CASE
            WHEN current_connections > (SELECT setting::INTEGER * 0.8 FROM pg_settings WHERE name = 'max_connections')
            THEN 'Approaching max_connections limit - consider increasing limit or implementing connection pooling'
            WHEN connection_trend = 'INCREASING'
            THEN 'Connection count is increasing - monitor for potential issues'
            ELSE 'Connection levels are normal'
        END;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- QUERY OPTIMIZATION RECOMMENDATIONS
-- ===========================================

-- Function to generate comprehensive optimization recommendations
CREATE OR REPLACE FUNCTION generate_optimization_recommendations()
RETURNS TABLE (
    category TEXT,
    priority TEXT,
    issue_description TEXT,
    impact_level TEXT,
    estimated_effort TEXT,
    sql_command TEXT
) AS $$
BEGIN
    -- Index recommendations
    INSERT INTO optimization_recommendations
    SELECT
        'INDEXING'::TEXT,
        'HIGH'::TEXT,
        'Missing index on ' || column_name || ' for table ' || table_name,
        'HIGH'::TEXT,
        'LOW'::TEXT,
        'CREATE INDEX idx_' || table_name || '_' || column_name || ' ON ' || table_name || ' (' || column_name || ');'
    FROM analyze_missing_indexes(24)
    WHERE estimated_benefit > 10;

    -- Statistics recommendations
    INSERT INTO optimization_recommendations
    SELECT
        'STATISTICS'::TEXT,
        CASE WHEN statistics_status = 'OUTDATED' THEN 'HIGH' ELSE 'MEDIUM' END,
        'Table statistics are ' || statistics_status || ' for ' || schema_name || '.' || table_name,
        CASE WHEN statistics_status = 'OUTDATED' THEN 'HIGH' ELSE 'MEDIUM' END,
        'LOW'::TEXT,
        'ANALYZE ' || schema_name || '.' || table_name || ';'
    FROM analyze_table_statistics()
    WHERE statistics_status IN ('OUTDATED', 'STALE', 'HIGH_DEAD_TUPLES');

    -- Query optimization recommendations
    INSERT INTO optimization_recommendations
    SELECT
        'QUERIES'::TEXT,
        'HIGH'::TEXT,
        'Slow query pattern: ' || left(query_pattern, 50) || '...',
        'HIGH'::TEXT,
        'MEDIUM'::TEXT,
        suggested_optimization
    FROM analyze_slow_queries(1000, 24)
    WHERE avg_execution_time > make_interval(secs => 1);

    -- Connection recommendations
    INSERT INTO optimization_recommendations
    SELECT
        'CONNECTIONS'::TEXT,
        'MEDIUM'::TEXT,
        'Connection pattern issue: ' || metric_name,
        'MEDIUM'::TEXT,
        'MEDIUM'::TEXT,
        recommendation
    FROM analyze_connection_patterns(60)
    WHERE recommendation LIKE '%consider%';

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- PERFORMANCE MONITORING DASHBOARD
-- ===========================================

-- Function to generate performance dashboard data
CREATE OR REPLACE FUNCTION generate_performance_dashboard()
RETURNS TABLE (
    metric_category TEXT,
    metric_name TEXT,
    current_value TEXT,
    trend TEXT,
    status TEXT,
    last_updated TIMESTAMP
) AS $$
BEGIN
    -- Database size
    RETURN QUERY
    SELECT
        'STORAGE'::TEXT,
        'Database Size'::TEXT,
        pg_size_pretty(pg_database_size(current_database())),
        'N/A'::TEXT,
        'INFO'::TEXT,
        now();

    -- Connection status
    RETURN QUERY
    SELECT
        'CONNECTIONS'::TEXT,
        'Active Connections'::TEXT,
        count(*)::TEXT,
        CASE WHEN count(*) > (SELECT setting::INTEGER * 0.8 FROM pg_settings WHERE name = 'max_connections')
             THEN 'HIGH' ELSE 'NORMAL' END,
        CASE WHEN count(*) > (SELECT setting::INTEGER * 0.8 FROM pg_settings WHERE name = 'max_connections')
             THEN 'WARNING' ELSE 'OK' END,
        now()
    FROM pg_stat_activity
    WHERE state = 'active';

    -- Cache hit ratio
    RETURN QUERY
    SELECT
        'PERFORMANCE'::TEXT,
        'Buffer Cache Hit Ratio'::TEXT,
        ROUND((sum(blks_hit) * 100.0) / nullif(sum(blks_hit + blks_read), 0), 1)::TEXT || '%',
        'N/A'::TEXT,
        CASE WHEN (sum(blks_hit) * 100.0) / nullif(sum(blks_hit + blks_read), 0) < 95 THEN 'WARNING' ELSE 'OK' END,
        now()
    FROM pg_stat_database;

    -- Slow queries count
    RETURN QUERY
    SELECT
        'QUERIES'::TEXT,
        'Slow Queries (>1s)'::TEXT,
        count(*)::TEXT,
        'N/A'::TEXT,
        CASE WHEN count(*) > 10 THEN 'WARNING' ELSE 'OK' END,
        now()
    FROM pg_stat_statements
    WHERE total_time / calls > 1000;

    -- Index usage
    RETURN QUERY
    SELECT
        'INDEXES'::TEXT,
        'Unused Indexes'::TEXT,
        count(*)::TEXT,
        'N/A'::TEXT,
        CASE WHEN count(*) > 5 THEN 'WARNING' ELSE 'OK' END,
        now()
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0 AND pg_relation_size(indexrelid) > 10000000;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUTOMATED QUERY ANALYSIS
-- ===========================================

-- Function to analyze and optimize specific queries
CREATE OR REPLACE FUNCTION analyze_and_optimize_query(
    query_id_param BIGINT DEFAULT NULL,
    min_calls INTEGER DEFAULT 10
)
RETURNS TABLE (
    query_text TEXT,
    execution_stats JSONB,
    optimization_suggestions JSONB,
    estimated_improvement TEXT
) AS $$
DECLARE
    query_record RECORD;
    plan_analysis JSONB;
    suggestions JSONB := '[]';
BEGIN
    -- Get query from pg_stat_statements or use provided ID
    FOR query_record IN
        SELECT
            queryid,
            query,
            calls,
            total_time,
            mean_time,
            rows,
            shared_blks_hit,
            shared_blks_read,
            temp_blks_written
        FROM pg_stat_statements
        WHERE (query_id_param IS NULL OR queryid = query_id_param)
          AND calls >= min_calls
          AND query NOT LIKE '%pg_stat%'
        ORDER BY mean_time DESC
        LIMIT 5
    LOOP
        -- Analyze execution plan
        BEGIN
            SELECT plan_data INTO plan_analysis
            FROM analyze_query_plan(query_record.query, true, false) AS plan_data;
        EXCEPTION WHEN OTHERS THEN
            plan_analysis := '{"error": "Could not analyze plan"}'::JSONB;
        END;

        -- Generate suggestions based on query patterns
        suggestions := '[]'::JSONB;

        -- Check for sequential scans
        IF query_record.query LIKE '%FROM%' AND query_record.shared_blks_read > query_record.shared_blks_hit THEN
            suggestions := suggestions || jsonb_build_object(
                'type', 'INDEX',
                'suggestion', 'Consider adding indexes for WHERE conditions',
                'impact', 'HIGH'
            );
        END IF;

        -- Check for temporary file usage
        IF query_record.temp_blks_written > 0 THEN
            suggestions := suggestions || jsonb_build_object(
                'type', 'MEMORY',
                'suggestion', 'Query uses temporary files - consider increasing work_mem',
                'impact', 'MEDIUM'
            );
        END IF;

        -- Check for low row count vs execution time
        IF query_record.rows < 100 AND query_record.mean_time > 100 THEN
            suggestions := suggestions || jsonb_build_object(
                'type', 'OPTIMIZATION',
                'suggestion', 'Query returns few rows but takes long - check for inefficient joins',
                'impact', 'HIGH'
            );
        END IF;

        RETURN QUERY
        SELECT
            query_record.query,
            jsonb_build_object(
                'calls', query_record.calls,
                'total_time_ms', ROUND(query_record.total_time::NUMERIC, 2),
                'mean_time_ms', ROUND(query_record.mean_time::NUMERIC, 2),
                'rows_returned', query_record.rows,
                'cache_hit_ratio', CASE
                    WHEN query_record.shared_blks_hit + query_record.shared_blks_read > 0
                    THEN ROUND((query_record.shared_blks_hit::NUMERIC /
                              (query_record.shared_blks_hit + query_record.shared_blks_read)) * 100, 1)
                    ELSE 100
                END,
                'temp_files_mb', ROUND((query_record.temp_blks_written * 8192)::NUMERIC / 1024 / 1024, 2)
            ),
            suggestions,
            CASE
                WHEN jsonb_array_length(suggestions) > 0 THEN 'POTENTIAL IMPROVEMENT'
                ELSE 'ANALYSIS COMPLETE'
            END;

    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- USAGE EXAMPLES
-- =========================================--

/*
-- Basic usage examples:

-- 1. Analyze a specific query plan
SELECT * FROM analyze_query_plan('SELECT * FROM users WHERE email = ''test@example.com''', true, true);

-- 2. Get index recommendations
SELECT * FROM analyze_missing_indexes(24);

-- 3. Analyze slow queries
SELECT * FROM analyze_slow_queries(1000, 24);

-- 4. Check table statistics
SELECT * FROM analyze_table_statistics();

-- 5. Analyze connection patterns
SELECT * FROM analyze_connection_patterns(60);

-- 6. Generate performance dashboard
SELECT * FROM generate_performance_dashboard();

-- 7. Analyze and optimize specific queries
SELECT * FROM analyze_and_optimize_query(NULL, 5);

-- 8. Get comprehensive optimization recommendations
SELECT * FROM generate_optimization_recommendations();
SELECT * FROM optimization_recommendations ORDER BY priority, category;
*/

-- ===========================================
-- NOTES
-- =========================================--

/*
Important Notes:
1. These functions require appropriate permissions to access system catalogs
2. Some functions may require pg_stat_statements extension
3. Query analysis can be resource-intensive on production systems
4. Recommendations are suggestions - always test before implementing
5. Monitor system performance when running analysis functions
6. Consider running analysis during off-peak hours
7. Store historical analysis data for trend analysis
8. Use EXPLAIN plans for detailed query analysis before optimization
*/
