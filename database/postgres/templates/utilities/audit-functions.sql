-- PostgreSQL Audit Functions Utility
-- Collection of reusable audit and logging functions for PostgreSQL databases

-- ===========================================
-- AUDIT TABLE CREATION
-- ===========================================

-- Create audit table if it doesn't exist
CREATE OR REPLACE FUNCTION create_audit_table(
    target_schema TEXT DEFAULT 'public',
    target_table TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    audit_table_name TEXT;
    create_sql TEXT;
BEGIN
    -- If no specific table, create generic audit table
    IF target_table IS NULL THEN
        audit_table_name := 'audit_log';
    ELSE
        audit_table_name := target_table || '_audit';
    END IF;

    -- Create audit table
    create_sql := format('
        CREATE TABLE IF NOT EXISTS %I.%I (
            audit_id SERIAL PRIMARY KEY,
            table_name TEXT NOT NULL,
            record_id TEXT,
            operation TEXT NOT NULL CHECK (operation IN (''INSERT'', ''UPDATE'', ''DELETE'')),
            old_values JSONB,
            new_values JSONB,
            changed_by TEXT,
            changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            client_ip INET,
            session_user TEXT DEFAULT session_user,
            transaction_id BIGINT DEFAULT txid_current()
        ) PARTITION BY RANGE (changed_at)',
        target_schema, audit_table_name
    );

    EXECUTE create_sql;

    -- Create index on commonly queried fields
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_table_record ON %I.%I (table_name, record_id)',
                  audit_table_name, target_schema, audit_table_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_changed_at ON %I.%I (changed_at DESC)',
                  audit_table_name, target_schema, audit_table_name);

    RAISE NOTICE 'Created audit table: %I.%I', target_schema, audit_table_name;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- GENERIC AUDIT TRIGGER
-- ===========================================

-- Generic audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    audit_table_name TEXT;
    insert_sql TEXT;
    old_data JSONB;
    new_data JSONB;
    record_id TEXT;
BEGIN
    -- Determine audit table name
    audit_table_name := TG_TABLE_NAME || '_audit';

    -- Get record identifier (try common primary key patterns)
    record_id := COALESCE(
        NEW.id::TEXT,
        NEW.uuid::TEXT,
        NEW.user_id::TEXT || '_' || NEW.id::TEXT,
        'unknown'
    );

    -- Prepare old and new data
    old_data := CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::JSONB ELSE NULL END;
    new_data := CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::JSONB ELSE NULL END;

    -- Build insert statement
    insert_sql := format('
        INSERT INTO %I (table_name, record_id, operation, old_values, new_values, changed_by, client_ip)
        VALUES ($1, $2, $3, $4, $5, $6, $7)',
        audit_table_name
    );

    -- Execute audit insert
    EXECUTE insert_sql
    USING TG_TABLE_NAME, record_id, TG_OP, old_data, new_data,
          current_setting('app.current_user_id', TRUE), inet_client_addr();

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Function to create audit trigger for a table
CREATE OR REPLACE FUNCTION create_audit_trigger(
    target_schema TEXT DEFAULT 'public',
    target_table TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    trigger_name TEXT;
    audit_table_name TEXT;
BEGIN
    -- Use current table if none specified
    IF target_table IS NULL THEN
        target_table := TG_TABLE_NAME;
    END IF;

    trigger_name := 'audit_' || target_table || '_trigger';
    audit_table_name := target_table || '_audit';

    -- Create audit table if it doesn't exist
    PERFORM create_audit_table(target_schema, target_table);

    -- Drop existing trigger if it exists
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
                  trigger_name, target_schema, target_table);

    -- Create new trigger
    EXECUTE format('
        CREATE TRIGGER %I
            AFTER INSERT OR UPDATE OR DELETE ON %I.%I
            FOR EACH ROW EXECUTE FUNCTION audit_trigger_function()',
        trigger_name, target_schema, target_table
    );

    RAISE NOTICE 'Created audit trigger: % on table: %I.%I', trigger_name, target_schema, target_table;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUDIT QUERY FUNCTIONS
-- ===========================================

