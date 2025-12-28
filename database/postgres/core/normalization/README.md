# Database Normalization in PostgreSQL

## Overview

Database normalization is the process of organizing data in a database to reduce redundancy and improve data integrity. This guide covers normalization principles and their practical implementation in PostgreSQL, with real-world examples and enterprise patterns.

## Table of Contents

1. [Normalization Fundamentals](#normalization-fundamentals)
2. [First Normal Form (1NF)](#first-normal-form-1nf)
3. [Second Normal Form (2NF)](#second-normal-form-2nf)
4. [Third Normal Form (3NF)](#third-normal-form-3nf)
5. [Boyce-Codd Normal Form (BCNF)](#boyce-codd-normal-form-bcnf)
6. [Fourth and Fifth Normal Forms](#fourth-and-fifth-normal-forms)
7. [Denormalization Strategies](#denormalization-strategies)
8. [PostgreSQL-Specific Normalization Features](#postgresql-specific-normalization-features)
9. [Practical Examples](#practical-examples)
10. [Enterprise Patterns](#enterprise-patterns)

## Normalization Fundamentals

### Why Normalize?

- **Reduce Data Redundancy**: Eliminate duplicate data storage
- **Improve Data Integrity**: Prevent update anomalies
- **Enhance Query Performance**: Better indexing and faster queries
- **Simplify Maintenance**: Easier schema modifications
- **Support Concurrent Access**: Reduce locking conflicts

### Normalization Trade-offs

- **Read Performance**: Normalized databases may require more joins
- **Write Performance**: Updates affect fewer tables
- **Storage Efficiency**: Less redundant data
- **Complexity**: More tables and relationships to manage

## First Normal Form (1NF)

### Definition
A table is in 1NF if:
- All columns contain atomic (indivisible) values
- No repeating groups or arrays
- Each column contains values of a single type
- Each row is uniquely identifiable

### 1NF Violations and Fixes

```sql
-- VIOLATION: Non-atomic values and repeating groups
CREATE TABLE customers_bad (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    phone_numbers VARCHAR(500),  -- Comma-separated values
    addresses TEXT              -- Multiple addresses in one field
);

-- FIX: Properly normalized to 1NF
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) UNIQUE
);

CREATE TABLE customer_phone_numbers (
    phone_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id) ON DELETE CASCADE,
    phone_type VARCHAR(20) CHECK (phone_type IN ('home', 'work', 'mobile')),
    phone_number VARCHAR(20) NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE
);

CREATE TABLE customer_addresses (
    address_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id) ON DELETE CASCADE,
    address_type VARCHAR(20) CHECK (address_type IN ('home', 'billing', 'shipping')),
    street_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',
    is_primary BOOLEAN DEFAULT FALSE
);

-- Ensure only one primary phone/address per customer
CREATE UNIQUE INDEX idx_customer_primary_phone
ON customer_phone_numbers (customer_id) WHERE is_primary = TRUE;

CREATE UNIQUE INDEX idx_customer_primary_address
ON customer_addresses (customer_id) WHERE is_primary = TRUE;
```

## Second Normal Form (2NF)

### Definition
A table is in 2NF if:
- It is in 1NF
- All non-key attributes are fully functionally dependent on the entire primary key
- No partial dependencies exist

### 2NF Example

```sql
-- VIOLATION: Partial dependency (order_item depends only on product_id)
CREATE TABLE order_items_bad (
    order_id INTEGER,
    product_id INTEGER,
    product_name VARCHAR(255),
    product_price DECIMAL(10,2),
    quantity INTEGER,
    PRIMARY KEY (order_id, product_id)
);

-- FIX: Separate product information
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    base_price DECIMAL(10,2) NOT NULL CHECK (base_price > 0),
    description TEXT,
    category_id INTEGER REFERENCES categories(category_id)
);

CREATE TABLE order_items (
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_percentage DECIMAL(5,4) DEFAULT 0.0000,
    PRIMARY KEY (order_id, product_id)
);

-- Add indexes for performance
CREATE INDEX idx_order_items_order_id ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);
```

## Third Normal Form (3NF)

### Definition
A table is in 3NF if:
- It is in 2NF
- No transitive dependencies exist
- Non-key attributes depend only on the primary key

### 3NF Example

```sql
-- VIOLATION: Transitive dependency (department_name depends on department_id, not on employee_id)
CREATE TABLE employees_bad (
    employee_id SERIAL PRIMARY KEY,
    employee_name VARCHAR(100) NOT NULL,
    department_id INTEGER NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    department_location VARCHAR(100) NOT NULL,
    salary DECIMAL(10,2) NOT NULL
);

-- FIX: Separate department information
CREATE TABLE departments (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    location VARCHAR(100) NOT NULL,
    manager_id INTEGER,  -- Can reference employees(employee_id)
    budget DECIMAL(12,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department_id INTEGER REFERENCES departments(department_id),
    position VARCHAR(100) NOT NULL,
    salary DECIMAL(10,2) NOT NULL CHECK (salary >= 0),
    hire_date DATE NOT NULL,
    manager_id INTEGER REFERENCES employees(employee_id),

    -- Add constraints
    CONSTRAINT chk_salary_positive CHECK (salary > 0),
    CONSTRAINT chk_hire_date_not_future CHECK (hire_date <= CURRENT_DATE)
);

-- Self-referencing foreign key for manager relationship
ALTER TABLE departments
ADD CONSTRAINT fk_department_manager
FOREIGN KEY (manager_id) REFERENCES employees(employee_id);
```

## Boyce-Codd Normal Form (BCNF)

### Definition
A table is in BCNF if:
- It is in 3NF
- Every determinant is a candidate key
- No non-trivial functional dependencies exist where the determinant is not a superkey

### BCNF Example

```sql
-- VIOLATION: Determinant (professor_id) is not a candidate key
CREATE TABLE course_schedule_bad (
    course_id INTEGER,
    professor_id INTEGER,
    semester VARCHAR(20),
    classroom VARCHAR(50),
    time_slot VARCHAR(50),
    PRIMARY KEY (course_id, semester),

    -- Functional dependency: professor_id → classroom, time_slot
    -- But professor_id is not a candidate key
    UNIQUE (professor_id, semester)
);

-- FIX: Separate into BCNF tables
CREATE TABLE courses (
    course_id SERIAL PRIMARY KEY,
    course_name VARCHAR(200) NOT NULL,
    department VARCHAR(100) NOT NULL,
    credits INTEGER NOT NULL CHECK (credits BETWEEN 1 AND 6)
);

CREATE TABLE professors (
    professor_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    office_location VARCHAR(100)
);

CREATE TABLE course_offerings (
    offering_id SERIAL PRIMARY KEY,
    course_id INTEGER REFERENCES courses(course_id),
    professor_id INTEGER REFERENCES professors(professor_id),
    semester VARCHAR(20) NOT NULL,
    year INTEGER NOT NULL,
    enrollment_limit INTEGER DEFAULT 30,

    UNIQUE (course_id, semester, year)
);

CREATE TABLE class_schedule (
    schedule_id SERIAL PRIMARY KEY,
    offering_id INTEGER REFERENCES course_offerings(offering_id),
    classroom VARCHAR(50) NOT NULL,
    time_slot VARCHAR(50) NOT NULL,
    days_of_week VARCHAR(20) NOT NULL,  -- e.g., 'MWF', 'TR'

    UNIQUE (classroom, time_slot, days_of_week)
);

-- Add indexes for performance
CREATE INDEX idx_course_offerings_course_semester ON course_offerings (course_id, semester, year);
CREATE INDEX idx_class_schedule_offering ON class_schedule (offering_id);
```

## Fourth and Fifth Normal Forms

### Fourth Normal Form (4NF)

**Definition**: A table is in 4NF if it is in BCNF and has no multi-valued dependencies.

```sql
-- VIOLATION: Multi-valued dependency
CREATE TABLE student_activities_bad (
    student_id INTEGER,
    activity VARCHAR(100),
    club VARCHAR(100),
    PRIMARY KEY (student_id, activity, club)
);

-- FIX: Separate multi-valued dependencies
CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL
);

CREATE TABLE activities (
    activity_id SERIAL PRIMARY KEY,
    activity_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE clubs (
    club_id SERIAL PRIMARY KEY,
    club_name VARCHAR(100) NOT NULL UNIQUE,
    advisor_id INTEGER REFERENCES professors(professor_id)
);

CREATE TABLE student_activities (
    student_id INTEGER REFERENCES students(student_id),
    activity_id INTEGER REFERENCES activities(activity_id),
    PRIMARY KEY (student_id, activity_id)
);

CREATE TABLE student_clubs (
    student_id INTEGER REFERENCES students(student_id),
    club_id INTEGER REFERENCES clubs(club_id),
    join_date DATE DEFAULT CURRENT_DATE,
    PRIMARY KEY (student_id, club_id)
);
```

### Fifth Normal Form (5NF)

**Definition**: A table is in 5NF (also called PJNF - Projection-Join Normal Form) if it is in 4NF and cannot be decomposed into smaller tables without loss of data.

5NF is rarely violated in practice and is more of a theoretical concern. It deals with cases where information can be reconstructed from smaller projections but not through natural joins.

## Denormalization Strategies

### When to Denormalize

- **Read-heavy workloads** with complex joins
- **Real-time analytics** requiring fast queries
- **Data warehousing** scenarios
- **Caching layers** for performance

### Denormalization Patterns

```sql
-- Example: E-commerce product catalog with denormalized data
CREATE TABLE products_denormalized (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,

    -- Normalized data (would be in separate category table)
    category_name VARCHAR(100) NOT NULL,
    category_description TEXT,
    parent_category_name VARCHAR(100),

    -- Denormalized price history (latest price + history)
    current_price DECIMAL(10,2) NOT NULL,
    original_price DECIMAL(10,2),
    discount_percentage DECIMAL(5,4) DEFAULT 0.0000,

    -- Denormalized inventory data
    total_stock INTEGER DEFAULT 0,
    available_stock INTEGER DEFAULT 0,
    reserved_stock INTEGER DEFAULT 0,

    -- Denormalized review data
    average_rating DECIMAL(3,2),
    review_count INTEGER DEFAULT 0,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Full-text search vector
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', name || ' ' || description || ' ' || category_name)
    ) STORED
);

-- Separate history table for audit trail
CREATE TABLE product_price_history (
    history_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products_denormalized(product_id),
    old_price DECIMAL(10,2),
    new_price DECIMAL(10,2),
    changed_by INTEGER REFERENCES users(user_id),
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_products_category ON products_denormalized (category_name);
CREATE INDEX idx_products_price ON products_denormalized (current_price);
CREATE INDEX idx_products_rating ON products_denormalized (average_rating DESC);
CREATE INDEX idx_products_search ON products_denormalized USING GIN (search_vector);
```

## PostgreSQL-Specific Normalization Features

### Array Types for Controlled Denormalization

```sql
-- Using arrays for multi-valued attributes (controlled denormalization)
CREATE TABLE articles (
    article_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    author_id INTEGER REFERENCES authors(author_id),

    -- Controlled denormalization with arrays
    tags TEXT[] DEFAULT '{}',
    related_article_ids INTEGER[] DEFAULT '{}',

    -- JSON for flexible metadata
    metadata JSONB DEFAULT '{}',

    published_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Query array data
SELECT * FROM articles WHERE 'postgresql' = ANY(tags);
SELECT * FROM articles WHERE array_length(tags, 1) > 3;

-- Update arrays
UPDATE articles SET tags = array_append(tags, 'database') WHERE article_id = 1;
UPDATE articles SET tags = array_remove(tags, 'old_tag') WHERE article_id = 1;
```

### Table Inheritance for Specialization

```sql
-- Using table inheritance for specialization
CREATE TABLE content_items (
    content_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    author_id INTEGER REFERENCES users(user_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'draft'
);

-- Specialized content types
CREATE TABLE blog_posts (
    excerpt TEXT,
    read_time_minutes INTEGER,
    featured_image_url VARCHAR(500)
) INHERITS (content_items);

CREATE TABLE videos (
    video_url VARCHAR(500) NOT NULL,
    duration_seconds INTEGER NOT NULL,
    thumbnail_url VARCHAR(500),
    transcript TEXT
) INHERITS (content_items);

CREATE TABLE podcasts (
    audio_url VARCHAR(500) NOT NULL,
    duration_seconds INTEGER NOT NULL,
    show_notes TEXT,
    guest_speaker VARCHAR(200)
) INHERITS (content_items);

-- Query across all content types
SELECT content_id, title, tableoid::regclass AS content_type
FROM content_items
WHERE status = 'published'
ORDER BY published_at DESC;
```

### Partial Indexes for Conditional Normalization

```sql
-- Use partial indexes to maintain normalization benefits
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,

    -- Denormalized customer info for active orders only
    customer_name VARCHAR(100),
    customer_email VARCHAR(255),

    CONSTRAINT chk_status CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'))
);

-- Trigger to maintain denormalized data
CREATE OR REPLACE FUNCTION maintain_customer_denorm()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('pending', 'confirmed', 'processing') THEN
        -- Populate denormalized data for active orders
        SELECT CONCAT(first_name, ' ', last_name), email
        INTO NEW.customer_name, NEW.customer_email
        FROM customers WHERE customer_id = NEW.customer_id;
    ELSE
        -- Clear denormalized data for completed/cancelled orders
        NEW.customer_name = NULL;
        NEW.customer_email = NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_customer_denorm_trigger
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION maintain_customer_denorm();

-- Partial index for fast queries on active orders
CREATE INDEX idx_active_orders_customer ON orders (customer_id, customer_name)
WHERE status IN ('pending', 'confirmed', 'processing');
```

## Practical Examples

### E-commerce Product Catalog

```sql
-- Normalized product catalog
CREATE TABLE product_categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    parent_category_id INTEGER REFERENCES product_categories(category_id),
    display_order INTEGER DEFAULT 0
);

CREATE TABLE product_brands (
    brand_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    logo_url VARCHAR(500),
    website_url VARCHAR(500)
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    brand_id INTEGER REFERENCES product_brands(brand_id),
    base_price DECIMAL(10,2) NOT NULL CHECK (base_price > 0),
    weight_grams INTEGER,
    dimensions JSONB,  -- {"length": 10, "width": 5, "height": 2}
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_categories_mapping (
    product_id INTEGER REFERENCES products(product_id),
    category_id INTEGER REFERENCES product_categories(category_id),
    is_primary BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (product_id, category_id)
);

CREATE TABLE product_variants (
    variant_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id),
    sku_suffix VARCHAR(20),
    name VARCHAR(255),  -- e.g., "Color: Red, Size: Large"
    price_modifier DECIMAL(8,2) DEFAULT 0.00,
    stock_quantity INTEGER DEFAULT 0 CHECK (stock_quantity >= 0),
    attributes JSONB  -- {"color": "red", "size": "large"}
);

-- Ensure only one primary category per product
CREATE UNIQUE INDEX idx_product_primary_category
ON product_categories_mapping (product_id) WHERE is_primary = TRUE;
```

### User Management System

```sql
-- User management with role-based access control (RBAC)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE roles (
    role_id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT FALSE
);

CREATE TABLE permissions (
    permission_id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    resource_type VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL
);

CREATE TABLE role_permissions (
    role_id INTEGER REFERENCES roles(role_id),
    permission_id INTEGER REFERENCES permissions(permission_id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    granted_by INTEGER REFERENCES users(user_id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id INTEGER REFERENCES users(user_id),
    role_id INTEGER REFERENCES roles(role_id),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_by INTEGER REFERENCES users(user_id),
    expires_at TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (user_id, role_id)
);

-- Check user permissions function
CREATE OR REPLACE FUNCTION user_has_permission(user_id_param INTEGER, permission_name_param VARCHAR)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM user_roles ur
        JOIN role_permissions rp ON ur.role_id = rp.role_id
        JOIN permissions p ON rp.permission_id = p.permission_id
        WHERE ur.user_id = user_id_param
        AND p.name = permission_name_param
        AND (ur.expires_at IS NULL OR ur.expires_at > CURRENT_TIMESTAMP)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Enterprise Patterns

### Temporal Data Management

```sql
-- Temporal tables for tracking data changes over time
CREATE TABLE employees_temporal (
    employee_id INTEGER NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department_id INTEGER,
    salary DECIMAL(10,2),
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_to TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT '9999-12-31 23:59:59+00',

    PRIMARY KEY (employee_id, valid_from),
    CHECK (valid_from < valid_to),

    FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

-- Function to update temporal data
CREATE OR REPLACE FUNCTION update_employee_temporal(
    emp_id INTEGER,
    new_first_name VARCHAR(50) DEFAULT NULL,
    new_last_name VARCHAR(50) DEFAULT NULL,
    new_department_id INTEGER DEFAULT NULL,
    new_salary DECIMAL(10,2) DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    current_record employees_temporal%ROWTYPE;
BEGIN
    -- Get current record
    SELECT * INTO current_record
    FROM employees_temporal
    WHERE employee_id = emp_id AND valid_to = '9999-12-31 23:59:59+00';

    IF FOUND THEN
        -- End current record
        UPDATE employees_temporal
        SET valid_to = CURRENT_TIMESTAMP
        WHERE employee_id = emp_id AND valid_to = '9999-12-31 23:59:59+00';

        -- Insert new record with updated data
        INSERT INTO employees_temporal (
            employee_id, first_name, last_name, department_id, salary,
            valid_from, valid_to
        ) VALUES (
            emp_id,
            COALESCE(new_first_name, current_record.first_name),
            COALESCE(new_last_name, current_record.last_name),
            COALESCE(new_department_id, current_record.department_id),
            COALESCE(new_salary, current_record.salary),
            CURRENT_TIMESTAMP,
            '9999-12-31 23:59:59+00'
        );
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### Slowly Changing Dimensions (SCD)

```sql
-- SCD Type 2 implementation for dimensional modeling
CREATE TABLE customers_scd (
    customer_id INTEGER NOT NULL,
    customer_key SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    address JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_to TIMESTAMP WITH TIME ZONE DEFAULT '9999-12-31 23:59:59+00',

    CHECK (valid_from < valid_to)
);

-- Index for current records
CREATE INDEX idx_customers_scd_current
ON customers_scd (customer_id)
WHERE valid_to = '9999-12-31 23:59:59+00';

-- Index for historical queries
CREATE INDEX idx_customers_scd_history
ON customers_scd (customer_id, valid_from, valid_to);

-- Function to handle SCD Type 2 updates
CREATE OR REPLACE FUNCTION update_customer_scd(
    cust_id INTEGER,
    new_first_name VARCHAR(50) DEFAULT NULL,
    new_last_name VARCHAR(50) DEFAULT NULL,
    new_email VARCHAR(255) DEFAULT NULL,
    new_phone VARCHAR(20) DEFAULT NULL,
    new_address JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    current_record customers_scd%ROWTYPE;
    new_customer_key INTEGER;
BEGIN
    -- Get current record
    SELECT * INTO current_record
    FROM customers_scd
    WHERE customer_id = cust_id AND valid_to = '9999-12-31 23:59:59+00';

    IF FOUND THEN
        -- Check if anything changed
        IF (new_first_name IS NULL OR new_first_name = current_record.first_name) AND
           (new_last_name IS NULL OR new_last_name = current_record.last_name) AND
           (new_email IS NULL OR new_email = current_record.email) AND
           (new_phone IS NULL OR new_phone = current_record.phone) AND
           (new_address IS NULL OR new_address = current_record.address) THEN
            RETURN current_record.customer_key;
        END IF;

        -- Expire current record
        UPDATE customers_scd
        SET valid_to = CURRENT_TIMESTAMP
        WHERE customer_key = current_record.customer_key;

        -- Insert new record
        INSERT INTO customers_scd (
            customer_id, first_name, last_name, email, phone, address,
            valid_from, valid_to
        ) VALUES (
            cust_id,
            COALESCE(new_first_name, current_record.first_name),
            COALESCE(new_last_name, current_record.last_name),
            COALESCE(new_email, current_record.email),
            COALESCE(new_phone, current_record.phone),
            COALESCE(new_address, current_record.address),
            CURRENT_TIMESTAMP,
            '9999-12-31 23:59:59+00'
        ) RETURNING customer_key INTO new_customer_key;

        RETURN new_customer_key;
    ELSE
        -- Insert new customer
        INSERT INTO customers_scd (
            customer_id, first_name, last_name, email, phone, address,
            valid_from, valid_to
        ) VALUES (
            cust_id,
            COALESCE(new_first_name, ''),
            COALESCE(new_last_name, ''),
            COALESCE(new_email, ''),
            new_phone,
            new_address,
            CURRENT_TIMESTAMP,
            '9999-12-31 23:59:59+00'
        ) RETURNING customer_key INTO new_customer_key;

        RETURN new_customer_key;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

This comprehensive guide covers database normalization principles and their practical implementation in PostgreSQL. The examples demonstrate how to apply normalization rules while leveraging PostgreSQL's advanced features for optimal database design.
