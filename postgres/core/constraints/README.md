# PostgreSQL Constraints

## Overview

Constraints in PostgreSQL are rules enforced by the database engine to maintain data integrity. They prevent invalid data from being inserted or updated, ensuring the consistency and reliability of your database.

## Table of Contents

1. [Primary Key Constraints](#primary-key-constraints)
2. [Foreign Key Constraints](#foreign-key-constraints)
3. [Unique Constraints](#unique-constraints)
4. [Check Constraints](#check-constraints)
5. [Not-Null Constraints](#not-null-constraints)
6. [Exclusion Constraints](#exclusion-constraints)
7. [Deferrable Constraints](#deferrable-constraints)
8. [Constraint Management](#constraint-management)
9. [Enterprise Patterns](#enterprise-patterns)

## Primary Key Constraints

### Basic Primary Keys

```sql
-- Single column primary key
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL
);

-- Composite primary key
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    PRIMARY KEY (order_id, product_id)
);

-- Named primary key constraint
CREATE TABLE categories (
    category_id SERIAL,
    name VARCHAR(100) NOT NULL,
    CONSTRAINT pk_categories PRIMARY KEY (category_id)
);
```

### Primary Key Best Practices

```sql
-- Use surrogate keys for complex natural keys
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    category_id INTEGER REFERENCES categories(category_id)
);

-- Composite primary keys with meaningful relationships
CREATE TABLE user_permissions (
    user_id INTEGER REFERENCES users(user_id),
    permission_id INTEGER REFERENCES permissions(permission_id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, permission_id)
);

-- Primary key with included columns (PostgreSQL 11+)
-- Note: This is more relevant for unique constraints
```

## Foreign Key Constraints

### Basic Foreign Keys

```sql
-- Simple foreign key
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Named foreign key with actions
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    category_id INTEGER,
    name VARCHAR(255) NOT NULL,
    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id)
        REFERENCES categories(category_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);
```

### Foreign Key Actions

```sql
-- CASCADE: When parent is deleted/updated, child follows
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL
);

-- SET NULL: Set foreign key to NULL when parent is deleted
CREATE TABLE user_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    session_data JSONB,
    expires_at TIMESTAMP WITH TIME ZONE
);

-- RESTRICT: Prevent deletion of parent if children exist
CREATE TABLE departments (
    department_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    manager_id INTEGER REFERENCES employees(employee_id) ON DELETE RESTRICT
);

-- NO ACTION: Check constraint at end of transaction
CREATE TABLE project_assignments (
    assignment_id SERIAL PRIMARY KEY,
    employee_id INTEGER REFERENCES employees(employee_id) ON DELETE NO ACTION,
    project_id INTEGER REFERENCES projects(project_id) ON DELETE NO ACTION,
    start_date DATE NOT NULL,
    end_date DATE
);
```

### Self-Referencing Foreign Keys

```sql
-- Employee hierarchy with self-referencing foreign key
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    manager_id INTEGER REFERENCES employees(employee_id),
    department_id INTEGER REFERENCES departments(department_id)
);

-- Category tree structure
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    parent_category_id INTEGER REFERENCES categories(category_id),
    level INTEGER GENERATED ALWAYS AS (
        CASE
            WHEN parent_category_id IS NULL THEN 1
            ELSE (SELECT level + 1 FROM categories WHERE category_id = parent_category_id)
        END
    ) STORED
);
```

### Multi-Column Foreign Keys

```sql
-- Multi-column foreign key
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    supplier_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (product_id, supplier_id)
        REFERENCES product_suppliers(product_id, supplier_id)
);
```

## Unique Constraints

### Single Column Unique

```sql
-- Basic unique constraint
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL
);

-- Named unique constraint
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    CONSTRAINT uk_products_sku UNIQUE (sku)
);
```

### Multi-Column Unique

```sql
-- Composite unique constraint
CREATE TABLE user_permissions (
    user_id INTEGER REFERENCES users(user_id),
    permission_id INTEGER REFERENCES permissions(permission_id),
    scope VARCHAR(50) DEFAULT 'global', -- 'global', 'department', 'project'
    UNIQUE (user_id, permission_id, scope)
);

-- Partial unique constraint with WHERE clause
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    department_id INTEGER REFERENCES departments(department_id),
    position VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE (department_id, position) WHERE is_active = TRUE
);
```

### Unique Constraints with Indexes

```sql
-- Unique constraint with included columns (PostgreSQL 11+)
-- This creates an index that includes additional columns for covering queries
CREATE UNIQUE INDEX idx_users_email_active
ON users (email)
WHERE is_active = TRUE;

-- Unique index on expressions
CREATE UNIQUE INDEX idx_users_lower_username
ON users (lower(username));

-- Case-insensitive unique constraint
CREATE UNIQUE INDEX idx_products_case_insensitive_name
ON products (lower(name));
```

## Check Constraints

### Basic Check Constraints

```sql
-- Simple value range check
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL CHECK (price > 0),
    stock_quantity INTEGER CHECK (stock_quantity >= 0),
    discount_percentage DECIMAL(5,2) CHECK (discount_percentage BETWEEN 0 AND 100)
);

-- String format validation
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL
        CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    phone VARCHAR(20)
        CHECK (phone IS NULL OR phone ~* '^\+?[0-9\s\-\(\)]+$'),
    age INTEGER CHECK (age >= 13 AND age <= 120)
);
```

### Complex Check Constraints

```sql
-- Business logic validation
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date DATE NOT NULL,
    delivery_date DATE,
    status VARCHAR(20) DEFAULT 'pending'
        CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')),
    CHECK (delivery_date IS NULL OR delivery_date >= order_date),
    CHECK (
        (status = 'delivered' AND delivery_date IS NOT NULL) OR
        (status != 'delivered' AND delivery_date IS NULL)
    )
);

-- Cross-column validation
CREATE TABLE salary_history (
    employee_id INTEGER REFERENCES employees(employee_id),
    effective_date DATE NOT NULL,
    salary DECIMAL(12,2) NOT NULL CHECK (salary > 0),
    previous_salary DECIMAL(12,2),
    percentage_change DECIMAL(5,2),
    CHECK (
        (previous_salary IS NULL AND percentage_change IS NULL) OR
        (previous_salary IS NOT NULL AND
         percentage_change = ROUND(((salary - previous_salary) / previous_salary) * 100, 2))
    )
);
```

### JSONB Check Constraints

```sql
-- JSONB structure validation
CREATE TABLE user_profiles (
    user_id INTEGER PRIMARY KEY REFERENCES users(user_id),
    profile_data JSONB NOT NULL,
    -- Ensure required fields exist
    CHECK (profile_data ? 'first_name'),
    CHECK (profile_data ? 'last_name'),
    -- Validate email format in JSONB
    CHECK (
        profile_data->>'email' IS NULL OR
        profile_data->>'email' ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    ),
    -- Validate age range
    CHECK (
        (profile_data->>'age')::INTEGER IS NULL OR
        (profile_data->>'age')::INTEGER BETWEEN 0 AND 150
    )
);
```

## Not-Null Constraints

### Basic Not-Null

```sql
-- Explicit NOT NULL constraints
CREATE TABLE required_fields (
    id SERIAL PRIMARY KEY,
    required_text VARCHAR(100) NOT NULL,
    required_number INTEGER NOT NULL,
    required_date DATE NOT NULL,
    optional_field VARCHAR(100)  -- Defaults to nullable
);

-- NOT NULL with default values
CREATE TABLE defaults_example (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'active' NOT NULL
);
```

### Not-Null Best Practices

```sql
-- Use NOT NULL for required business data
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),  -- Optional
    date_of_birth DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- NOT NULL for foreign keys (unless truly optional relationship)
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    shipping_address_id INTEGER NOT NULL REFERENCES addresses(address_id)
);
```

## Exclusion Constraints

### Basic Exclusion Constraints

```sql
-- Prevent overlapping date ranges
CREATE TABLE room_reservations (
    reservation_id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL,
    guest_name VARCHAR(100) NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    EXCLUDE (room_id WITH =, TSRANGE(check_in, check_out) WITH &&)
);

-- Prevent double-booking with GIST index
CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    doctor_id INTEGER NOT NULL,
    patient_id INTEGER NOT NULL,
    appointment_time TIMESTAMP WITH TIME ZONE NOT NULL,
    duration_minutes INTEGER DEFAULT 30,
    EXCLUDE (
        doctor_id WITH =,
        TSRANGE(appointment_time, appointment_time + (duration_minutes || ' minutes')::INTERVAL) WITH &&
    )
);
```

### Advanced Exclusion Examples

```sql
-- IP address range exclusion
CREATE TABLE ip_allocations (
    allocation_id SERIAL PRIMARY KEY,
    network_name VARCHAR(100) NOT NULL,
    ip_range TSRANGE NOT NULL,
    allocated_by INTEGER REFERENCES users(user_id),
    EXCLUDE (ip_range WITH &&)
);

-- Geographic exclusion (requires PostGIS)
-- CREATE EXTENSION postgis;
-- CREATE TABLE service_areas (
--     area_id SERIAL PRIMARY KEY,
--     provider_id INTEGER REFERENCES service_providers(provider_id),
--     service_area GEOGRAPHY(POLYGON, 4326),
--     EXCLUDE (provider_id WITH <>, service_area WITH &&)
-- );
```

## Deferrable Constraints

### Deferred Foreign Keys

```sql
-- Defer constraint checking until transaction end
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER,
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER,
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        DEFERRABLE INITIALLY DEFERRED
);

-- Usage: Insert order and items in any order within transaction
BEGIN;
INSERT INTO order_items (order_id, product_id, quantity) VALUES (1, 101, 2);
INSERT INTO orders (order_id, customer_id) VALUES (1, 123);
COMMIT;  -- Constraints checked here
```

### Deferred Unique Constraints

```sql
-- Deferrable unique constraint
CREATE TABLE user_permissions (
    user_id INTEGER REFERENCES users(user_id),
    permission_id INTEGER REFERENCES permissions(permission_id),
    is_active BOOLEAN DEFAULT TRUE,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, permission_id) DEFERRABLE INITIALLY DEFERRED
);

-- Allow temporary duplicates within transaction
BEGIN;
UPDATE user_permissions SET is_active = FALSE WHERE user_id = 1 AND permission_id = 5;
INSERT INTO user_permissions (user_id, permission_id, is_active) VALUES (1, 5, TRUE);
COMMIT;  -- Unique constraint checked here
```

## Constraint Management

### Adding Constraints to Existing Tables

```sql
-- Add primary key to existing table
ALTER TABLE legacy_table ADD PRIMARY KEY (id);

-- Add foreign key constraint
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

-- Add check constraint
ALTER TABLE products ADD CONSTRAINT chk_positive_price
    CHECK (price > 0);

-- Add unique constraint
ALTER TABLE users ADD CONSTRAINT uk_users_email UNIQUE (email);

-- Add not null constraint
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
```

### Dropping Constraints

```sql
-- Drop named constraint
ALTER TABLE users DROP CONSTRAINT uk_users_email;

-- Drop primary key
ALTER TABLE users DROP CONSTRAINT users_pkey;

-- Drop foreign key
ALTER TABLE orders DROP CONSTRAINT fk_orders_customer;

-- Drop check constraint
ALTER TABLE products DROP CONSTRAINT chk_positive_price;

-- Remove not null constraint
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
```

### Constraint Validation

```sql
-- Validate existing data before adding constraint
ALTER TABLE products ADD CONSTRAINT chk_positive_price CHECK (price > 0) NOT VALID;
ALTER TABLE products VALIDATE CONSTRAINT chk_positive_price;

-- Check constraint violations
SELECT * FROM products WHERE NOT (price > 0);

-- Add constraint only if data passes validation
ALTER TABLE products ADD CONSTRAINT chk_positive_price CHECK (price > 0);
```

### Performance Considerations

```sql
-- Constraints can impact performance
-- Primary keys and unique constraints create indexes automatically

-- Check constraint performance
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    total DECIMAL(10,2) NOT NULL,
    -- Fast check constraint (no function calls)
    CONSTRAINT chk_total_positive CHECK (total > 0),
    -- Slower check constraint (function call)
    CONSTRAINT chk_total_reasonable CHECK (total BETWEEN 0.01 AND 1000000.00)
);

-- Foreign key indexing for performance
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
-- (Foreign keys don't auto-create indexes like primary keys do)

-- Constraint exclusion for partitioned tables
CREATE TABLE sales (
    sale_id SERIAL,
    product_id INTEGER NOT NULL,
    sale_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (sale_id, sale_date)
) PARTITION BY RANGE (sale_date);

-- Constraint exclusion allows efficient partition pruning
SET constraint_exclusion = on;
SELECT * FROM sales WHERE sale_date = '2024-01-15'; -- Only scans relevant partition
```

## Enterprise Patterns

### Audit Constraints

```sql
-- Constraints for audit table integrity
CREATE TABLE audit_log (
    audit_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(user_id),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,

    -- Ensure either old or new values exist
    CONSTRAINT chk_audit_values CHECK (
        (operation = 'INSERT' AND old_values IS NULL AND new_values IS NOT NULL) OR
        (operation = 'UPDATE' AND old_values IS NOT NULL AND new_values IS NOT NULL) OR
        (operation = 'DELETE' AND old_values IS NOT NULL AND new_values IS NULL)
    ),

    -- Prevent future timestamps
    CONSTRAINT chk_audit_timestamp CHECK (changed_at <= CURRENT_TIMESTAMP + INTERVAL '1 minute')
) PARTITION BY RANGE (changed_at);
```

### Business Rule Constraints

```sql
-- Complex business rule constraints
CREATE TABLE insurance_policies (
    policy_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
    policy_type VARCHAR(50) NOT NULL,
    coverage_amount DECIMAL(12,2) NOT NULL CHECK (coverage_amount > 0),
    premium DECIMAL(10,2) NOT NULL CHECK (premium > 0),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Business rule constraints
    CHECK (end_date > start_date),
    CHECK (coverage_amount >= 10000 AND coverage_amount <= 10000000),
    CHECK (premium <= coverage_amount * 0.01), -- Premium max 1% of coverage

    -- Type-specific validation
    CHECK (
        (policy_type = 'auto' AND coverage_amount BETWEEN 10000 AND 1000000) OR
        (policy_type = 'home' AND coverage_amount BETWEEN 50000 AND 5000000) OR
        (policy_type = 'life' AND coverage_amount BETWEEN 50000 AND 2000000)
    )
);

-- Multi-table constraints using triggers
CREATE OR REPLACE FUNCTION check_insurance_limits()
RETURNS TRIGGER AS $$
DECLARE
    total_coverage DECIMAL(12,2);
BEGIN
    -- Check total coverage per customer doesn't exceed limit
    SELECT COALESCE(SUM(coverage_amount), 0)
    INTO total_coverage
    FROM insurance_policies
    WHERE customer_id = NEW.customer_id
      AND policy_type = NEW.policy_type
      AND end_date > CURRENT_DATE;

    IF total_coverage + NEW.coverage_amount > 5000000 THEN
        RAISE EXCEPTION 'Total coverage limit exceeded for customer and policy type';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_insurance_limits_trigger
    BEFORE INSERT OR UPDATE ON insurance_policies
    FOR EACH ROW EXECUTE FUNCTION check_insurance_limits();
```

### Data Quality Constraints

```sql
-- Comprehensive data quality constraints
CREATE TABLE customer_data_quality (
    customer_id INTEGER PRIMARY KEY REFERENCES customers(customer_id),

    -- Contact information quality
    email_quality_score INTEGER CHECK (email_quality_score BETWEEN 0 AND 100),
    phone_quality_score INTEGER CHECK (phone_quality_score BETWEEN 0 AND 100),

    -- Address verification
    address_verified BOOLEAN DEFAULT FALSE,
    address_verification_date TIMESTAMP WITH TIME ZONE,

    -- Identity verification
    identity_verified BOOLEAN DEFAULT FALSE,
    identity_verification_date TIMESTAMP WITH TIME ZONE,
    ssn_last_four CHAR(4),

    -- Risk scoring
    credit_score INTEGER CHECK (credit_score IS NULL OR credit_score BETWEEN 300 AND 850),
    fraud_score DECIMAL(5,2) CHECK (fraud_score BETWEEN 0 AND 1),

    -- Data completeness score
    completeness_score DECIMAL(5,2) GENERATED ALWAYS AS (
        (
            CASE WHEN email_quality_score >= 80 THEN 1 ELSE 0 END +
            CASE WHEN phone_quality_score >= 80 THEN 1 ELSE 0 END +
            CASE WHEN address_verified THEN 1 ELSE 0 END +
            CASE WHEN identity_verified THEN 1 ELSE 0 END +
            CASE WHEN credit_score IS NOT NULL THEN 1 ELSE 0 END
        ) / 5.0
    ) STORED,

    -- Validation constraints
    CHECK (
        (identity_verified = TRUE AND ssn_last_four IS NOT NULL) OR
        (identity_verified = FALSE)
    ),
    CHECK (
        (address_verified = TRUE AND address_verification_date IS NOT NULL) OR
        (address_verified = FALSE)
    )
);

-- Automated data quality scoring
CREATE OR REPLACE FUNCTION update_data_quality_score(customer_id_param INTEGER)
RETURNS VOID AS $$
DECLARE
    email_score INTEGER := 0;
    phone_score INTEGER := 0;
    customer_record RECORD;
BEGIN
    -- Get customer data
    SELECT * INTO customer_record FROM customers WHERE customer_id = customer_id_param;

    -- Email quality scoring
    IF customer_record.email IS NOT NULL THEN
        email_score := CASE
            WHEN customer_record.email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN 100
            WHEN customer_record.email ~* '@.*\.' THEN 80
            ELSE 50
        END;
    END IF;

    -- Phone quality scoring
    IF customer_record.phone IS NOT NULL THEN
        phone_score := CASE
            WHEN customer_record.phone ~* '^\+?[0-9\s\-\(\)]{10,}$' THEN 100
            WHEN customer_record.phone ~* '^[0-9\-\(\)\s]{7,}$' THEN 80
            ELSE 50
        END;
    END IF;

    -- Update quality scores
    INSERT INTO customer_data_quality (
        customer_id, email_quality_score, phone_quality_score
    ) VALUES (
        customer_id_param, email_score, phone_score
    ) ON CONFLICT (customer_id) DO UPDATE SET
        email_quality_score = EXCLUDED.email_quality_score,
        phone_quality_score = EXCLUDED.phone_quality_score;
END;
$$ LANGUAGE plpgsql;
```

### Constraint Naming Conventions

```sql
-- Consistent naming for maintainability
-- pk_ = Primary Key
-- fk_ = Foreign Key
-- uk_ = Unique Key
-- ck_ = Check Constraint
-- nn_ = Not Null (implied by column definition)
-- ex_ = Exclusion Constraint

CREATE TABLE enterprise_example (
    id SERIAL,
    parent_id INTEGER,
    code VARCHAR(20) NOT NULL,
    amount DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'active',

    CONSTRAINT pk_enterprise_example PRIMARY KEY (id),
    CONSTRAINT fk_enterprise_example_parent FOREIGN KEY (parent_id)
        REFERENCES enterprise_example(id),
    CONSTRAINT uk_enterprise_example_code UNIQUE (code),
    CONSTRAINT ck_enterprise_example_amount_positive CHECK (amount > 0),
    CONSTRAINT ck_enterprise_example_status_valid CHECK (status IN ('active', 'inactive', 'pending')),
    CONSTRAINT ex_enterprise_example_no_overlap EXCLUDE (parent_id WITH =, TSRANGE(created_at, end_date) WITH &&)
        WHERE parent_id IS NOT NULL
);
```

This comprehensive guide covers all major constraint types in PostgreSQL, their proper usage, performance implications, and enterprise patterns for maintaining data integrity at scale.
