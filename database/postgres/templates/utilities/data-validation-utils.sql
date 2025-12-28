-- PostgreSQL Data Validation and Integrity Utilities
-- Collection of functions for data quality assurance, integrity checking, and validation

-- ===========================================
-- DATA INTEGRITY CHECK FUNCTIONS
-- =========================================--

-- Function to check foreign key integrity
CREATE OR REPLACE FUNCTION check_foreign_key_integrity(
    check_all_tables BOOLEAN DEFAULT FALSE,
    specific_table TEXT DEFAULT NULL
)
RETURNS TABLE (
    table_name TEXT,
    column_name TEXT,
    referenced_table TEXT,
    referenced_column TEXT,
    orphaned_records BIGINT,
    status TEXT,
    recommendation TEXT
) AS $$
DECLARE
    fk_record RECORD;
    orphan_count BIGINT;
    check_query TEXT;
BEGIN
    FOR fk_record IN
        SELECT
            tc.table_name,
            kcu.column_name,
            ccu.table_name as referenced_table,
            ccu.column_name as referenced_column,
            tc.constraint_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = 'public'
          AND (check_all_tables OR tc.table_name = specific_table)
    LOOP
        -- Build query to check for orphaned records
        check_query := format('
            SELECT COUNT(*) FROM %I t1
            LEFT JOIN %I t2 ON t1.%I = t2.%I
            WHERE t2.%I IS NULL',
            fk_record.table_name,
            fk_record.referenced_table,
            fk_record.column_name,
            fk_record.referenced_column,
            fk_record.referenced_column
        );

        EXECUTE check_query INTO orphan_count;

        RETURN QUERY
        SELECT
            fk_record.table_name,
            fk_record.column_name,
            fk_record.referenced_table,
            fk_record.referenced_column,
            orphan_count,
            CASE
                WHEN orphan_count = 0 THEN 'VALID'
                WHEN orphan_count < 100 THEN 'WARNING'
                ELSE 'CRITICAL'
            END,
            CASE
                WHEN orphan_count = 0 THEN 'Foreign key integrity is valid'
                WHEN orphan_count < 100 THEN 'Small number of orphaned records found - review data'
                ELSE 'Large number of orphaned records - immediate data cleanup required'
            END;

    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- DATA QUALITY VALIDATION
-- =========================================--

-- Function to validate email formats
CREATE OR REPLACE FUNCTION validate_email_formats(
    target_table TEXT,
    email_column TEXT
)
RETURNS TABLE (
    total_records BIGINT,
    valid_emails BIGINT,
    invalid_emails BIGINT,
    null_emails BIGINT,
    validity_percentage DECIMAL,
    sample_invalid TEXT[]
) AS $$
DECLARE
    stats_record RECORD;
    invalid_samples TEXT[];
