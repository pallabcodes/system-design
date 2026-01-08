# PostgreSQL Common Patterns & Templates

## Overview

This directory contains reusable PostgreSQL patterns and templates used by major tech companies. These patterns provide standardized solutions for common database design challenges including audit trails, soft deletes, versioning, multi-tenancy, and more.

## Table of Contents

1. [Audit Trail Pattern](#audit-trail-pattern)
2. [Soft Delete Pattern](#soft-delete-pattern)
3. [Versioning Pattern](#versioning-pattern)
4. [Multi-Tenancy Patterns](#multi-tenancy-patterns)
5. [Search & Filtering](#search--filtering)
6. [Pagination Patterns](#pagination-patterns)
7. [Caching Patterns](#caching-patterns)
8. [Notification System](#notification-system)
9. [File Storage Pattern](#file-storage-pattern)
10. [Rate Limiting](#rate-limiting)

## Audit Trail Pattern

### Basic Audit Table

```sql
-- Generic audit table for tracking changes
CREATE TABLE audit_log (
    audit_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,  -- Primary key of the audited record
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(user_id),  -- NULL for system operations
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT,

    -- Partition by month for large tables
    PARTITION BY RANGE (changed_at)
);

-- Create monthly partitions
CREATE TABLE audit_log_2024_01 PARTITION OF audit_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Generic audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    audit_record_id UUID;
BEGIN
    -- Generate or extract record ID
    IF TG_OP = 'DELETE' THEN
        audit_record_id := OLD.id;
    ELSE
        audit_record_id := NEW.id;
    END IF;

    INSERT INTO audit_log (
        table_name,
        record_id,
        operation,
        old_values,
        new_values,
        changed_by
    ) VALUES (
        TG_TABLE_NAME,
        audit_record_id,
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        current_setting('app.current_user_id', TRUE)::UUID
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Apply audit trigger to any table
CREATE TRIGGER audit_users_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
```

### Advanced Audit with Change Details

```sql
-- Detailed audit with field-level changes
CREATE TABLE audit_log_detailed (
    audit_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    changed_fields TEXT[],
    old_values JSONB,
    new_values JSONB,
    change_summary TEXT,
    changed_by UUID REFERENCES users(user_id),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    PARTITION BY RANGE (changed_at)
);

-- Function to compare and summarize changes
CREATE OR REPLACE FUNCTION summarize_changes(old_record JSONB, new_record JSONB)
RETURNS TEXT AS $$
DECLARE
    changed_fields TEXT[] := ARRAY[]::TEXT[];
    field_name TEXT;
    summary_parts TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Get all unique field names
    FOR field_name IN SELECT jsonb_object_keys(COALESCE(old_record, '{}'::jsonb) || COALESCE(new_record, '{}'::jsonb))
    LOOP
        IF old_record->>field_name IS DISTINCT FROM new_record->>field_name THEN
            changed_fields := changed_fields || field_name;
            summary_parts := summary_parts || format('%s: %s → %s',
                field_name,
                COALESCE(old_record->>field_name, 'NULL'),
                COALESCE(new_record->>field_name, 'NULL')
            );
        END IF;
    END LOOP;

    RETURN array_to_string(summary_parts, '; ');
END;
$$ LANGUAGE plpgsql;

-- Enhanced audit trigger
CREATE OR REPLACE FUNCTION audit_detailed_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    audit_record_id UUID;
    changed_fields TEXT[];
    change_summary TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        audit_record_id := OLD.id;
    ELSE
        audit_record_id := NEW.id;
    END IF;

    -- Calculate changed fields and summary
    changed_fields := ARRAY[]::TEXT[];
    change_summary := '';

    IF TG_OP = 'UPDATE' THEN
        change_summary := summarize_changes(row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
    END IF;

    INSERT INTO audit_log_detailed (
        table_name,
        record_id,
        operation,
        changed_fields,
        old_values,
        new_values,
        change_summary,
        changed_by
    ) VALUES (
        TG_TABLE_NAME,
        audit_record_id,
        TG_OP,
        changed_fields,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::jsonb ELSE NULL END,
        change_summary,
        current_setting('app.current_user_id', TRUE)::UUID
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;
```

## Soft Delete Pattern

### Basic Soft Delete

```sql
-- Add soft delete columns to any table
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN deleted_by UUID REFERENCES users(user_id);

-- Partial index for active records
CREATE INDEX idx_users_active ON users (id) WHERE deleted_at IS NULL;

-- Soft delete function
CREATE OR REPLACE FUNCTION soft_delete_record(table_name TEXT, record_id UUID)
RETURNS VOID AS $$
BEGIN
    EXECUTE format('UPDATE %I SET deleted_at = CURRENT_TIMESTAMP, deleted_by = $1 WHERE id = $2 AND deleted_at IS NULL',
                   table_name)
    USING current_setting('app.current_user_id', TRUE)::UUID, record_id;
END;
$$ LANGUAGE plpgsql;

-- Query active records only
CREATE VIEW active_users AS
SELECT * FROM users WHERE deleted_at IS NULL;

-- Include soft deletes in audit trail
CREATE OR REPLACE FUNCTION soft_delete_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        INSERT INTO audit_log (table_name, record_id, operation, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'SOFT_DELETE', row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb,
                NEW.deleted_by);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Advanced Soft Delete with Cascade

```sql
-- Soft delete with cascade support
CREATE OR REPLACE FUNCTION soft_delete_cascade(
    root_table TEXT,
    root_id UUID,
    cascade_tables TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER := 0;
    cascade_table TEXT;
BEGIN
    -- Soft delete root record
    EXECUTE format('UPDATE %I SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1 AND deleted_at IS NULL',
                   root_table)
    USING root_id;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    -- Cascade to related tables
    FOREACH cascade_table IN ARRAY cascade_tables
    LOOP
        CASE cascade_table
            WHEN 'user_posts' THEN
                EXECUTE 'UPDATE posts SET deleted_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND deleted_at IS NULL' USING root_id;
            WHEN 'user_comments' THEN
                EXECUTE 'UPDATE comments SET deleted_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND deleted_at IS NULL' USING root_id;
            -- Add more cascade rules as needed
        END CASE;
    END LOOP;

    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
```

## Versioning Pattern

### Temporal Versioning (SCD Type 2)

```sql
-- Slowly Changing Dimension Type 2
CREATE TABLE products_versioned (
    product_id INTEGER NOT NULL,
    version_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    category_id INTEGER,
    is_current BOOLEAN DEFAULT TRUE NOT NULL,
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to TIMESTAMP WITH TIME ZONE DEFAULT '9999-12-31 23:59:59+00',
    created_by UUID REFERENCES users(user_id),

    CHECK (valid_from < valid_to),
    UNIQUE (product_id, is_current) DEFERRABLE INITIALLY DEFERRED
);

-- Function to version product changes
CREATE OR REPLACE FUNCTION version_product(
    prod_id INTEGER,
    new_name VARCHAR(255) DEFAULT NULL,
    new_price DECIMAL(10,2) DEFAULT NULL,
    new_category_id INTEGER DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    current_version products_versioned%ROWTYPE;
    new_version_id INTEGER;
BEGIN
    -- Get current version
    SELECT * INTO current_version
    FROM products_versioned
    WHERE product_id = prod_id AND is_current = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found';
    END IF;

    -- Check if anything changed
    IF (new_name IS NULL OR new_name = current_version.name) AND
       (new_price IS NULL OR new_price = current_version.price) AND
       (new_category_id IS NULL OR new_category_id = current_version.category_id) THEN
        RETURN current_version.version_id;
    END IF;

    -- Expire current version
    UPDATE products_versioned
    SET is_current = FALSE, valid_to = CURRENT_TIMESTAMP
    WHERE version_id = current_version.version_id;

    -- Create new version
    INSERT INTO products_versioned (
        product_id, sku, name, price, category_id,
        valid_from, created_by
    ) VALUES (
        prod_id,
        current_version.sku,
        COALESCE(new_name, current_version.name),
        COALESCE(new_price, current_version.price),
        COALESCE(new_category_id, current_version.category_id),
        CURRENT_TIMESTAMP,
        current_setting('app.current_user_id', TRUE)::UUID
    ) RETURNING version_id INTO new_version_id;

    RETURN new_version_id;
END;
$$ LANGUAGE plpgsql;
```

### Document Versioning with Diffs

```sql
-- Document versioning with change diffs
CREATE TABLE documents (
    document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(500) NOT NULL,
    current_version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE document_versions (
    version_id SERIAL PRIMARY KEY,
    document_id UUID REFERENCES documents(document_id),
    version_number INTEGER NOT NULL,
    title VARCHAR(500),
    content TEXT,
    diff_summary TEXT,
    change_type VARCHAR(50), -- 'create', 'edit', 'major_revision'
    created_by UUID REFERENCES users(user_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (document_id, version_number)
);

-- Function to create new document version
CREATE OR REPLACE FUNCTION create_document_version(
    doc_id UUID,
    new_title VARCHAR(500) DEFAULT NULL,
    new_content TEXT DEFAULT NULL,
    change_description TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    current_version document_versions%ROWTYPE;
    new_version_number INTEGER;
    diff_summary TEXT;
BEGIN
    -- Get current version
    SELECT * INTO current_version
    FROM document_versions
    WHERE document_id = doc_id
    ORDER BY version_number DESC
    LIMIT 1;

    new_version_number := COALESCE(current_version.version_number, 0) + 1;

    -- Calculate diff summary (simplified)
    IF current_version.content IS NOT NULL AND new_content IS NOT NULL THEN
        diff_summary := 'Content updated';
    ELSE
        diff_summary := 'New version created';
    END IF;

    -- Insert new version
    INSERT INTO document_versions (
        document_id, version_number, title, content,
        diff_summary, change_type, created_by
    ) VALUES (
        doc_id, new_version_number,
        COALESCE(new_title, current_version.title),
        COALESCE(new_content, current_version.content),
        COALESCE(change_description, diff_summary),
        CASE WHEN new_version_number = 1 THEN 'create' ELSE 'edit' END,
        current_setting('app.current_user_id', TRUE)::UUID
    );

    -- Update document
    UPDATE documents
    SET current_version = new_version_number,
        title = COALESCE(new_title, title),
        updated_at = CURRENT_TIMESTAMP
    WHERE document_id = doc_id;

    RETURN new_version_number;
END;
$$ LANGUAGE plpgsql;
```

## Multi-Tenancy Patterns

### Schema-per-Tenant

```sql
-- Function to create tenant schema
CREATE OR REPLACE FUNCTION create_tenant_schema(tenant_id UUID, tenant_name TEXT)
RETURNS VOID AS $$
DECLARE
    schema_name TEXT := 'tenant_' || tenant_id;
BEGIN
    -- Create schema
    EXECUTE format('CREATE SCHEMA %I', schema_name);

    -- Create tenant-specific tables
    EXECUTE format('CREATE TABLE %I.users (LIKE public.users INCLUDING ALL)', schema_name);
    EXECUTE format('CREATE TABLE %I.products (LIKE public.products INCLUDING ALL)', schema_name);
    EXECUTE format('CREATE TABLE %I.orders (LIKE public.orders INCLUDING ALL)', schema_name);

    -- Set permissions
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO tenant_user', schema_name);
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I TO tenant_user', schema_name);

    -- Insert tenant metadata
    INSERT INTO tenants (tenant_id, schema_name, name, created_at)
    VALUES (tenant_id, schema_name, tenant_name, CURRENT_TIMESTAMP);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Row-Level Security (RLS)

```sql
-- Tenants table
CREATE TABLE tenants (
    tenant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    schema_name VARCHAR(100) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS on shared tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- RLS policies for multi-tenant data
CREATE POLICY tenant_users_policy ON users
    FOR ALL USING (tenant_id = current_setting('app.tenant_id')::UUID);

CREATE POLICY tenant_products_policy ON products
    FOR ALL USING (tenant_id = current_setting('app.tenant_id')::UUID);

CREATE POLICY tenant_orders_policy ON orders
    FOR ALL USING (
        user_id IN (
            SELECT user_id FROM users WHERE tenant_id = current_setting('app.tenant_id')::UUID
        )
    );

-- Function to set tenant context
CREATE OR REPLACE FUNCTION set_tenant_context(tenant_uuid UUID)
RETURNS VOID AS $$
BEGIN
    -- Verify tenant exists and is active
    IF NOT EXISTS (SELECT 1 FROM tenants WHERE tenant_id = tenant_uuid AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Invalid or inactive tenant';
    END IF;

    -- Set session variable
    PERFORM set_config('app.tenant_id', tenant_uuid::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;
```

## Search & Filtering

### Advanced Search Template

```sql
-- Generic search function with multiple filters
CREATE OR REPLACE FUNCTION search_entities(
    table_name TEXT,
    search_query TEXT DEFAULT '',
    filters JSONB DEFAULT '{}',
    sort_by TEXT DEFAULT 'created_at',
    sort_order TEXT DEFAULT 'DESC',
    page_size INTEGER DEFAULT 20,
    page_number INTEGER DEFAULT 1
)
RETURNS TABLE (
    id UUID,
    data JSONB,
    relevance REAL,
    total_count BIGINT
) AS $$
DECLARE
    where_clause TEXT := '';
    order_clause TEXT := '';
    limit_offset_clause TEXT := '';
    search_vector_column TEXT;
    total_count BIGINT;
BEGIN
    -- Build WHERE clause from filters
    IF filters != '{}' THEN
        SELECT string_agg(
            CASE
                WHEN value::TEXT LIKE '["%"]' THEN format('%I IN (%s)', key, trim(value::TEXT, '[]"'))
                WHEN value::TEXT LIKE '{"%' THEN format('%I @> %L', key, value)
                ELSE format('%I = %L', key, value::TEXT)
            END,
            ' AND '
        ) INTO where_clause
        FROM jsonb_each_text(filters);
    END IF;

    -- Add search condition
    IF search_query != '' THEN
        search_vector_column := table_name || '_search_vector';
        IF where_clause != '' THEN
            where_clause := where_clause || ' AND ';
        END IF;
        where_clause := where_clause || format('%s @@ to_tsquery(''english'', %L)', search_vector_column, search_query);
    END IF;

    -- Build ORDER BY clause
    order_clause := format('%I %s', sort_by, sort_order);

    -- Build LIMIT/OFFSET
    limit_offset_clause := format('LIMIT %s OFFSET %s', page_size, (page_number - 1) * page_size);

    -- Get total count
    EXECUTE format('SELECT COUNT(*) FROM %I %s', table_name,
                   CASE WHEN where_clause != '' THEN 'WHERE ' || where_clause ELSE '' END)
    INTO total_count;

    -- Return results
    RETURN QUERY EXECUTE format('
        SELECT
            t.id,
            to_jsonb(t.*) AS data,
            CASE WHEN %L != '''' THEN ts_rank(%s, to_tsquery(''english'', %L)) ELSE 1.0 END AS relevance,
            %s AS total_count
        FROM %I t
        %s
        ORDER BY %s
        %s',
        search_query, search_vector_column, search_query, total_count, table_name,
        CASE WHEN where_clause != '' THEN 'WHERE ' || where_clause ELSE '' END,
        order_clause, limit_offset_clause);
END;
$$ LANGUAGE plpgsql;
```

### Faceted Search

```sql
-- Faceted search with aggregations
CREATE OR REPLACE FUNCTION faceted_search(
    search_query TEXT DEFAULT '',
    category_filter TEXT[] DEFAULT ARRAY[]::TEXT[],
    price_range NUMRANGE DEFAULT NULL,
    date_range TSRANGE DEFAULT NULL,
    facets TEXT[] DEFAULT ARRAY['category', 'price_range', 'date_range']
)
RETURNS TABLE (
    facet_name TEXT,
    facet_value TEXT,
    count BIGINT
) AS $$
BEGIN
    -- Category facet
    IF 'category' = ANY(facets) THEN
        RETURN QUERY
        SELECT
            'category'::TEXT,
            c.name::TEXT,
            COUNT(p.product_id)::BIGINT
        FROM products p
        JOIN categories c ON p.category_id = c.category_id
        WHERE (search_query = '' OR p.search_vector @@ to_tsquery('english', search_query))
          AND (array_length(category_filter, 1) IS NULL OR c.name = ANY(category_filter))
          AND (price_range IS NULL OR p.price <@ price_range)
          AND (date_range IS NULL OR p.created_at <@ date_range)
        GROUP BY c.category_id, c.name
        ORDER BY count DESC;
    END IF;

    -- Price range facet
    IF 'price_range' = ANY(facets) THEN
        RETURN QUERY
        SELECT
            'price_range'::TEXT,
            CASE
                WHEN p.price < 10 THEN 'Under $10'
                WHEN p.price < 50 THEN '$10 - $49'
                WHEN p.price < 100 THEN '$50 - $99'
                WHEN p.price < 500 THEN '$100 - $499'
                ELSE '$500+'
            END,
            COUNT(*)::BIGINT
        FROM products p
        WHERE (search_query = '' OR p.search_vector @@ to_tsquery('english', search_query))
          AND (array_length(category_filter, 1) IS NULL OR
               p.category_id IN (SELECT category_id FROM categories WHERE name = ANY(category_filter)))
          AND (price_range IS NULL OR p.price <@ price_range)
          AND (date_range IS NULL OR p.created_at <@ date_range)
        GROUP BY CASE
            WHEN p.price < 10 THEN 'Under $10'
            WHEN p.price < 50 THEN '$10 - $49'
            WHEN p.price < 100 THEN '$50 - $99'
            WHEN p.price < 500 THEN '$100 - $499'
            ELSE '$500+'
        END;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

## Pagination Patterns

### Cursor-Based Pagination

```sql
-- Cursor-based pagination for large datasets
CREATE OR REPLACE FUNCTION paginate_cursor(
    table_name TEXT,
    cursor_value TEXT DEFAULT NULL,
    cursor_column TEXT DEFAULT 'id',
    sort_direction TEXT DEFAULT 'ASC',
    page_size INTEGER DEFAULT 20,
    where_clause TEXT DEFAULT ''
)
RETURNS TABLE (
    data JSONB,
    next_cursor TEXT
) AS $$
DECLARE
    query TEXT;
    cursor_condition TEXT := '';
BEGIN
    -- Build cursor condition
    IF cursor_value IS NOT NULL THEN
        cursor_condition := format(
            'WHERE %I %s %L',
            cursor_column,
            CASE WHEN sort_direction = 'ASC' THEN '>' ELSE '<' END,
            cursor_value
        );
    END IF;

    -- Build main query
    query := format('
        SELECT
            to_jsonb(t.*) AS data,
            t.%I::TEXT AS next_cursor
        FROM %I t
        %s
        %s
        ORDER BY t.%I %s
        LIMIT %s',
        cursor_column, table_name,
        CASE WHEN where_clause != '' THEN where_clause ELSE '' END,
        cursor_condition,
        cursor_column, sort_direction, page_size + 1
    );

    -- Execute query and handle pagination
    RETURN QUERY EXECUTE query;
END;
$$ LANGUAGE plpgsql;
```

### Keyset Pagination

```sql
-- Keyset pagination (more efficient than offset)
CREATE OR REPLACE FUNCTION paginate_keyset(
    last_id UUID DEFAULT NULL,
    last_sort_value TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    page_size INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    has_more BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.title,
        p.created_at,
        COUNT(*) OVER () > page_size AS has_more
    FROM posts p
    WHERE (last_id IS NULL AND last_sort_value IS NULL)
       OR (p.created_at, p.id) < (last_sort_value, last_id)
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT page_size + 1;
END;
$$ LANGUAGE plpgsql;
```

## Caching Patterns

### Application-Level Cache

```sql
-- Cache table for frequently accessed data
CREATE TABLE cache (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value JSONB NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 0,
    last_accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Cache management functions
CREATE OR REPLACE FUNCTION get_cache(cache_key_param VARCHAR)
RETURNS JSONB AS $$
DECLARE
    cached_value JSONB;
BEGIN
    SELECT cache_value INTO cached_value
    FROM cache
    WHERE cache_key = cache_key_param
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);

    IF FOUND THEN
        -- Update access statistics
        UPDATE cache
        SET access_count = access_count + 1,
            last_accessed_at = CURRENT_TIMESTAMP
        WHERE cache_key = cache_key_param;

        RETURN cached_value;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION set_cache(
    cache_key_param VARCHAR,
    cache_value_param JSONB,
    ttl_seconds INTEGER DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    expires_at_value TIMESTAMP WITH TIME ZONE;
BEGIN
    IF ttl_seconds IS NOT NULL THEN
        expires_at_value := CURRENT_TIMESTAMP + INTERVAL '1 second' * ttl_seconds;
    END IF;

    INSERT INTO cache (cache_key, cache_value, expires_at)
    VALUES (cache_key_param, cache_value_param, expires_at_value)
    ON CONFLICT (cache_key)
    DO UPDATE SET
        cache_value = EXCLUDED.cache_value,
        expires_at = EXCLUDED.expires_at,
        access_count = 0,
        last_accessed_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;
```

### Materialized View Cache

```sql
-- Materialized view for expensive aggregations
CREATE MATERIALIZED VIEW user_stats_cache AS
SELECT
    u.user_id,
    u.first_name,
    u.last_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_spent,
    AVG(o.total_amount) AS avg_order_value,
    MAX(o.order_date) AS last_order_date,
    COUNT(DISTINCT p.product_id) AS unique_products_purchased,
    -- User engagement score
    (
        COUNT(DISTINCT o.order_id) * 10 +
        EXTRACT(EPOCH FROM (MAX(o.order_date) - MIN(o.order_date))) / 86400 / 30 * 5 +
        COUNT(DISTINCT p.product_id) * 2
    ) AS engagement_score
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id AND o.status = 'completed'
LEFT JOIN order_items oi ON o.order_id = oi.order_id
LEFT JOIN products p ON oi.product_id = p.product_id
GROUP BY u.user_id, u.first_name, u.last_name;

-- Index for fast lookups
CREATE INDEX idx_user_stats_user_id ON user_stats_cache (user_id);
CREATE INDEX idx_user_stats_engagement ON user_stats_cache (engagement_score DESC);

-- Function to refresh cache
CREATE OR REPLACE FUNCTION refresh_user_stats()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_stats_cache;
END;
$$ LANGUAGE plpgsql;
```

## Notification System

### Notification Queue

```sql
-- Notification types and templates
CREATE TABLE notification_types (
    type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    template_subject TEXT,
    template_body TEXT,
    channels TEXT[] DEFAULT ARRAY['email'], -- email, sms, push, in_app
    priority VARCHAR(20) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    throttle_window_minutes INTEGER DEFAULT 60, -- Min time between notifications
    is_active BOOLEAN DEFAULT TRUE
);

-- Notification queue
CREATE TABLE notifications (
    notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    type_id INTEGER REFERENCES notification_types(type_id),
    subject TEXT,
    body TEXT,
    data JSONB DEFAULT '{}', -- Additional context data
    channels TEXT[] NOT NULL DEFAULT ARRAY['email'],
    priority VARCHAR(20) DEFAULT 'normal',
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed', 'cancelled')),

    -- Scheduling
    scheduled_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,

    -- Retry logic
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    next_retry_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Notification delivery attempts
CREATE TABLE notification_deliveries (
    delivery_id SERIAL PRIMARY KEY,
    notification_id UUID REFERENCES notifications(notification_id),
    channel VARCHAR(50) NOT NULL,
    provider VARCHAR(100), -- 'sendgrid', 'twilio', 'fcm', etc.
    external_id VARCHAR(255), -- Provider's message ID
    status VARCHAR(20) NOT NULL CHECK (status IN ('sent', 'delivered', 'failed', 'bounced')),
    error_message TEXT,
    delivered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Notification Functions

```sql
-- Function to queue notification
CREATE OR REPLACE FUNCTION queue_notification(
    user_uuid UUID,
    notification_type_name VARCHAR,
    custom_subject TEXT DEFAULT NULL,
    custom_body TEXT DEFAULT NULL,
    notification_data JSONB DEFAULT '{}',
    scheduled_for TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS UUID AS $$
DECLARE
    notif_type RECORD;
    notif_id UUID;
BEGIN
    -- Get notification type
    SELECT * INTO notif_type
    FROM notification_types
    WHERE name = notification_type_name AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification type not found or inactive';
    END IF;

    -- Check throttling
    IF EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = user_uuid
          AND n.type_id = notif_type.type_id
          AND n.created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute' * notif_type.throttle_window_minutes
    ) THEN
        RETURN NULL; -- Throttled, don't create notification
    END IF;

    -- Create notification
    INSERT INTO notifications (
        user_id, type_id, subject, body, data, channels,
        priority, scheduled_at
    ) VALUES (
        user_uuid,
        notif_type.type_id,
        COALESCE(custom_subject, notif_type.template_subject),
        COALESCE(custom_body, notif_type.template_body),
        notification_data,
        notif_type.channels,
        notif_type.priority,
        scheduled_for
    ) RETURNING notification_id INTO notif_id;

    RETURN notif_id;
END;
$$ LANGUAGE plpgsql;

-- Function to process pending notifications
CREATE OR REPLACE FUNCTION process_notifications(batch_size INTEGER DEFAULT 50)
RETURNS INTEGER AS $$
DECLARE
    notification_record RECORD;
    processed_count INTEGER := 0;
BEGIN
    FOR notification_record IN
        SELECT * FROM notifications
        WHERE status = 'pending'
          AND scheduled_at <= CURRENT_TIMESTAMP
        ORDER BY priority DESC, created_at ASC
        LIMIT batch_size
    LOOP
        -- Mark as sent
        UPDATE notifications
        SET status = 'sent', sent_at = CURRENT_TIMESTAMP
        WHERE notification_id = notification_record.notification_id;

        -- Here you would integrate with actual notification services
        -- For each channel in notification_record.channels:
        -- - Send email via SendGrid/Twilio
        -- - Send SMS via Twilio
        -- - Send push notification via FCM/APNs
        -- - Create in-app notification

        processed_count := processed_count + 1;
    END LOOP;

    RETURN processed_count;
END;
$$ LANGUAGE plpgsql;
```

## File Storage Pattern

### File Metadata Management

```sql
-- File storage metadata
CREATE TABLE files (
    file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_filename VARCHAR(255) NOT NULL,
    storage_filename VARCHAR(255) NOT NULL UNIQUE,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    mime_type VARCHAR(100) NOT NULL,
    file_hash VARCHAR(128) NOT NULL, -- SHA-256 hash

    -- Storage details
    storage_provider VARCHAR(50) DEFAULT 'local', -- local, s3, gcs, azure
    bucket_name VARCHAR(100),
    region VARCHAR(50),

    -- Metadata
    uploaded_by UUID REFERENCES users(user_id),
    entity_type VARCHAR(50), -- 'user_avatar', 'product_image', 'document'
    entity_id UUID, -- Reference to the owning entity
    is_public BOOLEAN DEFAULT FALSE,

    -- Processing status
    processing_status VARCHAR(20) DEFAULT 'uploaded' CHECK (processing_status IN ('uploaded', 'processing', 'processed', 'failed')),
    processing_error TEXT,

    -- Versions and transformations
    original_file_id UUID REFERENCES files(file_id), -- For derived files
    transformation_type VARCHAR(50), -- 'thumbnail', 'resize', 'crop', etc.

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- File access logs
CREATE TABLE file_access_logs (
    access_id SERIAL PRIMARY KEY,
    file_id UUID REFERENCES files(file_id),
    accessed_by UUID REFERENCES users(user_id),
    ip_address INET,
    user_agent TEXT,
    access_type VARCHAR(20) DEFAULT 'download' CHECK (access_type IN ('download', 'view', 'embed')),
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- File processing queue
CREATE TABLE file_processing_queue (
    queue_id SERIAL PRIMARY KEY,
    file_id UUID REFERENCES files(file_id),
    operation VARCHAR(50) NOT NULL, -- 'thumbnail', 'resize', 'compress', 'convert'
    parameters JSONB DEFAULT '{}',
    priority INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE
);
```

### File Management Functions

```sql
-- Function to register uploaded file
CREATE OR REPLACE FUNCTION register_file(
    original_name VARCHAR,
    storage_name VARCHAR,
    file_path VARCHAR,
    file_size BIGINT,
    mime_type VARCHAR,
    file_hash VARCHAR,
    uploader_id UUID,
    entity_type VARCHAR DEFAULT NULL,
    entity_id UUID DEFAULT NULL,
    is_public BOOLEAN DEFAULT FALSE
)
RETURNS UUID AS $$
DECLARE
    file_uuid UUID;
BEGIN
    INSERT INTO files (
        original_filename, storage_filename, file_path, file_size,
        mime_type, file_hash, uploaded_by, entity_type, entity_id, is_public
    ) VALUES (
        original_name, storage_name, file_path, file_size,
        mime_type, file_hash, uploader_id, entity_type, entity_id, is_public
    ) RETURNING file_id INTO file_uuid;

    -- Queue processing tasks based on file type
    IF mime_type LIKE 'image/%' THEN
        INSERT INTO file_processing_queue (file_id, operation, parameters, priority)
        VALUES (file_uuid, 'thumbnail', '{"sizes": [100, 250, 500]}', 1);
    END IF;

    IF mime_type LIKE 'video/%' THEN
        INSERT INTO file_processing_queue (file_id, operation, parameters, priority)
        VALUES (file_uuid, 'compress', '{"format": "mp4", "quality": "720p"}', 2);
    END IF;

    RETURN file_uuid;
END;
$$ LANGUAGE plpgsql;

-- Function to get file URL with access control
CREATE OR REPLACE FUNCTION get_file_url(
    file_uuid UUID,
    requesting_user UUID DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    file_record RECORD;
    can_access BOOLEAN := FALSE;
BEGIN
    -- Get file details
    SELECT * INTO file_record FROM files WHERE file_id = file_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'File not found';
    END IF;

    -- Check access permissions
    IF file_record.is_public THEN
        can_access := TRUE;
    ELSIF requesting_user IS NOT NULL THEN
        -- Check if user owns the file or has permission
        IF file_record.uploaded_by = requesting_user THEN
            can_access := TRUE;
        ELSE
            -- Add additional permission checks based on entity_type
            CASE file_record.entity_type
                WHEN 'user_avatar' THEN
                    can_access := file_record.entity_id = requesting_user;
                WHEN 'course_material' THEN
                    -- Check if user is enrolled in the course
                    can_access := EXISTS(
                        SELECT 1 FROM enrollments e
                        JOIN course_modules cm ON e.course_id = cm.course_id
                        JOIN content_items ci ON cm.module_id = ci.module_id
                        WHERE e.user_id = requesting_user
                          AND ci.content_id = file_record.entity_id
                          AND e.enrollment_status = 'active'
                    );
                ELSE
                    can_access := FALSE;
            END CASE;
        END IF;
    END IF;

    IF NOT can_access THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- Log access
    INSERT INTO file_access_logs (file_id, accessed_by, ip_address, user_agent, access_type)
    VALUES (file_uuid, requesting_user, inet_client_addr(), current_setting('app.user_agent'), 'download');

    -- Generate URL based on storage provider
    CASE file_record.storage_provider
        WHEN 'local' THEN
            RETURN '/files/' || file_record.storage_filename;
        WHEN 's3' THEN
            RETURN 'https://' || file_record.bucket_name || '.s3.amazonaws.com/' || file_record.file_path;
        ELSE
            RETURN file_record.file_path;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Rate Limiting

### Rate Limiting Table

```sql
-- Rate limiting counters
CREATE TABLE rate_limits (
    rate_limit_id SERIAL PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL, -- IP, user_id, API key, etc.
    action_type VARCHAR(100) NOT NULL, -- 'login_attempt', 'api_call', 'email_send'
    window_start TIMESTAMP WITH TIME ZONE NOT NULL,
    window_end TIMESTAMP WITH TIME ZONE NOT NULL,
    request_count INTEGER DEFAULT 0,
    limit_exceeded BOOLEAN DEFAULT FALSE,

    UNIQUE (identifier, action_type, window_start),
    CHECK (window_start < window_end)
);

-- Rate limiting rules
CREATE TABLE rate_limit_rules (
    rule_id SERIAL PRIMARY KEY,
    action_type VARCHAR(100) UNIQUE NOT NULL,
    requests_per_window INTEGER NOT NULL,
    window_seconds INTEGER NOT NULL,
    block_duration_seconds INTEGER DEFAULT 0, -- 0 means just throttle, >0 means block
    is_active BOOLEAN DEFAULT TRUE,

    CHECK (requests_per_window > 0),
    CHECK (window_seconds > 0)
);
```

### Rate Limiting Functions

```sql
-- Function to check rate limit
CREATE OR REPLACE FUNCTION check_rate_limit(
    identifier_param VARCHAR,
    action_type_param VARCHAR
)
RETURNS TABLE (
    allowed BOOLEAN,
    remaining_requests INTEGER,
    reset_time TIMESTAMP WITH TIME ZONE,
    blocked_until TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
    rule_record rate_limit_rules%ROWTYPE;
    current_window_start TIMESTAMP WITH TIME ZONE;
    current_count INTEGER := 0;
    blocked_until TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Get rate limit rule
    SELECT * INTO rule_record
    FROM rate_limit_rules
    WHERE action_type = action_type_param AND is_active = TRUE;

    IF NOT FOUND THEN
        -- No rule found, allow request
        RETURN QUERY SELECT TRUE, -1, NULL::TIMESTAMP WITH TIME ZONE, NULL::TIMESTAMP WITH TIME ZONE;
        RETURN;
    END IF;

    -- Calculate current window
    current_window_start := date_trunc('second', CURRENT_TIMESTAMP);
    current_window_start := current_window_start - INTERVAL '1 second' *
        (EXTRACT(SECOND FROM current_window_start)::INTEGER % rule_record.window_seconds);

    -- Check if currently blocked
    SELECT rl.blocked_until INTO blocked_until
    FROM rate_limits rl
    WHERE rl.identifier = identifier_param
      AND rl.action_type = action_type_param
      AND rl.limit_exceeded = TRUE
      AND rl.blocked_until > CURRENT_TIMESTAMP;

    IF FOUND THEN
        RETURN QUERY SELECT FALSE, 0, current_window_start + INTERVAL '1 second' * rule_record.window_seconds, blocked_until;
        RETURN;
    END IF;

    -- Get current request count
    SELECT request_count INTO current_count
    FROM rate_limits
    WHERE identifier = identifier_param
      AND action_type = action_type_param
      AND window_start = current_window_start;

    IF current_count IS NULL THEN
        current_count := 0;
        -- Insert new window record
        INSERT INTO rate_limits (identifier, action_type, window_start, window_end, request_count)
        VALUES (identifier_param, action_type_param, current_window_start,
                current_window_start + INTERVAL '1 second' * rule_record.window_seconds, 0);
    END IF;

    -- Check if limit exceeded
    IF current_count >= rule_record.requests_per_window THEN
        -- Mark as exceeded and set block time
        blocked_until := CASE
            WHEN rule_record.block_duration_seconds > 0
            THEN CURRENT_TIMESTAMP + INTERVAL '1 second' * rule_record.block_duration_seconds
            ELSE NULL
        END;

        UPDATE rate_limits
        SET limit_exceeded = TRUE,
            blocked_until = blocked_until
        WHERE identifier = identifier_param
          AND action_type = action_type_param
          AND window_start = current_window_start;

        RETURN QUERY SELECT FALSE, 0, current_window_start + INTERVAL '1 second' * rule_record.window_seconds, blocked_until;
    ELSE
        -- Increment counter and allow request
        UPDATE rate_limits
        SET request_count = request_count + 1
        WHERE identifier = identifier_param
          AND action_type = action_type_param
          AND window_start = current_window_start;

        RETURN QUERY SELECT TRUE, rule_record.requests_per_window - current_count - 1,
                          current_window_start + INTERVAL '1 second' * rule_record.window_seconds, NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old rate limit data
CREATE OR REPLACE FUNCTION cleanup_rate_limits()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM rate_limits
    WHERE window_end < CURRENT_TIMESTAMP - INTERVAL '1 hour';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Insert default rate limiting rules
INSERT INTO rate_limit_rules (action_type, requests_per_window, window_seconds, block_duration_seconds) VALUES
('login_attempt', 5, 300, 900),        -- 5 attempts per 5 minutes, block for 15 minutes
('password_reset', 3, 3600, 3600),     -- 3 resets per hour, block for 1 hour
('api_call', 1000, 60, 0),             -- 1000 calls per minute, just throttle
('email_send', 10, 3600, 3600);        -- 10 emails per hour, block for 1 hour
```

These patterns provide a solid foundation for building scalable, maintainable PostgreSQL databases. They address common requirements like auditing, multi-tenancy, caching, and rate limiting that are essential for enterprise applications.