-- Get audit history for a specific record
CREATE OR REPLACE FUNCTION get_audit_history(
    target_table TEXT,
    record_identifier TEXT,
    limit_records INTEGER DEFAULT 100
)
RETURNS TABLE (
    audit_id INTEGER,
    operation TEXT,
    old_values JSONB,
    new_values JSONB,
    changed_by TEXT,
    changed_at TIMESTAMP WITH TIME ZONE,
    client_ip INET
) AS $$
DECLARE
    audit_table_name TEXT;
BEGIN
    audit_table_name := target_table || '_audit';

    RETURN QUERY EXECUTE format('
        SELECT audit_id, operation, old_values, new_values, changed_by, changed_at, client_ip
        FROM %I
        WHERE table_name = $1 AND record_id = $2
        ORDER BY changed_at DESC
        LIMIT $3',
        audit_table_name
    ) USING target_table, record_identifier, limit_records;
END;
$$ LANGUAGE plpgsql;

-- Get audit summary for a table
CREATE OR REPLACE FUNCTION get_audit_summary(
    target_table TEXT,
    days_back INTEGER DEFAULT 30
)
RETURNS TABLE (
    date DATE,
    total_changes BIGINT,
    inserts BIGINT,
    updates BIGINT,
    deletes BIGINT,
    unique_users BIGINT
) AS $$
DECLARE
    audit_table_name TEXT;
BEGIN
    audit_table_name := target_table || '_audit';

    RETURN QUERY EXECUTE format('
        SELECT
            DATE(changed_at) as date,
            COUNT(*) as total_changes,
            COUNT(CASE WHEN operation = ''INSERT'' THEN 1 END) as inserts,
            COUNT(CASE WHEN operation = ''UPDATE'' THEN 1 END) as updates,
            COUNT(CASE WHEN operation = ''DELETE'' THEN 1 END) as deletes,
            COUNT(DISTINCT changed_by) as unique_users
        FROM %I
        WHERE table_name = $1
          AND changed_at >= CURRENT_DATE - INTERVAL ''%s days''
        GROUP BY DATE(changed_at)
        ORDER BY date DESC',
        audit_table_name, days_back
    ) USING target_table;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUDIT CLEANUP FUNCTIONS
-- ===========================================

-- Clean old audit records
CREATE OR REPLACE FUNCTION cleanup_audit_logs(
    target_table TEXT,
    retention_days INTEGER DEFAULT 365
)
RETURNS INTEGER AS $$
DECLARE
    audit_table_name TEXT;
    deleted_count INTEGER;
