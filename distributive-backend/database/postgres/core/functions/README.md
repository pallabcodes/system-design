# PostgreSQL Functions

## Overview

PostgreSQL functions (also called stored procedures or user-defined functions) are powerful tools for encapsulating business logic, improving performance, and maintaining data consistency. Functions can be written in SQL, PL/pgSQL, or various other languages.

## Table of Contents

1. [Function Types and Languages](#function-types-and-languages)
2. [Basic Function Syntax](#basic-function-syntax)
3. [PL/pgSQL Functions](#plpgsql-functions)
4. [SQL Functions](#sql-functions)
5. [Function Parameters](#function-parameters)
6. [Return Types](#return-types)
7. [Error Handling](#error-handling)
8. [Performance Considerations](#performance-considerations)
9. [Security and Permissions](#security-and-permissions)
10. [Enterprise Patterns](#enterprise-patterns)

## Function Types and Languages

### Supported Languages

```sql
-- Enable additional languages (requires superuser)
CREATE EXTENSION plpython3u;  -- Python
CREATE EXTENSION plperl;     -- Perl
CREATE EXTENSION plv8;       -- JavaScript
CREATE EXTENSION plr;        -- R statistical language

-- Create functions in different languages
CREATE OR REPLACE FUNCTION python_function(input_value INTEGER)
RETURNS INTEGER AS $$
    return input_value * 2 + 1
$$ LANGUAGE plpython3u;

CREATE OR REPLACE FUNCTION js_function(input_value INTEGER)
RETURNS INTEGER AS $$
    return input_value * 2 + 1;
$$ LANGUAGE plv8;
```

### Function Categories

1. **Scalar Functions**: Return a single value
2. **Table-Valued Functions**: Return a table/result set
3. **Aggregate Functions**: Process multiple rows
4. **Window Functions**: Operate on window frames
5. **Trigger Functions**: Called by triggers

## Basic Function Syntax

### Creating Functions

```sql
-- Basic function creation
CREATE [OR REPLACE] FUNCTION function_name(parameters)
RETURNS return_type AS $$
    -- Function body
    -- Can be SQL, PL/pgSQL, or other languages
$$ LANGUAGE language_name;

-- Drop function
DROP FUNCTION [IF EXISTS] function_name(parameters);
DROP FUNCTION function_name;  -- Drops all overloads
```

### Function Overloading

```sql
-- Multiple functions with same name but different parameters
CREATE OR REPLACE FUNCTION calculate_tax(amount DECIMAL)
RETURNS DECIMAL AS $$
BEGIN
    RETURN amount * 0.08;  -- Default 8% tax
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calculate_tax(amount DECIMAL, tax_rate DECIMAL)
RETURNS DECIMAL AS $$
BEGIN
    RETURN amount * tax_rate;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calculate_tax(amount DECIMAL, state_code VARCHAR)
RETURNS DECIMAL AS $$
DECLARE
    tax_rate DECIMAL;
BEGIN
    -- Look up tax rate by state
    SELECT rate INTO tax_rate
    FROM state_tax_rates
    WHERE code = state_code;

    RETURN amount * COALESCE(tax_rate, 0.08);
END;
$$ LANGUAGE plpgsql;

-- Usage examples
SELECT calculate_tax(100.00);                    -- Uses 8% default
SELECT calculate_tax(100.00, 0.10);              -- Uses 10%
SELECT calculate_tax(100.00, 'CA');              -- Uses California rate
```

## PL/pgSQL Functions

### Basic PL/pgSQL Structure

```sql
CREATE OR REPLACE FUNCTION complex_business_logic(
    input_param INTEGER,
    text_param VARCHAR DEFAULT 'default'
)
RETURNS VARCHAR AS $$
DECLARE
    -- Variable declarations
    result_text VARCHAR(200);
    calculated_value INTEGER;
    user_record RECORD;
BEGIN
    -- Function logic
    calculated_value := input_param * 2;

    -- Query database
    SELECT username, email INTO user_record
    FROM users WHERE user_id = calculated_value;

    -- Conditional logic
    IF user_record.username IS NOT NULL THEN
        result_text := 'Found user: ' || user_record.username;
    ELSE
        result_text := 'User not found for ID: ' || calculated_value::TEXT;
    END IF;

    -- Return result
    RETURN result_text;
EXCEPTION
    WHEN OTHERS THEN
        -- Error handling
        RAISE NOTICE 'Error in complex_business_logic: %', SQLERRM;
        RETURN 'Error occurred';
END;
$$ LANGUAGE plpgsql;
```

### Control Structures

```sql
-- IF-THEN-ELSE
CREATE OR REPLACE FUNCTION get_user_status(user_id_param INTEGER)
RETURNS VARCHAR AS $$
DECLARE
    last_login TIMESTAMP;
    days_since_login INTEGER;
BEGIN
    SELECT last_login_at INTO last_login
    FROM users WHERE user_id = user_id_param;

    IF last_login IS NULL THEN
        RETURN 'Never logged in';
    END IF;

    days_since_login := EXTRACT(DAY FROM CURRENT_TIMESTAMP - last_login);

    IF days_since_login = 0 THEN
        RETURN 'Active today';
    ELSIF days_since_login <= 7 THEN
        RETURN 'Active this week';
    ELSIF days_since_login <= 30 THEN
        RETURN 'Active this month';
    ELSE
        RETURN 'Inactive';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- CASE statement
CREATE OR REPLACE FUNCTION get_priority_level(urgency VARCHAR, impact VARCHAR)
RETURNS VARCHAR AS $$
BEGIN
    RETURN CASE
        WHEN urgency = 'high' AND impact = 'high' THEN 'Critical'
        WHEN urgency = 'high' OR impact = 'high' THEN 'High'
        WHEN urgency = 'medium' OR impact = 'medium' THEN 'Medium'
        ELSE 'Low'
    END;
END;
$$ LANGUAGE plpgsql;

-- Loops
CREATE OR REPLACE FUNCTION process_batch(batch_size INTEGER DEFAULT 100)
RETURNS INTEGER AS $$
DECLARE
    processed_count INTEGER := 0;
    current_record RECORD;
BEGIN
    FOR current_record IN
        SELECT * FROM pending_orders
        WHERE status = 'pending'
        ORDER BY created_at
        LIMIT batch_size
    LOOP
        -- Process each record
        UPDATE pending_orders
        SET status = 'processing', processed_at = CURRENT_TIMESTAMP
        WHERE order_id = current_record.order_id;

        processed_count := processed_count + 1;
    END LOOP;

    RETURN processed_count;
END;
$$ LANGUAGE plpgsql;
```

### Working with Collections

```sql
-- Arrays
CREATE OR REPLACE FUNCTION get_user_permissions(user_id_param INTEGER)
RETURNS TEXT[] AS $$
DECLARE
    permission_array TEXT[];
BEGIN
    SELECT array_agg(permission_name)
    INTO permission_array
    FROM user_permissions up
    JOIN permissions p ON up.permission_id = p.permission_id
    WHERE up.user_id = user_id_param;

    RETURN permission_array;
END;
$$ LANGUAGE plpgsql;

-- Iterating over arrays
CREATE OR REPLACE FUNCTION validate_permissions(required_permissions TEXT[])
RETURNS BOOLEAN AS $$
DECLARE
    perm TEXT;
    has_permission BOOLEAN := FALSE;
BEGIN
    FOREACH perm IN ARRAY required_permissions
    LOOP
        -- Check if user has this permission
        SELECT EXISTS(
            SELECT 1 FROM user_permissions up
            JOIN permissions p ON up.permission_id = p.permission_id
            WHERE up.user_id = current_user_id()
              AND p.permission_name = perm
        ) INTO has_permission;

        IF NOT has_permission THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

## SQL Functions

### Simple SQL Functions

```sql
-- Pure SQL function (fastest for simple operations)
CREATE OR REPLACE FUNCTION get_full_name(first_name VARCHAR, last_name VARCHAR)
RETURNS VARCHAR AS $$
    SELECT CONCAT(first_name, ' ', last_name);
$$ LANGUAGE SQL;

-- SQL function with subqueries
CREATE OR REPLACE FUNCTION get_customer_order_count(customer_id_param INTEGER)
RETURNS INTEGER AS $$
    SELECT COUNT(*)
    FROM orders
    WHERE customer_id = customer_id_param
      AND status != 'cancelled';
$$ LANGUAGE SQL;

-- SQL function returning multiple values
CREATE OR REPLACE FUNCTION get_user_stats(user_id_param INTEGER)
RETURNS TABLE (
    total_orders INTEGER,
    total_spent DECIMAL(10,2),
    last_order_date DATE,
    favorite_category VARCHAR(100)
) AS $$
    SELECT
        COUNT(o.order_id) AS total_orders,
        COALESCE(SUM(o.total_amount), 0) AS total_spent,
        MAX(o.order_date)::DATE AS last_order_date,
        (
            SELECT c.name
            FROM order_items oi
            JOIN products p ON oi.product_id = p.product_id
            JOIN categories c ON p.category_id = c.category_id
            WHERE oi.order_id IN (SELECT order_id FROM orders WHERE customer_id = user_id_param)
            GROUP BY c.category_id, c.name
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS favorite_category
    FROM orders o
    WHERE o.customer_id = user_id_param
      AND o.status = 'completed';
$$ LANGUAGE SQL;
```

### Set-Returning Functions

```sql
-- Function returning multiple rows
CREATE OR REPLACE FUNCTION get_recent_orders(days_back INTEGER DEFAULT 30)
RETURNS TABLE (
    order_id INTEGER,
    customer_name VARCHAR(200),
    order_date DATE,
    total_amount DECIMAL(10,2),
    status VARCHAR(20)
) AS $$
    SELECT
        o.order_id,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        o.order_date::DATE,
        o.total_amount,
        o.status
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= CURRENT_DATE - INTERVAL '1 day' * days_back
    ORDER BY o.order_date DESC;
$$ LANGUAGE SQL;

-- Usage
SELECT * FROM get_recent_orders(7);  -- Last 7 days
SELECT * FROM get_recent_orders();   -- Default 30 days
```

## Function Parameters

### Parameter Modes

```sql
-- IN parameters (default - read-only input)
CREATE OR REPLACE FUNCTION calculate_discount(price DECIMAL, discount_percent DECIMAL)
RETURNS DECIMAL AS $$
BEGIN
    RETURN price * (1 - discount_percent / 100);
END;
$$ LANGUAGE plpgsql;

-- OUT parameters (output values)
CREATE OR REPLACE FUNCTION split_name(
    full_name VARCHAR,
    OUT first_name VARCHAR,
    OUT last_name VARCHAR
) AS $$
BEGIN
    first_name := split_part(full_name, ' ', 1);
    last_name := COALESCE(split_part(full_name, ' ', 2), '');
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT * FROM split_name('John Doe');  -- Returns first_name, last_name

-- INOUT parameters (input and output)
CREATE OR REPLACE FUNCTION increment_counter(INOUT counter INTEGER)
AS $$
BEGIN
    counter := counter + 1;
END;
$$ LANGUAGE plpgsql;

-- VARIADIC parameters (variable number of arguments)
CREATE OR REPLACE FUNCTION sum_values(VARIADIC values INTEGER[])
RETURNS INTEGER AS $$
DECLARE
    total INTEGER := 0;
    val INTEGER;
BEGIN
    FOREACH val IN ARRAY values
    LOOP
        total := total + val;
    END LOOP;
    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT sum_values(1, 2, 3, 4, 5);        -- Returns 15
SELECT sum_values(VARIADIC ARRAY[1,2,3]); -- Same result
```

### Default Parameters

```sql
-- Functions with default parameters
CREATE OR REPLACE FUNCTION create_user_notification(
    user_id_param INTEGER,
    message TEXT,
    priority VARCHAR DEFAULT 'normal',
    expires_in_hours INTEGER DEFAULT 24
)
RETURNS INTEGER AS $$
DECLARE
    notification_id INTEGER;
BEGIN
    INSERT INTO notifications (
        user_id, message, priority, expires_at
    ) VALUES (
        user_id_param,
        message,
        priority,
        CURRENT_TIMESTAMP + INTERVAL '1 hour' * expires_in_hours
    ) RETURNING notification_id INTO notification_id;

    RETURN notification_id;
END;
$$ LANGUAGE plpgsql;

-- Usage with defaults
SELECT create_user_notification(123, 'Welcome to our platform!');
-- Uses defaults: priority='normal', expires_in_hours=24

-- Override defaults
SELECT create_user_notification(123, 'Urgent message', 'high', 1);
```

## Return Types

### Single Value Returns

```sql
-- Simple scalar return
CREATE OR REPLACE FUNCTION get_user_age(user_id_param INTEGER)
RETURNS INTEGER AS $$
DECLARE
    birth_date DATE;
BEGIN
    SELECT date_of_birth INTO birth_date
    FROM users WHERE user_id = user_id_param;

    IF birth_date IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN EXTRACT(YEAR FROM AGE(birth_date))::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- Return with subquery
CREATE OR REPLACE FUNCTION get_most_expensive_product()
RETURNS VARCHAR AS $$
    SELECT name FROM products
    ORDER BY price DESC
    LIMIT 1;
$$ LANGUAGE SQL;
```

### Complex Returns

```sql
-- Return composite type
CREATE TYPE user_summary AS (
    user_id INTEGER,
    full_name VARCHAR(200),
    email VARCHAR(255),
    account_status VARCHAR(20),
    member_since DATE
);

CREATE OR REPLACE FUNCTION get_user_summary(user_id_param INTEGER)
RETURNS user_summary AS $$
DECLARE
    result user_summary;
BEGIN
    SELECT
        u.user_id,
        u.first_name || ' ' || u.last_name,
        u.email,
        u.status,
        u.created_at::DATE
    INTO result
    FROM users u
    WHERE u.user_id = user_id_param;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT * FROM get_user_summary(123);
```

### Multiple Result Sets

```sql
-- Return multiple result sets using refcursor
CREATE OR REPLACE FUNCTION get_user_reports(user_id_param INTEGER)
RETURNS SETOF refcursor AS $$
DECLARE
    user_cursor refcursor := 'user_cursor';
    orders_cursor refcursor := 'orders_cursor';
BEGIN
    -- Open cursors for different result sets
    OPEN user_cursor FOR
        SELECT * FROM users WHERE user_id = user_id_param;

    OPEN orders_cursor FOR
        SELECT * FROM orders WHERE customer_id = user_id_param;

    RETURN NEXT user_cursor;
    RETURN NEXT orders_cursor;
END;
$$ LANGUAGE plpgsql;
```

## Error Handling

### Basic Error Handling

```sql
-- Basic exception handling
CREATE OR REPLACE FUNCTION safe_division(numerator DECIMAL, denominator DECIMAL)
RETURNS DECIMAL AS $$
BEGIN
    IF denominator = 0 THEN
        RAISE EXCEPTION 'Division by zero: % / %', numerator, denominator;
    END IF;

    RETURN numerator / denominator;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Caught division by zero';
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Custom error codes
CREATE OR REPLACE FUNCTION validate_order(order_id_param INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    order_record RECORD;
BEGIN
    SELECT * INTO order_record FROM orders WHERE order_id = order_id_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0001';
    END IF;

    IF order_record.status = 'cancelled' THEN
        RAISE EXCEPTION 'Order is cancelled' USING ERRCODE = 'P0002';
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

### Advanced Error Handling

```sql
-- Nested error handling with savepoints
CREATE OR REPLACE FUNCTION process_payment_transaction(
    order_id_param INTEGER,
    payment_amount DECIMAL
)
RETURNS BOOLEAN AS $$
DECLARE
    order_total DECIMAL;
    payment_success BOOLEAN := FALSE;
BEGIN
    -- Start subtransaction
    BEGIN
        -- Validate order
        SELECT total_amount INTO order_total
        FROM orders WHERE order_id = order_id_param;

        IF order_total != payment_amount THEN
            RAISE EXCEPTION 'Payment amount mismatch: expected %, got %',
                order_total, payment_amount;
        END IF;

        -- Process payment (simulated)
        -- In real implementation, this would call payment processor
        payment_success := TRUE;

        -- Update order status
        UPDATE orders SET status = 'paid' WHERE order_id = order_id_param;

    EXCEPTION
        WHEN OTHERS THEN
            -- Log error but don't fail the outer transaction
            INSERT INTO payment_errors (order_id, error_message, error_time)
            VALUES (order_id_param, SQLERRM, CURRENT_TIMESTAMP);

            RAISE NOTICE 'Payment processing failed for order %: %',
                order_id_param, SQLERRM;
            RETURN FALSE;
    END;

    RETURN payment_success;
END;
$$ LANGUAGE plpgsql;
```

## Performance Considerations

### Function Volatility

```sql
-- IMMUTABLE: Always returns same result for same inputs
CREATE OR REPLACE FUNCTION calculate_tax(amount DECIMAL)
RETURNS DECIMAL AS $$
    SELECT amount * 0.08;
$$ LANGUAGE SQL IMMUTABLE;

-- STABLE: Result depends on database state, but doesn't modify it
CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS INTEGER AS $$
    SELECT current_setting('app.current_user_id')::INTEGER;
$$ LANGUAGE SQL STABLE;

-- VOLATILE: Can return different results or modify database (default)
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS VARCHAR AS $$
    SELECT 'ORD-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' ||
           LPAD(NEXTVAL('order_number_seq')::TEXT, 6, '0');
$$ LANGUAGE SQL VOLATILE;
```

### Performance Optimization

```sql
-- Use SQL functions for better performance
CREATE OR REPLACE FUNCTION get_user_count()
RETURNS INTEGER AS $$
    SELECT COUNT(*) FROM users WHERE is_active = TRUE;
$$ LANGUAGE SQL STABLE;

-- Avoid unnecessary PL/pgSQL for simple queries
CREATE OR REPLACE FUNCTION get_user_email(user_id_param INTEGER)
RETURNS VARCHAR AS $$
    SELECT email FROM users WHERE user_id = user_id_param;
$$ LANGUAGE SQL STABLE;

-- Use CTEs for complex logic to improve readability and sometimes performance
CREATE OR REPLACE FUNCTION get_top_customers(limit_count INTEGER DEFAULT 10)
RETURNS TABLE (
    customer_id INTEGER,
    customer_name VARCHAR(200),
    total_orders INTEGER,
    total_spent DECIMAL(10,2)
) AS $$
    WITH customer_stats AS (
        SELECT
            c.customer_id,
            c.first_name || ' ' || c.last_name AS customer_name,
            COUNT(o.order_id) AS total_orders,
            SUM(o.total_amount) AS total_spent
        FROM customers c
        LEFT JOIN orders o ON c.customer_id = o.customer_id
            AND o.status = 'completed'
        GROUP BY c.customer_id, c.first_name, c.last_name
    )
    SELECT * FROM customer_stats
    ORDER BY total_spent DESC
    LIMIT limit_count;
$$ LANGUAGE SQL STABLE;
```

### Indexing for Functions

```sql
-- Create indexes to support function-based queries
CREATE INDEX idx_users_age ON users (EXTRACT(YEAR FROM AGE(date_of_birth)));
CREATE INDEX idx_orders_month ON orders (DATE_TRUNC('month', order_date));

-- Partial indexes for common function conditions
CREATE INDEX idx_active_users ON users (user_id) WHERE is_active = TRUE;

-- Expression indexes for function results
CREATE INDEX idx_products_taxed_price ON products ((price * 1.08));

-- Query using function-based indexes
SELECT * FROM users WHERE EXTRACT(YEAR FROM AGE(date_of_birth)) >= 18;
SELECT * FROM orders WHERE DATE_TRUNC('month', order_date) = '2024-01-01'::DATE;
```

## Security and Permissions

### Function Security

```sql
-- SECURITY DEFINER: Function runs with creator's privileges
CREATE OR REPLACE FUNCTION admin_only_function()
RETURNS VOID AS $$
BEGIN
    -- This function can access tables that the caller might not have access to
    UPDATE system_settings SET value = 'updated' WHERE key = 'maintenance_mode';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- SECURITY INVOKER: Function runs with caller's privileges (default)
CREATE OR REPLACE FUNCTION user_function()
RETURNS VOID AS $$
BEGIN
    -- This function respects the caller's permissions
    UPDATE user_preferences SET theme = 'dark' WHERE user_id = current_user_id();
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;
```

### Function Permissions

```sql
-- Grant execute permission on functions
GRANT EXECUTE ON FUNCTION get_user_count() TO reporting_user;
GRANT EXECUTE ON FUNCTION calculate_tax(DECIMAL) TO public;
GRANT EXECUTE ON FUNCTION create_user_notification(INTEGER, TEXT, VARCHAR, INTEGER) TO application_user;

-- Revoke permissions
REVOKE EXECUTE ON FUNCTION admin_only_function() FROM public;

-- Function usage in policies
ALTER TABLE sensitive_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_data_policy ON sensitive_data
    FOR SELECT USING (user_id = get_current_user_id());
```

## Enterprise Patterns

### Audit Functions

```sql
-- Generic audit function
CREATE OR REPLACE FUNCTION audit_table_change()
RETURNS TRIGGER AS $$
DECLARE
    audit_data JSONB;
    old_data JSONB;
    new_data JSONB;
BEGIN
    -- Convert row data to JSONB
    old_data := CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::JSONB ELSE NULL END;
    new_data := CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::JSONB ELSE NULL END;

    -- Create audit record
    INSERT INTO audit_log (
        table_name,
        record_id,
        operation,
        old_values,
        new_values,
        changed_by,
        changed_at
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        old_data,
        new_data,
        current_setting('app.current_user_id', TRUE)::UUID,
        CURRENT_TIMESTAMP
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply audit function to tables
CREATE TRIGGER audit_users_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_table_change();
```

### Business Logic Functions

```sql
-- Complex business validation
CREATE OR REPLACE FUNCTION validate_loan_application(
    customer_id_param INTEGER,
    loan_amount DECIMAL,
    loan_term_months INTEGER
)
RETURNS TABLE (
    is_valid BOOLEAN,
    max_loan_amount DECIMAL,
    risk_score DECIMAL,
    validation_errors TEXT[]
) AS $$
DECLARE
    customer_record RECORD;
    credit_score INTEGER;
    debt_ratio DECIMAL;
    max_allowed DECIMAL;
    errors TEXT[] := ARRAY[]::TEXT[];
    risk_score_calc DECIMAL := 0;
BEGIN
    -- Get customer financial data
    SELECT
        c.*,
        COALESCE(cd.credit_score, 650) AS credit_score,
        COALESCE(cd.fraud_score, 0.5) AS fraud_score
    INTO customer_record
    FROM customers c
    LEFT JOIN customer_data_quality cd ON c.customer_id = cd.customer_id
    WHERE c.customer_id = customer_id_param;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 0::DECIMAL, 0::DECIMAL, ARRAY['Customer not found']::TEXT[];
        RETURN;
    END IF;

    -- Validate customer status
    IF customer_record.kyc_status != 'approved' THEN
        errors := errors || 'KYC not approved';
    END IF;

    -- Calculate debt ratio
    SELECT COALESCE(SUM(monthly_payment), 0) / (customer_record.annual_income / 12) INTO debt_ratio
    FROM existing_loans WHERE customer_id = customer_id_param;

    -- Calculate maximum loan amount
    max_allowed := GREATEST(0, customer_record.annual_income * 0.3 - (debt_ratio * customer_record.annual_income / 12));

    -- Validate loan amount
    IF loan_amount > max_allowed THEN
        errors := errors || format('Loan amount exceeds maximum allowed: $%', max_allowed);
    END IF;

    -- Calculate risk score (simplified)
    risk_score_calc := (
        (customer_record.credit_score / 850.0) * 40 +  -- 40% weight on credit score
        (1 - customer_record.fraud_score) * 30 +        -- 30% weight on fraud score
        (1 - debt_ratio) * 20 +                         -- 20% weight on debt ratio
        CASE WHEN array_length(errors, 1) IS NULL THEN 10 ELSE 0 END  -- 10% for validation
    );

    -- Final validation
    is_valid := array_length(errors, 1) IS NULL AND loan_amount <= max_allowed;

    RETURN QUERY SELECT is_valid, max_allowed, risk_score_calc, errors;
END;
$$ LANGUAGE plpgsql;
```

### Data Processing Functions

```sql
-- Batch processing function
CREATE OR REPLACE FUNCTION process_pending_orders(batch_size INTEGER DEFAULT 50)
RETURNS TABLE (
    processed_count INTEGER,
    success_count INTEGER,
    error_count INTEGER,
    errors JSONB
) AS $$
DECLARE
    order_record RECORD;
    processed INTEGER := 0;
    successful INTEGER := 0;
    failed INTEGER := 0;
    error_list JSONB := '[]';
    error_details JSONB;
BEGIN
    FOR order_record IN
        SELECT * FROM orders
        WHERE status = 'pending'
          AND created_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes'
        ORDER BY created_at
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
    LOOP
        BEGIN
            -- Attempt to process order
            UPDATE orders
            SET status = 'processing', updated_at = CURRENT_TIMESTAMP
            WHERE order_id = order_record.order_id;

            -- Simulate processing logic
            -- In real implementation, this would validate inventory, process payment, etc.

            -- Mark as successful
            UPDATE orders
            SET status = 'confirmed', confirmed_at = CURRENT_TIMESTAMP
            WHERE order_id = order_record.order_id;

            successful := successful + 1;

        EXCEPTION WHEN OTHERS THEN
            -- Record error
            UPDATE orders
            SET status = 'failed', updated_at = CURRENT_TIMESTAMP
            WHERE order_id = order_record.order_id;

            error_details := jsonb_build_object(
                'order_id', order_record.order_id,
                'error', SQLERRM,
                'timestamp', CURRENT_TIMESTAMP
            );
            error_list := error_list || error_details;

            failed := failed + 1;
        END;

        processed := processed + 1;
    END LOOP;

    RETURN QUERY SELECT processed, successful, failed, error_list;
END;
$$ LANGUAGE plpgsql;
```

### Utility Functions

```sql
-- Data cleanup function
CREATE OR REPLACE FUNCTION cleanup_old_data(retention_days INTEGER DEFAULT 90)
RETURNS TABLE (
    table_name TEXT,
    records_deleted BIGINT
) AS $$
DECLARE
    table_record RECORD;
    delete_query TEXT;
    deleted_count BIGINT;
BEGIN
    -- Define tables and their cleanup criteria
    CREATE TEMPORARY TABLE cleanup_tables (
        table_name TEXT,
        date_column TEXT,
        condition TEXT
    );

    INSERT INTO cleanup_tables VALUES
        ('user_sessions', 'created_at', ''),
        ('audit_log', 'changed_at', ''),
        ('failed_login_attempts', 'attempted_at', ''),
        ('temp_files', 'uploaded_at', 'AND processed = TRUE');

    FOR table_record IN SELECT * FROM cleanup_tables
    LOOP
        BEGIN
            delete_query := format(
                'DELETE FROM %I WHERE %I < CURRENT_DATE - INTERVAL ''%s days'' %s',
                table_record.table_name,
                table_record.date_column,
                retention_days,
                table_record.condition
            );

            EXECUTE delete_query;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;

            RETURN QUERY SELECT table_record.table_name, deleted_count;

        EXCEPTION WHEN OTHERS THEN
            -- Log error but continue with other tables
            RAISE NOTICE 'Error cleaning table %: %', table_record.table_name, SQLERRM;
            RETURN QUERY SELECT table_record.table_name, -1::BIGINT;
        END;
    END LOOP;

    DROP TABLE cleanup_tables;
END;
$$ LANGUAGE plpgsql;

-- Automated cleanup scheduling
-- SELECT cron.schedule('daily-data-cleanup', '0 2 * * *', 'SELECT cleanup_old_data(90)');
```

This comprehensive guide covers PostgreSQL functions from basic syntax to advanced enterprise patterns, including performance optimization, security considerations, and real-world business logic implementations.
