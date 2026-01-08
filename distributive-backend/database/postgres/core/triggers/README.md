# PostgreSQL Triggers

## Overview

Triggers in PostgreSQL are automatic procedures that execute in response to specific events on a table or view. They are powerful tools for maintaining data integrity, implementing business rules, auditing changes, and automating complex operations.

## Table of Contents

1. [Trigger Basics](#trigger-basics)
2. [Trigger Types](#trigger-types)
3. [Trigger Functions](#trigger-functions)
4. [Event Triggers](#event-triggers)
5. [Trigger Management](#trigger-management)
6. [Performance Considerations](#performance-considerations)
7. [Debugging Triggers](#debugging-triggers)
8. [Enterprise Patterns](#enterprise-patterns)

## Trigger Basics

### What is a Trigger?

A trigger is a special type of stored procedure that automatically executes when specific events occur on a table:

- **BEFORE triggers**: Execute before the triggering event
- **AFTER triggers**: Execute after the triggering event
- **INSTEAD OF triggers**: Execute instead of the triggering event (for views)

### Basic Syntax

```sql
CREATE [OR REPLACE] TRIGGER trigger_name
    { BEFORE | AFTER | INSTEAD OF } { event [OR ...] }
    ON table_name
    [ FOR [EACH] { ROW | STATEMENT } ]
    [ WHEN (condition) ]
    EXECUTE FUNCTION function_name(arguments);
```

### Events

- `INSERT`: Triggered when a row is inserted
- `UPDATE`: Triggered when a row is updated
- `DELETE`: Triggered when a row is deleted
- `TRUNCATE`: Triggered when a table is truncated

## Trigger Types

### Row-Level Triggers

```sql
-- Row-level trigger (executes once per affected row)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Row-level audit trigger
CREATE OR REPLACE FUNCTION audit_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, old_values, changed_at)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb, CURRENT_TIMESTAMP);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, old_values, new_values, changed_at)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, CURRENT_TIMESTAMP);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, new_values, changed_at)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW)::jsonb, CURRENT_TIMESTAMP);
        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_users_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION audit_user_changes();
```

### Statement-Level Triggers

```sql
-- Statement-level trigger (executes once per statement, regardless of affected rows)
CREATE OR REPLACE FUNCTION log_table_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO table_access_log (table_name, operation, accessed_by, accessed_at, row_count)
    VALUES (
        TG_TABLE_NAME,
        TG_OP,
        current_setting('app.current_user_id', TRUE),
        CURRENT_TIMESTAMP,
        (SELECT COUNT(*) FROM pg_stat_user_tables WHERE relname = TG_TABLE_NAME)
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER log_users_access
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH STATEMENT
    EXECUTE FUNCTION log_table_access();
```

### INSTEAD OF Triggers for Views

```sql
-- Create a view
CREATE VIEW active_orders AS
SELECT * FROM orders WHERE status != 'cancelled';

-- INSTEAD OF trigger to make the view updatable
CREATE OR REPLACE FUNCTION active_orders_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO orders (customer_id, order_date, total_amount, status)
    VALUES (NEW.customer_id, NEW.order_date, NEW.total_amount, 'pending');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER active_orders_insert_trigger
    INSTEAD OF INSERT ON active_orders
    FOR EACH ROW EXECUTE FUNCTION active_orders_insert();

-- Usage: Insert through view
INSERT INTO active_orders (customer_id, order_date, total_amount)
VALUES (123, CURRENT_DATE, 99.99);
```

### Conditional Triggers

```sql
-- Trigger that only fires under certain conditions
CREATE OR REPLACE FUNCTION validate_high_value_transaction()
RETURNS TRIGGER AS $$
BEGIN
    -- Only validate transactions over $10,000
    IF NEW.amount > 10000 THEN
        -- Perform additional validation
        IF NOT EXISTS (SELECT 1 FROM approved_transactions WHERE transaction_id = NEW.id) THEN
            RAISE EXCEPTION 'High-value transaction requires approval';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_high_value
    BEFORE INSERT OR UPDATE ON transactions
    FOR EACH ROW
    WHEN (NEW.amount > 10000)
    EXECUTE FUNCTION validate_high_value_transaction();
```

## Trigger Functions

### Special Variables in Triggers

```sql
CREATE OR REPLACE FUNCTION comprehensive_audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    audit_data JSONB;
BEGIN
    -- TG_OP: The operation that triggered the trigger
    -- TG_TABLE_NAME: Name of the table
    -- TG_TABLE_SCHEMA: Schema of the table
    -- TG_WHEN: BEFORE or AFTER
    -- TG_LEVEL: ROW or STATEMENT

    audit_data := jsonb_build_object(
        'operation', TG_OP,
        'table_name', TG_TABLE_NAME,
        'schema_name', TG_TABLE_SCHEMA,
        'trigger_when', TG_WHEN,
        'trigger_level', TG_LEVEL,
        'timestamp', CURRENT_TIMESTAMP
    );

    -- For row-level triggers, OLD and NEW are available
    IF TG_LEVEL = 'ROW' THEN
        audit_data := audit_data || jsonb_build_object(
            'old_data', CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
            'new_data', CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END
        );
    END IF;

    INSERT INTO audit_trail (audit_data, created_at)
    VALUES (audit_data, CURRENT_TIMESTAMP);

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;
```

### Multiple Triggers on Same Table

```sql
-- Multiple triggers can exist on the same table
-- Execution order can be controlled with trigger names

-- Trigger 1: Validation
CREATE OR REPLACE FUNCTION validate_user_email()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
        RAISE EXCEPTION 'Invalid email format';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_email_trigger
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION validate_user_email();

-- Trigger 2: Data normalization
CREATE OR REPLACE FUNCTION normalize_user_data()
RETURNS TRIGGER AS $$
BEGIN
    NEW.first_name := initcap(trim(NEW.first_name));
    NEW.last_name := initcap(trim(NEW.last_name));
    NEW.email := lower(trim(NEW.email));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER normalize_user_data_trigger
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION normalize_user_data();

-- Trigger 3: Audit logging
CREATE TRIGGER audit_users_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_user_changes();
```

### Trigger Functions with Parameters

```sql
-- Triggers can pass parameters to functions
CREATE OR REPLACE FUNCTION conditional_audit_trigger(audit_table_name TEXT)
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, record_id, operation, old_values, new_values)
    VALUES (
        audit_table_name,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Create trigger with parameter
CREATE TRIGGER audit_orders_trigger
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION conditional_audit_trigger('orders');
```

## Event Triggers

### DDL Event Triggers

```sql
-- Event triggers respond to DDL events
CREATE OR REPLACE FUNCTION log_ddl_changes()
RETURNS event_trigger AS $$
DECLARE
    ddl_command RECORD;
BEGIN
    -- Get information about the DDL command
    FOR ddl_command IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        INSERT INTO ddl_audit_log (
            event_type,
            object_type,
            object_name,
            schema_name,
            command,
            executed_by,
            executed_at
        ) VALUES (
            'DDL_COMMAND',
            ddl_command.object_type,
            ddl_command.object_identity,
            ddl_command.schema_name,
            ddl_command.command_tag,
            current_user,
            CURRENT_TIMESTAMP
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create event trigger for DDL commands
CREATE EVENT TRIGGER ddl_audit_trigger
    ON ddl_command_end
    EXECUTE FUNCTION log_ddl_changes();

-- Event trigger for SQL DROP commands
CREATE OR REPLACE FUNCTION prevent_drop_tables()
RETURNS event_trigger AS $$
DECLARE
    obj RECORD;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
    LOOP
        IF obj.object_type = 'table' AND obj.schema_name = 'public' THEN
            RAISE EXCEPTION 'Dropping tables from public schema is not allowed';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER prevent_table_drop
    ON sql_drop
    EXECUTE FUNCTION prevent_drop_tables();
```

### Configuration Event Triggers

```sql
-- Monitor configuration changes
CREATE OR REPLACE FUNCTION log_configuration_changes()
RETURNS event_trigger AS $$
BEGIN
    INSERT INTO config_change_log (
        event_type,
        changed_setting,
        old_value,
        new_value,
        changed_by,
        changed_at
    ) VALUES (
        'CONFIGURATION_CHANGE',
        current_setting('config_changed_setting'),
        current_setting('config_old_value'),
        current_setting('config_new_value'),
        current_user,
        CURRENT_TIMESTAMP
    );
END;
$$ LANGUAGE plpgsql;

-- Note: Configuration event triggers require specific setup
-- This is a simplified example
```

## Trigger Management

### Creating and Dropping Triggers

```sql
-- Create trigger
CREATE TRIGGER trigger_name
    AFTER UPDATE ON table_name
    FOR EACH ROW EXECUTE FUNCTION function_name();

-- Drop trigger
DROP TRIGGER IF EXISTS trigger_name ON table_name;

-- Drop all triggers for a function
DROP TRIGGER trigger_name ON table_name;

-- Disable/Enable trigger
ALTER TABLE table_name DISABLE TRIGGER trigger_name;
ALTER TABLE table_name ENABLE TRIGGER trigger_name;

-- Disable all triggers on a table
ALTER TABLE table_name DISABLE TRIGGER ALL;
ALTER TABLE table_name ENABLE TRIGGER ALL;

-- Check trigger status
SELECT
    t.tgname AS trigger_name,
    t.tgenabled AS enabled,
    p.proname AS function_name,
    c.relname AS table_name
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'your_table_name';
```

### Trigger Dependencies

```sql
-- View trigger dependencies
SELECT
    dependent_ns.nspname AS dependent_schema,
    dependent_obj.relname AS dependent_object,
    source_ns.nspname AS source_schema,
    source_obj.relname AS source_object,
    dependency.deptype
FROM pg_depend dependency
JOIN pg_class dependent_obj ON dependency.objid = dependent_obj.oid
JOIN pg_class source_obj ON dependency.refobjid = source_obj.oid
JOIN pg_namespace dependent_ns ON dependent_obj.relnamespace = dependent_ns.oid
JOIN pg_namespace source_ns ON source_obj.relnamespace = source_ns.oid
WHERE dependent_obj.relkind = 'R'  -- Regular tables
  AND dependency.deptype = 'n';    -- Normal dependency

-- Find triggers that depend on a function
SELECT
    t.tgname AS trigger_name,
    c.relname AS table_name,
    p.proname AS function_name
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE p.proname = 'your_function_name';
```

### Trigger Performance Impact

```sql
-- Analyze trigger performance
SELECT
    schemaname,
    tablename,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_del AS deletes,
    n_tup_hot_upd AS hot_updates,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public';

-- Monitor trigger execution time
CREATE TABLE trigger_performance_log (
    id SERIAL PRIMARY KEY,
    trigger_name TEXT,
    table_name TEXT,
    operation TEXT,
    execution_time INTERVAL,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add timing to trigger functions
CREATE OR REPLACE FUNCTION timed_audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    start_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();

    -- Your trigger logic here
    INSERT INTO audit_log (table_name, operation, changed_at)
    VALUES (TG_TABLE_NAME, TG_OP, CURRENT_TIMESTAMP);

    -- Log execution time
    INSERT INTO trigger_performance_log (trigger_name, table_name, operation, execution_time)
    VALUES (TG_NAME, TG_TABLE_NAME, TG_OP, clock_timestamp() - start_time);

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;
```

## Performance Considerations

### Optimizing Trigger Performance

```sql
-- Use BEFORE triggers for data modification
CREATE OR REPLACE FUNCTION set_default_values()
RETURNS TRIGGER AS $$
BEGIN
    -- Set defaults in BEFORE trigger to avoid additional UPDATE
    NEW.created_at := COALESCE(NEW.created_at, CURRENT_TIMESTAMP);
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Avoid expensive operations in triggers
CREATE OR REPLACE FUNCTION efficient_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    -- Use unlogged table for audit (if durability is not critical)
    INSERT INTO audit_log_unlogged (table_name, operation, record_id)
    VALUES (TG_TABLE_NAME, TG_OP, COALESCE(NEW.id, OLD.id));

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Batch audit operations
CREATE OR REPLACE FUNCTION batch_audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    audit_record audit_log%ROWTYPE;
BEGIN
    -- Prepare audit record
    audit_record.table_name := TG_TABLE_NAME;
    audit_record.operation := TG_OP;
    audit_record.record_id := COALESCE(NEW.id, OLD.id);
    audit_record.old_values := CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END;
    audit_record.new_values := CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END;
    audit_record.changed_at := CURRENT_TIMESTAMP;

    -- Store in session variable for batch processing
    PERFORM set_config('audit.pending_record', row_to_json(audit_record)::text, TRUE);

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Process batched audits (call this after transaction)
CREATE OR REPLACE FUNCTION process_batch_audits()
RETURNS VOID AS $$
DECLARE
    audit_json TEXT;
    audit_record audit_log%ROWTYPE;
BEGIN
    audit_json := current_setting('audit.pending_record', TRUE);

    IF audit_json IS NOT NULL THEN
        audit_record := jsonb_populate_record(NULL::audit_log, audit_json::jsonb);
        INSERT INTO audit_log VALUES (audit_record.*);
        PERFORM set_config('audit.pending_record', NULL, TRUE);
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### Trigger Execution Order

```sql
-- Control trigger execution order with names (alphabetical by default)
-- Prefix trigger names to control order

CREATE TRIGGER a01_validate_data BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION validate_order_data();

CREATE TRIGGER a02_set_defaults BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION set_order_defaults();

CREATE TRIGGER z99_audit_changes AFTER INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION audit_order_changes();
```

### Conditional Trigger Execution

```sql
-- Use WHEN clause to avoid unnecessary trigger execution
CREATE TRIGGER update_search_vector
    AFTER UPDATE OF title, description, tags ON articles
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION update_article_search_vector();

-- Complex conditions
CREATE TRIGGER escalate_high_value_orders
    AFTER UPDATE OF total_amount ON orders
    FOR EACH ROW
    WHEN (NEW.total_amount > 5000 AND OLD.status = 'pending')
    EXECUTE FUNCTION escalate_order_for_review();
```

## Debugging Triggers

### Trigger Debugging Techniques

```sql
-- Add debug logging to trigger functions
CREATE OR REPLACE FUNCTION debug_trigger()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Trigger fired: % on table % for operation %',
        TG_NAME, TG_TABLE_NAME, TG_OP;

    RAISE NOTICE 'OLD: %', CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD) ELSE 'N/A' END;
    RAISE NOTICE 'NEW: %', CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW) ELSE 'N/A' END;

    -- Your trigger logic here

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Check if trigger fired
SELECT
    schemaname,
    tablename,
    trigger_name,
    event_manipulation,
    action_timing,
    action_condition
FROM information_schema.triggers
WHERE event_object_table = 'your_table_name';

-- Monitor trigger performance
CREATE TABLE trigger_execution_log (
    id SERIAL PRIMARY KEY,
    trigger_name TEXT,
    table_name TEXT,
    operation TEXT,
    execution_start TIMESTAMP WITH TIME ZONE,
    execution_end TIMESTAMP WITH TIME ZONE,
    rows_affected INTEGER
);

-- Enhanced trigger with timing
CREATE OR REPLACE FUNCTION timed_trigger()
RETURNS TRIGGER AS $$
DECLARE
    start_time TIMESTAMP WITH TIME ZONE;
    rows_affected INTEGER;
BEGIN
    start_time := clock_timestamp();

    -- Your trigger logic here
    IF TG_OP = 'INSERT' THEN
        rows_affected := 1;
    ELSIF TG_OP = 'UPDATE' THEN
        rows_affected := 1;
    ELSE
        rows_affected := 0;
    END IF;

    -- Log execution
    INSERT INTO trigger_execution_log (
        trigger_name, table_name, operation, execution_start,
        execution_end, rows_affected
    ) VALUES (
        TG_NAME, TG_TABLE_NAME, TG_OP, start_time,
        clock_timestamp(), rows_affected
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;
```

### Common Trigger Issues

```sql
-- Issue: Triggers firing recursively
CREATE OR REPLACE FUNCTION safe_update_trigger()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent recursive trigger calls
    IF current_setting('trigger_depth', TRUE) IS NULL THEN
        PERFORM set_config('trigger_depth', '1', TRUE);
    ELSE
        -- Skip if already in a trigger context
        RETURN NEW;
    END IF;

    -- Your trigger logic here
    UPDATE related_table SET updated_at = CURRENT_TIMESTAMP
    WHERE related_id = NEW.related_id;

    -- Reset trigger depth
    PERFORM set_config('trigger_depth', NULL, TRUE);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Issue: Triggers causing constraint violations
CREATE OR REPLACE FUNCTION handle_constraint_violations()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for potential constraint violations before they occur
    IF TG_OP = 'UPDATE' AND NEW.status = 'completed' THEN
        -- Ensure all required fields are set
        IF NEW.completed_at IS NULL THEN
            NEW.completed_at := CURRENT_TIMESTAMP;
        END IF;

        -- Validate related data exists
        IF NOT EXISTS (SELECT 1 FROM order_items WHERE order_id = NEW.order_id) THEN
            RAISE EXCEPTION 'Cannot complete order without items';
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error and re-raise
        INSERT INTO trigger_error_log (trigger_name, table_name, operation, error_message, error_at)
        VALUES (TG_NAME, TG_TABLE_NAME, TG_OP, SQLERRM, CURRENT_TIMESTAMP);
        RAISE;
END;
$$ LANGUAGE plpgsql;
```

## Enterprise Patterns

### Comprehensive Audit System

```sql
-- Advanced audit trigger with change details
CREATE OR REPLACE FUNCTION enterprise_audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    changed_fields TEXT[] := ARRAY[]::TEXT[];
    field_name TEXT;
    audit_record JSONB;
BEGIN
    -- Identify changed fields
    IF TG_OP = 'UPDATE' THEN
        FOR field_name IN SELECT jsonb_object_keys(row_to_json(OLD)::jsonb || row_to_json(NEW)::jsonb)
        LOOP
            IF row_to_json(OLD)->>field_name IS DISTINCT FROM row_to_json(NEW)->>field_name THEN
                changed_fields := array_append(changed_fields, field_name);
            END IF;
        END LOOP;
    END IF;

    -- Create comprehensive audit record
    audit_record := jsonb_build_object(
        'table_name', TG_TABLE_NAME,
        'operation', TG_OP,
        'record_id', COALESCE(NEW.id, OLD.id),
        'changed_fields', changed_fields,
        'old_values', CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        'new_values', CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        'changed_by', current_setting('app.current_user_id', TRUE),
        'changed_at', CURRENT_TIMESTAMP,
        'ip_address', current_setting('app.client_ip', TRUE),
        'user_agent', current_setting('app.user_agent', TRUE),
        'session_id', current_setting('app.session_id', TRUE)
    );

    -- Insert audit record
    INSERT INTO audit_log_enterprise (audit_data, created_at)
    VALUES (audit_record, CURRENT_TIMESTAMP);

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply to critical tables
CREATE TRIGGER audit_users_enterprise
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION enterprise_audit_trigger();
```

### Business Rule Enforcement

```sql
-- Complex business rule trigger
CREATE OR REPLACE FUNCTION enforce_business_rules()
RETURNS TRIGGER AS $$
DECLARE
    customer_credit_limit DECIMAL;
    order_total DECIMAL;
    outstanding_balance DECIMAL;
BEGIN
    -- Business Rule 1: Credit limit validation
    IF TG_TABLE_NAME = 'orders' AND TG_OP = 'INSERT' THEN
        SELECT credit_limit, outstanding_balance
        INTO customer_credit_limit, outstanding_balance
        FROM customer_credit_info
        WHERE customer_id = NEW.customer_id;

        IF customer_credit_limit IS NOT NULL THEN
            order_total := NEW.subtotal + NEW.tax_amount + NEW.shipping_amount - COALESCE(NEW.discount_amount, 0);

            IF outstanding_balance + order_total > customer_credit_limit THEN
                RAISE EXCEPTION 'Order exceeds customer credit limit. Limit: %, Outstanding: %, Order: %',
                    customer_credit_limit, outstanding_balance, order_total;
            END IF;
        END IF;
    END IF;

    -- Business Rule 2: Inventory reservation
    IF TG_TABLE_NAME = 'order_items' AND TG_OP = 'INSERT' THEN
        -- Check and reserve inventory
        UPDATE products
        SET stock_quantity = stock_quantity - NEW.quantity
        WHERE product_id = NEW.product_id
          AND stock_quantity >= NEW.quantity;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient inventory for product %', NEW.product_id;
        END IF;
    END IF;

    -- Business Rule 3: Order status progression
    IF TG_TABLE_NAME = 'orders' AND TG_OP = 'UPDATE' THEN
        -- Validate status transitions
        CASE
            WHEN OLD.status = 'draft' AND NEW.status NOT IN ('confirmed', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid status transition from draft';
            WHEN OLD.status = 'confirmed' AND NEW.status NOT IN ('processing', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid status transition from confirmed';
            WHEN OLD.status = 'processing' AND NEW.status NOT IN ('shipped', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid status transition from processing';
            WHEN OLD.status = 'shipped' AND NEW.status NOT IN ('delivered', 'returned') THEN
                RAISE EXCEPTION 'Invalid status transition from shipped';
            WHEN OLD.status IN ('delivered', 'cancelled') THEN
                RAISE EXCEPTION 'Cannot change status from final state';
            ELSE
                -- Valid transition
                NULL;
        END CASE;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply business rules
CREATE TRIGGER enforce_order_business_rules
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION enforce_business_rules();

CREATE TRIGGER enforce_order_item_business_rules
    BEFORE INSERT ON order_items
    FOR EACH ROW EXECUTE FUNCTION enforce_business_rules();
```

### Data Synchronization Triggers

```sql
-- Synchronize data across related tables
CREATE OR REPLACE FUNCTION sync_customer_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Sync customer data to search index
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        INSERT INTO customer_search_index (
            customer_id, search_text, last_updated
        ) VALUES (
            NEW.customer_id,
            concat_ws(' ', NEW.first_name, NEW.last_name, NEW.email),
            CURRENT_TIMESTAMP
        ) ON CONFLICT (customer_id) DO UPDATE SET
            search_text = EXCLUDED.search_text,
            last_updated = EXCLUDED.last_updated;

    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM customer_search_index WHERE customer_id = OLD.customer_id;
    END IF;

    -- Update customer summary
    REFRESH MATERIALIZED VIEW CONCURRENTLY customer_summary
    WHERE customer_id = COALESCE(NEW.customer_id, OLD.customer_id);

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_customer_data_trigger
    AFTER INSERT OR UPDATE OR DELETE ON customers
    FOR EACH ROW EXECUTE FUNCTION sync_customer_data();
```

### Performance Monitoring Triggers

```sql
-- Monitor database performance
CREATE TABLE performance_metrics (
    id SERIAL PRIMARY KEY,
    metric_type VARCHAR(50),
    table_name VARCHAR(100),
    operation VARCHAR(20),
    execution_time INTERVAL,
    rows_affected INTEGER,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION monitor_performance()
RETURNS TRIGGER AS $$
DECLARE
    start_time TIMESTAMP WITH TIME ZONE;
    end_time TIMESTAMP WITH TIME ZONE;
BEGIN
    start_time := clock_timestamp();

    -- Simulate some work (replace with your actual trigger logic)
    -- This is just an example - real triggers would do actual work

    end_time := clock_timestamp();

    -- Log performance metrics
    INSERT INTO performance_metrics (
        metric_type, table_name, operation, execution_time, rows_affected
    ) VALUES (
        'trigger_execution',
        TG_TABLE_NAME,
        TG_OP,
        end_time - start_time,
        CASE WHEN TG_LEVEL = 'ROW' THEN 1 ELSE 0 END
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Monitor critical table operations
CREATE TRIGGER monitor_orders_performance
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION monitor_performance();
```

This comprehensive guide covers PostgreSQL triggers from basic concepts to advanced enterprise patterns, including performance optimization, debugging techniques, and real-world business rule enforcement.