BEGIN
    audit_table_name := target_table || '_audit';

    EXECUTE format('
        DELETE FROM %I
        WHERE table_name = $1
          AND changed_at < CURRENT_DATE - INTERVAL ''%s days''',
        audit_table_name, retention_days
    ) USING target_table;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    RAISE NOTICE 'Cleaned up % audit records from table: %', deleted_count, audit_table_name;

    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Automated audit cleanup scheduler
CREATE OR REPLACE FUNCTION schedule_audit_cleanup(
    retention_days INTEGER DEFAULT 365,
    cleanup_interval_days INTEGER DEFAULT 30
)
RETURNS VOID AS $$
DECLARE
    job_name TEXT := 'audit_cleanup_job';
BEGIN
    -- Remove existing job if it exists
    PERFORM cron.unschedule(job_name);

    -- Schedule new cleanup job
    PERFORM cron.schedule(
        job_name,
        format('0 2 */%s * *', cleanup_interval_days),  -- Every N days at 2 AM
        format('SELECT cleanup_all_audit_logs(%s);', retention_days)
    );

    RAISE NOTICE 'Scheduled audit cleanup job to run every % days with % days retention',
                 cleanup_interval_days, retention_days;
END;
$$ LANGUAGE plpgsql;

-- Cleanup all audit logs across tables
CREATE OR REPLACE FUNCTION cleanup_all_audit_logs(retention_days INTEGER DEFAULT 365)
RETURNS TABLE (table_name TEXT, records_deleted INTEGER) AS $$
DECLARE
    audit_table RECORD;
    deleted_count INTEGER;
BEGIN
    FOR audit_table IN
        SELECT tablename
        FROM pg_tables
        WHERE tablename LIKE '%_audit'
          AND schemaname = 'public'
    LOOP
        -- Extract base table name
        SELECT substring(audit_table.tablename from 1 for length(audit_table.tablename) - 6) INTO table_name;

        SELECT cleanup_audit_logs(table_name, retention_days) INTO deleted_count;

        RETURN QUERY SELECT table_name, deleted_count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUDIT REPORTING FUNCTIONS
-- ===========================================

-- Generate audit compliance report
CREATE OR REPLACE FUNCTION generate_audit_report(
    start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    table_name TEXT,
    total_changes BIGINT,
    inserts BIGINT,
    updates BIGINT,
    deletes BIGINT,
    unique_users BIGINT,
    most_active_user TEXT,
    date_range TEXT
) AS $$
DECLARE
    audit_table RECORD;
    report_record RECORD;
BEGIN
    FOR audit_table IN
        SELECT tablename
        FROM pg_tables
        WHERE tablename LIKE '%_audit'
          AND schemaname = 'public'
    LOOP
        -- Extract base table name
        SELECT substring(audit_table.tablename from 1 for length(audit_table.tablename) - 6) INTO table_name;

        EXECUTE format('
            SELECT
                $1 as table_name,
                COUNT(*) as total_changes,
                COUNT(CASE WHEN operation = ''INSERT'' THEN 1 END) as inserts,
                COUNT(CASE WHEN operation = ''UPDATE'' THEN 1 END) as updates,
                COUNT(CASE WHEN operation = ''DELETE'' THEN 1 END) as deletes,
                COUNT(DISTINCT changed_by) as unique_users,
                (SELECT changed_by FROM %I
                 WHERE table_name = $1 AND changed_at >= $2 AND changed_at <= $3
                 GROUP BY changed_by ORDER BY COUNT(*) DESC LIMIT 1) as most_active_user,
                $4 as date_range
            FROM %I
            WHERE table_name = $1 AND changed_at >= $2 AND changed_at <= $3',
            audit_table.tablename, audit_table.tablename
        ) INTO report_record
        USING table_name, start_date, end_date, format('%s to %s', start_date, end_date);

        -- Only return tables with activity
        IF report_record.total_changes > 0 THEN
            RETURN QUERY SELECT report_record.*;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUDIT MONITORING FUNCTIONS
-- ===========================================

-- Monitor audit table sizes
CREATE OR REPLACE FUNCTION get_audit_table_sizes()
RETURNS TABLE (
    table_name TEXT,
    audit_table_name TEXT,
    main_table_size TEXT,
    audit_table_size TEXT,
    audit_ratio DECIMAL
) AS $$
DECLARE
    audit_table RECORD;
BEGIN
    FOR audit_table IN
        SELECT
            t.tablename as audit_table,
            substring(t.tablename from 1 for length(t.tablename) - 6) as base_table,
            pg_size_pretty(pg_total_relation_size(t.tablename::regclass)) as audit_size
        FROM pg_tables t
        WHERE t.tablename LIKE '%_audit'
          AND t.schemaname = 'public'
    LOOP
        RETURN QUERY
        SELECT
            audit_table.base_table,
            audit_table.audit_table,
            COALESCE(pg_size_pretty(pg_total_relation_size((audit_table.base_table)::regclass)), 'N/A'),
            audit_table.audit_size,
            CASE
                WHEN pg_total_relation_size((audit_table.base_table)::regclass) > 0
                THEN ROUND(
                    pg_total_relation_size(audit_table.audit_table::regclass)::DECIMAL /
                    pg_total_relation_size((audit_table.base_table)::regclass) * 100, 2
                )
                ELSE 0
            END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Check audit system health
CREATE OR REPLACE FUNCTION check_audit_system_health()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    recommendation TEXT
) AS $$
DECLARE
    audit_table_count INTEGER;
    total_audit_records BIGINT;
    oldest_audit_record TIMESTAMP;
    newest_audit_record TIMESTAMP;
BEGIN
    -- Check if audit tables exist
    SELECT COUNT(*) INTO audit_table_count
    FROM pg_tables
    WHERE tablename LIKE '%_audit' AND schemaname = 'public';

    IF audit_table_count = 0 THEN
        RETURN QUERY SELECT
            'audit_tables_exist'::TEXT,
            'CRITICAL'::TEXT,
            'No audit tables found'::TEXT,
            'Run create_audit_table() for tables requiring audit'::TEXT;
    ELSE
        RETURN QUERY SELECT
            'audit_tables_exist'::TEXT,
            'OK'::TEXT,
            format('%s audit tables found', audit_table_count)::TEXT,
            NULL::TEXT;
    END IF;

    -- Check audit record counts
    SELECT
        COALESCE(SUM(n_tup_ins), 0),
        MIN(min_changed_at),
        MAX(max_changed_at)
    INTO total_audit_records, oldest_audit_record, newest_audit_record
    FROM (
        SELECT
            (SELECT reltuples::BIGINT FROM pg_class WHERE oid = (tablename::regclass))
            as n_tup_ins,
            (SELECT MIN(changed_at) FROM audit_table_name) as min_changed_at,
            (SELECT MAX(changed_at) FROM audit_table_name) as max_changed_at
        FROM (
            SELECT tablename::TEXT as audit_table_name
            FROM pg_tables
            WHERE tablename LIKE '%_audit' AND schemaname = 'public'
        ) t
    ) stats;

    IF total_audit_records = 0 THEN
        RETURN QUERY SELECT
            'audit_records_exist'::TEXT,
            'WARNING'::TEXT,
            'No audit records found'::TEXT,
            'Verify audit triggers are functioning'::TEXT;
    ELSE
        RETURN QUERY SELECT
            'audit_records_exist'::TEXT,
            'OK'::TEXT,
            format('%s total audit records, date range: %s to %s',
                   total_audit_records,
                   oldest_audit_record,
                   newest_audit_record)::TEXT,
            NULL::TEXT;
    END IF;

    -- Check for missing triggers
    FOR audit_table IN
        SELECT
            substring(tablename from 1 for length(tablename) - 6) as base_table,
            tablename as audit_table
        FROM pg_tables
        WHERE tablename LIKE '%_audit' AND schemaname = 'public'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            JOIN pg_class c ON t.tgrelid = c.oid
            WHERE c.relname = audit_table.base_table
              AND t.tgname LIKE 'audit_%'
        ) THEN
            RETURN QUERY SELECT
                'audit_triggers_exist'::TEXT,
                'WARNING'::TEXT,
                format('Missing audit trigger for table: %s', audit_table.base_table)::TEXT,
                format('Run: SELECT create_audit_trigger(''public'', ''%s'');', audit_table.base_table)::TEXT;
        END IF;
    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- USAGE EXAMPLES
-- ===========================================

/*
-- Basic usage examples:

-- 1. Create audit table for a specific table
SELECT create_audit_table('public', 'users');

-- 2. Create audit trigger for a table
SELECT create_audit_trigger('public', 'users');

-- 3. Get audit history for a record
SELECT * FROM get_audit_history('users', '123');

-- 4. Get audit summary for a table
SELECT * FROM get_audit_summary('users', 30);

-- 5. Generate audit compliance report
SELECT * FROM generate_audit_report();

-- 6. Clean old audit records
SELECT cleanup_audit_logs('users', 90);

-- 7. Schedule automated cleanup
SELECT schedule_audit_cleanup(365, 30);

-- 8. Check audit system health
SELECT * FROM check_audit_system_health();

-- 9. Monitor audit table sizes
SELECT * FROM get_audit_table_sizes();
*/

-- ===========================================
-- NOTES
-- ===========================================

/*
Important Notes:
1. These functions require the pg_cron extension for automated cleanup scheduling
2. Audit tables can grow very large - implement appropriate retention policies
3. Consider partitioning audit tables by date for better performance
4. Audit triggers add overhead - monitor performance impact
5. Ensure proper permissions for audit table access
6. Consider encrypting sensitive audit data
7. Regularly backup audit tables separately
8. Monitor disk space usage of audit tables
*/