BEGIN
    -- Get validation statistics
    EXECUTE format('
        SELECT
            COUNT(*) as total,
            COUNT(CASE WHEN %I ~* ''^[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'' THEN 1 END) as valid,
            COUNT(CASE WHEN %I !~* ''^[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'' AND %I IS NOT NULL THEN 1 END) as invalid,
            COUNT(CASE WHEN %I IS NULL THEN 1 END) as null_count
        FROM %I',
        email_column, email_column, email_column, email_column, target_table
    ) INTO stats_record;

    -- Get sample of invalid emails
    EXECUTE format('
        SELECT array_agg(%I) FROM (
            SELECT %I
            FROM %I
            WHERE %I !~* ''^[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$''
              AND %I IS NOT NULL
            LIMIT 5
        ) samples',
        email_column, email_column, target_table, email_column, email_column
    ) INTO invalid_samples;

    RETURN QUERY
    SELECT
        stats_record.total,
        stats_record.valid,
        stats_record.invalid,
        stats_record.null_count,
        ROUND((stats_record.valid::DECIMAL / NULLIF(stats_record.total, 0)) * 100, 2),
        invalid_samples;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- DUPLICATE DATA DETECTION
-- =========================================--

-- Function to find duplicate records based on specified columns
CREATE OR REPLACE FUNCTION find_duplicate_records(
    target_table TEXT,
    duplicate_columns TEXT[],
    min_duplicates INTEGER DEFAULT 2
)
RETURNS TABLE (
    duplicate_group TEXT,
    record_count BIGINT,
    sample_ids TEXT[],
    sample_values JSONB
) AS $$
DECLARE
    column_list TEXT;
    group_by_clause TEXT;
    query_text TEXT;
BEGIN
    -- Build column list and group by clause
    column_list := array_to_string(duplicate_columns, ', ');
    group_by_clause := 'GROUP BY ' || column_list;

    -- Build the main query
    query_text := format('
        SELECT
            %s as duplicate_group,
            COUNT(*) as record_count,
            array_agg(id ORDER BY id LIMIT 5) as sample_ids,
            jsonb_agg(
                jsonb_build_object(%s) ORDER BY id LIMIT 1
            ) as sample_values
        FROM %I
        WHERE %s IS NOT NULL
        %s
        HAVING COUNT(*) >= %s
        ORDER BY record_count DESC',
        column_list,
        '''' || array_to_string(
            (SELECT array_agg(format('''%s'', %I', col, col))
             FROM unnest(duplicate_columns) as col), ', '
        ) || '''',
        (SELECT string_agg(col || ' IS NOT NULL', ' AND ')
         FROM unnest(duplicate_columns) as col),
        group_by_clause,
        min_duplicates
    );

    -- Execute the dynamic query
    RETURN QUERY EXECUTE query_text;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- DATA CONSISTENCY CHECKS
-- =========================================--

-- Function to check data consistency across related tables
CREATE OR REPLACE FUNCTION check_data_consistency()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    affected_records BIGINT,
    recommendation TEXT
) AS $$
DECLARE
    check_result RECORD;
BEGIN
    -- Check for users without profiles
    SELECT COUNT(*) INTO check_result.affected_records
    FROM users u
    LEFT JOIN user_profiles up ON u.user_id = up.user_id
    WHERE up.profile_id IS NULL;

    RETURN QUERY SELECT
        'Users without profiles'::TEXT,
        CASE WHEN check_result.affected_records = 0 THEN 'OK' ELSE 'WARNING' END,
        format('%s users missing profiles', check_result.affected_records),
        check_result.affected_records,
        CASE WHEN check_result.affected_records > 0
             THEN 'Consider creating profiles for users or updating application logic'
             ELSE 'All users have profiles' END;

    -- Check for orders without customers
    SELECT COUNT(*) INTO check_result.affected_records
    FROM orders o
    LEFT JOIN users u ON o.user_id = u.user_id
    WHERE u.user_id IS NULL;

    RETURN QUERY SELECT
        'Orders without valid customers'::TEXT,
        CASE WHEN check_result.affected_records = 0 THEN 'OK' ELSE 'CRITICAL' END,
        format('%s orders with invalid customer references', check_result.affected_records),
        check_result.affected_records,
        CASE WHEN check_result.affected_records > 0
             THEN 'URGENT: Fix customer references in orders table'
             ELSE 'All orders have valid customers' END;

    -- Check for negative inventory
    SELECT COUNT(*) INTO check_result.affected_records
    FROM inventory_items
    WHERE quantity_available < 0;

    RETURN QUERY SELECT
        'Negative inventory levels'::TEXT,
        CASE WHEN check_result.affected_records = 0 THEN 'OK' ELSE 'CRITICAL' END,
        format('%s inventory items with negative quantities', check_result.affected_records),
        check_result.affected_records,
        CASE WHEN check_result.affected_records > 0
             THEN 'URGENT: Correct negative inventory levels'
             ELSE 'All inventory levels are valid' END;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- DATA TYPE VALIDATION
-- =========================================--

-- Function to validate data types and constraints
CREATE OR REPLACE FUNCTION validate_data_types(
    target_table TEXT DEFAULT NULL
)
RETURNS TABLE (
    table_name TEXT,
    column_name TEXT,
    data_type TEXT,
    constraint_name TEXT,
    constraint_type TEXT,
    violations BIGINT,
    sample_violations TEXT[]
) AS $$
DECLARE
    column_record RECORD;
    violation_query TEXT;
    violation_count BIGINT;
    violation_samples TEXT[];
BEGIN
    FOR column_record IN
        SELECT
            c.table_name,
            c.column_name,
            c.data_type,
            tc.constraint_name,
            tc.constraint_type,
            c.table_schema
        FROM information_schema.columns c
        LEFT JOIN information_schema.key_column_usage kcu
            ON c.table_name = kcu.table_name
            AND c.column_name = kcu.column_name
            AND c.table_schema = kcu.table_schema
        LEFT JOIN information_schema.table_constraints tc
            ON kcu.constraint_name = tc.constraint_name
            AND kcu.table_schema = tc.table_schema
        WHERE c.table_schema = 'public'
          AND (target_table IS NULL OR c.table_name = target_table)
          AND c.data_type IN ('integer', 'numeric', 'decimal', 'date', 'timestamp', 'boolean')
    LOOP
        -- Check for invalid data based on type
        CASE column_record.data_type
            WHEN 'integer', 'numeric', 'decimal' THEN
                violation_query := format('
                    SELECT COUNT(*), array_agg(LEFT(%I::TEXT, 50) ORDER BY %I LIMIT 3)
                    FROM %I
                    WHERE %I !~ ''^-?\d+(\.\d+)?$'' AND %I IS NOT NULL',
                    column_record.column_name, column_record.column_name,
                    column_record.table_name, column_record.column_name, column_record.column_name
                );
            WHEN 'date', 'timestamp' THEN
                violation_query := format('
                    SELECT COUNT(*), array_agg(LEFT(%I::TEXT, 50) ORDER BY %I LIMIT 3)
                    FROM %I
                    WHERE %I::TEXT !~ ''^\d{4}-\d{2}-\d{2}'' AND %I IS NOT NULL',
                    column_record.column_name, column_record.column_name,
                    column_record.table_name, column_record.column_name, column_record.column_name
                );
            WHEN 'boolean' THEN
                violation_query := format('
                    SELECT COUNT(*), array_agg(LEFT(%I::TEXT, 50) ORDER BY %I LIMIT 3)
                    FROM %I
                    WHERE %I::TEXT NOT IN (''true'', ''false'') AND %I IS NOT NULL',
                    column_record.column_name, column_record.column_name,
                    column_record.table_name, column_record.column_name, column_record.column_name
                );
            ELSE
                CONTINUE;
        END CASE;

        -- Execute validation query
        EXECUTE violation_query INTO violation_count, violation_samples;

        IF violation_count > 0 THEN
            RETURN QUERY SELECT
                column_record.table_name,
                column_record.column_name,
                column_record.data_type,
                column_record.constraint_name,
                column_record.constraint_type,
                violation_count,
                violation_samples;
        END IF;

    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- BUSINESS RULE VALIDATION
-- =========================================--

-- Function to validate business rules
CREATE OR REPLACE FUNCTION validate_business_rules()
RETURNS TABLE (
    rule_name TEXT,
    rule_description TEXT,
    violations BIGINT,
    severity TEXT,
    sample_violations JSONB,
    corrective_action TEXT
) AS $$
DECLARE
    violation_count BIGINT;
    violation_samples JSONB;
BEGIN
    -- Rule 1: Orders should not have future dates
    SELECT COUNT(*), jsonb_agg(
        jsonb_build_object('order_id', order_id, 'order_date', order_date)
        ORDER BY order_date DESC LIMIT 3
    )
    INTO violation_count, violation_samples
    FROM orders
    WHERE order_date > CURRENT_DATE + INTERVAL '1 day';

    RETURN QUERY SELECT
        'Future order dates'::TEXT,
        'Orders should not have dates more than 1 day in the future'::TEXT,
        violation_count,
        'MEDIUM'::TEXT,
        violation_samples,
        'Review and correct order dates'::TEXT;

    -- Rule 2: Products should have positive prices
    SELECT COUNT(*), jsonb_agg(
        jsonb_build_object('product_id', product_id, 'price', price)
        ORDER BY price LIMIT 3
    )
    INTO violation_count, violation_samples
    FROM product_variants
    WHERE price <= 0;

    RETURN QUERY SELECT
        'Invalid product prices'::TEXT,
        'Products should have positive prices'::TEXT,
        violation_count,
        'HIGH'::TEXT,
        violation_samples,
        'Correct product prices to positive values'::TEXT;

    -- Rule 3: Users should have valid email domains
    SELECT COUNT(*), jsonb_agg(
        jsonb_build_object('user_id', user_id, 'email', email)
        ORDER BY user_id LIMIT 3
    )
    INTO violation_count, violation_samples
    FROM users
    WHERE email LIKE '%@%' AND email ~ '@(test\.|example\.|invalid\.)';

    RETURN QUERY SELECT
        'Invalid email domains'::TEXT,
        'User emails should not use test or invalid domains'::TEXT,
        violation_count,
        'LOW'::TEXT,
        violation_samples,
        'Replace test emails with valid addresses'::TEXT;

    -- Rule 4: Inventory levels should not exceed capacity
    SELECT COUNT(*), jsonb_agg(
        jsonb_build_object(
            'inventory_item_id', inventory_item_id,
            'quantity', quantity_available,
            'location', location_id
        ) ORDER BY quantity_available DESC LIMIT 3
    )
    INTO violation_count, violation_samples
    FROM inventory_items ii
    JOIN storage_locations sl ON ii.storage_location_id = sl.storage_location_id
    WHERE ii.quantity_available > sl.max_items;

    RETURN QUERY SELECT
        'Inventory exceeds capacity'::TEXT,
        'Inventory quantities should not exceed storage location capacity'::TEXT,
        violation_count,
        'HIGH'::TEXT,
        violation_samples,
        'Redistribute inventory to appropriate locations'::TEXT;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- DATA ANOMALY DETECTION
-- =========================================--

-- Function to detect statistical anomalies in numeric data
CREATE OR REPLACE FUNCTION detect_data_anomalies(
    target_table TEXT,
    target_column TEXT,
    threshold_stddev DECIMAL DEFAULT 3.0
)
RETURNS TABLE (
    table_name TEXT,
    column_name TEXT,
    record_id TEXT,
    value DECIMAL,
    z_score DECIMAL,
    anomaly_type TEXT,
    confidence TEXT
) AS $$
DECLARE
    stats_record RECORD;
    value_record RECORD;
    mean_val DECIMAL;
    stddev_val DECIMAL;
    zscore_val DECIMAL;
BEGIN
    -- Calculate column statistics
    EXECUTE format('
        SELECT
            AVG(%I)::DECIMAL as mean_val,
            STDDEV(%I)::DECIMAL as stddev_val,
            COUNT(*) as total_records
        FROM %I
        WHERE %I IS NOT NULL',
        target_column, target_column, target_table, target_column
    ) INTO stats_record;

    mean_val := stats_record.mean_val;
    stddev_val := stats_record.stddev_val;

    -- Find anomalies
    FOR value_record IN
        EXECUTE format('
            SELECT id::TEXT as record_id, %I::DECIMAL as value
            FROM %I
            WHERE %I IS NOT NULL',
            target_column, target_table, target_column
        )
    LOOP
        -- Calculate z-score
        zscore_val := (value_record.value - mean_val) / NULLIF(stddev_val, 0);

        -- Check if it's an anomaly
        IF abs(zscore_val) >= threshold_stddev THEN
            RETURN QUERY SELECT
                target_table,
                target_column,
                value_record.record_id,
                value_record.value,
                ROUND(zscore_val, 2),
                CASE
                    WHEN zscore_val > 0 THEN 'HIGH_OUTLIER'
                    ELSE 'LOW_OUTLIER'
                END,
                CASE
                    WHEN abs(zscore_val) >= 5 THEN 'VERY_HIGH'
                    WHEN abs(zscore_val) >= 3 THEN 'HIGH'
                    ELSE 'MEDIUM'
                END;
        END IF;
    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- COMPREHENSIVE DATA QUALITY REPORT
-- =========================================--

-- Function to generate comprehensive data quality report
CREATE OR REPLACE FUNCTION generate_data_quality_report()
RETURNS TABLE (
    category TEXT,
    check_type TEXT,
    table_name TEXT,
    issue_description TEXT,
    severity TEXT,
    affected_records BIGINT,
    sample_data JSONB,
    recommended_action TEXT
) AS $$
BEGIN
    -- Foreign key integrity issues
    INSERT INTO data_quality_report
    SELECT
        'INTEGRITY'::TEXT,
        'Foreign Key'::TEXT,
        table_name,
        format('Orphaned records in %I.%I referencing %I.%I',
               table_name, column_name, referenced_table, referenced_column),
        CASE WHEN orphaned_records > 100 THEN 'CRITICAL' WHEN orphaned_records > 0 THEN 'HIGH' ELSE 'OK' END,
        orphaned_records,
        NULL,
        recommendation
    FROM check_foreign_key_integrity(true)
    WHERE orphaned_records > 0;

    -- Email validation issues
    INSERT INTO data_quality_report
    SELECT
        'VALIDATION'::TEXT,
        'Email Format'::TEXT,
        'users'::TEXT,
        format('Invalid email formats: %s%% validity rate', validity_percentage),
        CASE WHEN validity_percentage < 95 THEN 'MEDIUM' ELSE 'OK' END,
        invalid_emails,
        jsonb_build_object('sample_invalid', sample_invalid),
        'Clean up invalid email addresses'
    FROM validate_email_formats('users', 'email')
    WHERE validity_percentage < 100;

    -- Duplicate detection
    INSERT INTO data_quality_report
    SELECT
        'DUPLICATES'::TEXT,
        'Duplicate Records'::TEXT,
        'users'::TEXT,
        format('Duplicate records found: %s groups', COUNT(*)),
        'MEDIUM'::TEXT,
        SUM(record_count::BIGINT),
        jsonb_build_object('sample_group', (array_agg(duplicate_group))[1]),
        'Implement deduplication process'
    FROM find_duplicate_records('users', ARRAY['email'])
    WHERE record_count >= 2;

    -- Data type validation
    INSERT INTO data_quality_report
    SELECT
        'VALIDATION'::TEXT,
        'Data Type'::TEXT,
        table_name,
        format('Invalid %s values in column %I', data_type, column_name),
        CASE WHEN violations > 100 THEN 'HIGH' WHEN violations > 0 THEN 'MEDIUM' ELSE 'OK' END,
        violations,
        jsonb_build_object('sample_violations', sample_violations),
        'Fix data type violations'
    FROM validate_data_types()
    WHERE violations > 0;

    -- Business rule violations
    INSERT INTO data_quality_report
    SELECT
        'BUSINESS_RULES'::TEXT,
        rule_name::TEXT,
        NULL::TEXT,
        rule_description,
        severity,
        violations,
        sample_violations,
        corrective_action
    FROM validate_business_rules()
    WHERE violations > 0;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- AUTOMATED DATA CLEANUP
-- =========================================--

-- Function to perform automated data cleanup
CREATE OR REPLACE FUNCTION perform_data_cleanup(
    dry_run BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    cleanup_action TEXT,
    affected_table TEXT,
    records_affected BIGINT,
    action_taken BOOLEAN,
    details TEXT
) AS $$
DECLARE
    cleanup_count BIGINT;
    action_performed BOOLEAN;
BEGIN
    -- Clean up orphaned user profiles
    SELECT COUNT(*) INTO cleanup_count
    FROM user_profiles up
    WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = up.user_id);

    IF cleanup_count > 0 AND NOT dry_run THEN
        DELETE FROM user_profiles
        WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = up.user_id);
        action_performed := TRUE;
    ELSE
        action_performed := FALSE;
    END IF;

    RETURN QUERY SELECT
        'Remove orphaned user profiles'::TEXT,
        'user_profiles'::TEXT,
        cleanup_count,
        action_performed,
        CASE WHEN dry_run THEN 'DRY RUN: Would delete ' || cleanup_count || ' records'
             ELSE 'Deleted ' || cleanup_count || ' orphaned profiles' END;

    -- Fix invalid email formats (simple corrections)
    SELECT COUNT(*) INTO cleanup_count
    FROM users
    WHERE email LIKE '%@%' AND email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';

    IF cleanup_count > 0 AND NOT dry_run THEN
        -- Simple fixes: trim whitespace, lowercase
        UPDATE users
        SET email = LOWER(TRIM(email))
        WHERE email LIKE '%@%' AND email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
          AND LOWER(TRIM(email)) ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
        action_performed := TRUE;
    ELSE
        action_performed := FALSE;
    END IF;

    RETURN QUERY SELECT
        'Fix email formats'::TEXT,
        'users'::TEXT,
        cleanup_count,
        action_performed,
        CASE WHEN dry_run THEN 'DRY RUN: Would fix ' || cleanup_count || ' email addresses'
             ELSE 'Fixed email formats where possible' END;

END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- USAGE EXAMPLES
-- =========================================--

/*
-- Basic usage examples:

-- 1. Check foreign key integrity
SELECT * FROM check_foreign_key_integrity();

-- 2. Validate email formats
SELECT * FROM validate_email_formats('users', 'email');

-- 3. Find duplicate records
SELECT * FROM find_duplicate_records('users', ARRAY['email', 'first_name', 'last_name']);

-- 4. Check data consistency
SELECT * FROM check_data_consistency();

-- 5. Validate data types
SELECT * FROM validate_data_types('products');

-- 6. Validate business rules
SELECT * FROM validate_business_rules();

-- 7. Detect data anomalies
SELECT * FROM detect_data_anomalies('orders', 'total_amount', 2.5);

-- 8. Generate data quality report
SELECT * FROM generate_data_quality_report();
SELECT * FROM data_quality_report ORDER BY severity, category;

-- 9. Perform data cleanup (dry run first)
SELECT * FROM perform_data_cleanup(true);  -- Dry run
SELECT * FROM perform_data_cleanup(false); -- Actual cleanup
*/

-- ===========================================
-- NOTES
-- =========================================--

/*
Important Notes:
1. Some functions may require additional permissions on system catalogs
2. Data validation can be resource-intensive on large tables
3. Always perform dry runs before actual data cleanup
4. Consider business impact before automated corrections
5. Keep detailed logs of all data changes for audit purposes
6. Schedule regular data quality checks
7. Involve domain experts for complex data cleanup decisions
8. Test validation functions on development data first
9. Monitor system performance during data validation operations
10. Consider archiving historical data that fails validation
*/
