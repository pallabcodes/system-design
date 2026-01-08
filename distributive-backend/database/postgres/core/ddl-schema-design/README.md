# PostgreSQL DDL Schema Design

## Overview

This guide covers comprehensive DDL (Data Definition Language) schema design in PostgreSQL, focusing on best practices, advanced features, and enterprise-level patterns used by major tech companies.

## Table of Contents

1. [Database Creation and Management](#database-creation-and-management)
2. [Schema Design Principles](#schema-design-principles)
3. [Advanced Data Types](#advanced-data-types)
4. [Table Inheritance](#table-inheritance)
5. [Generated Columns](#generated-columns)
6. [Domains and Custom Types](#domains-and-custom-types)
7. [Extensions and Advanced Features](#extensions-and-advanced-features)
8. [Performance Considerations](#performance-considerations)
9. [Enterprise Patterns](#enterprise-patterns)

## Database Creation and Management

### Basic Database Creation

```sql
-- Create database with specific settings
CREATE DATABASE ecommerce_db
    WITH OWNER = ecommerce_user
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TABLESPACE = ecommerce_tablespace
    CONNECTION LIMIT = 100;

-- Create user and grant permissions
CREATE USER ecommerce_user WITH ENCRYPTED PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE ecommerce_db TO ecommerce_user;

-- Create schema for better organization
CREATE SCHEMA IF NOT EXISTS ecommerce AUTHORIZATION ecommerce_user;
```

### Advanced Database Configuration

```sql
-- Create database with advanced options
CREATE DATABASE analytics_db
    WITH
    OWNER = analytics_user
    ENCODING = 'UTF8'
    LC_COLLATE = 'C'  -- Use C locale for performance
    LC_CTYPE = 'C'
    TEMPLATE = template0
    CONNECTION LIMIT = -1  -- No limit
    ALLOW_CONNECTIONS = true;

-- Set database-level configuration
ALTER DATABASE analytics_db SET
    work_mem = '256MB',
    maintenance_work_mem = '1GB',
    shared_preload_libraries = 'pg_stat_statements,pg_buffercache';

-- Create tablespace for better I/O management
CREATE TABLESPACE fast_ssd LOCATION '/ssd/postgres/data';
CREATE TABLESPACE slow_hdd LOCATION '/hdd/postgres/data';
```

## Schema Design Principles

### Table Naming Conventions

```sql
-- Use consistent naming patterns
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Use snake_case for consistency
CREATE TABLE user_profiles (
    profile_id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    date_of_birth DATE,
    bio TEXT
);
```

### Primary Key Design

```sql
-- Natural vs Surrogate Keys
-- Surrogate key (recommended for most cases)
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL CHECK (price > 0)
);

-- Composite primary key (use when natural key exists)
CREATE TABLE order_items (
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, product_id)
);
```

### Foreign Key Relationships

```sql
-- One-to-Many relationship
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled')),
    total_amount DECIMAL(12,2) NOT NULL CHECK (total_amount >= 0)
);

-- Many-to-Many relationship with junction table
CREATE TABLE product_categories (
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    category_id INTEGER REFERENCES categories(category_id) ON DELETE CASCADE,
    PRIMARY KEY (product_id, category_id)
);

-- Self-referencing relationship
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    manager_id INTEGER REFERENCES employees(employee_id),
    name VARCHAR(100) NOT NULL,
    department_id INTEGER REFERENCES departments(department_id)
);
```

## Advanced Data Types

### JSON and JSONB

```sql
-- JSON for storing flexible data structures
CREATE TABLE user_preferences (
    user_id INTEGER PRIMARY KEY REFERENCES users(user_id),
    preferences JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert JSON data
INSERT INTO user_preferences (user_id, preferences) VALUES
(1, '{"theme": "dark", "notifications": {"email": true, "push": false}, "language": "en"}');

-- Query JSON data
SELECT user_id, preferences->>'theme' as theme
FROM user_preferences
WHERE preferences->>'language' = 'en';

-- Index JSON fields for performance
CREATE INDEX idx_user_preferences_theme ON user_preferences USING GIN ((preferences->'notifications'));
```

### Arrays

```sql
-- Array data types for multi-valued attributes
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    tags TEXT[] DEFAULT '{}',  -- Array of tags
    images VARCHAR(500)[] DEFAULT '{}',  -- Array of image URLs
    specifications JSONB
);

-- Query arrays
SELECT * FROM products WHERE 'electronics' = ANY(tags);
SELECT * FROM products WHERE array_length(images, 1) > 0;

-- Update arrays
UPDATE products SET tags = array_append(tags, 'new_tag') WHERE product_id = 1;
UPDATE products SET tags = array_remove(tags, 'old_tag') WHERE product_id = 1;
```

### Enumerated Types

```sql
-- Custom enumerated types
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended', 'banned');
CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled');

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    status user_status DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Alter enum types (PostgreSQL 12+)
ALTER TYPE user_status ADD VALUE 'verified' AFTER 'active';
```

### Geometric and Network Types

```sql
-- Geometric types for spatial data
CREATE TABLE locations (
    location_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    coordinates POINT,  -- (x, y) coordinates
    area POLYGON,       -- Polygon for areas
    route PATH          -- Path for routes
);

-- Network types for IP addresses
CREATE TABLE network_logs (
    log_id SERIAL PRIMARY KEY,
    ip_address INET NOT NULL,
    mac_address MACADDR,
    subnet CIDR,
    logged_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Query network types
SELECT * FROM network_logs
WHERE ip_address << '192.168.1.0/24';  -- IP in subnet

SELECT * FROM network_logs
WHERE ip_address >>= '192.168.1.1';    -- IP is contained by
```

## Table Inheritance

### Basic Table Inheritance

```sql
-- Parent table
CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY,
    make VARCHAR(50) NOT NULL,
    model VARCHAR(50) NOT NULL,
    year INTEGER NOT NULL,
    vin VARCHAR(17) UNIQUE NOT NULL
);

-- Child tables inheriting from parent
CREATE TABLE cars (
    doors INTEGER NOT NULL CHECK (doors BETWEEN 2 AND 5),
    trunk_capacity DECIMAL(5,2)
) INHERITS (vehicles);

CREATE TABLE trucks (
    payload_capacity DECIMAL(8,2) NOT NULL,
    towing_capacity DECIMAL(8,2)
) INHERITS (vehicles);

CREATE TABLE motorcycles (
    engine_cc INTEGER NOT NULL,
    has_sidecar BOOLEAN DEFAULT FALSE
) INHERITS (vehicles);

-- Insert data into child tables
INSERT INTO cars (make, model, year, vin, doors, trunk_capacity)
VALUES ('Toyota', 'Camry', 2023, '1N4AL3AP0FC123456', 4, 15.4);

INSERT INTO trucks (make, model, year, vin, payload_capacity, towing_capacity)
VALUES ('Ford', 'F-150', 2023, '1FTFW1ET0DFC12345', 2000.00, 11000.00);

-- Query with inheritance
SELECT * FROM vehicles;  -- Returns all vehicles from all child tables
SELECT * FROM cars;      -- Returns only cars
```

### Advanced Inheritance Patterns

```sql
-- Partitioned tables using inheritance (PostgreSQL 10+ declarative partitioning is preferred)
CREATE TABLE sales_data (
    sale_id SERIAL,
    sale_date DATE NOT NULL,
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    amount DECIMAL(10,2) NOT NULL
) PARTITION BY RANGE (sale_date);

-- Create partitions
CREATE TABLE sales_2023 PARTITION OF sales_data
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE sales_2024 PARTITION OF sales_data
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Automatic partition creation
CREATE TABLE sales_default PARTITION OF sales_data DEFAULT;
```

## Generated Columns

### Virtual Generated Columns

```sql
-- Generated columns that are computed on-the-fly
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    base_price DECIMAL(10,2) NOT NULL,
    tax_rate DECIMAL(5,4) NOT NULL DEFAULT 0.0825,
    discount_percentage DECIMAL(5,4) DEFAULT 0.0000,

    -- Virtual generated columns
    price_with_tax DECIMAL(10,2) GENERATED ALWAYS AS (base_price * (1 + tax_rate)) STORED,
    discounted_price DECIMAL(10,2) GENERATED ALWAYS AS (base_price * (1 - discount_percentage)) STORED,
    final_price DECIMAL(10,2) GENERATED ALWAYS AS (
        base_price * (1 + tax_rate) * (1 - discount_percentage)
    ) STORED
);

-- Insert data (generated columns are computed automatically)
INSERT INTO products (name, base_price, tax_rate, discount_percentage)
VALUES ('Laptop', 1000.00, 0.0825, 0.10);

-- Query generated columns
SELECT name, base_price, price_with_tax, discounted_price, final_price
FROM products;
```

### Functional Indexes with Generated Columns

```sql
-- Create a generated column for full-text search
CREATE TABLE articles (
    article_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    tags TEXT[],

    -- Generated column for search vector
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', title || ' ' || content || ' ' || array_to_string(tags, ' '))
    ) STORED
);

-- Create GIN index on generated column
CREATE INDEX idx_articles_search ON articles USING GIN (search_vector);

-- Search using generated column
SELECT title, ts_rank(search_vector, query) as rank
FROM articles, to_tsquery('english', 'database & performance') query
WHERE search_vector @@ query
ORDER BY rank DESC;
```

## Domains and Custom Types

### Domain Types

```sql
-- Create domain for email validation
CREATE DOMAIN email_domain AS VARCHAR(255)
    CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Create domain for positive integers
CREATE DOMAIN positive_int AS INTEGER
    CHECK (VALUE > 0);

-- Create domain for percentage values
CREATE DOMAIN percentage AS DECIMAL(5,4)
    CHECK (VALUE >= 0.0000 AND VALUE <= 1.0000);

-- Use domains in table definitions
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email email_domain UNIQUE NOT NULL,
    salary positive_int NOT NULL,
    tax_rate percentage DEFAULT 0.0825
);
```

### Composite Types

```sql
-- Create composite type for addresses
CREATE TYPE address_type AS (
    street_address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA'
);

-- Create composite type for contact information
CREATE TYPE contact_info AS (
    email VARCHAR(255),
    phone VARCHAR(20),
    emergency_contact address_type
);

-- Use composite types in tables
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    billing_address address_type,
    shipping_address address_type,
    contact contact_info
);

-- Insert data with composite types
INSERT INTO customers (name, billing_address, contact) VALUES (
    'John Doe',
    ('123 Main St', 'Anytown', 'CA', '12345', 'USA'),
    ('john@example.com', '555-0123', NULL)
);

-- Query composite type fields
SELECT name,
       (billing_address).city,
       (billing_address).state,
       (contact).email
FROM customers;
```

## Extensions and Advanced Features

### PostgreSQL Extensions

```sql
-- Enable essential extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "hstore";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Use UUID extension
CREATE TABLE sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id INTEGER REFERENCES users(user_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- Use pgcrypto for encryption
CREATE TABLE user_credentials (
    user_id INTEGER PRIMARY KEY REFERENCES users(user_id),
    password_hash VARCHAR(255) NOT NULL,
    salt VARCHAR(255) NOT NULL DEFAULT gen_salt('bf', 8),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Hash password before storage
CREATE OR REPLACE FUNCTION hash_password(password TEXT, salt TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN crypt(password, salt);
END;
$$ LANGUAGE plpgsql;
```

### Advanced Constraints

```sql
-- Exclusion constraints for complex business rules
CREATE TABLE room_bookings (
    booking_id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    guest_name VARCHAR(100) NOT NULL,

    -- Prevent overlapping bookings for the same room
    EXCLUDE (room_id WITH =, TSRANGE(check_in, check_out) WITH &&)
);

-- Deferrable constraints
CREATE TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    balance DECIMAL(12,2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
    account_type VARCHAR(20) NOT NULL
);

CREATE TABLE transfers (
    transfer_id SERIAL PRIMARY KEY,
    from_account_id INTEGER NOT NULL REFERENCES accounts(account_id),
    to_account_id INTEGER NOT NULL REFERENCES accounts(account_id),
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),

    -- Defer constraint checking until transaction end
    CONSTRAINT different_accounts CHECK (from_account_id != to_account_id) DEFERRABLE INITIALLY DEFERRED
);
```

## Performance Considerations

### Table Optimization

```sql
-- Optimize table storage
CREATE TABLE large_table (
    id SERIAL PRIMARY KEY,
    data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
) WITH (fillfactor = 70, autovacuum_enabled = true);

-- Create unlogged table for temporary/session data
CREATE UNLOGGED TABLE user_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER REFERENCES users(user_id),
    data JSONB,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- Create temporary table
CREATE TEMPORARY TABLE temp_results (
    id INTEGER,
    result_data JSONB
) ON COMMIT DROP;
```

### Advanced Indexing Strategies

```sql
-- Partial indexes for specific conditions
CREATE INDEX idx_active_users ON users (email) WHERE status = 'active';

-- Expression indexes
CREATE INDEX idx_users_lower_email ON users (lower(email));
CREATE INDEX idx_products_price_range ON products ((price_with_tax));

-- Covering indexes for query optimization
CREATE INDEX idx_orders_user_date_covering
ON orders (user_id, order_date)
INCLUDE (total_amount, status);

-- BRIN indexes for large tables with sequential data
CREATE INDEX idx_logs_timestamp_brin ON audit_logs USING BRIN (created_at);

-- SP-GiST indexes for complex data types
CREATE INDEX idx_locations_area ON locations USING SPGIST (area);
```

## Enterprise Patterns

### Audit Tables

```sql
-- Create audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, old_values, changed_by, changed_at)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), current_user, now());
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, old_values, new_values, changed_by, changed_at)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), row_to_json(NEW), current_user, now());
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, new_values, changed_by, changed_at)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW), current_user, now());
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create audit table
CREATE TABLE audit_log (
    audit_id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by TEXT DEFAULT current_user,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Apply audit trigger to tables
CREATE TRIGGER users_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
```

### Multi-Tenant Schema Design

```sql
-- Schema-per-tenant approach
CREATE SCHEMA tenant_001;
CREATE SCHEMA tenant_002;

-- Create tenant-specific tables
CREATE TABLE tenant_001.users (
    user_id SERIAL PRIMARY KEY,
    tenant_id INTEGER DEFAULT 1,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL
);

-- Row-level security for tenant isolation
ALTER TABLE tenant_001.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy ON tenant_001.users
    FOR ALL USING (tenant_id = current_setting('app.tenant_id')::INTEGER);

-- Shared tables with tenant context
CREATE TABLE shared_products (
    product_id SERIAL PRIMARY KEY,
    tenant_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,

    -- Partition by tenant for better performance
    PARTITION BY LIST (tenant_id)
);

-- Create partitions for each tenant
CREATE TABLE products_tenant_001 PARTITION OF shared_products
    FOR VALUES IN (1);

CREATE TABLE products_tenant_002 PARTITION OF shared_products
    FOR VALUES IN (2);
```

### Versioned Tables

```sql
-- Create versioned table structure
CREATE TABLE documents (
    document_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_by INTEGER REFERENCES users(user_id),
    is_current BOOLEAN DEFAULT TRUE
);

-- Create trigger for versioning
CREATE OR REPLACE FUNCTION version_document()
RETURNS TRIGGER AS $$
BEGIN
    -- Mark old version as not current
    UPDATE documents
    SET is_current = FALSE
    WHERE document_id = NEW.document_id AND is_current = TRUE;

    -- Set new version as current
    NEW.is_current = TRUE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER documents_versioning_trigger
    BEFORE UPDATE ON documents
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION version_document();
```

This comprehensive DDL schema design guide covers the essential patterns and best practices for PostgreSQL database design. Each section includes practical examples and enterprise-level considerations used by major tech companies.
